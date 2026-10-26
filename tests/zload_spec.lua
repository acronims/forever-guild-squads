-- Smoke test: load every file in GuildSquads.toc order against a permissive fake WoW API, fire the bootstrap
-- events, open the window, visit every tab (incl. Crear squad), open context menus and click every registered
-- button. Catches load/runtime Lua errors only; it says nothing about how the real client renders or behaves.
local scripts = {}
local created = { templates = {}, failed = {} }
local NUMERIC = { GetStringWidth = 60, GetWidth = 100, GetHeight = 20, GetFrameLevel = 3, GetEffectiveScale = 1, GetNumPoints = 1 }
-- geometry model. Every frame/texture/fontstring records its parent, its anchors (SetPoint /
-- SetAllPoints / ClearAllPoints), its size (SetSize / SetWidth / SetHeight) and its visibility (Show / Hide /
-- SetShown). GetWidth / GetHeight return the recorded size (100 x 20 when never set).
-- Limits of the model: no scale, no strata, no text measuring (GetStringWidth is always 60), no template
-- geometry (templates add no anchors or sizes), anchors to UIParent / named strings are not resolved, and an
-- element with only a CENTER-type anchor uses its recorded or default size; a fontstring without a width is
-- 7 px per character of its last SetText (UTF-8 bytes, colour codes included) - a rough stand-in for the font. Good enough to compute the left x
-- of top-row elements and the bottom tabs relative to the window; it is NOT how the client lays things out.
local allObjs = {}
local GEO = {
  SetPoint = function(self, point, a, b, c, d)
    local rel, relPoint, x, y
    if type(a) == "table" then
      rel = a
      if type(b) == "string" then relPoint, x, y = b, c, d else relPoint, x, y = point, b, c end
    else rel, relPoint, x, y = nil, point, a, b end
    local pts = rawget(self, "_pts") or {}
    for i = #pts, 1, -1 do if pts[i][1] == point then table.remove(pts, i) end end
    pts[#pts + 1] = { point, rel or rawget(self, "_parent"), relPoint or point, tonumber(x) or 0, tonumber(y) or 0 }
    rawset(self, "_pts", pts); rawset(self, "_all", nil)
  end,
  ClearAllPoints = function(self) rawset(self, "_pts", {}); rawset(self, "_all", nil) end,
  SetAllPoints = function(self, rel) rawset(self, "_all", rel or rawget(self, "_parent") or true); rawset(self, "_pts", {}) end,
  SetSize = function(self, w, h) rawset(self, "_w", w); rawset(self, "_h", h) end,
  SetWidth = function(self, w) rawset(self, "_w", w) end,
  SetHeight = function(self, h) rawset(self, "_h", h) end,
  GetWidth = function(self) return rawget(self, "_w") or 100 end,
  GetHeight = function(self) return rawget(self, "_h") or 20 end,
  Show = function(self) rawset(self, "_vis", true) end,
  Hide = function(self) rawset(self, "_vis", false) end,
  SetShown = function(self, v) rawset(self, "_vis", v and true or false) end,
  SetEnabled = function(self, v) rawset(self, "_enabled", v and true or false) end,
  SetText = function(self, t) rawset(self, "_text", t) end,
}
local stub
local function child(self) local c = stub(); rawset(c, "_parent", self); return c end
local function fsChild(self) local c = child(self); rawset(c, "_fs", true); return c end
stub = function()
  local s = {}
  allObjs[#allObjs + 1] = s
  return setmetatable(s, { __index = function(t, k)
    if GEO[k] then return GEO[k] end
    if k == "CreateFontString" then return fsChild end
    if k == "CreateTexture" or k == "CreateMaskTexture" then return child end
    if k == "GetText" then return function() return "" end end
    if k == "GetChecked" or k == "IsShown" or k == "IsMouseOver" then return function() return false end end
    if k == "IsEnabled" then return function() return true end end
    if NUMERIC[k] then return function() return NUMERIC[k] end end
    if k == "GetCenter" then return function() return 500, 400 end end
    if k == "GetScript" then return function(self, ev) return rawget(self, "_" .. ev) end end
    if k == "SetScript" or k == "HookScript" then
      return function(self, ev, fn) scripts[#scripts + 1] = { self, ev, fn }; rawset(self, "_" .. ev, fn) end
    end
    if type(k) ~= "string" or not k:match("^[A-Z]") then return nil end -- own fields start lowercase: unset = nil
    local f = function() return stub() end
    rawset(t, k, f)
    return f
  end })
end
local clock = 100
-- templates that "do not exist" in this fake client, to exercise every fallback chain
local MISSING = { PortraitFrameTemplate = true, ButtonFrameTemplate = true, PanelTabButtonTemplate = true,
                  SearchBoxTemplate = true, InsetFrameTemplate = true }
CreateFrame = function(kind, name, parent, tpl)
  if tpl and MISSING[tpl] then created.failed[tpl] = true; error("Unknown template " .. tpl) end
  if tpl then created.templates[tpl] = true end
  local f = stub()
  rawset(f, "_parent", parent)
  if name then _G[name] = f end
  return f
end
-- atlas lookups: nil (=> file fallback) except exactly once, to exercise SetAtlas too
local atlasCalls, atlasHits = 0, 0
C_Texture = { GetAtlasInfo = function(name)
  atlasCalls = atlasCalls + 1
  if atlasCalls == 3 then atlasHits = atlasHits + 1; return { width = 16, height = 16, file = 1 } end
  return nil
end }
UIParent, ChatFontNormal, UISpecialFrames, GameTooltip, Minimap = stub(), stub(), {}, stub(), stub()
RaidWarningFrame, UIErrorsFrame = stub(), stub()
ChatTypeInfo = { RAID_WARNING = { r = 1, g = 0.3, b = 0.1 } }
RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PRIEST = { r = 1, g = 1, b = 1 } }
StaticPopupDialogs = {}
local popups = {}
StaticPopup_Show = function(which, text, _, data) popups[#popups + 1] = { which, text, data } end
tinsert = table.insert
GetTime = function() return clock end
GetServerTime = function() return 1000 + clock end
GetLocale = function() return "esES" end
GetNormalizedRealmName = function() return "Realm" end
GetCursorPosition = function() return 300, 300 end
GetZoneText = function() return "Los Baldíos" end
GetSubZoneText = function() return "El Cruce" end
GetRealZoneText = function() return "Los Baldíos" end
UnitName = function() return "Ann" end
UnitClass = function() return "Warrior", "WARRIOR" end
UnitLevel = function() return 20 end
UnitRace = function() return "Human", "Human" end
IsInGuild = function() return true end
local combat = false
InCombatLockdown = function() return combat end
GetNumGuildMembers = function() return 3 end
local roster = { { "Ann-Realm", "GM", 0, 20, "Warrior", "Los Baldíos", "", "", true, 0, "WARRIOR" },
                 { "Bob-Realm", "Member", 4, 22, "Priest", "Los Baldíos", "", "", true, 0, "PRIEST" },
                 { "Cid-Realm", "Member", 4, 19, "Mage", "Durotar", "", "", true, 0, "MAGE" } }
GetGuildRosterInfo = function(i) return table.unpack(roster[i]) end
C_GuildInfo = { GuildRoster = function() end }
local invited = {}
C_PartyInfo = { InviteUnit = function(n) invited[#invited + 1] = n end }
local whispers = {}
C_ChatInfo = { RegisterAddonMessagePrefix = function() end,
               SendAddonMessage = function(_, msg, channel, target) if channel == "WHISPER" then whispers[#whispers + 1] = target end; return 0 end }
SlashCmdList = {}
print = function() end

local ns = {}
local toc = {}
for line in SOURCES["GuildSquads.toc"]:gmatch("[^\r\n]+") do
  if line:match("%.lua$") then toc[#toc + 1] = (line:gsub("\\", "/")) end
end

test("all files load in TOC order with the fake API", function()
  ok(#toc >= 17, "toc lists the files (" .. #toc .. ")")
  for _, f in ipairs(toc) do
    ok(SOURCES[f], "run.js preloads " .. f)
    loadmod(f, ns)
  end
  ok(ns.UI and ns.Actions and ns.Sync and ns.Comm and ns.Call and ns.Minimap, "modules present")
  eq(ns.L.TAB_FINDER, "Buscador", "Spanish locale active for esES")
end)

local function fire(ev, ...)
  for _, s in ipairs(scripts) do if s[2] == "OnEvent" then s[3](s[1], ev, ...) end end
end
local function visitAll()
  for _, key in ipairs(ns.UI.order) do ns.UI.Select(key) end
end

test("bootstrap, actions, every tab, Crear squad and fallbacks run without Lua errors", function()
  fire("ADDON_LOADED", "GuildSquads")
  fire("PLAYER_LOGIN")
  fire("GUILD_ROSTER_UPDATE")
  ok(ns.rosterReady, "roster ready"); eq(ns.roster("Bob").rank, 4); eq(ns.roster("Bob").zone, "Los Baldíos")
  ok(ns.state.profiles["Ann-Realm"], "own profile published")
  SlashCmdList.GUILDSQUADS("")             -- open with no squad: empty state of Mi squad
  visitAll()
  ns.UI.OpenCreate("new")                   -- Crear squad, step 1 and step 2
  eq(ns.UI.Current(), "create")
  ok(ns.Actions.SaveProfile({ role = "TANK", avail = "11000000", goals = { "dungeons" } }))
  ok(ns.Actions.CreateSquad({ name = "Los Lobos", icon = 3, color = 2, border = 2,
     tags = { "dungeons", "raid", "bg", "farm", "free text" }, open = true }))
  local id = ns.Actions.MySquadId(); ok(id, "in squad")
  ok(deq(ns.state.squads[id].d.tags, { "dungeons", "raid", "bg" }), "tags cleaned to 3 goal keys")
  ok(ns.Actions.AddMember(id, "Bob"))
  ok(ns.Actions.SaveSettings({ squadsEnabled = true, bench = 1, minCreateRank = 4, officerRanks = { 1 }, banned = {} }))
  visitAll()
  ns.UI.OpenCreate("edit"); ns.UI.OpenCreate("logo")
  ok(created.failed.PortraitFrameTemplate and created.templates.BasicFrameTemplateWithInset, "window fell back to BasicFrameTemplateWithInset")
  ok(created.failed.PanelTabButtonTemplate and created.templates.CharacterFrameTabButtonTemplate, "tabs fell back")
  ok(created.failed.SearchBoxTemplate and created.templates.InputBoxTemplate, "search fell back to InputBoxTemplate")
  ok(atlasCalls > 20 and atlasHits == 1, "atlas lookups exercised both paths (" .. atlasCalls .. ")")
  ns.Actions.InviteSquadToGroup(id)
  SlashCmdList.GUILDSQUADS("export"); SlashCmdList.GUILDSQUADS("debug"); SlashCmdList.GUILDSQUADS("sync")
  SlashCmdList.GUILDSQUADS("minimap"); SlashCmdList.GUILDSQUADS("ui")
  local rep = ns.W.ReportLines()
  ok(rep[2]:find("PortraitFrameTemplate", 1, true) and rep[4]:find("roleicon", 1, true), "ui report lists fallbacks: " .. rep[2])
  ok(ns.Comm.Pending() > 0, "messages queued")
end)

test("context menus, popups and every registered click/enter handler run without errors", function()
  local menus = 0
  local origMenu = ns.W.Menu
  ns.W.Menu = function(owner, items) menus = menus + 1; ok(#items >= 2, "menu has items"); return origMenu(owner, items) end
  local errors, n = {}, 0
  local seen = {}
  for pass = 1, 2 do
    local list = {}
    for i, s in ipairs(scripts) do list[i] = s end
    for _, s in ipairs(list) do
      local ev = s[2]
      if (ev == "OnClick" or ev == "OnEnter" or ev == "OnLeave" or ev == "OnDoubleClick" or ev == "OnMouseDown"
          or ev == "OnMouseUp" or ev == "OnTextChanged" or ev == "OnMouseWheel" or ev == "OnDragStart" or ev == "OnUpdate")
          and s[3] and not seen[s[3]] then
        seen[s[3]] = true
        for _, btn in ipairs({ "LeftButton", "RightButton" }) do
          n = n + 1
          local okc, e = pcall(s[3], s[1], ev == "OnMouseWheel" and -1 or (ev == "OnUpdate" and 0.1 or btn))
          if not okc then errors[#errors + 1] = ev .. ": " .. tostring(e) end
        end
      end
    end
    -- accept every confirmation that was asked for (destructive actions go through StaticPopup)
    for _, p in ipairs(popups) do if type(p[3]) == "function" then local okp, e = pcall(p[3], "Cid"); if not okp then errors[#errors + 1] = "popup: " .. tostring(e) end end end
    popups = {}
  end
  ns.W.Menu = origMenu
  ok(#errors == 0, #errors .. " handler errors, first: " .. tostring(errors[1]))
  ok(n > 200, "handlers exercised: " .. n)
  ok(menus >= 3, "context menus opened: " .. menus)
end)

test("call to squad: whisper to online members, cooldown, receiver anti-spam, never in combat", function()
  -- fresh state: the click-everything pass above saved settings (squads off) and may have disbanded the squad
  -- it also accepted every Ajustes > Logros popup with the text "Cid" (renamed races, bulk off, grants):
  -- drop that catalog and drain its bulk records from the queue so the next checks start clean
  ns.state.achdefs, ns.state.achgrants = {}, {}
  ns.HallGlue.MarkDirty()
  for _ = 1, 3000 do clock = clock + 1; ns.Comm.queue:pump(clock) end
  clock = clock + 5
  ok(ns.Actions.SaveSettings({ squadsEnabled = true, bench = 1, minCreateRank = 4, officerRanks = { 1 }, banned = {} }))
  if not ns.Actions.MySquadId() then
    clock = clock + 10
    ok(ns.Actions.CreateSquad({ name = "Los Lobos " .. clock, icon = 1, color = 1, border = 1, tags = {}, open = true }))
  end
  local id = ns.Actions.MySquadId(); ok(id, "has squad")
  ns.Actions.AddMember(id, "Bob")
  ns.state.profiles["Bob-Realm"] = { k = "profile", id = "Bob-Realm", a = "Bob-Realm", ts = 1, sq = 1, d = { squad = id } }
  clock = clock + 400
  combat = true
  ok(not ns.Actions.CallSquad(), "blocked in combat")
  combat = false
  whispers = {}
  ok(ns.Actions.CallSquad(), "call sent")
  ok(not ns.Actions.CallSquad(), "cooldown blocks a second call")
  local mem = ns.Model.members(ns.state, id)
  ok(#mem >= 2, "Bob is a member: " .. table.concat(mem, ","))
  for _ = 1, 600 do clock = clock + 1; ns.Comm.queue:pump(clock) end
  eq(ns.Comm.Pending(), 0, "queue drained")
  local toBob = false
  for _, t in ipairs(whispers) do if t == "Bob-Realm" then toBob = true end end
  ok(toBob, "whispered Bob")
  local shown = 0
  RaidNotice_AddMessage = function() shown = shown + 1 end
  ns.Sync.OnMessage("C", { z = "Durotar", s = "" }, "Bob-Realm")
  ns.Sync.OnMessage("C", { z = "Durotar", s = "" }, "Bob-Realm")
  eq(shown, 1, "receiver shows one call per sender per 5 min")
  ns.Sync.OnMessage("C", { z = "Durotar" }, "Cid-Realm")
  eq(shown, 1, "calls from non-members are ignored")
  fire("PLAYER_LOGOUT")
  -- records live under GuildSquadsDB.guilds[guildKey]
  local g = ns.gdb
  ok(g and GuildSquadsDB.guilds[ns.guildKey] == g and type(g.records) == "table" and #g.records >= 3, "saved per guild")
  ok(GuildSquadsDB.records == nil, "nothing at top level")
end)

-- smoke: Ranking tab for every category and wipe, fake ENCOUNTER_END / PLAYER_LEVEL_UP, witness via
-- a replicated event, forged event rejected, achievement toast. Fake API only: says nothing about the real client.
local function tick(n)
  for _ = 1, n or 1 do
    clock = clock + 1
    for _, s in ipairs(scripts) do if s[2] == "OnUpdate" then pcall(s[3], s[1], 1) end end
  end
end

test("ranking: fake ENCOUNTER_END + PLAYER_LEVEL_UP, witnesses, every category/wipe, toast", function()
  clock = clock + 20
  ok(ns.Actions.SaveSettings({ squadsEnabled = true, bench = 1, minCreateRank = 4, officerRanks = { 1 }, banned = {},
                               compEnabled = true, seasonKind = "weekly", wLevel = 1, wDungeon = 1, wRaid = 1, weekCap = 100, guildGoal = 30 }))
  local G = ns.ProgressGlue
  ok(G and G.Enabled(), "competition enabled")
  local id = ns.Actions.MySquadId(); ok(id, "has squad")
  ns.Actions.AddMember(id, "Bob")
  ns.state.profiles["Bob-Realm"] = { k = "profile", id = "Bob-Realm", a = "Bob-Realm", ts = 1, sq = 1, d = { squad = id } }
  ok(ns.Model.isMember(ns.state, id, "Bob-Realm"), "Bob member")
  GetInstanceInfo = function() return "Hall of Thanes", "party", 1, "Normal", 5, 0, false, 9001 end
  local origUnitName = UnitName
  UnitName = function(u) if u == "party1" then return "Bob" end; return "Ann" end
  local shown = 0
  RaidNotice_AddMessage = function() shown = shown + 1 end
  fire("ENCOUNTER_START", 101, "Thane", 1, 5)
  fire("ENCOUNTER_END", 101, "Thane", 1, 5, 0) -- wipe: nothing
  fire("ENCOUNTER_END", 101, "Thane", 1, 5, 1)
  local mine
  for _, ev in pairs(G.Events()) do if ev.t == "boss" then mine = ev end end
  ok(mine, "boss event captured"); eq(mine.who, "Ann-Realm"); eq(mine.iid, 9001); eq(mine.it, "party")
  eq(mine.pres[1], "Bob-Realm", "Bob present in party")
  eq(G.Compute().squads[id] and G.Compute().squads[id].dKills or 0, 0, "one report: no points")
  -- forged: Cid claims to be Bob -> rejected; Bob's own report -> witnessed
  local bobEv = { t = "boss", who = "Bob-Realm", sid = id, ts = GetServerTime(), inst = "Hall of Thanes", it = "party",
                  enc = 101, boss = "Thane", pres = { "Ann-Realm" }, gold = 5 }
  ns.Sync.OnMessage("E", { e = { bobEv } }, "Cid-Realm")
  eq(G.Compute().squads[id].dKills, 0, "forged relay rejected")
  ns.Sync.OnMessage("E", { e = { bobEv } }, "Bob-Realm")
  local r = G.Compute().squads[id]
  eq(r.dKills, 1, "two witnesses score"); ok(r.dungeon > 0 and r.general > 0, "points")
  for _, ev in pairs(G.Events()) do eq(ev.gold, nil, "no economy fields stored") end
  -- level up (event handler defers 1 s)
  fire("PLAYER_LEVEL_UP", 21)
  tick(5)
  local lv
  for _, ev in pairs(G.Events()) do if ev.t == "level" then lv = ev end end
  ok(lv and lv.lv == 21, "level event captured")
  ok(G.Achievements("squad", id).firstDungeon, "achievement awarded")
  ok(shown >= 1, "achievement toast via RaidNotice_AddMessage")
  -- Ranking tab: every category x every wipe
  ns.UI.Open("ranking")
  eq(ns.UI.Current(), "ranking", "ranking tab visible")
  local rk = ns.UI.RankingState()
  for _, cat in ipairs({ "general", "level", "dungeon", "raid" }) do
    rk.cat = cat
    for back = 0, 8 do rk.back = back; ns.UI.Select("ranking") end
  end
  rk.back = 0; rk.cat = "dungeon"; ns.UI.Select("ranking")
  ok(rk.mine._OnEnter, "pinned card has a breakdown tooltip"); rk.mine._OnEnter(rk.mine)
  rk.cat = "raid"; ns.UI.Select("ranking")
  ok(rk.notice:GetText() ~= nil, "notice evaluated")
  local done, goal = G.GoalProgress(); eq(done, 1); eq(goal, 30)
  ns.UI.Select("mysquad")
  ok(ns.Comm.Pending() > 0 or ns.Comm.stats.sent > 0, "events queued for GUILD")
  -- hello with fewer of my events -> my own events are whispered back after jitter
  local before = #whispers
  ns.Sync.OnMessage("H", { h = {}, ec = {} }, "Bob-Realm")
  tick(21) -- jitter is 2-20 s

  for _ = 1, 60 do clock = clock + 1; ns.Comm.queue:pump(clock) end
  ok(#whispers > before, "own events re-sent to a peer that lacks them")
  UnitName = origUnitName
  ok(G.Debug():find("events=", 1, true))
end)

-- smoke: Ranking 5 categories + General x Wipe/Temporada, Overlord hint (absent, dismiss) and mock
-- present, Ajustes > Temporada (save + nueva temporada), /gsq diag, fake BG end and HK readings. Fake API only.
test("smoke: ranking 6 chips x wipe/season, overlord, Settings > Season, /gsq diag, PvP events", function()
  local G = ns.ProgressGlue
  local id = ns.Actions.MySquadId(); ok(id, "has squad")
  -- settings record (no season fields) still loads: defaults filled
  local s3 = ns.Model.settingsOf({ settings = { d = { squadsEnabled = true, seasonKind = "monthly", weekCap = 100 } } })
  eq(s3.seasonStart, ns.Progress.DEFAULT_SEASON_START); eq(s3.wPvp, 1); eq(s3.overlordOn, true)
  eq(G.Kind(), "weekly", "legacy monthly setting ignored: wipes are weekly")
  -- PvP: BG won (C_PvP missing -> GetBattlefieldWinner), HK readings outside / inside instances
  local inside = false
  IsInInstance = function() return inside, inside and "pvp" or "none" end
  UnitFactionGroup = function() return "Horde", "Horde" end
  GetBattlefieldWinner = function() return 0 end
  GetInstanceInfo = function() return "Warsong Gulch", "pvp", 0, "", 10, 0, false, 489 end
  local hk = 100
  GetPVPLifetimeStats = function() return hk, 0 end
  fire("PLAYER_ENTERING_WORLD"); hk = 112; fire("PLAYER_PVP_KILLS_CHANGED")
  inside = true; fire("PLAYER_ENTERING_WORLD"); hk = 140; fire("PLAYER_PVP_KILLS_CHANGED")
  fire("PVP_MATCH_COMPLETE", 0, 600)
  local bgEv
  for _, ev in pairs(G.Events()) do if ev.t == "bg" then bgEv = ev end end
  ok(bgEv and bgEv.win == 1 and bgEv.inst == "Warsong Gulch", "bg win captured")
  inside = false; fire("PLAYER_ENTERING_WORLD")
  G.FlushNow()
  local hkEv
  for _, ev in pairs(G.Events()) do if ev.t == "hk" then hkEv = ev end end
  ok(hkEv and hkEv.n == 12, "12 HK outside, 28 inside ignored: " .. tostring(hkEv and hkEv.n))
  -- Overlord absent: hint shown in World PvP, dismiss is permanent
  Overlord = nil
  GuildSquadsDB.hideOverlordHint = nil -- the click-everything pass above may have pressed the dismiss button
  ns.UI.Open("ranking")
  local rk = ns.UI.RankingState()
  for _, mode in ipairs({ "wipe", "season" }) do
    rk.mode = mode
    for _, cat in ipairs({ "general", "level", "dungeon", "raid", "pvp", "wpvp" }) do
      rk.cat = cat
      for back = 0, 8 do rk.back = back; ns.UI.Select("ranking") end
    end
  end
  rk.mode, rk.cat, rk.back = "wipe", "wpvp", 0
  ns.UI.Select("ranking")
  ok(G.OverlordHint(), "hint when Overlord missing")
  rk.ovHint.close._OnClick(rk.ovHint.close)
  ok(not G.OverlordHint() and GuildSquadsDB.hideOverlordHint, "hint dismissed forever (SavedVariables)")
  -- Overlord present (mock): read-only captures
  local calls = 0
  Overlord = { Leaderboard = { GetMaxCapturesForDedupName = function(_, name) calls = calls + 1; return 4 + calls end } }
  -- PLAYER_PVP_KILLS_CHANGED is debounced (~2 s): one sample per burst, so the clock
  -- moves and the timers run between the two bursts
  local function burst()
    fire("PLAYER_PVP_KILLS_CHANGED"); fire("PLAYER_PVP_KILLS_CHANGED")
    clock = clock + 3
    for _, o in ipairs(allObjs) do local fn = rawget(o, "_OnUpdate"); if fn then pcall(fn, o, 3) end end
  end
  fire("PLAYER_PVP_KILLS_CHANGED"); eq(calls, 0, "no synchronous read per kill")
  burst(); local c1 = calls; ok(c1 >= 1 and c1 <= 2, "one sample per burst (Progress + Hall): " .. c1); burst()
  ok(calls >= 2, "Overlord read"); G.FlushNow()
  local capEv
  for _, ev in pairs(G.Events()) do if ev.t == "cap" then capEv = ev end end
  ok(capEv and capEv.n >= 1, "capture delta recorded")
  Overlord = nil
  -- Ajustes > Temporada
  ns.UI.Open("settings"); eq(ns.UI.Current(), "settings")
  ns.UI.OpenSeasonEditor()
  local se = ns.UI.SeasonEditorState()
  ok(se.box and se.save and se.new, "season editor built")
  se.save._OnClick(se.save)
  se.new._OnClick(se.new)
  for _, p in ipairs(popups) do if type(p[3]) == "function" then p[3]() end end
  popups = {}
  -- /gsq diag
  SlashCmdList.GUILDSQUADS("diag")
  local rep = ns.DiagGlue.Report()
  ok(rep:find("[apis]", 1, true) and rep:find("PVP_MATCH_COMPLETE=", 1, true) and rep:find("[pvp] honorable kills: lifetime=", 1, true), rep:sub(1, 200))
  ok(GuildSquadsDB.diag and GuildSquadsDB.diag.events.PVP_MATCH_COMPLETE, "diag stored in SavedVariables")
  ok(#rep <= ns.Diag.MAX_BYTES)
end)

-------------------------------------------------------------------------------
-- smoke: every Ajustes section as GM and as non-GM (read only), save, unsaved-changes guard,
-- Reject buttons, "Mi squad" with the "Este wipe" panel and achievement progress. Fake API only.
local function vis(f) return rawget(f, "_vis") end
local function click(b, btn) local fn = rawget(b, "_OnClick"); ok(fn, "has OnClick"); fn(b, btn or "LeftButton") end
local function acceptPopups()
  local list = popups; popups = {}
  for _, p in ipairs(list) do if type(p[3]) == "function" then p[3]() end end
  return #list
end

test("smoke: Settings sections as GM, save and share, unsaved-changes guard", function()
  clock = clock + 30
  ok(ns.Actions.SaveSettings({ squadsEnabled = true, bench = 1, minCreateRank = 4, officerRanks = { 1 }, banned = {},
                               compEnabled = true, weekCap = 100, guildGoal = 30 }))
  popups = {}
  ns.UI.Open("settings"); eq(ns.UI.Current(), "settings")
  local st = ns.UI.SettingsState()
  eq(vis(st.ro), false, "GM: no read-only banner"); eq(rawget(st.primary, "_enabled"), true, "GM: save enabled")
  for _, k in ipairs({ "squads", "comp", "season", "integ", "mod" }) do
    ns.UI.SettingsSection(k)
    for _, k2 in ipairs({ "squads", "comp", "season", "integ", "mod" }) do eq(vis(st.sec[k2]), k2 == k, k .. " shows only " .. k) end
  end
  ok(#st.modRows == 8 and vis(st.modRows[1]), "moderation lists the squads")
  -- change a weight -> dirty; leaving the tab asks; accepting discards and leaves
  local wl
  for _, sg in ipairs(st.seg) do if sg.field == "wLevel" then wl = sg end end
  ok(wl, "weight control"); click(wl.buttons[4])
  ok(st.dirty and st.draft.wLevel == 3, "draft changed, dirty")
  ns.UI.Select("squads")
  eq(ns.UI.Current(), "settings", "unsaved changes keep you on Ajustes")
  eq(popups[#popups][2], ns.L.S_UNSAVED, "unsaved-changes confirmation asked")
  acceptPopups()
  eq(ns.UI.Current(), "squads", "discard and leave"); ok(not st.dirty)
  eq(ns.Model.settingsOf(ns.state).wLevel, 1, "discarded: not published")
  -- change again and save and share
  ns.UI.Select("settings")
  click(wl.buttons[1]); local cap
  for _, sg in ipairs(st.seg) do if sg.field == "weekCap" then cap = sg end end
  click(cap.buttons[3])
  local days
  for _, sg in ipairs(st.seg) do if sg.field == "inactiveDays" then days = sg end end
  click(days.buttons[3])
  -- season: date picker arrows + name, then save
  local before = st.draft.seasonStart
  st.dEnd.none:SetChecked(false); click(st.dEnd.none)
  ok(st.draft.seasonEnd > 0, "end date picked")
  click(st.primary)
  local s = ns.Model.settingsOf(ns.state)
  eq(s.wLevel, 0); eq(s.weekCap, 150); eq(s.inactiveDays, 30); ok(s.seasonEnd > 0); eq(s.seasonStart, before)
  ok(not st.dirty, "saved: clean")
  ns.UI.Select("squads"); eq(ns.UI.Current(), "squads", "no guard after saving")
  -- new season with confirmation
  ns.UI.Select("settings"); ns.UI.SettingsSection("season")
  local pastBefore = #(ns.Model.settingsOf(ns.state).seasonsPast or {})
  clock = clock + 5
  click(st.newSeason); eq(acceptPopups(), 1, "new season asks first")
  eq(#ns.Model.settingsOf(ns.state).seasonsPast, pastBefore + 1, "season closed into the read-only list")
end)

test("smoke: Settings as non-GM is read only", function()
  roster[1][3] = 4; fire("GUILD_ROSTER_UPDATE"); tick(2) --[[coalesced roster]]
  ok(not ns.Permissions.isGM(ns.roster, ns.me()), "Ann is no longer GM")
  ns.UI.Select("settings"); eq(ns.UI.Current(), "settings", "tab visible to members")
  local st = ns.UI.SettingsState()
  eq(vis(st.ro), true, "read-only banner"); eq(rawget(st.primary, "_enabled"), false, "save disabled")
  for _, c in ipairs(st.ctl) do eq(rawget(c, "_enabled"), false, "every control disabled") end
  local recBefore = ns.state.settings
  for _, k in ipairs({ "squads", "comp", "season", "integ", "mod" }) do ns.UI.SettingsSection(k); eq(vis(st.sec[k]), true) end
  for _, sg in ipairs(st.seg) do click(sg.buttons[1]) end
  ok(not st.dirty, "clicks do nothing")
  eq(ns.UI.SaveSettingsNow(), false, "save refused")
  eq(ns.state.settings, recBefore, "no record written")
  ns.UI.Select("squads"); eq(ns.UI.Current(), "squads", "no unsaved guard for read-only")
  roster[1][3] = 0; fire("GUILD_ROSTER_UPDATE"); tick(2) --[[coalesced roster]]
end)

test("smoke: My squad with This wipe panel, achievement progress, Reject buttons", function()
  clock = clock + 10
  local id = ns.Actions.MySquadId()
  if not id then
    ok(ns.Actions.CreateSquad({ name = "Lobos " .. clock, icon = 1, color = 1, border = 1, tags = {}, open = true })); id = ns.Actions.MySquadId()
  end
  ok(id, "has squad")
  -- Cid requests; captain rejects (synced record); repeated reject is a no-op
  ns.state.profiles["Cid-Realm"] = { k = "profile", id = "Cid-Realm", a = "Cid-Realm", ts = 2, sq = 1, d = { squad = id, reqAt = 77 } }
  eq(#ns.Model.requests(ns.state, id), 1)
  ns.UI.Select("mysquad")
  local sq = ns.UI.MySquadState()
  click(sq.req[1].no)
  eq(#ns.Model.requests(ns.state, id), 0, "rejected via Reject record")
  local n = 0; for _ in pairs(ns.state.rejects) do n = n + 1 end
  local sent = ns.Comm.Pending()
  ok(ns.Actions.Reject(id, "Cid", "req")); eq(ns.Comm.Pending(), sent, "repeat: nothing sent")
  local n2 = 0; for _ in pairs(ns.state.rejects) do n2 = n2 + 1 end
  eq(n2, n, "repeat: nothing stored")
  -- Este wipe
  ok(sq.wipe, "wipe panel built"); eq(vis(sq.wipe), true, "shown with competition on")
  eq(#sq.wipe.cells, 6)
  local r = sq.wipe:SetSquad(id)
  ok(r and r.dungeon ~= nil, "squad has points this wipe")
  -- achievement progress in the strip tooltips
  local prog = ns.ProgressGlue.AchievementProgress(id)
  ok(prog.boss10 and prog.boss10.need == 10, "progress available")
  ok(ns.UI.ProgressText({ cur = 3, need = 9, unit = "dungeon" }) == "3/9 mazmorras", ns.UI.ProgressText({ cur = 3, need = 9, unit = "dungeon" }))
  ok(ns.UI.ProgressText({ cur = 62, need = 100, unit = "hk" }) == "62/100 HK")
  local shownIcons = 0
  for _, b in ipairs(sq.ach.icons) do if vis(b) then shownIcons = shownIcons + 1 end end
  ok(shownIcons >= 3, "strip shows earned + in-progress achievements: " .. shownIcons)
  -- ranking export text
  ns.UI.Open("ranking")
  local txt = ns.UI.RankingText()
  ok(txt:find("1%. ") and txt:find(ns.L.PTS, 1, true), txt)
  click(ns.UI.RankingState().export)
end)

-------------------------------------------------------------------------------
-- geometry: with the model above, no element of the top row of any screen starts less than 70 px
-- from the window's left edge (portrait zone), and the visible bottom tabs are centred (+-10 px).
-- "Top row" = elements whose top edge is above y = -60 in window coordinates (the portrait reaches ~-54).
local function hfrac(p) if p:find("LEFT") then return 0 elseif p:find("RIGHT") then return 1 end return 0.5 end
local function vfrac(p) if p:find("TOP") then return 0 elseif p:find("BOTTOM") then return 1 end return 0.5 end
local function geo(f, win, depth)
  depth = depth or 0
  if f == win then return 0, 0, rawget(win, "_w") or 720, rawget(win, "_h") or 520 end
  if type(f) ~= "table" or depth > 60 or f == UIParent then return nil end
  local all = rawget(f, "_all")
  if all then
    if all == true then return nil end
    return geo(all, win, depth + 1)
  end
  local pts = rawget(f, "_pts")
  if not pts or #pts == 0 then return nil end
  local Lx, Rx, Cx, Ty, By, Cy
  for _, p in ipairs(pts) do
    local rl, rt, rw, rh = geo(p[2], win, depth + 1)
    if not rl then return nil end
    local rx = rl + hfrac(p[3]) * rw + p[4]
    local ry = rt - vfrac(p[3]) * rh + p[5]
    local hf, vf = hfrac(p[1]), vfrac(p[1])
    if hf == 0 then Lx = rx elseif hf == 1 then Rx = rx else Cx = rx end
    if vf == 0 then Ty = ry elseif vf == 1 then By = ry else Cy = ry end
  end
  local txt = rawget(f, "_fs") and rawget(f, "_text")
  local w = (Lx and Rx) and (Rx - Lx) or rawget(f, "_w") or (type(txt) == "string" and 7 * #txt) or 100
  local h = (Ty and By) and (Ty - By) or rawget(f, "_h") or 20
  local left = Lx or (Rx and Rx - w) or (Cx - w / 2)
  local top = Ty or (By and By + h) or (Cy + h / 2)
  return left, top, w, h, (Lx and Rx) and true or false
end
local function under(f, root)
  local p, n = f, 0
  while p and n < 60 do if p == root then return true end p = rawget(p, "_parent"); n = n + 1 end
  return false
end

test("geometry: top rows clear of the portrait (>= 70 px), bottom tabs centred (+-10 px)", function()
  local win = ns.UI.Window(); ok(win, "window built")
  eq(rawget(win, "_w"), 720)
  -- visit every screen (incl. Crear squad) so each refresh anchors its rows
  for _, key in ipairs(ns.UI.order) do ns.UI.Select(key) end
  ns.UI.OpenCreate("new")
  local checked, bad = 0, {}
  for _, key in ipairs(ns.UI.order) do
    local root = ns.UI.panels[key].frame
    for _, o in ipairs(allObjs) do
      if o ~= root and under(o, root) then
        local left, top, _, _, stretched = geo(o, win)
        -- containers stretched across the panel (SetAllPoints / left+right anchors) are not row elements
        if left and not stretched and top > -60 then
          checked = checked + 1
          if left < 70 then
            local p1 = (rawget(o, "_pts") or {})[1]
            bad[#bad + 1] = key .. "@" .. math.floor(left) .. "," .. math.floor(top) .. " anchor " .. tostring(p1 and p1[1]) .. "/" .. tostring(p1 and p1[3]) .. " " .. tostring(p1 and p1[4]) .. "," .. tostring(p1 and p1[5]) .. " rel=" .. tostring(p1 and p1[2] == root)
          end
        end
      end
    end
  end
  ok(checked >= 20, "top-row elements measured: " .. checked)
  ok(#bad == 0, #bad .. " top-row elements inside the portrait zone, first: " .. tostring(bad[1]))
  -- bottom tabs
  local minL, maxR, n = nil, nil, 0
  for _, key in ipairs(ns.UI.order) do
    local t = ns.UI.panels[key].tab
    if t and vis(t) ~= false then
      local l, _, w = geo(t, win)
      ok(l, "tab anchored: " .. key)
      n = n + 1
      minL = math.min(minL or l, l); maxR = math.max(maxR or (l + w), l + w)
    end
  end
  ok(n >= 5, "visible tabs: " .. n)
  local centre = (minL + maxR) / 2
  ok(math.abs(centre - 360) <= 10, "tabs centred: " .. centre)
  -- the model itself: a known anchor resolves as expected (guards against a vacuous pass)
  local probe = CreateFrame("Frame", nil, win); probe:SetSize(10, 10); probe:SetPoint("TOPLEFT", win, "TOPLEFT", 33, -5)
  local pl, pt = geo(probe, win); eq(pl, 33); eq(pt, -5)
  local p2 = CreateFrame("Frame", nil, win); p2:SetSize(40, 10); p2:SetPoint("TOP", win, "TOP", 0, -5)
  eq((geo(p2, win)), 340, "centred probe")
end)

-- UI regression checks registered by tests/ui_layout_spec.lua (it runs earlier, before this fake client
-- exists) are executed here, with the whole addon loaded against the fake API.
for _, c in ipairs(SMOKE_CHECKS or {}) do
  test(c[1], function()
    c[2]({ ns = ns, geo = geo, vis = vis, click = click, win = ns.UI.Window(), roster = roster, fire = fire,
           allObjs = allObjs, under = under })
  end)
end

-------------------------------------------------------------------------------
-- smoke: Salón de la fama (every filter + a detail), Mis logros, Ajustes > Celebraciones and
-- Contenido, GM annulment, export; detection glue (roster levels incl. non-addon members, kills, catalog),
-- celebrations (single announcer, never in an encounter, GM off = silent), missing profession/rep APIs.
test("smoke: hall of fame, detection, annulment, export, celebrations, settings, My achievements", function()
  clock = clock + 40
  local H, R = ns.HallGlue, ns.Races
  ok(H and H.Enabled(), "hall enabled")
  -- roster: Cid (no addon) goes 19 -> 20 seen by Ann's client; first sighting of Dan is not reported
  roster[3][4] = 20; fire("GUILD_ROSTER_UPDATE"); tick(2) --[[coalesced roster]]
  local seen
  for _, ev in pairs(H.Store().obs) do if ev.t == "lv" and ev.who == "Cid-Realm" and ev.lv == 20 then seen = ev end end
  ok(seen and seen.by == "Ann-Realm" and seen.src == "roster", "roster level change observed (member without addon)")
  -- a second observer (Bob) confirms within 10 min -> approx entry in lvl.all.20
  ns.HallGlue.OnObs({ o = { { t = "lv", who = "Cid-Realm", by = "Bob-Realm", ts = seen.ts + 60, src = "roster", lv = 20, cls = "MAGE" } } }, "Bob-Realm", false)
  local r = H.Race("lvl.all.20")
  eq(#r.entries, 1); eq(r.entries[1].key, "Cid-Realm"); eq(r.entries[1].mark, "approx")
  -- forged live observation (sender ~= by) is refused
  ns.HallGlue.OnObs({ o = { { t = "lv", who = "Zed-Realm", by = "Bob-Realm", ts = seen.ts, src = "roster", lv = 20 } } }, "Cid-Realm", false)
  eq(#H.Race("lvl.all.20").entries, 1, "forged report ignored")
  -- own level up (milestone) -> self observation with UnitClass/UnitRace
  H.OnLevelUp(30)
  local mine
  for _, ev in pairs(H.Store().obs) do if ev.t == "lv" and ev.who == "Ann-Realm" and ev.lv == 30 then mine = ev end end
  ok(mine and mine.src == "self" and mine.cls == "WARRIOR" and mine.race == "Human", "self level report")
  -- kills captured by the ranking smoke taught the catalog
  ok(#ns.Content.bossList() >= 1, "boss catalog learned from ENCOUNTER_END")
  -- open the tab: every filter, a detail
  ns.UI.Open("hall"); eq(ns.UI.Current(), "hall")
  local hs = ns.UI.HallState()
  for _, cat in ipairs({ "level", "class", "race", "dungeon", "raid", "pvp", "other" }) do
    click(hs.chips[cat]); eq(hs.cat, cat); eq(ns.UI.Current(), "hall")
  end
  click(hs.chips.level)
  hs.sel = "lvl.all.20"; ns.UI.Select("hall")
  ok(rawget(hs.title, "_text"):find("20"), "detail title: " .. tostring(rawget(hs.title, "_text")))
  eq(vis(hs.detail.cells[1]), true, "entry shown")
  ok(rawget(hs.detail.cells[1].pos, "_text"):find("#1", 1, true), "medal for #1")
  -- tooltip with participants (OnEnter handler runs)
  local enter = rawget(hs.detail.cells[1], "_OnEnter"); ok(enter, "tooltip"); enter(hs.detail.cells[1])
  -- export
  local txt = H.ExportText("lvl.all.20"); ok(txt:find("1%. Cid") and not txt:find("|", 1, true), txt)
  click(hs.export)
  -- GM annulment: right-click > menu > reason prompt > confirmation
  local menus = {}
  local origMenu = ns.W.Menu
  ns.W.Menu = function(owner, items) menus[#menus + 1] = items end
  click(hs.detail.cells[1], "RightButton")
  ns.W.Menu = origMenu
  ok(#menus == 1 and menus[1][2].text == ns.L.HALL_ANNUL, "GM menu offers the annulment")
  popups = {}
  menus[1][2].func()
  eq(#popups, 1, "reason prompt"); popups[1][3]("  "); eq(#popups, 1, "empty reason refused")
  popups[1][3]("multicuenta"); eq(#popups, 2, "confirmation asked")
  popups[2][3](); popups = {}
  local rr = H.Race("lvl.all.20")
  eq(#rr.entries, 0, "annulled"); eq(#rr.history, 1); eq(rr.history[1].reason, "multicuenta")
  ok(ns.state.annuls["lvl.all.20|Cid-Realm"], "annul record stored (replicated)")
  -- non-GM: no annulment
  roster[1][3] = 4; fire("GUILD_ROSTER_UPDATE"); tick(2) --[[coalesced roster]]
  local okA, why = H.Annul("lvl.all.20", "x", "y"); ok(not okA); eq(why, "denied")
  roster[1][3] = 0; fire("GUILD_ROSTER_UPDATE"); tick(2) --[[coalesced roster]]
  -- celebrations: GM off by default -> nothing; on -> one message, never in an encounter, <= 1 / 10 s
  local said = {}
  SendChatMessage = function(text, chan) said[#said + 1] = { text, chan } end
  ns.Celebrate.enqueue(H.CelQueue(), { key = "t1", text = "Guild Squads: prueba" })
  H.PumpCelebrations(); eq(#said, 0, "GM switched celebrations off: silent")
  ok(ns.Actions.SaveSettings({ squadsEnabled = true, bench = 1, minCreateRank = 4, officerRanks = { 1 }, banned = {},
                               compEnabled = true, celOn = true, celScope = "any", celSquad = true }))
  fire("ENCOUNTER_START", 102, "Boss", 1, 5)
  clock = clock + 30; H.PumpCelebrations(); eq(#said, 0, "never during an encounter")
  fire("ENCOUNTER_END", 102, "Boss", 1, 5, 0)
  clock = clock + 1; H.PumpCelebrations(); eq(#said, 1, "sent after the encounter"); eq(said[1][2], "GUILD")
  ns.Celebrate.enqueue(H.CelQueue(), { key = "t2", text = "dos" })
  clock = clock + 3; H.PumpCelebrations(); eq(#said, 1, "rate limit 10 s")
  clock = clock + 10; H.PumpCelebrations(); eq(#said, 2)
  C_ChatInfo.InChatMessagingLockdown = function() return true end
  ns.Celebrate.enqueue(H.CelQueue(), { key = "t3", text = "tres" })
  clock = clock + 20; H.PumpCelebrations(); eq(#said, 2, "chat lockdown: held")
  C_ChatInfo.InChatMessagingLockdown = nil
  eq(H.Announcer({ "Zed-Realm" }), "Ann-Realm", "no protagonist with addon: highest rank online announces")
  SendChatMessage = nil
  -- profession / reputation APIs absent in this fake client: pending data, no error
  eq(H.ReadProfessions(), nil); eq(H.ReadReputation(), nil)
  eq(H.profPath, "none")
  -- fake 16001 client -- only the APIs in the 1.60.1 dump exist: no global GetNumSkillLines /
  -- GetSkillLineInfo; GetProfessions exists but returns nothing; C_SkillInfo carries the skill lines
  ok(rawget(_G, "GetNumSkillLines") == nil and rawget(_G, "GetSkillLineInfo") == nil, "16001: no legacy globals")
  GetProfessions = function() return end
  GetProfessionInfo = function() return nil end
  local lines = { { "Professions", true }, { "Mining", false, 0, 175 }, { "Tailoring", false, 0, 120 },
                  { "Secondary Skills", true }, { "Cooking", false, 0, 60 }, { "Weapon Skills", true }, { "Swords", false, 0, 300 } }
  C_SkillInfo = { GetNumSkillLines = function() return #lines end,
                  GetSkillLineInfo = function(i) return (table.unpack or unpack)(lines[i]) end }
  local pr = H.ReadProfessions()
  eq(pr and pr.Mining, 175, "16001 multi-value: Mining"); eq(pr.Tailoring, 120); eq(pr.Cooking, 60)
  eq(pr.Swords, nil, "weapon skills are not professions"); eq(H.profPath, "C_SkillInfo"); eq(H.profCount, 3)
  ok(H.ProfDebug():find("path=C_SkillInfo n=3", 1, true), "diag line")
  ok(not H.NoData().prof, "16001: professions not 'pending data'")
  -- table-shaped return (the other accepted assumption)
  C_SkillInfo.GetSkillLineInfo = function(i)
    local l = lines[i]; return { skillName = l[1], isHeader = l[2], skillRank = l[4] }
  end
  pr = H.ReadProfessions(); eq(pr and pr.Mining, 175, "16001 table shape"); eq(H.profCount, 3)
  C_SkillInfo, GetProfessions, GetProfessionInfo = nil, nil, nil
  eq(H.ReadProfessions(), nil)
  H.SampleCounters()
  local nd = H.Races()["prof.*"]; ok(nd and nd.state == "nodata", "professions: pending data")
  -- Ajustes > Celebraciones and > Contenido
  ns.UI.Open("settings")
  local st = ns.UI.SettingsState()
  ns.UI.SettingsSection("cel"); eq(vis(st.sec.cel), true)
  ok(rawget(st.celAdopt, "_text"):find("/"), "adoption X/Y: " .. tostring(rawget(st.celAdopt, "_text")))
  ns.UI.SettingsSection("content"); eq(vis(st.sec.content), true)
  local row = st.bossRows[1]; ok(row.boss, "learned boss listed")
  local bid = row.boss.id
  row.final:SetChecked(true); click(row.final); eq(#popups, 1, "final boss asks first"); popups[1][3](); popups = {}
  ok(ns.Content.bosses[bid].final and ns.state.bosses[bid].d.final, "GM marked the final boss (record)")
  -- Mis logros (profile grid)
  ns.UI.Select("profile")
  local prof = ns.UI.ProfileState()
  ok(prof.ach, "achievement grid built")
  local n = 0; for _, b in ipairs(prof.ach.icons) do if vis(b) then n = n + 1 end end
  ok(n >= 10, "badges shown: " .. n)
  ok(rawget(prof.achT, "_text"):find("%(%d+/%d+%)"), rawget(prof.achT, "_text"))
  -- paginated catch-up after a hello with empty hashes
  local before = ns.Comm.Pending()
  ns.Sync.OnMessage("H", { h = {}, rh = R.bucketHashes(R.newStore()) }, "Bob-Realm")
  for _ = 1, 40 do clock = clock + 1; for _, s in ipairs(scripts) do if s[2] == "OnUpdate" and s[1] ~= nil then pcall(s[3], s[1], 1) end end end
  ok(ns.HallGlue.Adoption() >= 1, "hello counted for adoption")
end)

test("geometry: Hall of Fame top row clear of the portrait, chips centred, tab present", function()
  local win = ns.UI.Window()
  ns.UI.Select("hall"); eq(ns.UI.Current(), "hall")
  local root = ns.UI.panels.hall.frame
  local checked, bad = 0, {}
  for _, o in ipairs(allObjs) do
    if o ~= root and under(o, root) then
      local left, top, _, _, stretched = geo(o, win)
      if left and not stretched and top > -60 then checked = checked + 1; if left < 70 then bad[#bad + 1] = math.floor(left) .. "," .. math.floor(top) end end
    end
  end
  ok(checked >= 8, "hall top-row elements measured: " .. checked)
  eq(#bad, 0, "inside the portrait zone: " .. tostring(bad[1]))
  local hs = ns.UI.HallState()
  local l1 = geo(hs.chips.level, win); local le, _, we = geo(hs.export, win)
  ok(math.abs((l1 + le + we) / 2 - 360) <= 12, "filter row centred: " .. (l1 + le + we) / 2)
  ok(ns.UI.panels.hall.tab and vis(ns.UI.panels.hall.tab) ~= false, "tab visible")
  -- settings: 7 section buttons fit right of the portrait and inside the window
  ns.UI.Select("settings")
  local st = ns.UI.SettingsState()
  local maxR = 0
  for _, b in pairs(st.secBtn) do local l, _, w = geo(b, win); ok(l >= 70, "section button clear of the portrait"); maxR = math.max(maxR, l + w) end
  ok(maxR <= 712, "section buttons inside the window: " .. maxR)
end)

-- the hello announcement path is removed; member relays are refused, the author's own page is fine
test("on race pages: relays need GM/officer (or the author itself)", function()
  local H = ns.HallGlue
  local function count() local n = 0 for _ in pairs(H.Store().obs) do n = n + 1 end return n end
  local t = (GetServerTime and GetServerTime() or time()) - 100
  local ev1 = { t = "kill", who = "Bob-Realm", by = "Bob-Realm", ts = t, it = "party", inst = "Ragefire Chasm", enc = 9901, pres = {}, sqm = {} }
  local ev2 = { t = "kill", who = "Bob-Realm", by = "Bob-Realm", ts = t + 1, it = "party", inst = "Ragefire Chasm", enc = 9902, pres = {}, sqm = {} }
  local ev3 = { t = "kill", who = "Bob-Realm", by = "Bob-Realm", ts = t + 2, it = "party", inst = "Ragefire Chasm", enc = 9903, pres = {}, sqm = {} }
  local n0 = count()
  H.OnObs({ o = { ev1 } }, "Cid-Realm", true)
  eq(count(), n0, "member relay of an unannounced observation refused")
  H.OnObs({ o = { ev1 } }, "Ann-Realm", true)
  eq(count(), n0 + 1, "GM relay accepted")
  H.OnObs({ o = { ev2, ev3 } }, "Cid-Realm", true)
  eq(count(), n0 + 1, "member relay refused")
  H.OnObs({ o = { ev2 } }, "Bob-Realm", true)
  eq(count(), n0 + 2, "the author's own catch-up page is taken")
  -- levels only live and inside the window; a level page is taken only from a GM/officer
  local back = { t = "lv", who = "Bob-Realm", by = "Bob-Realm", ts = t - 30 * 86400, src = "self", lv = 50 }
  H.OnObs({ o = { back } }, "Bob-Realm", false)
  eq(count(), n0 + 2, "backdated live level refused")
  local fresh = { t = "lv", who = "Bob-Realm", by = "Bob-Realm", ts = t + 50, src = "self", lv = 50 }
  -- the author's own page is its retry path and follows the send window:
  -- a backdated level is refused there too, a fresh one is taken (then the live copy is a duplicate)
  H.OnObs({ o = { back } }, "Bob-Realm", true)
  eq(count(), n0 + 2, "backdated level on the author's own page refused")
  H.OnObs({ o = { fresh } }, "Bob-Realm", true)
  eq(count(), n0 + 3, "fresh level on the author's own page (retry) accepted")
  H.OnObs({ o = { fresh } }, "Bob-Realm", false)
  eq(count(), n0 + 3, "fresh live level: duplicate")
  local fut = { t = "kill", who = "Bob-Realm", by = "Bob-Realm", ts = t + 100000, it = "party", inst = "Ragefire Chasm", enc = 9904, pres = {}, sqm = {} }
  H.OnObs({ o = { fut } }, "Bob-Realm", false)
  eq(count(), n0 + 3, "far-future observation refused")
  H.OnObs({ c = "dng.fake", x = "x" }, "Cid-Realm", true)
  ok(not H.Store().closed["dng.fake"], "closed race from a member refused")
end)

test("MetricEvents relayed only by GM/officers; far-future events refused", function()
  local G = ns.ProgressGlue
  local function n() return tonumber(G.Debug():match("events=(%d+)")) end
  local t = (GetServerTime and GetServerTime() or time()) - 50
  local ev = { t = "hk", who = "Cid-Realm", ts = t, sid = "X1", n = 3 }
  local n0 = n()
  G.OnEvents({ e = { ev } }, "Bob-Realm")
  eq(n(), n0, "member relay refused")
  G.OnEvents({ e = { ev } }, "Ann-Realm")
  eq(n(), n0 + 1, "GM relay accepted")
  G.OnEvents({ e = { { t = "hk", who = "Bob-Realm", ts = t + 100000, sid = "X1", n = 3 } } }, "Bob-Realm")
  eq(n(), n0 + 1, "future refused")
  G.OnEvents({ e = { { t = "hk", who = "Bob-Realm", ts = t, sid = "X1", n = 2 } } }, "Bob-Realm")
  eq(n(), n0 + 2, "live from the author accepted")
end)

test("My profile keeps unsaved edits and asks before leaving; actions give feedback", function()
  local UI = ns.UI
  UI.Select("profile")
  local pr = UI.profileState
  pr.slots[1].on = not pr.slots[1].on
  UI.Dirty(); tick(2)                                   -- a background refresh must not wipe the edit
  local n0 = #popups
  UI.Select("squads")
  eq(UI.Current(), "profile", "stays on Mi perfil")
  eq(#popups, n0 + 1, "unsaved-profile confirmation asked")
  eq(popups[#popups][2], ns.L.PROFILE_UNSAVED)
  popups[#popups][3]()                                  -- Descartar
  eq(UI.Current(), "squads", "discard moves on")
  -- feedback: inviting the squad to the group reports counts in chat + status bar
  local printed = {}
  local oldPrint = print
  print = function(m) printed[#printed + 1] = tostring(m) end
  local sid = ns.Actions.MySquadId()
  ok(sid, "the smoke player has a squad")
  local okI, sent, total = pcall(ns.Actions.InviteSquadToGroup, sid)
  print = oldPrint
  ok(okI, "invite to group ran")
  local want = ns.L.FB_PARTY:format(sent, total, total - sent):sub(1, 12)
  local found = false
  for _, m in ipairs(printed) do if m:find(want, 1, true) then found = true end end
  ok(found, "feedback printed: " .. table.concat(printed, " | "))
end)

test("+ Novedades: welcome once per character (4 steps for the GM), news after an update, geometry", function()
  local UI = ns.UI
  UI.Open("squads")
  UI.uiDB().welcomed = {}
  UI.MaybeGuide()
  eq(UI.GuideShown(), "welcome", "first use shows the welcome")
  eq(#UI.GuideSteps(true), 4); eq(#UI.GuideSteps(false), 3)
  UI.MaybeGuide()
  -- the same character never sees it twice
  eq(GuildSquadsDB.ui.welcomed[ns.me()], true)
  -- geometry: the box and every step button sit inside the window
  local win = UI.Window()
  local _, _, ww, wh = geo(win, win)
  local g = UI.GuideFrame()
  local gl, gt, gw, gh = geo(g, win)
  ok(gl and gl >= 0 and gt <= 0 and gl + gw <= ww and gt - gh >= -wh, ("guide inside the window (%s,%s,%s,%s)"):format(tostring(gl), tostring(gt), tostring(gw), tostring(gh)))
  for i = 1, 4 do
    local r = g.rows[i]
    local bl, bt, bw, bh = geo(r.btn, win)
    ok(bl and bl >= gl and bl + bw <= gl + gw + 0.5 and bt <= gt and bt - bh >= gt - gh, "step button " .. i .. " inside the box")
  end
  local cl, ct, cw, ch = geo(g.close, win)
  ok(cl and cl >= gl and cl + cw <= gl + gw + 0.5 and ct - ch >= gt - gh, "close button inside the box")
  -- a step button navigates
  g.rows[1].btn:GetScript("OnClick")()
  eq(UI.Current(), "profile"); ok(not UI.GuideShown(), "guide closed")
  local v = ns.VERSION
  ns.VERSION = "9.9.9-test"
  UI.MaybeGuide()
  eq(UI.GuideShown(), "news", "news after a version change")
  UI.MaybeGuide()
  eq(GuildSquadsDB.ui.lastVersion, "9.9.9-test")
  ns.VERSION = v
end)

-- the live score of a CLOSED wipe matches the canonical summary even when this client's local
-- membership snapshot (pdb.snap) disagrees with the replicated records
test("closed-wipe live score = canonical summary, not the local snapshot", function()
  local G, Pr = ns.ProgressGlue, ns.Progress
  local w = G.Wipe()
  local before = G.Compute(w)
  local sid
  for s, x in pairs(before.squads or {}) do if (x.general or 0) > 0 then sid = s end end
  ok(sid, "a squad with points in the current wipe")
  clock = clock + 8 * 86400 -- the wipe closes
  ok(G.Wipe() ~= w, "wipe closed")
  -- corrupt THIS client's local snapshot of the closed wipe: nobody was a member
  local function findSnap(t, depth)
    if type(t) ~= "table" or depth > 4 then return nil end
    if type(t.snap) == "table" and t.snap[w] then return t.snap end
    for _, v in pairs(t) do local s = findSnap(v, depth + 1); if s then return s end end
  end
  local snap = findSnap(GuildSquadsDB, 0)
  ok(snap, "local snapshot found"); for s in pairs(snap[w]) do snap[w][s] = {} end
  local o = G.Opts(); o.profiles = ns.state.profiles; o.squads = ns.state.squads
  local sums = Pr.wipeSummary(G.Events(), w, o)
  local live = G.Compute(w).squads[sid]
  ok(sums[sid] and live, "both present")
  eq(string.format("%.4f", live.general or 0), string.format("%.4f", sums[sid].general or 0), "live == canonical")
end)

-- the unsaved-profile prompt offers a third button "Guardar y salir" that saves, then leaves
test("My profile unsaved prompt has 'Save and exit' (esES 'Guardar y salir', button3/OnAlt) that saves and leaves", function()
  local UI, A = ns.UI, ns.Actions
  UI.Select("profile")
  local pr = UI.profileState
  pr.slots[2].on = not pr.slots[2].on
  local want = pr.slots[2].on
  UI.Dirty(); tick(2)
  local n0 = #popups
  UI.Select("squads")
  eq(UI.Current(), "profile", "stays on Mi perfil")
  eq(#popups, n0 + 1, "prompt asked")
  local dlg = StaticPopupDialogs.GUILDSQUADS_CONFIRM
  eq(dlg.button1, ns.L.DISCARD); eq(dlg.button2, ns.L.KEEP_EDITING)
  eq(dlg.button3, "Guardar y salir", "third button label (esES)")
  ok(type(dlg.OnAlt) == "function", "OnAlt set")
  dlg.OnAlt(nil, popups[#popups][3])
  eq(UI.Current(), "squads", "save-and-exit moves on")
  eq(A.MyProfile().avail:sub(2, 2), want and "1" or "0", "the draft was saved")
  -- a plain confirm elsewhere does not inherit the third button
  ns.W.Confirm("x", function() end)
  ok(dlg.button3 == nil and dlg.OnAlt == nil, "button3 cleared for two-button confirms")
end)

-- "!" on the Mi perfil tab while the profile has no role or no main goal
test("'!' marker on My profile while the profile is incomplete", function()
  local UI, A = ns.UI, ns.Actions
  ok(A.SaveProfile({ role = "TANK", goals = {} }), "saved without goals")
  ok(A.ProfileIncomplete(), "no goals -> incomplete")
  ns.UpdateBadge()
  local m = UI.profileMarker
  ok(m, "marker created on the tab")
  ok(vis(m), "marker shown while incomplete")
  eq(rawget(m.text, "_text") or (m.text.GetText and m.text:GetText()), "!", "marker text")
  ok(A.SaveProfile({ role = "TANK", goals = { "raid" } }), "saved complete")
  ok(not A.ProfileIncomplete(), "role + goal -> complete")
  ns.UpdateBadge()
  ok(not vis(m), "marker hidden once complete")
end)
