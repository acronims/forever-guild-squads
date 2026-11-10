-- 2.0.1 (docs/SPEC-v2.0.1-sin-perfil.md): members who have Guild Squads but no filled profile show in the Buscador
-- as «No profile yet»; a captain can invite them and joining needs a complete profile (role + a goal), checked by the
-- invited player's own client before it signs the acceptance. Protocol unchanged.
-- Environment: the same strict WoW Forever builder as periphery_spec (copied, each spec stands alone).
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

-------------------------------------------------------------------------------
-- the guild of these cases: me = Kas Pitas (GM, 30), the rest members (rank 4)
local function roster201()
  local function m(n, lv, cls, online) return { n .. "-" .. REALM, "Member", 4, lv, cls, "Durotar", "", "", online, 0, cls } end
  return { { "Kas Pitas-" .. REALM, "GM", 0, 30, "Warrior", "Durotar", "", "", true, 0, "WARRIOR" },
           m("Kas Mora", 30, "PRIEST", true),     -- complete profile
           m("Dan Ash", 30, "MAGE", true),        -- the automatic profile (DAMAGER, no goals): no profile yet
           m("Eva Elm", 31, "PRIEST", false),     -- verified presence, no profile record: no profile yet
           m("Fay Fir", 30, "ROGUE", true),       -- presence older than adoptDays: nothing
           m("Gil Oak", 30, "WARRIOR", true),     -- profile only by relay (unverified)
           m("Hal Yew", 30, "MAGE", true),        -- presence only by relay (pending): nothing
           m("Mb9 Apmb9", 30, "MAGE", true) }     -- presences stored under non canonical spellings: nothing
end
local function rec201(k, n, ts, d) return { k = k, id = n, a = n, ts = ts, sq = 1, d = d } end
local DAY = 86400
local curEnv
local function boot201(opts) local ns, env, rec, fire = boot(opts); curEnv = env; return ns, env, rec, fire end
local function GetServerTime() return curEnv.GetServerTime() end
local function seed(ns)
  local now = GetServerTime()
  local st = ns.state
  st.presence = st.presence or {}
  st.profiles["Kas Mora"] = rec201("profile", "Kas Mora", now - 50, { role = "HEALER", goals = { "raid" }, avail = "11110000" })
  st.profiles["Dan Ash"] = rec201("profile", "Dan Ash", now - 50, { role = "DAMAGER", avail = "00000000", goals = {} })
  st.presence["Dan Ash"] = rec201("presence", "Dan Ash", now - 50, { ver = "2.0.1", day = math.floor(now / DAY) })
  st.presence["Eva Elm"] = rec201("presence", "Eva Elm", now - 60, { ver = "2.0.0", day = math.floor(now / DAY) })
  st.presence["Fay Fir"] = rec201("presence", "Fay Fir", now - 31 * DAY, { ver = "2.0.0", day = math.floor(now / DAY) - 31 })
  st.presence["mb9 apmb9"] = rec201("presence", "mb9 apmb9", now - 60, { ver = "2.0.0", day = math.floor(now / DAY) })
  st.presence["Mb9 Apmb9-" .. REALM] = rec201("presence", "Mb9 Apmb9-" .. REALM, now - 60, { ver = "2.0.0", day = math.floor(now / DAY) })
  st.presence["Zed Nope"] = rec201("presence", "Zed Nope", now - 60, { ver = "2.0.0", day = math.floor(now / DAY) })   -- not in the guild
  local okH, whyH = ns.Sync.Apply(rec201("presence", "Hal Yew", now - 40, { ver = "2.0.0", day = math.floor(now / DAY) }), "Kas Mora")
  eq(okH, false, "relayed presence not applied"); eq(whyH, "pending", "relayed presence pending")
  local okG, whyG = ns.Sync.Apply(rec201("profile", "Gil Oak", now - 40, { role = "TANK", goals = { "raid" } }), "Kas Mora")
  eq(okG, false, "relayed profile not applied"); eq(whyG, "pending", "relayed profile pending")
  ok(ns.state.presence["Hal Yew"] == nil, "a pending presence is not in state.presence")
  return now
end
local function finder(ns)
  local fd = ns.UI.FinderState()
  fd.mode = "players"
  ns.UI.Open("finder"); ns.UI.Select("finder")
  return fd
