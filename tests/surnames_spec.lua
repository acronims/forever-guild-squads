-- WoW Forever surnames. GetGuildRosterInfo returns "Fire Essency"
-- (character + space + surname) while UnitName("player") is "Fire": the roster cache must be keyed by the
-- character name so ns.me() is found and writes are not refused with "notInGuild".
-- Own environment per case (strict fake of the 16001 API, same builder as zzcold_spec).
local LUA = { "assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select", "setmetatable",
              "getmetatable", "rawget", "rawset", "rawequal", "tonumber", "tostring", "type", "string", "table",
              "math", "os", "coroutine" }

local function cold081(opts)
  local inGuild = true
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
  env.GetNormalizedRealmName = function() return opts.realm or "ClassicBetaPvE" end
  env.GetCursorPosition = function() return 300, 300 end
  env.GetZoneText, env.GetSubZoneText, env.GetRealZoneText = function() return "Durotar" end, function() return "" end, function() return "Durotar" end
  env.UnitName = function() return opts.me or "Fire" end
  env.UnitClass = function() return "Warrior", "WARRIOR" end
  env.UnitLevel = function() return 20 end
  env.UnitRace = function() return "Orc", "Orc" end
  env.UnitFactionGroup = function() return "Horde" end
  env.InCombatLockdown = function() return false end
  env.IsInGroup, env.IsInRaid, env.IsInInstance = function() return false end, function() return false end, function() return false end
  env.GetNumGroupMembers = function() return 0 end
  env.IsInGuild = function() return inGuild end
  env.GetGuildInfo = function() if inGuild then return "Por Honor", "Member", 4, opts.realm or "ClassicBetaPvE" end return nil end
  local roster = opts.roster
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

local function run081(opts)
  local env, printed, scripts = cold081(opts)
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
  return ns, env, out, printed
end

-- a real client, 1.60.1 build 70450: rank 4, surname "Essency", realm ClassicBetaPvE
local function fireRoster()
  return { { "Fire Essency", "Member", 4, 20, "Warrior", "Durotar", "", "", true, 0, "WARRIOR" },
           { "Gm-ClassicBetaPvE", "GM", 0, 22, "Priest", "Durotar", "", "", false, 0, "PRIEST" } }
end

test("surname in the roster ('Fire Essency', rank 4) + UnitName 'Fire': save profile and create a squad", function()
  local ns = run081({ roster = fireRoster(), me = "Fire" })
  ok(ns.rosterReady, "roster read")
  eq(ns.me(), "Fire-ClassicBetaPvE", "my key")
  local okP, whyP = ns.Actions.SaveProfile({ role = "TANK" })
  ok(okP, "save profile: " .. tostring(whyP))
  ok(ns.roster(ns.me()) ~= nil, "I am in the roster cache")
  eq(ns.state.profiles[ns.me()].d.role, "TANK", "profile stored under my key")
  local okS, whyS = ns.Actions.CreateSquad({ name = "Los Fuegos", tags = {} })
  ok(okS, "create squad: " .. tostring(whyS))
  local sid = ns.Actions.MySquadId()
  ok(sid and ns.state.squads[sid] and ns.state.squads[sid].d.captain == "Fire-ClassicBetaPvE", "I captain the new squad")
end)

test("M.charName: the 4 surname formats + no surname (no regression)", function()
  local M = NS.Model
  local cases = {
    { "Fire Essency", "Fire-Home", "Essency" },
    { "Fire-Reino", "Fire-Reino", nil },
    { "Fire Essency-Reino", "Fire-Reino", "Essency" },
    { "Fire-Reino Essency", "Fire-Reino", "Essency" },
    { "Fire", "Fire-Home", nil },
    { "Ñandú Ébano", "Ñandú-Home", "Ébano" },     -- non-ASCII: split on the plain space, not on %s
  }
  for _, c in ipairs(cases) do
    local key, surname = M.charName(c[1], "Home")
    eq(key, c[2], "key of '" .. c[1] .. "'")
    eq(surname, c[3], "surname of '" .. c[1] .. "'")
  end
  eq(M.charName("", "Home"), nil, "empty")
  eq(M.charName(nil, "Home"), nil, "nil")
  eq(M.charName(" Essency", "Home"), nil, "no character name")
end)

