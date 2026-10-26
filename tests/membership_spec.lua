-- membership in the current wipe: a pending join request (profile points at the squad, squad record does
-- not list the player) is not a member in the LIVE score of the current wipe, and the live score agrees with the
-- canonical wipe summary when the summary is given the squad records.
local M, P = NS.Model, NS.Progress
local T0 = 1795000000

test("pending request is not a member, live (M.isMember) == summary (recordMember + squads)", function()
  local T = T0 + 3 * 86400
  local wipe = P.wipeOf(T)
  local events = {}
  local function add(ev) local id = P.eventId(ev); events[id] = P.sanitize(ev) end
  local pres = { "A-R", "B-R", "C-R", "Pend-R" }
  add({ t = "boss", who = "A-R", ts = T, sid = "X", inst = "Barrow Deeps", it = "raid", enc = 777, boss = "Jefe", pres = pres })
  add({ t = "boss", who = "B-R", ts = T + 5, sid = "X", inst = "Barrow Deeps", it = "raid", enc = 777, boss = "Jefe", pres = pres })
  local state = { squads = { X = { ts = T0, d = { captain = "A-R", members = { "B-R", "C-R" }, bench = {} } } }, profiles = {} }
  for _, n in ipairs(pres) do state.profiles[n] = { ts = T0, d = { squad = "X" } } end  -- Pend-R: request only
  ok(not M.isMember(state, "X", "Pend-R"), "pending request is not a member")
  ok(M.isMember(state, "X", "C-R"), "accepted member is a member")
  local live = P.compute(events, { season = wipe, kind = "weekly", isMember = function(sid, n) return M.isMember(state, sid, n) end })
  eq(live.squads.X.active, 3, "live active members")
  local sums = P.wipeSummary(events, wipe, { profiles = state.profiles, squads = state.squads })
  eq(sums.X.active, live.squads.X.active, "active members differ (summary vs live)")
  eq(P.roundSum(sums.X.raid), P.roundSum(live.squads.X.raid), "raid score differs (summary vs live)")
end)
