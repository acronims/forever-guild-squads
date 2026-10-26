-- Regression tests: authority, convergence and scoring edge cases. Each test asserts the CORRECT behaviour.
local M, Pr, S = NS.Model, NS.Progress, NS.Serialize
local roster = makeRoster({ ["Gm-R"] = 0, ["Off-R"] = 1, ["Ali-R"] = 5, ["Bob-R"] = 5, ["Cid-R"] = 5, ["Eve-R"] = 7 })
local ctx = { roster = roster }
local T0 = 1795000000

local function squad(id, cap, name, members, ts, a, extra)
  local d = { name = name, captain = cap, members = members, bench = {}, icon = 1, color = 1, border = 1, approved = true }
  for k, v in pairs(extra or {}) do d[k] = v end
  return { k = "squad", id = id, a = a or cap, ts = ts, sq = 1, d = d }
end
local function prof(name, sid, ts) return { k = "profile", id = name, a = name, ts = ts, sq = 1, d = { squad = sid, role = "DAMAGER" } } end

-- authorship is bound to the physical sender: a forged GM settings record relayed by a non-GM is rejected
test("forged GM settings relayed by a non-GM are rejected", function()
  local st = M.newState()
  local forged = { k = "settings", id = "settings", a = "Gm-R", ts = T0, sq = 1,
                   d = { squadsEnabled = false, compEnabled = false, banned = { "a" } } }
  -- Eve (rank 7) sends it. Model receives the physical sender
  -- (ctx.sender); the forged record is rejected and the genuine one accepted.
  local okA = M.apply(st, forged, { roster = roster, sender = "Eve-R" })
  ok(not okA, "settings authored as GM but sent by Eve were applied")
  ok(M.apply(st, forged, { roster = roster, sender = "Gm-R" }), "the same record sent by the GM is accepted")
end)

test("far-future ts locks a record forever (no ts sanity bound)", function()
  local st = M.newState()
  M.apply(st, { k = "settings", id = "settings", a = "Gm-R", ts = 4e9, sq = 1, d = { squadsEnabled = false } }, ctx)
  local okA, why = M.apply(st, { k = "settings", id = "settings", a = "Gm-R", ts = T0 + 10, sq = 99, d = { squadsEnabled = true } }, ctx)
  ok(okA, "real GM save after a far-future forged one is 'stale': " .. tostring(why))
end)

-- a squad cannot be taken over by an outsider who signs a hand-over to themselves
test("outsider cannot take over a squad by claiming a transfer", function()
  local st = M.newState()
  ok(M.apply(st, squad("S1", "Ali-R", "Raiders", { "Ali-R", "Cid-R" }, T0), ctx))
  M.apply(st, prof("Cid-R", "S1", T0 + 1), ctx)
  local hijack = squad("S1", "Bob-R", "Raiders", { "Bob-R" }, T0 + 5, "Bob-R", { xferFrom = "Ali-R" })
  local okA = M.apply(st, hijack, ctx)
  ok(not okA, "Bob (not a member) became captain of S1 and kicked everyone; captain now " .. st.squads.S1.d.captain)
end)

