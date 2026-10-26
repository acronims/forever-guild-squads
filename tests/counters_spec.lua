-- guarded counters, canonical wipe summaries, queue dedupe, annulment revert
local R, Pr, Q = NS.Races, NS.Progress, NS.Queue
local T0 = 1795000000

local function cnt(k, n, ts, key, by)
  return { t = "cnt", who = by or "Ali-R", by = by or "Ali-R", ts = ts, k = k, key = key, n = n }
end

-- item 1: counters ----------------------------------------------------------
test("counters: live window [now-600, now+300] by the receiver clock", function()
  local now = T0 + 5000
  for _, k in ipairs({ "hk", "caps", "prof", "rep" }) do
    local key = (k == "prof" or k == "rep") and "mining" or nil
    ok(R.liveCounterOk(cnt(k, 100, now, key), now), k .. " now")
    -- measured from the send; up to 3 h waiting in the sender's queue
    ok(R.liveCounterOk(cnt(k, 100, now - 3 * 3600, key), now), k .. " 3 h ago is the edge")
    ok(not R.liveCounterOk(cnt(k, 100, now - 3 * 3600 - 1, key), now), k .. " 3 h + 1 s refused")
    ok(R.liveCounterOk(cnt(k, 100, now + 300, key), now) and not R.liveCounterOk(cnt(k, 100, now + 301, key), now),
       k .. " future edge 300 s")
    ok(not R.liveCounterOk(cnt(k, 100, now - 30 * 86400, key), now), k .. " backdated 30 days refused")
  end
  ok(R.CNT_GUARDED.hk and R.CNT_GUARDED.caps and R.CNT_GUARDED.prof and R.CNT_GUARDED.rep)
end)

test("counters: monotonic per character (a lower value later, or a higher one earlier, is refused)", function()
  local s = R.newStore()
  ok(R.add(s, cnt("hk", 1000, T0), T0), "hk 1000")
  local okA, why = R.add(s, cnt("hk", 100, T0 + 7200), T0 + 7200)
  ok(not okA and why == "decrease", "hk 100 after 1000 refused: " .. tostring(why))
  okA, why = R.add(s, cnt("hk", 5000, T0 - 3600 * 100), T0)
  ok(not okA and why == "decrease", "a higher value dated before refused: " .. tostring(why))
  ok(R.add(s, cnt("hk", 100, T0 - 7200), T0), "a lower value dated before is fine")
  -- other character / other key are independent
  ok(R.add(s, cnt("hk", 100, T0 + 10, nil, "Bob-R"), T0 + 10), "another character")
  ok(R.add(s, cnt("prof", 300, T0, "mining"), T0) and R.add(s, cnt("prof", 150, T0 + 9000, "herbalism"), T0 + 9000),
     "another profession")
  okA, why = R.add(s, cnt("prof", 225, T0 + 9000, "mining"), T0 + 9000)
  ok(not okA and why == "decrease", "mining going down refused")
  ok(R.add(s, cnt("caps", 100, T0), T0) and not R.add(s, cnt("caps", 10, T0 + 60), T0 + 60), "captures monotonic")
end)

