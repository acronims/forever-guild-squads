-- Guild Squads (MIT) - Hall.lua
-- WoW glue for the "Salón de la fama": detection (own level ups, guild roster level changes incl. members
-- without the addon, boss kills, BG wins with the map name, honorable kills, PvP rank, professions, reputation,
-- Overlord captures), replication of RaceObs over the GUILD addon channel (same throttled queue: never during an
-- encounter), paginated catch-up on sync hellos, learned boss catalog, toasts and GM-configured celebrations in
-- guild chat (single announcer, 1 message / 10 s, never during an encounter or chat lockdown).
-- Every client API here is unverified in WoW Forever: existence check + pcall, with fallbacks.
local _, ns = ...
local L, M, P, Pr, R, Cel, Content, Comm = ns.L, ns.Model, ns.Permissions, ns.Progress, ns.Races, ns.Celebrate, ns.Content, ns.Comm
local Cat = ns.Catalog

local H = {}
ns.HallGlue = H

local store = R.newStore()
local rdb                                  -- GuildSquadsDB.races
local races, info, dirty = nil, nil, true
local achProg = { squad = {}, char = {}, guild = {} }
local celQ = Cel.newQueue()
local PAGE, PAGES_PER_HELLO, PER_MSG = 20, 3, 4
H.chatError = nil

local function now() return (GetServerTime and GetServerTime()) or time() end
local function settings() return M.settingsOf(ns.state) end
local function call(fn, ...) if type(fn) ~= "function" then return false end return pcall(fn, ...) end
function H.Enabled() local s = settings(); return s.squadsEnabled and s.compEnabled ~= false end

local encounter = false -- ENCOUNTER_START .. ENCOUNTER_END (backup for IsEncounterInProgress)
function H.InEncounter()
  if encounter then return true end
  local okE, v = call(((ns.encounterFn and ns.encounterFn()) or IsEncounterInProgress))
  return okE and v == true
end
function H.ChatLocked()
  if C_ChatInfo and type(C_ChatInfo.InChatMessagingLockdown) == "function" then
    local okL, v = pcall(C_ChatInfo.InChatMessagingLockdown)
    if okL and v then return true end
  end
  return false
end

-------------------------------------------------------------------------------
-- context for Core/Races
local function squadsMap()
  local out = {}
  for sid, r in pairs(ns.state.squads or {}) do if not r.d.disbanded then out[sid] = M.members(ns.state, sid) end end
  return out
