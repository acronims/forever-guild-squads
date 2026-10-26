-- Regression tests: Core/Races, Progress, Model, Permissions, Serialize, Chunk, Queue.
-- Each test asserts the CORRECT behaviour.
-- The wipe-summary test gives the summary the squad records too (the captain's side of the consent): with
-- profiles only, a pending request and an accepted member are indistinguishable.
local S, M, P, R = NS.Serialize, NS.Model, NS.Progress, NS.Races
local T0 = 1795000000

local ranks = { ["Gm-R"] = 0, ["Off-R"] = 1, ["Off2-R"] = 1, ["Cx-R"] = 5, ["Cy-R"] = 5, ["A-R"] = 5, ["B-R"] = 5,
                ["C-R"] = 5, ["Pend-R"] = 5 }
local roster = makeRoster(ranks)
local function rec(kind, id, a, d, ts, sq) return { k = kind, id = id, a = a, ts = ts, sq = sq or 1, d = d } end
local function ap(s, r) return M.apply(s, r, { roster = roster }) end

-- non-finite numbers: the decoder refuses them and a -inf progress event cannot break prune
test("decode refuses non-finite numbers", function()
  local okD = S.decode("n-1e999;")
  ok(not okD, "decoder accepted -1e999 (= -inf)")
end)
test("a -inf progress event must not break prune", function()
  local okD, payload = S.decode(S.encode({ e = { { t = "hk", who = "A-R", sid = "S1", n = 1, ts = 0 } } }):gsub("n0;", "n-1e999;"))
  ok(okD, "decode")
  local store = P.newStore()
  local ev = P.sanitize(payload.e[1])
  if ev then P.add(store, ev) end           -- what Progress.lua OnEvents does (ts <= now+300 holds for -inf)
  P.add(store, { t = "hk", who = "B-R", sid = "S1", n = 1, ts = T0 })
  local okP, err = pcall(P.prune, store, P.wipeOf(T0 + 86400 * 120), "weekly", {})
  ok(okP, "prune raised: " .. tostring(err))
end)

-- non-finite numbers in any record kind are refused, so every re-encode (sync, export) keeps working
test("a record with sq = inf is refused (or can still be exported)", function()
  local s = M.newState()
  ap(s, rec("settings", "settings", "Gm-R", { squadsEnabled = true, officerRanks = { 1 } }, T0))
  local okD, r = S.decode(S.encode(rec("profile", "A-R", "A-R", { class = "MAGE", level = 10 }, T0 + 5, 7)):gsub("n7;", "n1e999;"))
  ok(okD, "decode")
  local applied = ap(s, r)
  local okE, err = pcall(M.export, s)
  ok(not applied or okE, "stored a record that can no longer be serialized: " .. tostring(err))
end)

-- a rename of an existing squad that collides with a younger squad never deletes the younger one
test("renaming an older squad onto a younger squad's name must not delete the younger squad", function()
  local s = M.newState()
  ap(s, rec("settings", "settings", "Gm-R", { squadsEnabled = true, officerRanks = { 1 } }, T0))
  ok(ap(s, rec("squad", "X", "Cx-R", { name = "Alfa", captain = "Cx-R", members = { "Cx-R" } }, T0 + 100)), "X")
  ok(ap(s, rec("squad", "Y", "Cy-R", { name = "Lobos", captain = "Cy-R", members = { "Cy-R" } }, T0 + 200)), "Y")
  ap(s, rec("squad", "X", "Cx-R", { name = "lobos", captain = "Cx-R", members = { "Cx-R" }, ct = T0 + 100 }, T0 + 300))
  ok(s.squads.Y ~= nil, "squad Y was deleted by X's rename")
end)

-- concurrent `boss` records from non-GM authors converge whatever the arrival order
test("concurrent boss records converge whatever the arrival order", function()
  local function mk() local s = M.newState(); ap(s, rec("settings", "settings", "Gm-R", { squadsEnabled = true }, T0)); return s end
  local d = { inst = "barrow", enc = 777, name = "Jefe", kind = "raid" }
  local ra = rec("boss", "barrow.777", "A-R", d, T0 + 10)
  local rb = rec("boss", "barrow.777", "B-R", d, T0 + 11)
  local s1, s2 = mk(), mk()
  ap(s1, ra); ap(s1, rb)
  ap(s2, rb); ap(s2, ra)
  eq(table.concat(M.bucketHashes(s1, "boss"), ","), table.concat(M.bucketHashes(s2, "boss"), ","), "boss buckets diverge")
end)

-- concurrent `vconfirm` records converge whatever the arrival order
test("concurrent vconfirm records converge whatever the arrival order", function()
  local function mk() local s = M.newState(); ap(s, rec("settings", "settings", "Gm-R", { squadsEnabled = true, officerRanks = { 1 } }, T0)); return s end
  local oid = "A-R|kill|1795000100|e777"
  local ra = rec("vconfirm", oid, "Off-R", { oid = oid }, T0 + 10)
  local rb = rec("vconfirm", oid, "Off2-R", { oid = oid }, T0 + 12)
  local s1, s2 = mk(), mk()
  ap(s1, ra); ap(s1, rb)
  ap(s2, rb); ap(s2, ra)
  eq(table.concat(M.bucketHashes(s1, "vconfirm"), ","), table.concat(M.bucketHashes(s2, "vconfirm"), ","), "vconfirm buckets diverge")
end)

-- the wipe summary uses the same membership as the live score: a pending join request is not a member
test("wipe summary uses the same membership as the live score (pending request is not a member)", function()
  local T = T0 + 3 * 86400
  local wipe = P.wipeOf(T)
  local events = {}
  local function add(ev) local id = P.eventId(ev); events[id] = P.sanitize(ev) end
  local pres = { "A-R", "B-R", "C-R", "Pend-R" }
  add({ t = "boss", who = "A-R", ts = T, sid = "X", inst = "Barrow Deeps", it = "raid", enc = 777, boss = "Jefe", pres = pres })
  add({ t = "boss", who = "B-R", ts = T + 5, sid = "X", inst = "Barrow Deeps", it = "raid", enc = 777, boss = "Jefe", pres = pres })
  local real = { ["A-R"] = true, ["B-R"] = true, ["C-R"] = true }
  local live = P.compute(events, { season = wipe, kind = "weekly", isMember = function(sid, n) return sid == "X" and real[n] == true end })
  local profiles = {}
  for _, n in ipairs(pres) do profiles[n] = { ts = T0, d = { squad = "X" } } end   -- Pend-R: request only
  local squads = { X = { ts = T0, d = { captain = "A-R", members = { "A-R", "B-R", "C-R" }, bench = {} } } }
  local sums = P.wipeSummary(events, wipe, { profiles = profiles, squads = squads })
  eq(sums.X.active, live.squads.X.active, "active members differ (summary vs live)")
  eq(P.roundSum(sums.X.raid), P.roundSum(live.squads.X.raid), "raid score differs (summary vs live)")
end)

-- an open season longer than 104 wipes still contains the current wipe
test("a season longer than 104 wipes still contains the current wipe", function()
  local season = { start = P.DEFAULT_SEASON_START, stop = 0 }
  local now = P.DEFAULT_SEASON_START + 110 * 604800
  local list = P.seasonWipes(season, now)
  eq(list[#list], P.wipeOf(now), "current wipe missing from the season")
end)

-- tie order (same ts) is the same whether candidates come from observations or from frozen rows
test("tie order does not depend on candidates coming from observations or frozen rows", function()
  local id = "pvp.bg.10"
  local function frozenStore()
    local rows = {}
    rows[1] = { key = "sq:S1", ts = T0, mark = "wit", chars = { "a" }, squads = { "S1" }, sup = {}, wit = 2 }
    rows[2] = { key = "sq:S2", ts = T0, mark = "wit", chars = { "b" }, squads = { "S2" }, sup = {}, wit = 2 }
    for i = 3, 10 do rows[i] = { key = "sq:Z" .. i, ts = T0 + i, mark = "wit", chars = {}, squads = { "Z" .. i }, sup = {}, wit = 2 } end
    return { obs = {}, closed = { [id] = { rows = rows, at = 0 } } }
  end
  local function race(cands) local r = R.def(id); r.cands = cands; r.history = {}; r.entries = {}; return r end
  local a = R.place(frozenStore(), race({}), {})
  local b = R.place(frozenStore(), race({ { key = "sq:S2", ts = T0, mark = "wit", squads = { "S2" }, chars = { "b" }, sup = {}, wit = 2, name = "S2" } }), {})
  eq(b.entries[1].squads[1], a.entries[1].squads[1], "position 1 changes with the source of the candidate")
end)