-- an implausible jump is not refused by R.add; it is kept "unverified" and not
-- scored until the pace is plausible again (the profession cap is 60 / 10 min). Two values with the same ts refused.
test("counters: plausible jumps (HK 200 / prof 60 / rep 1 level per 10 min) score, the rest stays unverified", function()
  local function scored(s, ev)
    local list = {}
    for _, o in pairs(s.obs) do list[#list + 1] = o end
    local sc = R.scoredCounters(list)
    return sc[s.obs[R.obsId(R.sanitize(ev))]] == true
  end
  local s = R.newStore()
  ok(R.add(s, cnt("hk", 100, T0), T0))
  local fast = cnt("hk", 1000, T0 + 600)
  ok(R.add(s, fast, T0 + 600), "+900 HK in 10 min kept")
  ok(not scored(s, fast), "+900 HK in 10 min: unverified")
  local slow = cnt("hk", 5000, T0 + 600 * 25)
  ok(R.add(s, slow, T0 + 600 * 25) and scored(s, slow), "+4900 from the baseline in 250 min: plausible again")
  -- professions: 150 -> 225 needs 12.5 min
  local s2 = R.newStore()
  ok(R.add(s2, cnt("prof", 150, T0, "mining"), T0))
  local p1 = cnt("prof", 225, T0 + 600, "mining")
  ok(R.add(s2, p1, T0 + 600) and not scored(s2, p1), "+75 in 10 min unverified")
  local s3 = R.newStore()
  ok(R.add(s3, cnt("prof", 150, T0, "mining"), T0))
  local p2 = cnt("prof", 225, T0 + 750, "mining")
  ok(R.add(s3, p2, T0 + 750) and scored(s3, p2), "+75 in 12.5 min fine")
  -- reputation: one standing per 10 min
  local s4 = R.newStore()
  ok(R.add(s4, cnt("rep", 6, T0, "argent_dawn"), T0))
  local r1 = cnt("rep", 8, T0 + 600, "argent_dawn")
  ok(R.add(s4, r1, T0 + 600) and not scored(s4, r1), "2 levels in 10 min unverified")
  -- the baseline (first reading) never scores; a second value with the same ts is refused
  local s5 = R.newStore()
  local b = cnt("prof", 150, T0, "tailoring")
  ok(R.add(s5, b, T0) and not scored(s5, b), "baseline kept, not scored")
  local okA, why = R.add(s5, cnt("prof", 225, T0, "tailoring"), T0)
  ok(not okA and why == "sameTs", "same-ts second value refused: " .. tostring(why))
  -- loading SavedVariables (no rxNow) keeps what was already accepted
  local s6 = R.newStore()
  ok(R.add(s6, cnt("hk", 1000, T0)) and R.add(s6, cnt("hk", 100, T0 + 60)), "load path is not filtered")
end)

-- item 2: R11 deterministic wipe summaries ----------------------------------
local function wipeEvents()
  local w0 = Pr.weekOf(T0)
  local base = Pr.wipeStartTs("W" .. w0) + 3600
  local list = {}
  for i = 0, 9 do
    list[#list + 1] = { t = "bg", who = "Ali-R", ts = base + i * 600, sid = "S1", inst = "WSG", win = i % 2 }
    list[#list + 1] = { t = "bg", who = "Bob-R", ts = base + i * 600 + 7, sid = "S1", inst = "WSG", win = i % 2 }
    list[#list + 1] = { t = "level", who = "Cid-R", ts = base + i * 700, sid = "S2", lv = 20 + i }
    list[#list + 1] = { t = "hk", who = "Dan-R", ts = base + i * 900, sid = "S3", n = 7 + i }
  end
  return list, "W" .. w0
end

test("two clients with the same events produce identical summaries, whatever the order", function()
  local list, w = wipeEvents()
  local a, b = Pr.newStore(), Pr.newStore()
  for i = 1, #list do Pr.add(a, list[i]) end
  for i = #list, 1, -1 do Pr.add(b, list[i]) end
  -- b also got a duplicate (re-sent event) and an event of another wipe
  Pr.add(b, list[3])
  Pr.add(b, { t = "level", who = "Eve-R", ts = Pr.wipeStartTs(Pr.prevWipe(w, -1)) + 10, sid = "S2", lv = 11 })
  local sa, na = Pr.wipeSummary(a.events, w)
  local sb, nb = Pr.wipeSummary(b.events, w)
  eq(na, #list, "events counted once"); eq(nb, na, "same count")
  eq(Pr.summaryText(sb), Pr.summaryText(sa), "same canonical text")
  eq(Pr.summaryHash(sb), Pr.summaryHash(sa), "same hash")
  ok(Pr.summaryText(sa):find("S1=", 1, true) and Pr.summaryText(sa):find("S3=", 1, true), "squads in the text")
  -- a plain list in a third order gives the same result too
  local shuffled = {}
  for i = 1, #list do shuffled[#shuffled + 1] = list[((i * 7) % #list) + 1] end
  eq(Pr.summaryHash((Pr.wipeSummary(shuffled, w))), Pr.summaryHash(sa), "any order")
  -- prune stores the canonical summary with its event count, and the stored hash matches
  local now = Pr.wipeStartTs(Pr.prevWipe(w, -(Pr.KEEP_SEASONS + 2))) + 60
  Pr.prune(a, Pr.wipeOf(now), "weekly"); Pr.prune(b, Pr.wipeOf(now), "weekly")
  local ma, mb = Pr.storedSummary(a.events, w), Pr.storedSummary(b.events, w)
  ok(ma and mb, "summaries stored")
  eq(ma.hash, mb.hash, "stored hashes equal"); eq(ma.n, #list, "stored n")
end)

test("on a mismatch, the client with more events of that wipe is right (tie: smaller hash)", function()
  local list, w = wipeEvents()
  local full, part = Pr.newStore(), Pr.newStore()
  for i = 1, #list do Pr.add(full, list[i]) end
  for i = 1, #list - 5 do Pr.add(part, list[i]) end
  local sf, nf = Pr.wipeSummary(full.events, w)
  local sp, np = Pr.wipeSummary(part.events, w)
  Pr.setSummary(full, w, sf, nf); Pr.setSummary(part, w, sp, np)
  local mf, mp = Pr.storedSummary(full.events, w), Pr.storedSummary(part.events, w)
  ok(mf.hash ~= mp.hash, "they differ")
  ok(Pr.peerSummaryWins(mp, mf.n, mf.hash), "the client with fewer events takes the other one")
  ok(not Pr.peerSummaryWins(mf, mp.n, mp.hash), "the client with more events keeps its own")
  ok(not Pr.peerSummaryWins(mf, mf.n, mf.hash), "same hash: nothing to do")
  local tieA, tieB = { n = 5, hash = "aaaa" }, { n = 5, hash = "bbbb" }
  ok(Pr.peerSummaryWins(tieB, tieA.n, tieA.hash) and not Pr.peerSummaryWins(tieA, tieB.n, tieB.hash), "tie")
  -- after taking it, both hold the same summary
  Pr.setSummary(part, w, mf.sums, mf.n)
  eq(Pr.storedSummary(part.events, w).hash, mf.hash, "converged")
  -- season scores computed from the summary agree too
  local season = { start = Pr.wipeStartTs(w), stop = 0 }
  local now = Pr.wipeStartTs(w) + 86400
  eq(Pr.seasonScore(part.events, season, now, {}).squads.S1.pvp, Pr.seasonScore(full.events, season, now, {}).squads.S1.pvp)
end)

-- item 3: R13 level dedupe ---------------------------------------------------
test("one level report per reporter + character + level, the earliest ts stays", function()
  local lv = function(by, ts) return { t = "lv", who = "Ali-R", by = by, ts = ts, src = by == "Ali-R" and "self" or "roster", lv = 40 } end
  local a, b = R.newStore(), R.newStore()
  R.add(a, lv("Bob-R", T0 + 100)); R.add(a, lv("Bob-R", T0 + 50)); R.add(a, lv("Bob-R", T0 + 70))
  R.add(b, lv("Bob-R", T0 + 70)); R.add(b, lv("Bob-R", T0 + 50)); R.add(b, lv("Bob-R", T0 + 100))
  local function only(s)
    local list = {}
    for id, o in pairs(s.obs) do if o.t == "lv" then list[#list + 1] = id end end
    return list
  end
  eq(#only(a), 1, "one kept"); eq(#only(b), 1, "one kept (other order)")
  eq(only(a)[1], only(b)[1], "same id in both clients")
  eq(a.obs[only(a)[1]].ts, T0 + 50, "the earliest ts")
  -- other reporters (witnesses) and other levels are separate
  R.add(a, lv("Cid-R", T0 + 60)); R.add(a, lv("Ali-R", T0 + 40))
  R.add(a, { t = "lv", who = "Ali-R", by = "Bob-R", ts = T0 + 900, src = "roster", lv = 50 })
  eq(#only(a), 4, "witnesses and other levels kept")
  -- the index survives compaction
  R.compact(a)
  ok(not R.add(a, lv("Bob-R", T0 + 999)), "later duplicate refused after compaction")
end)

-- item 4: queue dedupe -------------------------------------------------------
test("queue: identical pending messages (same record and version) are queued once", function()
  local sent = {}
  local q = Q.new({ send = function(it) sent[#sent + 1] = it.msg; return true end, now = 0 })
  q:setBlocked("encounter", true)
  ok(q:pushMessage({ { msg = "a1" }, { msg = "a2" } }, "GUILD||rec:profile:Ali@5"), "first copy queued")
  ok(not q:pushMessage({ { msg = "b1" }, { msg = "b2" } }, "GUILD||rec:profile:Ali@5"), "identical one deduped")
  ok(q:pushMessage({ { msg = "c1" } }, "GUILD||rec:profile:Ali@6"), "a newer version is queued")
  ok(q:pushMessage({ { msg = "d1" } }, "WHISPER|Bob-R|rec:profile:Ali@5"), "another target is queued")
  eq(q:size(), 4); eq(q.deduped, 1)
  q:setBlocked("encounter", false)
  for t = 1, 10 do q:pump(t) end
  eq(table.concat(sent, ","), "a1,a2,c1,d1")
  ok(q:pushMessage({ { msg = "e1" } }, "GUILD||rec:profile:Ali@5"), "once sent, the same message can go again")
  ok(q:push({ msg = "plain" }), "push without key still works")
end)

test("queue: Comm.Send dedupes an identical payload while it is pending", function()
  local frame = { scripts = {} }
  function frame:RegisterEvent() end
  function frame:SetScript(k, fn) self.scripts[k] = fn end
  local savedCF, savedGT, savedCI = CreateFrame, GetTime, C_ChatInfo
  local clock, wire = 0, {}
  CreateFrame = function() return frame end
  GetTime = function() return clock end
  C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end,
                 SendAddonMessage = function(_, msg) wire[#wire + 1] = msg; return 0 end }
  local ns = { Serialize = NS.Serialize, Chunk = NS.Chunk, Queue = NS.Queue, roster = function() return {} end }
  loadmod("Comm.lua", ns)
  local Comm = ns.Comm
  Comm.Init(function() end)
  Comm.queue:setBlocked("encounter", true)
  local rec = { k = "profile", id = "Ali-R", ts = 5, a = "Ali-R", d = { note = "hi" } }
  Comm.Send("D", { r = { rec } }); Comm.Send("D", { r = { rec } })
  eq(Comm.Pending(), 1, "one pending")
  Comm.Send("D", { r = { rec } }, "WHISPER", "Bob-R")
  eq(Comm.Pending(), 2, "other target queued")
  Comm.queue:setBlocked("encounter", false)
  for _ = 1, 6 do clock = clock + 1; frame.scripts.OnUpdate(frame, 1) end
  eq(#wire, 2, "two messages on the wire")
  CreateFrame, GetTime, C_ChatInfo = savedCF, savedGT, savedCI
end)

-- item 5: B14 timers ----------------------------------------------------------
test("with C_Timer the send queue runs on a ticker that exists only while messages are pending", function()
  local frame = { scripts = {} }
  function frame:RegisterEvent() end
  function frame:SetScript(k, fn) self.scripts[k] = fn end
  local savedCF, savedGT, savedCI, savedCT = CreateFrame, GetTime, C_ChatInfo, C_Timer
  local clock, wire, tickers = 0, {}, {}
  CreateFrame = function() return frame end
  GetTime = function() return clock end
  C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end,
                 SendAddonMessage = function(_, msg) wire[#wire + 1] = msg; return 0 end }
  C_Timer = { After = function() end,
              NewTicker = function(p, fn) local t = { p = p, fn = fn }; function t:Cancel() self.cancelled = true end
                tickers[#tickers + 1] = t; return t end }
  local ns = { Serialize = NS.Serialize, Chunk = NS.Chunk, Queue = NS.Queue, roster = function() return {} end }
  loadmod("Comm.lua", ns)
  local Comm = ns.Comm
  Comm.Init(function() end)
  ok(frame.scripts.OnUpdate == nil, "no permanent OnUpdate")
  eq(#tickers, 0, "no ticker while idle")
  Comm.Send("D", { a = 1 })
  eq(#tickers, 1, "ticker started on send"); eq(tickers[1].p, 0.2)
  for _ = 1, 3 do clock = clock + 1; if not tickers[1].cancelled then tickers[1].fn() end end
  ok(#wire >= 1 and tickers[1].cancelled, "sent, then the ticker is cancelled")
  Comm.Send("D", { a = 2 })
  eq(#tickers, 2, "a new ticker for the next message")
  CreateFrame, GetTime, C_ChatInfo, C_Timer = savedCF, savedGT, savedCI, savedCT
end)

-- item 8: R14 revert an annulment + retract derived achievements ----------------
test("the GM reverts an annulment (on=false) and derived achievements follow the races", function()
  local M = NS.Model
  local roster = makeRoster({ ["GM-R"] = 0, ["Ali-R"] = 5, ["Bob-R"] = 5 })
  local st = M.newState()
  local function rec(on, ts)
    return { k = "annul", id = "lvl.all.20|Ali-R", a = "GM-R", ts = ts, sq = 1,
             d = { race = "lvl.all.20", key = "Ali-R", reason = "trampa", on = on } }
  end
  local s = R.newStore()
  for i, who in ipairs({ "Ali-R", "Bob-R" }) do
    R.add(s, { t = "lv", who = who, by = who, ts = T0 + i * 10, src = "self", lv = 20 })
    R.add(s, { t = "lv", who = who, by = "GM-R", ts = T0 + i * 10 + 1, src = "roster", lv = 20 })
  end
  ok(M.apply(st, rec(true, 10), { roster = roster }), "annulled")
  local r = R.compute(s, { now = T0 + 999, annul = R.annulMap(st.annuls) })["lvl.all.20"]
  eq(r.entries[1].key, "Bob-R", "Bob moves up"); eq(#r.history, 1)
  ok(M.apply(st, rec(false, 20), { roster = roster }), "reverted by the GM")
  r = R.compute(s, { now = T0 + 999, annul = R.annulMap(st.annuls) })["lvl.all.20"]
  eq(r.entries[1].key, "Ali-R", "Ali back to #1"); eq(#r.history, 0)
  local okD, whyD = M.apply(st, { k = "annul", id = "lvl.all.20|Ali-R", a = "Bob-R", ts = 30, sq = 1,
    d = { race = "lvl.all.20", key = "Ali-R", reason = "x", on = true } }, { roster = roster })
  ok(not okD and whyD == "denied", "only the GM")
  -- achievements: first1 given to Ali, then her entry is annulled -> retracted; Bob's stays; other kinds untouched
  local known = { squad = { S1 = { hallOfFame = 5, allRoles = 5 } }, char = { ["Ali-R"] = { first1 = 5, ["top100.20"] = 5, lvl20 = 5 } } }
  local fresh = { squad = { S1 = { allRoles = 5 } }, char = { ["Ali-R"] = { lvl20 = 5 }, ["Bob-R"] = { first1 = 6 } } }
  Pr.mergeAchievements(known, fresh)
  local removed = R.retractAchievements(known, fresh)
  eq(#removed, 3, "first1, top100.20 and hallOfFame retracted")
  ok(known.char["Ali-R"].lvl20 and known.squad.S1.allRoles and known.char["Bob-R"].first1, "the rest kept")
  ok(not known.char["Ali-R"].first1 and not known.squad.S1.hallOfFame)
end)
