-- Guild Squads simulator: fake WoW API for ONE client (one fengari state per client).
-- Derived from the permissive stub of tests/zload_spec.lua (frames are stubs whose unknown methods return stubs),
-- plus what a multi-client run needs: a real event registry, C_Timer driven by the simulated clock, a guild
-- roster fed by the driver, group/instance state, an addon-message outbox and a guild-chat outbox.
-- The driver (tests/sim/sim.js) sets SIM_* globals, calls SIM_step(t), SIM_fire(ev, ...), SIM_pop() etc.
local CFG = SIM_CFG            -- { name, realm, guild, skew, epoch, uptime0 }
SIM_T = SIM_T or 0             -- simulated seconds since the start of the run (shared by every client)
SIM_ERRORS = {}                -- Lua errors caught by the fake (event handlers, timers) and by ns.debug
local function err(where, e) SIM_ERRORS[#SIM_ERRORS + 1] = where .. ": " .. tostring(e) end

local events, onUpdate = {}, {}
local stub
local function child(self) local c = stub(); rawset(c, "_parent", self); return c end
stub = function()
  local s = {}
  return setmetatable(s, { __index = function(t, k)
    if k == "CreateFontString" or k == "CreateTexture" or k == "CreateMaskTexture" then return child end
    if k == "GetText" then return function() return "" end end
    if k == "GetChecked" or k == "IsShown" or k == "IsMouseOver" or k == "IsVisible" then return function() return false end end
    if k == "IsEnabled" then return function() return true end end
    if k == "GetWidth" or k == "GetStringWidth" then return function() return 100 end end
    if k == "GetHeight" then return function() return 20 end end
    if k == "GetEffectiveScale" then return function() return 1 end end
    if k == "GetNumPoints" or k == "GetFrameLevel" then return function() return 1 end end
    if k == "GetCenter" then return function() return 500, 400 end end
    if k == "RegisterEvent" then return function(self, ev) events[ev] = events[ev] or {}; events[ev][self] = true end end
    if k == "UnregisterEvent" then return function(self, ev) if events[ev] then events[ev][self] = nil end end end
    if k == "UnregisterAllEvents" then return function(self) for _, set in pairs(events) do set[self] = nil end end end
    if k == "GetScript" then return function(self, ev) return rawget(self, "_" .. ev) end end
    if k == "SetScript" or k == "HookScript" then
      return function(self, ev, fn)
        rawset(self, "_" .. ev, fn)
        if ev == "OnUpdate" then onUpdate[self] = fn end
      end
    end
    if type(k) ~= "string" or not k:match("^[A-Z]") then return nil end
    local f = function() return stub() end
    rawset(t, k, f)
    return f
  end })
end
CreateFrame = function(_, name) local f = stub(); if name then _G[name] = f end return f end
UIParent, ChatFontNormal, UISpecialFrames, GameTooltip, Minimap = stub(), stub(), {}, stub(), stub()
RaidWarningFrame, UIErrorsFrame = stub(), stub()
ChatTypeInfo = { RAID_WARNING = { r = 1, g = 0.3, b = 0.1 } }
RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PRIEST = { r = 1, g = 1, b = 1 }, MAGE = { r = 0.4, g = 0.8, b = 1 } }
StaticPopupDialogs = {}
StaticPopup_Show = function() end
tinsert, tremove = table.insert, table.remove
print = function() end
SlashCmdList = {}
C_Texture = { GetAtlasInfo = function() return nil end }

