-- Guild Squads (MIT) - Core/Trust.lua
-- Pure Lua (no WoW API). v1.2 annex F of docs/SPEC-v1.2-p2p.md, with BRO's change of 8-nov 01:02 (no dev key, no
-- notary, no central root of trust). Ed25519 keys per character (Core/Ed25519.lua):
--   * our own key: generated once from an entropy pool (see T.entropy) and kept in SavedVariables.
--   * learning other keys:
--       - STRONG: heard from its owner in person (WoW guarantees the sender of addon messages): trust on first use,
--         the first strong key heard is pinned.
--       - CERT (annex G): a key relayed by others is only a candidate (T.hearRelayed, no quorum); it is used once >= 2
--         certificates of issuers heard in person by us list it (Core/Cert.lua -> T.certify). An in-person issuer
--         listing another key makes the name "disputed" (T.dispute): shown unverified, nothing new applied, diag.
--       - "weak" (the 1.1 / early 1.2 quorum of 2 relayers) is no longer produced; a "weak" entry left in an old
--         SavedVariables is still treated as weak by the callers (never over strong, never a repudiate or authority).
--   * conflicts: the owner in person always wins (BRO 8-nov 03:09); the replaced key and what it signed are dropped
--     and the relayers that brought it are counted as suspects (diag).
--   * rotation: only the old key signing the new one (T.rotation). A lost key needs `/gsq trust reset <name>` by hand.
local _, ns = ...
ns = ns or {}

local T = {}
ns.Trust = T
local E = ns.Ed25519

-- v1.2 annex G (BRO 8-nov 04:13, option 1): relayed keys are only candidates (no quorum); a stranger's key is accepted
-- when >= 2 certificates of issuers heard in person by us list it (Core/Cert.lua -> T.certify, strength "cert")
T.MAX_PEND_KEYS = 500          -- relayed keys waiting for quorum on one client
T.MAX_PEND_RELAYER = 200       -- of those, brought by one relayer (same cap as the P2P pending records)
T.PEND_TTL = 7 * 86400
T.ALERTS_MAX = 20
T.ROT_TAG = "GSQ-ROT2"         -- domain separation of the rotation statement (2.0, SPEC-v2.0 §4.2; 1.x: GSQ-ROT1)

local function hex(s) return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
T.hex = hex
function T.unhex(h)
  if type(h) ~= "string" or #h % 2 ~= 0 or h:find("[^0-9a-fA-F]") then return nil end
  return (h:gsub("..", function(x) return string.char(tonumber(x, 16)) end))
end

-- trust state lives in db (a SavedVariables subtree): { me = {sk, pk}, keys = {[name] = {pk, s = "strong"|"weak",
-- t = first seen, by = {relayers}}}, pend = {[name] = {[pk] = {by = {[relayer] = t}, t}}}, contested = {[name] = t},
-- suspects = {[relayer] = n}, alerts = {list of strings}, n = counters }
function T.st(db)
  db.keys = db.keys or {}
  db.pend = db.pend or {}
  db.contested = db.contested or {}
  db.suspects = db.suspects or {}
  db.alerts = db.alerts or {}
  db.n = db.n or { verified = 0, rejected = 0, pending = 0 }
  return db
end

