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
local I = ns.Identity
-- 2.0 (SPEC-v2.0-identidad §2.4): the roster index of ns.id (byFirst, byFirstRealm, byLower, byFull, realms)
local rosterIdx = I.newIndex()
-- realm mode only (the 1.2.2): two members of one realm with the same first name and different surnames share the
-- key "Name-Realm". Such a key is ambiguous: out of the roster (their records are refused as notInGuild), their
-- messages are dropped and nothing is whispered to it. key -> { "Name Surname", ... }. In forever the identity
-- «Name Surname» is unique in the region: never ambiguous.
local ambig = {}

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

-------------------------------------------------------------------------------
-- 2.0 identity (docs/SPEC-v2.0-identidad.md §2). One function for every input: ns.id(a, b).
--   forever (WoW Forever, RegionalUniqueNamesEnabled() true): "Name Surname", no realm, unique in the region. It is
--           the author, trust key, signature, certificate, index and WHISPER target.
--   realm   (anything else): "Name-Realm", the 1.2.2 key.
-- The mode is read at ADDON_LOADED and again at PLAYER_LOGIN (that one wins), then frozen for the session. Tests
-- force it by setting ns.ID_MODE before loading the files. While it is nil, ns.id and ns.me give nil (nothing written).
local forcedMode = ns.ID_MODE
if forcedMode ~= "forever" and forcedMode ~= "realm" then forcedMode = nil end
ns.ID_MODE = forcedMode
local modeFrozen = forcedMode ~= nil
local meA, meB, meId                   -- my identity, kept while the client gives the same name (ns.me)
local function secret(v) return issecretvalue ~= nil and issecretvalue(v) and true or false end
local idCtx = { mode = forcedMode, myRealm = "", index = rosterIdx, isSecret = secret }

local function evalIdMode(final)
  if modeFrozen then return ns.ID_MODE end
  local mode = "realm"
  if type(RegionalUniqueNamesEnabled) == "function" then
    local okR, on = pcall(RegionalUniqueNamesEnabled)
    if okR and on == true then mode = "forever" end
  end
  if mode ~= ns.ID_MODE then meA, meB, meId = nil, nil, nil end
  ns.ID_MODE = mode
  if final then modeFrozen = true end
  return mode
end
ns.EvalIdMode = evalIdMode
do
  local idFrame = CreateFrame("Frame")
  idFrame:RegisterEvent("ADDON_LOADED")
  idFrame:RegisterEvent("PLAYER_LOGIN")
  idFrame:SetScript("OnEvent", function(_, ev, arg1)
    if ev == "ADDON_LOADED" and arg1 == ADDON then evalIdMode(false)
    elseif ev == "PLAYER_LOGIN" then evalIdMode(true) end
  end)
end

-- the identity of a name. a = sender, roster name, typed name or saved 1.x name; (a, b) = what UnitName gives.
-- Never raises; idempotent; nil when it is no character (or ambiguous: two «Kas» and no surname).
function ns.id(a, b)
  local mode = ns.ID_MODE
  if mode == nil then return nil end
  idCtx.mode, idCtx.myRealm, idCtx.index = mode, myRealm(), rosterIdx
  return I.id(a, b, idCtx)
end
-- UnitNameUnmodified first (WoW Forever: (name, surname); Ace3 swapped to it for the surname), UnitName otherwise
local function unitName(unit)
  local fn = UnitNameUnmodified or UnitName
  if type(fn) ~= "function" then return false end
  return pcall(fn, unit)
end
function ns.idFromUnit(unit)
  local okU, a, b = unitName(unit)
  if not okU then return nil end
  return ns.id(a, b)
end
-- my identity. Kept while the client gives the same (name, surname); TRP3 #1482: when the surname is missing for a
-- moment ("Kas", nil) and the roster cannot tell, the identity I already had stays (it does not change in a session)
function ns.me()
  if ns.ID_MODE == nil then return nil end
  local okU, a, b = unitName("player")
  if not okU or secret(a) or secret(b) then return meId end
  if meId ~= nil and a == meA and b == meB then return meId end
  -- realm (1.2.2): only the first value; for the player the realm is always mine
  local id = ns.ID_MODE == "realm" and ns.id(a) or ns.id(a, b)
  if id ~= nil then meA, meB, meId = a, b, id; return id end
  if meId ~= nil and ns.ID_MODE == "forever" and type(a) == "string" and I.firstOf(meId) == a then return meId end
  return nil