-- clock: GetTime = client uptime, GetServerTime = epoch + run time + this client's skew
local loginAt = SIM_T
GetTime = function() return CFG.uptime0 + (SIM_T - loginAt) end
GetServerTime = function() return math.floor(CFG.epoch + SIM_T + (CFG.skew or 0)) end
time = function() return GetServerTime() end
date = function(fmt, t) return os.date(fmt, t) end
GetLocale = function() return CFG.locale or "esES" end
GetNormalizedRealmName = function() return CFG.realm end
GetRealmName = GetNormalizedRealmName
GetCursorPosition = function() return 300, 300 end
GetZoneText = function() return SIM_ZONE or "Los Baldíos" end
GetSubZoneText = function() return "" end
GetRealZoneText = GetZoneText
UnitName = function(unit)
  if unit == "player" then return CFG.name end
  local i = type(unit) == "string" and tonumber(unit:match("^party(%d)$"))
  if i and SIM_GROUP and not SIM_GROUP.raid then
    local others = {}
    for _, n in ipairs(SIM_GROUP) do if n ~= CFG.name .. "-" .. CFG.realm then others[#others + 1] = n end end
    local n = others[i]
    if n then local s, r = n:match("^([^-]+)-(.+)$"); return s, r end
  end
  return nil
end
UnitClass = function() return "Warrior", "WARRIOR" end
UnitLevel = function() return SIM_LEVEL or 20 end
UnitRace = function() return "Human", "Human" end
UnitFactionGroup = function() return "Alliance" end
InCombatLockdown = function() return false end

-- guild roster (driver writes SIM_ROSTER = { {name, rankIndex, level, classFile, online}, ... })
IsInGuild = function() return CFG.guild ~= nil end
GetGuildInfo = function() if CFG.guild then return CFG.guild, "Rank", 0, CFG.realm end return nil end
GetNumGuildMembers = function() return CFG.guild and #(SIM_ROSTER or {}) or 0 end
GetGuildRosterInfo = function(i)
  local r = SIM_ROSTER[i]
  if not r then return nil end
  return r[1], "R" .. r[2], r[2], r[3], "Warrior", "Los Baldíos", "", "", r[5], 0, r[4]
end
GetGuildRosterLastOnline = function() return 0, 0, 1, 0 end
GuildControlGetNumRanks = function() return 10 end
GuildControlGetRankName = function(i) return "R" .. tostring(i) end
C_GuildInfo = { GuildRoster = function() SIM_ROSTER_REQ = true end }

-- group / instance: SIM_GROUP = { raid = bool, "Name-Realm", ... }, SIM_INST = { name, type, diff, id }
IsInGroup = function() return SIM_GROUP ~= nil and #SIM_GROUP > 1 end
IsInRaid = function() return SIM_GROUP ~= nil and SIM_GROUP.raid == true end
GetNumGroupMembers = function() return SIM_GROUP and #SIM_GROUP or 0 end
GetRaidRosterInfo = function(i)
  local n = SIM_GROUP and SIM_GROUP[i]
  if not n then return nil end
  return n, (i == 1) and 2 or 0, math.floor((i - 1) / 5) + 1, 60, "Warrior", "WARRIOR", "", true
end
local function inGroupShort(n)
  if not SIM_GROUP or type(n) ~= "string" then return false end
  for _, g in ipairs(SIM_GROUP) do if g == n or g:match("^([^-]+)") == n then return true end end
  return false
end
UnitInRaid = function(n) return (SIM_GROUP and SIM_GROUP.raid and inGroupShort(n)) and 1 or nil end
UnitInParty = function(n) return (SIM_GROUP and not SIM_GROUP.raid and inGroupShort(n)) and true or false end
UnitIsGroupLeader = function() return SIM_GROUP ~= nil and SIM_GROUP[1] == CFG.name .. "-" .. CFG.realm end
UnitIsGroupAssistant = function() return false end
IsInInstance = function() if SIM_INST then return true, SIM_INST[2] end return false, "none" end
GetInstanceInfo = function()
  if SIM_INST then return SIM_INST[1], SIM_INST[2], SIM_INST[3] or 1, "", 10, 0, false, SIM_INST[4] or 0 end
  return "Kalimdor", "none", 0, "", 0, 0, false, 1
end
IsEncounterInProgress = function() return SIM_ENCOUNTER == true end
C_PvP = { IsMatchActive = function() return SIM_BG == true end, GetActiveMatchWinner = function() return nil end }
GetPVPLifetimeStats = function() return SIM_HK or 0, 0, 0 end
GetPVPSessionStats = function() return 0, 0 end
C_PartyInfo = { InviteUnit = function(n) SIM_INVITED = SIM_INVITED or {}; SIM_INVITED[#SIM_INVITED + 1] = n end, ConvertToRaid = function() end }
InviteUnit = C_PartyInfo.InviteUnit

-- addon messages: outbox drained by the driver; the driver decides throttle (returns 3) and lockdown
SIM_OUT, SIM_CHAT = {}, {}
SIM_SENDRESULT = nil           -- driver may force a result code for the next sends (nil = ask SIM_canSend)
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() return true end,
  InChatMessagingLockdown = function() return SIM_ENCOUNTER == true or SIM_BG == true end,
  SendAddonMessage = function(prefix, msg, channel, target)
    if SIM_ENCOUNTER or SIM_BG then return 11 end
    local res = SIM_canSend and SIM_canSend(prefix) or 0
    if res ~= 0 then return res end
    SIM_OUT[#SIM_OUT + 1] = { prefix, msg, channel, target or "" }
    return 0
  end,
}
SendChatMessage = function(text, channel) SIM_CHAT[#SIM_CHAT + 1] = { tostring(text), tostring(channel) } end

-- timers on the simulated clock
local timers, tseq = {}, 0
local function addTimer(at, fn, period, iter)
  tseq = tseq + 1
  local t = { at = at, fn = fn, period = period, iter = iter, seq = tseq }
  timers[#timers + 1] = t
  return t
end
C_Timer = {
  After = function(d, fn) addTimer(GetTime() + math.max(0, d or 0), fn) end,
  NewTicker = function(p, fn, n)
    local t = addTimer(GetTime() + p, fn, p, n)
    return { Cancel = function() t.cancelled = true end, IsCancelled = function() return t.cancelled end }
  end,
  NewTimer = function(d, fn)
    local t = addTimer(GetTime() + d, fn)
    return { Cancel = function() t.cancelled = true end }
  end,
}
-- earliest due timer, in run seconds (nil = none)
function SIM_next()
  local best
  for _, t in ipairs(timers) do
    if not t.cancelled and (not best or t.at < best) then best = t.at end
  end
  if not best then return nil end
  return best - CFG.uptime0 + loginAt
end
local lastStep = SIM_T
function SIM_step(t)
  SIM_T = t
  for _ = 1, 10000 do
    local due, idx
    for i, tm in ipairs(timers) do
      if not tm.cancelled and tm.at <= GetTime() + 1e-9 and (not due or tm.at < due.at or (tm.at == due.at and tm.seq < due.seq)) then due, idx = tm, i end
    end
    if not due then break end
    if due.period and not due.cancelled and (due.iter == nil or due.iter > 1) then
      due.at = due.at + due.period
      if due.iter then due.iter = due.iter - 1 end
    else
      table.remove(timers, idx)
    end
    local okT, e = pcall(due.fn, due.period and { Cancel = function() due.cancelled = true end } or nil)
    if not okT then err("timer", e) end
  end
  for i = #timers, 1, -1 do if timers[i].cancelled then table.remove(timers, i) end end
  local elapsed = t - lastStep
  lastStep = t
  if elapsed > 0 then
    for f, fn in pairs(onUpdate) do
      if rawget(f, "_OnUpdate") == fn then local okU, e = pcall(fn, f, elapsed); if not okU then err("OnUpdate", e) end
      else onUpdate[f] = nil end
    end
  end
end
function SIM_fire(ev, ...)
  local list = {}
  for f in pairs(events[ev] or {}) do list[#list + 1] = f end
  for _, f in ipairs(list) do
    local fn = rawget(f, "_OnEvent")
    if fn then local okE, e = pcall(fn, f, ev, ...); if not okE then err("event " .. ev, e) end end
  end
end
function SIM_pop()
  local m = table.remove(SIM_OUT, 1)
  if not m then return nil end
  return m[1], m[2], m[3], m[4]
end
function SIM_popChat()
  local m = table.remove(SIM_CHAT, 1)
  if not m then return nil end
  return m[1], m[2]
end

-- SavedVariables: plain Lua literal of GuildSquadsDB (numbers with %.17g, strings with %q)
local function ser(v, out)
  local tv = type(v)
  if tv == "table" then
    out[#out + 1] = "{"
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
      if type(a) == type(b) then return a < b end
      return type(a) < type(b)
    end)
    for _, k in ipairs(keys) do
      if type(k) == "number" or type(k) == "string" then
        out[#out + 1] = "["; ser(k, out); out[#out + 1] = "]="; ser(v[k], out); out[#out + 1] = ","
      end
    end
    out[#out + 1] = "}"
  elseif tv == "string" then out[#out + 1] = string.format("%q", v)
  elseif tv == "number" then
    if v ~= v then out[#out + 1] = "(0/0)" elseif v == math.huge then out[#out + 1] = "math.huge"
    elseif v == -math.huge then out[#out + 1] = "-math.huge"
    elseif math.type and math.type(v) == "integer" then out[#out + 1] = string.format("%d", v)
    else out[#out + 1] = string.format("%.17g", v) end
  elseif tv == "boolean" then out[#out + 1] = tostring(v)
  else out[#out + 1] = "nil" end
end
function SIM_saveVars()
  local out = { "return " }
  ser(GuildSquadsDB, out)
  return table.concat(out)
end
SIM_ser = ser
