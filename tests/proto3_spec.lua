-- 2.0 (docs/SPEC-v2.0-identidad.md §4, AC6): PROTO 3. What is signed carries the character name, and in the 2.0 the
-- name is the WoW Forever identity «Name Surname» (a 1.2.x reads it as «Name-Realm» and mixes identities), so the 2.0
-- and the 1.x are two separate networks:
--   * Comm.PROTO = M.PROTO = 3. A v = 1 / 2 message is dropped, its sender counted once per identity (oldPeers) and
--     the OLD_PEERS line ("... older than 2.0 ...") is shown once per session.
--   * new domain tags (GSQ-MAN3 / GSQ-MAN4 / GSQ-CRT2 / GSQ-ROT2): a manifest, a certificate or a rotation signed with
--     the 1.2.2 tags never verifies in the 2.0, not even with the same name and the same key (realm mode).
--   * character-name fields hold 64 bytes (12 + 1 + 12 characters of 2 bytes = 49), they were 48.
local G, Cc, T, E, S, M = NS.Sig, NS.Cert, NS.Trust, NS.Ed25519, NS.Serialize, NS.Model
local NOW = 1795000000

local function hex(s) return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64(s)
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local d = { math.floor(n / 262144) % 64, math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64 }
    for j = 1, (b and (c and 4 or 3) or 2) do out[#out + 1] = B64:sub(d[j] + 1, d[j] + 1) end
  end
  return table.concat(out)
end
local function key(tag) local sk = E.sha512("proto3-key " .. tag):sub(1, 32) return sk, E.publicKey(sk) end
local sk, pk = key("Kas Pitas")
local skN, pkN = key("Kas Pitas new")
local ME = "Kas Pitas"
local function keyOf(n) if n == ME then return pk, "strong" end end

-- the 1.2.2 forms, written out here on purpose (Core/Sig.lua and Core/Cert.lua memoize their hashes by body / name|pk,
-- not by tag, so switching G.TAG / C.TAG for a moment would poison the memo)
local function hash122(rec)
  local body = S.encode({ k = rec.k, id = rec.id, ts = rec.ts, sq = rec.sq, a = rec.a, d = rec.d or {} })
  return hex(E.sha512("GSQ-MAN1|rec|" .. body):sub(1, 16))
end
local function statement122(m)
  local kids = {}
  for kid in pairs(m.h) do kids[#kids + 1] = kid end
  table.sort(kids)
  local parts = { "GSQ-MAN2", #m.a .. ":" .. m.a, string.format("%d", m.n) }
  for _, kid in ipairs(kids) do parts[#parts + 1] = #kid .. ":" .. kid .. "=" .. m.h[kid] end
  return table.concat(parts, "\n")
end
local function certHash122(name, k) return b64(E.sha512("GSQ-CRT1|" .. name .. "|" .. k):sub(1, 12)) end

test("proto3: the 2.0 speaks PROTO 3 and signs under its own domain tags (MAN3, MAN4, CRT2, ROT2)", function()
  eq(M.PROTO, 3, "M.PROTO")
  eq(G.TAG, "GSQ-MAN3", "record hash tag"); eq(G.STMT_TAG, "GSQ-MAN4", "manifest statement tag")
  eq(Cc.TAG, "GSQ-CRT2", "certificate tag"); eq(T.ROT_TAG, "GSQ-ROT2", "rotation tag")
  local st = Cc.statement({ i = ME, n = 1, e = {} })
  ok(st:find("GSQ-CRT2", 1, true) == 1, "the certificate statement starts with its tag")
  ok(T.rotationMsg(ME, "x"):find("GSQ-ROT2|", 1, true) == 1, "the rotation statement starts with its tag")
end)

test("proto3: a manifest signed with the 1.2.2 tags (same name, same key) never verifies in the 2.0", function()
  local r = { k = "profile", id = ME, ts = NOW, sq = 1, a = ME, d = { class = "MAGE" } }
  -- control: the 2.0 manifest of the same author and key verifies (the check below is not empty)
  G.resetQueue()
  local db = G.st({})
  G.offer(db, G.build(ME, 1, { r }, sk, pk), keyOf)
  ok(G.step(db) == ME and G.status(db, r) == "strong", "control: a 2.0 manifest verifies")
  ok(hash122(r) ~= G.recHash(r), "the record hash depends on the tag")
  -- the 1.2.2 manifest: record hashes under GSQ-MAN1, statement under GSQ-MAN2, signed by the same key
  local m = { a = ME, n = 2, h = { ["profile:" .. ME] = hash122(r) } }
  m.s = hex(E.sign(sk, pk, statement122(m)))
  G.resetQueue()
  local db2 = G.st({})
  eq(G.offer(db2, m, keyOf), "queued")
  ok(G.step(db2) == nil, "the 1.2.2 manifest is not accepted")
  eq(db2.cnt.rejected, 1, "counted as rejected")
  ok(G.status(db2, r) == nil, "its record stays unverified")
  -- the 2.0 hashes under the 1.2.2 statement tag: rejected too (the statement tag alone separates the domains)
  local m2 = { a = ME, n = 3, h = { ["profile:" .. ME] = G.recHash(r) } }
  m2.s = hex(E.sign(sk, pk, statement122(m2)))
  G.offer(db2, m2, keyOf)
  ok(G.step(db2) == nil and db2.cnt.rejected == 2, "a GSQ-MAN2 statement over 2.0 hashes is rejected")
end)

test("proto3: a certificate signed with the 1.2.2 tag never verifies in the 2.0", function()
  local tdb = T.st({})
  T.hearOwner(tdb, ME, pk, NOW)                      -- the issuer is in person for us
  local _, pkZ = key("Zed Ruiz")
  -- control: the 2.0 certificate verifies
  Cc.resetQueue()
  local cdb = Cc.st({})
  Cc.offer(cdb, Cc.build(ME, 1, { ["Zed Ruiz"] = pkZ }, sk, pk))
  while Cc.pending() > 0 do Cc.step(cdb, tdb, NOW) end
  ok(Cc.holds(cdb, ME), "control: a 2.0 certificate verifies")
  ok(certHash122("Zed Ruiz", pkZ) ~= Cc.hash("Zed Ruiz", pkZ), "the certified hash12 depends on the tag")
  -- the 1.2.2 certificate: entries under GSQ-CRT1, statement under GSQ-CRT1, same issuer and key
  local c = { i = ME, n = 2, e = { certHash122("Zed Ruiz", pkZ) } }
  c.s = hex(E.sign(sk, pk, "GSQ-CRT1\n" .. c.i .. "\n" .. string.format("%d", c.n) .. "\n" .. table.concat(c.e, "\n")))
  ok(Cc.validShape(c), "well formed (only the tag is old)")
  Cc.resetQueue()
  local cdb2 = Cc.st({})
  Cc.offer(cdb2, c)
  while Cc.pending() > 0 do Cc.step(cdb2, tdb, NOW) end
  ok(not Cc.holds(cdb2, ME), "the 1.2.2 certificate is not accepted")
end)

test("proto3: a key rotation signed with the 1.2.2 tag never rotates in the 2.0", function()
  local function db() return T.st({ keys = { [ME] = { pk = hex(pk), s = "strong", t = NOW } } }) end
  local old = E.sign(sk, pk, "GSQ-ROT1|" .. ME .. "|" .. pkN)
  ok(not T.rotate(db(), ME, pkN, old, NOW), "the 1.2.2 rotation signature is refused")
  ok(T.rotate(db(), ME, pkN, T.signRotation(sk, pk, ME, pkN), NOW), "control: a 2.0 rotation signature rotates")
end)

-------------------------------------------------------------------------------
-- Comm: v = 2 dropped, its senders counted once per identity
local Gl = { CreateFrame = CreateFrame, GetTime = GetTime, C_ChatInfo = C_ChatInfo, C_Timer = C_Timer }
local frame = { scripts = {} }
function frame:RegisterEvent() end
function frame:SetScript(k, fn) self.scripts[k] = fn end
local handled, olds = {}, 0
CreateFrame = function() return frame end
GetTime = function() return 1000 end
C_Timer = nil
C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end, SendAddonMessage = function() return 0 end }
-- the identity of the contract (§2.4), forever mode: «Name Surname», a realm suffix dropped
local function id(n)
  if type(n) ~= "string" or n == "" then return nil end
  local sp, dash = n:find(" ", 1, true), n:find("-", 1, true)
  if sp and dash and dash > sp then return n:sub(1, dash - 1) end
  return sp and n or nil
end
local nsC = { Serialize = NS.Serialize, Chunk = NS.Chunk, Queue = NS.Queue, Model = M, id = id, fullName = id,
              me = function() return "Ann Essency" end, roster = function(n) return id(n) and {} or nil end,
              Sync = { OnOldPeer = function() olds = olds + 1 end } }
nsC.isSelf = function(s) return id(s) == "Ann Essency" end
local okLoad, errLoad = pcall(loadmod, "Comm.lua", nsC)
if okLoad and nsC.Comm then nsC.Comm.Init(function(tag, payload, sender) handled[#handled + 1] = { tag, payload, sender } end) end
CreateFrame, GetTime, C_ChatInfo, C_Timer = Gl.CreateFrame, Gl.GetTime, Gl.C_ChatInfo, Gl.C_Timer

local seq = 0
local function hear(v, sender, tag)
  seq = seq + 1
  local msg = string.format("p%d:1/1:", seq % 10) .. S.escape(S.encode({ v = v, t = tag or "H", p = { h = {} } }))
  frame.scripts.OnEvent(frame, "CHAT_MSG_ADDON", "GSquads", msg, "GUILD", sender)
end

test("proto3: Comm drops v = 1 / 2, counts each old identity once (any sender form) and says so once", function()
  ok(okLoad, "Comm.lua loads: " .. tostring(errLoad))
  local Comm = nsC.Comm
  eq(Comm.PROTO, 3, "Comm.PROTO")
  local n0, bad0 = #handled, Comm.stats.badProto
  hear(2, "Kas Pitas")
  hear(2, "Kas Pitas-CAMWOWEU4Realm6PvP")          -- the same character, roster form
  hear(1, "Kas Pitas")
  hear(2, "Kas Mora")                              -- another character (same first name)
  eq(#handled, n0, "no 1.x message reaches the handler")
  eq(Comm.stats.badProto, bad0 + 4, "all four counted as badProto")
  eq(Comm.OldPeerCount(), 2, "two old identities: Kas Pitas and Kas Mora")
  ok(Comm.oldPeers["Kas Pitas"] and Comm.oldPeers["Kas Mora"], "oldPeers is keyed by identity")
  eq(olds, 2, "Sync.OnOldPeer once per new old identity")
  hear(3, "Kas Mora")
  eq(#handled, n0 + 1, "a v = 3 message from the same member goes through")
  -- a newer protocol than ours is not an old version
  hear(4, "Zed Ruiz")
  eq(Comm.OldPeerCount(), 2, "v = 4 is not an old peer")
end)

-- the OLD_PEERS text names the 2.0 (§4.3), in both locales
test("proto3: OLD_PEERS says «older than 2.0» in esES and enUS", function()
  for _, file in ipairs({ "Locales/esES.lua", "Locales/enUS.lua" }) do
    local text = SOURCES[file]:match('\nL%.OLD_PEERS = "([^"]*)"')
    ok(text and text:find("2.0", 1, true) and text:find("%d", 1, true), file .. " OLD_PEERS names the 2.0: " .. tostring(text))
  end
end)

-------------------------------------------------------------------------------
-- 64-byte character names (§3 #23-24): 12 + 1 + 12 Cyrillic characters = 49 bytes survive every name field
local N49 = "Александрина Константинов"
local N65 = N49 .. string.rep("x", 16)
test("proto3: a 49-byte «Name Surname» survives every character-name field (caps 48 -> 64)", function()
  eq(#N49, 49, "the test name is 49 bytes")
  local function same(kind, d, field, list)
    local out = M.sanitize(kind, d)
    ok(out, kind .. " sanitized")
    local v = out[field]
    if list then v = v and v[1] end
    eq(v, N49, kind .. "." .. field)
  end
  same("squad", { captain = N49 }, "captain")
  same("squad", { members = { N49 } }, "members", true)
  same("squad", { bench = { N49 } }, "bench", true)
  same("squad", { xferFrom = N49 }, "xferFrom")
  same("reject", { name = N49 }, "name")
  same("roster", { main = { N49 } }, "main", true)
  same("roster", { bench = { N49 } }, "bench", true)
  same("roster", { owner = N49 }, "owner")
  same("rsvp", { name = N49 }, "name")
  same("attendance", { names = { N49 } }, "names", true)
  same("witness", { names = { N49 } }, "names", true)
  same("settings", { rlList = { N49 } }, "rlList", true)
  same("achgrant", { who = N49 }, "who")
  ok(#(M.sanitize("squad", { captain = N65 }).captain) == 64, "still capped at 64")
  -- progress events and race observations
  local Pg, Rc = NS.Progress, NS.Races
  local ev = Pg.sanitize({ t = "boss", who = N49, ts = NOW, sid = "s1", it = "raid", enc = 610, pres = { N49 } })
  ok(ev and ev.who == N49 and ev.pres and ev.pres[1] == N49, "progress who / pres")
  local ob = Rc.sanitize({ t = "kill", who = N49, by = N49, ts = NOW, inst = "x", it = "raid", enc = 1, pres = { N49 } })
  ok(ob and ob.who == N49 and ob.by == N49 and ob.pres[1] == N49, "race who / by / pres")
end)
