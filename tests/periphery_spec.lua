-- 2.0 periphery and UI names (docs/SPEC-v2.0-identidad.md §3 #15-20 and #47-67, §7, AC10 and AC11).
-- In WoW Forever a character is «Name Surname» (ns.id / ns.idFromUnit, contract §2.4): no realm, unique in the region.
-- Two «Kas» in the same realm: «Kas Pitas» (me, GM) and «Kas Mora». Every case checks a site that reads a name from the
-- client (party / raid witnesses, typed names, senders, invites) or a text that shows one.
-- Own strict environment per case (same builder as surnames_spec): UnitName / UnitNameUnmodified give (name, surname),
-- the roster and GetRaidRosterInfo give «Name Surname-Realm», RegionalUniqueNamesEnabled() is true, a sender is
-- «Name Surname». Frames are stubs that record their texts (SetText, AddLine, AddMessage, popups): this proves which
-- strings the addon builds, not how the client renders them.
local LUA = { "assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select", "setmetatable",
              "getmetatable", "rawget", "rawset", "rawequal", "tonumber", "tostring", "type", "string", "table",
              "math", "os", "coroutine" }
local REALM = "CAMWOWEU4Realm6PvP"
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

local function roster20()
  return { { "Kas Pitas-" .. REALM, "GM", 0, 30, "Warrior", "Durotar", "", "", true, 0, "WARRIOR" },
           { "Kas Mora-" .. REALM, "Member", 4, 28, "Priest", "Durotar", "", "", true, 0, "PRIEST" },
           { "Bob Stone-OtherRealm", "Officer", 1, 25, "Mage", "Durotar", "", "", true, 0, "MAGE" },
           { "Cid Oak-" .. REALM, "Member", 4, 22, "Rogue", "Durotar", "", "", true, 0, "ROGUE" } }
end

local function env20(opts)
  opts = opts or {}
  local env = {}
  for _, k in ipairs(LUA) do env[k] = _G[k] end
  env._G = env
  env.unpack = table.unpack
  env.tinsert, env.tremove, env.wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
  env.strsplit = function(sep, s) local out = {} for p in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = p end return table.unpack(out) end
  env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  env.date, env.time = os.date, os.time
  local rec = { printed = {}, texts = {}, invited = {}, whispers = {}, popups = {}, scripts = {}, frames = {}, chat = {} }
  local function note(s) if type(s) == "string" then rec.texts[#rec.texts + 1] = s end end
  env.print = function(...)
    local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    rec.printed[#rec.printed + 1] = table.concat(t, " "); note(rec.printed[#rec.printed])
  end
  local TEXT = { SetText = true, AddLine = true, AddMessage = true, SetFormattedText = true, AddDoubleLine = true }
  local stub
  stub = function()
    local o = setmetatable({}, { __index = function(t, k)
      if k == "SetScript" or k == "HookScript" then
        return function(self, ev, fn) rec.scripts[#rec.scripts + 1] = { self, ev, fn }; rawset(self, "_" .. ev, fn) end
      end
      if TEXT[k] then
        return function(self, s, ...)
          if k == "SetFormattedText" and type(s) == "string" then s = s:format(...) end
          if k == "SetText" then rawset(self, "_text", s) end
          note(s)
        end
      end
      if k == "GetScript" then return function(self, ev) return rawget(self, "_" .. ev) end end
      if k == "GetText" then return function() return "" end end
      if k == "IsShown" or k == "GetChecked" or k == "IsMouseOver" then return function() return false end end
      if k == "IsEnabled" then return function() return true end end
      if k == "GetCenter" then return function() return 500, 400 end end
      if k == "GetFontString" then return function() return nil end end
      if type(k) == "string" and (k:match("^Get")) then return function() return 10 end end
      if type(k) ~= "string" or not k:match("^[A-Z]") then return nil end
      local f = function() return stub() end
      rawset(t, k, f)
      return f
    end })
    rec.frames[#rec.frames + 1] = o
    return o
  end
  env.CreateFrame = function(_, name) local f = stub(); if name then env[name] = f end return f end
  env.UIParent, env.ChatFontNormal, env.GameTooltip, env.Minimap = stub(), stub(), stub(), stub()
  env.UIErrorsFrame, env.RaidWarningFrame, env.DEFAULT_CHAT_FRAME = stub(), stub(), stub()
  env.UISpecialFrames, env.StaticPopupDialogs, env.SlashCmdList = {}, {}, {}
  env.StaticPopup_Show = function(which, text, _, data) rec.popups[#rec.popups + 1] = { which, text, data }; note(text) end
  env.ChatTypeInfo = { RAID_WARNING = { r = 1, g = 0.3, b = 0.1 } }
  env.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PRIEST = { r = 1, g = 1, b = 1 } }
  env.CLASS_SORT_ORDER = { "WARRIOR", "PRIEST", "MAGE", "ROGUE" }
  env.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", PRIEST = "Priest", MAGE = "Mage", ROGUE = "Rogue" }
  env.Mixin = function(o, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do o[k] = v end end return o end
  local clock = 100
  rec.advance = function(s) clock = clock + s end
  env.GetTime = function() return clock end
  env.GetServerTime = function() return 1000000 + clock end
  env.GetBuildInfo = function() return "1.60.1", "70450", "Oct 1 2026", 16001 end
  env.GetLocale = function() return opts.locale or "enUS" end
  env.GetNormalizedRealmName = function() return REALM end
  env.GetCursorPosition = function() return 300, 300 end
  env.GetZoneText, env.GetSubZoneText, env.GetRealZoneText = function() return "Durotar" end, function() return "" end, function() return "Durotar" end
  -- WoW Forever: UnitName's 2nd value is the SURNAME (research-surnames.md), not the realm
  local units = opts.units or {}
  units.player = units.player or { "Kas", "Pitas" }
  local function unitName(u) local t = units[u]; if not t then return nil end return t[1], t[2] end
  env.UnitName, env.UnitNameUnmodified = unitName, unitName
  env.UnitFullName = function(u) local t = units[u]; if not t then return nil end return t[1], REALM end
  env.UnitExists = function(u) return units[u] ~= nil end
  env.RegionalUniqueNamesEnabled = function() return opts.forever ~= false end
  env.UnitClass = function() return "Warrior", "WARRIOR" end
  env.UnitLevel = function() return 30 end
  env.UnitRace = function() return "Orc", "Orc" end
  env.UnitFactionGroup = function() return "Horde" end
  env.UnitIsGroupLeader = function() return true end
  env.InCombatLockdown = function() return false end
  local raid = opts.raid
  local inParty = opts.party and true or false
  env.IsInGroup = function() return inParty or raid ~= nil end
  env.IsInRaid = function() return raid ~= nil end
  env.IsInInstance = function() if opts.instance then return true, "party" end return false, "none" end
  env.GetInstanceInfo = function()
    if opts.instance then return "The Deadmines", "party", 1, "Normal", 5, 0, false, 36 end
    return "Kalimdor", "none", 0, "", 0, 0, false, 1
  end
  env.GetNumGroupMembers = function()
    if raid then return #raid end
    if not inParty then return 0 end
    local n = 1
    for i = 1, 4 do if units["party" .. i] then n = n + 1 end end
    return n
  end
  env.GetRaidRosterInfo = function(i) local r = raid and raid[i]; if not r then return nil end return r[1], r[2] or 0, r[3] or 1 end
  env.IsInGuild = function() return true end
  env.GetGuildInfo = function() return "Por Honor", "GM", 0, REALM end
  local roster = opts.roster or roster20()
  env.GetNumGuildMembers = function() return #roster, #roster end
  env.GetGuildRosterInfo = function(i) if roster[i] then return table.unpack(roster[i]) end return nil end
  env.GuildControlGetNumRanks = function() return 5 end
  env.GuildControlGetRankName = function(i) return "Rank" .. tostring(i) end
  env.C_GuildInfo = { GuildRoster = function() end }
  env.C_AddOns = { GetAddOnMetadata = function() return "2.0.0" end }
  env.C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end,
                     SendAddonMessage = function(_, _, channel, target) if channel == "WHISPER" then rec.whispers[#rec.whispers + 1] = target end return 0 end,
                     InChatMessagingLockdown = function() return false end, SendChatMessage = function() end }
  env.C_InstanceEncounter = { IsEncounterInProgress = function() return false end }
  env.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
  env.C_Texture = { GetAtlasInfo = function() return nil end }
  env.C_PartyInfo = { InviteUnit = function(n) rec.invited[#rec.invited + 1] = n end, ConvertToRaid = function() end }
  env.issecretvalue = function(v) return v == SECRET end
  env.ChatFrameUtil = { OpenChat = function(t) rec.chat[#rec.chat + 1] = t end }
  env.GuildSquadsDB = nil
  return env, rec
end

local function boot(opts)
  local env, rec = env20(opts)
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
    for _, s in ipairs(rec.scripts) do
      if s[2] == "OnEvent" then
        local okE, errE = pcall(s[3], s[1], ev, ...)
        if not okE then error(ev .. ": " .. tostring(errE)) end
      end
    end
  end
  fire("ADDON_LOADED", "GuildSquads")
  fire("PLAYER_LOGIN")
  fire("GUILD_ROSTER_UPDATE")
  ok(ns.rosterReady, "roster read")
  return ns, env, rec, fire
end

local function hasDash(list)
  for _, n in ipairs(list) do if type(n) == "string" and n:find("-", 1, true) then return n end end
  return nil
end
local function sorted(list) local t = {} for i, v in ipairs(list) do t[i] = v end table.sort(t) return table.concat(t, ",") end
-- my squad with Kas Mora (and Bob Stone) as members: invited through the typed-name path (A.AddMember), then their
-- profile points at the squad (they accepted; M.isMember needs both sides)
local function accepted(ns, n, sid)
  ns.state.profiles[n] = { k = "profile", id = n, a = n, ts = 1, sq = 1, d = { squad = sid } }
end
local function squad(ns, extra)
  local okS, whyS = ns.Actions.CreateSquad({ name = "Los Lobos", tags = {} })
  ok(okS, "create squad: " .. tostring(whyS))
  local sid = ns.Actions.MySquadId()
  ok(sid, "in my squad")
  for _, n in ipairs(extra or { "Kas Mora" }) do
    local okA, whyA = ns.Actions.AddMember(sid, n)
    ok(okA, "add " .. n .. ": " .. tostring(whyA))
    accepted(ns, n, sid)
  end
  return sid
end

-------------------------------------------------------------------------------
-- AC10: witnesses, invites, typed names, senders

test("2.0 Hall witnesses: UnitName('party1') = ('Kas','Mora') is «Kas Mora», never 'Kas-Mora' (§3 #48)", function()
  local ns = boot({ party = true, units = { party1 = { "Kas", "Mora" }, party2 = { "Bob", "Stone" },
                                           party3 = { SECRET, "Oak" }, party4 = { "Cid", nil } } })
  local names = ns.HallGlue.GroupNames()
  -- party3 is secret (restricted instance): skipped; party4 has no surname cached yet: the roster resolves the
  -- only «Cid» (§2.3)
  eq(table.concat(names, ","), "Kas Pitas,Kas Mora,Bob Stone,Cid Oak", "Hall group names")
  eq(ns.ID_MODE, "forever", "identity mode")
  eq(ns.me(), "Kas Pitas", "me")
end)

test("2.0 Hall witnesses: the 2nd «Kas» without a cached surname is ambiguous and skipped, without errors (§9.4)", function()
  local ns = boot({ party = true, units = { party1 = { "Kas", nil }, party2 = { "Bob", "Stone" } } })
  eq(table.concat(ns.HallGlue.GroupNames(), ","), "Kas Pitas,Bob Stone")
end)

test("2.0 Hall witnesses: raid roster «Name Surname-Realm» is «Name Surname» (§3 #47)", function()
  local ns = boot({ raid = { { "Kas Pitas-" .. REALM, 2, 1 }, { "Kas Mora-" .. REALM, 0, 1 }, { "Bob Stone-OtherRealm", 0, 2 } } })
  eq(table.concat(ns.HallGlue.GroupNames(), ","), "Kas Pitas,Kas Mora,Bob Stone")
end)

test("2.0 Progress witnesses: a boss kill in a party counts the squad mate «Kas Mora» (§3 #53)", function()
  local ns = boot({ party = true, instance = true, units = { party1 = { "Kas", "Mora" } } })
  local sid = squad(ns)
  ns.ProgressGlue.OnEncounterEnd(36, "Edwin VanCleef", 1, 5, 1)
  local boss
  for _, ev in pairs(ns.ProgressGlue.Events()) do if ev.t == "boss" then boss = ev end end
  ok(boss, "boss event recorded")
  eq(boss.sid, sid)
  eq(table.concat(boss.pres or {}, ","), "Kas Mora", "present squad mates")
end)

test("2.0 Progress witnesses: raid roster «Name Surname-Realm» (§3 #52)", function()
  local ns = boot({ instance = true, raid = { { "Kas Pitas-" .. REALM, 2, 1 }, { "Kas Mora-" .. REALM, 0, 1 },
                                              { "Bob Stone-OtherRealm", 0, 2 } } })
  squad(ns, { "Kas Mora", "Bob Stone" })
  ns.ProgressGlue.OnEncounterEnd(36, "Edwin VanCleef", 1, 5, 1)
  local boss
  for _, ev in pairs(ns.ProgressGlue.Events()) do if ev.t == "boss" then boss = ev end end
  ok(boss, "boss event recorded")
  eq(sorted(boss.pres or {}), "Bob Stone,Kas Mora", "present squad mates")
end)

test("2.0 invites: InviteUnit gets «Kas Mora» (squad and raid roster), never a name with '-' (§3 #57, AC10)", function()
  local ns, _, rec = boot({})
  local sid = squad(ns, { "Kas Mora", "Bob Stone" })
  ns.Actions.InviteSquadToGroup(sid)
  eq(sorted(rec.invited), "Bob Stone,Kas Mora", "squad invite")
  local n0 = #rec.invited
  local api = ns.RaidGlue.GroupAPI()
  local res = ns.Roster.invite(api, { main = {}, bench = {} }, ns.Model.members(ns.state, sid), ns.me())
  eq(res.invited, 2, "raid roster invite")
  eq(sorted({ rec.invited[n0 + 1], rec.invited[n0 + 2] }), "Bob Stone,Kas Mora")
  -- no whisper target (not in the guild roster) -> not invited, counted as noTarget
  local res2 = ns.Roster.invite(api, { main = {}, bench = {} }, { "Nadie Nunca" }, ns.me())
  eq(res2.invited, 0, "nobody invited"); eq(res2.noTarget, 1, "noTarget counted")
  eq(#rec.invited, n0 + 2, "InviteUnit not called without a target")
  eq(hasDash(rec.invited), nil, "no invite with '-'")
end)

test("2.0 /gsq trust reset Kas Mora forgets «Kas Mora» (the rest of the line), not the other Kas (§3 #19-20)", function()
  local ns, env, rec = boot({})
  local db = ns.trustDB
  ok(db and db.keys, "trust db")
  for _, n in ipairs({ "Kas Mora", "Bob Stone", "Cid Oak" }) do db.keys[n] = { pk = n, s = 2 } end
  env.SlashCmdList.GUILDSQUADS("trust reset Kas Mora")
  eq(db.keys["Kas Mora"], nil, "Kas Mora forgotten")
  ok(db.keys["Bob Stone"] and db.keys["Cid Oak"], "the others kept")
  ok(rec.printed[#rec.printed]:find("Kas Mora", 1, true), "feedback names Kas Mora: " .. tostring(rec.printed[#rec.printed]))
  env.SlashCmdList.GUILDSQUADS("trust reset   bob stone  ")      -- typed in lower case, extra spaces
  eq(db.keys["Bob Stone"], nil, "Bob Stone forgotten (case-insensitive, roster)")
  local before = #rec.printed
  env.SlashCmdList.GUILDSQUADS("trust reset Kas")                  -- two «Kas»: ambiguous, nothing forgotten
  env.SlashCmdList.GUILDSQUADS("trust reset Nadie Nunca")          -- not in the guild
  ok(db.keys["Cid Oak"], "Cid Oak kept")
  local out = table.concat(rec.printed, "\n", before + 1)
  ok(out:find(ns.L.TYPED_AMBIGUOUS:format("Kas"), 1, true), "ambiguous first name: asks for the surname: " .. out)
  ok(out:find(ns.L.TYPED_NOT_MEMBER:format("Nadie Nunca"), 1, true), "the error names the typed full name: " .. out)
  eq(#rec.printed - before, 2, "one line per refused name")
end)

test("2.0 typed names: AddMember / Reject take «kas mora» as «Kas Mora»; unknown -> error with the full name (§3 #16)", function()
  local ns, _, rec = boot({})
  local sid = squad(ns, {})
  ok(ns.Actions.AddMember(sid, "  kas mora "), "typed in lower case")
  accepted(ns, "Kas Mora", sid)
  eq(table.concat(ns.Model.members(ns.state, sid), ","), "Kas Pitas,Kas Mora", "members")
  local before = #rec.printed
  local okN, whyN = ns.Actions.AddMember(sid, "Nadie Nunca")
  ok(not okN, "unknown name refused"); eq(whyN, "notGuildMember")
  eq(#rec.printed - before, 1, "one error line (the caller's repeat is skipped)")
  ok(rec.printed[before + 1]:find(ns.L.TYPED_NOT_MEMBER:format("Nadie Nunca"), 1, true), "the error shows the full typed name: "
     .. tostring(rec.printed[before + 1]))
  ok(not ns.Actions.AddMember(sid, "Kas"), "an ambiguous first name is refused")
  ok(ns.Actions.Reject(sid, "cid oak", "req"), "reject typed")
  ok(ns.Model.isRejected(ns.state, sid, "Cid Oak", "req"), "rejection stored under «Cid Oak»")
end)

test("2.0 typed names: rlList «kas mora» is stored as «Kas Mora»; unknown names are dropped (§3 #65)", function()
  local ns, _, rec = boot({})
  ns.UI.Open("settings")
  local eb
  for _, f in ipairs(rec.frames) do if rawget(f, "listField") == "rlList" then eb = f end end
  ok(eb, "rlList edit box built")
  rawset(eb, "GetText", function() return "kas mora\nBob Stone-OtherRealm, Nadie Nunca" end)
  rawget(eb, "_OnTextChanged")(eb, true)
  eq(table.concat(ns.UI.SettingsState().draft.rlList or {}, ","), "Kas Mora,Bob Stone", "rlList draft")
end)

test("2.0 typed names: the catalog grant to «kas mora» goes to «Kas Mora» (§3 #66)", function()
  local ns = boot({})
  local W, prompts, menus = ns.W, {}, {}
  W.Menu = function(_, items) menus[#menus + 1] = items end
  W.Prompt = function(text, fn) prompts[#prompts + 1] = { text, fn } end
  W.Confirm = function(_, fn) fn() end
  ok(ns.UI.CatalogGrantFlow({}), "grant flow opened")
  local who
  for i = 2, #menus[1] do
    menus[1][i].func()
    if prompts[#prompts] and prompts[#prompts][1] == ns.L.CAT_GRANT_WHO then who = prompts[#prompts]; break end
  end
  ok(who, "a character badge asks who")
  who[2]("  kas mora ")
  local why = prompts[#prompts]
  ok(why ~= who and why[1]:find("Kas Mora", 1, true), "reason prompt names Kas Mora: " .. tostring(why and why[1]))
  why[2]("evento")
  local got = 0
  for _ in pairs(ns.Catalog.grantsFor("Kas Mora")) do got = got + 1 end
  eq(got, 1, "badge granted to Kas Mora")
end)

test("2.0 senders «Name Surname»: a squad call from «Kas Mora» is shown as «Kas Mora» (§3 #17)", function()
  local ns, _, rec = boot({})
  squad(ns)
  local before = #rec.texts
  ns.OnCall(ns.Call.payload("Durotar", "Razor Hill"), "Kas Mora")
  local shown = table.concat(rec.texts, "\n", before + 1)
  ok(shown:find("Kas Mora", 1, true), "call shown with the full name: " .. shown)
end)

test("2.0 senders «Name Surname»: Progress events and summaries take the author by ns.id (§3 #55)", function()
  local ns = boot({})
  squad(ns)
  local G, t = ns.ProgressGlue, ns.ProgressGlue.Now()
  local sid = ns.Actions.MySquadId()
  local function has(who, n)
    for _, ev in pairs(G.Events()) do if ev.who == who and ev.n == n then return true end end
    return false
  end
  G.OnEvents({ e = { { t = "hk", who = "Kas Mora", ts = t, sid = sid, n = 3 } } }, "Kas Mora")
  ok(has("Kas Mora", 3), "event from its author «Kas Mora» accepted")
  G.OnEvents({ e = { { t = "hk", who = "Kas Mora", ts = t + 1, sid = sid, n = 4 } } }, "Kas Mora-" .. REALM)
  ok(has("Kas Mora", 4), "sender with the realm suffix is the same author")
  G.OnEvents({ e = { { t = "hk", who = "Kas Mora", ts = t + 2, sid = sid, n = 5 } } }, "Kas")
  ok(not has("Kas Mora", 5), "a bare «Kas» (two in the guild) is nobody: dropped")
end)

test("2.0 senders «Name Surname»: Hall observations from «Kas Mora» are hers, a bare «Kas» is dropped (§3 #50)", function()
  local ns = boot({})
  local H, t = ns.HallGlue, ns.ProgressGlue.Now()
  local function obs(lv, sender)
    H.OnObs({ o = { { t = "lv", who = "Kas Mora", by = "Kas Mora", ts = t - 5, src = "self", lv = lv } } }, sender, false, t)
  end
  obs(29, "Kas Mora")
  obs(30, "Kas")                       -- two «Kas» in the guild: nobody, dropped
  obs(31, "Kas Pitas")                 -- another author cannot speak for Kas Mora
  local lv = {}
  for _, ev in pairs(H.Store().obs) do if ev.who == "Kas Mora" and ev.t == "lv" then lv[#lv + 1] = ev.lv end end
  eq(sorted(lv), "29", "only the level Kas Mora sent herself")
end)

test("2.0 /gsq diag: «id mode=forever me=Kas Pitas surname=yes» and the identity APIs are probed (§2.1, §3 #63)", function()
  local ns, env, rec = boot({})
  local shown
  local orig = ns.UI.ShowExport
  ns.UI.ShowExport = function(text, ...) shown = text; return orig(text, ...) end
  env.SlashCmdList.GUILDSQUADS("diag")
  ok(type(shown) == "string", "diag shown")
  ok(shown:find("id mode=forever me=Kas Pitas surname=yes", 1, true), "id line:\n" .. shown)
  -- [apis] lines: "  <section> OK: a b c | NO: d e"
  local present = {}
  for line in shown:gmatch("[^\n]+") do
    local okPart = line:match("^%s+%a+ OK: (.-) | NO:")
    if okPart then for n in okPart:gmatch("%S+") do present[n] = true end end
  end
  for _, api in ipairs({ "RegionalUniqueNamesEnabled", "UnitNameUnmodified", "UnitFullName" }) do
    ok(present[api], api .. " probed and present")
  end
  ok(not shown:find("Kas-", 1, true), "no «Kas-…» in the report")
end)

test("2.0 /gsq diag in realm mode (RegionalUniqueNamesEnabled false): «id mode=realm me=Kas-…» (§2.1)", function()
  local _, env, rec = boot({ forever = false, units = { player = { "Kas", nil } },
                             roster = { { "Kas-" .. REALM, "GM", 0, 30, "Warrior", "Durotar", "", "", true, 0, "WARRIOR" } } })
  env.SlashCmdList.GUILDSQUADS("diag")
  local out = table.concat(rec.texts, "\n")
  ok(out:find("id mode=realm me=Kas-" .. REALM .. " surname=no", 1, true), "realm id line")
end)

-------------------------------------------------------------------------------
-- AC11: every text of §7 shows «Kas Pitas» and «Kas Mora», never «Kas» alone nor «Kas-…»

-- every «Kas» in the texts must be followed by « Pitas» or « Mora»
local function bareKas(texts)
  for _, s in ipairs(texts) do
    local plain = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local i = 1
    while true do
      local a, b = plain:find("Kas", i, true)
      if not a then break end
      local rest = plain:sub(b + 1, b + 6)
      if rest:sub(1, 6) ~= " Pitas" and rest:sub(1, 5) ~= " Mora" then return s end
      i = b + 1
    end
  end
  return nil
end
local function textsSince(rec, n) local t = {} for i = n + 1, #rec.texts do t[#t + 1] = rec.texts[i] end return t end
local function find(texts, needle) for _, s in ipairs(texts) do if s:find(needle, 1, true) then return s end end return nil end

test("2.0 UI: squad screens, member menu and confirmations show «Kas Pitas» and «Kas Mora» (§7)", function()
  local ns, _, rec = boot({})
  local sid = squad(ns)
  local n0 = #rec.texts
  ns.UI.Open("mysquad")
  for _, key in ipairs(ns.UI.order) do ns.UI.Select(key) end
  ns.UI.Select("mysquad")
  -- member menu of Kas Mora (right click on her slot card, Panels.lua:144-159): title + confirm texts
  local W, menus = ns.W, {}
  local origMenu = W.Menu
  W.Menu = function(owner, items) menus[#menus + 1] = items; return origMenu(owner, items) end
  local slot
  for _, f in ipairs(rec.frames) do
    local nm = rawget(f, "name")
    local t = type(nm) == "table" and rawget(nm, "_text")
    if type(t) == "string" and t:find("Kas Mora", 1, true) and rawget(f, "_OnClick") then slot = f end
  end
  ok(slot, "Kas Mora's slot card")
  rawget(slot, "_OnClick")(slot, "RightButton")
  eq(#menus, 1, "member menu opened")
  local texts = textsSince(rec, n0)
  local byText = {}
  for _, it in ipairs(menus[1]) do
    texts[#texts + 1] = it.text; byText[it.text] = it
    if it.confirm then texts[#texts + 1] = it.confirm end
  end
  eq(menus[1][1].text, "Kas Mora", "menu title")
  ok(find(texts, ns.L.CONFIRM_KICK:format("Kas Mora")), "kick confirmation names Kas Mora")
  ok(find(texts, "Kas Pitas"), "Kas Pitas shown")
  eq(bareKas(texts), nil, "a text with «Kas» alone")
  eq(find(texts, "Kas-"), nil, "a text with «Kas-…»")
  -- «Invite to party» and «Whisper» use her target «Kas Mora» (Panels.lua:33-53), never the key with «-»
  local n1 = #rec.invited
  byText[ns.L.INVITE_PARTY].func()
  eq(rec.invited[n1 + 1], "Kas Mora", "invite to party target")
  byText[ns.L.WHISPER].func()
  eq(rec.chat[#rec.chat], "/w Kas Mora ", "whisper opens the chat with the full name")
end)

test("2.0 UI: feedback, unverified / disputed tooltips and the call show the full names (§7)", function()
  local ns, _, rec = boot({})
  ok(ns.Actions.SaveSettings({ squadsEnabled = true, bench = 1, minCreateRank = 4, officerRanks = { 1 }, banned = {} }), "bench on")
  local sid = squad(ns, { "Kas Mora", "Bob Stone" })
  local n0 = #rec.texts
  ns.Actions.MoveToBench(sid, "Kas Mora")
  ns.Actions.Kick(sid, "Kas Mora")
  ns.Actions.AddMember(sid, "Kas Mora")
  ns.Actions.Reject(sid, "Cid Oak", "req")
  rec.texts[#rec.texts + 1] = ns.UnverifiedTip("Kas Mora", "Kas Pitas")
  ns.trustDB.contested = ns.trustDB.contested or {}
  ns.trustDB.contested["Kas Mora"] = true
  rec.texts[#rec.texts + 1] = ns.UnverifiedTip("Kas Mora", "Kas Pitas")
  local texts = textsSince(rec, n0)
  ok(find(texts, ns.L.FB_KICKED:format("Kas Mora")), "kick feedback: " .. table.concat(texts, " | "))
  ok(find(texts, ns.L.FB_BENCHED:format("Kas Mora")), "bench feedback")
  ok(find(texts, ns.L.UNVERIFIED_TIP:format("Kas Pitas", "Kas Mora")), "unverified tooltip")
  ok(find(texts, ns.L.UNVERIFIED_TIP_DISPUTED:format("Kas Mora")), "disputed tooltip")
  eq(bareKas(texts), nil, "a text with «Kas» alone")
end)

test("2.0 UI: Hall version list and entry label, Discord export (§7)", function()
  local ns, env, rec = boot({})
  local H, R = ns.HallGlue, ns.Roster
  H.OnHello({}, "Kas Mora")                     -- heard: she counts in the adoption list
  local n0 = #rec.texts
  H.AdoptionTooltip(env.CreateFrame("GameTooltip"))
  rec.texts[#rec.texts + 1] = H.EntryLabel({ key = "Kas Mora", chars = { "Kas Mora", "Kas Pitas" } })
  local exp = R.exportText({ rosters = { r1 = { d = { name = "Raid", raid = "custom", size = 10, at = 0,
                             main = { "Kas Pitas", "Kas Mora", "", "", "", "", "", "", "", "" }, bench = { "Bob Stone" } } } } },
                           "r1", function(n) return n == "Kas Pitas" and "TANK" or "HEALER" end, {})
  rec.texts[#rec.texts + 1] = exp
  local texts = textsSince(rec, n0)
  ok(find(texts, "Kas Pitas  |cff999999") and find(texts, "Kas Mora  |cff999999"), "version list: " .. table.concat(texts, " | "))
  eq(texts[#texts - 1], "Kas Mora", "entry label")
  ok(exp:find("Kas Pitas (T)", 1, true) and exp:find("Kas Mora (H)", 1, true) and exp:find("Bob Stone", 1, true), exp)
  eq(bareKas(texts), nil, "a text with «Kas» alone")
  eq(find(texts, "Kas-"), nil, "a text with «Kas-…»")
end)
