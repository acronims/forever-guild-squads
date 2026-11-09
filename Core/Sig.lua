-- Guild Squads (MIT) - Core/Sig.lua
-- Pure Lua (no WoW API). v1.2 annex F of docs/SPEC-v1.2-p2p.md (with BRO's change of 8-nov 01:02, no dev key):
-- signed MANIFESTS, one per author.
--   * the author signs { a = name, n = manifest seq, h = { [kind:id] = hash of the record } } and re-signs it (n + 1)
--     when one of his records changes. A record hash = first 16 bytes of sha512 over its signed fields (k, id, ts, sq,
--     a, d), so a relayer cannot change a byte of a record without the author's key.
--   * the receiver verifies a manifest once (1 ed25519 verify), then checks every record of that author against the
--     hashes: Sig.status(rec) -> "strong" | "weak" | nil (nil = no valid signature: an authorial record is not applied).
--   * replay: a manifest with n <= the one we hold is ignored (an old manifest cannot bring back an old record).
--   * verifications are queued (Sig.step does at most 1 per call: one per frame, paused in combat / encounters by the
--     caller) and cached by (author, n, signature).
--   * what the manifest was verified with (strong / weak key) is kept: Sig.dropKey(name, pk) forgets everything a
--     replaced weak key signed (ns.OnKeyReplaced).
local _, ns = ...
ns = ns or {}

local G = {}
ns.Sig = G
local E, S = ns.Ed25519, ns.Serialize

-- 2.0 (SPEC-v2.0 §4.2): new tags, so a 1.x signature never verifies here, not even with the same name and key
G.TAG = "GSQ-MAN3"             -- domain separation of the record hash (1.x: GSQ-MAN1)
G.STMT_TAG = "GSQ-MAN4"        -- domain separation of the manifest statement (sec r3 S1: length-prefixed kids; 1.x: GSQ-MAN2)
G.HASH_LEN = 16                -- bytes of sha512 kept per record
G.MAX_ENTRIES = 400            -- records listed in one manifest
G.MAX_QUEUE = 300              -- manifests waiting for a verify on one client
G.TAG_ALT = 4                  -- different bodies queued for the same (author, n, signature) (sec F6)

local function num(n) if type(n) == "number" and n == math.floor(n) and n > -1e15 and n < 1e15 then return string.format("%d", n) end return tostring(n) end
local function hex(s) return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local function unhex(h)
  if type(h) ~= "string" or #h % 2 ~= 0 or h:find("[^0-9a-fA-F]") then return nil end
  return (h:gsub("..", function(x) return string.char(tonumber(x, 16)) end))
end

-- the hash of a record (hex): only the fields the author wrote; u (relay flag) and local fields are left out
-- fix/perf (runtime review M3): memoized by the encoded body (an exact key: a forged body never hits the real one's
-- entry); G.status runs it per relayed record in the message handler and X.retry per pending copy. Flushed whole past
-- HASH_MEMO entries.
G.HASH_MEMO = 600
local memo, memoN = {}, 0
function G.recHash(rec)
  local body = S.encode({ k = rec.k, id = rec.id, ts = rec.ts, sq = rec.sq, a = rec.a, d = rec.d or {} })
  local h = memo[body]
  if h then return h end
  h = hex(E.sha512(G.TAG .. "|rec|" .. body):sub(1, G.HASH_LEN))
  if memoN >= G.HASH_MEMO then memo, memoN = {}, 0 end
  memo[body], memoN = h, memoN + 1
  return h
end

-- the signed statement: canonical (sorted) so both ends build the same bytes. sec r3 S1: every kid goes with its
-- byte length ("<len>:<kid>=<hash>"), so the statement is injective whatever characters the ids hold (no entries can
-- be merged into one under the same signature, and no id chosen by someone else can make a manifest unsendable)
function G.statement(m)
  local kids = {}
  for kid in pairs(m.h) do kids[#kids + 1] = kid end
  table.sort(kids)
  local a = tostring(m.a)
  local parts = { G.STMT_TAG, #a .. ":" .. a, num(m.n) }
  for _, kid in ipairs(kids) do parts[#parts + 1] = #kid .. ":" .. kid .. "=" .. tostring(m.h[kid]) end
  return table.concat(parts, "\n")
end

-- the author's manifest over his records (list of records with rec.a == name)
-- sec F7 / QA D6, decision 2 (BRO 8-nov): a manifest lists only the MAN_CAP most recent records of its author, so it
-- always fits the 64 parts the receiver reassembles (Chunk.lua); older ones are seen "unverified". Signed pages: 1.2.1
G.MAN_CAP = 180
-- sec r5 S5-1/S5-2: a byte budget too (forced denials can have ids of ~300 chars), and the author's data records go
-- first, then presence, then repudiates, so a flood of forced denials cannot push them out of the signed set
G.MAN_BYTES = 13000            -- ~ 50-55 parts of 255 after encoding; the receiver takes 64
local CLASS = { presence = 1, repudiate = 2 }
function G.pick(name, records)
  local mine = {}
  for _, rec in ipairs(records) do if rec.a == name then mine[#mine + 1] = rec end end
  local function kid(r) return tostring(r.k) .. ":" .. tostring(r.id) end
  table.sort(mine, function(x, y)
    local cx, cy = CLASS[x.k] or 0, CLASS[y.k] or 0
    if cx ~= cy then return cx < cy end
    local tx, ty = tonumber(x.ts) or 0, tonumber(y.ts) or 0
    if tx ~= ty then return tx > ty end
    return kid(x) < kid(y)
  end)
  local out, bytes = {}, 0
  for _, r in ipairs(mine) do
    if #out >= G.MAN_CAP then break end
    local k = kid(r)
    local b = #((S and S.escape) and S.escape(S.encode(k)) or k) + G.HASH_LEN * 2 + 8   -- wire bytes, escapes included
    if bytes + b <= G.MAN_BYTES then out[#out + 1] = r; bytes = bytes + b end
  end
  return out
end

-- h (optional, fix/perf A2): the hashes of G.pick(name, records), already computed by the caller (Sync.OwnManifest)
function G.build(name, n, records, sk, pk, h)
  if not h then
    h = {}
    for _, rec in ipairs(G.pick(name, records)) do h[rec.k .. ":" .. rec.id] = G.recHash(rec) end
  end
  local m = { a = name, n = n, h = h }
  m.s = hex(E.sign(sk, pk, G.statement(m)))
  return m
end

function G.validShape(m)
  if type(m) ~= "table" or type(m.a) ~= "string" or type(m.n) ~= "number" or m.n < 1 or m.n ~= math.floor(m.n)
    or type(m.h) ~= "table" or type(m.s) ~= "string" or #m.s ~= 128 or m.a:find("%c") then return false end
  local c = 0
  for kid, h in pairs(m.h) do
    c = c + 1
    -- sec r2 R2 was closed by refusing "=" and controls in a kid; sec r3 S1: that let anyone make a victim sign an
    -- unsendable manifest, so the statement is length-prefixed instead and any kid string is allowed
    if c > G.MAX_ENTRIES or type(kid) ~= "string" or type(h) ~= "string" or #h ~= G.HASH_LEN * 2 or h:find("[^0-9a-f]") then return false end
  end
  return unhex(m.s) ~= nil
end

-- state: db = { man = { [author] = { n, h, s, strength, pk (hex) } }, n = counters }; queue is in memory only
function G.st(db)
  db.man = type(db.man) == "table" and db.man or {}
  db.cnt = type(db.cnt) == "table" and db.cnt or { verified = 0, rejected = 0 }
  return db
end
local queue, queued, parked = {}, {}, {}
local nParked, parkedBy = 0, {}
G.MAX_PARKED = 300             -- manifests of authors whose key we do not hold yet (annex G: it may get certified)
G.PARK_PER_AUTHOR = 8          -- parked per author: one per sender (AF6: a fake with a huge n cannot displace the real)
G.PARK_PER_SENDER = 20         -- sec F11: one sender cannot fill the global park with keyless authors
function G.resetQueue() queue, queued, parked, nParked, parkedBy = {}, {}, {}, 0, {} end
-- the author's key just became usable (certified, annex G): his parked manifests get their verify, newest first
-- (a fake one fails its verify, then the real one is next)
function G.unpark(name)
  local P = parked[name]
  if not P then return false end
  parked[name] = nil
  local list = {}
  for from, q in pairs(P.by) do
    list[#list + 1] = q; nParked = nParked - 1
    local c = (parkedBy[from] or 1) - 1
    parkedBy[from] = c > 0 and c or nil
  end
  table.sort(list, function(x, y) return x.m.n > y.m.n end)
  local any = false
  for _, q in ipairs(list) do
    if not queued[q.tag] and #queue < G.MAX_QUEUE then
      queued[q.tag] = q
      queue[#queue + 1] = q
      any = true
    end
  end
  return any
end
function G.pending() return #queue end

-- a manifest heard from anyone: queued for verification unless we already hold this or a newer one
-- keyOf(name) -> pk (raw), "strong" | "weak" | nil (Trust.keyOf bound to the trust db)
function G.offer(db, m, keyOf, from)
  G.st(db)
  if not G.validShape(m) then db.cnt.rejected = db.cnt.rejected + 1; return "bad" end
  local cur = db.man[m.a]
  if cur and cur.n >= m.n then
    -- the same seq with another body from a valid key would be the author signing twice: keep the first
    return "old"
  end
  -- sec F6: (a, n, s) alone does not identify a manifest (a forged copy can reuse a real signature over another body):
  -- a copy is deduplicated only against a queued one with the same body; up to G.TAG_ALT bodies per (a, n, s)
  local base = m.a .. "|" .. num(m.n) .. "|" .. m.s
  local tag
  for i = 1, G.TAG_ALT do
    local t = i == 1 and base or (base .. "|" .. i)
    local q = queued[t]
    if q then
      if G.sameBody(q.m, m) then return "queued" end
    elseif not tag then tag = t end
  end
  if not tag then return "full" end
  if #queue >= G.MAX_QUEUE then return "full" end
  local q = { m = m, tag = tag, keyOf = keyOf, from = type(from) == "string" and from or "?" }
  queued[tag] = q
  queue[#queue + 1] = q
  return "queued"
end

-- the same listed hashes (the signed body of two manifests with the same a, n)
function G.sameBody(m1, m2)
  if type(m1) ~= "table" or type(m2) ~= "table" or type(m1.h) ~= "table" or type(m2.h) ~= "table" then return false end
  if m1.a ~= m2.a or m1.n ~= m2.n then return false end
  for k, v in pairs(m1.h) do if m2.h[k] ~= v then return false end end
  for k in pairs(m2.h) do if m1.h[k] == nil then return false end end
  return true
end

-- one verification (call once per frame, not in combat). Returns the author whose manifest was accepted, or nil.
function G.step(db, onAccept)
  G.st(db)
  local q = table.remove(queue, 1)
  if not q then return nil end
  queued[q.tag] = nil
  local m = q.m
  local cur = db.man[m.a]
  if cur and cur.n >= m.n then return nil end
  local pk, strength = q.keyOf(m.a)
  if not pk then
    -- no key yet: it may arrive later (hello / ks / certificates, annex G): parked, the newest per author AND sender
    -- (AF6: one sender's fake manifest with a huge n would otherwise displace the real one until the key arrives)
    local P = parked[m.a]
    if not P then P = { by = {}, c = 0 } end
    local from = q.from or "?"
    local p = P.by[from]
    if p then if p.m.n < m.n then P.by[from] = q end
    elseif P.c < G.PARK_PER_AUTHOR and nParked < G.MAX_PARKED and (parkedBy[from] or 0) < G.PARK_PER_SENDER then
      P.by[from] = q; P.c = P.c + 1; nParked = nParked + 1; parkedBy[from] = (parkedBy[from] or 0) + 1
    end
    if P.c > 0 then parked[m.a] = P end
    return nil
  end
  if not E.verify(pk, G.statement(m), unhex(m.s)) then db.cnt.rejected = db.cnt.rejected + 1; return nil end
  -- a weak key never replaces what a strong key signed
  if cur and cur.strength ~= "weak" and strength == "weak" then db.cnt.rejected = db.cnt.rejected + 1; return nil end
  db.man[m.a] = { n = m.n, h = m.h, s = m.s, strength = strength, pk = hex(pk) }
  db.cnt.verified = db.cnt.verified + 1
  if onAccept then onAccept(m.a, strength) end
  return m.a
end

-- "strong" | "weak" | nil: is this exact record listed in the last verified manifest of its author?
function G.status(db, rec)
  local cur = db.man and db.man[rec.a]
  if not cur then return nil end
  if cur.h[rec.k .. ":" .. rec.id] ~= G.recHash(rec) then return nil end
  return cur.strength
end

-- the manifest we hold for an author (to relay it next to his records)
function G.manifestOf(db, name)
  local cur = db.man and db.man[name]
  if not cur then return nil end
  return { a = name, n = cur.n, h = cur.h, s = cur.s }
end

-- a replaced (weak) key: forget what it signed
function G.dropKey(db, name, oldPk)
  local cur = db.man and db.man[name]
  if cur and (oldPk == nil or cur.pk == hex(oldPk)) then db.man[name] = nil; return true end
  return false
end

-- the author's key we verified a manifest with as weak is now his strong key (heard in person, same pk)
function G.promote(db, name, pk)
  local cur = db.man and db.man[name]
  if cur and cur.strength ~= "strong" and cur.pk == hex(pk) then cur.strength = "strong"; return true end
  return false
end

function G.counts(db)
  G.st(db)
  local strong, weak = 0, 0
  for _, m in pairs(db.man) do if m.strength == "strong" then strong = strong + 1 else weak = weak + 1 end end
  return { verified = db.cnt.verified, rejected = db.cnt.rejected, pending = #queue, strong = strong, weak = weak }
end

return G
