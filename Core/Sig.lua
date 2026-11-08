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

G.TAG = "GSQ-MAN1"             -- domain separation of the manifest statement
G.HASH_LEN = 16                -- bytes of sha512 kept per record
G.MAX_ENTRIES = 400            -- records listed in one manifest
G.MAX_QUEUE = 300              -- manifests waiting for a verify on one client

local function num(n) if type(n) == "number" and n == math.floor(n) and n > -1e15 and n < 1e15 then return string.format("%d", n) end return tostring(n) end
local function hex(s) return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local function unhex(h)
  if type(h) ~= "string" or #h % 2 ~= 0 or h:find("[^0-9a-fA-F]") then return nil end
  return (h:gsub("..", function(x) return string.char(tonumber(x, 16)) end))
end

-- the hash of a record (hex): only the fields the author wrote; u (relay flag) and local fields are left out
function G.recHash(rec)
  local body = S.encode({ k = rec.k, id = rec.id, ts = rec.ts, sq = rec.sq, a = rec.a, d = rec.d or {} })
  return hex(E.sha512(G.TAG .. "|rec|" .. body):sub(1, G.HASH_LEN))
end

-- the signed statement: canonical (sorted) so both ends build the same bytes
function G.statement(m)
  local kids = {}
  for kid in pairs(m.h) do kids[#kids + 1] = kid end
  table.sort(kids)
  local parts = { G.TAG, tostring(m.a), num(m.n) }
  for _, kid in ipairs(kids) do parts[#parts + 1] = kid .. "=" .. m.h[kid] end
  return table.concat(parts, "\n")
end

-- the author's manifest over his records (list of records with rec.a == name)
function G.build(name, n, records, sk, pk)
  local h = {}
  for _, rec in ipairs(records) do if rec.a == name then h[rec.k .. ":" .. rec.id] = G.recHash(rec) end end
  local m = { a = name, n = n, h = h }
  m.s = hex(E.sign(sk, pk, G.statement(m)))
  return m
end

function G.validShape(m)
  if type(m) ~= "table" or type(m.a) ~= "string" or type(m.n) ~= "number" or m.n < 1 or m.n ~= math.floor(m.n)
    or type(m.h) ~= "table" or type(m.s) ~= "string" or #m.s ~= 128 then return false end
  local c = 0
  for kid, h in pairs(m.h) do
    c = c + 1
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
local queue, queued = {}, {}
function G.resetQueue() queue, queued = {}, {} end
function G.pending() return #queue end

-- a manifest heard from anyone: queued for verification unless we already hold this or a newer one
-- keyOf(name) -> pk (raw), "strong" | "weak" | nil (Trust.keyOf bound to the trust db)
function G.offer(db, m, keyOf)
  G.st(db)
  if not G.validShape(m) then db.cnt.rejected = db.cnt.rejected + 1; return "bad" end
  local cur = db.man[m.a]
  if cur and cur.n >= m.n then
    -- the same seq with another body from a valid key would be the author signing twice: keep the first
    return "old"
  end
  local tag = m.a .. "|" .. num(m.n) .. "|" .. m.s
  if queued[tag] then return "queued" end
  if #queue >= G.MAX_QUEUE then return "full" end
  queued[tag] = true
  queue[#queue + 1] = { m = m, tag = tag, keyOf = keyOf }
  return "queued"
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
    -- no key yet: it may arrive later (hello / ks); the next copy of the manifest gets another try
    return nil
  end
  if not E.verify(pk, G.statement(m), unhex(m.s)) then db.cnt.rejected = db.cnt.rejected + 1; return nil end
  -- a weak key never replaces what a strong key signed
  if cur and cur.strength == "strong" and strength ~= "strong" then db.cnt.rejected = db.cnt.rejected + 1; return nil end
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
