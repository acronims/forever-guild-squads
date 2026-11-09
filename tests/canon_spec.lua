-- 2.0, blind review D (agents/g20-d.md): what arrives inside data must already be an identity, ns.id(x) == x.
-- A1  «Ann-<realm>», «ann oak», «Ann», «Ann-Oak» or «Ann Oak-X» resolve to Ann Oak in the roster (rank, GM, display) but
--     are other names for trust, signatures and the «mine» check: two colluders certified a key for one of them and
--     the record signed with it was applied and shown as the GM (D9). Every network or saved entry now refuses a name
--     that is not canonical (never normalized) and counts it (/gsq diag: alias=N).
-- M1  RegionalUniqueNamesEnabled() false at ADDON_LOADED and true at PLAYER_LOGIN, with the roster in between (D4):
--     the session stayed in a realm partition, never migrated. The roster waits for the final mode.
-- B2  ns.id idempotent on odd forms («Kas Pitas -Realm» gave «Kas Pitas »): a property over a battery of forms.
local I = NS.Identity
local MY = "CAMWOWEU4Realm6PvP"
local SECRET = "Sekret Wert"   -- stands for a secret value (issecretvalue is true for it)
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
  env.GuildSquadsDB = opts.db   -- saved data (nil = fresh install)
  if opts.loggedIn ~= nil then env.IsLoggedIn = function() return opts.loggedIn end end
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
local function F(extra)
  local o = { roster = foreverRoster(), regional = function() return true end, surname = "Pitas" }
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
end
local function aliasCount(diag)
  local out = diag()
  return tonumber(out:match("alias=(%d+)") or "") , out
end
-- spellings of the GM «Ann Oak» that the roster resolves to her (D1) and that are not her identity
local ALIASES = { "Ann-" .. MY, "ann oak", "ANN OAK", "Ann", "Ann-Oak", "Ann Oak-Whatever", " Ann Oak", "Ann  Oak" }

test("A1 precondition: every alias resolves to the GM «Ann Oak» (D1), none of them is her identity", function()
  local ns = boot(F())
  eq(ns.ID_MODE, "forever"); eq(ns.me(), "Kas Pitas")
  for _, a in ipairs(ALIASES) do
    eq(ns.id(a), "Ann Oak", a)
    ok(ns.roster(a) ~= nil and ns.Permissions.isGM(ns.roster, a), "resolves as the GM: " .. a)
  end
end)

-- D9 of the reviewer as a test: Bob Stone and Kas Mora (heard in person) certify one key for `target`, relay a record
-- of `target` with that key (ks) and a manifest signed with it
local function ghost(target, realKnown)
  local ns, env, fire, diag = boot(F())
  local E, T, C, G = ns.Ed25519, ns.Trust, ns.Cert, ns.Sig
  local now = 1000100
  local function key(tag) local sk = E.sha512("probe " .. tag):sub(1, 32) return sk, E.publicKey(sk) end
  local skB, pkB = key("bob"); local skM, pkM = key("mora"); local skE, pkE = key("evil"); local _, pkA = key("ann")
  T.hearOwner(ns.trustDB, "Bob Stone", pkB, now)          -- colluder 1, heard in person
  T.hearOwner(ns.trustDB, "Kas Mora", pkM, now)           -- colluder 2, heard in person
  if realKnown then T.hearOwner(ns.trustDB, "Ann Oak", pkA, now) end   -- the real GM, heard in person
  local rec = { k = "profile", id = target, a = target, ts = 1000050, sq = 1, d = { note = "ghost of the GM" } }
  ns.Sync.OnMessage("D", { r = { rec }, ks = { [target] = T.hex(pkE) } }, "Bob Stone", "GUILD")
  ns.Sync.OfferCert(C.build("Bob Stone", 1, { [target] = pkE }, skB, pkB), "Bob Stone")
  ns.Sync.OfferCert(C.build("Kas Mora", 1, { [target] = pkE }, skM, pkM), "Kas Mora")
  for _ = 1, 10 do if C.pending() > 0 then ns.Sync.CertStep() end end
  local m = G.build(target, 1, { rec }, skE, pkE)
  ns.Sync.OnMessage("D", { r = { rec }, m = { m } }, "Bob Stone", "GUILD")
  for _ = 1, 20 do if G.pending() > 0 or C.pending() > 0 then ns.Sync.SigStep() end end
  local _, st = T.keyOf(ns.trustDB, target)
  return { ns = ns, diag = diag, st = st, p = ns.state.profiles[target],
           held = ns.trustDB.keys[target] ~= nil or ns.trustDB.pend[target] ~= nil or (ns.sigDB.man or {})[target] ~= nil }
