-- Core/Progress.lua + Core/Content.lua (incl. positive schema test)
local Pr, Ct = NS.Progress, NS.Content

local T0 = 1792566000 -- Wed 21-Oct-2026 09:00 CEST (07:00 UTC) = start of a wipe
local function boss(who, sid, ts, extra)
  local e = { t = "boss", who = who, sid = sid, ts = ts, inst = "Hall of Thanes", it = "party", enc = 101, boss = "Thane", gs = 5, pres = {} }
  for k, v in pairs(extra or {}) do e[k] = v end
  return e
end
local function store(list)
  local s = Pr.newStore()
  for _, e in ipairs(list) do assert(Pr.add(s, e)) end
  return s.events
end

test("progress: MetricEvent schema keeps only whitelisted fields (no economy fields)", function()
  local clean = Pr.sanitize({ t = "boss", who = "Ann", sid = "S1", ts = T0, it = "party", enc = 5, inst = "X", boss = "Y",
                              gold = 999, money = 1, trade = "x", copper = 3, price = 4, extra = { 1 } })
  ok(clean, "sanitized")
  local allowed = {}
  for k in pairs(Pr.SCHEMA) do allowed[k] = true end
  for k in pairs(clean) do ok(allowed[k], "field allowed: " .. k) end
  eq(clean.gold, nil); eq(clean.money, nil); eq(clean.trade, nil); eq(clean.extra, nil)
  local n = 0
  for k in pairs(Pr.SCHEMA) do
    n = n + 1
    ok(not k:lower():find("gold") and not k:lower():find("money") and not k:lower():find("trade"), "schema field " .. k)
  end
  eq(n, 15, "15 schema fields (incl. win, n)")
  ok(not Pr.sanitize({ t = "boss", who = "Ann", sid = "S1", ts = T0, it = "scenario", enc = 1 }), "only party/raid")
  ok(not Pr.sanitize({ t = "level", who = "Ann", sid = "S1", ts = T0, lv = 61 }), "level <= 60")
  ok(not Pr.sanitize({ t = "total", who = "Ann", sid = "S1", ts = T0 }), "no totals")
  local lv = Pr.sanitize({ t = "level", who = "Ann", sid = "S1", ts = T0, lv = 12, enc = 4 })
  eq(lv.enc, nil, "level events carry no boss fields")
end)

