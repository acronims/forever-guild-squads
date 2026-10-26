-- Guild Squads (MIT) - Raids.lua
-- WoW glue of the raid rosters (Core/Roster.lua is the pure part): signed writes, RSVP, the one-click invite
-- (C_PartyInfo.InviteUnit / ConvertToRaid / SetRaidSubgroup, every API guarded, only on a user click and never in
-- combat), attendance seen through GROUP_ROSTER_UPDATE on the RL / GM clients, auto-close 3 h after the start,
-- weekly copies of repeating rosters, the in-addon reminder 1 h before and the tab badge.
-- Writes go through the normal record queue, which holds everything while an encounter is running.
local _, ns = ...
local L, M, P, R = ns.L, ns.Model, ns.Permissions, ns.Roster

local G = {}
ns.RaidGlue = G

local function me() return ns.me and ns.me() or "?" end
local function settings() return M.settingsOf(ns.state) end
local function now() return (GetServerTime and GetServerTime()) or time() end
local function offsetAt(ts) return (ns.Progress and ns.Progress.realmOffset) and ns.Progress.realmOffset(ts) or 0 end
function G.WallNow() local t = now(); return t + offsetAt(t) end
function G.ToEpoch(wall) return R.wallToEpoch(wall, offsetAt) end

local function apiTrue(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok, v = pcall(fn, ...)
  return ok and v and true or false
end

function G.roleOf(name)
  local p = ns.state.profiles[name]
  return p and p.d.role or nil
end
function G.classOf(name)
  local r = ns.roster and ns.roster(name)
  if r and r.class then return r.class end
  local p = ns.state.profiles[name]
  return p and p.d.class or nil
end
function G.Util() return R.utilTable(settings()) end
function G.CanLead() return ns.rosterReady and R.canLead(ns.roster, me(), settings()) or false end
function G.Get(rid) return ns.state.rosters and ns.state.rosters[rid] or nil end
function G.CanEdit(rid)
  local r = G.Get(rid)
  if not r then return G.CanLead() end
  return R.canEdit(ns.roster, me(), r.d, settings())
end

local function write(kind, id, data)
  if not (ns.Actions and ns.Actions.WriteRecord) then return false, "denied" end
  return ns.Actions.WriteRecord(kind, id, data)
end
local function feedback(ok, text) if ns.Feedback then ns.Feedback(ok, text) end end

-- create a draft. f = { raid, size, name, at, wk, tpl }
function G.Create(f)
  if not G.CanLead() then return nil, "denied" end
  local d = R.new(f)
  d.owner = me()
  local id = me() .. ":" .. now()
  if G.Get(id) then id = id .. "b" end
  local ok, why = write("roster", id, d)
  feedback(ok, L.RB_FB_CREATED:format(d.name))
  return ok and id or nil, why
end

function G.Save(rid, d)
  local ok, why = write("roster", rid, d)
  return ok, why
end

local function setState(rid, st)
  local r = G.Get(rid)
  if not r then return false, "denied" end
  local d = R.copy(r.d)
  d.st = st
  return write("roster", rid, d)
end

function G.Publish(rid, d)
  if d then local okS, why = G.Save(rid, d); if not okS then return false, why end end
  local ok, why = setState(rid, "published")
  feedback(ok, L.RB_FB_PUBLISHED)
  return ok, why
end
function G.Cancel(rid)
  local ok, why = setState(rid, "cancelled")
  feedback(ok, L.RB_FB_CANCELLED)
  return ok, why
end

-- attendance seen on this client during the window (per guild, persisted)
local function seenDB()
  local g = ns.gdb
  if not g then return {} end
  g.raidSeen = type(g.raidSeen) == "table" and g.raidSeen or {}
  return g.raidSeen
end
function G.Seen(rid)
  local s = seenDB()[rid]
  local out = {}
  for n in pairs(type(s) == "table" and s or {}) do out[#out + 1] = n end
  table.sort(out)
  return out
end

-- closing and signing the attendance are separate. Close = state "closed"; the attendance
-- is signed only when this client SAW the raid (never an empty list). With nothing seen the roster stays
-- "closed - attendance pending" and the RL / GM sign or correct it within 7 days (G.SignAttendance).
function G.Close(rid)
  local r = G.Get(rid)
  if not r then return false, "denied" end
  local ok, why = setState(rid, "closed")
  if ok then
    local names = G.Seen(rid)
    if #names > 0 then
      G.SignAttendance(rid, names)
      seenDB()[rid] = nil
      feedback(true, L.RB_FB_CLOSED:format(#names))
    else
      feedback(true, L.RB_FB_CLOSED_PENDING)
    end
  end
  return ok, why
end

-- sign (or correct) the official attendance: RL / GM, closed roster, within 7 days. Bounded to the roster's
-- listed players first, then the others (size + bench names at most).
function G.SignAttendance(rid, names)
  local r = G.Get(rid)
  if not r or not G.CanEdit(rid) or not R.canFixAttendance(ns.state, rid, now()) then return false, "denied" end
  local listed, others = {}, {}
  for _, n in ipairs(R.cleanNames(names, ns.roster)) do
    if R.where(r.d, n) then listed[#listed + 1] = n else others[#others + 1] = n end
  end
  for _, n in ipairs(others) do listed[#listed + 1] = n end
  local max = (r.d.size or 10) + R.MAX_BENCH
  while #listed > max do table.remove(listed) end
  if #listed == 0 then return false, "empty" end
  return write("attendance", rid, { rid = rid, names = listed, at = r.d.at })
end

function G.CanFixAttendance(rid) return G.CanEdit(rid) and R.canFixAttendance(ns.state, rid, now()) end

-- after the close, what this client saw is not lost: the RL / GM add it to the official record (union with
-- what is already signed), any other member who was there signs a witness report (counts from 2 witnesses)
function G.ReportSeen()
  local db = seenDB()
  local mine = me()
  for rid in pairs(db) do
    local r = G.Get(rid)
    local keep = false
    if r and r.d.st ~= "published" then
      local names = G.Seen(rid)
      if r.d.st == "closed" and #names > 0 and R.canFixAttendance(ns.state, rid, now()) then
        if G.CanEdit(rid) then
          local a = ns.state.attendance and ns.state.attendance[rid]
          for _, n in ipairs(a and a.d.names or {}) do names[#names + 1] = n end
          -- what this client saw is forgotten only once the signature is accepted
          if not G.SignAttendance(rid, names) then keep = true end
        else
          local self = false
          for _, n in ipairs(names) do if n == mine then self = true end end
          if self then
            -- cut by relevance, not alphabetically: the witness first, then the players
            -- listed in the roster, then the rest. The report is forgotten only once it is written.
            local list = { mine }
            for _, n in ipairs(names) do if n ~= mine and R.where(r.d, n) then list[#list + 1] = n end end
            for _, n in ipairs(names) do if n ~= mine and not R.where(r.d, n) then list[#list + 1] = n end end
            local max = (r.d.size or 10) + R.MAX_BENCH
            while #list > max do table.remove(list) end
            if not write("witness", R.witnessId(rid, mine), { rid = rid, names = list }) then keep = true end
          end
        end
      end
      if not keep then db[rid] = nil end
    end
  end
end

function G.Duplicate(rid)
  local r = G.Get(rid)
  if not r or not G.CanLead() then return nil, "denied" end
  local d = R.duplicate(r.d, rid, G.WallNow())   -- the first weekly date after now
  d.owner = me()
  local id = me() .. ":" .. now() .. ":" .. (ns.gdb and #R.list(ns.state) or 0)
  local ok, why = write("roster", id, d)
  feedback(ok, L.RB_FB_DUPLICATED:format(R.fmtWall(d.at)))
  return ok and id or nil, why
end

function G.Answer(rid, v, comment)
  if not R.isAnswer(v) then return false, "shape" end
  local name = me()
  if comment == nil then   -- answering from the card keeps the comment already written
    local prev = R.rsvpOf(ns.state, rid, name)
    comment = prev and prev.c or ""
  end
  local ok, why = write("rsvp", R.rsvpId(rid, name), { rid = rid, name = name, v = v, c = comment:sub(1, R.MAX_COMMENT) })
  feedback(ok, L.RB_FB_ANSWER:format(L["RB_ANS_" .. v] or v))
  if ok and ns.UpdateBadge then pcall(ns.UpdateBadge) end
  return ok, why
end

-------------------------------------------------------------------------------
-- group API adapter for R.invite (every call guarded; missing APIs are simply absent)
local function short(n) return (type(n) == "string" and n:match("^([^-]+)")) or n end
function G.GroupAPI()
  local api = {}
  api.now = function() return (type(GetTime) == "function" and GetTime()) or now() end
  -- alone, leader or assistant; unknown API -> allowed (the server decides)
  api.canInvite = function()
    if not (apiTrue(IsInGroup) or apiTrue(IsInRaid)) then return true end
    if type(UnitIsGroupLeader) ~= "function" then return true end
    return apiTrue(UnitIsGroupLeader, "player") or apiTrue(UnitIsGroupAssistant, "player")
  end
  api.inCombat = function()
    return apiTrue(InCombatLockdown) or apiTrue(((ns.encounterFn and ns.encounterFn()) or IsEncounterInProgress))
  end
  local inviteFn = (C_PartyInfo and type(C_PartyInfo.InviteUnit) == "function" and C_PartyInfo.InviteUnit) or
                   (type(InviteUnit) == "function" and InviteUnit) or nil
  if inviteFn then api.invite = function(n) inviteFn(n) end end
  api.isRaid = function() return apiTrue(IsInRaid) end
  api.groupSize = function()
    if type(GetNumGroupMembers) ~= "function" then return 1 end
    local ok, n = pcall(GetNumGroupMembers)
    return (ok and type(n) == "number" and n > 0) and n or 1
  end
  api.inGroup = function(n)
    return apiTrue(UnitInRaid, short(n)) or apiTrue(UnitInParty, short(n)) or apiTrue(UnitInRaid, n) or apiTrue(UnitInParty, n)
  end
  local convert = (C_PartyInfo and type(C_PartyInfo.ConvertToRaid) == "function" and C_PartyInfo.ConvertToRaid) or
                  (type(ConvertToRaid) == "function" and ConvertToRaid) or nil
  if convert then api.convert = function() convert() end end
  if type(GetRaidRosterInfo) == "function" and type(GetNumGroupMembers) == "function" then
    api.members = function()
      local out = {}
      local okN, n = pcall(GetNumGroupMembers)
      for i = 1, (okN and tonumber(n)) or 0 do
        local ok, name, _, sub = pcall(GetRaidRosterInfo, i)
        if ok and type(name) == "string" then out[#out + 1] = { name = ns.charKey(name), index = i, sub = tonumber(sub) or 1 } end
      end
      return out
    end
  end
  if type(SetRaidSubgroup) == "function" then api.setSub = function(i, g) SetRaidSubgroup(i, g) end end
  if type(SwapRaidSubgroup) == "function" then api.swapSub = function(a, b) SwapRaidSubgroup(a, b) end end
  return api
end

-- confirmed players that are online right now
function G.ConfirmedOnline(rid)
  local out = {}
  for _, n in ipairs(R.confirmed(ns.state, rid)) do
    local r = ns.roster and ns.roster(n)
    if r and r.online then out[#out + 1] = n end
  end
  return out
end

-- ONLY from a button click (hardware event). One batch per click.
function G.Invite(rid)
  local r = G.Get(rid)
  if not r then return nil end
  local res = R.invite(G.GroupAPI(), r.d, G.ConfirmedOnline(rid), me())
  if res.reason == "combat" then ns.print(L.IN_COMBAT); return res end
  if res.reason == "noInvite" then ns.print(L.FB_NO_INVITE_API); return res end
  if res.reason == "notLeader" then feedback(false, L.RB_NOT_LEADER); return res end
  local parts = { L.RB_FB_INVITED:format(res.invited, res.remaining) }
  if res.noConvert then parts[#parts + 1] = L.RB_NO_CONVERT end
  if res.converted then parts[#parts + 1] = L.RB_CONVERTED end
  if res.sub == "missing" or res.sub == "failed" then parts[#parts + 1] = L.RB_NO_SUBGROUP end
  if res.remaining > 0 then parts[#parts + 1] = L.RB_CLICK_AGAIN end
  feedback(true, table.concat(parts, " "))
  return res
end

function G.ExportText(rid)
  return R.exportText(ns.state, rid, G.roleOf, { group = "G", bench = L.RB_BENCH, attendance = L.RB_ATTENDANCE,
                                                 custom = L.RB_CUSTOM })
end

-------------------------------------------------------------------------------
-- badge: published rosters where I am listed and have not answered
function G.PendingCount()
  if not ns.state.rosters then return 0 end
  local n, wall = 0, G.WallNow()
  for _, r in pairs(ns.state.rosters) do
    if r.d.st == "published" and r.d.at + R.CLOSE_AFTER > wall and R.where(r.d, me()) and not R.rsvpOf(ns.state, r.id, me()) then
      n = n + 1
    end
  end
  return n
end

-- attendance: every client in the raid records who is in it during the window, for ONE roster only (the
-- active roster, R.activeRoster). Editors sign it, the others report as witnesses.
function G.OnGroupRoster()
  if not ns.rosterReady or not ns.state.rosters then return end
  if not apiTrue(IsInRaid) and not apiTrue(IsInGroup) then return end
  local wall = G.WallNow()
  local api = G.GroupAPI()
  local members = api.members and api.members() or {}
  local names = {}
  for _, m in ipairs(members) do if m.name then names[#names + 1] = m.name end end
  local r = R.activeRoster(ns.state, names, wall, me())
  if not r then return end
  local seen = seenDB()
  seen[r.id] = type(seen[r.id]) == "table" and seen[r.id] or {}
  for _, n in ipairs(names) do if ns.roster(n) then seen[r.id][n] = true end end
end

-- every minute: auto-close (owner, or the GM when the owner is offline), weekly copies, reminder 1 h before
local reminded = {}
function G.Tick()
  if not ns.rosterReady or not ns.state.rosters then return end
  local wall, mine = G.WallNow(), me()
  for _, r in pairs(ns.state.rosters) do
    local d = r.d
    if R.autoCloseDue(d, wall) then
      local owner = ns.roster(d.owner)
      -- the GM also closes when the owner can no longer edit it (left the RL list)
      local closer = d.owner == mine or (P.isGM(ns.roster, mine) and
                     (not (owner and owner.online) or not R.canEdit(ns.roster, d.owner, d, settings())))
      if closer and R.canEdit(ns.roster, mine, d, settings()) then G.Close(r.id) end
    elseif R.remindDue(d, wall) and not reminded[r.id] and (R.where(d, mine) or R.rsvpOf(ns.state, r.id, mine)) then
      reminded[r.id] = true
      local msg = L.RB_REMIND:format(d.name, R.fmtWall(d.at):sub(12))
      if UIErrorsFrame and UIErrorsFrame.AddMessage then pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, msg, 1, 0.82, 0) end
      ns.print(msg)
    end
  end
  if G.CanLead() then
    for _, r in ipairs(R.dueRepeats(ns.state, mine, wall)) do G.Duplicate(r.id) end
  end
  -- sample the group every minute too (no GROUP_ROSTER_UPDATE after a /reload)
  pcall(G.OnGroupRoster)
  pcall(G.ReportSeen)
  R.prune(ns.state, wall)   -- closed rosters older than 8 weeks lose their RSVPs
end

function G.OnRecord(rec)
  if rec.k == "roster" and ns.UpdateBadge then pcall(ns.UpdateBadge) end
end

-- (diag): group / raid APIs this feature uses, present or not in this client
G.APIS = { "C_PartyInfo.InviteUnit", "C_PartyInfo.ConvertToRaid", "InviteUnit", "ConvertToRaid", "IsInRaid", "IsInGroup",
           "GetNumGroupMembers", "GetRaidRosterInfo", "SetRaidSubgroup", "SwapRaidSubgroup", "UnitInRaid", "UnitInParty",
           "InCombatLockdown", "IsEncounterInProgress" }
function G.ApiReport()
  local out = {}
  for _, name in ipairs(G.APIS) do
    local a, b = name:match("^([%w_]+)%.([%w_]+)$")
    local v
    if a then local t = _G[a]; v = type(t) == "table" and t[b] or nil else v = _G[name] end
    out[#out + 1] = name .. "=" .. (type(v) == "function" and "yes" or "no")
  end
  return table.concat(out, " ")
end

local f = CreateFrame("Frame")
if f.RegisterEvent then
  pcall(f.RegisterEvent, f, "GROUP_ROSTER_UPDATE")
end
f:SetScript("OnEvent", function(_, ev)
  if ev == "GROUP_ROSTER_UPDATE" then pcall(G.OnGroupRoster) end
end)
if ns.Every then ns.Every(60, function() pcall(G.Tick) end) end
