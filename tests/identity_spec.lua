-- 2.0 identity (docs/SPEC-v2.0-identidad.md §2, AC1): one function for every input, ns.id(a, b).
--   forever (RegionalUniqueNamesEnabled): "Name Surname", no realm, unique in the region
--   realm   (anything else): "Name-Realm", the 1.2.2 key
-- Part 1: the pure Core/Identity.lua over a table of cases in both modes (idempotence on every case).
-- Part 2: the ns.* contract of §2.4 with the whole addon loaded in a strict cold client (as surnames_spec).
local I = NS.Identity

local MY = "CAMWOWEU4Realm6PvP"
local SECRET = "Sekret Wert"   -- stands for a secret value (issecretvalue is true for it)
-- 49 bytes: 12 + 1 + 12 Cyrillic letters of 2 bytes (SPEC risk 6: the 64-byte cap)
local CYR = "Александрина Константинов"
if not I then
  test("AC1 identity: Core/Identity.lua (ns.Identity) exists", function() error("ns.Identity is missing") end)
else
local ROSTER = {
  "Kas Pitas-" .. MY, "Ann Oak-" .. MY, "Bob Stone-RealmA", "Mb2 Uno-RealmA", "Mb2 Dos-RealmB",
  "Cid Pitas-RealmB", "Cid Mora-RealmB", CYR .. "-RealmB", "Ñandú Ébano-RealmA",
}
local function index(names, mode, myRealm)
  local ix = I.newIndex()
  for _, raw in ipairs(names) do
    local first, surname, realm = I.split(raw)
    local id
    if mode == "forever" then id = surname and (first .. " " .. surname) or nil
    else id = I.realmKey(raw, myRealm) end
    if id then I.indexAdd(ix, id, first, surname, realm or myRealm) end
  end
  return ix