test("glue: the 4 formats and a plain name key the roster like ns.fullName(UnitName) and senders", function()
  local roster = {
    { "Fire Essency", "Member", 4, 20, "Warrior", "Durotar", "", "", true, 0, "WARRIOR" },
    { "Ann-ClassicBetaPvE", "GM", 0, 22, "Priest", "Durotar", "", "", true, 0, "PRIEST" },
    { "Bob Stone-OtherRealm", "Member", 5, 22, "Priest", "Durotar", "", "", true, 0, "PRIEST" },
    { "Cid-OtherRealm Oak", "Member", 5, 22, "Priest", "Durotar", "", "", false, 0, "PRIEST" },
    { "Dee", "Member", 6, 22, "Priest", "Durotar", "", "", false, 0, "PRIEST" },
  }
  local ns = run081({ roster = roster, me = "Fire" })
  local list = ns.rosterList()
  eq(list["Fire-ClassicBetaPvE"].rank, 4); eq(list["Fire-ClassicBetaPvE"].surname, "Essency")
  eq(list["Ann-ClassicBetaPvE"].rank, 0); eq(list["Ann-ClassicBetaPvE"].surname, nil)
  eq(list["Bob-OtherRealm"].surname, "Stone"); eq(list["Cid-OtherRealm"].surname, "Oak")
  eq(list["Dee-ClassicBetaPvE"].rank, 6)
  local n = 0
  for k in pairs(list) do n = n + 1; ok(not k:find(" ", 1, true), "no space in key " .. k) end
  eq(n, 5, "5 entries")
  ok(ns.roster(ns.fullName("Bob-OtherRealm")), "addon sender (no surname) found")
  ok(ns.roster("Dee"), "bare name found")
  eq(ns.displayName("Fire-ClassicBetaPvE"), "Fire Essency", "display with surname")
  eq(ns.displayName("Ann-ClassicBetaPvE"), "Ann", "display without surname")
  eq(ns.charKey("Fire Essency"), "Fire-ClassicBetaPvE", "typed name with surname -> character key")
end)

test("honest error: roster ready and I am missing -> new text; roster not ready -> old text", function()
  local ns = run081({ roster = { { "Gm-ClassicBetaPvE", "GM", 0, 22, "Priest", "Durotar", "", "", true, 0, "PRIEST" },
                                 { "Bob-ClassicBetaPvE", "Member", 4, 22, "Priest", "Durotar", "", "", true, 0, "PRIEST" } },
                      me = "Fire" })
  ok(ns.rosterReady, "roster read")
  local okP, why = ns.Actions.SaveProfile({ role = "TANK" })
  ok(not okP and why == "notInGuild", "write refused: " .. tostring(why))
  local text = ns.ErrText("notInGuild")
  eq(text, ns.L.ERR_notInRoster:format("Fire-ClassicBetaPvE", 2))
  ok(text:find("Fire-ClassicBetaPvE", 1, true) and text:find("(2 members)", 1, true) and text:find("/gsq diag", 1, true), text)
  ok(not text:find("not loaded", 1, true), "does not blame the roster load")
  ns.rosterReady = false
  eq(ns.ErrText("notInGuild"), ns.L.ERR_notInGuild, "roster really not ready -> old text")
  ns.rosterReady = true
  eq(ns.ErrText("rank"), ns.L.ERR_rank, "other codes untouched")
  ok(rawget(ns.L, "ERR_notInRoster"), "enUS key")
end)

test("honest error in esES", function()
  local env = cold081({ roster = {} })
  local ns = {}
  for _, f in ipairs({ "Locales/enUS.lua", "Locales/esES.lua" }) do
    env.GetLocale = function() return "esES" end
    load(SOURCES[f], "@" .. f, "t", env)("GuildSquads", ns)
  end
  ok(rawget(ns.L, "ERR_notInRoster"):find("no aparece en la lista de la guild", 1, true), "esES text")
end)

test("/gsq diag: [roster] me=<key> found=<yes/no> entries=<n> surnames=<n>", function()
  local _, _, out = run081({ roster = fireRoster(), me = "Fire" })
  ok(out:find("[roster] me=Fire-ClassicBetaPvE found=yes entries=2 surnames=1", 1, true), out)
  local _, _, out2 = run081({ roster = { { "Gm-ClassicBetaPvE", "GM", 0, 22, "Priest", "Durotar", "", "", true, 0, "PRIEST" } }, me = "Fire" })
  ok(out2:find("[roster] me=Fire-ClassicBetaPvE found=no entries=1 surnames=0", 1, true), out2)
end)