end

test("A1 (D9) cert path: two colluders certify a key for another spelling of the GM: nothing kept, nothing applied", function()
  local c = ghost("Ann Oak", true)
  eq(c.p, nil, "control: the canonical GM, heard in person, is not ghosted")
  -- control: the same harness does reach the annex G limit for a canonical member nobody heard in person (S16c)
  local z = ghost("Cid Uno", false)
  ok(z.p and z.p.d.note == "ghost of the GM" and z.st == "cert", "control: a canonical name never heard in person is certified (annex G)")
  for _, alias in ipairs({ "Ann-" .. MY, "ann oak", "Ann", "Ann-Oak", "Ann Oak-Whatever" }) do
    local g = ghost(alias, true)
    eq(g.p, nil, alias .. ": the ghost profile applied")
    eq(g.st, nil, alias .. ": a key status under the alias")
    ok(not g.held, alias .. ": trust / manifests hold something under the alias")
    local n, out = aliasCount(g.diag)
    ok(n and n > 0, alias .. ": counted in /gsq diag (alias=N): " .. tostring(out:match("id mode[^\n]*")))
    ok(g.ns.Permissions.isGM(g.ns.roster, "Ann Oak"), "the real GM is still the GM")
  end
end)

test("A1 Sync / Model: a record whose author is not canonical is refused as «alias» (live, relayed, own disk)", function()
  local ns = boot(F())
  local S = ns.Sync
  for _, a in ipairs(ALIASES) do
    local function rec() return { k = "profile", id = a, a = a, ts = 1000050, sq = 1, d = { note = "x" } } end
    local _, w1 = S.Apply(rec(), "Bob Stone"); eq(w1, "alias", "relayed by Bob: " .. a)
    local _, w2 = S.Apply(rec(), "Ann Oak"); eq(w2, "alias", "from the GM herself: " .. a)
    local _, w3 = S.Apply(rec()); eq(w3, "alias", "own disk: " .. a)
    eq(ns.state.profiles[a], nil, "stored under " .. a)
  end
  -- the canonical spelling is untouched (control)
  local okC, wC = S.Apply({ k = "profile", id = "Bob Stone", a = "Bob Stone", ts = 1000050, sq = 1, d = { note = "real" } }, "Bob Stone")
  ok(okC, "canonical author applied: " .. tostring(wC))
  -- my own identity under another spelling: never «mine» for P2P, refused before it
  local _, wMe = S.Apply({ k = "profile", id = "kas pitas", a = "kas pitas", ts = 1000050, sq = 1, d = { note = "me?" } }, "Bob Stone")
  eq(wMe, "alias", "an alias of me")
end)

