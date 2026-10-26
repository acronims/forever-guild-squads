-- cold load: fresh install, no SavedVariables. Each case gets its OWN environment (not the shared
-- globals zload_spec leaves behind) with only a strict fake of the 16001 API: a global the addon calls without a
-- guard and that this fake does not define fails the test. Globals 16001 dropped (IsEncounterInProgress,
-- SendChatMessage, GuildRoster, GetAddOnMetadata, ChatFrame_OpenChat, RaidNotice_AddMessage, UnitPVPRank...)
-- are deliberately absent. Fires ADDON_LOADED, PLAYER_LOGIN, GUILD_ROSTER_UPDATE, then /gsq diag.
-- Limits: frames are permissive stubs; this proves "no Lua error on load", not how the client renders.
local LUA = { "assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select", "setmetatable",
              "getmetatable", "rawget", "rawset", "rawequal", "tonumber", "tostring", "type", "string", "table",
              "math", "os", "coroutine" }

local function coldEnv(inGuild)
  local env = {}
  for _, k in ipairs(LUA) do env[k] = _G[k] end
  env._G = env
  env.unpack = table.unpack
  env.tinsert, env.tremove, env.wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
  env.strsplit = function(sep, s) local out = {} for p in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = p end return table.unpack(out) end
  env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  env.date, env.time = os.date, os.time
  local printed, scripts, errors = {}, {}, {}
  env.print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end printed[#printed + 1] = table.concat(t, " ") end
  local stub
  stub = function()
    return setmetatable({}, { __index = function(t, k)
      if k == "SetScript" or k == "HookScript" then
        return function(self, ev, fn) scripts[#scripts + 1] = { self, ev, fn }; rawset(self, "_" .. ev, fn) end
      end
      if k == "GetScript" then return function(self, ev) return rawget(self, "_" .. ev) end end
      if k == "GetText" then return function() return "" end end
      if k == "IsShown" or k == "GetChecked" or k == "IsMouseOver" then return function() return false end end
      if k == "IsEnabled" then return function() return true end end
      if k == "GetCenter" then return function() return 500, 400 end end
      if type(k) == "string" and (k:match("^Get") ) then return function() return 10 end end
      if type(k) ~= "string" or not k:match("^[A-Z]") then return nil end
      local f = function() return stub() end
      rawset(t, k, f)
      return f
    end })
  end
  env.CreateFrame = function(_, name) local f = stub(); if name then env[name] = f end return f end
  env.UIParent, env.ChatFontNormal, env.GameTooltip, env.Minimap = stub(), stub(), stub(), stub()
  env.UIErrorsFrame, env.RaidWarningFrame, env.DEFAULT_CHAT_FRAME = stub(), stub(), stub()
  env.UISpecialFrames, env.StaticPopupDialogs, env.SlashCmdList = {}, {}, {}
  env.StaticPopup_Show = function() end
  env.ChatTypeInfo = { RAID_WARNING = { r = 1, g = 0.3, b = 0.1 } }
  env.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
  env.CLASS_SORT_ORDER = { "WARRIOR" }
  env.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior" }
  env.Mixin = function(o, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do o[k] = v end end return o end
  local clock = 100
  env.GetTime = function() return clock end
  env.GetServerTime = function() return 1000000 + clock end
  env.GetBuildInfo = function() return "1.60.1", "70338", "Oct 1 2026", 16001 end
  env.GetLocale = function() return "enUS" end
  env.GetNormalizedRealmName = function() return "Realm" end
  env.GetCursorPosition = function() return 300, 300 end
  env.GetZoneText, env.GetSubZoneText, env.GetRealZoneText = function() return "Durotar" end, function() return "" end, function() return "Durotar" end
  env.UnitName = function() return "Ann" end
  env.UnitClass = function() return "Warrior", "WARRIOR" end
  env.UnitLevel = function() return 20 end
  env.UnitRace = function() return "Orc", "Orc" end
  env.UnitFactionGroup = function() return "Horde" end
  env.InCombatLockdown = function() return false end
  env.IsInGroup, env.IsInRaid, env.IsInInstance = function() return false end, function() return false end, function() return false end
  env.GetNumGroupMembers = function() return 0 end
  env.IsInGuild = function() return inGuild end
  env.GetGuildInfo = function() if inGuild then return "Horda Fiel", "GM", 0, "Realm" end return nil end
  local roster = { { "Ann-Realm", "GM", 0, 20, "Warrior", "Durotar", "", "", true, 0, "WARRIOR" },
                   { "Bob-Realm", "Member", 4, 22, "Priest", "Durotar", "", "", true, 0, "PRIEST" } }
  env.GetNumGuildMembers = function() if inGuild then return #roster, #roster end return 0, 0 end
  env.GetGuildRosterInfo = function(i) if inGuild and roster[i] then return table.unpack(roster[i]) end return nil end
  env.GuildControlGetNumRanks = function() return inGuild and 5 or 0 end
  env.GuildControlGetRankName = function(i) return "Rank" .. tostring(i) end
  env.C_GuildInfo = { GuildRoster = function() end }
  env.C_AddOns = { GetAddOnMetadata = function() return "1.0.0" end }
  env.C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end, SendAddonMessage = function() return 0 end,
                     InChatMessagingLockdown = function() return false end, SendChatMessage = function() end }
  env.C_InstanceEncounter = { IsEncounterInProgress = function() return false end }
  env.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
  env.C_Texture = { GetAtlasInfo = function() return nil end }
  env.C_PartyInfo = { InviteUnit = function() end, ConvertToRaid = function() end }
  env.issecretvalue = function() return false end
  env.GuildSquadsDB = nil -- fresh install: the client leaves the SavedVariable nil
  return env, printed, scripts, errors
end

local function coldRun(inGuild)
  local env, printed, scripts = coldEnv(inGuild)
  local ns, toc = {}, {}
  for line in SOURCES["GuildSquads.toc"]:gmatch("[^\r\n]+") do
    if line:match("%.lua$") then toc[#toc + 1] = (line:gsub("\\", "/")) end
  end
  for _, f in ipairs(toc) do
    local chunk, err = load(SOURCES[f], "@" .. f, "t", env)
    if not chunk then error("parse " .. f .. ": " .. tostring(err)) end
    local okL, errL = pcall(chunk, "GuildSquads", ns)
    if not okL then error("load " .. f .. ": " .. tostring(errL)) end
  end
  local function fire(ev, ...)
    for _, s in ipairs(scripts) do
      if s[2] == "OnEvent" then
        local okE, errE = pcall(s[3], s[1], ev, ...)
        if not okE then error(ev .. ": " .. tostring(errE)) end
      end
    end
  end
  fire("ADDON_LOADED", "GuildSquads")
  ok(type(env.GuildSquadsDB) == "table", "ADDON_LOADED creates GuildSquadsDB from nothing")
  fire("PLAYER_LOGIN")
  fire("GUILD_ROSTER_UPDATE")
  ok(type(env.SlashCmdList.GUILDSQUADS) == "function", "/gsq registered")
  local shown
  if ns.UI then
    local orig = ns.UI.ShowExport
    ns.UI.ShowExport = function(text, ...) shown = text; if orig then return orig(text, ...) end end
  end
  local before = #printed
  local okD, errD = pcall(env.SlashCmdList.GUILDSQUADS, "diag")
  ok(okD, "/gsq diag: " .. tostring(errD))
  local out = shown or table.concat(printed, "\n", before + 1)
  ok(type(out) == "string" and #out > 20, "/gsq diag produced output (" .. tostring(out and #out) .. " chars)")
  return ns, env, out
end

test("cold load, no SavedVariables, NOT in a guild: TOC + ADDON_LOADED/PLAYER_LOGIN/GUILD_ROSTER_UPDATE + /gsq diag", function()
  local ns, env = coldRun(false)
  ok(ns.guildKey == nil, "no guild key outside a guild")
  ok(type(env.GuildSquadsDB) == "table", "SavedVariables created")
end)

test("cold load, no SavedVariables, IN a guild: TOC + ADDON_LOADED/PLAYER_LOGIN/GUILD_ROSTER_UPDATE + /gsq diag", function()
  local ns, _, out = coldRun(true)
  ok(ns.rosterReady, "GUILD_ROSTER_UPDATE read the roster")
  ok(ns.guildKey ~= nil, "guild key set in a guild")
  ok(out:find("16001", 1, true) or out:find("1.60.1", 1, true), "diag report carries the client build")
end)

test("ns.apiFn resolves globals and dotted paths, nil when missing", function()
  local env = coldEnv(true)
  local ns = {}
  local chunk = load(SOURCES["Core/Serialize.lua"], "@Core/Serialize.lua", "t", env)
  chunk("GuildSquads", ns)
  ok(ns.apiFn("NoSuchApi", "C_InstanceEncounter.IsEncounterInProgress") == env.C_InstanceEncounter.IsEncounterInProgress, "dotted fallback")
  ok(ns.apiFn("NoSuchApi", "C_Nope.Fn") == nil, "nil when missing")
  ok(ns.encounterFn() == env.C_InstanceEncounter.IsEncounterInProgress, "encounter fallback")
end)
