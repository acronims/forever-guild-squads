-- convergence: rename collisions with nts, pending requests, urgent messages, GM boss records
local M, P = NS.Model, NS.Progress
local T0 = 1795000000

-- with nts (written on rename), the squad that had the name first keeps it on every client,
-- whatever the arrival order; nothing is evicted or refused.
test("rename collision with nts: same state and same display on every arrival order", function()
  local roster = makeRoster({ ["Gm-R"] = 0, ["Ca-R"] = 5, ["Cb-R"] = 5 })
  local function ap(s, r) return M.apply(s, r, { roster = roster }) end
  local function rec(id, a, d, ts) return { k = "squad", id = id, a = a, ts = ts, sq = 1, d = d } end
  local function copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = copy(v) end return o end
  local b0 = rec("B", "Cb-R", { name = "Bar", captain = "Cb-R", members = { "Cb-R" } }, T0 + 100)
  local a0 = rec("A", "Ca-R", { name = "Foo", captain = "Ca-R", members = { "Ca-R" } }, T0 + 200)
  local b1 = rec("B", "Cb-R", { name = "Foo", captain = "Cb-R", members = { "Cb-R" }, ct = T0 + 100, nts = T0 + 300 }, T0 + 300)
  local orders = { { b0, a0, b1 }, { b1, a0 }, { a0, b1 }, { b0, b1, a0 } }
  local seen
  for _, order in ipairs(orders) do
    local s = M.newState()
    ap(s, { k = "settings", id = "settings", a = "Gm-R", ts = T0, sq = 1, d = { squadsEnabled = true } })
    for _, r in ipairs(order) do ap(s, copy(r)) end
    local view = M.displayName(s, "A") .. "|" .. M.displayName(s, "B")
    eq(view, "Foo|Foo (2)", "display")
    seen = seen or view
    eq(view, seen)
  end
end)

-- the summary of a wipe is the same whether it is computed at the close or 8 weeks later, after the squad
-- record changed (captain's consent still required while the record predates the end of the wipe)
test("pending request (record older than the wipe end, name not listed) still does not count", function()
  local T = T0 + 3 * 86400
  local wipe = P.wipeOf(T)
  local events = {}
  local ev = P.sanitize({ t = "boss", who = "N-R", ts = T, sid = "X", inst = "Barrow Deeps", it = "raid", enc = 777, boss = "Jefe", pres = { "N-R" } })
  events[P.eventId(ev)] = ev
  local squads = { X = { ts = T0, d = { captain = "A-R", members = { "A-R" }, bench = {} } } }
  local profiles = { ["N-R"] = { ts = T0, d = { squad = "X" } } }
  local sums = P.wipeSummary(events, wipe, { profiles = profiles, squads = squads })
  ok(not (sums.X and (sums.X.active or 0) > 0), "a pending request is not a member")
end)

-- a fresh own record goes before the backlog of hello replies, parts in order
test("urgent messages jump the reply backlog, parts kept in order", function()
  local Q = NS.Queue
  local sent = {}
  local q = Q.new({ rate = 1, burst = 1, send = function(it) sent[#sent + 1] = it.msg; return true end })
  for i = 1, 5 do q:pushMessage({ { msg = "reply" .. i } }, "r" .. i) end
  ok(q:pushMessageFront({ { msg = "own1" }, { msg = "own2" } }, "own"))
  ok(not q:pushMessageFront({ { msg = "own1" } }, "own"), "same pending key deduped")
  for t = 1, 7 do q:pump(t) end
  eq(table.concat(sent, ","), "own1,own2,reply1,reply2,reply3,reply4,reply5")
  eq(q:size(), 0)
end)

-- GM and a member teach the same boss at the same moment (skewed clocks) -> same catalog
test("a GM boss record wins over a member's whatever the order and the clocks", function()
  local roster = makeRoster({ ["Gm-R"] = 0, ["Mb-R"] = 5 })
  local function rec(a, ts) return { k = "boss", id = "ragefire_chasm.102", a = a, ts = ts, sq = 1, d = { inst = "ragefire_chasm", enc = 102, name = "Boss", kind = "dungeon" } } end
  local gm, mb = rec("Gm-R", T0 + 10), rec("Mb-R", T0)          -- the member's clock says "earlier"
  local s1, s2 = M.newState(), M.newState()
  M.apply(s1, gm, { roster = roster }); M.apply(s1, mb, { roster = roster })
  M.apply(s2, mb, { roster = roster }); M.apply(s2, gm, { roster = roster })
  eq(s1.bosses["ragefire_chasm.102"].a, "Gm-R"); eq(s2.bosses["ragefire_chasm.102"].a, "Gm-R")
end)