test("A1 Model: the names inside a record must be canonical too (squad, reject, settings, roster, rsvp, grant, transfer)", function()
  local ns = boot(F())
  local S, me = ns.Sync, ns.me()
  local t = 1000050
  local function why(r) local _, w = S.Apply(r); return w end
  local base = function(members, bench, captain)
    return { k = "squad", id = me .. ":1", a = me, ts = t, sq = 2, d = { name = "Lobos", captain = captain or me, members = members, bench = bench or {},
             icon = 1, color = 1, border = 1, tags = {}, open = true } }
  end
  eq(why(base({ me, "ann oak" })), "alias", "squad member")
  eq(why(base({ me }, { "Bob Stone-RealmA" })), "alias", "squad bench")
  eq(why(base({ me, "Ann" }, {}, "Ann")), "alias", "squad captain")
  local sx = base({ me }); sx.d.xferFrom = "Kas-" .. MY; eq(why(sx), "alias", "squad xferFrom")
  eq(why({ k = "reject", id = me .. ":1|ann oak|req", a = me, ts = t, sq = 3, d = { sid = me .. ":1", name = "ann oak", kind = "req" } }), "alias", "reject name")
  eq(why({ k = "settings", id = "settings", a = "Ann Oak", ts = t, sq = 4, d = { squadsEnabled = true, rlList = { "bob stone" } } }), "alias", "settings rlList")
  eq(why({ k = "profile", id = me, a = me, ts = t, sq = 5, d = { note = "x", xferTo = me .. ":1>Kas-Mora" } }), "alias", "profile xferTo")
  eq(why({ k = "achgrant", id = "a1|ann oak", a = "Ann Oak", ts = t, sq = 6, d = { ach = "a1", who = "ann oak" } }), "alias", "grant who")
  eq(why({ k = "rsvp", id = "r1|Bob", a = me, ts = t, sq = 7, d = { rid = "r1", name = "Bob", v = "yes" } }), "alias", "rsvp name")
  eq(why({ k = "attendance", id = "r1", a = "Ann Oak", ts = t, sq = 8, d = { rid = "r1", names = { me, "kas mora" }, at = t } }), "alias", "attendance names")
  eq(why({ k = "witness", id = "w1", a = me, ts = t, sq = 9, d = { rid = "w1", names = { "Kas Mora-" .. MY } } }), "alias", "witness names")
  eq(why({ k = "roster", id = "x1", a = me, ts = t, sq = 10, d = { raid = "custom", size = 10, name = "Raid", at = t, st = "open", owner = "kas pitas", main = { "" }, bench = {} } }), "alias", "raid roster owner")
  -- empty raid slots are not names (control): the same roster with a canonical owner is not refused as alias
  local w = why({ k = "roster", id = "x2", a = me, ts = t, sq = 11, d = { raid = "custom", size = 10, name = "Raid", at = t, st = "open", owner = me, main = { "", me }, bench = {} } })
  ok(w ~= "alias", "empty slots / canonical names: " .. tostring(w))
end)

test("A1 roster path: for decisions over data an alias of the GM is neither GM, officer nor member (ns.rosterStrict)", function()
  local ns = boot(F())
  local P = ns.Permissions
  ok(type(ns.rosterStrict) == "function", "ns.rosterStrict")
  ok(P.isGM(ns.rosterStrict, "Ann Oak") and P.isOfficer(ns.rosterStrict, "Ann Oak", {}), "the GM by her identity")
  for _, a in ipairs(ALIASES) do
    ok(not P.inGuild(ns.rosterStrict, a) and not P.isGM(ns.rosterStrict, a) and not P.isOfficer(ns.rosterStrict, a, {}), a)
  end
  -- the GM's settings live from her client but authored under another spelling: refused, the settings unchanged
  local before = ns.Model.settingsOf(ns.state).squadsEnabled
  local _, w = ns.Sync.Apply({ k = "settings", id = "settings", a = "ann oak", ts = 1000050, sq = 1, d = { squadsEnabled = not before } }, "Ann Oak")
  eq(w, "alias", "GM settings by an alias"); eq(ns.Model.settingsOf(ns.state).squadsEnabled, before, "settings unchanged")
end)

test("A1 keys: a relayed key, a manifest or a rotation under an alias is never kept, my own alias included (D3)", function()
  local ns = boot(F())
  local T, db = ns.Trust, ns.trustDB
  local pk = string.rep("ab", 32)
  for _, a in ipairs({ "Ann-" .. MY, "ann oak", "kas pitas", "Kas Mora-" .. MY, "Bob" }) do
    local rec = { k = "profile", id = a, a = a, ts = 1000050, sq = 1, d = { note = "ghost" } }
    ns.Sync.OnMessage("D", { r = { rec }, ks = { [a] = pk }, kr = { [a] = string.rep("cd", 64) } }, "Bob Stone", "GUILD")
    eq(db.pend[a], nil, "candidate key under " .. a); eq(db.keys[a], nil, "key under " .. a)
  end
  eq(ns.Sync.RotPending(), 0, "no rotation queued for an alias")
  local n = aliasCount(select(4, boot(F())))
  ok(n == 0, "a fresh client counts 0 aliases: " .. tostring(n))
end)

