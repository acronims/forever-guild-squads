-- Guild Squads (MIT) - Progress.lua
-- WoW glue for the rankings: captures PLAYER_LEVEL_UP / ENCOUNTER_END (PvE), battleground results and honorable
-- kills outside instances (PvP), optional Overlord captures (read-only), replicates MetricEvents over the
-- GUILD addon channel (same throttled queue: never during an encounter), computes scores locally (Core/Progress)
-- per wipe and per season, and awards addon achievements. Every client API here is unverified in WoW Forever:
-- existence check + pcall.
local _, ns = ...
local L, M, Pr, Content, Comm = ns.L, ns.Model, ns.Progress, ns.Content, ns.Comm

local G = {}
ns.ProgressGlue = G

local store = Pr.newStore()
local version, cache = 0, {}
local pdb                    -- GuildSquadsDB.progress
local MAX_EVENTS_PER_MSG = 4

local function now() return (GetServerTime and GetServerTime()) or time() end
local function settings() return M.settingsOf(ns.state) end
function G.Enabled() local s = settings(); return s.squadsEnabled and s.compEnabled ~= false end
-- the weekly reset is the WIPE (monthly mode removed from the UI; a legacy "monthly" setting is ignored)
function G.Kind() return "weekly" end
function G.Wipe() return Pr.wipeOf(now()) end
G.Season = G.Wipe -- name, kept for compatibility
function G.Events() return store.events end
function G.Now() return now() end

local function isMemberNow(sid, name) return M.isMember(ns.state, sid, name) end
-- membership rule: closed wipes use the membership snapshot of that wipe
-- one memberAt closure per second instead of one per call
local memberFn, memberAt_t = nil, nil
local function isMember(sid, name, ts)
  if not pdb then return isMemberNow(sid, name) end
  local t = now()
  if not memberFn or memberAt_t ~= t then memberFn, memberAt_t = Pr.memberAt(pdb.snap, isMemberNow, t), t end
  return memberFn(sid, name, ts)
end

