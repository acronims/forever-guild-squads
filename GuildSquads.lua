-- Guild Squads (MIT) - GuildSquads.lua
-- Bootstrap: saved variables, guild roster cache, local actions, slash commands.
local ADDON, ns = ...
local L, M, P, Sync, Comm, Logo = ns.L, ns.Model, ns.Permissions, ns.Sync, ns.Comm, ns.Logo

ns.state = M.newState()

-- positive notices (achievements, celebrations) in yellow, not the red raid-warning colour
ns.POSITIVE_NOTICE = { r = 1, g = 0.82, b = 0 }

-- version from the TOC (C_AddOns first, legacy global as fallback; the packager replaces the token)
do
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  if get then
    local ok, v = pcall(get, ADDON, "Version")
    if ok and type(v) == "string" and v ~= "" and not v:find("@", 1, true) then ns.VERSION = v end
  end
  ns.VERSION = ns.VERSION or "dev"
end
local db
local rosterCache, onlineN = {}, 0

-------------------------------------------------------------------------------
-- helpers
local function print_(msg) print("|cff33ccff[Guild Squads]|r " .. tostring(msg)) end
ns.print = print_

local debugOn = false
function ns.debug(msg) if debugOn then print_("|cff999999" .. tostring(msg) .. "|r") end end

local realm
local function myRealm()
  if not realm and GetNormalizedRealmName then realm = GetNormalizedRealmName() end
  return realm or ""
end

function ns.fullName(name)
  if type(name) ~= "string" or name == "" then return nil end
  if name:find("-", 1, true) then return name end
  return name .. "-" .. myRealm()
end

function ns.me()
  local n = UnitName and UnitName("player")
  return ns.fullName(n)
end

function ns.isSelf(sender) return ns.fullName(sender) == ns.me() end

-- character key of a name that may carry a WoW Forever surname (guild roster, raid roster, typed names).
-- Names without a space give exactly ns.fullName(name). Returns key, surname.
function ns.charKey(name)
  if type(name) ~= "string" or name == "" then return nil end
  return M.charName(name, myRealm())
end

function ns.shortName(name) return (name and name:match("^([^-]+)")) or tostring(name) end

-- timers. C_Timer.After / C_Timer.NewTicker when the client has them; otherwise a frame OnUpdate that
-- only runs while a timer is pending (the frame is hidden when the list is empty).
local timers = {}
local timerFrame = CreateFrame("Frame")
local hasAfter = C_Timer and type(C_Timer.After) == "function"
local function runSafe(fn) local ok, err = pcall(fn); if not ok and ns.debug then ns.debug(err) end end
timerFrame:SetScript("OnUpdate", function(self)
  if #timers == 0 then if self.Hide then self:Hide() end return end
  local now = GetTime()
  for i = #timers, 1, -1 do
    local tm = timers[i]
    if now >= tm.t then table.remove(timers, i); runSafe(tm.fn) end
  end
end)
function ns.After(delay, fn)
  if hasAfter and pcall(C_Timer.After, delay, function() runSafe(fn) end) then return end
  timers[#timers + 1] = { t = GetTime() + delay, fn = fn }
  if timerFrame.Show then timerFrame:Show() end
end
-- repeating timer: C_Timer.NewTicker, else an OnUpdate accumulator on `frame` (or a new one). Returns a handle
-- with :Cancel().
function ns.Every(period, fn, frame)
  if C_Timer and type(C_Timer.NewTicker) == "function" then
    local okT, t = pcall(C_Timer.NewTicker, period, function() runSafe(fn) end)
    if okT and t then return t end
  end
  frame = frame or CreateFrame("Frame")
  local acc = 0
  frame:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc >= period then acc = 0; runSafe(fn) end
  end)
  return { Cancel = function() frame:SetScript("OnUpdate", nil) end }
end

-------------------------------------------------------------------------------
-- guild roster
function ns.roster(name)
  return rosterCache[ns.fullName(name) or ""]
end
function ns.onlineCount() return onlineN end
function ns.rosterList() return rosterCache end
-- "Fire Essency" when the roster gave a surname, otherwise the short name
function ns.displayName(name)
  local r = ns.roster(name)
  local short = ns.shortName(name)
  return (r and r.surname) and (short .. " " .. r.surname) or short