test("A1 W envelope: only my exact identity is the recipient", function()
  local ns = boot(F())
  ok(ns.Comm.ForMe("Kas Pitas"), "my identity")
  for _, a in ipairs({ "kas pitas", "KAS PITAS", "Kas Pitas-" .. MY, "Kas-Pitas", " Kas Pitas", "Kas  Pitas" }) do
    eq(ns.Comm.ForMe(a), false, a)
  end
end)

test("A1 saved data: keys, manifests, certificates, pending copies and records under an alias go at load (counted)", function()
  local KEY = "Por Honor-" .. MY
  local pk, pk2, sig = string.rep("ab", 32), string.rep("cd", 32), string.rep("0", 128)
  local ghostRec = { k = "profile", id = "ann oak", a = "ann oak", ts = 1000000, sq = 1, d = { note = "ghost" } }
  local db = {
    idv = { ["Kas Pitas"] = 2 },
    guilds = { [KEY] = {
      idv = 2,
      records = { ghostRec, { k = "profile", id = "Bob Stone", a = "Bob Stone", ts = 1000000, sq = 1, d = { note = "real" } } },
      trust = { keys = { ["ann oak"] = { pk = pk, s = "cert", t = 1 }, ["Bob Stone"] = { pk = pk2, s = "strong", t = 1 } },
                pend = { ["Ann-" .. MY] = { [pk] = { by = { ["Bob Stone"] = 1 }, t = 1 } } },
                contested = { ["Ann"] = 1 }, suspects = {}, alerts = {} },
      sig = { man = { ["ann oak"] = { n = 1, h = {}, s = sig, strength = "cert", pk = pk } } },
      cert = { crt = { ["ann oak"] = { n = 1, pk = pk, e = {}, s = sig } } },
      p2p = { pend = { ["profile:ann oak"] = { ["1000000.1.ann oak"] = { r = ghostRec, by = { ["Bob Stone"] = 1 }, t = 1 } } } },
    } },
  }
  local ns, env, fire, diag = boot(F({ db = db }))
  ok(ns.gdb, "partition loaded")
  eq(ns.state.profiles["ann oak"], nil, "ghost record applied from disk")
  ok(ns.state.profiles["Bob Stone"], "the canonical record from disk is applied (control)")
  eq(ns.trustDB.keys["ann oak"], nil, "key"); ok(ns.trustDB.keys["Bob Stone"], "canonical key kept")
  eq(ns.trustDB.pend["Ann-" .. MY], nil, "pend"); eq(ns.trustDB.contested["Ann"], nil, "contested")
  eq(ns.sigDB.man["ann oak"], nil, "manifest"); eq(ns.certDB.crt["ann oak"], nil, "certificate")
  local pend = ns.state.p2p and ns.state.p2p.pend or {}
  eq(pend["profile:ann oak"], nil, "pending copy")
  local n = aliasCount(diag)
  ok(n and n >= 6, "counted: " .. tostring(n))
end)

-------------------------------------------------------------------------------
-- M1 (D4)
test("M1 (D4): realm at ADDON_LOADED, the roster before PLAYER_LOGIN, forever at PLAYER_LOGIN: forever, migrated", function()
  local on = false
  local ns, env, fire = client(F({ regional = function() return on end }))
  fire("ADDON_LOADED", "GuildSquads")
  fire("GUILD_ROSTER_UPDATE")
  on = true
  fire("PLAYER_LOGIN")
  eq(ns.ID_MODE, "forever", "mode"); eq(ns.me(), "Kas Pitas", "me")
  ok(ns.rosterReady, "roster read in the final mode")
  ok(ns.roster(ns.me()) ~= nil, "me in the roster")
  eq(ns.gdb and ns.gdb.idv, 2, "the partition migrated")
  eq(env.GuildSquadsDB.idv and env.GuildSquadsDB.idv["Kas Pitas"], 2, "my character migrated")
  for k in pairs(ns.rosterList()) do ok(not k:find("-", 1, true), "a realm key in the roster: " .. k) end
  fire("GUILD_ROSTER_UPDATE")
  eq(ns.ID_MODE, "forever", "frozen")
end)

