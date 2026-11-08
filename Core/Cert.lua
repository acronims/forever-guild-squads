-- Guild Squads (MIT) - Core/Cert.lua
-- Pure Lua (no WoW API). v1.2 annex G of docs/SPEC-v1.2-p2p.md (GO of BRO 8-nov 03:15, option 1 on 04:13):
-- cross certification of keys, replacing the 1.1 "weak key with a quorum of 2 relayers".
--   * every client signs ONE certificate { i = issuer, n, e = sorted list of hash12(name|key) } of the keys it heard
--     IN PERSON in the last 30 days, re-signed only when the list changes (n grows, n = max(n + 1, server time)).
--   * a certificate counts for us only if its issuer is in person for us (Trust.inPerson) and it verifies with that
--     key: no second hop (a certified issuer does not certify).
--   * the key K of a stranger Z (a candidate relayed with his records, Trust.candidates) is "cert" when >= 2 such
--     certificates list hash12(Z|K) and none lists another candidate for Z; otherwise "disputed" (no key is used,
--     nothing new is applied, diag). Z in person always wins (Trust.hearOwner).
--   * limit (docs/DESIGN-certificados.md): 2 alts known in person can certify a fake key for someone nobody honest
--     certifies to us; one honest certificate against it makes it disputed.
--   * verifications are queued (Cert.step: 1 verify per call, the caller does 1 per frame outside combat).
local _, ns = ...
ns = ns or {}

local C = {}
ns.Cert = C
local E, T = ns.Ed25519, ns.Trust

