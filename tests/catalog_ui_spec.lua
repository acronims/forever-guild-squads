-- GM catalog: UI / glue tests in a cold 16001 client (same builder as pvp_rank_spec, plus
-- visibility recording on the stub frames): achievements strip, bulk through the throttled queue, Ajustes >
-- Logros only for the GM (a member sees the GM's names and not what is disabled), /gsq diag catalog line.
-- Fake API only: it says nothing about how the real client renders.
local LUA = { "assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select", "setmetatable",
              "getmetatable", "rawget", "rawset", "rawequal", "tonumber", "tostring", "type", "string", "table",
              "math", "os", "coroutine" }

local function cold10(opts)
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
      if k == "GetFontString" then return function() return nil end end
      if k == "SetShown" then return function(self, v) rawset(self, "_vis", v and true or false) end end
      if k == "Show" then return function(self) rawset(self, "_vis", true) end end
      if k == "Hide" then return function(self) rawset(self, "_vis", false) end end
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
  if opts.pvpRank then -- clients with the classic honor rank API (not WoW Forever 1.60.1)
    env.UnitPVPRank = function() return opts.pvpRank end
    env.GetPVPRankInfo = function(id) return "Rank", id - 4 end
  end
  env.GuildSquadsDB = nil -- fresh install: the client leaves the SavedVariable nil
  return env, printed, scripts, errors
end

local function run10(opts)
  local env, printed, scripts = cold10(opts)
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



local function roster10()
  return { { "Fire Essency", "Member", 4, 20, "Warrior", "Durotar", "", "", true, 0, "WARRIOR" },
           { "Gm-ClassicBetaPvE", "GM", 0, 22, "Priest", "Durotar", "", "", true, 0, "PRIEST" } }
end
local GMN = "Gm-ClassicBetaPvE"
local gseq = 0
local function gmRec(ns, kind, id, d, dt)
  gseq = gseq + 1
  return { k = kind, id = id, a = GMN, ts = 1000000 + (dt or 0), sq = gseq, d = d }
end
local function fromGM(ns, kind, id, d, dt) return ns.Sync.Apply(gmRec(ns, kind, id, d, dt), GMN) end

test("Settings > Achievements: only the GM sees the section; a member sees the GM's names and not what is disabled", function()
  -- GM
  local ns = run10({ roster = roster10(), me = "Gm" })
  ok(ns.Permissions.isGM(ns.roster, ns.me()), "GM client")
  ns.UI.Open("settings")
  local st = ns.UI.SettingsState()
  ok(st.secBtn.ach, "Logros section button exists")
  eq(rawget(st.secBtn.ach, "_vis"), true, "GM: Logros button shown")
  ns.UI.SettingsSection("ach")
  eq(ns.UI.SettingsSection(), "ach", "GM: Logros section opens")
  ok(#ns.UI.CatalogRows("level") >= 6, "GM: level races listed (" .. #ns.UI.CatalogRows("level") .. ")")
  -- member
  local nm = run10({ roster = roster10(), me = "Fire" })
  ok(not nm.Permissions.isGM(nm.roster, nm.me()), "member client")
  ok(fromGM(nm, "achdef", "lvl.all.10", { name = "Primeros diez" }), "GM rename received")
  ok(fromGM(nm, "achdef", "lvl.all.20", { on = false }, 1), "GM disable received")
  ok(fromGM(nm, "achdef", "lvl10", { on = false }, 2), "GM disables the lvl10 achievement")
  nm.HallGlue.MarkDirty()
  nm.UI.Open("settings")
  local sm = nm.UI.SettingsState()
  eq(rawget(sm.secBtn.ach, "_vis"), false, "member: Logros button hidden")
  nm.UI.SettingsSection("ach")
  ok(nm.UI.SettingsSection() ~= "ach", "member: Logros cannot be opened")
  local races = nm.HallGlue.Races()
  local ids = {}
  for _, r in ipairs(nm.UI.HallRaceList(races, "level")) do ids[r.id] = nm.UI.RaceTitle(r.id) end
  eq(ids["lvl.all.10"], "Primeros diez", "member sees the GM's name")
  eq(ids["lvl.all.20"], nil, "member does not see the disabled race")
  ok(ids["lvl.all.30"], "the others stay")
  local keys = {}
  for _, a in ipairs(nm.UI.MyAchievementList()) do keys[a.key] = true end
  ok(keys.lvl20 and not keys.lvl10, "disabled achievement not listed (never earned)")
end)

test("strip: granted badge shown with its reason; disabled + earned -> Legacy at the end; disabled in progress hidden", function()
  local nm = run10({ roster = roster10(), me = "Fire" })
  local me = nm.me()
  ok(fromGM(nm, "achgrant", "guildFirst60|" .. me, { ach = "guildFirst60", who = me, reason = "evento", on = true }), "grant received")
  local list = nm.UI.StripList("S1")
  local first, boss10
  for _, a in ipairs(list) do if a.key == "guildFirst60" then first = a end; if a.key == "boss10" then boss10 = a end end
  ok(first and first.ts and first.grant and first.grant.reason == "evento", "granted badge with its reason")
  ok(boss10 and boss10.p, "boss10 in progress listed")
  ok(fromGM(nm, "achdef", "guildFirst60", { on = false }, 1) and fromGM(nm, "achdef", "boss10", { on = false }, 2), "GM disables both")
  list = nm.UI.StripList("S1")
  first, boss10 = nil, nil
  for i, a in ipairs(list) do if a.key == "guildFirst60" then first = a; first.i = i end; if a.key == "boss10" then boss10 = a end end
  ok(first and first.legacy == true and first.i == #list, "earned + disabled -> Legado, last")
  eq(boss10, nil, "disabled, never earned -> hidden")
  local grid = {}
  for _, a in ipairs(nm.UI.MyAchievementList()) do grid[a.key] = a end
  ok(grid.guildFirst60 and grid.guildFirst60.legacy, "Mis logros: guildFirst60 under Legado")
end)

test("'Desactivar todo PvP' = exactly N achdef records through the queue (1 msg/s, burst 4)", function()
  local ns, env = run10({ roster = roster10(), me = "Gm" })
  local H, Cat = ns.HallGlue, ns.Catalog
  local items, secs = H.BulkPlan("pvp", false)
  local N = #items
  ok(N >= 8, "pvp entries to disable: " .. N)
  local sent = {}
  local t = 5000
  env.GetTime = function() return t end
  env.C_ChatInfo.SendAddonMessage = function(_, msg) sent[#sent + 1] = { t = t, msg = msg }; return 0 end
  for _ = 1, 50 do t = t + 1; ns.Comm.queue:pump(t) end   -- drain whatever the login queued
  sent = {}
  local before = 0
  for _ in pairs(ns.state.achdefs or {}) do before = before + 1 end
  local okB, applied = H.Bulk("pvp", false)
  ok(okB and applied == N, "applied " .. tostring(applied) .. " of " .. N)
  local after, off = 0, 0
  for id, r in pairs(ns.state.achdefs) do after = after + 1; if r.d.on == false and Cat.groupOf(id) == "pvp" then off = off + 1 end end
  eq(after - before, N, "exactly N new records"); eq(off, N, "N pvp entries off")
  for _ = 1, 10 * (secs + 10) do t = t + 0.2; ns.Comm.queue:pump(t) end
  eq(ns.Comm.Pending(), 0, "queue drained")
  eq(#sent, secs, "messages = the estimate shown in the confirmation (" .. secs .. ")")
  local maxIn1, maxIn10 = 0, 0
  for i = 1, #sent do
    local a, b = 0, 0
    for j = i, #sent do
      if sent[j].t - sent[i].t < 1 then a = a + 1 end
      if sent[j].t - sent[i].t < 10 then b = b + 1 end
    end
    maxIn1, maxIn10 = math.max(maxIn1, a), math.max(maxIn10, b)
  end
  ok(maxIn1 <= 4, "burst <= 4 in any 1 s: " .. maxIn1)
  ok(maxIn10 <= 4 + 10, "<= 4 + 1/s in any 10 s: " .. maxIn10)
  -- the messages carry exactly the N records
  local asm, recs = ns.Chunk.newAssembler(), 0
  for _, m in ipairs(sent) do
    local full = ns.Chunk.feed(asm, "x", m.msg, 0)
    if full then
      local okD, data = ns.Serialize.decode(ns.Serialize.unescape(full))
      if okD and data.t == "D" then for _, r in ipairs(data.p.r) do if r.k == "achdef" then recs = recs + 1 end end end
    end
  end
  eq(recs, N, "achdef records on the wire")
end)

test("/gsq diag [extra]: catalog achdef=<n> custom=<n> grants=<n> off=<n>", function()
  local _, _, out = run10({ roster = roster10(), me = "Fire" })
  local line = out:match("(%[extra%] catalog [^\n]*)")
  ok(line and line:find("achdef=0 custom=0 grants=0 off=0", 1, true), tostring(line or out))
end)