-- record the current membership of every squad as the snapshot of the current wipe (the last one before the
-- wipe closes is the membership at close)
local snapSig
local snapAt -- at most one snapshot walk per second (GetTime)
local function snapshotNow()
  if not pdb then return end
  local gt = GetTime and GetTime() or nil
  if gt and snapAt and gt - snapAt < 1 then return end
  snapAt = gt
  local w = G.Wipe()
  local parts = {}
  for sid, r in pairs(ns.state.squads or {}) do
    if not r.d.disbanded then
      local names = M.members(ns.state, sid)
      for _, n in ipairs(M.benchMembers(ns.state, sid)) do names[#names + 1] = n end
      table.sort(names)
      parts[#parts + 1] = sid .. "=" .. table.concat(names, ",")
      Pr.snapshot(pdb.snap, w, sid, names)
    end
  end
  table.sort(parts)
  local sig = w .. "|" .. table.concat(parts, ";")
  if sig ~= snapSig then snapSig = sig; return true end
end

function G.Opts(season)
  local s = settings()
  return { season = season, kind = "weekly", cap = s.weekCap or 100, isMember = isMember,
           weights = { level = s.wLevel or 1, dungeon = s.wDungeon or 1, raid = s.wRaid or 1, pvp = s.wPvp or 1,
                       wpvp = s.wWpvp or 1 } }
end

local function changed() version = version + 1; cache = {} end

local function cacheKey(k)
  local rec = ns.state.settings
  return k .. "#" .. tostring(rec and rec.ts or 0)
end
-- cached score table for a wipe (recomputed when events, settings or memberships change)
function G.Compute(wipe)
  if snapshotNow() then cache = {} end
  wipe = wipe or G.Wipe()
  local key = cacheKey(wipe)
  if wipe ~= G.Wipe() then
    -- a CLOSED wipe is scored with the canonical rule of the wipe summary (its own events +
    -- P.recordMember over the replicated profile/squad records), not with the local membership snapshot
    -- (pdb.snap), so every client shows the same live number as the canonical summary.
    local profiles, squads = ns.state.profiles, ns.state.squads
    local n, mx = 0, 0
    for _, r in pairs(type(profiles) == "table" and profiles or {}) do
      n = n + 1; if type(r) == "table" and type(r.ts) == "number" and r.ts > mx then mx = r.ts end
    end
    for _, r in pairs(type(squads) == "table" and squads or {}) do
      n = n + 1; if type(r) == "table" and type(r.ts) == "number" and r.ts > mx then mx = r.ts end
    end
    key = key .. "#c" .. n .. ":" .. mx
    if not cache[key] then
      local list = Pr.wipeEvents(store.events, wipe, "weekly")
      local o = G.Opts(wipe)
      o.isMember = Pr.recordMember(list, profiles, wipe, squads)
      cache[key] = Pr.compute(list, o)
    end
    return cache[key]
  end
  if not cache[key] then cache[key] = Pr.compute(store.events, G.Opts(wipe)) end
  return cache[key]
end

-- seasons (Temporadas)
function G.SeasonCfg() return Pr.seasonCfg(settings()) end
-- back = 0: current season, 1..n: closed seasons (newest first). Returns season table or nil.
function G.SeasonAt(back)
  local cfg = G.SeasonCfg()
  if (back or 0) == 0 then return cfg.current end
  return cfg.past[back]
end
function G.ComputeSeason(season)
  if snapshotNow() then cache = {} end
  local key = cacheKey("S" .. tostring(season.start) .. ":" .. tostring(season.stop))
  if not cache[key] then
    local o = G.Opts()
    o.computeWipe = function(w) return G.Compute(w) end
    cache[key] = Pr.seasonScore(store.events, season, now(), o)
  end
  return cache[key]
end

function G.GoalProgress()
  return Pr.weekKills(store.events, now(), { isMember = isMember }), settings().guildGoal or 30
end

-------------------------------------------------------------------------------
-- achievements
local achTimer = false
local function toast(msg)
  if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo.RAID_WARNING then
    if pcall(RaidNotice_AddMessage, RaidWarningFrame, msg, ns.POSITIVE_NOTICE or ChatTypeInfo.RAID_WARNING) then ns.print(msg); return end
  end
  ns.print(msg)
end

function G.CheckAchievements(silent)
  if not pdb then return {} end
  local fresh = Pr.achievements(store.events, {
    now = now(), kind = G.Kind(), weights = G.Opts().weights, cap = G.Opts().cap, isMember = isMember,
    seasons = G.SeasonCfg().past,
    members = function(sid) return M.members(ns.state, sid) end,
    levelOf = function(name) local r = ns.roster(name); return r and r.level end,
  })
  local new = Pr.mergeAchievements(pdb.ach, fresh)
  if silent then return new end
  local me, mySid = ns.me(), ns.Actions.MySquadId()
  local shown, t = 0, now()
  for _, a in ipairs(new) do
    local mine = (a.scope == "squad" and a.owner == mySid) or (a.scope == "char" and a.owner == me)
    -- only recent ones (a fresh install may learn old achievements from the guild: no toast storm)
    if mine and t - a.ts < 86400 and shown < 3 then
      shown = shown + 1
      toast(L.ACH_TOAST:format(L["ACH_" .. a.key] or a.key))
    end
  end
  return new
end

local function scheduleAch()
  if achTimer then return end
  achTimer = true
  ns.After(3, function() achTimer = false; G.CheckAchievements(false); if ns.UI and ns.UI.Dirty then ns.UI.Dirty() end end)
end

-- progress towards each squad achievement (tooltips: "3/9 mazmorras", "62/100 HK")
function G.AchievementProgress(sid)
  if not sid then return {} end
  return Pr.achievementProgress(sid, store.events, {
    isMember = isMember,
    members = function(s) return M.members(ns.state, s) end,
    levelOf = function(name) local r = ns.roster(name); return r and r.level end,
  })
end

function G.Achievements(scope, owner)
  local t = pdb and pdb.ach and pdb.ach[scope]
  return (t and t[owner]) or {}
end

-------------------------------------------------------------------------------
-- capture
local function addLocal(ev)
  local okAdd, id = Pr.add(store, ev)
  if not okAdd then return false, id end
  changed()
  local clean = store.events[id]
  -- small delay; Comm's queue also holds everything while an encounter / lockdown is active
  ns.After(1 + math.random() * 3, function() Comm.Send("E", { e = { clean } }, nil, nil, nil, true) end)
  scheduleAch()
  if ns.UI and ns.UI.Dirty then ns.UI.Dirty() end
  return true, id
end

function G.OnLevelUp(level)
  if not (G.Enabled() and type(level) == "number") then return end
  local sid = ns.Actions.MySquadId()
  if not sid then return end
  return addLocal({ t = "level", who = ns.me(), ts = now(), sid = sid, lv = level })
end

-- names of everyone in my party/raid (full names)
local function groupNames()
  local out = {}
  local inRaid = IsInRaid and select(2, pcall(IsInRaid)) == true
  if inRaid and GetRaidRosterInfo and GetNumGroupMembers then
    local okN, n = pcall(GetNumGroupMembers)
    for i = 1, (okN and type(n) == "number") and math.min(n, 40) or 0 do
      local okR, name = pcall(GetRaidRosterInfo, i)
      if okR and type(name) == "string" then out[ns.charKey(name)] = true end
    end
  elseif UnitName then
    for i = 1, 4 do
      local okU, name, realm = pcall(UnitName, "party" .. i)
      -- party names can be secret in restricted instances; skip them instead of comparing
      if okU and issecretvalue and (issecretvalue(name) or issecretvalue(realm)) then okU = false end
      if okU and type(name) == "string" then
        out[ns.fullName((realm and realm ~= "") and (name .. "-" .. realm) or name)] = true
      end
    end
  end
  return out
end

local function inGroup(name, set)
  if set[name] then return true end
  local short = ns.shortName(name)
  local fns = { UnitInRaid or false, UnitInParty or false }
  for i = 1, 2 do
    local fn = fns[i]
    if fn then local okF, v = pcall(fn, short); if okF and v then return true end end
  end
  return false
end

function G.OnEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
  if success ~= 1 and success ~= true then return end
  if not G.Enabled() or not GetInstanceInfo then return end
  local okI, instName, instType, diff, _, _, _, _, instanceID = pcall(GetInstanceInfo)
  if not okI or (instType ~= "party" and instType ~= "raid") then return end
  local sid = ns.Actions.MySquadId()
  if not sid then return end
  local me, set, pres = ns.me(), groupNames(), {}
  local names = M.members(ns.state, sid)
  for _, n in ipairs(M.benchMembers(ns.state, sid)) do names[#names + 1] = n end
  for _, n in ipairs(names) do if n ~= me and inGroup(n, set) then pres[#pres + 1] = n end end
  local entry = Content.match(instName, instType, instanceID)
  if pdb then pdb.learned = Content.learned end
  return addLocal({ t = "boss", who = me, ts = now(), sid = sid, inst = type(instName) == "string" and instName or entry.name,
                    iid = type(instanceID) == "number" and instanceID or nil, it = instType,
                    diff = type(difficultyID) == "number" and difficultyID or (type(diff) == "number" and diff or nil),
                    enc = type(encounterID) == "number" and encounterID or nil,
                    boss = type(encounterName) == "string" and encounterName or nil,
                    gs = type(groupSize) == "number" and groupSize or nil, pres = pres })
end

-------------------------------------------------------------------------------
-- PvP: battleground result (witnessed like bosses) and honorable kills outside instances
local bgDone = false -- one report per match; reset when zoning
local function call(fn, ...) if type(fn) ~= "function" then return false end return pcall(fn, ...) end

local function inInstance()
  local okI, inside, kind = call(IsInInstance)
  if okI then return inside and true or false, kind end
  return false, nil
end

function G.BgWinner()
  if C_PvP and type(C_PvP.GetActiveMatchWinner) == "function" then
    local okW, w = pcall(C_PvP.GetActiveMatchWinner)
    if okW and type(w) == "number" then return w end
  end
  local okW, w = call(GetBattlefieldWinner)
  if okW and type(w) == "number" then return w end
  return nil
end

function G.OnBattleEnd(source)
  if bgDone or not G.Enabled() then return end
  local winner = G.BgWinner()
  local okF, faction = call(UnitFactionGroup, "player")
  local win = Pr.bgOutcome(winner, okF and faction or nil)
  if ns.DiagGlue then ns.DiagGlue.Bg(("%s winner=%s faction=%s -> %s"):format(tostring(source), tostring(winner),
    tostring(okF and faction), tostring(win))) end
  if win == nil then return end
  bgDone = true
  local sid = ns.Actions.MySquadId()
  if not sid then return end
  local okI, instName = call(GetInstanceInfo)
  local me, set, pres = ns.me(), groupNames(), {}
  for _, n in ipairs(M.members(ns.state, sid)) do if n ~= me and inGroup(n, set) then pres[#pres + 1] = n end end
  return addLocal({ t = "bg", who = me, ts = now(), sid = sid, inst = (okI and type(instName) == "string") and instName or "?",
                    win = win, pres = pres })
end

-- lifetime HK (fallback: session HK) ; returns number or nil
function G.ReadHK()
  local okL, hk = call(GetPVPLifetimeStats)
  if okL and type(hk) == "number" then return hk, "lifetime" end
  local okS, shk = call(GetPVPSessionStats)
  if okS and type(shk) == "number" then return shk, "session" end
  return nil
end

-- Overlord (optional): present? enabled by the GM? Read-only, never mutates Overlord.
function G.Overlord() return rawget(_G, "Overlord") end
function G.OverlordPresent()
  local ov = G.Overlord()
  return type(ov) == "table" and type(ov.Leaderboard) == "table"
end
function G.OverlordEnabled() return settings().overlordOn ~= false end
function G.OverlordHint()
  if settings().ovHint == false then return false end -- the GM can switch the recommendation off
  return Pr.overlordHint(G.OverlordPresent(), G.OverlordEnabled(), GuildSquadsDB and GuildSquadsDB.hideOverlordHint)
end
function G.DismissOverlordHint()
  GuildSquadsDB = GuildSquadsDB or {}
  GuildSquadsDB.hideOverlordHint = true
end

local FLUSH_EVERY = 300
local lastFlush = 0
local function flushPending(force)
  if not pdb or not G.Enabled() then return end
  local t = now()
  if not force and t - lastFlush < FLUSH_EVERY then return end
  lastFlush = t
  -- pending counters belong to one character; before the roster nothing is decided
  if pdb.pending.who and pdb.pending.who ~= ns.me() then pdb.pending.hk, pdb.pending.cap = 0, 0 end
  pdb.pending.who = ns.me()
  if not ns.rosterReady then lastFlush = 0; return end
  local sid = ns.Actions.MySquadId()
  if not sid then pdb.pending.hk, pdb.pending.cap = 0, 0; return end
  for _, kind in ipairs({ "hk", "cap" }) do
    local n = pdb.pending[kind] or 0
    local mx = kind == "hk" and Pr.MAX_HK_PER_EVENT or Pr.MAX_CAP_PER_EVENT
    if n >= 1 then
      n = math.min(n, mx)
      pdb.pending[kind] = 0
      addLocal({ t = kind, who = ns.me(), ts = t, sid = sid, n = n })
    end
  end
end

-- sample counters: on PvP-related events, zoning and every 60 s
function G.SampleCounters(reason)
  if not pdb then return end
  local inside = inInstance()
  local hk, src = G.ReadHK()
  if hk then
    local d
    d, pdb.hkState = Pr.counterStep(pdb.hkState, ns.me() .. ":" .. src, hk, inside)
    if d > 0 then pdb.pending.hk = (pdb.pending.hk or 0) + d end
    if ns.DiagGlue then ns.DiagGlue.HK(("%s=%d inInstance=%s delta=%d pending=%d (%s)"):format(src, hk, tostring(inside), d,
      pdb.pending.hk or 0, tostring(reason))) end
  end
  if G.OverlordPresent() and G.OverlordEnabled() then
    local okN, short = call(UnitName, "player")
    local caps = Pr.overlordCaptures(G.Overlord(), okN and short or ns.me())
    if caps then
      local d
      d, pdb.ovState = Pr.counterStep(pdb.ovState, ns.me(), caps, false, Pr.MAX_CAP_PER_EVENT)
      if d > 0 then pdb.pending.cap = (pdb.pending.cap or 0) + d end
    end
    if ns.DiagGlue then ns.DiagGlue.Overlord("present, captures=" .. tostring(caps)) end
  elseif ns.DiagGlue then
    ns.DiagGlue.Overlord(G.OverlordPresent() and "present, disabled by GM" or "not installed")
  end
  flushPending(false)
end

-------------------------------------------------------------------------------
-- replication: each client only accepts events reported by their own author (sender == who)
-- relay rule: events come from their author (live) or are relayed by a GM/officer
local function trustedRelayer(name)
  local P = ns.Permissions
  return P and P.isOfficer(ns.roster, name, M.settingsOf(ns.state)) or false
end
G.trustedRelayer = trustedRelayer

G.FUTURE_RETRY = 1800
function G.OnEvents(payload, sender)
  if type(payload) ~= "table" or type(payload.e) ~= "table" then return end
  local from = ns.fullName(sender)
  local relayOK = trustedRelayer(from)
  local any = false
  for i = 1, math.min(#payload.e, 20) do
    local ev = Pr.sanitize(payload.e[i])
    if ev and (ev.who == from or relayOK) then
      local author = ev.who
      local accept = ev.ts <= now() + 300                -- no far-future events
      if ev.t == "level" then
        local r = ns.roster(author)
        -- old events (backfill): only levels ABOVE the last level we knew for that character
        local known = pdb and pdb.lvKnown and pdb.lvKnown[author]
        accept = accept and r ~= nil and (Pr.acceptLevel(ev, r.level) or (now() - ev.ts > 3600 and type(r.level) == "number"
                 and ev.lv <= r.level and known ~= nil and ev.lv > known))
        if pdb and pdb.lvKnown and type(r and r.level) == "number" then pdb.lvKnown[author] = math.max(known or 0, r.level) end
      end
      if accept and Pr.add(store, ev) then any = true
      elseif ev.ts > now() + 300 and ev.ts <= now() + G.FUTURE_RETRY then
        -- a peer whose clock runs ahead of ours (two clocks +-200 s apart) is not lost:
        -- the event is offered again once it is not in the future any more (without waiting for a hello)
        local p1 = { e = { payload.e[i] } }
        ns.After(ev.ts - now() - 300 + 2, function() G.OnEvents(p1, sender) end)
      end
    end
  end
  if any then changed(); scheduleAch(); if ns.UI and ns.UI.Dirty then ns.UI.Dirty() end end
end

local function seasonsWanted()
  local cur = G.Season()
  return { [cur] = true, [Pr.prevSeason(cur)] = true }
end

local function myEvents()
  local me, want, out = ns.me(), seasonsWanted(), {}
  for _, ev in pairs(store.events) do
    if ev.who == me and want[Pr.seasonOf(ev.ts, G.Kind())] then out[#out + 1] = ev end
  end
  table.sort(out, function(a, b) return a.ts < b.ts end)
  return out
end

-- counts per author for the current + previous season, sent inside the sync "hello"
function G.HelloCounts()
  -- full counts, then at most 60 authors (sorted, deterministic); "~t" marks a truncated list
  local want, all = seasonsWanted(), {}
  for _, ev in pairs(store.events) do
    if ev.who and want[Pr.seasonOf(ev.ts, G.Kind())] then all[ev.who] = (all[ev.who] or 0) + 1 end
  end
  local names = {}
  for n in pairs(all) do names[#names + 1] = n end
  table.sort(names)
  local out = {}
  local me = ns.me and ns.me()
  if me and all[me] then out[me] = all[me] end
  for i = 1, #names do
    if not out[names[i]] then
      if #names > 60 and i > 59 then out["~t"] = 1; break end
      out[names[i]] = all[names[i]]
    end
  end
  return out
end

-- a peer has fewer of my events than I do: whisper mine to it (only my own, after jitter)
-- a truncated count list never triggers a reply for missing authors, one reply per peer every
-- 10 minutes, wider jitter
local lastReplyTo = {}
function G.OnHello(ec, sender)
  if type(ec) ~= "table" or not G.Enabled() then return end
  local mine = myEvents()
  local theirs = tonumber(ec[ns.me()])
  local own = #mine
  if theirs ~= nil or not ec["~t"] then
    if (theirs or 0) >= own then mine = {} end
  else mine = {} end
  local to = ns.fullName(sender)
  -- a GM/officer also relays the events of other authors the peer lacks (trusted relay, max 60)
  if trustedRelayer(ns.me()) then
    local want, by = seasonsWanted(), {}
    for _, ev in pairs(store.events) do
      if ev.who and ev.who ~= ns.me() and ev.t ~= "sum" and want[Pr.seasonOf(ev.ts, G.Kind())] then
        by[ev.who] = by[ev.who] or {}
        table.insert(by[ev.who], ev)
      end
    end
    local extra = {}
    for who, list in pairs(by) do
      local theirsW = tonumber(ec[who])
      if not (theirsW == nil and ec["~t"]) and (theirsW or 0) < #list then
        for _, ev in ipairs(list) do if #extra < 60 then extra[#extra + 1] = ev end end
      end
    end
    for _, ev in ipairs(extra) do mine[#mine + 1] = ev end
  end
  if #mine == 0 then return end
  local t = now()
  if lastReplyTo[to] and t - lastReplyTo[to] < 600 then return end
  lastReplyTo[to] = t
  ns.After(2 + math.random() * 18, function()
    local batch = {}
    for i = math.max(1, #mine - 119), #mine do
      batch[#batch + 1] = mine[i]
      if #batch >= MAX_EVENTS_PER_MSG then Comm.Send("E", { e = batch }, "WHISPER", to); batch = {} end
    end
    if #batch > 0 then Comm.Send("E", { e = batch }, "WHISPER", to) end
  end)
end

-------------------------------------------------------------------------------
-- replicable wipe summaries. The hello carries "hash:n" of the newest summarised wipes; when
-- two clients disagree, the one with fewer events of that wipe asks the one with more ("SQ") and takes its summary
-- ("SR") if it comes from a GM/officer (derived data is only relayed by trusted ranks) and re-hashes the same.
G.SUM_ANNOUNCE = 8
function G.HelloSummaries()
  local wipes = {}
  for _, ev in pairs(store.events) do if ev.t == "sum" and not wipes[ev.wipe] then wipes[ev.wipe] = true end end
  local list = {}
  for w in pairs(wipes) do list[#list + 1] = w end
  table.sort(list, function(a, b)
    local _, x = Pr.parseSeason(a); local _, y = Pr.parseSeason(b)
    if x and y and x ~= y then return x > y end
    return a > b
  end)
  local out, any = {}, false
  for i = 1, math.min(#list, G.SUM_ANNOUNCE) do
    local m = Pr.storedSummary(store.events, list[i])
    if m then out[list[i]] = m.hash .. ":" .. m.n; any = true end
  end
  return any and out or nil
end
local asked = {}
function G.OnSummaries(ws, sender)
  if type(ws) ~= "table" or not G.Enabled() then return end
  local from = ns.fullName(sender)
  if not (from and trustedRelayer(from)) then return end
  local n = 0
  for w, v in pairs(ws) do
    if type(w) == "string" and type(v) == "string" and n < 2 then
      local h, cnt = v:match("^([%w%-]+):(%d+)$")
      local mine = Pr.storedSummary(store.events, w)
      local key = from .. "|" .. w .. "|" .. tostring(h)
      if h and (mine or #Pr.wipeEvents(store.events, w) == 0) and Pr.peerSummaryWins(mine, tonumber(cnt), h)
         and not asked[key] then
        asked[key] = true; n = n + 1
        Comm.Send("SQ", { w = w }, "WHISPER", from)
      end
    end
  end
end
local sqGate = {}
function G.OnSummaryRequest(payload, sender)
  if type(payload) ~= "table" or type(payload.w) ~= "string" or not G.Enabled() then return end
  local from = ns.fullName(sender)
  if not (from and ns.roster(from)) then return end
  local m = Pr.storedSummary(store.events, payload.w)
  -- <= 1 SQ / 30 s per sender, and never the same summary twice to the same requester
  if m and Pr.sqGate(sqGate, from, payload.w, m.hash, now()) then
    Comm.Send("SR", { w = payload.w, n = m.n, s = m.sums }, "WHISPER", from)
  end
end
local function cleanSums(s)
  if type(s) ~= "table" then return nil end
  local out, count = {}, 0
  for sid, r in pairs(s) do
    if type(sid) ~= "string" or #sid > 80 or type(r) ~= "table" then return nil end
    count = count + 1
    if count > 200 then return nil end
    local keep = { capped = {} }
    for _, f in ipairs(Pr.SUM_FIELDS) do
      local v = r[f]
      if v ~= nil and (type(v) ~= "number" or v ~= v or v < 0 or v > 1000000) then return nil end
      keep[f] = v
    end
    for c, on in pairs(type(r.capped) == "table" and r.capped or {}) do
      if type(c) == "string" and on == true then keep.capped[c] = true end
    end
    out[sid] = keep
  end
  return out
end
function G.OnSummary(payload, sender)
  if type(payload) ~= "table" or type(payload.w) ~= "string" or type(payload.n) ~= "number" then return end
  local from = ns.fullName(sender)
  if not (from and trustedRelayer(from)) then return end
  local sums = cleanSums(payload.s)
  if not sums or not Pr.parseSeason(payload.w) then return end
  local mine = Pr.storedSummary(store.events, payload.w)
  if not (mine or #Pr.wipeEvents(store.events, payload.w) == 0) then return end
  if not Pr.peerSummaryWins(mine, payload.n, Pr.summaryHash(sums)) then return end
  Pr.setSummary(store, payload.w, sums, math.floor(payload.n))
  pdb.events = store.events
  changed()
end

-------------------------------------------------------------------------------
-- persistence + events
local function load(gdb)
  -- align wipes with the client's weekly reset when the API exists (else Wednesday 09:00 CET)
  if C_DateAndTime and type(C_DateAndTime.GetSecondsUntilWeeklyReset) == "function" then
    local okR, secs = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
    if okR then Pr.SHIFT = Pr.weeklyShift(now(), secs) end
  end
  gdb.progress = type(gdb.progress) == "table" and gdb.progress or {}
  pdb = gdb.progress
  pdb.events = pdb.events or {}
  pdb.ach = pdb.ach or { squad = {}, char = {} }
  pdb.learned = pdb.learned or {}
  pdb.snap = pdb.snap or {}          -- membership per wipe
  pdb.pending = pdb.pending or { hk = 0, cap = 0 }
  for id, key in pairs(pdb.learned) do Content.learnId(id, key) end
  pdb.learned = Content.learned
  pdb.lvKnown = type(pdb.lvKnown) == "table" and pdb.lvKnown or {}
  for id, ev in pairs(pdb.events) do
    if Pr.isSummary(ev) then store.events[id] = ev else Pr.add(store, ev) end   -- wipe summaries
  end
  local o = G.Opts(); o.profiles = ns.state.profiles   -- wipe summaries use the profile records
  o.squads = ns.state.squads                            -- and the squad records (captain's consent)
  Pr.prune(store, G.Season(), G.Kind(), o)
  pdb.events = store.events
  changed()
end

ns.guildHooks = ns.guildHooks or {}
table.insert(ns.guildHooks, load)
-- guild changed in-session: drop this guild's store (the partition was saved by GuildSquads.lua)
ns.guildUnloadHooks = ns.guildUnloadHooks or {}
table.insert(ns.guildUnloadHooks, function() store = Pr.newStore(); pdb = nil; changed() end)

local f = CreateFrame("Frame")
for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_LEVEL_UP", "ENCOUNTER_END", "PVP_MATCH_COMPLETE", "UPDATE_BATTLEFIELD_SCORE",
                     "PLAYER_ENTERING_WORLD", "PLAYER_PVP_KILLS_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_LOGOUT" }) do
  pcall(f.RegisterEvent, f, ev)
end
-- 60 s sampling on a C_Timer ticker (OnUpdate fallback)
if ns.Every then ns.Every(60, function() G.SampleCounters("timer") end, f)
else
  local sampleAcc = 0
  f:SetScript("OnUpdate", function(_, elapsed)
    sampleAcc = sampleAcc + (elapsed or 0)
    if sampleAcc >= 60 then sampleAcc = 0; G.SampleCounters("timer") end
  end)
end
local hkPending = false
f:SetScript("OnEvent", function(_, ev, ...)
  if ev == "ADDON_LOADED" then
    -- data is loaded when the guild is known (GuildSquads.lua selectGuild)
  elseif ev == "PVP_MATCH_COMPLETE" then
    G.OnBattleEnd(ev)
  elseif ev == "UPDATE_BATTLEFIELD_SCORE" then
    local _, kind = inInstance()
    if kind == "pvp" and G.BgWinner() ~= nil then G.OnBattleEnd(ev) end
  elseif ev == "PLAYER_ENTERING_WORLD" or ev == "ZONE_CHANGED_NEW_AREA" then
    if ev == "PLAYER_ENTERING_WORLD" then bgDone = false end
    G.SampleCounters(ev)
  elseif ev == "PLAYER_PVP_KILLS_CHANGED" then
    -- one sample per burst (~2 s debounce), not one per kill
    if not hkPending then
      hkPending = true
      ns.After(2, function() hkPending = false; G.SampleCounters(ev) end)
    end
  elseif ev == "PLAYER_LOGOUT" then
    -- a HK made < 2 s before logging out is sampled now (not in the next wipe)
    if hkPending then hkPending = false; G.SampleCounters("logout") end
  elseif ev == "PLAYER_LEVEL_UP" then
    local level = ...
    ns.After(1, function() G.OnLevelUp(level) end)
  elseif ev == "ENCOUNTER_END" then
    local a, b, c, d, e = ...
    G.OnEncounterEnd(a, b, c, d, e)
  end
end)

function G.FlushNow() flushPending(true) end

function G.Debug()
  local n = 0
  for _ in pairs(store.events) do n = n + 1 end
  return ("events=%d wipe=%s v=%d"):format(n, G.Wipe(), version)
end

return G
