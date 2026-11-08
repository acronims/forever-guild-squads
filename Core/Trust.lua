-- Guild Squads (MIT) - Core/Trust.lua
-- Pure Lua (no WoW API). v1.2 annex F of docs/SPEC-v1.2-p2p.md, with BRO's change of 8-nov 01:02 (no dev key, no
-- notary, no central root of trust). Ed25519 keys per character (Core/Ed25519.lua):
--   * our own key: generated once from an entropy pool (see T.entropy) and kept in SavedVariables.
--   * learning other keys:
--       - STRONG: heard from its owner in person (WoW guarantees the sender of addon messages): trust on first use,
--         the first strong key heard is pinned.
--       - WEAK: relayed by others, once 2 distinct relayers (none of them the owner) bring the same key. What a weak
--         key signs is shown "unverified" and never deletes or replaces data signed by a strong key, never applies a
--         `repudiate`, a squad roster or settings (the callers check T.isStrong).
--       - two different weak keys for the same name, both with quorum: the name is "contested" and neither is used
--         until the owner is heard in person (a pair of alts cannot win a race against the real key).
--   * conflicts: the owner in person always beats a weak key; the weak key and what it signed are dropped and the
--     relayers that brought it are counted as suspects (diag). A pinned strong key that changes is refused and noted.
--   * rotation: only the old key signing the new one (T.rotation). A lost key needs `/gsq trust reset <name>` by hand.
local _, ns = ...
ns = ns or {}

local T = {}
ns.Trust = T
local E = ns.Ed25519

T.QUORUM_KEY = 2
T.MAX_PEND_KEYS = 500          -- relayed keys waiting for quorum on one client
T.MAX_PEND_RELAYER = 200       -- of those, brought by one relayer (same cap as the P2P pending records)
T.PEND_TTL = 7 * 86400
T.ALERTS_MAX = 20
T.ROT_TAG = "GSQ-ROT1"         -- domain separation of the rotation statement

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
-- returns pk, "strong" | "weak" | nil
function T.keyOf(db, name)
  local k = db.keys and db.keys[name]
  if not k or (db.contested and db.contested[name]) then return nil end
  return T.unhex(k.pk), k.s
end
function T.isStrong(db, name, pk)
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
--   "replaced" it beat a weak/contested key: the caller drops what the old weak key signed (second value = old pk)
--   "changed"  a different strong key without rotation: refused, noted in alerts
function T.hearOwner(db, name, pk, now)
  T.st(db)
  if not validPk(pk) then return "bad" end
  local k = db.keys[name]
  local h = hex(pk)
  if k and k.s == "strong" then
    if k.pk == h then return "same" end
    db.n.rejected = db.n.rejected + 1
    alert(db, "keychange " .. name)
    return "changed"
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
  db.keys[name] = { pk = h, s = "strong", t = now }
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

-- `relayer` (not the owner) says `name` has key `pk`. Returns "strong" (we already hold it strong: nothing to do),
-- "pending", "weak" (quorum reached: weak key), "contested", "full" (caps) or "bad".
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
    return "weak"
  end
  local byPk = db.pend[name] or {}
  local e = byPk[h]
  if not e then
    if relayerLoad(db, relayer) >= T.MAX_PEND_RELAYER or pendCount(db) >= T.MAX_PEND_KEYS then return "full" end
    e = { by = {}, t = now }
    byPk[h] = e
    db.pend[name] = byPk
  end
  e.by[relayer] = now
  local n = 0
  for _ in pairs(e.by) do n = n + 1 end
  if n < T.QUORUM_KEY then return "pending" end
  if k and k.pk ~= h then
    -- a second weak key with quorum: neither is used until the owner is heard in person
    db.contested[name] = now
    alert(db, "contested " .. name)
    return "contested"
  end
  if db.contested[name] then return "contested" end
  local by = {}
  for r in pairs(e.by) do by[r] = true end
  db.keys[name] = { pk = h, s = "weak", t = now, by = by }
  return "weak"
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
  db.keys[name] = { pk = hex(newPk), s = s, t = now, by = db.keys[name].by }
  alert(db, "rotated " .. name)
  return true
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
