-- Comm.lua with mocked WoW API (nothing is sent during an encounter)
local sent, handled, clock = {}, {}, 0
local frame = { scripts = {} }
function frame:RegisterEvent() end
function frame:SetScript(k, fn) self.scripts[k] = fn end
CreateFrame = function() return frame end
GetTime = function() return clock end
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() return true end,
  SendAddonMessage = function(prefix, msg, channel) sent[#sent + 1] = { prefix, msg, channel }; return 0 end,
}
local ns = { Serialize = NS.Serialize, Chunk = NS.Chunk, Queue = NS.Queue }
loadmod("Comm.lua", ns)
local Comm = ns.Comm
Comm.Init(function(tag, payload, sender) handled[#handled + 1] = { tag, payload, sender } end)
local function tick(dt) clock = clock + dt; frame.scripts.OnUpdate(frame, dt) end

test("comm: queued during encounter, flushed after ENCOUNTER_END", function()
  frame.scripts.OnEvent(frame, "ENCOUNTER_START", 1, "Boss", 1, 5)
  Comm.Send("D", { note = string.rep("x", 600) })
  for _ = 1, 50 do tick(0.5) end
  eq(#sent, 0, "nothing sent during encounter")
  frame.scripts.OnEvent(frame, "ENCOUNTER_END", 1, "Boss", 1, 5, 1)
  for _ = 1, 20 do tick(0.5) end
  ok(#sent >= 3, "chunks sent after encounter: " .. #sent)
  for _, s in ipairs(sent) do eq(s[1], "GSquads"); eq(s[3], "GUILD"); ok(#s[2] <= 255) end
end)
test("comm: chat lockdown predicate blocks sending", function()
  local before = #sent
  C_ChatInfo.InChatMessagingLockdown = function() return true end
  Comm.Send("D", { a = 1 })
  for _ = 1, 10 do tick(0.5) end
  eq(#sent, before)
  C_ChatInfo.InChatMessagingLockdown = function() return false end
  for _ = 1, 10 do tick(0.5) end
  eq(#sent, before + 1)
end)
test("comm: receive path reassembles and checks protocol version", function()
  local n = #sent
  Comm.Send("R", { list = { "a|b", "c\nd" } })
  for _ = 1, 10 do tick(0.5) end
  for i = n + 1, #sent do frame.scripts.OnEvent(frame, "CHAT_MSG_ADDON", "GSquads", sent[i][2], "GUILD", "Bob-Realm") end
  local last = handled[#handled]
  eq(last[1], "R"); eq(last[2].list[2], "c\nd"); eq(last[3], "Bob-Realm")
  frame.scripts.OnEvent(frame, "CHAT_MSG_ADDON", "GSquads", "zz:1/1:" .. NS.Serialize.encode({ v = 99, t = "X" }), "GUILD", "Eve")
  eq(handled[#handled][1], "R", "wrong protocol ignored"); eq(Comm.stats.badProto, 1)
end)
-- v1.2 (BRO 7-nov 21:20): PROTO 2 cut 1.0.x / 1.1 off; 2.0 (SPEC-v2.0 §4): PROTO 3 cuts the 1.x off (v = 1 and 2 are
-- dropped and their senders counted; tests/proto3_spec.lua counts them per identity)
test("comm: the 2.0 speaks PROTO 3, drops v = 1 and counts the distinct old-version senders", function()
  eq(Comm.PROTO, 3)
  local n, bad = #handled, Comm.stats.badProto
  local old = NS.Serialize.encode({ v = 1, t = "H", p = { a = 1 } })
  frame.scripts.OnEvent(frame, "CHAT_MSG_ADDON", "GSquads", "zz:1/1:" .. old, "GUILD", "Old-Realm")
  frame.scripts.OnEvent(frame, "CHAT_MSG_ADDON", "GSquads", "zy:1/1:" .. old, "GUILD", "Old-Realm")
  frame.scripts.OnEvent(frame, "CHAT_MSG_ADDON", "GSquads", "zx:1/1:" .. old, "GUILD", "Older-Realm")
  eq(#handled, n, "v = 1 never reaches the handler"); eq(Comm.stats.badProto, bad + 3)
  eq(Comm.OldPeerCount(), 2, "two distinct members on an old version")
  -- a newer protocol is not an old version
  frame.scripts.OnEvent(frame, "CHAT_MSG_ADDON", "GSquads", "zw:1/1:" .. NS.Serialize.encode({ v = 4, t = "H" }), "GUILD", "New-Realm")
  eq(Comm.OldPeerCount(), 2)
end)
-- sec F7 / QA D6: the receiver drops any message of more than 64 parts (Chunk.lua), so the sender never queues one
test("comm: a message of more than 64 parts is never queued, and counted (sec F7)", function()
  local before = Comm.Pending()
  local r = Comm.Send("D", { note = string.rep("y", 255 * 70) })
  eq(r, false, "refused")
  eq(Comm.Pending(), before, "nothing queued")
  eq(Comm.stats.tooBig, 1, "counted")
  ok(Comm.Send("D", { note = string.rep("z", 255 * 30) }) ~= false, "a 30-part message still goes")
end)