test("progress: witnesses (1 report no, 2 yes, 2 more than 180 s apart no)", function()
  eq(#Pr.kills(store({ boss("Ann", "S1", T0 + 10) })), 0, "single report does not score")
  local k = Pr.kills(store({ boss("Ann", "S1", T0 + 10), boss("Bob", "S1", T0 + 70, { pres = { "Cid" } }) }))
  eq(#k, 1, "two reports score"); eq(k[1].witnesses, 2); eq(k[1].present, 3, "Ann+Bob+Cid present")
  eq(#Pr.kills(store({ boss("Ann", "S1", T0 + 10), boss("Bob", "S1", T0 + 191) })), 0, "181 s apart: no")
  eq(#Pr.kills(store({ boss("Ann", "S1", T0 + 10), boss("Bob", "S1", T0 + 190) })), 1, "exactly 180 s: yes")
  eq(#Pr.kills(store({ boss("Ann", "S1", T0 + 10), boss("Bob", "S2", T0 + 20) })), 0, "different squads do not witness each other")
  eq(#Pr.kills(store({ boss("Ann", "S1", T0 + 10), boss("Ann", "S1", T0 + 20, { boss = "other" }) })), 0, "same reporter twice is one witness")
  -- no encounterID: same boss + instance name (case-insensitive)
  local a = boss("Ann", "S1", T0, { enc = nil, boss = "Thane Ulf" })
  local b = boss("Bob", "S1", T0 + 5, { enc = nil, boss = "THANE ULF", inst = "hall of thanes" })
  eq(#Pr.kills(store({ a, b })), 1, "matched by names")
  -- isMember filter
  local res = Pr.kills(store({ boss("Ann", "S1", T0), boss("Eve", "S1", T0 + 5) }), { isMember = function(_, n) return n ~= "Eve" end })
  eq(#res, 0, "non-member reports are not witnesses")
end)

test("progress: daily dedupe per boss per squad", function()
  local ev = {}
  for i = 0, 2 do -- the same boss three times the same day
    ev[#ev + 1] = boss("Ann", "S1", T0 + 3600 * i); ev[#ev + 1] = boss("Bob", "S1", T0 + 3600 * i + 30)
  end
  ev[#ev + 1] = boss("Ann", "S1", T0 + 86400); ev[#ev + 1] = boss("Bob", "S1", T0 + 86400 + 30) -- next day
  local k = Pr.kills(store(ev))
  eq(#k, 4, "4 witnessed kills"); eq(#Pr.dedupeDaily(k), 2, "one per day")
  local r = Pr.compute(store(ev), { season = Pr.seasonOf(T0) })
  local w = Ct.get("thanes").weight
  eq(w, 1 + 13 / 20, "weight = 1 + min/20")
  eq(r.squads.S1.dKills, 2)
  eq(r.squads.S1.dungeon, 2 * w / 3, "2 kills x weight / max(3, 2 active)")
end)

test("progress: leveling points, milestones, normalisation and cap per wipe", function()
  local ev = {}
  for lv = 2, 11 do ev[#ev + 1] = { t = "level", who = "Ann", sid = "S1", ts = T0 + lv * 100, lv = lv } end
  local r = Pr.compute(store(ev), { season = Pr.seasonOf(T0) })
  -- 10 levels + milestone 10 = 12, one active member -> / 3
  eq(r.squads.S1.raw.level, 12); eq(r.squads.S1.div, 3); eq(r.squads.S1.level, 4)
  -- 4 active members -> / 4
  for i, n in ipairs({ "Bob", "Cid", "Dan" }) do ev[#ev + 1] = { t = "level", who = n, sid = "S1", ts = T0 + 5000 + i, lv = 30 } end
  r = Pr.compute(store(ev), { season = Pr.seasonOf(T0) })
  eq(r.squads.S1.div, 4); eq(r.squads.S1.raw.level, 12 + 9); eq(r.squads.S1.level, 21 / 4)
  -- cap
  r = Pr.compute(store(ev), { season = Pr.seasonOf(T0), cap = 2 })
  eq(r.squads.S1.level, 2, "capped at 2"); ok(r.squads.S1.capped.level)
  -- weights in general
  r = Pr.compute(store(ev), { season = Pr.seasonOf(T0), weights = { level = 2, dungeon = 1, raid = 1 } })
  eq(r.squads.S1.general, 2 * 21 / 4)
  -- duplicate level report does not count twice, out-of-wipe ignored
  ev[#ev + 1] = { t = "level", who = "Ann", sid = "S1", ts = T0 + 9000, lv = 5 }
  ev[#ev + 1] = { t = "level", who = "Ann", sid = "S1", ts = T0 - 10, lv = 40 }
  r = Pr.compute(store(ev), { season = Pr.seasonOf(T0) })
  eq(r.squads.S1.raw.level, 21)
  ok(Pr.acceptLevel({ lv = 12 }, 11) and Pr.acceptLevel({ lv = 12 }, 13) and not Pr.acceptLevel({ lv = 12 }, 14)
     and not Pr.acceptLevel({ lv = 12 }, nil), "roster level +-1")
end)

test("progress: raids, present members and first guild kill bonus", function()
  local raid = { it = "raid", inst = "Onyxia's Lair", enc = 900, boss = "Onyxia" }
  local function rb(who, sid, ts, pres) local e = boss(who, sid, ts, raid); e.pres = pres or {}; return e end
  local ev = { rb("Ann", "S1", T0 + 100, { "Cid", "Dan" }), rb("Bob", "S1", T0 + 101),
               rb("Eve", "S2", T0 + 102, { "Gus", "Hal", "Ivy" }), rb("Fay", "S2", T0 + 103) }
  local r = Pr.compute(store(ev), { season = Pr.seasonOf(T0) })
  -- 4 present -> 5*4/5 = 4 raw; S2: 5 present -> 5 raw + 10 bonus (more members present)
  eq(r.squads.S1.raw.raid, 4); eq(r.squads.S2.raw.raid, 15); eq(r.squads.S2.bonus, 10); eq(r.squads.S1.bonus, 0)
  eq(r.squads.S2.raid, 3, "15 / 5 active")
  local rk = Pr.ranking(r, "raid")
  eq(rk[1].sid, "S2"); eq(rk[1].pos, 1); eq(rk[2].sid, "S1")
  local rk2 = Pr.ranking(r, "raid", { S1 = true, S2 = true, S9 = true })
  eq(#rk2, 3, "squads without events listed with 0"); eq(rk2[3].sid, "S9"); eq(rk2[3].points, 0)
  eq(Pr.weekKills(store(ev), T0 + 200), 2, "guild goal counts witnessed kills of all squads")
  eq(Pr.weekKills(store(ev), T0 + 8 * 86400), 0, "next wipe starts at 0")
end)

test("progress: wipe id boundaries (Wednesday 09:00 realm time, DST) and legacy monthly", function()
  local s = Pr.seasonOf(T0)
  eq(Pr.seasonOf(T0 - 1), Pr.prevSeason(s), "08:59:59 CEST is previous week")
  eq(Pr.seasonOf(T0 + 6 * 86400 + 23 * 3600), s, "Tuesday night same week")
  local T1 = 1793174400 -- Wed 28-Oct-2026 09:00 CET (08:00 UTC), after the DST change
  eq(Pr.seasonOf(T1), Pr.prevSeason(s, -1), "next Wednesday 09:00 CET")
  eq(Pr.seasonOf(T1 - 1), s, "08:59:59 CET still this week")
  local y, m, d = Pr.seasonStart(s)
  eq(y, 2026); eq(m, 10); eq(d, 21)
  eq(Pr.realmOffset(T0), 7200); eq(Pr.realmOffset(T1), 3600)
  -- monthly: 1-Nov-2026 09:00 CET = 08:00 UTC
  local N1 = 1793174400 + 4 * 86400
  ok(Pr.seasonOf(N1, "monthly") ~= Pr.seasonOf(N1 - 1, "monthly"), "month boundary at day 1 09:00")
  eq(Pr.seasonOf(N1, "monthly"), "M" .. (2026 * 12 + 10))
  eq(#Pr.seasonList(s), 9, "current + 8 previous")
  local st = Pr.newStore()
  Pr.add(st, { t = "level", who = "Ann", sid = "S1", ts = T0 - 20 * 7 * 86400, lv = 5 })
  Pr.add(st, { t = "level", who = "Ann", sid = "S1", ts = T0, lv = 6 })
  eq(Pr.prune(st, s), 1, "events older than 8 wipes pruned")
  local yy, mm, dd = Pr.civilFromDays(Pr.daysFromCivil(2024, 2, 29)); eq(yy * 10000 + mm * 100 + dd, 20240229)
end)

test("progress: key achievements", function()
  local ev = {}
  local t = T0
  local function kill(inst, enc, it, sid, a, b)
    t = t + 86400 -- one per day so dedupe does not hide them
    ev[#ev + 1] = boss(a or "Ann", sid or "S1", t, { inst = inst, enc = enc, it = it or "party", boss = "B" .. enc })
    ev[#ev + 1] = boss(b or "Bob", sid or "S1", t + 10, { inst = inst, enc = enc, it = it or "party", boss = "B" .. enc })
  end
  for i, d in ipairs(Ct.DUNGEONS) do kill(d.name, 200 + i) end
  kill("Barrow Deeps", 300, "raid")
  ev[#ev + 1] = { t = "level", who = "Bob", sid = "S1", ts = T0 + 50, lv = 60 }
  ev[#ev + 1] = { t = "level", who = "Eve", sid = "S2", ts = T0 + 40, lv = 60 }
  local members = { S1 = { "Ann", "Bob", "Cid", "Dan", "Fay" } }
  local levels = { Ann = 60, Bob = 60, Cid = 60, Dan = 60, Fay = 60 }
  local a = Pr.achievements(store(ev), { now = t + 30 * 86400, members = function(sid) return members[sid] end,
                                         levelOf = function(n) return levels[n] end })
  local s1 = a.squad.S1
  ok(s1.firstDungeon and s1.forever and s1.boss10 and s1.firstRaid and s1.first60 and s1.squad60, "S1 achievements")
  eq(s1.firstDungeon, T0 + 86400); ok(not s1.boss50)
  eq(a.squad.S2.first60, T0 + 40)
  ok(a.char.Eve and a.char.Eve.guildFirst60 == T0 + 40, "first of the guild to 60 is Eve"); eq(a.char.Bob, nil)
  ok(s1.sotw, "squad of the wipe for a closed wipe")
  levels.Fay = 59
  a = Pr.achievements(store(ev), { now = t, members = function(sid) return members[sid] end, levelOf = function(n) return levels[n] end })
  eq(a.squad.S1.squad60, nil, "not all 5 at 60")
  -- 8 of 9 Forever dungeons: no "Ruta Forever"
  local ev2 = {}
  for i = 1, #ev do if not (ev[i].enc == 209) then ev2[#ev2 + 1] = ev[i] end end
  eq(Pr.achievements(store(ev2), {}).squad.S1.forever, nil, "8/9 is not the route")
  local known = {}
  eq(#Pr.mergeAchievements(known, a), 6 + 1 + 1, "first merge: S1 x6 (no squad60), S2 x1, Eve x1")
  eq(#Pr.mergeAchievements(known, a), 0, "second merge: nothing new")
end)

test("content: catalog matching by name, alias, learned id; unknown = classic weight 1", function()
  eq(#Ct.DUNGEONS, 9); eq(#Ct.RAIDS, 3)
  eq(Ct.match("ruins of lordaeron", "party").key, "lordaeron")
  eq(Ct.match("Guarida de Onyxia", "raid").key, "onyxia")
  eq(Ct.get("onyxia").size, 40); eq(Ct.get("barrow").size, 10); eq(Ct.get("hyjal").size, 20)
  local u = Ct.match("Deadmines", "party"); eq(u.weight, 1); eq(u.forever, false); eq(u.kind, "dungeon")
  eq(Ct.match("Molten Core", "raid").kind, "raid")
  Ct.match("Shaper's Terrace", "party", 7777)
  eq(Ct.match("Terraza del Modelador", "party", 7777).key, "shaper", "learned by instanceID")
  eq(Ct.match("terraza del modelador", "party").key, "shaper", "and the localized name")
  eq(Ct.get("shaper").final, nil, "final boss unknown")
end)