end
local function names(fd)
  local t = {}
  for _, it in ipairs(fd.grid.items) do t[#t + 1] = it.player.name .. (it.player.noProfile and "*" or "") .. (it.player.unverified and "?" or "") end
  return table.concat(t, ",")
end
local function publishes(ns)
  local list, orig = {}, ns.Sync.Publish
  ns.Sync.Publish = function(r, ...) list[#list + 1] = r; return orig(r, ...) end
  return list, function() ns.Sync.Publish = orig end
end
-- Kas Mora's squad listing me (an invitation to Kas Pitas): her record, as every client holds it once verified
local function invitedBy(ns, open)
  local now = GetServerTime()
  local sid = "Kas Mora:" .. (now - 500)
  ns.state.squads[sid] = rec201("squad", "Kas Mora", now - 100, { name = "Los Lobos", captain = "Kas Mora",
    members = { "Kas Mora", "Kas Pitas" }, bench = {}, icon = 1, color = 1, border = 1, open = open and true or false,
    approved = true, ct = now - 500, tags = {} })
  ns.state.squads[sid].id = sid
  ns.state.profiles["Kas Mora"] = rec201("profile", "Kas Mora", now - 100, { role = "HEALER", goals = { "raid" }, squad = sid })
  return sid
end

-------------------------------------------------------------------------------
test("2.0.1 AC1: M.profileComplete = a main role and at least one goal; the '!' uses the same rule", function()
  local M = NS.Model
  ok(type(M.profileComplete) == "function", "M.profileComplete")
  eq(M.profileComplete(nil), false, "nil")
  eq(M.profileComplete({}), false, "empty")
  eq(M.profileComplete({ role = "DAMAGER", avail = "00000000", goals = {} }), false, "the automatic profile")
  eq(M.profileComplete({ goals = { "raid" } }), false, "goal without role")
  eq(M.profileComplete({ role = "", goals = { "raid" } }), false, "empty role")
  eq(M.profileComplete({ role = "TANK", goals = "raid" }), false, "goals not a list")
  eq(M.profileComplete({ role = "TANK", goals = { "raid" } }), true, "role + goal")
  local ns = boot201({ roster = roster201() })
  eq(ns.Actions.ProfileIncomplete(), true, "after login: the automatic profile is incomplete")
  ok(ns.Actions.SaveProfile({ role = "TANK", goals = { "bg" } }))
  eq(ns.Actions.ProfileIncomplete(), not M.profileComplete(ns.state.profiles[ns.me()].d), "same rule")
  eq(ns.Actions.ProfileIncomplete(), false, "complete")
end)

test("2.0.1 AC2/AC3/AC5: the Buscador lists who has the addon without a profile as «No profile yet», nobody else", function()
  local ns, _, rec = boot201({ roster = roster201() })
  local L = ns.L
  ok(type(L.NO_PROFILE) == "string" and type(L.NO_PROFILE_TIP) == "string", "texts")
  seed(ns)
  local fd = finder(ns)
  -- complete verified first, then unverified, then no profile (online before offline)
  eq(names(fd), "Kas Mora,Gil Oak?,Dan Ash*,Eva Elm*", "finder list")
  -- record what the cards hide / show
  for _, c in ipairs(fd.grid.cells) do
    for _, part in ipairs({ c.fit, c.role }) do
      rawset(part, "Show", function(self) rawset(self, "_hid", false) end)
      rawset(part, "Hide", function(self) rawset(self, "_hid", true) end)
    end
  end
  ns.UI.Select("finder")
  for i, it in ipairs(fd.grid.items) do
    local c = fd.grid.cells[i]
    local t = rawget(c.name, "_text") or ""
    if it.player.noProfile then
      ok(t:find(L.NO_PROFILE, 1, true), "card says no profile: " .. t)
      ok(t:find(it.player.name, 1, true), "card has the full name: " .. t)
      ok(not t:find(L.UNVERIFIED, 1, true), "not the unverified text")
      eq(rawget(c.fit, "_hid"), true, "no fit badge for " .. it.player.name)
      eq(rawget(c.role, "_hid"), true, "no role icon for " .. it.player.name)
      eq(c.tip, L.NO_PROFILE, "tooltip title"); eq(c.tipText, L.NO_PROFILE_TIP, "tooltip text")
      eq(#it.reasons, 0, "no reasons")
    else
      ok(not t:find(L.NO_PROFILE, 1, true), "no mark on " .. it.player.name)
      eq(rawget(c.fit, "_hid"), false, "fit badge shown for " .. it.player.name)
    end
  end
  -- a complete profile later: Dan Ash shows as everyone else
  ns.state.profiles["Dan Ash"].d = { role = "TANK", goals = { "raid" } }
  ns.UI.Select("finder")
  eq(names(fd), "Dan Ash,Kas Mora,Gil Oak?,Eva Elm*", "Dan Ash complete now (TANK scores first for a TANK-less me)")
  ok(#rec.texts > 0)
end)

test("2.0.1 AC4: role, goal and time filters hide the members without a profile; class, level and online apply", function()
  local ns = boot201({ roster = roster201() })
  local L = ns.L
  ok(ns.Actions.SaveProfile({ role = "TANK", goals = { "raid" }, avail = "11110000" }))
  seed(ns)
  local fd = finder(ns)
  eq(names(fd), "Kas Mora,Gil Oak?,Dan Ash*,Eva Elm*", "no filter")
  ok((rawget(fd.foot, "_text") or ""):find(L.RESULTS_N:format(4, 4, L.PLAYERS_WORD), 1, true), "foot counts them: " .. tostring(rawget(fd.foot, "_text")))
  fd.role.HEALER = true; ns.UI.Select("finder")
  eq(names(fd), "Kas Mora", "role filter")
  ok((rawget(fd.foot, "_text") or ""):find(L.RESULTS_N:format(1, 4, L.PLAYERS_WORD), 1, true), "total still 4: " .. tostring(rawget(fd.foot, "_text")))
  fd.role.HEALER = nil; fd.goal.raid = true; ns.UI.Select("finder")
  eq(names(fd), "Kas Mora,Gil Oak?", "goal filter")
  fd.goal.raid = nil
  rawset(fd.avail, "GetChecked", function() return true end); ns.UI.Select("finder")
  eq(names(fd), "Kas Mora", "time filter (Gil Oak has no hours)")
  rawset(fd.avail, "GetChecked", function() return false end)
  fd.class.MAGE = true; ns.UI.Select("finder")
  eq(names(fd), "Dan Ash*", "class filter: from the roster")
  fd.class.MAGE = nil
  rawset(fd.minL, "GetText", function() return "31" end); ns.UI.Select("finder")
  eq(names(fd), "Eva Elm*", "level filter: from the roster")
  rawset(fd.minL, "GetText", function() return "" end)
  rawset(fd.online, "GetChecked", function() return true end); ns.UI.Select("finder")
  eq(names(fd), "Kas Mora,Gil Oak?,Dan Ash*", "online filter")
end)

test("2.0.1 AC6: the captain invites a member without a profile from the Buscador; the model lists the invitation", function()
  local ns = boot201({ roster = roster201() })
  ok(ns.Actions.SaveSettings({ squadsEnabled = true, bench = 1, minCreateRank = 4, officerRanks = { 1 }, banned = {} }))
  seed(ns)
  local okS, whyS = ns.Actions.CreateSquad({ name = "Los Lobos", tags = {} })
  ok(okS, "create: " .. tostring(whyS))
  local sid = ns.Actions.MySquadId()
  local fd = finder(ns)
  local i
  for k, it in ipairs(fd.grid.items) do if it.player.name == "Dan Ash" then i = k end end
  ok(i and fd.grid.items[i].player.noProfile, "Dan Ash listed without a profile")
  -- right click -> «Invite to squad»
  local menus, W = {}, ns.W
  local orig = W.Menu
  W.Menu = function(owner, items) menus[#menus + 1] = items; return orig(owner, items) end
  rawget(fd.grid.cells[i], "_OnClick")(fd.grid.cells[i], "RightButton")
  W.Menu = orig
  local inv
  for _, it in ipairs(menus[1] or {}) do if it.text == ns.L.INVITE_SQUAD then inv = it end end
  ok(inv, "invite to squad in the menu")
  inv.func()
  ok(ns.Model.isMember(ns.state, sid, "Dan Ash") == false, "listed, not a member yet")
  eq(table.concat(ns.Model.invites(ns.state, "Dan Ash"), ","), sid, "his invitation")
end)

test("2.0.1 AC7/AC8: accepting with an incomplete profile opens Mi perfil; the save of a complete profile joins", function()
  local ns, _, rec = boot201({ roster = roster201() })
  local L, M, A = ns.L, ns.Model, ns.Actions
  local sid = invitedBy(ns)
  eq(table.concat(M.invites(ns.state, "Kas Pitas"), ","), sid, "invited")
  ok(A.ProfileIncomplete(), "my profile is the automatic one")
  ns.UI.Open("mysquad")
  local pub, undo = publishes(ns)
  local n0 = #rec.texts
  local okJ, why = A.RequestJoin(sid)
  eq(okJ, false, "not joined"); eq(why, "profileIncomplete", "reason")
  eq(#pub, 0, "nothing signed")
  eq(M.isMember(ns.state, sid, "Kas Pitas"), false, "not a member")
  eq(ns.UI.Current(), "profile", "Mi perfil opened")
  eq(A.JoinAfterProfile(), sid, "join remembered")
  local hint = L.JOIN_AFTER_PROFILE:format("Los Lobos")
  local seen = false
  for k = n0 + 1, #rec.texts do if rec.texts[k] == hint then seen = true end end
  ok(seen, "hint with the squad name")
  ok(type(L.ERR_profileIncomplete) == "string", "error text")
  -- save a role only: profile saved, still incomplete, no join
  local prof = ns.UI.ProfileState()
  prof.role = "TANK"
  for _, c in ipairs(prof.goals) do c.on = false end
  rawget(prof.save, "_OnClick")(prof.save)
  eq(#pub, 1, "one profile record"); eq(pub[1].k, "profile")
  ok(pub[1].d.squad ~= sid, "no squad in it")
  eq(M.isMember(ns.state, sid, "Kas Pitas"), false, "still not a member")
  eq(A.JoinAfterProfile(), sid, "still remembered")
  -- add a goal and save: one record with the role, the goal and the squad
  prof.goals[1].on = true
  rawget(prof.save, "_OnClick")(prof.save)
  eq(#pub, 2, "exactly one more record")
  eq(pub[2].k, "profile"); eq(pub[2].d.squad, sid, "squad in the same save"); eq(pub[2].d.role, "TANK")
  ok(type(pub[2].d.reqAt) == "number", "reqAt stamped")
  ok(M.profileComplete(pub[2].d), "complete")
  eq(M.isMember(ns.state, sid, "Kas Pitas"), true, "member")
  eq(#M.invites(ns.state, "Kas Pitas"), 0, "invitation gone")
  eq(A.JoinAfterProfile(), nil, "forgotten")
  local fb = false
  for k = n0 + 1, #rec.texts do if rec.texts[k]:find(L.FB_JOINED:format("Los Lobos"), 1, true) then fb = true end end
  ok(fb, "joined feedback")
  undo()
end)

test("2.0.1 AC8: «Save and exit» of a complete profile also completes the join", function()
  local ns, env, rec = boot201({ roster = roster201() })
  local M, A = ns.Model, ns.Actions
  local sid = invitedBy(ns)
  ns.UI.Open("mysquad")
  eq(select(2, A.RequestJoin(sid)), "profileIncomplete")
  eq(ns.UI.Current(), "profile")
  local prof = ns.UI.ProfileState()
  prof.role = "HEALER"; prof.goals[2].on = true
  local pub, undo = publishes(ns)
  local p0 = #rec.popups
  ns.UI.Select("squads")
  eq(#rec.popups, p0 + 1, "unsaved prompt")
  local dlg = env.StaticPopupDialogs.GUILDSQUADS_CONFIRM
  ok(dlg and type(dlg.OnAlt) == "function", "save and exit")
  dlg.OnAlt(nil, rec.popups[#rec.popups][3])
  eq(#pub, 1, "one record"); eq(pub[1].d.squad, sid, "with the squad")
  eq(M.isMember(ns.state, sid, "Kas Pitas"), true, "member")
  eq(A.JoinAfterProfile(), nil)
  undo()
end)

test("2.0.1 AC9: the network cannot force a join: a squad listing me, received again and again, signs nothing", function()
  local ns = boot201({ roster = roster201() })
  local M, A = ns.Model, ns.Actions
  local pub, undo = publishes(ns)
  local sid = invitedBy(ns)
  local r = ns.state.squads[sid]
  for _ = 1, 3 do
    pcall(ns.Sync.Apply, { k = "squad", id = sid, a = "Kas Mora", ts = r.ts + 1, sq = 2, d = r.d }, "Kas Mora")
    pcall(ns.Sync.Apply, { k = "squad", id = sid, a = "Kas Mora", ts = r.ts + 1, sq = 2, d = r.d }, "Dan Ash")
    ns.UpdateBadge()
  end
  eq(#pub, 0, "nothing of mine signed")
  eq(M.isMember(ns.state, sid, "Kas Pitas"), false, "not a member")
  eq(A.JoinAfterProfile(), nil, "nothing remembered without my action")
  -- a profile «of mine» pointing at the squad, sent by someone else, is not applied as mine
  local mine = ns.state.profiles["Kas Pitas"]
  local okP = ns.Sync.Apply({ k = "profile", id = "Kas Pitas", a = "Kas Pitas", ts = GetServerTime(), sq = 999,
    d = { role = "TANK", goals = { "raid" }, squad = sid } }, "Kas Mora")
  eq(okP, false, "forged profile not applied")
  eq(ns.state.profiles["Kas Pitas"], mine, "my profile untouched")
  eq(M.isMember(ns.state, sid, "Kas Pitas"), false, "still not a member")
  undo()
end)

test("2.0.1 AC10: with a complete profile, accepting joins at once (as in 2.0.0)", function()
  local ns = boot201({ roster = roster201() })
  local M, A = ns.Model, ns.Actions
  ok(A.SaveProfile({ role = "TANK", goals = { "raid" } }))
  local sid = invitedBy(ns)
  local pub, undo = publishes(ns)
  local okJ, why = A.RequestJoin(sid)
  ok(okJ, "joined: " .. tostring(why))
  eq(#pub, 1); eq(pub[1].d.squad, sid)
  eq(M.isMember(ns.state, sid, "Kas Pitas"), true)
  eq(A.JoinAfterProfile(), nil)
  undo()
  -- a join request to an open squad that does not list me, also with a complete profile: a request
  local ns2 = boot201({ roster = roster201() })
  ok(ns2.Actions.SaveProfile({ role = "TANK", goals = { "raid" } }))
  local sid2 = invitedBy(ns2, true)
  ns2.state.squads[sid2].d.members = { "Kas Mora" }
  ok(ns2.Actions.RequestJoin(sid2), "request sent")
  eq(table.concat(M.requests(ns2.state, sid2), ","), "Kas Pitas", "a request")
  -- and with an incomplete one the request also waits for the profile
  local ns3 = boot201({ roster = roster201() })
  local sid3 = invitedBy(ns3, true)
  ns3.state.squads[sid3].d.members = { "Kas Mora" }
  eq(select(2, ns3.Actions.RequestJoin(sid3)), "profileIncomplete", "request gated too")
  eq(#M.requests(ns3.state, sid3), 0, "no request")
end)

test("2.0.1 AC12: protocol 3 and the record schemas of 2.0.0, unchanged", function()
  local ns = boot201({ roster = roster201() })
  eq(ns.Model.PROTO, 3, "Model.PROTO"); eq(ns.Comm.PROTO, 3, "Comm.PROTO")
  local S = ns.Serialize or NS.Serialize
  local function shape(t)
    local keys = {}
    for k, v in pairs(t) do keys[#keys + 1] = k .. "=" .. table.concat((function() local o = {} for i, x in ipairs(v) do o[i] = tostring(x) end return o end)(), ":") end
    table.sort(keys)
    return table.concat(keys, ",")
  end
  eq(shape(ns.Model.SCHEMA.profile), "avail=A,class=s:20,goals=L:6:12,level=n,note=s:60,race=s:24,reqAt=n,role2=R,role=R,squad=s:64,xferTo=s:120", "profile schema")
  eq(shape(ns.P2P.SCHEMA_PRESENCE), "day=n,ver=s:16", "presence schema")
  ok(S ~= nil or true)
end)
