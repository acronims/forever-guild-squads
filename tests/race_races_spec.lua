-- 2.0.1: races by race (lvl.race.<RACE>.<H>). BRO 12-nov-2026: «las carreras por raza no están funcionando».
-- Pure Core: no WoW API. The race token comes from UnitRace (self report only: the guild roster has no race),
-- so a token outside R.RACE_OK (Skyborne, the new Forever race) had a single reporter and never opened.
local R = NS.Races
local T0 = 1795000000
local function lv(who, by, ts, level, src, cls, race)
  return { t = "lv", who = who, by = by, ts = ts, lv = level, src = src, cls = cls, race = race }
end
local function store(list)
  local s = R.newStore()
  for _, ev in ipairs(list) do local okA, why = R.add(s, ev); assert(okA, "add: " .. tostring(why)) end
  return s
end
-- the client's race table (C_CreatureInfo.GetRaceInfo): ids 1..N, with gaps; Skyborne's token is unknown, so the
-- fixture uses two made-up ones (the two Skyborne variants) to prove nothing depends on its spelling
local INFO = {
  [1] = { raceName = "Humano", clientFileString = "Human", raceID = 1 },
  [2] = { raceName = "Orco", clientFileString = "Orc", raceID = 2 },
  [5] = { raceName = "No-muerto", clientFileString = "Scourge", raceID = 5 },
  [91] = { raceName = "Altonato (Alta Orden)", clientFileString = "SkyborneHighOrder", raceID = 91 },
  [92] = { raceName = "Altonato (Ventolera)", clientFileString = "SkyborneWindshaper", raceID = 92 },
}
local function getInfo(id) return INFO[id] end

test("race races: a whitelisted race opens with the player's own report + one roster witness (control)", function()
  local s = store({ lv("Ann-R", "Ann-R", T0, 10, "self", "WARRIOR", "Human"), lv("Ann-R", "Bob-R", T0 + 30, 10, "roster") })
  local r = R.compute(s, { now = T0 + 99 })["lvl.race.HUMAN.10"]
  ok(r and r.entries[1] and r.entries[1].key == "Ann-R", "Human Top 10 at 10")
  eq(r.entries[1].mark, "exact")
end)

test("race races: the first Skyborne to reach a level is listed (client race table, one reporter)", function()
  local s = store({ lv("Sky-R", "Sky-R", T0, 10, "self", "MAGE", "SkyborneHighOrder"), lv("Sky-R", "Bob-R", T0 + 30, 10, "roster") })
  local ctx = { now = T0 + 99, raceOk = R.knownRaces(getInfo) }
  local r = R.compute(s, ctx)["lvl.race.SKYBORNEHIGHORDER.10"]
  ok(r and r.entries[1] and r.entries[1].key == "Sky-R", "Skyborne Top 10 at 10 (was: no race until a 2nd Skyborne)")
  ok(R.compute(s, ctx)["lvl.all.10"].entries[1], "the level race too")
end)

test("race races: R.knownRaces reads the client's race table (gaps, bad rows, no API)", function()
  local k = R.knownRaces(getInfo)
  ok(k.HUMAN and k.ORC and k.SCOURGE and k.SKYBORNEHIGHORDER and k.SKYBORNEWINDSHAPER, "every row, upper slug")
  local n = 0; for _ in pairs(k) do n = n + 1 end
  eq(n, 5, "only real rows")
  eq(next(R.knownRaces(nil)), nil, "no API -> empty")
  eq(next(R.knownRaces(function() error("boom") end)), nil, "an erroring API -> empty")
  eq(next(R.knownRaces(function() return { clientFileString = 7 } end)), nil, "a bad row -> skipped")
  eq(R.raceLabels(getInfo).SKYBORNEWINDSHAPER, "Altonato (Ventolera)", "the client's own localized name")
end)

test("race races: junk tokens still need 2 reporters (the client table does not whitelist them)", function()
  local s = store({ lv("Eve-R", "Eve-R", T0, 10, "self", "WARRIOR", "JUNKRACE"), lv("Eve-R", "Bob-R", T0 + 5, 10, "roster") })
  local races = R.compute(s, { now = T0 + 99, raceOk = R.knownRaces(getInfo) })
  ok(not races["lvl.race.JUNKRACE.10"], "unknown race key: no race")
end)

test("race races: the Raza filter lists the open races of the guild's races before anyone reaches a level", function()
  local races = R.compute(R.newStore(), { now = T0, classes = { "WARRIOR" }, races = { "Human", "SkyborneHighOrder", "JUNK" },
                                          raceOk = R.knownRaces(getInfo) })
  ok(races["lvl.class.WARRIOR.10"], "class rows exist (control)")
  ok(races["lvl.race.HUMAN.10"] and races["lvl.race.HUMAN.60"], "Human rows, 10..60")
  ok(races["lvl.race.SKYBORNEHIGHORDER.30"], "Skyborne rows")
  ok(not races["lvl.race.JUNK.10"], "a junk profile race makes no row")
  local list = R.list(races, "race")
  ok(#list >= 12, "Raza filter not empty: " .. #list)
end)

-- review 2.0.1 H3/H5: the race table must not depend on Skyborne's id, and two rows with one name stay apart
test("race races: ids over 200 are read (the scan goes on while rows keep coming), and it always ends", function()
  local info = { [1] = { raceName = "Humano", clientFileString = "Human" },
                 [201] = { raceName = "Skyborne", clientFileString = "Skyborne" },
                 [290] = { raceName = "Skyborne", clientFileString = "SkyborneB" } }
  local k = R.knownRaces(function(id) return info[id] end)
  ok(k.HUMAN and k.SKYBORNE and k.SKYBORNEB, "ids 201 and 290 read")
  local s = store({ lv("Sky-R", "Sky-R", T0, 10, "self", "MAGE", "Skyborne"), lv("Sky-R", "Bob-R", T0 + 5, 10, "roster") })
  ok(R.compute(s, { now = T0 + 99, raceOk = k })["lvl.race.SKYBORNE.10"], "Skyborne at id 201 opens")
  local calls = 0
  R.knownRaces(function() calls = calls + 1; return { clientFileString = "Same" } end)
  ok(calls <= R.RACE_ID_MAX, "an API that answers every id stops at the cap: " .. calls)
  calls = 0
  R.knownRaces(function() calls = calls + 1 end)
  ok(calls <= R.RACE_ID_SCAN, "an empty table is not scanned to the cap: " .. calls)
end)

test("race races: two tokens with the same client name get two different labels", function()
  local info = { [91] = { raceName = "Skyborne", clientFileString = "SkyborneA" }, [92] = { raceName = "Skyborne", clientFileString = "SkyborneB" },
                 [1] = { raceName = "Humano", clientFileString = "Human" } }
  local lab = R.raceLabels(function(id) return info[id] end)
  ok(lab.SKYBORNEA and lab.SKYBORNEB and lab.SKYBORNEA ~= lab.SKYBORNEB, "distinct: " .. tostring(lab.SKYBORNEA) .. " / " .. tostring(lab.SKYBORNEB))
  ok(lab.SKYBORNEA:find("Skyborne", 1, true) == 1, "still starts with the client's name")
  eq(lab.HUMAN, "Humano", "a unique name is left alone")
end)