test("M1: the mode flips with the partition already loaded (the API appears late): dropped, read again and migrated", function()
  local o = F(); o.regional = nil                  -- no RegionalUniqueNamesEnabled at ADDON_LOADED
  local ns, env, fire = client(o)
  fire("ADDON_LOADED", "GuildSquads")
  fire("GUILD_ROSTER_UPDATE")                        -- no RegionalUniqueNamesEnabled yet: realm, read now
  eq(ns.ID_MODE, "realm"); ok(ns.rosterReady and ns.gdb, "realm partition loaded")
  env.RegionalUniqueNamesEnabled = function() return true end
  fire("PLAYER_LOGIN")
  eq(ns.ID_MODE, "forever"); eq(ns.me(), "Kas Pitas")
  ok(ns.rosterReady and ns.roster("Kas Pitas") ~= nil, "roster in forever keys")
  eq(ns.gdb and ns.gdb.idv, 2, "migrated")
  for k in pairs(ns.rosterList()) do ok(not k:find("-", 1, true), "a realm key in the roster: " .. k) end
end)

test("M1: no flip keeps the order of reads; an addon loaded after login takes its mode at ADDON_LOADED", function()
  local ns, env, fire = client(F({ regional = function() return false end }))
  fire("ADDON_LOADED", "GuildSquads"); fire("GUILD_ROSTER_UPDATE"); fire("PLAYER_LOGIN")
  eq(ns.ID_MODE, "realm"); ok(ns.rosterReady, "realm: read by PLAYER_LOGIN"); eq(ns.me(), "Kas-" .. MY)
  local ns2, env2, fire2 = client(F({ loggedIn = true }))
  fire2("ADDON_LOADED", "GuildSquads"); fire2("GUILD_ROSTER_UPDATE")
  eq(ns2.ID_MODE, "forever"); ok(ns2.rosterReady, "logged in already: no PLAYER_LOGIN to wait for")
  eq(ns2.gdb and ns2.gdb.idv, 2)
end)

-------------------------------------------------------------------------------
-- B2: rule (b), idempotence, as a property over odd forms (both modes, with and without the roster)
local function index(names, mode, myRealm)
  local ix = I.newIndex()
  for _, raw in ipairs(names) do
    local first, surname, realm = I.split(raw)
    local key = mode == "forever" and (surname and (first .. " " .. surname)) or I.realmKey(raw, myRealm)
    if key then I.indexAdd(ix, key, first, surname, realm or myRealm) end
  end
  return ix
