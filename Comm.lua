-- Guild Squads (MIT) - Comm.lua
-- Addon-channel transport: serialize -> escape -> chunk -> throttled queue -> SendAddonMessage.
-- Nothing is sent while an encounter / PvP match / M+ is running or chat is locked down.
local _, ns = ...
ns = ns or {}

local Comm = {}
ns.Comm = Comm
local S, C, Q = ns.Serialize, ns.Chunk, ns.Queue

Comm.PREFIX = "GSquads"
Comm.PROTO = 1
Comm.stats = { sent = 0, recv = 0, failed = 0, badProto = 0 }

local function now() return (GetTime and GetTime()) or 0 end

local function chatLocked()
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
    local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
    if ok and locked then return true end
  end
  local encFn = ((ns.encounterFn and ns.encounterFn()) or IsEncounterInProgress)
  if encFn then
    local ok, inProgress = pcall(encFn)
    if ok and inProgress then return true end
  end
  return false
end

-- Enum.SendAddonMessageResult. 11 = AddOnMessageLockdown -> pause the queue and keep the item;
-- permanent errors are dropped at once; only throttling / generic failures are retried.
Comm.LOCKDOWN = 11
local PERMANENT = { [1] = true, [2] = true, [4] = true, [6] = true, [7] = true, [10] = true, [12] = true }
Comm.lockUntil = nil
local function sentOk(item)
  if item.onSent then pcall(item.onSent) end
  return true
end
local restamp
local function rawSend(item)
  if item.stamp then restamp(item) end
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return sentOk(item) end
  local ok, res = pcall(C_ChatInfo.SendAddonMessage, Comm.PREFIX, item.msg, item.channel, item.target)
  -- Retail returns an Enum.SendAddonMessageResult (0 = success); older builds return a boolean.
  if ok and (res == nil or res == true or res == 0) then
    Comm.stats.sent = Comm.stats.sent + 1
    return sentOk(item)
  end
  if ok and res == Comm.LOCKDOWN then
    Comm.queue:setBlocked("lockdown", true)
    Comm.lockUntil = now() + 30
    Comm.stats.lockdowns = (Comm.stats.lockdowns or 0) + 1
    return false
  end
  if ok and PERMANENT[res] then
    Comm.stats.failed = Comm.stats.failed + 1
    if ns.debug then ns.debug("send failed (permanent " .. tostring(res) .. "), dropped") end
    return true
  end
  item.tries = (item.tries or 0) + 1
  if item.tries >= 5 then
    Comm.stats.failed = Comm.stats.failed + 1
    if ns.debug then ns.debug("send failed, dropped: " .. tostring(res)) end
    return true -- give up on this one so the queue does not stall
  end
  return false
end

Comm.queue = Q.new({ rate = 1, burst = 4, send = rawSend, isLocked = chatLocked })
Comm.assembler = C.newAssembler()

-- seeded per session so a /reload does not reuse the ids of half-received messages
local counter = math.floor(((GetTime and GetTime()) or 0) * 1000) % 1296
local function nextId()
  counter = (counter + 1) % 1296
  local digits = "0123456789abcdefghijklmnopqrstuvwxyz"
  local a, b = math.floor(counter / 36) + 1, (counter % 36) + 1
  return digits:sub(a, a) .. digits:sub(b, b)
end

-- every message carries `s` = sentAt, the server time when it really
-- leaves the queue (fixed 10-digit string, restamped on the first part right before SendAddonMessage). The body is
-- deterministic (keys sorted: p < s < t < v), so it is rebuilt around the stamp without re-encoding the payload.
local function serverNow()
  if type(GetServerTime) == "function" then
    local okT, v = pcall(GetServerTime)
    if okT and type(v) == "number" then return v end
  end
  return time and time() or 0
end
Comm.ServerNow = serverNow
local function stampOf(t) return string.format("%010d", math.max(0, math.floor(t or 0)) % 10000000000) end
function Comm.Body(tag, payload, at)
  local pre = S.encode({ p = payload })
  return pre:sub(1, -2) .. "s1:s" .. S.encode(stampOf(at)) .. "s1:t" .. S.encode(tag) .. "s1:v" .. S.encode(Comm.PROTO) .. "e"