local function alert(db, msg)
  local a = db.alerts
  a[#a + 1] = msg
  while #a > T.ALERTS_MAX do table.remove(a, 1) end
end

local function validPk(pk) return type(pk) == "string" and #pk == 32 end

-- ---------------------------------------------------------------------------------------------------------------
-- entropy and our own key
-- The pool hashes every sample it gets (debugprofilestop() at input/frame events, GetTime, GetServerTime, cursor
-- position, GUID, math.random). Limited entropy is a documented risk (docs: security notes): the samples are many
-- and timing-based, the seed is sha512 of all of them.
function T.entropy()
  local pool = { acc = "", buf = {}, len = 0, n = 0 }
  function pool.add(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    local s = table.concat(parts, ",")
    pool.buf[#pool.buf + 1] = s
    pool.len = pool.len + #s + 1
    pool.n = pool.n + 1
    if pool.len > 2048 then -- fold the buffer into the running hash
      pool.acc = E.sha512(pool.acc .. "|" .. table.concat(pool.buf, "|"))
      pool.buf, pool.len = {}, 0
    end
  end
  function pool.seed() return E.sha512("GSQ-SEED1" .. pool.acc .. "|" .. table.concat(pool.buf, "|") .. "|" .. pool.n):sub(1, 32) end
  return pool
end

T.MIN_SAMPLES = 64             -- samples the pool needs before we create our key
-- `db` here is the per-character holder of our key (only `me` is written), not the guild's trust db
function T.ensureOwn(db, pool)
  if db.me and validPk(T.unhex(db.me.pk)) and T.unhex(db.me.sk) then return T.unhex(db.me.sk), T.unhex(db.me.pk) end
  if not pool or pool.n < T.MIN_SAMPLES then return nil end
  local sk = pool.seed()
  local pk = E.publicKey(sk)
  db.me = { sk = hex(sk), pk = hex(pk) }
  return sk, pk
end
function T.own(db)
  if not (db and db.me) then return nil end
  return T.unhex(db.me.sk), T.unhex(db.me.pk)
end

-- ---------------------------------------------------------------------------------------------------------------
-- learning keys
-- returns pk, "strong" | "cert" | "weak" | nil ("cert" = annex G, counts as strong to apply data; "weak" = 1.1 quorum)
function T.keyOf(db, name)
  local k = db.keys and db.keys[name]
  if not k or (db.contested and db.contested[name]) then return nil end
  return T.unhex(k.pk), k.s
end
function T.isStrong(db, name, pk)
  local k, s = T.keyOf(db, name)
  return (s == "strong" or s == "cert") and (pk == nil or k == pk)
end
-- heard from its owner in person (the only keys that may issue certificates for us, annex G)
function T.inPerson(db, name, pk)
  local k, s = T.keyOf(db, name)
  return s == "strong" and (pk == nil or k == pk)
end

local function dropPend(db, name)
  local p = db.pend[name]
  if p then db.pend[name] = nil end
end

-- the owner `name` sent us `pk` himself. Returns:
--   "new"      first key: pinned strong
--   "same"     already pinned (or a weak one that becomes strong)
--   "replaced" it beat the key we held, weak, contested or strong (BRO 8-nov 03:09: WoW guarantees the sender, so a
--              key heard from the owner in person always wins; the old one is "replaced", noted in alerts/diag, and
--              the caller drops what it signed; second value = old pk)
function T.hearOwner(db, name, pk, now)
  T.st(db)
  if not validPk(pk) then return "bad" end
  local k = db.keys[name]
  local h = hex(pk)
  if k and k.s == "strong" then
    if k.pk == h then k.seen = now; return "same" end
    db.n.replaced = (db.n.replaced or 0) + 1
    alert(db, "keychange " .. name)
    db.keys[name] = { pk = h, s = "strong", t = now, seen = now, prev = k.pk }
    db.contested[name] = nil
    dropPend(db, name)
    return "replaced", T.unhex(k.pk)
  end
  local old
  if k and k.pk ~= h then
    old = T.unhex(k.pk)
    for r in pairs(k.by or {}) do db.suspects[r] = (db.suspects[r] or 0) + 1 end
    alert(db, "weak-lost " .. name)
  end
  if db.contested[name] then
    for opk, e in pairs(db.pend[name] or {}) do
      if opk ~= h then for r in pairs(e.by) do db.suspects[r] = (db.suspects[r] or 0) + 1 end end
    end
  end
  local wasWeak = k ~= nil and not old
  db.keys[name] = { pk = h, s = "strong", t = now, seen = now }
  db.contested[name] = nil
  dropPend(db, name)
  if old then return "replaced", old end
  return wasWeak and "same" or "new"
end

local function relayerLoad(db, relayer)
  local n = 0
  for _, byPk in pairs(db.pend) do for _, e in pairs(byPk) do if e.by[relayer] then n = n + 1 end end end
  return n
end
local function pendCount(db)
  local n = 0
  for _, byPk in pairs(db.pend) do for _ in pairs(byPk) do n = n + 1 end end
  return n
end

-- sec F3: make room for one candidate: drop the oldest one brought by a single relayer, taken from the relayer who
-- brought the most (a flood evicts itself first); if every candidate has several relayers, the oldest overall
local function evictPend(db)
  local load = {}
  for _, byPk in pairs(db.pend) do for _, e in pairs(byPk) do for r in pairs(e.by) do load[r] = (load[r] or 0) + 1 end end end
  local bn, bpk, bl, bt, on, opk, ot
  for name, byPk in pairs(db.pend) do
    for pk, e in pairs(byPk) do
      local r = next(e.by)
      if r and next(e.by, r) == nil then
        local l, t = load[r], e.t or 0
        if not bl or l > bl or (l == bl and t < bt) then bn, bpk, bl, bt = name, pk, l, t end
      end
      if not ot or (e.t or 0) < ot then on, opk, ot = name, pk, e.t or 0 end
    end
  end
  local n, pk = bn or on, bpk or opk
  if n then db.pend[n][pk] = nil; if next(db.pend[n]) == nil then db.pend[n] = nil end end
end

-- `relayer` (not the owner) says `name` has key `pk`. Returns "strong" (we already hold it strong: nothing to do),
-- "pending" (a candidate for annex G certificates), the strength we already hold it with, "full" (caps) or "bad".
function T.hearRelayed(db, name, pk, relayer, now)
  T.st(db)
  if not validPk(pk) or type(relayer) ~= "string" then return "bad" end
  if relayer == name then return T.hearOwner(db, name, pk, now) end
  local h = hex(pk)
  local k = db.keys[name]
  if k and k.s == "strong" then
    if k.pk ~= h then db.suspects[relayer] = (db.suspects[relayer] or 0) + 1 end
    return "strong"
  end
  if k and k.pk == h and not db.contested[name] then
    k.by = k.by or {}
    k.by[relayer] = true
    return k.s
  end
  local byPk = db.pend[name] or {}
  local e = byPk[h]
  if not e then
    if relayerLoad(db, relayer) >= T.MAX_PEND_RELAYER then return "full" end
    -- sec F3: a relayer stands for one key per name (his newest); a full table evicts instead of refusing, so a flood
    -- cannot keep the real key of a stranger from being a candidate
    for opk, o in pairs(byPk) do
      if o.by[relayer] then o.by[relayer] = nil; if next(o.by) == nil then byPk[opk] = nil end end
    end
    if pendCount(db) >= T.MAX_PEND_KEYS then evictPend(db) end
    e = { by = {}, t = now }
    byPk[h] = e
    db.pend[name] = byPk
  end
  e.by[relayer] = now
  return "pending"
end

-- annex G: the candidate keys we heard relayed for `name` (raw pk list), the one in use first
function T.candidates(db, name)
  T.st(db)
  local out, seen = {}, {}
  local k = db.keys[name]
  if k then out[1] = T.unhex(k.pk); seen[k.pk] = true end
  for h in pairs(db.pend[name] or {}) do if not seen[h] then seen[h] = true; out[#out + 1] = T.unhex(h) end end
  return out
end
-- annex G: >= 2 certificates of in-person issuers. Never over a key heard in person. Returns the replaced pk, if any.
function T.certify(db, name, pk, now)
  T.st(db)
  local k = db.keys[name]
  if k and k.s == "strong" then return nil end
  local h, old = hex(pk), nil
  if k and k.pk ~= h then old = T.unhex(k.pk) end
  if k and k.pk == h and k.s == "cert" then return nil end
  db.keys[name] = { pk = h, s = "cert", t = now, by = k and k.pk == h and k.by or nil }
  db.contested[name] = nil
  if db.pend[name] then db.pend[name][h] = nil; if next(db.pend[name]) == nil then db.pend[name] = nil end end
  if old then alert(db, "cert-changed " .. name) end
  return old
end
-- annex G: an in-person issuer lists another key: "disputed" (shown unverified, nothing new applied, diag). Returns
-- the key that was in use (not in person), which the caller drops with what it signed.
function T.dispute(db, name, now)
  T.st(db)
  local k = db.keys[name]
  if k and k.s == "strong" then return nil end
  if not db.contested[name] then alert(db, "disputed " .. name) end
  db.contested[name] = db.contested[name] or now
  if k then
    db.keys[name] = nil
    local pend = db.pend[name] or {}
    pend[k.pk] = pend[k.pk] or { by = k.by or {}, t = now }
    db.pend[name] = pend
    return T.unhex(k.pk)
  end
  return nil
end

-- rotation statement: the OLD key signs ROT_TAG | name | new pk
function T.rotationMsg(name, newPk) return T.ROT_TAG .. "|" .. name .. "|" .. newPk end
function T.signRotation(oldSk, oldPk, name, newPk) return E.sign(oldSk, oldPk, T.rotationMsg(name, newPk)) end
-- applies a rotation heard from anyone: valid only if signed by the key we hold for `name`; keeps its strength
function T.rotate(db, name, newPk, sig, now)
  T.st(db)
  local cur, s = T.keyOf(db, name)
  if not cur or not validPk(newPk) or type(sig) ~= "string" then return false end
  if not E.verify(cur, T.rotationMsg(name, newPk), sig) then
    db.n.rejected = db.n.rejected + 1
    alert(db, "badrotation " .. name)
    return false
  end
  db.keys[name] = { pk = hex(newPk), s = s, t = now, by = db.keys[name].by, rs = hex(sig), prev = hex(cur) }
  alert(db, "rotated " .. name)
  return true
end
-- the rotation signature (old key over the current one) we hold for `name`, so relayers can pass it on (AF5)
function T.rotSig(db, name)
  local k = db and db.keys and db.keys[name]
  return k and type(k.rs) == "string" and k.rs or nil
end
-- a relayed key that differs from the strong one we hold, without a valid rotation signature (AF5): refused, noted
-- once per name in alerts (diag) and counted; the relayer becomes a suspect
function T.unsignedChange(db, name, relayer)
  T.st(db)
  db.n.rejected = db.n.rejected + 1
  if type(relayer) == "string" then db.suspects[relayer] = (db.suspects[relayer] or 0) + 1 end
  local msg = "unsigned-keychange " .. name
  for _, a in ipairs(db.alerts) do if a == msg then return end end
  alert(db, msg)
end

-- /gsq trust reset <name>: forget everything about the key of `name` (lost SavedVariables)
function T.reset(db, name)
  T.st(db)
  db.keys[name], db.contested[name] = nil, nil
  dropPend(db, name)
end

function T.expire(db, now)
  T.st(db)
  for name, byPk in pairs(db.pend) do
    for h, e in pairs(byPk) do if now - e.t > T.PEND_TTL then byPk[h] = nil end end
    if next(byPk) == nil then db.pend[name] = nil end
  end
end

function T.counts(db)
  T.st(db)
  local strong, weak = 0, 0
  for name, k in pairs(db.keys) do
    if not db.contested[name] then if k.s == "strong" then strong = strong + 1 else weak = weak + 1 end end
  end
  local sus = 0
  for _, n in pairs(db.suspects) do if n > 0 then sus = sus + 1 end end
  return strong, weak, pendCount(db), sus
end

return T