C.TAG = "GSQ-CRT1"
C.HASH_LEN = 12
C.MAX_ENTRIES = 600
C.MAX_QUEUE = 200
C.WINDOW = 30 * 86400          -- keys heard in person in the last 30 days
C.NEED = 2                     -- certificates of in-person issuers

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64(s)
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local d = { math.floor(n / 262144) % 64, math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64 }
    local k = b and (c and 4 or 3) or 2
    for j = 1, k do out[#out + 1] = B64:sub(d[j] + 1, d[j] + 1) end
  end
  return table.concat(out)
end
local function num(n) if type(n) == "number" and n == math.floor(n) and n > -1e15 and n < 1e15 then return string.format("%d", n) end return tostring(n) end
local function hex(s) return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local function unhex(h)
  if type(h) ~= "string" or #h % 2 ~= 0 or h:find("[^0-9a-fA-F]") then return nil end
  return (h:gsub("..", function(x) return string.char(tonumber(x, 16)) end))
end

-- 12 bytes of sha512 in base64 (16 chars). fix/perf (runtime review A1 / M1): a pure function, memoized by its own
-- input (name|pk, so the memo is exact); evalAll and C.own call it for every candidate / every key heard in person,
-- and a sha512 costs ~2-3 ms in the client. Flushed whole past HASH_MEMO entries (~60 B each).
C.HASH_MEMO = 2000
local memo, memoN = {}, 0
function C.hash(name, pk)
  local key = tostring(name) .. "|" .. pk
  local h = memo[key]
  if h then return h end
  h = b64(E.sha512(C.TAG .. "|" .. key):sub(1, C.HASH_LEN))
  if memoN >= C.HASH_MEMO then memo, memoN = {}, 0 end
  memo[key], memoN = h, memoN + 1
  return h
end

function C.statement(c) return C.TAG .. "\n" .. tostring(c.i) .. "\n" .. num(c.n) .. "\n" .. table.concat(c.e, "\n") end

-- heard = { [name] = raw pk }
function C.build(issuer, n, heard, sk, pk)
  local e = {}
  for name, k in pairs(heard) do e[#e + 1] = C.hash(name, k) end
  table.sort(e)
  local c = { i = issuer, n = n, e = e }
  c.s = hex(E.sign(sk, pk, C.statement(c)))
  return c
end

function C.validShape(c)
  if type(c) ~= "table" or type(c.i) ~= "string" or type(c.n) ~= "number" or c.n < 1 or c.n ~= math.floor(c.n)
    or type(c.e) ~= "table" or type(c.s) ~= "string" or #c.s ~= 128 or not unhex(c.s) then return false end
  if #c.e > C.MAX_ENTRIES then return false end
  local prev
  for i = 1, #c.e do
    local h = c.e[i]
    if type(h) ~= "string" or #h ~= 16 or h:find("[^A-Za-z0-9+/]") or (prev and h <= prev) then return false end
    prev = h
  end
  for k in pairs(c.e) do if type(k) ~= "number" or k < 1 or k > #c.e then return false end end
  return true
end

-- state: db = { crt = { [issuer] = { n, pk (hex), e, s, set } }, cnt } (set is rebuilt, not saved)
function C.st(db)
  db.crt = type(db.crt) == "table" and db.crt or {}
  db.cnt = type(db.cnt) == "table" and db.cnt or { verified = 0, rejected = 0 }
  return db
end
local queue, queued = {}, {}
function C.resetQueue() queue, queued = {}, {} end
function C.pending() return #queue end

local function setOf(cur)
  if not cur.set then cur.set = {}; for _, h in ipairs(cur.e) do cur.set[h] = true end end
  return cur.set
end

function C.offer(db, c)
  C.st(db)
  if not C.validShape(c) then db.cnt.rejected = db.cnt.rejected + 1; return "bad" end
  local cur = db.crt[c.i]
  if cur and cur.n >= c.n then return "old" end
  local tag = c.i .. "|" .. num(c.n) .. "|" .. c.s
  if queued[tag] then return "queued" end
  if #queue >= C.MAX_QUEUE then return "full" end
  queued[tag] = true
  queue[#queue + 1] = { c = c, tag = tag }
  return "queued"
end

-- one verification; returns the issuer whose certificate was accepted, or nil
function C.step(db, tdb, now)
  C.st(db)
  local q = table.remove(queue, 1)
  if not q then return nil end
  queued[q.tag] = nil
  local c = q.c
  local cur = db.crt[c.i]
  if cur and cur.n >= c.n then return nil end
  if not T.inPerson(tdb, c.i) then return nil end   -- not an issuer for us (yet): the next copy gets another try
  local pk = T.keyOf(tdb, c.i)
  if not E.verify(pk, C.statement(c), unhex(c.s)) then db.cnt.rejected = db.cnt.rejected + 1; return nil end
  local e = {}
  for i = 1, #c.e do e[i] = c.e[i] end
  db.crt[c.i] = { n = c.n, pk = hex(pk), e = e, s = c.s }
  db.cnt.verified = db.cnt.verified + 1
  return c.i
end

function C.holds(db, issuer) return db.crt ~= nil and db.crt[issuer] ~= nil end
function C.certOf(db, issuer)
  local cur = db.crt and db.crt[issuer]
  if not cur then return nil end
  return { i = issuer, n = cur.n, e = cur.e, s = cur.s }
end

-- the certificates of issuers in person for us: { {issuer, set}, ... }. fix/perf A1: built once per evalAll (it was
-- two unhex + a keyOf per issuer and per candidate name); eval / evalAll do not change who is in person
local function issuers(db, tdb)
  local out = {}
  for issuer, cur in pairs(db.crt) do
    if T.inPerson(tdb, issuer, unhex(cur.pk)) then out[#out + 1] = { issuer, setOf(cur) } end
  end
  return out
end
-- how many in-person issuers (other than `name`) list hash12(name|pk)
local function support(db, tdb, name, pk, iss)
  local h, n = C.hash(name, pk), 0
  for _, it in ipairs(iss or issuers(db, tdb)) do
    if it[1] ~= name and it[2][h] then n = n + 1 end
  end
  return n
end

-- decide the key of `name` from the certificates: "strong" (in person, nothing to do) | "cert" | "disputed" | nil.
-- onDrop(name, oldPk) when a key in use (not in person) is dropped: the caller forgets what it signed.
function C.eval(db, tdb, name, now, onDrop, iss)
  C.st(db)
  T.st(tdb)
  if T.inPerson(tdb, name) then return "strong" end
  local best, bestN, others = nil, 0, 0
  local cands = T.candidates(tdb, name)
  if #cands > 1 and not iss then iss = issuers(db, tdb) end
  for _, pk in ipairs(cands) do
    local n = support(db, tdb, name, pk, iss)
    if n >= C.NEED and n > bestN then
      if best then others = others + 1 end
      best, bestN = pk, n
    elseif n > 0 then
      others = others + 1
    end
  end
  if tdb.contested[name] or (best and others > 0) then
    local old = T.dispute(tdb, name, now)
    if old and onDrop then onDrop(name, old) end
    return "disputed"
  end
  if best then
    local old = T.certify(tdb, name, best, now)
    if old and onDrop then onDrop(name, old) end
    return "cert"
  end
  local _, s = T.keyOf(tdb, name)
  return s
end

-- every name with a candidate key (after a certificate is accepted); onCert(name) for the certified ones
function C.evalAll(db, tdb, now, onDrop, onCert)
  T.st(tdb)
  local names = {}
  for name in pairs(tdb.pend) do names[name] = true end
  for name, k in pairs(tdb.keys) do if k.s ~= "strong" then names[name] = true end end
  local iss = issuers(db, tdb)
  for name in pairs(names) do
    if C.eval(db, tdb, name, now, onDrop, iss) == "cert" and onCert then onCert(name) end
  end
end

-- our own certificate. own = per-character holder { c = last certificate, key = joined entries, pk = signer (hex) }
function C.own(own, tdb, me, sk, pk, now)
  T.st(tdb)
  local heard = {}
  for name, k in pairs(tdb.keys) do
    if name ~= me and k.s == "strong" and not tdb.contested[name] and (k.seen or k.t or 0) >= now - C.WINDOW then
      heard[name] = unhex(k.pk)
    end
  end
  local e = {}
  for name, k in pairs(heard) do e[#e + 1] = C.hash(name, k) end
  table.sort(e)
  local joined = table.concat(e, ",")
  if own.c and own.key == joined and own.pk == hex(pk) then return own.c end
  local n = math.max((own.c and own.c.n or 0) + 1, now)
  own.c = C.build(me, n, heard, sk, pk)
  own.key, own.pk = joined, hex(pk)
  return own.c
end

function C.counts(db, tdb)
  C.st(db)
  local held, disputed, cert = 0, 0, 0
  for _ in pairs(db.crt) do held = held + 1 end
  if tdb then
    T.st(tdb)
    for _ in pairs(tdb.contested) do disputed = disputed + 1 end
    for name, k in pairs(tdb.keys) do if k.s == "cert" and not tdb.contested[name] then cert = cert + 1 end end
  end
  return { held = held, disputed = disputed, cert = cert, pending = #queue, verified = db.cnt.verified, rejected = db.cnt.rejected }
end

return C