end

function ns.isSelf(sender)
  local id = ns.id(sender)
  return id ~= nil and id == ns.me()
end
-- realm mode (1.2.2): a name whose key two roster members share (never my own key: my entry is kept)
function ns.isAmbiguous(name)
  if ns.ID_MODE ~= "realm" then return false end
  local key = ns.id(name)
  return key ~= nil and ambig[key] ~= nil and key ~= ns.me()
end

-- TEMPORARY aliases (SPEC §2.4) so B and C merge in any order. C removes them at the end:
-- git grep -nE 'ns\.(fullName|charKey)\(' -- '*.lua' ':!tests/*' = 0.
function ns.fullName(name) return ns.id(name) end
function ns.charKey(name)
  local id = ns.id(name)
  if id == nil then return nil end
  idCtx.mode, idCtx.myRealm = ns.ID_MODE, myRealm()
  return id, I.surnameOf(name, idCtx)
end

-- forever: the identity itself («Kas Pitas»: nothing to cut, the realm is not part of it); realm: the 1.2.2
function ns.shortName(name)
  if ns.ID_MODE == "forever" then
    return ns.id(name) or (type(name) == "string" and name) or tostring(name)
  end
  return (name and name:match("^([^-]+)")) or tostring(name)
end

-- the WHISPER target of a character, nil when it is not in the roster (Comm routes the message over GUILD with the
-- recipient, never a blind whisper). forever (§6): the identity «Name Surname», never «-Realm», also towards a
-- connected realm, and no other variant (alt -> nil). realm: the 1.2.2 («Name Surname», alt with «-Realm»).
function ns.whisperTarget(name, alt)
  local key = ns.id(name)
  local r = key and rosterCache[key]
  if not r then return nil end
  if ns.ID_MODE == "forever" then
    if alt or not key:find(" ", 1, true) then return nil end
    return key
  end
  -- names are realm-unique only outside Forever: with regional unique names a roster entry without its surname (not
  -- cached yet) has no target that works (envelope instead)
  if not r.surname and type(RegionalUniqueNamesEnabled) == "function" then
    local okR, on = pcall(RegionalUniqueNamesEnabled)
    if okR and on then return nil end
  end
  return M.whisperTarget(key, r.surname, myRealm(), alt)
end

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
-- the roster entry of a character: { rank, level, class, online, zone, seen, surname, realm, raw }
function ns.roster(name)
  return rosterCache[ns.id(name) or ""]
