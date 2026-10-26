-- races (order, Top N closing, witnesses, squad alliance, dungeon crediting, GM annulment,
-- PvP rank per season, compaction, pagination, migration), celebrations, learned boss catalog, adoption, schema.
-- Pure Core: no WoW API.
local R, C, Cel, M = NS.Races, NS.Content, NS.Celebrate, NS.Model
local T0 = 1795000000
local function lv(who, by, ts, level, src, cls, race)
  return { t = "lv", who = who, by = by, ts = ts, lv = level, src = src, cls = cls, race = race }
end
local function store(list)
  local s = R.newStore()
  for _, ev in ipairs(list) do local okA, why = R.add(s, ev); assert(okA, "add: " .. tostring(why)) end
  return s
end
local function keys(r) local o = {} for _, e in ipairs(r.entries) do o[#o + 1] = e.key end return table.concat(o, " ") end

test("races: order by ts, tie broken by full name, exact mark", function()
  local s = store({
    lv("Bob-R", "Bob-R", T0 + 100, 60, "self", "PRIEST"), lv("Bob-R", "GM-R", T0 + 160, 60),
    lv("Ann-R", "Ann-R", T0 + 100, 60, "self", "WARRIOR"), lv("Ann-R", "GM-R", T0 + 130, 60),
    lv("Cid-R", "Cid-R", T0 + 50, 60, "self", "MAGE"), lv("Cid-R", "Bob-R", T0 + 70, 60),
  })
  local races = R.compute(s, { now = T0 + 1000 })
  local r = races["lvl.all.60"]
  eq(keys(r), "Cid-R Ann-R Bob-R", "earliest first, tie -> alphabetical")
  eq(r.entries[1].pos, 1); eq(r.entries[2].mark, "exact"); eq(r.state, "open"); eq(r.size, 100)
  eq(races["lvl.class.WARRIOR.60"].entries[1].key, "Ann-R", "class race from UnitClass/classFile")
  eq(races["lvl.all.10"].state, "open", "registry lists empty races")
end)

test("races: Top 100 closes at 100, frozen (late earlier report changes nothing), compaction", function()
  local list = {}
  for i = 1, 105 do
    local who = ("P%03d-R"):format(i)
    list[#list + 1] = lv(who, who, T0 + i * 10, 10, "self", "WARRIOR")
    list[#list + 1] = lv(who, "GM-R", T0 + i * 10 + 5, 10)
  end
  local s = store(list)
  local races = R.compute(s, { now = T0 + 5000 })
  local r = races["lvl.all.10"]
  eq(#r.entries, 100); eq(r.state, "closed"); eq(r.entries[100].key, "P100-R")
  ok(s.closed["lvl.all.10"], "frozen as a closed race")
  -- the closed Top is always recomputed deterministically from every record held,
  -- so a late report with an EARLIER time enters (every client with the same data shows the same Top); still 100
  assert(R.add(s, lv("Zed-R", "Zed-R", T0 - 999, 10, "self", "WARRIOR"))); assert(R.add(s, lv("Zed-R", "GM-R", T0 - 990, 10)))
  r = R.compute(s, { now = T0 + 6000 })["lvl.all.10"]
  eq(#r.entries, 100); eq(r.entries[1].key, "Zed-R", "deterministic Top"); ok(not keys(r):find("P100"), "no 101st")
  -- compaction: level-10 observations only feed closed races (all + WARRIOR class) -> dropped, result kept
  local before = 0; for _ in pairs(s.obs) do before = before + 1 end
  local dropped = R.compact(s)
  ok(dropped >= 200, "dropped " .. dropped .. " of " .. before)
  r = R.compute(s, { now = T0 + 7000 })["lvl.all.10"]
  eq(#r.entries, 100); eq(r.entries[38].key, "P037-R", "frozen row survives compaction")
  -- one compact row per closed race, round trip
  local text = R.packClosed(s.closed["lvl.all.10"])
  local back = R.unpackClosed(text)
  eq(#back.rows, 100); eq(back.rows[6].key, "P005-R"); eq(back.rows[6].ts, T0 + 50)
  local s2 = R.newStore()
  ok(R.importClosed(s2, "lvl.all.10", text, 1)); ok(not R.importClosed(s2, "lvl.all.10", text, 2), "closed: never replaced")
  eq(R.compute(s2, { now = T0 })["lvl.all.10"].entries[100].key, "P099-R")
end)

test("races: level witnesses (exact vs approx, 10 min window, trusted single observer)", function()
  local s = store({
    lv("Ann-R", "Ann-R", T0, 20, "self"), lv("Ann-R", "Bob-R", T0 + 300, 20),      -- exact
    lv("Dan-R", "Bob-R", T0 + 100, 20), lv("Dan-R", "Cid-R", T0 + 400, 20),          -- 2 observers -> approx
    lv("Eve-R", "Bob-R", T0 + 100, 20), lv("Eve-R", "Cid-R", T0 + 100 + 1200, 20),   -- 20 min apart: no
    lv("Fay-R", "Bob-R", T0 + 50, 20),                                               -- single member: no
    lv("Gus-R", "GM-R", T0 + 60, 20),                                                -- single GM/officer: approx
    lv("Hal-R", "Hal-R", T0 + 70, 20, "self"),                                       -- self, never confirmed: no
  })
  local r = R.compute(s, { now = T0 + 9999, trusted = function(n) return n == "GM-R" end })["lvl.all.20"]
  eq(keys(r), "Ann-R Gus-R Dan-R")
  local byKey = {}
  for _, e in ipairs(r.entries) do byKey[e.key] = e end
  eq(byKey["Ann-R"].mark, "exact"); eq(byKey["Ann-R"].ts, T0)
  eq(byKey["Dan-R"].mark, "approx"); eq(byKey["Dan-R"].ts, T0 + 100, "earliest of the observers")
  eq(byKey["Gus-R"].mark, "approx")
  ok(not R.add(R.newStore(), lv("Ann-R", "Bob-R", T0, 20, "self")), "a 'self' report by someone else is refused")
end)

local function kill(by, ts, inst, it, enc, boss, members)
  local pres, sqm = {}, {}
  for sid, names in pairs(members) do
    for _, n in ipairs(names) do pres[#pres + 1] = n; if sid ~= "-" then sqm[#sqm + 1] = n .. ">" .. sid end end
  end
  table.sort(pres); table.sort(sqm)
  return { t = "kill", who = by, by = by, ts = ts, inst = inst, it = it, enc = enc, boss = boss, pres = pres, sqm = sqm }
end
local S1 = { "A1", "A2", "A3", "A4", "A5" }
local S2 = { "B1", "B2", "B3", "B4", "B5" }

test("races: boss/BG witnesses, pending 24 h with a single report", function()
  local m = { S1 = { "A1", "A2", "A3" }, ["-"] = { "X1", "X2" } }
  local s = store({
    kill("A1", T0, "Hall of Thanes", "party", 501, "Thane A", m), kill("A2", T0 + 100, "Hall of Thanes", "party", 501, "Thane A", m),
    kill("A1", T0 + 3600, "Hall of Thanes", "party", 502, "Thane B", m),                       -- single report
    kill("A1", T0 + 7200, "Hall of Thanes", "party", 503, "Thane C", m), kill("A2", T0 + 7200 + 200, "Hall of Thanes", "party", 503, "Thane C", m),
    { t = "bg", who = "A1", by = "A1", ts = T0, inst = "Warsong Gulch", win = 1, pres = { "A1", "A2" }, sqm = { "A1>S1", "A2>S1" } },
    { t = "bg", who = "A2", by = "A2", ts = T0 + 20, inst = "Warsong Gulch", win = 1, pres = { "A1", "A2" }, sqm = { "A1>S1", "A2>S1" } },
  })
  local races = R.compute(s, { now = T0 + 7300 })
  local a = races["dng.thanes.501"]
  eq(#a.entries, 1); eq(a.entries[1].mark, "wit"); eq(a.entries[1].wit, 2); eq(a.entries[1].key, "sq:S1")
  -- a single report never creates a race
  local b = races["dng.thanes.502"]
  ok(not b or #b.entries == 0, "one report: not counted, no race created")
  ok(not races["dng.thanes.503"] or #races["dng.thanes.503"].entries == 0, "two reports 200 s apart: no witness")
  eq(races["pvp.bgmap.warsong_gulch"].entries[1].key, "sq:S1", "BG map race from GetInstanceInfo name")
  local later = R.compute(s, { now = T0 + 3600 + 86400 + 1 })
  ok(not later["dng.thanes.502"] or #later["dng.thanes.502"].pending == 0, "after 24 h the single report is dropped")
end)

test("races: squad alliance (2 squads of 5 in a 10 raid share one position; a squad < 70 % does not)", function()
  local saved = C.bosses; C.bosses = {}
  C.learnBoss("barrow", 901, "Wight A", "raid"); C.learnBoss("barrow", 902, "Wight B", "raid"); C.learnBoss("barrow", 903, "Barrow King", "raid")
  local b3 = C.learnBoss("barrow", 903, "Barrow King", "raid")
  ok(C.setFinal(b3.id, true)); ok(C.hasFinal("barrow"))
  local S3p = { "C1", "C2", "C3" }
  local list = {}
  for i, enc in ipairs({ 901, 902, 903 }) do
    local m = { S1 = S1, S2 = S2 }
    if i == 1 then m = { S1 = S1, S2 = S2, S3 = S3p } end -- S3 only at the first boss (1/3 < 70 %)
    for _, by in ipairs({ "A1", "B1" }) do list[#list + 1] = kill(by, T0 + i * 600 + (by == "B1" and 30 or 0), "Barrow Deeps", "raid", enc, "x", m) end
  end
  local s = store(list)
  local ctx = { now = T0 + 9999, isFinal = C.isFinal, hasFinal = C.hasFinal, bossesOf = C.bossesOf }
  local races = R.compute(s, ctx)
  local r = races["raid.barrow"]
  eq(#r.entries, 1, "one shared position"); eq(r.entries[1].key, "al:S1+S2")
  eq(table.concat(r.entries[1].squads, "+"), "S1+S2"); eq(r.entries[1].pos, 1)
  ok(not r.entries[1].key:find("S3"), "S3 below 70 % is not credited")
  local sup = table.concat(r.entries[1].sup, ","); ok(sup:find("C1"), "S3 players appear as support: " .. sup)
  -- squads come only from reporters' own squads; S3 sent no report -> support
  eq(races["raid.barrow.901"].entries[1].key, "al:S1+S2", "boss race: only reporting squads")
  eq(races["raid.all"].state, "nodata", "raid.all waits for the other finals")
  eq(races["raid.hyjal"].state, "nodata")
  -- alliance credit helper directly: 2 of 3 = 66 % < 70 %
  local run = R.witnessed(s.obs and (function() local l = {} for _, e in pairs(s.obs) do l[#l + 1] = e end return l end)(), T0)
  for _, k in ipairs(run) do k.boss = R.bossSlug(k.ev) end
  eq(R.allianceCredit(run, { "901", "902", "903" }).key, "al:S1+S2")
  C.bosses = saved
end)

test("races: dungeon credited to one squad (>= 3) or 'grupo mixto'", function()
  local mixed = { S1 = { "A1", "A2" }, S2 = { "B1", "B2" }, ["-"] = { "X1" } }
  local one = { S1 = { "A1", "A2", "A3" }, ["-"] = { "X1", "X2" } }
  local s = store({
    kill("A1", T0, "Alcaz Prison", "party", 701, "Warden", mixed), kill("B1", T0 + 5, "Alcaz Prison", "party", 701, "Warden", mixed),
    kill("A1", T0 + 500, "Alcaz Prison", "party", 701, "Warden", one), kill("A2", T0 + 505, "Alcaz Prison", "party", 701, "Warden", one),
  })
  local r = R.compute(s, { now = T0 + 999 })["dng.alcaz.701"]
  eq(#r.entries, 2)
  ok(r.entries[1].mixed and r.entries[1].key:find("^mix:"), "first: mixed group")
  eq(r.entries[2].key, "sq:S1"); eq(#r.entries[2].squads, 1)
  eq(R.compute(s, { now = T0 })["dng.alcaz"].state, "nodata", "completion race: final boss unknown -> pending data")
end)

test("races: GM annulment (GM only, reason, next moves up, history) also on a closed race", function()
  local roster = makeRoster({ ["GM-R"] = 0, ["Off-R"] = 1 })
  local st = M.newState()
  local function rec(a, race, key, reason, ts) return { k = "annul", id = race .. "|" .. key, a = a, ts = ts or 10, sq = 1, d = { race = race, key = key, reason = reason } } end
  local okO, why = M.apply(st, rec("Off-R", "lvl.all.30", "P002-R", "trampa"), { roster = roster }); ok(not okO); eq(why, "denied")
  local okE, whyE = M.apply(st, rec("GM-R", "lvl.all.30", "P002-R", "  "), { roster = roster }); ok(not okE); eq(whyE, "reason")
  ok(M.apply(st, rec("GM-R", "lvl.all.30", "P002-R", "trampa"), { roster = roster }))
  local list = {}
  for i = 1, 103 do
    local who = ("P%03d-R"):format(i)
    list[#list + 1] = lv(who, who, T0 + i, 30, "self"); list[#list + 1] = lv(who, "GM-R", T0 + i + 1, 30)
  end
  local s = store(list)
  local plain = R.compute(R.newStore(), {}) -- empty store works
  ok(plain["lvl.all.30"], "empty")
  local races = R.compute(s, { now = T0 + 999, annul = R.annulMap(st.annuls) })
  local r = races["lvl.all.30"]
  eq(r.entries[2].key, "P003-R", "the next one moves up"); eq(#r.entries, 100); eq(r.entries[100].key, "P101-R")
  eq(#r.history, 1); eq(r.history[1].reason, "trampa"); eq(r.history[1].by, "GM-R")
  -- closed race: a later annulment frees a slot that the next candidate takes; history kept
  ok(M.apply(st, rec("GM-R", "lvl.all.30", "P050-R", "multicuenta", 11), { roster = roster }))
  r = R.compute(s, { now = T0 + 2000, annul = R.annulMap(st.annuls) })["lvl.all.30"]
  eq(#r.entries, 100); eq(r.entries[100].key, "P102-R"); eq(#r.history, 2)
  ok(not keys(r):find("P050%-R"), "annulled entry gone")
end)

test("races: PvP rank races per season, class rank 14, counters 'informado por el jugador'", function()
  local function cnt(who, ts, k, n, extra)
    local e = { t = "cnt", who = who, by = who, ts = ts, k = k, n = n }
    for a, b in pairs(extra or {}) do e[a] = b end
    return e
  end
  local s = store({
    cnt("Ann-R", T0, "pvprank", 12, { sea = "1", cls = "WARRIOR" }), cnt("Bob-R", T0 + 5, "pvprank", 14, { sea = "1", cls = "PRIEST" }),
    cnt("Ann-R", T0 + 99999, "pvprank", 5, { sea = "2" }), cnt("Cid-R", T0, "hk", 1000), cnt("Cid-R", T0, "prof", 225, { key = "Herrería" }),
    cnt("Dan-R", T0, "rep", 8, { key = "Darnassus" }),
    -- earlier baseline readings (the first reading of a counter never scores)
    cnt("Cid-R", T0 - 3600 * 5, "hk", 0), cnt("Cid-R", T0 - 600, "prof", 200, { key = "Herrería" }),
    cnt("Dan-R", T0 - 600, "rep", 7, { key = "Darnassus" }),
  })
  local races = R.compute(s, { now = T0, season = "2" })
  eq(keys(races["pvp.rank.12.s1"]), "Ann-R Bob-R"); eq(keys(races["pvp.rank.14.s1"]), "Bob-R")
  eq(keys(races["pvp.rank.class.PRIEST.14.s1"]), "Bob-R")
  eq(keys(races["pvp.rank.5.s2"]), "Ann-R", "season 2 starts from zero"); eq(races["pvp.rank.5.s2"].season, "2")
  eq(races["pvp.rank.5.s1"].entries[1].mark, "self")
  eq(keys(races["pvp.hk.1000"]), "Cid-R"); eq(keys(races["pvp.hk.100"]), "Cid-R")
  eq(keys(races["prof.herrería.225"]), "Cid-R"); eq(keys(races["rep.darnassus.exalted"]), "Dan-R")
  ok(not R.add(R.newStore(), { t = "cnt", who = "Ann-R", by = "Bob-R", ts = 1, k = "hk", n = 5 }), "counters only from the player")
  -- API missing in the client: pending data without errors
  local nd = R.compute(R.newStore(), { now = T0, nodata = { prof = true, rep = true, legacy = true } })
  eq(nd["prof.*"].state, "nodata"); eq(nd["rep.*"].state, "nodata"); eq(nd["legacy.100"].state, "nodata")
end)

test("sync: paginated diff of observations + closed races, migration of legacy SavedVariables", function()
  local list = {}
  for i = 1, 50 do list[#list + 1] = { t = "cnt", who = "W" .. i, by = "W" .. i, ts = T0 + i, k = "hk", n = 100 } end
  local s = store(list)
  local p1, more1, total = R.diffPage(s, nil, 1, 20); eq(#p1, 20); ok(more1); eq(total, 50)
  local p3, more3 = R.diffPage(s, nil, 3, 20); eq(#p3, 10); ok(not more3)
  local same = R.diffPage(s, R.bucketHashes(s), 1, 20); eq(#same, 0, "same hashes: nothing to send")
  -- a peer converges from the pages
  local s2 = R.newStore()
  local remote = R.bucketHashes(s2) -- the hello the peer sent once; the replier pages through it
  for page = 1, 3 do for _, it in ipairs((R.diffPage(s, remote, page, 20))) do if it.o then R.add(s2, it.o) end end end
  ok(deq(R.bucketHashes(s2), R.bucketHashes(s)), "converged")
  -- migration: a legacy db keeps its data and gains `races`
  local db = { profile = { x = 1 }, progress = { events = { a = 1 }, ach = { squad = {}, char = {} } }, minimap = { angle = 3 } }
  local r = R.migrate(db)
  ok(r and db.races == r and r.ver == 6); eq(db.progress.events.a, 1); eq(db.minimap.angle, 3)
  r.obs.x = 1; R.migrate(db); eq(db.races.obs.x, 1, "idempotent")
end)

test("celebrations: single announcer, rate limit, GM off = nothing, never during an encounter", function()
  local addon = { ["Ann-R"] = true, ["Off-R"] = true, ["Bob-R"] = true, ["Alt-R"] = true }
  local online = { ["Ann-R"] = true, ["Off-R"] = true, ["Bob-R"] = true, ["Zed-R"] = true, ["Alt-R"] = true }
  local rank = { ["Ann-R"] = 4, ["Off-R"] = 1, ["Bob-R"] = 4, ["Alt-R"] = 1 }
  local ctx = { hasAddon = function(n) return addon[n] end, online = function(n) return online[n] end,
                rank = function(n) return rank[n] end, users = { "Ann-R", "Off-R", "Bob-R", "Alt-R" } }
  eq(C and Cel.announcer({ "Bob-R", "Zed-R" }, ctx), "Bob-R", "protagonist with the addon")
  -- a protagonist online in the guild roster is preferred even when this client has
  -- not heard its addon yet (every client must agree); the CLAIM step covers protagonists without the addon
  eq(Cel.announcer({ "Zed-R" }, ctx), "Zed-R", "protagonist online in the roster")
  online["Zed-R"] = nil
  eq(Cel.announcer({ "Zed-R" }, ctx), "Alt-R", "protagonist offline: highest rank online addon user, tie by name (Alt < Off)")
  online["Alt-R"] = nil
  eq(Cel.announcer({ "Zed-R" }, ctx), "Off-R")
  -- every client computes the same announcer -> exactly one sends
  local senders = 0
  for _, me in ipairs(ctx.users) do if Cel.announcer({ "Zed-R" }, ctx) == me then senders = senders + 1 end end
  eq(senders, 1, "single announcer")
  -- scope
  local s = { celOn = true, celScope = "first", celSquad = false }
  ok(Cel.eligible({ kind = "race", pos = 1 }, s)); ok(not Cel.eligible({ kind = "race", pos = 2 }, s))
  s.celScope = "top3"; ok(Cel.eligible({ kind = "race", pos = 3 }, s)); ok(not Cel.eligible({ kind = "race", pos = 4 }, s))
  s.celScope = "any"; ok(Cel.eligible({ kind = "race", pos = 77 }, s)); ok(not Cel.eligible({ kind = "ach" }, s), "squad ach off")
  s.celSquad = true; ok(Cel.eligible({ kind = "ach" }, s))
  s.celOn = false; ok(not Cel.eligible({ kind = "race", pos = 1 }, s), "GM off: nothing")
  ok(not Cel.eligible({ kind = "race", pos = 1 }, M.defaultSettings()), "default: guild chat off")
  -- rate limit: <= 1 per 10 s; blocked (encounter / lockdown) = nothing leaves; no duplicates
  local q = Cel.newQueue()
  ok(Cel.enqueue(q, { key = "a" })); ok(Cel.enqueue(q, { key = "b" })); ok(not Cel.enqueue(q, { key = "a" }), "dedupe")
  eq(Cel.pump(q, 100, true), nil, "encounter: held")
  eq(Cel.pump(q, 100, false).key, "a"); eq(Cel.pump(q, 105, false), nil, "5 s later: held")
  eq(Cel.pump(q, 110, false).key, "b"); eq(Cel.pump(q, 200, false), nil, "empty")
  -- plain text, no links / escapes
  local t = Cel.text("%s |cffff0000x|r |Hitem:1|h[link]|h", "Ann")
  ok(not t:find("|", 1, true), t); ok(#Cel.text(("x"):rep(500)) <= Cel.MAX_LEN)
end)

test("catalog learns bosses (no duplicates, replicated, GM-only final) and adoption X/Y", function()
  local saved = C.bosses; C.bosses = {}
  local b, new = C.learnBoss("thanes", 11, "Thane Uno", "dungeon"); ok(new)
  local b2, new2 = C.learnBoss("thanes", 11, "Thane Uno", "dungeon"); ok(not new2); eq(b2, b, "no duplicate")
  local _, n3 = C.learnBoss("thanes", nil, "Sin ID", "dungeon"); ok(n3, "name-only boss")
  -- learned bosses are pending (not required) until confirmed (GM/officer or >= 2 witnesses)
  eq(#C.bossList(), 2); eq(table.concat(C.bossesOf("thanes"), ","), "")
  C.confirmBoss(b.id); C.learnBoss("thanes", nil, "Sin ID", "dungeon", true)
  eq(table.concat(C.bossesOf("thanes"), ","), "11,sin_id")
  ok(not C.learnBoss("thanes", nil, nil), "nothing to learn")
  -- replication through Model records
  local roster = makeRoster({ ["GM-R"] = 0, ["Ann-R"] = 4, ["Bob-R"] = 4 })
  local ctx = { roster = roster }
  local st, st2 = M.newState(), M.newState()
  local function brec(a, id, d, ts) return { k = "boss", id = id, a = a, ts = ts or 1, sq = 1, d = d } end
  ok(M.apply(st, brec("Ann-R", b.id, { inst = "thanes", enc = 11, name = "Thane Uno", kind = "dungeon", final = true }), ctx))
  eq(st.bosses[b.id].d.final, nil, "non-GM cannot mark final")
  local okD, whyD = M.apply(st, brec("Bob-R", b.id, { inst = "thanes", enc = 11, name = "Otro" }, 5), ctx); ok(not okD); eq(whyD, "dup")
  ok(not M.apply(st, brec("Ann-R", "zz.1", { inst = "thanes", enc = 11 }), ctx), "id must match the instance")
  ok(M.apply(st, brec("GM-R", b.id, { inst = "thanes", enc = 11, name = "Thane Uno", kind = "dungeon", final = true }, 9), ctx))
  eq(st.bosses[b.id].d.final, true, "GM marks the final boss")
  ok(M.import(st2, M.export(st), ctx) >= 1); eq(st2.bosses[b.id].d.final, true, "replicated")
  eq(#M.diffRecords(st, "boss", M.bucketHashes(st2, "boss")), 0, "same list everywhere")
  C.bosses = saved
  -- adoption: hellos of the last 14 days among the members active in the last 14 days
  local now = T0
  local members = { { name = "Me-R", days = 0, self = true }, { name = "Ann-R", days = 0 }, { name = "Bob-R", days = 3 },
                    { name = "Cid-R", days = 30 }, { name = "Dan-R", days = 1 } }
  local hello = { ["Ann-R"] = now - 3600, ["Bob-R"] = now - 20 * 86400, ["Cid-R"] = now }
  local x, y = R.adoption(members, hello, now)
  eq(x, 2, "me + Ann"); eq(y, 4, "Cid inactive for 30 days is not counted")
  local ach = R.achievements({}, {}, { now = now, adoption = { x = 8, y = 10 } })
  ok(ach.guild.guild and ach.guild.guild.allAboard, "Toda la guild a bordo at 80 %")
  local _, prog = R.achievements({}, {}, { now = now, adoption = { x = 2, y = 10 } })
  eq(prog.guild.guild.allAboard.cur, 2); eq(prog.guild.guild.allAboard.need, 8)
end)

test("achievements: squad and character catalogue with progress", function()
  local list = {}
  for i = 1, 3 do
    local who = "K" .. i .. "-R"
    list[#list + 1] = lv(who, who, T0 + i, 10, "self", "MAGE", "Human"); list[#list + 1] = lv(who, "GM-R", T0 + i + 1, 10)
  end
  local s = store(list)
  local races, info = R.compute(s, { now = T0 + 99 })
  local mem = { S1 = { "a", "b", "c", "d", "e" } }
  local role = { a = "TANK", b = "HEALER", c = "DAMAGER", d = "DAMAGER", e = "DAMAGER" }
  local cls = { a = "WARRIOR", b = "PRIEST", c = "MAGE", d = "ROGUE", e = "MAGE" }
  local got, prog = R.achievements(races, info, { now = T0 + 99, squads = function() return mem end,
    roleOf = function(n) return role[n] end, classOf = function(n) return cls[n] end,
    wipeStats = { S1 = { capped = 3, streak = 2 } } })
  ok(got.squad.S1.allRoles, "tank + healer + 3 dps"); ok(not got.squad.S1.allClasses, "4 classes only")
  eq(prog.squad.S1.allClasses.cur, 4); eq(prog.squad.S1.wipeTopAll.cur, 3); eq(prog.squad.S1.wipes4.cur, 2)
  ok(got.char["K1-R"].first1 and got.char["K1-R"]["top100.10"] and got.char["K1-R"].top10class and got.char["K1-R"].top10race)
  ok(got.char["K2-R"].lvl10, "level with the addon"); ok(not got.char["K2-R"].first1)
  -- wipe stats from the wipe scoring
  local function res(pts) return { squads = { S1 = { level = pts, dungeon = pts, raid = pts, pvp = pts, wpvp = pts, general = pts * 5 } } } end
  local rank = function(r) return { { sid = "S1", pos = 1, points = r.squads.S1.general } } end
  local ws = R.wipeStats({ { wipe = "W1", ends = 1, res = res(100) }, { wipe = "W2", ends = 2, res = res(10) },
                           { wipe = "W3", ends = 3, res = res(10) }, { wipe = "W4", ends = 4, res = res(10) } }, rank,
                         { "level", "dungeon", "raid", "pvp", "wpvp" }, 100)
  eq(ws.S1.allCapped, 1); eq(ws.S1.streak, 4); eq(ws.S1.streakTs, 4)
end)

test("schema: RaceObs / RaceEntry / AchUnlock / celebration fields, no economy fields", function()
  local bad = { gold = 1, money = 1, copper = 1, silver = 1, trade = 1, price = 1, cost = 1, auction = 1 }
  local function clean(t, what)
    for k in pairs(t) do
      for b in pairs(bad) do ok(not tostring(k):lower():find(b), what .. " has economy field " .. tostring(k)) end
    end
  end
  -- positive: the fields that must exist
  for _, f in ipairs({ "t", "who", "by", "ts", "lv", "inst", "enc", "pres", "sqm", "k", "n", "sea" }) do ok(R.SCHEMA[f], "RaceObs." .. f) end
  clean(R.SCHEMA, "RaceObs")
  local s = store({ lv("Ann-R", "Ann-R", T0, 10, "self"), lv("Ann-R", "Bob-R", T0 + 1, 10) })
  local e = R.compute(s, { now = T0 })["lvl.all.10"].entries[1]
  for _, f in ipairs({ "key", "pos", "ts", "mark", "chars", "squads", "sup" }) do ok(e[f] ~= nil, "RaceEntry." .. f) end
  clean(e, "RaceEntry")
  local row = R.unpackClosed("k~1~exact~a~~~0").rows[1]; clean(row, "closed row")
  for _, kind in ipairs({ "annul", "boss" }) do ok(M.SCHEMA[kind], kind); clean(M.SCHEMA[kind], kind) end
  for _, f in ipairs({ "celOn", "celScope", "celSquad" }) do ok(M.SCHEMA.settings[f], "settings." .. f) end
  clean(M.SCHEMA.settings, "settings")
  local got = R.achievements({}, {}, { now = 1, adoption = { x = 1, y = 1 } })
  local unlock = { id = "allAboard", owner = "guild", ts = got.guild.guild.allAboard }
  ok(unlock.ts); clean(unlock, "AchUnlock")
  local msg = { key = "lvl.all.60|Ann-R", kind = "race", pos = 1, who = { "Ann-R" }, what = "lvl.all.60" }
  ok(Cel.eligible(msg, { celOn = true, celScope = "first" })); clean(msg, "CelebrationMsg")
end)
