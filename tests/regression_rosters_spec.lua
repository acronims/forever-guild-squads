-- Regression tests: raid rosters. Each test asserts the CORRECT behaviour.
local R, M = NS.Roster, NS.Model
local T0 = 1795000000

local ranks = { ["Gm-R"] = 0, ["Off-R"] = 1, ["Rl-R"] = 4, ["Mem-R"] = 4 }
for i = 1, 60 do ranks["P" .. i .. "-R"] = 5 end
local roster = makeRoster(ranks)

local function fresh(offEdit)
  local s = M.newState()
  ok(M.apply(s, { k = "settings", id = "settings", a = "Gm-R", ts = T0, sq = 1,
                  d = { squadsEnabled = true, officerRanks = { 1 }, rlList = { "Rl-R" }, offEdit = offEdit or false } },
             { roster = roster }), "settings")
  return s
end
local function rec(kind, id, a, d, ts, sq) return { k = kind, id = id, a = a, ts = ts, sq = sq or ts, d = d } end
local function ap(s, r) return M.apply(s, R.copy(r), { roster = roster }) end
local function rdata(st, extra)
  local d = R.new({ raid = "custom", size = 10, name = "Raid A", at = R.civil(2026, 12, 9, 20, 0) })
  d.st = st; d.owner = "Rl-R"
  for k, v in pairs(extra or {}) do d[k] = v end
  return d
end
local RID = "Rl-R:" .. T0

-- a concurrent close and edit converge to the same roster state in any order
test("concurrent close + edit converge to the same roster state in any order", function()
  local create = rec("roster", RID, "Rl-R", rdata("published"), T0 + 100)
  local close = rec("roster", RID, "Rl-R", rdata("closed"), T0 + 200)
  local edit = rec("roster", RID, "Gm-R", rdata("published", { main = { "P1-R" } }), T0 + 201)
  local a, b = fresh(), fresh()
  ap(a, create); ap(a, close); ap(a, edit)
  ap(b, create); ap(b, edit); ap(b, close)
  eq(a.rosters[RID].d.st, b.rosters[RID].d.st, "peers diverge on roster state")
end)

-- an RSVP sent before the close but delivered after it converges across peers
test("a late-delivered RSVP (ts before the close) converges across peers", function()
  local create = rec("roster", RID, "Rl-R", rdata("published", { main = { "P1-R" } }), T0 + 100)
  local rs = rec("rsvp", R.rsvpId(RID, "P1-R"), "P1-R", { rid = RID, name = "P1-R", v = "yes", c = "" }, T0 + 150)
  local close = rec("roster", RID, "Rl-R", rdata("closed", { main = { "P1-R" } }), T0 + 200)
  local a, b = fresh(), fresh()
  ap(a, create); ap(a, rs); ap(a, close)
  ap(b, create); ap(b, close); ap(b, rs)
  eq(table.concat(M.bucketHashes(a, "rsvp"), ","), table.concat(M.bucketHashes(b, "rsvp"), ","), "rsvp buckets differ")
end)

-- RSVPs for roster ids that do not exist are not stored
test("an RSVP for a roster nobody has is not stored", function()
  local s = fresh()
  local n = 0
  for i = 1, 50 do
    local rid = "Fake-R:" .. i
    if ap(s, rec("rsvp", R.rsvpId(rid, "Mem-R"), "Mem-R", { rid = rid, name = "Mem-R", v = "yes", c = "spam" }, T0 + i)) then n = n + 1 end
  end
  eq(n, 0, "rsvps for unknown rosters stored: " .. n)
end)

-- a weekly roster resumed after a long absence produces one future copy, not a cascade
test("a weekly roster resumed after 10 weeks produces one future copy, not a cascade", function()
  local s = fresh()
  local at0 = R.civil(2026, 12, 9, 20, 0)
  ok(ap(s, rec("roster", RID, "Rl-R", rdata("published", { wk = true }), T0 + 1)))
  local now = at0 + 10 * R.WEEK + 3600
  local due = R.dueRepeats(s, "Rl-R", now)
  eq(#due, 1)
  local d2 = R.duplicate(due[1].d, due[1].id)
  ok(ap(s, rec("roster", "Rl-R:copy1", "Rl-R", d2, T0 + 2)))
  eq(#R.dueRepeats(s, "Rl-R", now), 0, "copy is already in the past and will be copied again on the next tick")
end)

-- attendance is bounded to guild members and size + bench
test("attendance is bounded to guild members and size + bench", function()
  local s = fresh()
  ok(ap(s, rec("roster", RID, "Rl-R", rdata("published"), T0 + 1)))
  local names = {}
  for i = 1, 60 do names[#names + 1] = "P" .. i .. "-R" end
  for i = 1, 20 do names[#names + 1] = "Stranger" .. i .. "-X" end
  ap(s, rec("attendance", RID, "Rl-R", { rid = RID, names = names, at = 1 }, T0 + 2))
  local a = s.attendance and s.attendance[RID]
  ok(not a or #a.d.names <= 20, "attendance stored with " .. (a and #a.d.names or 0) .. " names")
end)

-- a numeric bench entry is refused or exported without error
test("a roster with a numeric bench entry is refused or exported without error", function()
  local s = fresh()
  local okA = ap(s, rec("roster", RID, "Rl-R", rdata("published", { bench = { 12345 } }), T0 + 1))
  if okA then
    local okE, err = pcall(R.exportText, s, RID, function() return nil end, {})
    ok(okE, "export raised: " .. tostring(err))
  end
end)

-- a roster with a non-finite date is refused
test("a roster with a non-finite date is refused", function()
  local s = fresh()
  local okA = ap(s, rec("roster", RID, "Rl-R", rdata("published", { at = math.huge }), T0 + 1))
  ok(not okA, "roster with at=inf accepted")
end)

-- the second invite click invites the next batch, not the still-pending one
test("the second click invites the next batch, not the still-pending one", function()
  local names = {}
  for i = 1, 9 do names[#names + 1] = "P" .. i .. "-R" end
  local function api(log)
    return { inCombat = function() return false end, invite = function(n) log[#log + 1] = n end,
             isRaid = function() return false end, groupSize = function() return 1 end, inGroup = function() return false end }
  end
  local l1, l2 = {}, {}
  R.invite(api(l1), {}, names, "Rl-R")
  R.invite(api(l2), {}, names, "Rl-R")
  local first = {}
  for _, n in ipairs(l1) do first[n] = true end
  local again = 0
  for _, n in ipairs(l2) do if first[n] then again = again + 1 end end
  eq(again, 0, "click 2 re-invited " .. again .. " pending players")
end)

-- after ConvertToRaid, invites beyond the party cap wait until the group is a raid
test("after ConvertToRaid, invites beyond the party cap wait until the group is a raid", function()
  local names = {}
  for i = 1, 8 do names[#names + 1] = "P" .. i .. "-R" end
  local sent = 0
  local res = R.invite({ inCombat = function() return false end, invite = function() sent = sent + 1 end,
                         isRaid = function() return false end, groupSize = function() return 2 end,
                         inGroup = function() return false end, convert = function() end }, {}, names, "Rl-R")
  ok(sent <= 3, "invited " .. sent .. " while still a 5-man party (remaining reported " .. res.remaining .. ")")
end)