end
local function classesSeen()
  local seen, out = {}, {}
  for _, r in pairs(ns.rosterList and ns.rosterList() or {}) do
    if type(r.class) == "string" and not seen[r.class] then seen[r.class] = true; out[#out + 1] = r.class end
  end
  table.sort(out)
  return out
end
function H.SeasonId()
  local cfg = Pr.seasonCfg(settings())
  return tostring(#(cfg.past or {}) + 1)
end
-- APIs that do not exist in this client -> "pendiente de datos"
function H.NoData()
  local nd = { legacy = true } -- no known Legacy Points API (see docs/en/ACHIEVEMENTS.md §5)
  if not (ns.apiFn("GetProfessions", "GetSkillLineInfo", "C_SkillInfo.GetSkillLineInfo")) then nd.prof = true end
  if not ((C_Reputation and (C_Reputation.GetFactionDataByIndex or C_Reputation.GetNumFactions)) or GetFactionInfo) then nd.rep = true end
  return nd
end

-- learned catalog = replicated "boss" records (GM records may mark `final`)
-- a boss taught by a GM/officer is confirmed; anyone else's stays pending until a kill of it is
-- witnessed by >= 2 reporters (info.killed). `final` is replayed in (ts, id) order, so the GM's LAST decision
-- wins on every client (Content.setFinal clears the other finals of the instance).
local function syncCatalog(killed)
  local list = {}
  for id, rec in pairs(ns.state.bosses or {}) do list[#list + 1] = rec end
  table.sort(list, function(a, b) if a.ts ~= b.ts then return a.ts < b.ts end return a.id < b.id end)
  local s = settings()
  for _, rec in ipairs(list) do
    local d = rec.d
    local b = Content.learnBoss(d.inst, d.enc, d.name, d.kind, P.isOfficer(ns.roster, rec.a, s))
    if b and b.id == rec.id and d.final ~= nil and P.isGM(ns.roster, rec.a) then Content.setFinal(rec.id, d.final) end
  end
  for id in pairs(killed or {}) do if Content.bosses[id] then Content.confirmBoss(id) end end
end

function H.Ctx()
  return { now = now(), isFinal = Content.isFinal, hasFinal = Content.hasFinal, bossesOf = Content.bossesOf,
           trusted = function(n) return P.isOfficer(ns.roster, n, settings()) end,
           inGuild = function(n) return ns.roster(n) ~= nil end,
           squads = squadsMap, annul = R.annulMap(ns.state.annuls), nodata = H.NoData(), season = H.SeasonId(),
           classes = classesSeen(), syncing = ns.Sync and ns.Sync.Syncing and ns.Sync.Syncing() or false }
end

local function markDirty() dirty = true; if ns.UI and ns.UI.Dirty then ns.UI.Dirty() end end
H.MarkDirty = markDirty

local afterCompute
function H.Races()
  if dirty or not races then
    syncCatalog(info and info.killed)
    R.applyConfirms(store, ns.state.vconfirm)   -- GM / officer confirmations
    races, info = R.compute(store, H.Ctx())
    syncCatalog(info and info.killed)
    dirty = false
    if afterCompute then pcall(afterCompute) end
  end
  return races, info
end
function H.Race(id) return (H.Races())[id] end
function H.Store() return store end

-------------------------------------------------------------------------------
-- capture
local function addObs(ev)
  if not rdb then return false end
  local okA, id = R.add(store, ev, now())
  if not okA then return false, id end
  local clean = store.obs[id]
  -- ACK: our own observation waits in `pend` until a peer's hello shows it holds it (or 3 h)
  if clean.by == ns.me() and type(rdb.pend) == "table" then rdb.pend[id] = now() end
  -- live observations go before any backlog of hello replies
  ns.After(1 + math.random() * 3, function() Comm.Send("RO", { o = { clean } }, nil, nil, nil, true) end)
  markDirty()
  return true, id
end
H.AddObs = addObs

local function isMilestone(lv) for _, h in ipairs(R.LEVELS) do if h == lv then return true end end return false end

function H.OnLevelUp(level)
  if not (H.Enabled() and type(level) == "number" and isMilestone(level)) then return end
  local okC, _, cls = call(UnitClass, "player")
  local okR, _, race = call(UnitRace, "player")
  return addObs({ t = "lv", who = ns.me(), by = ns.me(), ts = now(), src = "self", lv = level,
                  cls = okC and type(cls) == "string" and cls or nil, race = okR and type(race) == "string" and race or nil })
end

-- GUILD_ROSTER_UPDATE: level changes of other members (with or without the addon) against a cache.
-- First sighting = no report (not retroactive).
function H.OnRoster(cache)
  if not rdb or not H.Enabled() then return end
  local me = ns.me()
  for name, r in pairs(cache or {}) do
    local lv = r.level
    if type(lv) == "number" then
      local prev = rdb.rcache[name]
      if type(prev) == "number" and lv > prev and name ~= me then
        for _, h in ipairs(R.LEVELS) do
          if prev < h and lv >= h then
            addObs({ t = "lv", who = name, by = me, ts = now(), src = "roster", lv = h, cls = type(r.class) == "string" and r.class or nil })
          end
        end
      end
      if not prev or lv > prev then
        rdb.rcache[name] = lv
        rdb.rseen[name] = { lv = lv, ts = now() }   -- when this client saw the level (backdating bound)
      end
    end
  end
end

local function groupNames()
  local out = { ns.me() }
  local inRaid = IsInRaid and select(2, pcall(IsInRaid)) == true
  if inRaid and GetRaidRosterInfo and GetNumGroupMembers then
    local okN, n = pcall(GetNumGroupMembers)
    for i = 1, (okN and type(n) == "number") and math.min(n, 40) or 0 do
      local okR, name = pcall(GetRaidRosterInfo, i)
      if okR and type(name) == "string" and ns.charKey(name) ~= ns.me() then out[#out + 1] = ns.charKey(name) end
    end
  elseif UnitName then
    for i = 1, 4 do
      local okU, name, realm = pcall(UnitName, "party" .. i)
      -- party names can be secret in restricted instances; skip them instead of comparing
      if okU and issecretvalue and (issecretvalue(name) or issecretvalue(realm)) then okU = false end
      if okU and type(name) == "string" then out[#out + 1] = ns.fullName((realm and realm ~= "") and (name .. "-" .. realm) or name) end
    end
  end
  return out
end
local function squadMarks(names)
  local sqm = {}
  for _, n in ipairs(names) do
    local sid = M.squadOf(ns.state, n)
    if sid then sqm[#sqm + 1] = n .. ">" .. sid end
  end
  return sqm
end
H.GroupNames, H.SquadMarks = groupNames, squadMarks

function H.OnEncounterEnd(encounterID, encounterName, _, groupSize, success)
  if success ~= 1 and success ~= true then return end
  if not H.Enabled() then return end
  local okI, instName, instType, _, _, _, _, _, instanceID = call(GetInstanceInfo)
  if not okI or (instType ~= "party" and instType ~= "raid") then return end
  local names = groupNames()
  local ev = { t = "kill", who = ns.me(), by = ns.me(), ts = now(), inst = type(instName) == "string" and instName or nil,
               iid = type(instanceID) == "number" and instanceID or nil, it = instType,
               enc = type(encounterID) == "number" and encounterID or nil,
               boss = type(encounterName) == "string" and encounterName or nil,
               gs = type(groupSize) == "number" and groupSize or nil, pres = names, sqm = squadMarks(names) }
  local okA = addObs(ev)
  -- learned boss catalog: the first kill teaches it to the guild (replicated record, no duplicates)
  local clean = R.sanitize(ev)
  if clean then
    local ik, kind = R.instKey(clean)
    local b = Content.learnBoss(ik, clean.enc, clean.boss, kind)
    if b and not (ns.state.bosses and ns.state.bosses[b.id]) and ns.Actions.WriteRecord then
      ns.Actions.WriteRecord("boss", b.id, { inst = ik, enc = b.enc, name = b.name, kind = kind })
    end
  end
  return okA
end

local bgDone = false
function H.OnBattleEnd()
  if bgDone or not H.Enabled() then return end
  local winner = ns.ProgressGlue and ns.ProgressGlue.BgWinner and ns.ProgressGlue.BgWinner()
  local okF, faction = call(UnitFactionGroup, "player")
  local win = Pr.bgOutcome(winner, okF and faction or nil)
  if win == nil then return end
  bgDone = true
  local okI, instName = call(GetInstanceInfo) -- the BG map name ("pvp.bgmap.<MAPA>")
  local names = groupNames()
  return addObs({ t = "bg", who = ns.me(), by = ns.me(), ts = now(), inst = (okI and type(instName) == "string") and instName or "?",
                  win = win, pres = names, sqm = squadMarks(names) })
end

-- readers (all guarded; nil = API missing) ----------------------------------
-- WoW Forever 1.60.1 has no UnitPVPRank -> the honor rank achievements and races cannot be earned there;
-- the UI hides them (UI.MyAchievementList, UI.HallRaceList) and /gsq diag says pvpRank=unsupported.
function H.PvPRankSupported() return ns.apiFn("UnitPVPRank") ~= nil end
function H.ReadPvPRank()
  local okR, rankID = call(UnitPVPRank, "player")
  if not okR or type(rankID) ~= "number" then return nil end
  local okI, _, rankNumber = call(GetPVPRankInfo, rankID)
  if okI and type(rankNumber) == "number" then return math.max(0, rankNumber) end
  return math.max(0, rankID - 4) -- classic: rank ids start at 5 for rank 1
end

-- professions: WoW Forever 1.60.1 (build 70338) has no global GetNumSkillLines/GetSkillLineInfo; the
-- API dump lists C_SkillInfo.GetNumSkillLines / C_SkillInfo.GetSkillLineInfo and the globals GetProfessions /
-- GetProfessionInfo. Paths, in order, each guarded with ns.apiFn and pcall; a path that yields 0 professions falls
-- through to the next one (an existing-but-empty GetProfessions returns {} and must not stop the search):
--   1. GetProfessions + GetProfessionInfo (retail shape: indices; name, icon, rank)
--   2. C_SkillInfo.GetNumSkillLines + C_SkillInfo.GetSkillLineInfo, then the legacy globals as fallback.
-- ASSUMPTION (not readable from the dump, which has names only): C_SkillInfo.GetSkillLineInfo(i) returns EITHER
-- the legacy multi-value shape (name, isHeader, isExpanded, rank, ...) OR a table with
-- {skillName|name, isHeader, skillRank|rank|skillLineRank}. Both are accepted. /gsq diag reports the path used and
-- the count (H.ProfDebug) so the in-game test confirms which one is real.
H.profPath, H.profCount = "none", 0
local function profHeader(h) return h and (h:find("rofes") or h:find("econdar") or h:find("ecundar")) end
local function skillLines(nFn, infoFn, out)
  local okN, n = pcall(nFn)
  if not okN or type(n) ~= "number" then return false end
  local header
  for i = 1, math.min(n, 80) do
    local okS, name, isHeader, _, rank = pcall(infoFn, i)
    if okS and type(name) == "table" then
      local t = name
      name, isHeader = t.skillName or t.name, t.isHeader
      rank = t.skillRank or t.rank or t.skillLineRank
    end
    if okS and type(name) == "string" then
      if isHeader then header = name:lower()
      elseif profHeader(header) and type(rank) == "number" then out[name] = rank end
    end
  end
  return true
end
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

function H.ReadProfessions()
  local out, any = {}, false
  local getP, getPI = ns.apiFn("GetProfessions"), ns.apiFn("GetProfessionInfo")
  if getP and getPI then
    local okP, a, b, c, d, e = pcall(getP)
    if okP then
      any = true
      for _, idx in ipairs({ a or false, b or false, c or false, d or false, e or false }) do
        if idx then
          local okI, name, _, rank = pcall(getPI, idx)
          if okI and type(name) == "string" and type(rank) == "number" then out[name] = rank end
        end
      end
      if next(out) then H.profPath, H.profCount = "GetProfessions", count(out); return out end
    end
  end
  local paths = { { "C_SkillInfo", "C_SkillInfo.GetNumSkillLines", "C_SkillInfo.GetSkillLineInfo" },
                  { "GetSkillLineInfo", "GetNumSkillLines", "GetSkillLineInfo" } }
  for _, p in ipairs(paths) do
    local nFn, infoFn = ns.apiFn(p[2]), ns.apiFn(p[3])
    if nFn and infoFn and skillLines(nFn, infoFn, out) then
      any = true
      if next(out) then H.profPath, H.profCount = p[1], count(out); return out end
    end
  end
  H.profPath, H.profCount = any and "empty" or "none", 0
  if any then return out end
  return nil
end
function H.ProfDebug() return ("prof path=%s n=%d"):format(tostring(H.profPath), H.profCount or 0) end

function H.ReadReputation()
  local out = {}
  if C_Reputation and type(C_Reputation.GetNumFactions) == "function" and type(C_Reputation.GetFactionDataByIndex) == "function" then
    local okN, n = pcall(C_Reputation.GetNumFactions)
    if okN and type(n) == "number" then
      for i = 1, math.min(n, 120) do
        local okD, d = pcall(C_Reputation.GetFactionDataByIndex, i)
        if okD and type(d) == "table" and type(d.name) == "string" and not d.isHeader and type(d.reaction) == "number" then out[d.name] = d.reaction end
      end
      return out
    end
  end
  if type(GetNumFactions) == "function" and type(GetFactionInfo) == "function" then
    local okN, n = pcall(GetNumFactions)
    if not okN or type(n) ~= "number" then return nil end
    for i = 1, math.min(n, 120) do
      local okF, name, _, standing, _, _, _, _, _, isHeader = pcall(GetFactionInfo, i)
      if okF and type(name) == "string" and not isHeader and type(standing) == "number" then out[name] = standing end
    end
    return out
  end
  return nil
end

-- counters: only threshold crossings are reported (one observation per step, never twice)
-- `sent` is per character; a step is marked only when the observation
-- was really taken (or already held). The first sample of a guarded counter sends one BASELINE reading with the
-- current value (never scored: the Top counts progress from there) and marks the steps already crossed.
local function charTable(field)
  local me = ns.me()
  rdb[field] = type(rdb[field]) == "table" and rdb[field] or {}
  rdb[field][me] = type(rdb[field][me]) == "table" and rdb[field][me] or {}
  return rdb[field][me]
end
local function report(k, key, n, steps, extra)
  local sent = charTable("sent")
  local sea = (extra and extra.sea) or ""
  local function obs(v)
    local ev = { t = "cnt", who = ns.me(), by = ns.me(), ts = now(), k = k, key = key, n = v }
    for a, b in pairs(extra or {}) do ev[a] = b end
    local okA, why = addObs(ev)
    return okA or why == "dup"
  end
  if R.CNT_GUARDED[k] then
    local bk = "base|" .. k .. "|" .. (key or "") .. "|" .. sea
    if not sent[bk] then
      local any = false
      for _, step in ipairs(steps) do if sent[k .. "|" .. (key or "") .. "|" .. step .. "|" .. sea] then any = true end end
      if not any then   -- nothing reported yet for this counter: the baseline
        if not obs(math.min(math.max(0, math.floor(n)), 1000000)) then return end
        for _, step in ipairs(steps) do if n >= step then sent[k .. "|" .. (key or "") .. "|" .. step .. "|" .. sea] = true end end
      end
      sent[bk] = true
      if not any then return end
    end
  end
  for _, step in ipairs(steps) do
    local sk = k .. "|" .. (key or "") .. "|" .. step .. "|" .. sea
    if n >= step and not sent[sk] then
      if obs(step) then sent[sk] = true end
      return   -- one step per sample (two steps with the same ts would be refused)
    end
  end
end

function H.SampleCounters()
  if not rdb or not H.Enabled() then return end
  if ns.ProgressGlue and ns.ProgressGlue.ReadHK then
    local hk, src = ns.ProgressGlue.ReadHK()
    if hk and src == "lifetime" then
      -- counted from the moment the addon is installed, per character
      rdb.hkBase = type(rdb.hkBase) == "table" and rdb.hkBase or {}
      rdb.hkBase[ns.me()] = rdb.hkBase[ns.me()] or hk
      report("hk", nil, math.max(0, hk - rdb.hkBase[ns.me()]), R.HK_STEPS)
    end
    local g = ns.ProgressGlue
    if g.OverlordPresent and g.OverlordPresent() and g.OverlordEnabled() then
      local okN, short = call(UnitName, "player")
      local caps = Pr.overlordCaptures(g.Overlord(), okN and short or ns.me())
      if caps then report("caps", nil, caps, R.CAPS_STEPS) end
    end
  end
  local rank = H.ReadPvPRank()
  if rank and rank > 0 then
    local okC, _, cls = call(UnitClass, "player")
    report("pvprank", nil, rank, R.PVP_RANKS, { sea = H.SeasonId(), cls = okC and cls or nil })
  end
  for name, lv in pairs(H.ReadProfessions() or {}) do report("prof", name, lv, R.PROF_STEPS) end
  for name, st in pairs(H.ReadReputation() or {}) do report("rep", name, st, { R.EXALTED }) end
end

-------------------------------------------------------------------------------
-- replication
-- "RO": live observations, author only (sender == by). "RP": catch-up pages.
-- (no "announced hash" path):
--   * a relayed observation is taken only when the relayer is GM/officer or the author itself (its own page);
--   * a LEVEL observation is taken live only when dated inside [now-600, now+300] (receiver clock) and not before
--     this client last saw the character at a lower level; from a catch-up page only when a GM/officer relays it;
--   * closed races (aggregates without an author) only from GM/officers; >300 s in the future is refused.
-- counters (HK, captures, professions, reputation) follow the level rule; R.add also refuses a counter that
--   goes down or jumps more than the plausible rate (Core/Races.lua R.counterOk).
local function relayerTrusted(from)
  local P = ns.Permissions
  return P and ns.Model and P.isOfficer(ns.roster, from, ns.Model.settingsOf(ns.state)) or false
end
-- every observation from its author (live "RO", or the author's own
--   page in reply to a hello = the retry path) is judged by the send window R.liveOk (sentAt within 300 s of our
--   clock, ts <= sentAt, at most 3 h in the sender's queue): levels, counters, kills and BGs alike. Pages relayed by
--   a GM/officer are trusted (and confirm what we hold as unverified).
function H.OnObs(payload, sender, relayed, sentAt)
  if not rdb or type(payload) ~= "table" then return end
  local from = ns.fullName(sender)
  local officer = relayerTrusted(from)
  local t = now()
  local limit = t + 300
  local any = false
  local list = type(payload.o) == "table" and payload.o or {}
  for i = 1, math.min(#list, 20) do
    local ev = R.sanitize(list[i])
    if ev and ev.ts <= limit and ns.roster(ev.by) then
      local trusted = relayed and officer and ev.by ~= from
      local okRelay
      if trusted then okRelay = true
      elseif ev.by ~= from then okRelay = false
      elseif ev.t == "lv" then okRelay = R.liveLevelOk(ev, t, rdb.rseen[ev.who], sentAt)
      else okRelay = R.liveOk(ev, t, sentAt) end
      if okRelay then
        if R.add(store, ev, t, trusted) then any = true end
      else
        H.refused = (H.refused or 0) + 1
      end
    end
  end
  if type(payload.c) == "string" and type(payload.x) == "string" and relayed and officer
     and R.importClosed(store, payload.c, payload.x, t) then any = true end
  if any then markDirty() end
end

function H.HelloHashes()
  if not rdb then return nil end
  return R.bucketHashes(store)
end

-- a peer's hello: remember it (adoption X/Y) and send up to PAGES_PER_HELLO pages of what differs
-- only members of the guild roster are remembered; a non-officer only sends its OWN observations
-- (anything else would be refused) and never closed races; the item list is built once per hello.
H.REPLY_BACKLOG = 40
function H.OnHello(rh, sender)
  if not rdb then return end
  local from = ns.fullName(sender)
  if not (from and ns.roster(from)) then return end
  rdb.hello[from] = now()
  if type(rh) ~= "table" or not H.Enabled() then return end
  -- ACK + retry: what this peer does not hold yet is sent again live (fresh sentAt), at most once
  -- a minute; acknowledged (its bucket matches ours) or older than 3 h = forgotten
  if type(rdb.pend) == "table" and now() - (H.lastRetry or 0) >= 60 then
    local again = R.ackScan(rdb.pend, store, rh, now())
    if #again > 0 then
      H.lastRetry = now()
      for i = 1, #again, PER_MSG do
        local batch = {}
        for j = i, math.min(#again, i + PER_MSG - 1) do batch[#batch + 1] = again[j] end
        Comm.Send("RO", { o = batch })
      end
    end
  end
  local online = ns.onlineCount and ns.onlineCount() or 1
  local officer = relayerTrusted(ns.me())
  if not officer and math.random() > math.min(1, 4 / math.max(1, online)) then return end
  local me = ns.me()
  ns.After(3 + math.random() * 8, function()
    -- with a backlog already waiting (a whole raid logging in at once) this page is skipped:
    -- it is catch-up only, the peer's next hello / the ACK retry gets it, and the send queue stays bounded
    if Comm.Pending() > H.REPLY_BACKLOG then H.skippedReplies = (H.skippedReplies or 0) + 1; return end
    -- unverified observations are never relayed (an officer page would confirm them)
    local filter = function(it)
      if it.o and it.o.uv then return false end
      return officer or (it.o ~= nil and it.o.by == me)
    end
    local cache = R.itemsOf(store)
    for page = 1, PAGES_PER_HELLO do
      local list, more = R.diffPage(store, rh, page, PAGE, nil, filter, cache)
      local batch = {}
      for _, it in ipairs(list) do
        if it.o then
          batch[#batch + 1] = it.o
          if #batch >= PER_MSG then Comm.Send("RP", { o = batch }, "WHISPER", from); batch = {} end
        elseif it.c then Comm.Send("RP", { c = it.c, x = it.text }, "WHISPER", from) end
      end
      if #batch > 0 then Comm.Send("RP", { o = batch }, "WHISPER", from) end
      if not more then break end
    end
  end)
end

-- adoption: "Guild Squads instalado: X/Y miembros activos"
function H.Adoption()
  local members = {}
  local me = ns.me()
  for name, r in pairs(ns.rosterList and ns.rosterList() or {}) do
    members[#members + 1] = { name = name, days = r.seen or 0, self = name == me }
  end
  return R.adoption(members, rdb and rdb.hello or {}, now())
end

-------------------------------------------------------------------------------
-- toasts + celebrations
local function toast(msg, big)
  if big and RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo.RAID_WARNING then
    if pcall(RaidNotice_AddMessage, RaidWarningFrame, msg, ns.POSITIVE_NOTICE or ChatTypeInfo.RAID_WARNING) then ns.print(msg); return end
  end
  ns.print(msg)
end

-- "has the addon" = we received an addon message from them in the last 15 min (not the persisted
-- hello map, which is empty on a fresh install); "online" = the guild roster.
local ADDON_FRESH = 900
local function hasAddon(n)
  if n == ns.me() then return true end
  local ago = ns.Sync and ns.Sync.HeardAgo and ns.Sync.HeardAgo(n)
  return type(ago) == "number" and ago <= ADDON_FRESH
end
local function isOnline(n) if n == ns.me() then return true end local r = ns.roster(n); return r and r.online end
local function annCtx()
  local users = {}
  for name in pairs(ns.rosterList and ns.rosterList() or {}) do
    if name ~= ns.me() and isOnline(name) and hasAddon(name) then users[#users + 1] = name end
  end
  users[#users + 1] = ns.me()
  return { hasAddon = hasAddon, users = users, online = isOnline,
           rank = function(n) local r = ns.roster(n); return r and r.rank end }
end
function H.Announcer(protagonists) return Cel.announcer(protagonists, annCtx()) end

-- CLAIM before announcing (Core/Celebrate.lua): the preferred announcer claims after 2-6 s; everyone else is a
-- backup that claims after 8-12 s unless it knows the preferred one has the addon. A claim heard first cancels ours;
-- simultaneous claims are resolved by the lowest name. CL travels on the addon channel (never during an encounter).
local claims = Cel.newClaims()
local function clock() return (GetTime and GetTime()) or now() end
local function claimKey(key) return tostring(key):sub(1, 120) end
function H.OnClaim(payload, sender, sentAt)
  if type(payload) ~= "table" or type(payload.k) ~= "string" then return end
  local from = ns.fullName(sender)
  if not (from and ns.roster(from)) then return end
  -- a claim that waited in its sender's queue (BG, instance) is stale and does not count
  if type(sentAt) == "number" and math.abs(now() - sentAt) > Cel.CLAIM_HOLD + 3 then return end
  Cel.noteClaim(claims, claimKey(payload.k), from, clock())
end
function H.Claims() return claims end
-- in a BG / instance we neither claim nor announce (the next candidate does)
local function busy()
  local okI, inInst = call(IsInInstance)
  if okI and inInst then return true end
  local okP, active = false, false
  if C_PvP and type(C_PvP.IsMatchActive) == "function" then okP, active = pcall(C_PvP.IsMatchActive) end
  return okP and active == true
end
local function celebrate(ev, prot)
  local me = ns.me()
  local ck = claimKey(ev.key)
  local cands = Cel.candidates(prot, annCtx())
  Cel.setCandidates(claims, ck, cands)
  local mine
  for i, n in ipairs(cands) do if n == me then mine = i end end
  if not mine then return end                 -- not a candidate: our claim would be ignored anyway
  local tries = 0
  local function try()
    if Cel.claimed(claims, ck) then return end
    if busy() then return end
    if H.InEncounter() or H.ChatLocked() then
      tries = tries + 1
      if tries <= 30 then ns.After(10, try) end
      return
    end
    -- our claim counts from the moment it really leaves the queue (Comm onSent), like the ones we hear
    Comm.Send("CL", { k = ck }, nil, nil, function()   -- urgent (see last argument)
      Cel.noteClaim(claims, ck, me, clock())
      ns.After(Cel.CLAIM_HOLD, function()
        if Cel.claimWinner(claims, ck) == me and not busy() then ev.at = now(); Cel.enqueue(celQ, ev) end
      end)
    end, true)
  end
  ns.After(Cel.claimDelay(mine == 1, math.random()) + (mine > 2 and Cel.BACKUP_DELAY or 0), try)
end

local function protagonists(e)
  if #(e.chars or {}) > 0 and #(e.squads or {}) == 0 then return e.chars end
  local out = {}
  for _, sid in ipairs(e.squads or {}) do for _, n in ipairs(M.members(ns.state, sid)) do out[#out + 1] = n end end
  if #out == 0 then for _, n in ipairs(e.chars or {}) do out[#out + 1] = n end end
  return out
end

function H.RaceTitle(id) return (ns.UI and ns.UI.RaceTitle) and ns.UI.RaceTitle(id) or id end
function H.EntryLabel(e)
  if #(e.squads or {}) > 0 then
    local parts = {}
    for _, sid in ipairs(e.squads) do local r = ns.state.squads[sid]; parts[#parts + 1] = r and r.d.name or "?" end
    return table.concat(parts, " + ")
  end
  if e.mixed then return L.HALL_MIXED end
  return ns.shortName(e.chars and e.chars[1] or e.key)
end

local first = true
afterCompute = function()
  if not rdb then return end
  local t, me, mySid = now(), ns.me(), ns.Actions.MySquadId()
  local s = settings()
  for id, r in pairs(races) do
    for _, e in ipairs(r.entries) do
      local sk = id .. "|" .. e.key
      if not rdb.seen[sk] then
        rdb.seen[sk] = true
        -- a race disabled by the GM keeps counting but is never toasted / celebrated
        local recent = t - (e.ts or 0) < 3600 and not first and not r.off
        local mine = false
        for _, n in ipairs(e.chars or {}) do if n == me and #(e.squads or {}) == 0 then mine = true end end
        for _, sid in ipairs(e.squads or {}) do if sid == mySid then mine = true end end
        if recent and mine then toast(L.HALL_TOAST:format(e.pos, H.RaceTitle(id)), e.pos == 1)
        elseif recent and e.pos == 1 then toast(L.HALL_FIRST_OTHER:format(H.EntryLabel(e), H.RaceTitle(id)), false) end
        if recent then
          local ev = { key = sk, kind = "race", pos = e.pos, what = id }
          if Cel.eligible(ev, s) then
            ev.text = Cel.text(L.CEL_RACE, H.EntryLabel(e), e.pos, H.RaceTitle(id))
            celebrate(ev, protagonists(e))
          end
        end
      end
    end
  end
  -- achievements (squad / char / guild), merged and dated
  local x, y = H.Adoption()
  local got
  got, achProg = R.achievements(races, info, { now = t, squads = squadsMap,
    roleOf = function(n) local p = ns.state.profiles[n]; return p and p.d.role end,
    classOf = function(n) local r = ns.roster(n); return r and r.class end,
    wipeStats = H.WipeStats(), adoption = { x = x, y = y } })
  local new = Pr.mergeAchievements(rdb.ach, got)
  R.retractAchievements(rdb.ach, got)   -- an annulled entry does not keep its achievements
  for _, a in ipairs(new) do
    local mine = (a.scope == "squad" and a.owner == mySid) or (a.scope == "char" and a.owner == me) or a.scope == "guild"
    if mine and not first and t - a.ts < 86400 and not (Cat and not Cat.isOn(a.key)) then
      toast(L.ACH_TOAST:format(L["ACH_" .. a.key] or a.key))
      if a.scope == "squad" then
        local ev = { key = "ach|" .. a.owner .. "|" .. a.key, kind = "ach", what = a.key }
        local sq = ns.state.squads[a.owner]
        if Cel.eligible(ev, s) then
          ev.text = Cel.text(L.CEL_ACH, sq and sq.d.name or "?", L["ACH_" .. a.key] or a.key)
          celebrate(ev, M.members(ns.state, a.owner))
        end
      end
    end
  end
  first = false
end

-- squad wipe stats (Sin fisuras / Constancia) from the closed wipes of the wipe scoring (cached per wipe)
local wsCache = {}
function H.WipeStats()
  local g = ns.ProgressGlue
  if not (g and g.Compute and g.Wipe) then return {} end
  local cur = g.Wipe()
  if wsCache.wipe == cur and wsCache.v then return wsCache.v end
  local results = {}
  for back = Pr.KEEP_SEASONS, 1, -1 do
    local w = Pr.prevWipe(cur, back)
    local okC, res = pcall(g.Compute, w)
    if okC and res then results[#results + 1] = { wipe = w, ends = Pr.wipeEndTs(w), res = res } end
  end
  local cap = settings().weekCap or 100
  wsCache = { wipe = cur, v = R.wipeStats(results, Pr.ranking, Pr.SCORED, cap) }
  return wsCache.v
end

function H.AchProgress() return achProg end
-- + badges granted by the GM (achgrant, on). An achievement earned on its own keeps its own date.
function H.Achievements(scope, owner)
  local t = rdb and rdb.ach and rdb.ach[scope]
  local base = (t and t[owner]) or {}
  local g = Cat and owner and Cat.grantsFor(owner) or {}
  if not next(g) then return base end
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, x in pairs(g) do if not out[k] then out[k] = x.ts end end
  return out
end
function H.GrantOf(owner, key) return Cat and owner and Cat.grantsFor(owner)[key] or nil end

-- celebrations leave one at a time: never in an encounter / chat lockdown / GM off; SendChatMessage guarded
function H.PumpCelebrations()
  local s = settings()
  local blocked = s.celOn ~= true or H.InEncounter() or H.ChatLocked() or (InCombatLockdown and InCombatLockdown() == true)
  local ev = Cel.pump(celQ, now(), blocked)
  if not ev then return nil end
  -- 16001 has C_ChatInfo.SendChatMessage, not the SendChatMessage global
  local sendFn = (ns.apiFn and ns.apiFn("SendChatMessage", "C_ChatInfo.SendChatMessage")) or SendChatMessage
  if type(sendFn) ~= "function" then H.chatError = "SendChatMessage missing"; return nil end
  local okS, err = pcall(sendFn, ev.text, "GUILD")
  if not okS then H.chatError = tostring(err) end
  return okS and ev.text or nil
end
function H.CelQueue() return celQ end

-- GM actions --------------------------------------------------------------
function H.Annul(raceId, key, reason)
  if not P.isGM(ns.roster, ns.me()) then return false, "denied" end
  if type(reason) ~= "string" or reason:gsub("%s", "") == "" then return false, "reason" end
  local okW, why = ns.Actions.WriteRecord("annul", raceId .. "|" .. key, { race = raceId, key = key, reason = reason:sub(1, 80), on = true })
  if okW then markDirty() end
  return okW, why
end
-- unverified observations and their explicit confirmation (GM / officers only)
function H.CanConfirm() return P.isOfficer(ns.roster, ns.me(), settings()) and true or false end
function H.Unverified() return R.unverifiedList(store) end
function H.Confirm(oid)
  if not H.CanConfirm() then return false, "denied" end
  if type(oid) ~= "string" or not store.obs[oid] then return false, "shape" end
  local okW, why = ns.Actions.WriteRecord("vconfirm", oid, { oid = oid })
  if okW then markDirty() end
  return okW, why
end
-- the GM reverts an annulment (same record id, on = false; the reason is kept for the history)
function H.Restore(raceId, key)
  if not P.isGM(ns.roster, ns.me()) then return false, "denied" end
  local cur = ns.state.annuls and ns.state.annuls[raceId .. "|" .. key]
  if not (cur and cur.d and cur.d.on ~= false) then return false, "notAnnulled" end
  local okW, why = ns.Actions.WriteRecord("annul", raceId .. "|" .. key,
    { race = raceId, key = key, reason = cur.d.reason, on = false })
  if okW then markDirty() end
  return okW, why
end
function H.SetFinal(bossId, on)
  if not P.isGM(ns.roster, ns.me()) then return false, "denied" end
  local b = Content.bosses[bossId]
  if not b then return false, "shape" end
  local okW, why = ns.Actions.WriteRecord("boss", bossId, { inst = b.inst, enc = b.enc, name = b.name, kind = b.kind, final = on and true or false })
  if okW then Content.setFinal(bossId, on); markDirty() end
  return okW, why
end

-------------------------------------------------------------------------------
-- the GM's catalog. Everybody sees names / on-off applied; only the GM writes
-- (validated again on every client by Core/Catalog: rank 0, like `settings`; officers cannot).
if Cat then Cat.sizeGuard = function(id, size, sts) return Cat.guardFor(store, races)(id, size, sts) end end
local function gm() return P.isGM(ns.roster, ns.me()) and true or false end
H.IsGM = gm
local function pvpRankHidden(id) return id:find("^pvp%.rank") ~= nil and not H.PvPRankSupported() end
function H.CatalogIds() return Cat.knownIds(H.Races(), nil, pvpRankHidden) end
local function copyT(t) local o = {} for k, v in pairs(t or {}) do o[k] = v end return o end
-- fields: on / size / name (nil name = keep; "" = back to the default name). Keeps the rest of the record.
function H.SetDef(id, fields)
  if not gm() then return false, "denied" end
  local d = copyT(Cat.def(id))
  for k, v in pairs(fields or {}) do d[k] = v end
  if fields and fields.size ~= nil then
    local r = H.Races()[id]
    if r and r.state == "closed" then return false, "catClosed" end
    d.sts = now()
  end
  if fields and fields.name ~= nil then
    d.name = Cat.cleanName(fields.name)
    if d.name == "" then d.name = nil end
  end
  local okW, why = ns.Actions.WriteRecord("achdef", id, d)
  if okW then markDirty() end
  return okW, why
end
function H.SetOn(id, on) return H.SetDef(id, { on = on and true or false }) end
-- bulk "activar / desactivar todo" (group nil = global): the plan (records + estimated seconds) and the write
function H.BulkPlan(group, on)
  local items = Cat.bulk(H.CatalogIds(), group, on and true or false)
  local _, _, recs = ns.Actions.WriteMany("achdef", items, true)
  local secs = (ns.Sync and ns.Sync.EstimateParts) and ns.Sync.EstimateParts(recs) or #items
  return items, secs
end
function H.Bulk(group, on)
  if not gm() then return false, "denied" end
  local items = H.BulkPlan(group, on)
  if #items == 0 then return true, 0 end
  local applied, refused = ns.Actions.WriteMany("achdef", items)
  markDirty()
  return applied > 0, applied, refused
end
-- new custom achievement / race: spec = { metric, param, thr, size, name, scope }
function H.CreateCustom(spec)
  if not gm() then return false, "denied" end
  if type(spec) ~= "table" then return false, "shape" end
  if Cat.countCustom(Cat.defs()) >= Cat.MAX_CUSTOM then return false, "maxCustom" end
  local name = Cat.cleanName(spec.name or "")
  if not name or name == "" then return false, "name" end
  local id = Cat.newId(name)
  local d = { on = true, custom = true, metric = spec.metric, param = spec.param, thr = spec.thr, size = spec.size,
              name = name, scope = spec.scope, sts = spec.metric ~= "manual" and now() or nil }
  if d.metric == "manual" then d.size = nil end
  local okW, why = ns.Actions.WriteRecord("achdef", id, d)
  if okW then markDirty() end
  return okW and id or false, why
end
-- grants (badges only): who = character (char badges) or squad id (squad badges)
function H.Grant(ach, who, reason)
  if not gm() then return false, "denied" end
  if type(reason) ~= "string" or reason:gsub("%s", "") == "" then return false, "reason" end
  local okW, why = ns.Actions.WriteRecord("achgrant", Cat.grantId(ach, who), { ach = ach, who = who, reason = reason:sub(1, 80), on = true })
  if okW then markDirty() end
  return okW, why
end
function H.Ungrant(ach, who, reason)
  if not gm() then return false, "denied" end
  local cur = Cat.grants()[Cat.grantId(ach, who)]
  if not (cur and cur.d and cur.d.on ~= false) then return false, "notGranted" end
  local why = (type(reason) == "string" and reason:gsub("%s", "") ~= "") and reason:sub(1, 80) or cur.d.reason
  local okW, err = ns.Actions.WriteRecord("achgrant", cur.id, { ach = ach, who = who, reason = why, on = false })
  if okW then markDirty() end
  return okW, err
end

function H.ExportText(id)
  local r = H.Race(id)
  if not r then return "" end
  return R.exportText(r, L.TITLE .. " · " .. H.RaceTitle(id), function(e)
    return H.EntryLabel(e) .. " (" .. Pr.formatDate(e.ts) .. ")"
  end)
end

function H.Debug()
  local n = 0
  for _ in pairs(store.obs) do n = n + 1 end
  local c = 0
  for _ in pairs(store.closed) do c = c + 1 end
  return ("hall obs=%d closed=%d chatErr=%s pvpRank=%s"):format(n, c, tostring(H.chatError),
    H.PvPRankSupported() and "ok" or "unsupported")
end

-------------------------------------------------------------------------------
-- persistence + events
local function load(gdb)
  rdb = R.migrate(gdb)
  rdb.sent = type(rdb.sent) == "table" and rdb.sent or {}
  rdb.pend = type(rdb.pend) == "table" and rdb.pend or {}
  for _, ev in pairs(rdb.obs) do R.add(store, ev) end
  store.closed = rdb.closed
  rdb.obs = store.obs
  R.migrateCharState(rdb)   -- sent / hkBase per character
  R.compact(store)
  markDirty()
end

ns.guildHooks = ns.guildHooks or {}
table.insert(ns.guildHooks, load)
-- guild changed in-session: drop this guild's observations (the partition was saved already)
ns.guildUnloadHooks = ns.guildUnloadHooks or {}
table.insert(ns.guildUnloadHooks, function() store = R.newStore(); rdb = nil; markDirty() end)

local samplePending = false
local f = CreateFrame("Frame")
for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_LEVEL_UP", "ENCOUNTER_END", "PVP_MATCH_COMPLETE", "PLAYER_ENTERING_WORLD",
                     "PLAYER_PVP_KILLS_CHANGED", "SKILL_LINES_CHANGED", "UPDATE_FACTION", "PLAYER_LOGOUT", "ENCOUNTER_START" }) do
  pcall(f.RegisterEvent, f, ev)
end
-- one 1 s ticker (C_Timer when present, OnUpdate fallback): celebrations every second, counters
-- every 60 s
local acc = 0
local function hallTick()
  acc = acc + 1
  H.PumpCelebrations()
  if acc >= 60 then acc = 0; H.SampleCounters(); if dirty then H.Races() end end
end
if ns.Every then ns.Every(1, hallTick, f)
else
  local pump = 0
  f:SetScript("OnUpdate", function(_, elapsed)
    pump = pump + (elapsed or 0)
    if pump >= 1 then pump = pump - 1; hallTick() end
  end)
end
f:SetScript("OnEvent", function(_, ev, ...)
  if ev == "ADDON_LOADED" then
    -- data is loaded when the guild is known (GuildSquads.lua selectGuild)
  elseif ev == "PLAYER_LEVEL_UP" then
    local level = ...
    ns.After(1, function() H.OnLevelUp(level) end)
  elseif ev == "ENCOUNTER_START" then
    encounter = true
  elseif ev == "ENCOUNTER_END" then
    encounter = false
    local a, b, c, d, e = ...
    H.OnEncounterEnd(a, b, c, d, e)
  elseif ev == "PVP_MATCH_COMPLETE" then
    H.OnBattleEnd()
  elseif ev == "PLAYER_ENTERING_WORLD" then
    bgDone = false; encounter = false
    ns.After(5, H.SampleCounters)
  elseif ev == "PLAYER_LOGOUT" then
    if rdb then R.compact(store); rdb.obs = store.obs; rdb.closed = store.closed end
  elseif not samplePending then
    -- a burst of UPDATE_FACTION / SKILL_LINES_CHANGED / PLAYER_PVP_KILLS_CHANGED is one sample
    samplePending = true
    ns.After(2, function() samplePending = false; H.SampleCounters() end)
  end
end)

return H