end
-- honest text for "notInGuild" on my own writes. Roster read and I am still missing ->
-- "your character (%s) was not found in the guild roster (%d members)"; nil while the roster is really not ready.
function ns.NotInGuildText()
  if not ns.rosterReady then return nil end
  local me = ns.me()
  if me and rosterCache[me] then return nil end
  local n = 0
  for _ in pairs(rosterCache) do n = n + 1 end
  return L.ERR_notInRoster:format(tostring(me), n)
end
-- /gsq diag line
function ns.RosterDiag()
  local n, s = 0, 0
  for _, r in pairs(rosterCache) do n = n + 1; if r.surname then s = s + 1 end end
  local me = ns.me()
  return ("[roster] me=%s found=%s entries=%d surnames=%d"):format(tostring(me), (me and rosterCache[me]) and "yes" or "no", n, s)
end

local function requestRoster()
  if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster)
  elseif GuildRoster then pcall(GuildRoster) end
end

-- per-guild data. Hooks run once, when the guild key is known (Progress, Hall).
ns.guildHooks = ns.guildHooks or {}
local function guildKey()
  if not GetGuildInfo then return M.guildKey("?", myRealm()) end      -- API missing: one bucket per realm
  local ok, name, _, _, gRealm = pcall(GetGuildInfo, "player")
  if not ok or type(name) ~= "string" or name == "" then return nil end -- not loaded yet: try on the next roster
  return M.guildKey(name, gRealm or myRealm())
end

local function selectGuild()
  if ns.gdb then return true end
  local key = guildKey()
  if not key then return false end
  local root = GuildSquadsDB
  local g, migrated = M.guildDB(root, key, function(n) return rosterCache[ns.fullName(n) or ""] ~= nil end)
  ns.gdb, ns.guildKey = g, key
  g.ann = nil -- announced hashes are not used
  local saved = type(g.records) == "table" and g.records or {}
  for _, r in ipairs(saved) do Sync.Apply(r) end    -- own disk: re-validated, no relay rule
  for _, fn in ipairs(ns.guildHooks) do pcall(fn, g) end
  if migrated then ns.debug("data moved to guild " .. key) end
  return true
end

-- the guild changed (left, kicked, joined another) without /reload. The current partition
-- is saved under its own key, every per-guild store is dropped (ns.guildUnloadHooks: Progress, Hall) and the next
-- roster read selects the new guild (bootstrap path: records, hooks, hello) and refreshes the UI.
ns.guildUnloadHooks = ns.guildUnloadHooks or {}
local saveDB
local function unloadGuild()
  if not ns.gdb then return end
  saveDB()
  ns.debug("guild partition " .. tostring(ns.guildKey) .. " unloaded")
  ns.gdb, ns.guildKey, ns.rosterReady = nil, nil, false
  ns.state = M.newState()
  for _, fn in ipairs(ns.guildUnloadHooks) do pcall(fn) end
  if ns.UI then ns.UI.Dirty() end
end
ns.UnloadGuild = unloadGuild