-- validation does not depend on arrival order (name uniqueness converges)
test("two clients converge on the same squad set regardless of arrival order", function()
  local x = squad("X", "Ali-R", "Raiders", { "Ali-R" }, T0)
  local y = squad("Y", "Bob-R", "raiders", { "Bob-R" }, T0 + 1)
  local c1, c2 = M.newState(), M.newState()
  M.apply(c1, x, ctx); M.apply(c1, y, ctx)
  M.apply(c2, y, ctx); M.apply(c2, x, ctx)
  local function ids(st) local o = {} for id in pairs(st.squads) do o[#o + 1] = id end table.sort(o) return table.concat(o, ",") end
  eq(ids(c1), ids(c2), "clients diverge (c1 has " .. ids(c1) .. ", c2 has " .. ids(c2) .. ")")
end)

-- an officer disband and a concurrent captain edit converge to the same state
test("disband by officer + later captain edit converge", function()
  local base = squad("S1", "Ali-R", "Raiders", { "Ali-R" }, T0)
  local disband = squad("S1", "Ali-R", "Raiders", { "Ali-R" }, T0 + 10, "Off-R", { disbanded = true })
  local edit = squad("S1", "Ali-R", "Raiders", { "Ali-R", "Bob-R" }, T0 + 20) -- captain had not seen the disband yet
  local c1, c2 = M.newState(), M.newState()
  M.apply(c1, base, ctx); M.apply(c1, disband, ctx); M.apply(c1, edit, ctx)
  M.apply(c2, base, ctx); M.apply(c2, edit, ctx); M.apply(c2, disband, ctx)
  eq(tostring(c1.squads.S1.d.disbanded), tostring(c2.squads.S1.d.disbanded), "disbanded state diverges")
end)

-- a season total stays stable after old events are pruned
test("season score is stable after Progress.prune (season longer than 8 wipes)", function()
  local season = { start = Pr.wipeStartTs("W" .. Pr.weekOf(T0)), stop = 0 }
  local store = Pr.newStore()
  local w0 = Pr.weekOf(T0)
  for i = 0, 11 do -- 12 wipes, one witnessed BG win each (10 raw points)
    local ts = Pr.wipeStartTs("W" .. (w0 + i)) + 3600
    Pr.add(store, { t = "bg", who = "Ali-R", ts = ts, sid = "S1", inst = "WSG", win = 1 })
    Pr.add(store, { t = "bg", who = "Bob-R", ts = ts + 5, sid = "S1", inst = "WSG", win = 1 })
  end
  local now = Pr.wipeStartTs("W" .. (w0 + 11)) + 7200
  local before = Pr.seasonScore(store.events, season, now, {}).squads.S1.pvp
  Pr.prune(store, Pr.wipeOf(now), "weekly")
  local afterS = Pr.seasonScore(store.events, season, now, {}).squads.S1
  eq(afterS and afterS.pvp or 0, before, "season PvP points shrink after prune (reload)")
end)

-- hello replies are paginated so a fresh client converges
test("a fresh client converges after repeated hellos (100 squads)", function()
  local A = M.newState()
  local ranks = {}
  for i = 1, 100 do
    local cap = ("C%03d-R"):format(i); ranks[cap] = 5
    A.squads["S" .. i] = squad("S" .. i, cap, ("Squad %03d"):format(i), { cap }, T0 + i)
  end
  local ros = makeRoster(ranks)
  local sent = {}
  local ns = { Model = M, state = A, roster = ros, rosterReady = true, onlineCount = function() return 1 end,
               After = function(_, fn) fn() end,
               Comm = { Send = function(tag, p) sent[#sent + 1] = { tag, p } end } }
  loadmod("Sync.lua", ns)
  local B = M.newState()
  for _ = 1, 10 do
    local h = {}
    for _, k in ipairs({ "settings", "squad", "profile", "reject" }) do h[k] = M.bucketHashes(B, k) end
    sent = {}
    ns.Sync.OnMessage("H", { h = h }, "New-R")
    for _, m in ipairs(sent) do for _, r in ipairs(m[2].r) do M.apply(B, r, { roster = ros }) end end
  end
  local n = 0; for _ in pairs(B.squads) do n = n + 1 end
  eq(n, 100, "squads known by the fresh client after 10 hellos")
end)

-- a malformed record never raises a Lua error
test("malformed record does not raise a Lua error", function()
  local ns = { Model = M, state = M.newState(), roster = roster, rosterReady = true, After = function() end,
               Comm = { Send = function() end } }
  loadmod("Sync.lua", ns)
  local okP, err = pcall(ns.Sync.OnMessage, "D", { r = { { id = "x", k = "squad" } } }, "Eve-R")
  ok(okP, "Lua error: " .. tostring(err))
end)

-- the level backfill rule does not let a level-60 score levels again
test("a level-60 cannot score levels 2..60 again in the current wipe", function()
  local store = Pr.newStore()
  local now = T0
  local r = { level = 60 }
  for lv = 2, 60 do
    local ev = { t = "level", who = "Ali-R", ts = now - 3601, sid = "S1", lv = lv }
    -- Progress.lua:353 acceptance rule, verbatim
    local accept = Pr.acceptLevel(ev, r.level) or (now - ev.ts > 3600 and ev.lv <= r.level)
    if accept then Pr.add(store, ev) end
  end
  local res = Pr.compute(store.events, { season = Pr.wipeOf(now - 3601) })
  ok((res.squads.S1 and res.squads.S1.raw.level or 0) <= 3, "raw level points " .. tostring(res.squads.S1 and res.squads.S1.raw.level))
end)

-- instance weight is not decided by a single reporter
test("instance weight is not taken from a single reporter's claim", function()
  local store = Pr.newStore()
  Pr.add(store, { t = "boss", who = "Ali-R", ts = T0, sid = "S1", inst = "Blackmaw Hold", it = "party", enc = 1444, boss = "Taragaman" })
  Pr.add(store, { t = "boss", who = "Bob-R", ts = T0 + 2, sid = "S1", inst = "Ragefire Chasm", it = "party", enc = 1444, boss = "Taragaman" })
  local res = Pr.compute(store.events, { season = Pr.wipeOf(T0) })
  ok(res.squads.S1.raw.dungeon <= 1, "dungeon raw " .. res.squads.S1.raw.dungeon .. " (weight of the claimed instance)")
end)

-- names that differ only by a trailing space cannot coexist
test("'Raiders' and 'Raiders ' cannot coexist", function()
  local st = M.newState()
  ok(M.apply(st, squad("X", "Ali-R", "Raiders", { "Ali-R" }, T0), ctx))
  local okA = M.apply(st, squad("Y", "Bob-R", "Raiders ", { "Bob-R" }, T0 + 1), ctx)
  ok(not okA, "duplicate visible name accepted")
end)

-- a boss kill whose reports straddle the 09:00 reset still counts
test("kill reported at 08:59:50 and 09:00:05 on reset day still counts", function()
  local w = Pr.weekOf(T0) + 1
  local reset = Pr.wipeStartTs("W" .. w)
  local store = Pr.newStore()
  Pr.add(store, { t = "boss", who = "Ali-R", ts = reset - 10, sid = "S1", inst = "Ragefire Chasm", it = "party", enc = 7 })
  Pr.add(store, { t = "boss", who = "Bob-R", ts = reset + 5, sid = "S1", inst = "Ragefire Chasm", it = "party", enc = 7 })
  local a = Pr.compute(store.events, { season = "W" .. (w - 1) }).squads.S1
  local b = Pr.compute(store.events, { season = "W" .. w }).squads.S1
  local kills = (a and a.dKills or 0) + (b and b.dKills or 0)
  eq(kills, 1, "witnessed kill lost across the wipe boundary")
end)
