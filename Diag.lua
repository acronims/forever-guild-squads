-- Guild Squads (MIT) - Diag.lua
-- WoW glue for the automatic diagnostics (Core/Diag): on login and on every relevant event it records into
-- GuildSquadsDB.diag which APIs exist, event counters, the last ENCOUNTER_END, whether comms were held during an
-- encounter, HK readings and Overlord presence. /gsq diag shows the report ready to copy; the same data is written
-- to the SavedVariables file when the game saves (logout / reload). Nothing is ever sent because of this module.
local _, ns = ...
local D, L = ns.Diag, ns.L

local G = {}
ns.DiagGlue = G
local db

local function now() return (GetServerTime and GetServerTime()) or time() end
local function stamp() return (date and date("%Y-%m-%d %H:%M:%S")) or tostring(now()) end
local function lookup(name) return rawget(_G, name) end

function G.DB() return db end

local function load()
  GuildSquadsDB = GuildSquadsDB or {}
  db = D.ensure(GuildSquadsDB.diag)
  GuildSquadsDB.diag = db
  db.logins = (db.logins or 0) + 1
  db.lastLogin = stamp()
  if GetBuildInfo then
    local okB, ver, build, _, iface = pcall(GetBuildInfo)
    if okB then db.build = tostring(ver) .. " (" .. tostring(build) .. ")"; db.interface = iface end
  end
  if GetLocale then local okL, loc = pcall(GetLocale); if okL then db.locale = loc end end
  db.addon = ns.VERSION or "?"
  D.scanApis(db, lookup)
end

function G.Count(ev) if db then D.count(db, ev, now()) end end
function G.HK(text) if db then D.note(db, "hk", text, now()) end end
function G.Bg(text) if db then D.note(db, "lastBg", text, now()) end end
function G.Overlord(text) if db then D.note(db, "overlord", text, now()) end end

-- comms during an encounter: we never send; we record whether the lock was detected and what was held
local function checkEncounterComm()
  if not db then return end
  local parts = {}
  if C_ChatInfo and type(C_ChatInfo.InChatMessagingLockdown) == "function" then
    local okC, v = pcall(C_ChatInfo.InChatMessagingLockdown); parts[#parts + 1] = "lockdown=" .. tostring(okC and v)
  else parts[#parts + 1] = "lockdown=NOAPI" end
  local encFn = ((ns.encounterFn and ns.encounterFn()) or IsEncounterInProgress)
  if type(encFn) == "function" then
    local okE, v = pcall(encFn); parts[#parts + 1] = "inProgress=" .. tostring(okE and v)
  else parts[#parts + 1] = "inProgress=NOAPI" end
  local q = ns.Comm and ns.Comm.queue
  parts[#parts + 1] = "queueBlocked=" .. tostring(q and q:blocked() or false)
  parts[#parts + 1] = "held=" .. tostring(ns.Comm and ns.Comm.Pending() or 0)
  parts[#parts + 1] = "sentTotal=" .. tostring(ns.Comm and ns.Comm.stats.sent or 0)
  D.note(db, "encComm", table.concat(parts, " "), now())
end

function G.Report()
  if not db then load() end
  local W = ns.W
  if W and W.ReportLines then D.note(db, "ui", table.concat(W.ReportLines(), " | "), now()) end
  local extra = {}
  if ns.ProgressGlue then extra[#extra + 1] = ns.ProgressGlue.Debug() end
  if ns.HallGlue then extra[#extra + 1] = ns.HallGlue.Debug() end
  if ns.HallGlue and ns.HallGlue.ProfDebug then -- which profession API path was used + how many found
    pcall(ns.HallGlue.ReadProfessions); extra[#extra + 1] = ns.HallGlue.ProfDebug()
  end -- obs, closed races, guild-chat errors
  if ns.RaidGlue then -- group / raid APIs used by the rosters (present or not) + roster counts
    local n = 0
    for _ in pairs(ns.state and ns.state.rosters or {}) do n = n + 1 end
    extra[#extra + 1] = "raid apis " .. ns.RaidGlue.ApiReport() .. " rosters=" .. n
  end
  if ns.Comm then
    local s = ns.Comm.stats
    extra[#extra + 1] = ("comm sent=%d recv=%d failed=%d pending=%d"):format(s.sent, s.recv, s.failed, ns.Comm.Pending())
  end
  if ns.Sync and ns.Sync.stats then -- refused / malformed records
    local y = ns.Sync.stats
    extra[#extra + 1] = ("sync bad=%d relayRefused=%d future=%d errors=%d quarantine=%d guild=%s"):format(y.bad, y.relayRefused,
      y.future, y.errors, ns.Sync.QuarantineCount(), tostring(ns.guildKey))
  end
  if ns.Catalog and ns.Catalog.debugLine then extra[#extra + 1] = ns.Catalog.debugLine() end -- GM catalog
  if ns.RosterDiag then extra[#extra + 1] = ns.RosterDiag() end -- am I in the roster cache (surnames)
  return D.report(db, extra)
end

local EVENTS = { "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ENCOUNTER_START", "ENCOUNTER_END",
                 "PLAYER_LEVEL_UP", "PVP_MATCH_ACTIVE", "PVP_MATCH_COMPLETE", "PVP_MATCH_INACTIVE",
                 "UPDATE_BATTLEFIELD_SCORE", "PLAYER_PVP_KILLS_CHANGED", "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE",
                 "ZONE_CHANGED_NEW_AREA", "PLAYER_LOGOUT" }
local f = CreateFrame("Frame")
G.registered = {}
for _, ev in ipairs(EVENTS) do
  local okR = pcall(f.RegisterEvent, f, ev)
  G.registered[ev] = okR and true or false
end
f:SetScript("OnEvent", function(_, ev, ...)
  if ev == "ADDON_LOADED" then
    if ... ~= "GuildSquads" then return end
    load()
    local unreg = {}
    for e, okR in pairs(G.registered) do if not okR then unreg[#unreg + 1] = e end end
    table.sort(unreg)
    if #unreg > 0 then D.addNote(db, "events not registrable: " .. table.concat(unreg, " "), stamp()) end
  end
  if not db then return end
  if ev == "CHAT_MSG_ADDON" then
    local prefix, _, _, sender = ...
    if prefix ~= (ns.Comm and ns.Comm.PREFIX) then return end
    if issecretvalue and issecretvalue(sender) then return end   -- as Comm.lua
    local own = ns.isSelf and type(sender) == "string" and ns.isSelf(sender)
    D.count(db, own and "CHAT_MSG_ADDON:own" or "CHAT_MSG_ADDON:other", now())
    return
  end
  D.count(db, ev, now())
  if ev == "PLAYER_LOGIN" and not GuildSquadsDB.diagNoticed then
    GuildSquadsDB.diagNoticed = true
    if ns.print then ns.print(L.DIAG_NOTICE) end
  elseif ev == "ENCOUNTER_END" then
    D.note(db, "lastEncounter", D.args(...) .. " @" .. stamp(), now())
  elseif ev == "ENCOUNTER_START" then
    if ns.After then ns.After(1, checkEncounterComm) else checkEncounterComm() end
  elseif ev == "PLAYER_LOGOUT" then
    G.Report() -- refresh the ui line so the SavedVariables copy is complete
  end
end)

return G
