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