end
function ns.onlineCount() return onlineN end
function ns.rosterList() return rosterCache end
function ns.rosterIndex() return rosterIdx end
-- forever: the identity «Kas Pitas» (two Kas never look the same; never «-Realm»). realm: «Fire Essency» when the
-- roster gave a surname, otherwise the short name (1.2.2)
function ns.displayName(name)
  if ns.ID_MODE == "forever" then return ns.shortName(name) end
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
-- 1.2.1: plus the realms of the roster keys, most common first (connected realms: senders and authors must carry
-- the same realm as these keys, see the diag line `peers ... notInRoster=`)
-- 2.0: plus the line `id mode=<forever|realm> me=<identity> surname=<yes|no>` first; in forever the realms come
-- from r.realm (the identity carries none)
function ns.RosterDiag()
  local n, s, realms = 0, 0, {}
  for key, r in pairs(rosterCache) do
    n = n + 1; if r.surname then s = s + 1 end
    local rl = (ns.ID_MODE == "forever" and r.realm) or key:match("%-(.*)$") or "?"
    realms[rl] = (realms[rl] or 0) + 1
  end
  local list = {}
  for rl, c in pairs(realms) do list[#list + 1] = { rl, c } end
  table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
  local parts = {}
  for i = 1, math.min(#list, 4) do parts[i] = list[i][1] .. ":" .. list[i][2] end
  local me = ns.me()
  -- realm mode (1.2.2): keys two members share (same realm, same first name)
  local na, first = 0, nil
  for key, names in pairs(ambig) do na = na + 1; first = first or (key .. ": " .. table.concat(names, ", ")) end
  local mine = me and rosterCache[me]
  local hasSurname = ns.ID_MODE == "forever" and me ~= nil and me:find(" ", 1, true) ~= nil or (mine and mine.surname ~= nil)
  return ("id mode=%s me=%s surname=%s\n"):format(tostring(ns.ID_MODE), tostring(me), hasSurname and "yes" or "no") ..
    ("[roster] me=%s found=%s entries=%d surnames=%d online=%d realms=%s ambiguous=%d%s mode=%s"):format(tostring(me),
    mine and "yes" or "no", n, s, onlineN, table.concat(parts, ","), na, first and (" (" .. first .. ")") or "",
    tostring(ns.ID_MODE))
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
  local g, migrated = M.guildDB(root, key, function(n) return ns.roster(n) ~= nil end)   -- 2.0: by identity (§3 #11)
  ns.gdb, ns.guildKey = g, key
  g.ann = nil -- announced hashes are not used
  -- 2.0 (SPEC-v2.0 §5): the 1.x names of this partition and of my character move to «Name Surname» before anything
  -- reads them (step 1 needs the roster, read just now). false = forever mode and no identity yet: wait for the next
  -- roster read, nothing is loaded nor written
  local idr = ns.MigrateIdentity and ns.MigrateIdentity(root, g)
  if idr == false then ns.gdb, ns.guildKey = nil, nil; return false end
  if type(idr) == "table" then
    ns.idMigration = idr
    local went = (idr.swept or 0) + (idr.dropped or 0)
    if went > 0 then ns.sweptSurnames = went; ns.debug(("2.0 identity: %d 1.x entries dropped, %d own records re-signed"):format(went, idr.resigned or 0)) end
  end
  -- v1.2 annex F: the keys we learned for this guild's members (TOFU strong / weak with quorum)
  if ns.Trust then
    g.trust = type(g.trust) == "table" and g.trust or {}
    ns.trustDB = ns.Trust.st(g.trust)
    pcall(ns.Trust.expire, ns.trustDB, (GetServerTime and GetServerTime()) or 0)
  end
  -- v1.2 annex F: the manifests verified for this guild's members and our own (Core/Sig.lua)
  if ns.Sig then
    g.sig = type(g.sig) == "table" and g.sig or {}
    ns.sigDB = ns.Sig.st(g.sig)
    ns.Sig.resetQueue()
  end
  -- v1.2 annex G: the certificates of the members we heard in person, and our own (Core/Cert.lua)
  if ns.Cert then
    g.cert = type(g.cert) == "table" and g.cert or {}
    ns.certDB = ns.Cert.st(g.cert)
    ns.Cert.resetQueue()
  end
  local saved = type(g.records) == "table" and g.records or {}
  -- v1.1: pending (unverified) versions, relay provenance and repudiation counts, before the records
  if ns.P2P then pcall(ns.P2P.import, ns.state, g.p2p) end
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
  ns.trustDB = nil
  ns.sigDB = nil
  ns.certDB = nil
  if ns.Sig then ns.Sig.resetQueue() end
  if ns.Cert then ns.Cert.resetQueue() end
  ns.state = M.newState()
  for _, fn in ipairs(ns.guildUnloadHooks) do pcall(fn) end
  if ns.UI then ns.UI.Dirty() end
end
ns.UnloadGuild = unloadGuild

local function readRoster()
  if not ns.ID_MODE then return end   -- no identity yet (before ADDON_LOADED): nothing to key the roster with
  if not (IsInGuild and IsInGuild()) then
    rosterCache = {}; onlineN = 0; rosterIdx = I.newIndex(); ambig = {}
    unloadGuild()   -- no guild -> no partition
    return
  end
  if ns.gdb and ns.rosterReady then
    local key = guildKey()
    if key and key ~= ns.guildKey then unloadGuild() end   -- another guild
  end
  local n = GetNumGuildMembers and GetNumGuildMembers() or 0
  if n == 0 then return end
  local cache, online, ix, amb, full = {}, 0, I.newIndex(), {}, {}
  local forever = ns.ID_MODE == "forever"
  for i = 1, n do
    local ok, name, rankLabel, rankIndex, level, _, zone, _, _, isOnline, _, classFile = pcall(GetGuildRosterInfo, i)
    -- 2.0: the identity of the entry. forever: «Kas Pitas-Realm» -> «Kas Pitas», the realm apart (r.realm); an entry
    -- without its surname is no identity there. realm (1.2.2): «Fire Essency» -> «Fire-Realm» + surname «Essency».
    local key, first, surname, rl
    if ok and type(name) == "string" and not secret(name) then
      first, surname, rl = I.split(name)
      if forever then
        if first and first ~= "" and surname then key = first .. " " .. surname end
      else
        key, surname = I.realmKey(name, myRealm())
        if key then first, _, rl = I.split(key) end
      end
      if not rl or rl == "" then rl = myRealm() end
    end
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
                     zone = type(zone) == "string" and zone or nil, seen = seen, surname = surname, realm = rl,
                     raw = name }
      I.indexAdd(ix, key, first, surname, rl)
      if not forever then
        local fk = first .. (surname and (" " .. surname) or "")
        if full[key] and full[key] ~= fk then
          amb[key] = amb[key] or { full[key] }
          local seen = false
          for _, x in ipairs(amb[key]) do if x == fk then seen = true end end
          if not seen then amb[key][#amb[key] + 1] = fk end
        end
        full[key] = full[key] or fk
      end
      if isOnline then online = online + 1 end
    end
  end
  rosterIdx = ix   -- before ns.me(): a player whose surname is not cached yet is found through it
  local me = ns.me()
  for key in pairs(amb) do if key ~= me then cache[key] = nil end end
  rosterCache, onlineN, ambig = cache, online, amb
  if ns.HallGlue and ns.HallGlue.OnRoster then pcall(ns.HallGlue.OnRoster, cache) end -- level races (roster)
  if not ns.rosterReady then
    if not selectGuild() then return end
    ns.rosterReady = true
    Sync.FlushPending()
    ns.Actions.RefreshProfile(true)
    ns.Actions.P2PHousekeeping()
    ns.After(3 + math.random() * 7, Sync.Hello)
    -- anti-entropy. A version that reached only some clients (loss, /reload mid-send)
    -- was never repaired while nobody logged in; one hello every 10-20 min (jittered) closes the gap
    if not ns.antiEntropy then
      ns.antiEntropy = true
      local function again()
        ns.After(600 + math.random() * 600, function()
          if ns.rosterReady then ns.Actions.P2PHousekeeping(); Sync.Hello() end
          again()
        end)
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
  if not ok then ns.ShowError(why)
  elseif ns.P2P and ns.gdb then
    -- v1.1: the ledger of my own versions (a relayed version with my name that is not here gets repudiated)
    ns.gdb.mine = type(ns.gdb.mine) == "table" and ns.gdb.mine or {}
    pcall(ns.P2P.ledgerNote, ns.gdb.mine, { k = kind, id = id, a = rec.a, ts = rec.ts, sq = rec.sq, d = M.sanitize(kind, data) or {} }, rec.ts)
  end
  return ok, why
end

-- v1.1: presence {ver, day}, at most once a day (the real installed counter); pending versions expire after 7 days;
-- presences of members who left the guild or older than 60 days are pruned
function A.PublishPresence()
  if not ns.rosterReady then return false end
  local me = ns.me()
  local day = math.floor(serverTime() / 86400)
  local ver = tostring(ns.VERSION or "?"):sub(1, 16)
  local cur = ns.state.presence and ns.state.presence[me]
  if cur and cur.d.day == day and cur.d.ver == ver then return false end
  return write("presence", me, { ver = ver, day = day })
end
function A.P2PHousekeeping()
  local X = ns.P2P
  if not (X and ns.rosterReady) then return end
  local t = serverTime()
  pcall(X.expire, ns.state, t)
  pcall(X.prunePresence, ns.state, rosterCache, t)
  A.PublishPresence()
end
-- a relayed version with my name that I never wrote (Sync: "mine"): sign a repudiate once and resend my version.
-- sec F1: anyone can forge unsigned versions with my name, so at most MINE_MAX repudiates per MINE_WINDOW seconds
-- (each one is a record of mine, re-signed into my manifest and stored by the whole guild for 30 days)
local denied = {}
local MINE_MAX, MINE_WINDOW = 5, 3600
local mineAt = {}
-- sec r3 I4: the window is kept in the guild's saved db in server time, so a /reload does not give MINE_MAX more
local function mineTimes()
  if not ns.gdb then return mineAt, GetTime and GetTime() or 0 end
  ns.gdb.mineAt = type(ns.gdb.mineAt) == "table" and ns.gdb.mineAt or {}
  return ns.gdb.mineAt, (ns.serverTime and ns.serverTime()) or (GetServerTime and GetServerTime()) or 0
end
function ns.OnMine(rec)
  local X = ns.P2P
  if not X or type(rec) ~= "table" then return end
  local clean = { k = rec.k, id = rec.id, a = rec.a, ts = rec.ts, sq = rec.sq, d = M.sanitize(rec.k, rec.d) or {} }
  if clean.a ~= ns.me() then return end
  local vk = X.vkey(clean)
  if denied[vk] or (ns.state.repudiates and ns.state.repudiates[vk]) then return end
  local times, now = mineTimes()
  while times[1] and (type(times[1]) ~= "number" or now - times[1] >= MINE_WINDOW or times[1] > now + 60) do table.remove(times, 1) end
  if #times >= MINE_MAX then Sync.stats.mineCapped = (Sync.stats.mineCapped or 0) + 1; return end
  times[#times + 1] = now
  denied[vk] = true
  write("repudiate", vk, { t = X.kid(clean), v = vk })
  Sync.Resend(M.stored(ns.state, clean))
end

-- a key of `name` was replaced (owner heard in person, signed rotation, disputed / re-certified): drop what the old
-- key signed and we applied by relay (annex F/G, QA D1); the author's own copy comes back with his new manifest
function ns.OnKeyReplaced(name, oldPk)
  local X = ns.P2P
  if not (X and X.dropSignedBy) then return end
  local okD, n = pcall(X.dropSignedBy, ns.state, name, oldPk)
  if okD and n and n > 0 and ns.UI and ns.UI.Dirty then pcall(ns.UI.Dirty) end
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
  if db and ns.gdb and ns.rosterReady then
    ns.gdb.records = M.allRecords(ns.state)
    if ns.P2P then ns.gdb.p2p = ns.P2P.export(ns.state) end
  end
end

-------------------------------------------------------------------------------
-- v1.2 annex F: our own ed25519 key, per character (GuildSquadsDB.ownKeys[name] = { me = {sk, pk} }), created once
-- the entropy pool has T.MIN_SAMPLES samples: debugprofilestop() at every event and frame, GetTime, GetServerTime,
-- cursor position, the player GUID and math.random. The pool stops sampling once the key exists.
local pool = ns.Trust and ns.Trust.entropy()
local ownPk
local f, sampler                       -- the events frame and its OnUpdate key sampler (defined below)
local function sample(tag)
  if not pool or ownPk then return end
  local cx, cy
  if GetCursorPosition then cx, cy = GetCursorPosition() end
  pool.add(tag, debugprofilestop and debugprofilestop() or 0, GetTime and GetTime() or 0,
    GetServerTime and GetServerTime() or 0, cx, cy, UnitGUID and UnitGUID("player") or "", math.random(1, 2147483646))
end
local ownFor                           -- the identity ownPk belongs to
function ns.myPk()
  if not (ns.Trust and db and ns.me) then return nil end
  local me = ns.me()
  if not me then return nil end
  if ownPk and ownFor == me then return ownPk end
  ownPk = nil
  -- 2.0 (SPEC-v2.0 §5 step 2): in forever mode the key of the identity is made after the migration ran for it (it
  -- drops the 1.x key "Name-Realm"); never one under a name that is not the identity
  if ns.ID_MODE == "forever" and not (type(db.idv) == "table" and db.idv[me] == M.IDV) then return nil end
  db.ownKeys = type(db.ownKeys) == "table" and db.ownKeys or {}
  local holder = type(db.ownKeys[me]) == "table" and db.ownKeys[me] or {}
  local fresh = holder.me == nil
  local ok, _, pk = pcall(ns.Trust.ensureOwn, holder, pool)
  if ok and pk then
    db.ownKeys[me] = holder; ownPk, ownFor = pk, me
    -- a key made now: our records may already be out unsigned (published while the pool was still sampling). Sign
    -- and send our manifest (MAN_DEBOUNCE s later) so the ones who log in after us can verify them when relayed.
    if fresh and ns.Sync and ns.Sync.QueueOwnManifest then ns.Sync.QueueOwnManifest() end
    -- 2.0 (SPEC-v2.0 §5 step 2): in forever mode the key of the identity is only made after the migration (selectGuild),
    -- so it can be born after a hello already went out without it: one hello now (heard in person the key is strong
    -- for everyone online, who then verify the manifest n = 1), not 10-20 min later in the next anti-entropy hello.
    -- Realm mode keeps the 1.2.2 behaviour (the key in the next hello).
    if fresh and ns.ID_MODE == "forever" and ns.Sync and ns.Sync.helloWithoutKey and ns.rosterReady and ns.Sync.Hello then
      ns.Sync.helloWithoutKey = nil
      local hello = function() pcall(ns.Sync.Hello) end
      if ns.After and ns.Sync.WhenIdle then ns.After(1, function() ns.Sync.WhenIdle(hello) end) else hello() end
    end
    -- AF5: a key made after /gsq trust newkey is signed by the old one (Sync.OwnRotation), then the old one is gone
    local prev = type(db.prevOwnKeys) == "table" and db.prevOwnKeys[me]
    if prev then
      local osk, opk = ns.Trust.own(prev)
      if osk and opk and ns.Sync and ns.Sync.OwnRotation then pcall(ns.Sync.OwnRotation, osk, opk, pk) end
      db.prevOwnKeys[me] = nil
      -- re-sign our records and say hello with the new key now (heard in person it is strong), not in the next one
      if ns.Sync and ns.Sync.ResignOwn then ns.Sync.ResignOwn() end
      if ns.Sync and ns.Sync.QueueOwnManifest then ns.Sync.QueueOwnManifest() end
      -- fix/perf M2: the hello re-signs our certificate (one more sign + a hash per key): not in the frame of the
      -- publicKey and the rotation sign, and not in combat / an encounter
      if ns.Sync and ns.Sync.Hello and ns.rosterReady then
        local hello = function() pcall(ns.Sync.Hello) end
        if ns.After and ns.Sync.WhenIdle then ns.After(1, function() ns.Sync.WhenIdle(hello) end) else hello() end
      end
    end
  end
  return ownPk
end
-- /gsq trust newkey (BRO 8-nov 03:09): drop our key after a confirmation; a new one is made from fresh entropy,
-- announced in the next hello (heard in person it always wins) and our records are signed again with it
function ns.NewOwnKey()
  local me = ns.me and ns.me()
  if not (db and me and type(db.ownKeys) == "table") then return false end
  if type(db.ownKeys[me]) == "table" and db.ownKeys[me].me then
    db.prevOwnKeys = type(db.prevOwnKeys) == "table" and db.prevOwnKeys or {}
    db.prevOwnKeys[me] = db.ownKeys[me]            -- kept only until the new key is made and signed (AF5)
  end
  db.ownKeys[me] = nil
  ownPk = nil
  -- fresh entropy: the old pool stopped sampling once our key existed, its seed would give the same key again.
  -- The new key is made by the OnUpdate sampler once the new pool has T.MIN_SAMPLES samples (ns.myPk above).
  pool = ns.Trust.entropy()
  if f and sampler then f:SetScript("OnUpdate", sampler) end
  return true
end
function ns.mySk()
  if not ns.myPk() then return nil end
  return ns.Trust.own(db.ownKeys[ns.me()])
end
-- 2.0 (SPEC-v2.0 §5): Model.migrateIdentity with this client's identity, on a guild partition g of root
-- (GuildSquadsDB). Realm mode: nothing to migrate ({}). Forever mode without an identity yet: false (selectGuild
-- waits). dry = count what it would do on a copy (/gsq diag). Returns the counts of Model.migrateIdentity.
function ns.MigrateIdentity(root, g, dry)
  if ns.ID_MODE ~= "forever" then return {} end
  local me = ns.me and ns.me()
  if type(me) ~= "string" or me == "" then return false end
  local sp = string.find(me, " ", 1, true)
  local oldMe = (sp and string.sub(me, 1, sp - 1) or me) .. "-" .. myRealm()     -- the 1.x key of this character
  local now = (ns.serverTime and ns.serverTime()) or (GetServerTime and GetServerTime()) or 0
  local Pg, Rc, Ro, Ca, X = ns.Progress, ns.Races, ns.Roster, ns.Catalog, ns.P2P
  local ctx = { mode = "forever", id = ns.id, me = me, oldMe = oldMe, now = now, dry = dry and true or nil,
                eventId = Pg and Pg.eventId, obsId = Rc and Rc.obsId, rsvpId = Ro and Ro.rsvpId, grantId = Ca and Ca.grantId }
  if X and X.ledgerNote then   -- my re-signed versions go to the ledger (a relayed copy of them is never repudiated)
    ctx.note = function(rec)
      g.mine = type(g.mine) == "table" and g.mine or {}
      X.ledgerNote(g.mine, { k = rec.k, id = rec.id, a = rec.a, ts = rec.ts, sq = rec.sq, d = M.sanitize(rec.k, rec.d) or {} }, now)
    end
  end
  local okM, r = pcall(M.migrateIdentity, root, g, ctx)
  if not okM then if ns.debug then ns.debug("2.0 identity migration error: " .. tostring(r)) end return {} end
  return r
end

-------------------------------------------------------------------------------
-- events
f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("PLAYER_GUILD_UPDATE")
local rosterQueued = false
sampler = function()
  if ownPk or not pool then f:SetScript("OnUpdate", nil); return end
  sample("f")
  if pool.n >= ns.Trust.MIN_SAMPLES and db and ns.myPk() then f:SetScript("OnUpdate", nil) end
end
f:SetScript("OnUpdate", sampler)
-- v1.2 annex F: at most one manifest verify per frame, never in combat nor during a boss encounter
local sigFrame = CreateFrame("Frame")
sigFrame:SetScript("OnUpdate", function()
  if not ((ns.sigDB and ns.Sig and ns.Sig.pending() > 0) or (ns.Cert and ns.certDB and ns.Cert.pending() > 0)
    or (Sync.RotPending and Sync.RotPending() > 0)) then return end
  if InCombatLockdown and InCombatLockdown() then return end
  local enc = ns.encounterFn and ns.encounterFn()  -- 16001: C_InstanceEncounter, not a global (QA r3 Q3-1)
  if enc and enc() then return end
  Sync.SigStep()
end)
f:SetScript("OnEvent", function(_, ev, arg1)
  sample(ev)
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
  elseif cmd == "trust" then
    -- /gsq trust reset <name>: forget a member's key (he lost his SavedVariables); learned again from him in person
    local sub, who = (msg or ""):match("^%S+%s+(%S+)%s*(%S*)")
    if sub == "newkey" then
      local W = ns.W
      local go = function()
        if ns.NewOwnKey() then print_(L.TRUST_NEWKEY_DONE or "Clave nueva en curso.") end
      end
      if W and W.Confirm then W.Confirm(L.TRUST_NEWKEY_CONFIRM, go) else print_(L.TRUST_NEWKEY_CONFIRM) end
    elseif sub == "reset" and who and who ~= "" and ns.Trust and ns.trustDB then
      local name = (ns.fullName and ns.fullName(who)) or who
      ns.Trust.reset(ns.trustDB, name)
      if ns.Sync and ns.Sync.DropOwnCertCache then ns.Sync.DropOwnCertCache() end
      print_((L.TRUST_RESET or "Clave olvidada: %s"):format(name))
    else
      print_(L.TRUST_USAGE or "/gsq trust reset <nombre>")
    end
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
