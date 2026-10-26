-- wipes and seasons, PvP and world PvP, Overlord optional, diagnostics,
-- membership per wipe (leaving removes only the current wipe's contributions)
local Pr, D = NS.Progress, NS.Diag
local T0 = 1792566000 -- Wed 21-Oct-2026 09:00 CEST = start of a wipe
local WEEK = 604800
local function store(list)
  local s = Pr.newStore()
  for _, e in ipairs(list) do assert(Pr.add(s, e)) end
  return s.events
end
local function lv(who, sid, ts, l) return { t = "level", who = who, sid = sid, ts = ts, lv = l } end

test("wipe: wipeOf = legacy weekly season id, exact start/end, legacy ids stay valid", function()
  eq(Pr.wipeOf(T0), Pr.seasonOf(T0), "same id as the legacy season id"); eq(Pr.wipeOf(T0 - 1), Pr.prevWipe(Pr.wipeOf(T0)))
  eq(Pr.wipeStartTs(Pr.wipeOf(T0)), T0, "CEST start")
  eq(Pr.wipeOf(T0 + WEEK), Pr.wipeOf(T0), "28-Oct 08:00 CET is still the old wipe")
  eq(Pr.wipeStartTs(Pr.wipeOf(T0 + WEEK + 3600)), T0 + WEEK + 3600, "CET start after DST")
  eq(Pr.wipeEndTs(Pr.wipeOf(T0)), T0 + WEEK + 3600)
  ok(Pr.parseSeason("W2856"), "a stored legacy id parses as a wipe id")
end)

test("season: default start 4-Nov-2026 09:00, start/end bounds, new season, date parse", function()
  eq(Pr.formatDate(Pr.DEFAULT_SEASON_START), "2026-11-04 09:00")
  eq(Pr.parseDate("2026-11-04 09:00"), Pr.DEFAULT_SEASON_START); eq(Pr.parseDate("2026-10-21"), T0)
  eq(Pr.parseDate("nope"), nil)
  local cfg = Pr.seasonCfg({})
  eq(cfg.current.start, Pr.DEFAULT_SEASON_START); eq(cfg.current.stop, 0); eq(#cfg.past, 0)
  local S = Pr.DEFAULT_SEASON_START
  eq(#Pr.seasonWipes(cfg.current, S - 1), 0, "before the start: no wipes")
  eq(#Pr.seasonWipes(cfg.current, S), 1, "first wipe at the start")
  eq(#Pr.seasonWipes(cfg.current, S + 3 * WEEK + 10), 4)
  eq(Pr.seasonWipes(cfg.current, S)[1], Pr.wipeOf(S))
  -- closed season: end bounds the wipes even later
  local closed = { start = S, stop = S + 2 * WEEK }
  eq(#Pr.seasonWipes(closed, S + 10 * WEEK), 2, "end bound")
  -- season starting mid-wipe: that wipe belongs to the previous season
  eq(#Pr.seasonWipes({ start = S + 3600, stop = 0 }, S + WEEK - 1), 0, "mid-wipe start: first wipe not included")
  -- new season
  local f = Pr.newSeason({ seasonName = "Temporada 1", seasonStart = S, seasonEnd = 0 }, S + 5 * WEEK, "T2")
  eq(f.seasonStart, S + 5 * WEEK); eq(f.seasonEnd, 0); eq(f.seasonName, "T2")
  local c2 = Pr.seasonCfg(f)
  eq(#c2.past, 1); eq(c2.past[1].start, S); eq(c2.past[1].stop, S + 5 * WEEK); eq(c2.past[1].name, "Temporada 1")
  eq(#Pr.seasonWipes(c2.past[1], S + 9 * WEEK), 5, "closed season keeps its 5 wipes")
  eq(Pr.seasonWipes(c2.current, S + 5 * WEEK)[1], Pr.wipeOf(S + 5 * WEEK), "new season starts with the next wipe")
end)

test("season score = sum of each wipe's capped score", function()
  local S = Pr.DEFAULT_SEASON_START
  local ev = {}
  for w = 0, 2 do
    for l = 2, 41 do ev[#ev + 1] = lv("Ann", "S1", S + w * WEEK + 100 + l * 120, l) end -- re-levelling alt; levels 120 s apart (Pr.LEVEL_GAP)
  end
  local events = store(ev)
  local season = { start = S, stop = 0 }
  local res = Pr.seasonScore(events, season, S + 2 * WEEK + 9000, { cap = 10 })
  -- each wipe: 40 levels + 4 milestones*2 = 48 raw / 3 = 16 -> capped at 10 ; 3 wipes = 30
  eq(res.squads.S1.level, 30, "3 wipes x cap 10"); eq(res.squads.S1.nWipes, 3); ok(res.squads.S1.capped.level)
  eq(#res.wipes, 3)
  local res2 = Pr.seasonScore(events, season, S + 2 * WEEK + 9000, { cap = 100 })
  eq(res2.squads.S1.level, 3 * 16, "uncapped sum")
  ok(res2.squads.S1.general <= 500 * 3, "max 500 per wipe")
end)

test("pvp: BG won 10 / lost 3, needs 2 witnesses within 180 s, cap per wipe", function()
  local function bg(who, ts, win, inst) return { t = "bg", who = who, sid = "S1", ts = ts, inst = inst or "Warsong Gulch", win = win } end
  local r = Pr.compute(store({ bg("Ann", T0 + 10, 1) }), { season = Pr.wipeOf(T0) })
  eq(r.squads.S1 and r.squads.S1.pvp or 0, 0, "1 report: nothing")
  r = Pr.compute(store({ bg("Ann", T0 + 10, 1), bg("Bob", T0 + 40, 1) }), { season = Pr.wipeOf(T0) })
  eq(r.squads.S1.raw.pvp, 10, "won"); eq(r.squads.S1.bgW, 1)
  r = Pr.compute(store({ bg("Ann", T0 + 10, 0), bg("Bob", T0 + 40, 0) }), { season = Pr.wipeOf(T0) })
  eq(r.squads.S1.raw.pvp, 3, "lost"); eq(r.squads.S1.bgL, 1)
  r = Pr.compute(store({ bg("Ann", T0 + 10, 1), bg("Bob", T0 + 300, 1) }), { season = Pr.wipeOf(T0) })
  eq(r.squads.S1 and r.squads.S1.raw.pvp or 0, 0, "300 s apart: no")
  local many = {}
  for i = 1, 40 do many[#many + 1] = bg("Ann", T0 + i * 3600, 1); many[#many + 1] = bg("Bob", T0 + i * 3600 + 5, 1) end
  r = Pr.compute(store(many), { season = Pr.wipeOf(T0) })
  eq(r.squads.S1.raw.pvp, 400); eq(r.squads.S1.pvp, 100, "capped at 100"); ok(r.squads.S1.capped.pvp)
  eq(Pr.bgOutcome(0, "Horde"), 1); eq(Pr.bgOutcome(1, "Horde"), 0); eq(Pr.bgOutcome(1, "Alliance"), 1)
  eq(Pr.bgOutcome(nil, "Horde"), nil); eq(Pr.bgOutcome(255, "Horde"), nil, "draw/unknown")
  ok(not Pr.sanitize({ t = "bg", who = "Ann", sid = "S1", ts = T0, win = 2 }), "win must be 0/1")
end)

test("world pvp: HK deltas (outside instances, never negative, no jump on reset or character change)", function()
  local d, st = Pr.counterStep(nil, "Ann", 100, false)
  eq(d, 0, "first reading is a baseline")
  d, st = Pr.counterStep(st, "Ann", 107, false); eq(d, 7)
  d, st = Pr.counterStep(st, "Ann", 107, true); eq(d, 0, "no change")
  d, st = Pr.counterStep(st, "Ann", 130, false); eq(d, 0, "previous reading inside an instance: BG kills ignored")
  d, st = Pr.counterStep(st, "Ann", 133, false); eq(d, 3)
  d, st = Pr.counterStep(st, "Ann", 2, false); eq(d, 0, "counter reset: never negative")
  d, st = Pr.counterStep(st, "Ann", 5, false); eq(d, 3, "continues after reset")
  d, st = Pr.counterStep(st, "Ann", 5000, false); eq(d, 0, "huge jump ignored")
  d, st = Pr.counterStep(st, "Alt", 9000, false); eq(d, 0, "other character: baseline")
  ok(not Pr.sanitize({ t = "hk", who = "Ann", sid = "S1", ts = T0, n = 500 }), "event over the max rejected")
  ok(not Pr.sanitize({ t = "hk", who = "Ann", sid = "S1", ts = T0, n = -2 }), "negative rejected")
  -- scoring: 1 point per 5 HK per member and wipe, normalised, cap 100
  local r = Pr.compute(store({ { t = "hk", who = "Ann", sid = "S1", ts = T0 + 1, n = 7 }, { t = "hk", who = "Ann", sid = "S1", ts = T0 + 2, n = 4 },
                              { t = "hk", who = "Bob", sid = "S1", ts = T0 + 3, n = 4 } }), { season = Pr.wipeOf(T0) })
  eq(r.squads.S1.raw.wpvp, 2, "Ann 11 HK -> 2, Bob 4 -> 0"); eq(r.squads.S1.hk, 15)
  local big = {}
  for i = 1, 60 do big[#big + 1] = { t = "hk", who = "Ann", sid = "S1", ts = T0 + i, n = 100 } end
  r = Pr.compute(store(big), { season = Pr.wipeOf(T0) })
  eq(r.squads.S1.wpvp, 100, "cap 100")
  local a = Pr.achievements(store(big), {}); ok(a.squad.S1.hk100, "100 HK achievement")
end)

test("overlord optional: mock present adds captures (read-only), absent shows hint without errors", function()
  local calls = 0
  local lb = { GetMaxCapturesForDedupName = function(self, name) calls = calls + 1; return name == "Ann" and 12 or 0 end }
  local ov = { Leaderboard = lb }
  local mt = setmetatable({}, { __newindex = function() error("Overlord must not be mutated") end, __index = ov })
  eq(Pr.overlordCaptures(mt, "Ann"), 12); eq(calls, 1)
  eq(Pr.overlordCaptures(nil, "Ann"), nil, "absent: nil, no error")
  eq(Pr.overlordCaptures({ Leaderboard = { GetMaxCapturesForDedupName = function() error("boom") end } }, "Ann"), nil, "error caught")
  eq(Pr.overlordCaptures({ Leaderboard = {} }, "Ann"), nil, "API missing")
  ok(Pr.overlordHint(false, true, false), "hint when missing"); ok(not Pr.overlordHint(true, true, false), "no hint when present")
  ok(not Pr.overlordHint(false, true, true), "dismissed forever"); ok(not Pr.overlordHint(false, false, false), "GM disabled")
  local r = Pr.compute(store({ { t = "cap", who = "Ann", sid = "S1", ts = T0 + 1, n = 3 } }), { season = Pr.wipeOf(T0) })
  eq(r.squads.S1.raw.wpvp, 6, "2 points per capture"); eq(r.squads.S1.caps, 3)
  local ev = {}
  for i = 1, 10 do ev[#ev + 1] = { t = "cap", who = "Ann", sid = "S1", ts = T0 + i, n = 1 } end
  ok(Pr.achievements(store(ev), {}).squad.S1.conq, "Conquistadores at 10 captures")
end)

test("membership per wipe: closed wipes keep points, current wipe loses the leaver's, witnesses at event time", function()
  local S = T0
  local members = { S1 = { Ann = true, Bob = true } }
  local function now_(sid, n) return members[sid] and members[sid][n] or false end
  local snap = {}
  local function take(ts) local l = {}; for n in pairs(members.S1) do l[#l + 1] = n end; Pr.snapshot(snap, Pr.wipeOf(ts), "S1", l) end
  local ev = { lv("Ann", "S1", S + 100, 10), lv("Bob", "S1", S + 200, 12),
               { t = "boss", who = "Ann", sid = "S1", ts = S + 300, inst = "Hall of Thanes", it = "party", enc = 7, boss = "X" },
               { t = "boss", who = "Bob", sid = "S1", ts = S + 310, inst = "Hall of Thanes", it = "party", enc = 7, boss = "X" } }
  take(S + 500) -- membership snapshot while wipe N is current
  -- wipe N closes, Bob leaves in wipe N+1
  local tN1 = S + WEEK + 4000
  members.S1.Bob = nil
  ev[#ev + 1] = lv("Ann", "S1", tN1, 11)
  ev[#ev + 1] = lv("Bob", "S1", tN1 + 10, 13) -- Bob in current wipe, already gone
  local events = store(ev)
  local isM = Pr.memberAt(snap, now_, tN1 + 20)
  local wN = Pr.compute(events, { season = Pr.wipeOf(S), isMember = isM }).squads.S1
  local wN0 = Pr.compute(events, { season = Pr.wipeOf(S) }).squads.S1
  eq(wN.raw.level, wN0.raw.level, "wipe N unchanged after Bob left"); eq(wN.dKills, 1, "witnessed kill kept")
  local season = { start = S, stop = 0 }
  local ss = Pr.seasonScore(events, season, tN1 + 20, { isMember = isM })
  eq(ss.squads.S1.level, wN.level + Pr.compute(events, { season = Pr.wipeOf(tN1), isMember = isM }).squads.S1.level, "season sum keeps wipe N")
  -- current wipe: Bob's contribution removed
  local cur = Pr.compute(events, { season = Pr.wipeOf(tN1), isMember = isM }).squads.S1
  eq(cur.raw.level, 1, "only Ann's level counts in the current wipe")
  members.S1.Bob = true
  local cur2 = Pr.compute(events, { season = Pr.wipeOf(tN1), isMember = Pr.memberAt(snap, now_, tN1 + 20) }).squads.S1
  eq(cur2.raw.level - cur.raw.level, 1, "drop = Bob's contribution")
  -- witness at event time: Cid was not a member during wipe N -> his report is no witness there
  members.S1.Bob = nil; members.S1.Cid = true
  local ev3 = store({ { t = "boss", who = "Ann", sid = "S1", ts = S + 900, inst = "I", it = "party", enc = 9, boss = "Y" },
                      { t = "boss", who = "Cid", sid = "S1", ts = S + 950, inst = "I", it = "party", enc = 9, boss = "Y" } })
  eq(#Pr.kills(ev3, { isMember = Pr.memberAt(snap, now_, tN1 + 20) }), 0, "Cid joined later: not a witness in wipe N")
end)

test("diag: report has every section and key counters, size cap, safe args", function()
  local db = D.new()
  D.scanApis(db, function(n) if n == "GetPVPLifetimeStats" or n == "C_PvP" then return {} end end)
  ok(db.apis.pvp.GetPVPLifetimeStats, "present API"); eq(db.apis.pvp.GetBattlefieldWinner, false, "missing API")
  D.count(db, "ENCOUNTER_END", 1); D.count(db, "ENCOUNTER_END", 2); D.count(db, "CHAT_MSG_ADDON:own", 3)
  D.note(db, "lastEncounter", D.args(101, "Thane", 1, 5, 1, { x = 1 }), 2)
  D.note(db, "hk", "lifetime=10", 3); D.note(db, "encComm", "lockdown=false held=2", 4)
  local rep = D.report(db)
  for _, sec in ipairs({ "[build]", "[apis]", "[events]", "[encounter] last ENCOUNTER_END: 101, \"Thane\", 1, 5, 1, table",
                         "[encounter] comm during encounter: lockdown", "[pvp] honorable kills: lifetime=10", "[overlord]" }) do
    ok(rep:find(sec, 1, true), "section " .. sec)
  end
  for _, ev in ipairs(D.KEY_EVENTS) do ok(rep:find(ev .. "=", 1, true), "counter " .. ev) end
  ok(rep:find("ENCOUNTER_END=2", 1, true) and rep:find("PLAYER_LEVEL_UP=0", 1, true) and rep:find("CHAT_MSG_ADDON:own=1", 1, true))
  for i = 1, 200 do D.count(db, "EV_" .. i, i); D.addNote(db, string.rep("x", 150), i) end
  eq(db.nEvents, D.MAX_EVENTS, "distinct events capped"); eq(#db.notes, D.MAX_NOTES)
  local big = D.report(db, { string.rep("y", 9000) })
  ok(#big <= D.MAX_BYTES, "size cap " .. #big); ok(big:find("[truncated]", 1, true))
  eq(D.ensure({ v = 0 }).v, D.VERSION, "bad saved shape replaced")
end)