local function readRoster()
  if not (IsInGuild and IsInGuild()) then
    rosterCache = {}; onlineN = 0
    unloadGuild()   -- no guild -> no partition
    return
  end
  if ns.gdb and ns.rosterReady then
    local key = guildKey()
    if key and key ~= ns.guildKey then unloadGuild() end   -- another guild
  end
  local n = GetNumGuildMembers and GetNumGuildMembers() or 0
  if n == 0 then return end
  local cache, online = {}, 0
  for i = 1, n do
    local ok, name, rankLabel, rankIndex, level, _, zone, _, _, isOnline, _, classFile = pcall(GetGuildRosterInfo, i)
    local key, surname -- "Fire Essency" -> "Fire-Realm" + surname "Essency" (same key as ns.me() and senders)
    if ok and type(name) == "string" then key, surname = ns.charKey(name) end
    if key then
      -- real rank names (fallback when GuildControlGetRankName is missing)
      if type(rankIndex) == "number" and type(rankLabel) == "string" and rankLabel ~= "" then ns.rankNames[rankIndex] = rankLabel end
      -- days since last online (0 = online); nil when the API is missing (feature omitted)
      local seen
      if isOnline then seen = 0
      elseif GetGuildRosterLastOnline then
        local okL, y, mo, d, h = pcall(GetGuildRosterLastOnline, i)
        if okL and (type(y) == "number" or type(d) == "number") then
          seen = (tonumber(y) or 0) * 365 + (tonumber(mo) or 0) * 30 + (tonumber(d) or 0) + (tonumber(h) or 0) / 24
        end
      end
      cache[key] = { rank = rankIndex, level = level, class = classFile, online = isOnline and true or false,
                     zone = type(zone) == "string" and zone or nil, seen = seen, surname = surname }
      if isOnline then online = online + 1 end
    end
  end
  rosterCache, onlineN = cache, online
  if ns.HallGlue and ns.HallGlue.OnRoster then pcall(ns.HallGlue.OnRoster, cache) end -- level races (roster)
  if not ns.rosterReady then
    if not selectGuild() then return end
    ns.rosterReady = true
    Sync.FlushPending()
    ns.Actions.RefreshProfile(true)
    ns.After(3 + math.random() * 7, Sync.Hello)
    -- anti-entropy. A version that reached only some clients (loss, /reload mid-send)
    -- was never repaired while nobody logged in; one hello every 10-20 min (jittered) closes the gap
    if not ns.antiEntropy then
      ns.antiEntropy = true
      local function again()
        ns.After(600 + math.random() * 600, function() if ns.rosterReady then Sync.Hello() end; again() end)
      end
      again()
    end
  end
  if ns.UI then ns.UI.Dirty() end
end

-------------------------------------------------------------------------------
-- local actions (each one = one signed-by-sender record, validated locally first)
local A = {}
ns.Actions = A

local function copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = copy(v) end
  return o
end

local function serverTime() return (GetServerTime and GetServerTime()) or time() end

-- one error message per failed action. write() reports the Model refusal and the UI
-- layer (Panels err(), Hall) calls this again with the same reason in the same frame: the repeat is skipped.
local lastErr = { why = nil, t = nil }
function ns.ShowError(why)
  if not why then return end
  local t = GetTime and GetTime() or 0
  if lastErr.why == why and lastErr.t == t then return end
  lastErr.why, lastErr.t = why, t
  print_(L.ERR:format(ns.ErrText(why)))
end

local function write(kind, id, data)
  db.seq = (db.seq or 0) + 1
  local rec = { k = kind, id = id, a = ns.me(), ts = serverTime(), sq = db.seq, d = data }
  local ok, why = Sync.Publish(rec)
  if not ok then ns.ShowError(why) end
  return ok, why
end