end

-- number of <=255-byte parts a message takes (the queue sends 1 part per second): the GM's bulk estimate
function Comm.Parts(tag, payload) return #C.split(S.escape(Comm.Body(tag, payload, 0)), "zz") end

-- the first part of a message is restamped right before it leaves (same length: the other parts keep their split)
restamp = function(item)
  local m = item.stamp
  local okB, fresh = pcall(m.build, serverNow())
  if okB and #fresh == #m.items then for i, p in ipairs(fresh) do m.items[i].msg = p end end
end

-- Send a message table. channel "GUILD" (default) or "WHISPER" with target. onSent (optional) runs when the last
-- part has really left (claims are timed from that moment).
function Comm.Send(tag, payload, channel, target, onSent, urgent)
  -- an identical message still waiting in the queue (same payload, channel and target, e.g.
  -- the same record version published twice while comms are locked) is not queued again (the stamp is not part of
  -- the key)
  local ch = channel or "GUILD"
  local key = ch .. "|" .. tostring(target or "") .. "|" .. S.escape(S.encode({ v = Comm.PROTO, t = tag, p = payload }))
  if Comm.queue.pending and Comm.queue:pending(key) then
    Comm.queue.deduped = (Comm.queue.deduped or 0) + 1
    return false
  end
  local id = nextId()
  local pre = S.encode({ p = payload }):sub(1, -2)          -- snapshot: later changes to `payload` do not leak
  local tail = "s1:t" .. S.encode(tag) .. "s1:v" .. S.encode(Comm.PROTO) .. "e"
  local m = { items = {} }
  function m.build(at) return C.split(S.escape(pre .. "s1:s" .. S.encode(stampOf(at)) .. tail), id) end
  local parts = {}
  for i, part in ipairs(m.build(serverNow())) do
    local it = { msg = part, channel = ch, target = target }
    if i == 1 then it.stamp = m end
    m.items[i] = it
    parts[#parts + 1] = it
  end
  if onSent and #parts > 0 then parts[#parts].onSent = onSent end
  local okP = true
  if urgent and Comm.queue.pushMessageFront then okP = Comm.queue:pushMessageFront(parts, key)
  elseif Comm.queue.pushMessage then okP = Comm.queue:pushMessage(parts, key)
  else for _, item in ipairs(parts) do Comm.queue:push(item) end end
  if Comm.Wake then Comm.Wake() end
  return okP
end

function Comm.Pending() return Comm.queue:size() end

local BLOCK_ON = { ENCOUNTER_START = "encounter", PVP_MATCH_ACTIVE = "pvp", CHALLENGE_MODE_START = "mplus" }
local BLOCK_OFF = { ENCOUNTER_END = "encounter", PVP_MATCH_COMPLETE = "pvp", PVP_MATCH_INACTIVE = "pvp",
                    CHALLENGE_MODE_COMPLETED = "mplus", CHALLENGE_MODE_RESET = "mplus" }

-- accepted addon channels. GUILD (the server only delivers it to members), or WHISPER
-- from someone in our guild roster. PARTY/RAID/INSTANCE/CHANNEL and strangers' whispers are ignored.
function Comm.ChannelOk(channel, sender)
  if channel == "GUILD" then return true end
  if channel == "WHISPER" and type(sender) == "string" and ns.roster then
    local okR, r = pcall(ns.roster, sender)
    return okR and r ~= nil
  end
  return false
end

local lastGc = 0
function Comm.OnEvent(event, ...)
  if event == "CHAT_MSG_ADDON" then   -- drop stale half-received messages every 30 s of traffic
    local t = now()
    if t - lastGc > 30 then lastGc = t; C.gc(Comm.assembler, t) end
  end
  if BLOCK_ON[event] then
    Comm.queue:setBlocked(BLOCK_ON[event], true)
  elseif BLOCK_OFF[event] then
    Comm.queue:setBlocked(BLOCK_OFF[event], false)
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- zone change / reload: recompute the blocks from the client state instead of clearing them
    Comm.RecomputeBlocks()
  elseif event == "CHAT_MSG_ADDON" then
    local prefix, msg, channel, sender = ...
    if prefix ~= Comm.PREFIX or type(msg) ~= "string" or type(sender) ~= "string" then return end
    -- never index tables with Midnight secret values
    if issecretvalue and (issecretvalue(sender) or issecretvalue(msg)) then return end
    if ns.isSelf and ns.isSelf(sender) then return end
    -- only the GUILD channel, or a WHISPER from a member of the guild roster
    if not Comm.ChannelOk(channel, sender) then Comm.stats.badChannel = (Comm.stats.badChannel or 0) + 1; return end
    local full = C.feed(Comm.assembler, sender, msg, now())
    if not full then return end
    local ok, data = S.decode(S.unescape(full))
    if not ok or type(data) ~= "table" then return end
    if data.v ~= Comm.PROTO then Comm.stats.badProto = Comm.stats.badProto + 1; return end
    Comm.stats.recv = Comm.stats.recv + 1
    -- a broken payload never raises inside CHAT_MSG_ADDON
    if Comm.handler then
      local sentAt = type(data.s) == "string" and tonumber(data.s) or nil   -- absent from older clients
      local okH = pcall(Comm.handler, data.t, data.p, sender, channel, sentAt)
      if not okH then Comm.stats.handlerErrors = (Comm.stats.handlerErrors or 0) + 1 end
    end
  end
end

local function apiTrue(fn)
  if type(fn) ~= "function" then return false end
  local ok, v = pcall(fn)
  return ok and v and true or false
end
function Comm.RecomputeBlocks()
  Comm.queue:setBlocked("encounter", apiTrue(((ns.encounterFn and ns.encounterFn()) or IsEncounterInProgress)))
  Comm.queue:setBlocked("pvp", apiTrue(C_PvP and C_PvP.IsMatchActive))
  Comm.queue:setBlocked("mplus", apiTrue(C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive))
end

local EVENTS = { "CHAT_MSG_ADDON", "ENCOUNTER_START", "ENCOUNTER_END", "PVP_MATCH_ACTIVE", "PVP_MATCH_COMPLETE",
                 "PVP_MATCH_INACTIVE", "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET",
                 "PLAYER_ENTERING_WORLD" }

function Comm.Init(handler)
  Comm.handler = handler
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, Comm.PREFIX)
  end
  local f = CreateFrame("Frame")
  for _, ev in ipairs(EVENTS) do pcall(f.RegisterEvent, f, ev) end -- unknown events are skipped
  f:SetScript("OnEvent", function(_, ev, ...) Comm.OnEvent(ev, ...) end)
  -- with C_Timer the queue runs on a 0.2 s ticker that only exists while something is pending
  -- (Comm.Wake on every Send) and is cancelled when the queue is empty; without C_Timer the old OnUpdate stays.
  -- Half-received chunks are collected on incoming traffic (Comm.OnEvent) instead of on a timer.
  local function step()
    if Comm.lockUntil and now() >= Comm.lockUntil then Comm.lockUntil = nil; Comm.queue:setBlocked("lockdown", false) end
    Comm.queue:pump(now())
  end
  local ticker
  if C_Timer and type(C_Timer.NewTicker) == "function" then
    function Comm.Wake()
      if ticker then return end
      local okT, t = pcall(C_Timer.NewTicker, 0.2, function()
        step()
        if Comm.queue:size() == 0 and not Comm.lockUntil and ticker then ticker:Cancel(); ticker = nil end
      end)
      if okT then ticker = t end
    end
    function Comm.Ticking() return ticker ~= nil end
  else
    local acc = 0
    f:SetScript("OnUpdate", function(_, elapsed)
      acc = acc + (elapsed or 0)
      if acc < 0.2 then return end
      acc = 0
      step()
    end)
    function Comm.Wake() end
    function Comm.Ticking() return true end
  end
  Comm.frame = f
end

return Comm