end
local function isSecret(v) return v == SECRET end
local F = { mode = "forever", myRealm = MY, index = index(ROSTER, "forever", MY), isSecret = isSecret }
local twoKas = {}
for i, n in ipairs(ROSTER) do twoKas[i] = n end
twoKas[#twoKas + 1] = "Kas Mora-RealmB"
local F2 = { mode = "forever", myRealm = MY, index = index(twoKas, "forever", MY), isSecret = isSecret }
local F0 = { mode = "forever", myRealm = MY, index = I.newIndex() }          -- roster not read yet

-- { label, ctx, a, b, expected }
local FOREVER = {
  { "roster form «N A-R»", F, "Kas Pitas-" .. MY, nil, "Kas Pitas" },
  { "sender «N A» (no realm)", F, "Kas Pitas", nil, "Kas Pitas" },
  { "sender «N A» of another realm", F, "Bob Stone", nil, "Bob Stone" },
  { "sender «N A» not in the roster stays itself", F, "Kas Mora", nil, "Kas Mora" },
  { "sender «N A» with a realm suffix", F, "Bob Stone-RealmA", nil, "Bob Stone" },
  { "UnitName pair (N, A)", F, "Kas", "Pitas", "Kas Pitas" },
  { "UnitFullName («N A», \"\")", F, "Kas Pitas", "", "Kas Pitas" },
  { "UnitName pair of a member not in the roster", F0, "Kas", "Pitas", "Kas Pitas" },
  { "(N, nil) surname not cached, one Kas -> roster", F, "Kas", nil, "Kas Pitas" },
  { "(N, nil) with two Kas -> nil", F2, "Kas", nil, nil },
  { "(N, nil) roster not read -> nil", F0, "Kas", nil, nil },
  { "bare sender with two Cid -> nil", F, "Cid", nil, nil },
  { "bare sender with one Bob -> roster", F, "Bob", nil, "Bob Stone" },
  { "bare sender unknown -> nil", F, "Zed", nil, nil },
  { "typed lower case -> roster spelling", F, "kas pitas", nil, "Kas Pitas" },
  { "typed upper case -> roster spelling", F, "BOB STONE", nil, "Bob Stone" },
  { "typed with extra spaces", F, "  Kas   Pitas  ", nil, "Kas Pitas" },
  { "typed link separator «Kas-Pitas» (in the roster)", F, "Kas-Pitas", nil, "Kas Pitas" },
  { "typed link separator, lower case", F, "kas-pitas", nil, "Kas Pitas" },
  { "link separator not in the roster -> nil", F, "Zed-Pitas", nil, nil },
  { "saved 1.x «Kas-MyRealm» -> index (first, realm)", F, "Kas-" .. MY, nil, "Kas Pitas" },
  { "saved 1.x «Bob-RealmA» (connected realm)", F, "Bob-RealmA", nil, "Bob Stone" },
  { "saved 1.x «Mb2-RealmA» / two Mb2 on two realms", F, "Mb2-RealmA", nil, "Mb2 Uno" },
  { "saved 1.x «Mb2-RealmB»", F, "Mb2-RealmB", nil, "Mb2 Dos" },
  { "bare «Mb2» with one per realm -> nil", F, "Mb2", nil, nil },
  { "saved 1.x «Cid-RealmB» with two Cid there -> nil", F, "Cid-RealmB", nil, nil },
  { "saved 1.x of a realm nobody has -> nil", F, "Kas-RealmZ", nil, nil },
  { "1.2.0 leftover «N A-OtherRealm»", F, "Kas Pitas-RealmA", nil, "Kas Pitas" },
  { "1.2.0 form «N-R A»", F, "Bob-RealmA Stone", nil, "Bob Stone" },
  { "unit pair (N, myRealm) is a realm -> index", F, "Kas", MY, "Kas Pitas" },
  { "unit pair (N, RealmA) is a realm -> index", F, "Bob", "RealmA", "Bob Stone" },
  { "Cyrillic 49 bytes comes back the same", F, CYR, nil, CYR },
  { "Cyrillic 49 bytes, roster form", F, CYR .. "-RealmB", nil, CYR },
  { "accented name, roster spelling", F, "Ñandú Ébano", nil, "Ñandú Ébano" },
  { "accented in another case: no ASCII rule, typed text stays (not the roster's)", F, "ñandú ébano", nil, "ñandú ébano" },
  { "trailing dash", F, "Kas Pitas-", nil, "Kas Pitas" },
  { "no first name «-Realm»", F, "-RealmA", nil, nil },
  { "only blanks", F, "   ", nil, nil },
  { "empty", F, "", nil, nil },
  { "nil", F, nil, nil, nil },
  { "number", F, 42, nil, nil },
  { "table", F, {}, nil, nil },
  { "boolean", F, true, "Pitas", nil },
  { "secret value", F, SECRET, nil, nil },
  { "secret surname", F, "Kas", SECRET, nil },
  { "no mode -> nil", { myRealm = MY, index = F.index }, "Kas Pitas", nil, nil },
}

-- realm mode = the 1.2.2 (the surnames_spec cases of the 1.2.1/1.2.2 moved to realm mode)
local R = { mode = "realm", myRealm = "Home", index = index({ "Bob Stone-OtherRealm", "Fire Essency", "Gil Uno-RA", "Gil Uno-RB" }, "realm", "Home"), isSecret = isSecret }
local REALM = {
  { "realm: «Fire Essency» (roster, my realm)", R, "Fire Essency", nil, "Fire-Home" },
  { "realm: «Fire-Reino»", R, "Fire-Reino", nil, "Fire-Reino" },
  { "realm: «Fire Essency-Reino»", R, "Fire Essency-Reino", nil, "Fire-Reino" },
  { "realm: «Fire-Reino Essency»", R, "Fire-Reino Essency", nil, "Fire-Reino" },
  { "realm: bare «Fire»", R, "Fire", nil, "Fire-Home" },
  { "realm: non-ASCII split on the plain space", R, "Ñandú Ébano", nil, "Ñandú-Home" },
  { "realm: sender «N A» of another connected realm (1.2.2 fullIdx)", R, "Bob Stone", nil, "Bob-OtherRealm" },
  { "realm: «N A» two keys share it -> my realm (1.2.2)", R, "Gil Uno", nil, "Gil-Home" },
  { "realm: unit (N, nil)", R, "Kas", nil, "Kas-Home" },
  { "realm: unit (N, realm)", R, "Kas", "Otro", "Kas-Otro" },
  { "realm: unit (N, \"\")", R, "Kas", "", "Kas-Home" },
  { "realm: no character name", R, " Essency", nil, nil },
  { "realm: empty", R, "", nil, nil },
  { "realm: nil", R, nil, nil, nil },
  { "realm: secret", R, SECRET, nil, nil },
}

test("AC1 identity: the case table in forever and realm modes, idempotent on every case", function()
  local n = 0
  for _, list in ipairs({ FOREVER, REALM }) do
    for _, c in ipairs(list) do
      local got = I.id(c[3], c[4], c[2])
      eq(got, c[5], c[1])
      if got ~= nil then eq(I.id(got, nil, c[2]), got, "idempotent: " .. c[1]) end
      n = n + 1
    end
  end
  ok(n >= 35, "at least 35 cases (" .. n .. ")")
end)

test("AC1 identity: never raises, whatever the context", function()
  local weird = { nil, 1, "x", {}, { mode = "forever" }, { mode = "forever", index = 5 }, { mode = "realm", index = { byFull = 3 } },
                  { mode = "forever", index = { byLower = {}, byFirst = {}, byFirstRealm = {}, realms = {} }, isSecret = function() error("boom") end } }
  for i = 1, 8 do
    local okC, r = pcall(I.id, "Kas Pitas", nil, weird[i])
    ok(okC, "ctx " .. i .. " raised")
    ok(r == nil or r == "Kas Pitas", "ctx " .. i .. ": " .. tostring(r))
  end
end)

test("AC1 identity: realm wrappers M.charName / M.whisperTarget keep the 1.2.2 answers", function()
  local M = NS.Model
  local cases = {
    { "Fire Essency", "Fire-Home", "Essency" }, { "Fire-Reino", "Fire-Reino", nil },
    { "Fire Essency-Reino", "Fire-Reino", "Essency" }, { "Fire-Reino Essency", "Fire-Reino", "Essency" },
    { "Fire", "Fire-Home", nil }, { "Ñandú Ébano", "Ñandú-Home", "Ébano" },
  }
  for _, c in ipairs(cases) do
    local key, surname = M.charName(c[1], "Home")
    eq(key, c[2], "key of " .. c[1]); eq(surname, c[3], "surname of " .. c[1])
  end
  eq(M.charName(" Essency", "Home"), nil); eq(M.charName("", "Home"), nil); eq(M.charName(nil, "Home"), nil)
  eq(M.whisperTarget("Kas-Realm", "Pitas", "Realm"), "Kas Pitas")
  eq(M.whisperTarget("Kas-Realm", "Pitas", "Realm", true), "Kas Pitas-Realm")
  eq(M.whisperTarget("Kas-Other", "Pitas", "Realm"), "Kas Pitas", "any realm: no suffix")
  eq(M.whisperTarget("Kas-Realm", nil, "Realm"), "Kas")
  eq(M.whisperTarget(nil, "Pitas", "Realm"), nil)
end)

test("AC1 identity: the index (§2.4 ns.rosterIndex shape)", function()
  local ix = F2.index
  eq(#ix.byFirst["kas"], 2, "two Kas by first name"); eq(#ix.byFirst["bob"], 1)
  eq(ix.byFirstRealm["mb2-RealmA"][1], "Mb2 Uno"); eq(ix.byFirstRealm["mb2-RealmB"][1], "Mb2 Dos")
  eq(ix.byLower["kas pitas"], "Kas Pitas"); eq(ix.byLower["kas mora"], "Kas Mora")
  ok(ix.realms[MY] and ix.realms.RealmA and ix.realms.RealmB, "realms")
  eq(I.lower("ÑANDÚ Kas"), "ÑandÚ kas", "ASCII-only lower case")
  eq(I.firstOf("Kas Pitas"), "Kas"); eq(I.firstOf("Kas-Realm"), "Kas"); eq(I.firstOf("Kas"), "Kas")
  eq(I.surnameOf("Kas Pitas-R", F), "Pitas"); eq(I.surnameOf("Fire Essency-Reino", R), "Essency"); eq(I.surnameOf("Fire", R), nil)
end)

end

-------------------------------------------------------------------------------
-- part 2: the ns.* contract with the whole addon (strict cold client of the 16001 API)
local LUA = { "assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select", "setmetatable",
              "getmetatable", "rawget", "rawset", "rawequal", "tonumber", "tostring", "type", "string", "table",
              "math", "os", "coroutine" }
-- getters with a number (as zload_spec); any other Get* gives nil (no font string, no anchor)
local NUMERIC = { GetStringWidth = 60, GetWidth = 100, GetHeight = 20, GetFrameLevel = 3, GetEffectiveScale = 1, GetNumPoints = 1 }
local function client(opts)
  local env = {}
  for _, k in ipairs(LUA) do env[k] = _G[k] end
  env._G = env
  env.unpack = table.unpack
  env.tinsert, env.tremove, env.wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
  env.strsplit = function(sep, s) local out = {} for p in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = p end return table.unpack(out) end
  env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  env.date, env.time = os.date, os.time
  local printed, scripts, texts = {}, {}, {}
  env.print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end printed[#printed + 1] = table.concat(t, " ") end
  local stub
  stub = function()
    return setmetatable({}, { __index = function(t, k)
      if k == "SetScript" or k == "HookScript" then
        return function(self, ev, fn) scripts[#scripts + 1] = { self, ev, fn }; rawset(self, "_" .. ev, fn) end
      end
      if k == "GetScript" then return function(self, ev) return rawget(self, "_" .. ev) end end
      if k == "GetText" then return function(self) return rawget(self, "_text") or "" end end
      if k == "SetText" then return function(self, t) rawset(self, "_text", t); texts[#texts + 1] = tostring(t) end end
      if k == "IsShown" or k == "GetChecked" or k == "IsMouseOver" then return function() return false end end
      if k == "IsEnabled" then return function() return true end end
      if k == "GetCenter" then return function() return 500, 400 end end
      if NUMERIC[k] then return function() return NUMERIC[k] end end
      if type(k) == "string" and (k:match("^Get") ) then return function() return nil end end
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
  env.GetTime = function() return 100 end
  env.GetServerTime = function() return 1000100 end
  env.GetBuildInfo = function() return "1.60.1", "70862", "Nov 7 2026", 16001 end
  env.GetLocale = function() return "enUS" end
  env.GetNormalizedRealmName = function() return MY end
  env.GetCursorPosition = function() return 300, 300 end
  env.GetZoneText, env.GetSubZoneText, env.GetRealZoneText = function() return "Durotar" end, function() return "" end, function() return "Durotar" end
  env.UnitName = function() return opts.first or "Kas" end          -- WoW Forever: the bare first name
  env.UnitNameUnmodified = function(u)
    if u == "player" then return opts.first or "Kas", opts.surname end
    return nil
  end
  if opts.regional ~= nil then env.RegionalUniqueNamesEnabled = opts.regional end
  env.UnitClass = function() return "Warrior", "WARRIOR" end
  env.UnitLevel = function() return 20 end
  env.UnitRace = function() return "Orc", "Orc" end
  env.UnitFactionGroup = function() return "Horde" end
  env.InCombatLockdown = function() return false end
  env.IsInGroup, env.IsInRaid, env.IsInInstance = function() return false end, function() return false end, function() return false end
  env.GetNumGroupMembers = function() return 0 end
  env.IsInGuild = function() return true end
  env.GetGuildInfo = function() return "Por Honor", "Member", 4, MY end
  local roster = opts.roster
  env.GetNumGuildMembers = function() return #roster, #roster end
  env.GetGuildRosterInfo = function(i) if roster[i] then return table.unpack(roster[i]) end return nil end
  env.GuildControlGetNumRanks = function() return 5 end
  env.GuildControlGetRankName = function(i) return "Rank" .. tostring(i) end
  env.C_GuildInfo = { GuildRoster = function() end }
  env.C_AddOns = { GetAddOnMetadata = function() return "2.0.0" end }
  env.C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end, SendAddonMessage = function() return 0 end,
                     InChatMessagingLockdown = function() return false end, SendChatMessage = function() end }
  env.C_InstanceEncounter = { IsEncounterInProgress = function() return false end }
  env.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
  env.C_Texture = { GetAtlasInfo = function() return nil end }
  env.C_PartyInfo = { InviteUnit = function() end, ConvertToRaid = function() end }
  env.issecretvalue = function(v) return v == SECRET end
  env.GuildSquadsDB = nil
  local ns = { ID_MODE = opts.force }
  local toc = {}
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
  local function diag()
    local shown
    local orig = ns.UI.ShowExport
    ns.UI.ShowExport = function(text, ...) shown = text; return orig(text, ...) end
    local okD, errD = pcall(env.SlashCmdList.GUILDSQUADS, "diag")
    ns.UI.ShowExport = orig
    ok(okD, "/gsq diag: " .. tostring(errD))
    return shown or ""
  end
  return ns, env, fire, diag, printed, texts
end
local function row(name, online, rank) return { name, "Member", rank or 4, 20, "Warrior", "Durotar", "", "", online ~= false, 0, "WARRIOR" } end
local function foreverRoster()
  return { row("Kas Pitas-" .. MY), row("Kas Mora-" .. MY), row("Ann Oak-" .. MY, true, 0), row("Bob Stone-RealmA"),
           row("Cid Uno-RealmA", false), row("Gm-" .. MY) }   -- the last one has no surname (never an identity in forever)
end
local function boot(opts)
  local ns, env, fire, diag, printed, texts = client(opts)
  fire("ADDON_LOADED", "GuildSquads")
  fire("PLAYER_LOGIN")
  fire("GUILD_ROSTER_UPDATE")
  return ns, env, fire, diag, printed, texts
end

test("AC1 ns.*: forever (RegionalUniqueNamesEnabled), me «Kas Pitas», two Kas in the roster", function()
  local ns, _, _, diag = boot({ roster = foreverRoster(), regional = function() return true end, surname = "Pitas" })
  eq(ns.ID_MODE, "forever", "mode")
  ok(ns.rosterReady, "roster read")
  eq(ns.me(), "Kas Pitas", "me from UnitNameUnmodified(player) = (Kas, Pitas)")
  ok(ns.isSelf("Kas Pitas") and ns.isSelf("Kas Pitas-" .. MY) and ns.isSelf("kas pitas"), "isSelf")
  ok(not ns.isSelf("Kas Mora") and not ns.isSelf("Kas") and not ns.isSelf(nil) and not ns.isSelf(""), "not self")
  eq(ns.id("Kas Pitas-" .. MY), "Kas Pitas"); eq(ns.id("Kas", "Pitas"), "Kas Pitas"); eq(ns.id("Kas"), nil, "two Kas")
  eq(ns.id("Bob"), "Bob Stone", "one Bob"); eq(ns.id("Bob-RealmA"), "Bob Stone"); eq(ns.id("kas-mora"), "Kas Mora")
  eq(ns.id(SECRET), nil, "secret"); eq(ns.id(7), nil)
  local r = ns.roster("Kas Pitas-" .. MY)
  ok(r and r.realm == MY and r.raw == "Kas Pitas-" .. MY and r.surname == "Pitas", "roster entry: realm, raw, surname")
  ok(ns.roster("Bob Stone") and ns.roster("Bob Stone").realm == "RealmA", "other realm")
  eq(ns.roster("Gm-" .. MY), nil, "no surname: no identity in forever")
  local list, n = ns.rosterList(), 0
  for id in pairs(list) do n = n + 1; ok(id:find(" ", 1, true) and not id:find("-", 1, true), "id «N A»: " .. id) end
  eq(n, 5, "5 identities")
  local ix = ns.rosterIndex()
  eq(#ix.byFirst["kas"], 2); eq(ix.byLower["bob stone"], "Bob Stone"); ok(ix.realms.RealmA and ix.realms[MY], "realms")
  eq(#ix.byFirstRealm["kas-" .. MY], 2)
  -- WHISPER target = the identity, never «-Realm», no other variant; nil outside the roster
  eq(ns.whisperTarget("Kas Mora"), "Kas Mora"); eq(ns.whisperTarget("Bob Stone-RealmA"), "Bob Stone", "another realm: no suffix")
  eq(ns.whisperTarget("Kas Mora", true), nil, "no alt variant"); eq(ns.whisperTarget("Zed Nope"), nil, "not in the roster")
  eq(ns.displayName("Kas Mora"), "Kas Mora"); eq(ns.shortName("Kas Mora"), "Kas Mora"); eq(ns.displayName("Kas Pitas"), "Kas Pitas")
  ok(ns.displayName("Kas Mora") ~= ns.displayName("Kas Pitas"), "the two Kas show apart")
  ok(not ns.isAmbiguous("Kas Pitas") and not ns.isAmbiguous("Kas Mora"), "forever: no ambiguous identities")
  -- temporary aliases for B and C (§2.4)
  eq(ns.fullName("Kas Pitas-" .. MY), "Kas Pitas"); local k, s = ns.charKey("Kas Mora-" .. MY); eq(k, "Kas Mora"); eq(s, "Mora")
  -- writes work under the new identity
  local okP, whyP = ns.Actions.SaveProfile({ role = "TANK" })
  ok(okP, "save profile: " .. tostring(whyP))
  eq(ns.state.profiles["Kas Pitas"].a, "Kas Pitas", "profile id and author «Kas Pitas»")
  local okS, whyS = ns.Actions.CreateSquad({ name = "Los Kas", tags = {} })
  ok(okS, "create squad: " .. tostring(whyS))
  local sid = ns.Actions.MySquadId()
  eq(ns.state.squads[sid].d.captain, "Kas Pitas", "captain «Kas Pitas», not «Kas Mora»")
  ok(not ns.Model.isMember(ns.state, sid, "Kas Mora"), "Kas Mora is not a member")
  local out = diag()
  ok(out:find("id mode=forever me=Kas Pitas surname=yes", 1, true), out)
  ok(out:find("[roster] me=Kas Pitas found=yes entries=5 surnames=5", 1, true), out)
  ok(out:find("realms=" .. MY .. ":3,RealmA:2", 1, true), out)
end)

test("AC1 ns.*: forever, surname not cached yet for the player (TRP3 #1482) -> the roster gives it, then cached", function()
  local roster = { row("Ann Oak-" .. MY, true, 0), row("Kas Pitas-" .. MY) }
  local ns, env = boot({ roster = roster, regional = function() return true end, surname = nil })
  eq(ns.me(), "Kas Pitas", "one Kas: the roster gives the surname")
  env.GetNumGuildMembers = function() return 0, 0 end
  eq(ns.me(), "Kas Pitas", "still me")
  local ns2 = boot({ roster = { row("Kas Pitas-" .. MY), row("Kas Mora-" .. MY) }, regional = function() return true end })
  eq(ns2.me(), nil, "two Kas and no surname: nobody (nothing is written)")
  local okP, whyP = ns2.Actions.SaveProfile({ role = "TANK" })
  ok(not okP, "no write without an identity: " .. tostring(whyP))
end)

test("AC1 ns.*: the mode (RegionalUniqueNamesEnabled at ADDON_LOADED, again at PLAYER_LOGIN, then frozen; forced in tests)", function()
  local ns = boot({ roster = foreverRoster(), regional = function() return false end })
  eq(ns.ID_MODE, "realm", "false -> realm"); eq(ns.me(), "Kas-" .. MY, "realm: 1.2.2 key")
  ns = boot({ roster = foreverRoster() })
  eq(ns.ID_MODE, "realm", "missing -> realm")
  ns = boot({ roster = foreverRoster(), regional = function() error("no") end })
  eq(ns.ID_MODE, "realm", "raises -> realm")
  ns = boot({ roster = foreverRoster(), force = "forever", surname = "Pitas" })
  eq(ns.ID_MODE, "forever", "forced before loading"); eq(ns.me(), "Kas Pitas")
  -- ADDON_LOADED says forever, PLAYER_LOGIN says realm: PLAYER_LOGIN wins, then the session keeps it
  local on = true
  local ns2, env2, fire2 = client({ roster = foreverRoster(), regional = function() return on end, surname = "Pitas" })
  eq(ns2.me(), nil, "before ADDON_LOADED: no mode, no me")
  fire2("ADDON_LOADED", "GuildSquads")
  eq(ns2.ID_MODE, "forever", "ADDON_LOADED"); eq(ns2.me(), "Kas Pitas")
  on = false
  fire2("PLAYER_LOGIN")
  eq(ns2.ID_MODE, "realm", "PLAYER_LOGIN wins"); eq(ns2.me(), "Kas-" .. MY, "me follows the mode")
  on = true
  fire2("PLAYER_LOGIN"); fire2("ADDON_LOADED", "GuildSquads"); fire2("GUILD_ROSTER_UPDATE")
  eq(ns2.ID_MODE, "realm", "frozen for the session")
  ok(env2, "env")
end)

test("AC1 ns.*: realm mode keeps the 1.2.2 (surname in the roster, UnitName bare)", function()
  local roster = { row("Fire Essency"), row("Gm-ClassicBetaPvE", true, 0), row("Bob Stone-OtherRealm") }
  local ns, env, fire, diag = client({ roster = roster, first = "Fire" })
  env.GetNormalizedRealmName = function() return "ClassicBetaPvE" end
  env.GetGuildInfo = function() return "Por Honor", "Member", 4, "ClassicBetaPvE" end
  fire("ADDON_LOADED", "GuildSquads"); fire("PLAYER_LOGIN"); fire("GUILD_ROSTER_UPDATE")
  eq(ns.ID_MODE, "realm")
  eq(ns.me(), "Fire-ClassicBetaPvE"); eq(ns.id("Bob Stone"), "Bob-OtherRealm", "1.2.2 fullIdx")
  eq(ns.roster("Fire").surname, "Essency"); eq(ns.roster("Fire").realm, "ClassicBetaPvE"); eq(ns.roster("Fire").raw, "Fire Essency")
  eq(ns.displayName("Fire-ClassicBetaPvE"), "Fire Essency"); eq(ns.shortName("Fire-ClassicBetaPvE"), "Fire")
  eq(ns.whisperTarget("Bob-OtherRealm"), "Bob Stone"); eq(ns.whisperTarget("Bob-OtherRealm", true), "Bob Stone-OtherRealm")
  eq(ns.fullName("Fire"), "Fire-ClassicBetaPvE"); local k, s = ns.charKey("Fire Essency"); eq(k, "Fire-ClassicBetaPvE"); eq(s, "Essency")
  local out = diag()
  ok(out:find("id mode=realm me=Fire-ClassicBetaPvE surname=yes", 1, true), out)
  ok(out:find("[roster] me=Fire-ClassicBetaPvE found=yes entries=3 surnames=2", 1, true), out)
end)

-- AC3 (unit part): on each of the two «Kas» the list shows the other one with his surname, and never a name cut to
-- «Kas» or carrying «-Realm» (finder, players: the profiles of the members without a squad)
test("AC3 UI: the finder list of Kas Pitas shows «Kas Mora», the one of Kas Mora shows «Kas Pitas»", function()
  local function finderTexts(meSurname, other)
    local ns, _, _, _, _, texts = boot({ roster = foreverRoster(), regional = function() return true end, surname = meSurname })
    eq(ns.me(), "Kas " .. meSurname)
    ns.state.profiles[other] = { k = "profile", id = other, a = other, ts = 1, sq = 1, d = { role = "HEALER" } }
    -- a captain with room: the finder opens on the players (the members without a squad)
    local okS, whyS = ns.Actions.CreateSquad({ name = "Squad " .. meSurname, tags = {} })
    ok(okS, "create squad: " .. tostring(whyS))
    local before = #texts
    ns.UI.Open("finder")
    ns.UI.Select("finder", true)
    local out = {}
    for i = before + 1, #texts do out[#out + 1] = texts[i] end
    return table.concat(out, "\n")
  end
  local onPitas, onMora = finderTexts("Pitas", "Kas Mora"), finderTexts("Mora", "Kas Pitas")
  ok(onPitas:find("Kas Mora", 1, true), "Kas Pitas's list shows «Kas Mora»: " .. onPitas:sub(1, 300))
  ok(onMora:find("Kas Pitas", 1, true), "Kas Mora's list shows «Kas Pitas»: " .. onMora:sub(1, 300))
  for _, t in ipairs({ onPitas, onMora }) do
    ok(not t:find("Kas%-"), "no «Kas-…» in the list")
    ok(not t:find("|r Kas|r", 1, true) and not t:find("Kas  |cff", 1, true), "no bare «Kas»")
  end
end)