-- generic signed record (boss catalog, GM annulments); validated by Model like every other record
function A.WriteRecord(kind, id, data) return write(kind, id, data) end
-- many records of one kind at once (the GM's bulk catalog changes). items = { { id, d } }.
-- dryRun = only build them (for the confirmation: count + estimated seconds). -> applied, refused, records
function A.WriteMany(kind, items, dryRun)
  local recs = {}
  local ts = serverTime()
  for _, it in ipairs(items or {}) do
    local sq = (db.seq or 0) + #recs + 1
    recs[#recs + 1] = { k = kind, id = it.id, a = ns.me(), ts = ts, sq = sq, d = it.d }
  end
  if dryRun then return 0, 0, recs end
  db.seq = (db.seq or 0) + #recs
  local applied, refused = Sync.PublishMany(recs)
  return applied, refused, recs
end

function A.MyProfile()
  local r = ns.state.profiles[ns.me()]
  return r and copy(r.d) or { role = "DAMAGER", avail = "00000000", goals = {} }
end

-- refresh auto-detected fields; publish when they changed (or when forced)
function A.RefreshProfile(force)
  if not ns.rosterReady then return end
  local d = A.MyProfile()
  local _, class = UnitClass("player")
  local level = UnitLevel("player")
  local race = select(2, UnitRace("player"))
  if force or d.class ~= class or d.level ~= level or d.race ~= race then
    d.class, d.level, d.race = class, level, race
    write("profile", ns.me(), d)
  end
end

function A.SaveProfile(fields)
  local d = A.MyProfile()
  for k, v in pairs(fields) do d[k] = v end
  return write("profile", ns.me(), d)
end

function A.MySquadId() return M.squadOf(ns.state, ns.me()) end

-- my profile is incomplete while it has never been saved, or has no role or no main goal
function A.ProfileIncomplete()
  local me = ns.me and ns.me()
  local r = me and ns.state and ns.state.profiles and ns.state.profiles[me]
  local d = type(r) == "table" and r.d
  if type(d) ~= "table" then return true end
  if type(d.role) ~= "string" or d.role == "" then return true end
  return type(d.goals) ~= "table" or next(d.goals) == nil
end

-- every action confirms what happened (chat + status bar of the window)
local function feedback(ok, text)
  if not ok or not text then return end
  print_(text)
  if ns.UI and ns.UI.Flash then pcall(ns.UI.Flash, text) end
end
ns.Feedback = feedback
local function squadName(id) return M.displayName(ns.state, id) or "?" end

function A.CreateSquad(f)
  local me = ns.me()
  local d = { name = f.name, captain = me, members = { me }, bench = {}, icon = f.icon, color = f.color,
              border = f.border, motto = f.motto, tags = M.cleanTags(f.tags), open = f.open and true or false, approved = true }
  local id = me .. ":" .. serverTime()
  local ok, why = write("squad", id, d)
  if ok then A.SaveProfile({ squad = id }) end
  return ok, why
end

local function editSquad(id, fn)
  local r = ns.state.squads[id]
  if not r then return false, "denied" end
  local d = copy(r.d)
  fn(d)
  -- a rename stamps the name ts (name collisions are resolved by (nts, author, id))
  if type(d.name) == "string" and M.nameKey(d.name) ~= M.nameKey(r.d.name) then d.nts = serverTime() end
  return write("squad", id, d)
end
A.EditSquad = editSquad

local function remove(list, name)
  for i = #list, 1, -1 do if list[i] == name then table.remove(list, i) end end
end

function A.Kick(id, name)
  local ok, why = editSquad(id, function(d) remove(d.members, name); remove(d.bench, name) end)
  feedback(ok, L.FB_KICKED:format(ns.shortName(name)))
  return ok, why
end
-- the outgoing captain first signs the hand-over in their own profile, then writes the squad
function A.Transfer(id, name)
  local p = A.MyProfile()
  p.xferTo = tostring(id) .. ">" .. tostring(name)
  write("profile", ns.me(), p)
  local ok, why = editSquad(id, function(d) d.xferFrom = d.captain; d.captain = name end)
  feedback(ok, L.FB_CAPTAIN:format(ns.shortName(name)))
  return ok, why
end
-- only leaving MY squad clears my profile; hiding another squad (moderation) does not
function A.Disband(id)
  local mine = A.MySquadId() == id
  local name = squadName(id)
  local ok, why = editSquad(id, function(d) d.disbanded = true end)
  if ok and mine then A.SaveProfile({ squad = "" }) end
  feedback(ok, L.FB_DISBANDED:format(name))
  return ok, why
end
function A.Approve(id) return editSquad(id, function(d) d.approved = true end) end

-- captain adds a name (invite or accepting a request); goes to bench when the 5 are full
function A.AddMember(id, name)
  name = ns.charKey(name)   -- a typed "Fire Essency" is the character "Fire"
  -- only guild members can be added (the Buscador does not accept any other name)
  if not (name and ns.roster(name)) then ns.ShowError("notGuildMember"); return false, "notGuildMember" end
  local settings = M.settingsOf(ns.state)
  local p = ns.state.profiles[name]
  local requested = p and p.d.squad == id
  local ok, why = editSquad(id, function(d)
    if P.contains(d.members, name) or P.contains(d.bench, name) then return end
    if #d.members < M.SQUAD_SIZE then d.members[#d.members + 1] = name
    elseif #d.bench < (settings.bench or 0) then d.bench[#d.bench + 1] = name
    else d.members[#d.members + 1] = name end -- rejected by validation ("squadFull")
  end)
  feedback(ok, (requested and L.FB_ACCEPTED or L.FB_INVITED):format(ns.shortName(name)))
  return ok, why
end

function A.MoveToBench(id, name)
  local ok, why = editSquad(id, function(d) remove(d.members, name); d.bench[#d.bench + 1] = name end)
  feedback(ok, L.FB_BENCHED:format(ns.shortName(name)))
  return ok, why
end

function A.RequestJoin(id) -- also = accept invitation
  local r = ns.state.squads[id]
  local me = ns.me()
  local invited = r and (P.contains(r.d.members or {}, me) or P.contains(r.d.bench or {}, me))
  local ok, why = A.SaveProfile({ squad = id, reqAt = serverTime() }, true)
  feedback(ok, (invited and L.FB_JOINED or L.FB_REQ_SENT):format(squadName(id)))
  return ok, why
end

-- durable rejection: kind "req" (captain rejects `name`'s request to squad `sid`) or "inv" (I decline `sid`)
function A.Reject(sid, name, kind)
  name = ns.charKey(name)
  if M.isRejected(ns.state, sid, name, kind) then return true end -- repeated rejection: nothing to do
  local p = ns.state.profiles[name]
  local at = kind == "req" and ((p and p.d.reqAt) or 0) or 0
  local ok, why = write("reject", M.rejectId(sid, name, kind), { sid = sid, name = name, kind = kind, at = at, on = true })
  feedback(ok, kind == "inv" and L.FB_DECLINED:format(squadName(sid)) or L.FB_REJECTED:format(ns.shortName(name)))
  return ok, why
end

-- inactivity (days since every member was last seen; nil when unknown)
ns.rankNames = ns.rankNames or {}
function ns.lastSeenDays(name) local r = ns.roster(name); return r and r.seen end
function A.IsInactive(sid) return M.isInactive(ns.state, sid, ns.lastSeenDays, M.settingsOf(ns.state).inactiveDays) end
function A.Leave()
  local name = squadName(A.MySquadId())
  local ok, why = A.SaveProfile({ squad = "" }, true)
  feedback(ok, L.FB_LEFT:format(name))
  return ok, why
end

function A.SaveSettings(s) return write("settings", "settings", s) end

function A.InviteSquadToGroup(id)
  if InCombatLockdown and InCombatLockdown() then print_(L.IN_COMBAT); return end
  if not (C_PartyInfo and C_PartyInfo.InviteUnit) then print_(L.FB_NO_INVITE_API); return end
  local me = ns.me()
  local sent, total, offline = 0, 0, 0
  for _, name in ipairs(M.members(ns.state, id)) do
    local r = ns.roster(name)
    if name ~= me then
      total = total + 1
      if r and r.online then
        if pcall(C_PartyInfo.InviteUnit, name) then sent = sent + 1 end
      else offline = offline + 1 end
    end
  end
  feedback(true, L.FB_PARTY:format(sent, total, offline))
  return sent, total, offline
end

-------------------------------------------------------------------------------
-- "Llamar al squad": zone sent by addon WHISPER to online members (queued like all comms)
local lastCall
local seenCalls = {}
function A.CallReady() return ns.Call.canSend(lastCall, GetTime()) end

function A.CallSquad()
  if InCombatLockdown and InCombatLockdown() then print_(L.IN_COMBAT); return false end
  if IsInInstance then
    local ok, inst, kind = pcall(IsInInstance)
    if ok and inst and (kind == "pvp" or kind == "arena") then print_(L.CALL_PVP); return false end
  end
  local ready, left = A.CallReady()
  if not ready then print_(L.CALL_CD:format(ns.Call.fmtLeft(left))); return false end
  local id = A.MySquadId()
  if not id then return false end
  local x, y
  if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
    local ok, mapId = pcall(C_Map.GetBestMapForUnit, "player")
    if ok and mapId then
      local ok2, pos = pcall(C_Map.GetPlayerMapPosition, mapId, "player")
      if ok2 and type(pos) == "table" and pos.GetXY then x, y = pos:GetXY() end
    end
  end
  local payload = ns.Call.payload(GetZoneText and GetZoneText() or "", GetSubZoneText and GetSubZoneText() or "", x, y)
  local n, me = 0, ns.me()
  for _, name in ipairs(M.members(ns.state, id)) do
    local r = ns.roster(name)
    if name ~= me and r and r.online then Comm.Send("C", payload, "WHISPER", name); n = n + 1 end
  end
  for _, name in ipairs(M.benchMembers(ns.state, id)) do
    local r = ns.roster(name)
    if r and r.online then Comm.Send("C", payload, "WHISPER", name); n = n + 1 end
  end
  lastCall = GetTime()
  print_(L.CALL_SENT:format(n))
  return true
end

-- receiver side: only from a member of my squad, at most one per sender every 5 min
function ns.OnCall(payload, sender)
  local from = ns.fullName(sender)
  local id = A.MySquadId()
  if not id or not M.isMember(ns.state, id, from) then return end
  if not ns.Call.accept(seenCalls, from, GetTime()) then return end
  local text = ns.Call.text(payload)
  if not text then return end
  local msg = L.CALL_RECV:format(ns.shortName(from), text)
  if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo.RAID_WARNING then
    pcall(RaidNotice_AddMessage, RaidWarningFrame, msg, ns.POSITIVE_NOTICE or ChatTypeInfo.RAID_WARNING)
  elseif UIErrorsFrame and UIErrorsFrame.AddMessage then
    pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, msg, 1, 0.82, 0)
  end
  if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
  print_(msg)
end

-- pending requests (captain) + invitations, for the tab / minimap badge
function A.PendingCount()
  local me = ns.me()
  local n = #M.invites(ns.state, me)
  local id = A.MySquadId()
  if id and ns.state.squads[id].d.captain == me then n = n + #M.requests(ns.state, id) end
  return n
end
-- tell the captain when a new join request arrives (screen + chat + simple sound)
local lastReq
local function notifyRequests()
  local id = A.MySquadId()
  if not id or not ns.rosterReady or ns.state.squads[id].d.captain ~= ns.me() then lastReq = nil; return end
  local n = #M.requests(ns.state, id)
  if lastReq and n > lastReq then
    local msg = L.NEW_REQUEST
    if UIErrorsFrame and UIErrorsFrame.AddMessage then pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, msg, 1, 0.82, 0) end
    if PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then pcall(PlaySound, SOUNDKIT.TELL_MESSAGE) end
    print_(msg)
  end
  lastReq = n
end
-- the invited player gets the same notice (screen + sound + chat)
local lastInv
local function notifyInvites()
  if not ns.rosterReady then lastInv = nil; return end
  local list = M.invites(ns.state, ns.me())
  local n = #list
  if lastInv and n > lastInv then
    local msg = L.NEW_INVITE:format(squadName(list[#list]))
    if UIErrorsFrame and UIErrorsFrame.AddMessage then pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, msg, 1, 0.82, 0) end
    if PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then pcall(PlaySound, SOUNDKIT.TELL_MESSAGE) end
    print_(msg)
  end
  lastInv = n
end
function ns.UpdateBadge()
  pcall(notifyRequests)
  pcall(notifyInvites)
  if ns.UI and ns.UI.SetBadge then ns.UI.SetBadge(A.PendingCount()) end
  -- raids I am listed in and have not answered (badge on the Bandas tab)
  if ns.UI and ns.UI.SetRaidBadge and ns.RaidGlue then pcall(ns.UI.SetRaidBadge, ns.RaidGlue.PendingCount()) end
  -- "!" on the Mi perfil tab while the profile is incomplete
  if ns.UI and ns.UI.SetProfileMarker then pcall(ns.UI.SetProfileMarker, A.ProfileIncomplete()) end
end

-------------------------------------------------------------------------------
-- persistence
-- account-wide: seq, minimap, diag, UI hints. Guild data: GuildSquadsDB.guilds[key] (loaded in selectGuild)
local function loadDB()
  GuildSquadsDB = GuildSquadsDB or {}
  db = GuildSquadsDB
  db.v = 2
  db.seq = db.seq or 0
  db.minimap = db.minimap or { angle = 200, hide = false }
end

-- a character without guild (or before the roster) never overwrites anything
function saveDB()
  if db and ns.gdb and ns.rosterReady then ns.gdb.records = M.allRecords(ns.state) end
end

-------------------------------------------------------------------------------
-- events
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("PLAYER_GUILD_UPDATE")
local rosterQueued = false
f:SetScript("OnEvent", function(_, ev, arg1)
  if ev == "ADDON_LOADED" and arg1 == ADDON then
    if math.randomseed then math.randomseed(math.floor((GetTime() * 1000) % 2147483647)) end  -- not in the 1.60.1 API dump
    loadDB()
    Comm.Init(Sync.OnMessage)
  elseif ev == "PLAYER_LOGIN" then
    requestRoster()
  elseif ev == "GUILD_ROSTER_UPDATE" or ev == "PLAYER_GUILD_UPDATE" then
    -- the first read is immediate (bootstrap); later bursts are coalesced into one read after 1.5 s
    if not ns.rosterReady then readRoster()
    elseif not rosterQueued then
      rosterQueued = true
      ns.After(1.5, function() rosterQueued = false; readRoster() end)
    end
  elseif ev == "PLAYER_LEVEL_UP" then
    ns.After(2, function() A.RefreshProfile(false) end)
  elseif ev == "PLAYER_LOGOUT" then
    saveDB()
  end
end)
ns.Every(60, function() requestRoster() end, f)   -- ticker when C_Timer exists

-------------------------------------------------------------------------------
-- slash
SLASH_GUILDSQUADS1 = "/gsq"
SlashCmdList.GUILDSQUADS = function(msg)
  local cmd = ((msg or ""):match("^(%S*)") or ""):lower()
  if cmd == "export" then ns.UI.ShowExport(M.export(ns.state))
  elseif cmd == "import" then ns.UI.ShowExport("", true)
  elseif cmd == "sync" then
    -- one manual sync per 60 s
    local t = GetTime and GetTime() or 0
    if ns.lastManualSync and t - ns.lastManualSync < 60 then print_(L.SYNC_COOLDOWN or L.SYNC_SENT); return end
    ns.lastManualSync = t
    requestRoster(); Sync.Hello(); print_(L.SYNC_SENT)
  elseif cmd == "debug" then
    debugOn = not debugOn
    local s = Comm.stats
    local y = Sync.stats
    print_(L.DEBUG:format(("%s | sent=%d recv=%d failed=%d queued=%d pending=%d roster=%s online=%d bad=%d relayRefused=%d future=%d errors=%d quarantine=%d dropped=%d guild=%s"):format(
      tostring(debugOn), s.sent, s.recv, s.failed, Comm.Pending(), Sync.PendingCount(), tostring(ns.rosterReady), onlineN,
      y.bad, y.relayRefused, y.future, y.errors + (s.handlerErrors or 0), Sync.QuarantineCount(), Comm.queue.dropped or 0, tostring(ns.guildKey))))
    if ns.ProgressGlue then print_(ns.ProgressGlue.Debug()) end
    if ns.HallGlue then print_(ns.HallGlue.Debug()) end
  elseif cmd == "ui" then
    if not ns.UI.template then ns.UI.Toggle(); ns.UI.Toggle() end -- build the window once so every builder runs
    for _, line in ipairs(ns.W.ReportLines()) do print_(line) end
  elseif cmd == "diag" then
    if ns.DiagGlue then ns.UI.ShowExport(ns.DiagGlue.Report(), false, L.DIAG_HELP) end
  elseif cmd == "minimap" then
    db.minimap = db.minimap or {}
    db.minimap.hide = false
    if ns.Minimap then ns.Minimap.Show() end
  elseif cmd == "help" then print_(L.HELP)
  elseif cmd == "news" or cmd == "novedades" then
    ns.UI.Open(); ns.UI.ShowGuide("news")
  elseif cmd == "welcome" or cmd == "bienvenida" then
    ns.UI.Open(); ns.UI.ShowGuide("welcome")
  elseif cmd == "toggle" then ns.UI.Toggle()
  else ns.UI.Toggle() end
end

function ns.ImportText(text)
  local applied, rejected = M.import(ns.state, text, { roster = ns.roster, sender = ns.me() })
  print_(L.IMPORTED:format(applied, rejected))
  -- share what we restored
  if applied > 0 then Sync.Hello() end
  if ns.UI then ns.UI.Dirty() end
end