end
local NAMES = { "Kas Pitas-" .. MY, "Kas Mora-" .. MY, "Ann Oak-" .. MY, "Kás Pítas-RealmA", "Ñandú Ébano-" .. MY, "Bob Stone-RealmA" }
local CTXS = {
  { mode = "forever", myRealm = MY, index = index(NAMES, "forever", MY) },
  { mode = "forever", myRealm = MY, index = I.newIndex() },
  { mode = "realm", myRealm = MY, index = index(NAMES, "realm", MY) },
}
test("B2 property: I.id(I.id(x)) == I.id(x) over odd forms; in forever no «-» and no blank at the ends or doubled", function()
  local firsts = { "Kas", "kas", "KAS", "Kás", "ñandú", "Ann", "Gm" }
  local seps = { " ", "  ", "-", " -", "- ", "--", " - ", "\t" }
  local surs = { "Pitas", "pitas", "Pítas", "Oak", "", "Pitas Mora" }
  local tails = { "", "-" .. MY, "-RealmA", "-Realm With Spaces", "--Realm", " -Realm", "- Realm", "-", " " }
  local pads = { "", " " }
  local bs = { "", "Pitas", " Pitas", "X-Y", MY, "RealmA", " Pitas -R", "-", "Pitas Mora" }
  local n, bad = 0, {}
  local function check(x, b)
    for ci, ctx in ipairs(CTXS) do
      local y = I.id(x, b, ctx)
      n = n + 1
      if y ~= nil then
        local z = I.id(y, nil, ctx)
        local why
        if z ~= y then why = "not idempotent: " .. tostring(z)
        elseif ctx.mode == "forever" and y:find("-", 1, true) then why = "a dash"
        elseif ctx.mode == "forever" and (y:sub(1, 1) == " " or y:sub(-1) == " " or y:find("  ", 1, true)) then why = "blanks" end
        if why and #bad < 12 then bad[#bad + 1] = ("[%d] %q,%s -> %q: %s"):format(ci, x, b == nil and "nil" or ("%q"):format(b), y, why) end
      end
    end
  end
  for _, p in ipairs(pads) do
    for _, f in ipairs(firsts) do
      for _, s in ipairs(seps) do
        for _, u in ipairs(surs) do
          for _, t in ipairs(tails) do check(p .. f .. s .. u .. t .. p, nil) end
        end
      end
      for _, b in ipairs(bs) do check(p .. f .. p, b); check(f .. "-" .. MY, b) end
    end
  end
  ok(n > 15000, "battery size " .. n)
  ok(#bad == 0, #bad .. " counterexamples:\n" .. table.concat(bad, "\n"))
  -- the reviewer's case (B2)
  local F1 = CTXS[1]
  eq(I.id("Kas Pitas -Realm", nil, F1), "Kas Pitas"); eq(I.id("Kas", "X-Y", CTXS[2]), "Kas X")
end)

test("B2 property on the addon: ns.id(ns.id(x)) == ns.id(x) with the roster loaded, and ns.id(x) == x for every identity", function()
  local ns = boot(F())
  for key in pairs(ns.rosterList()) do eq(ns.id(key), key, "identity " .. key) end
  for _, x in ipairs({ "Kas Pitas -" .. MY, "kas pitas", " Kas  Pitas ", "Kas-Pitas", "Ann-" .. MY, "Ann", "Bob Stone-RealmA",
                       "Kas Pitas-RealmA-B", "Kas--" .. MY, "Kas - Pitas", "Ann Oak -", "Ann -Oak", "Kas\tPitas" }) do
    local y = ns.id(x)
    if y then eq(ns.id(y), y, ("%q"):format(x)) end
  end
end)

-------------------------------------------------------------------------------
-- the trivial lows of review D
test("B8: a race observation keeps «name>squad id» whole for a 64-byte name and its squad (sqm cap)", function()
  local R = NS.Races
  local name = string.rep("Ж", 12) .. " " .. string.rep("Ж", 12) .. string.rep("x", 15)   -- 49 + 15 = 64 bytes
  local sid = name .. ":" .. "1700000000"
  local entry = name .. ">" .. sid
  eq(#entry, 140, "fixture length")
  local ev = R.sanitize({ t = "kill", who = name, by = name, ts = 1700000000, inst = "Foo", it = "raid", enc = 1, pres = { name }, sqm = { entry } })
  ok(ev and ev.sqm, "sanitized")
  eq(ev.sqm[1], entry, "the entry is not cut")
end)

test("B4: rejecting a typed name that matches nobody in the roster stores no rejection", function()
  local ns, env, fire, diag, printed = boot(F())
  local A = ns.Actions
  local before = 0
  for _ in pairs(ns.state.rejects or {}) do before = before + 1 end
  A.Reject("Kas Pitas:1", "Nadie Nunca", "req")
  local after = 0
  for _ in pairs(ns.state.rejects or {}) do after = after + 1 end
  eq(after, before, "rejection stored for a name outside the roster")
end)

test("B10: the manual whisper of a name the roster does not know never opens «/w» with a «-Realm»", function()
  local ns, env = boot(F())
  local told = {}
  env.ChatFrame_SendTell = function(n) told[#told + 1] = n end
  ok(ns.UI and ns.UI.Whisper, "ns.UI.Whisper")
  ns.UI.Whisper("Zed Nadie-" .. MY)
  ns.UI.Whisper("Ann Oak-" .. MY)
  eq(told[1], "Zed Nadie", "unknown name: no realm suffix")
  eq(told[2], "Ann Oak", "known: the whisper target")
end)
