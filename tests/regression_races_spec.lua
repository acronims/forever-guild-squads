-- Regression tests: races and celebrations. Each test asserts the CORRECT behaviour.
local M, R, Cel, C = NS.Model, NS.Races, NS.Celebrate, NS.Content
local roster = makeRoster({ ["Gm-R"] = 0, ["Off-R"] = 1, ["Ali-R"] = 5, ["Bob-R"] = 5, ["Cid-R"] = 5, ["Eve-R"] = 7,
                            ["Dan-R"] = 5, ["Fay-R"] = 5, ["Gus-R"] = 5 })
local T0 = 1795000000
local DAY = 86400

-- a forged GM settings record with a colliding hash is refused (relays need a GM/officer)
test("forged GM settings with a colliding version hash are refused", function()
  local st = M.newState()
  local real = { k = "settings", id = "settings", a = "Gm-R", ts = T0, sq = 1, d = { squadsEnabled = true } }
  ok(M.apply(st, real, { roster = roster }))
  local ann = {}
  for _, h in ipairs(M.announce(st, "Gm-R", 40)) do ann[h] = true end
  -- sq found by brute force offline: 34657359 with exact arithmetic (WoW Lua 5.1 doubles),
  -- 1367654 under fengari's 32-bit integers (the test VM wraps h1 * 31)
  local exact = (2147483647 * 31) % 2147483647 == 0
  local forged = { k = "settings", id = "settings", a = "Gm-R", ts = T0 + 200, sq = exact and 34657359 or 1367654,
                   d = { squadsEnabled = false, compEnabled = false } }
  eq(M.versionHash(forged), M.versionHash(real), "precondition: collision found offline")
  local okA = M.apply(st, forged, { roster = roster, sender = "Eve-R", now = T0 + 200,
                                    announced = function(a, h) return a == "Gm-R" and ann[h] == true end })
  ok(not okA, "Eve relayed a forged GM settings record (squads disabled) and it was applied")
end)

-- a backdated self level report cannot take #1 with an exact mark
test("a backdated self level report cannot take #1 with mark exact", function()
  local s = R.newStore()
  -- honest Ali reaches 60 at T0 (self + roster witness)
  ok(R.add(s, { t = "lv", who = "Ali-R", by = "Ali-R", ts = T0, src = "self", lv = 60 }))
  ok(R.add(s, { t = "lv", who = "Ali-R", by = "Bob-R", ts = T0 + 30, src = "roster", lv = 60 }))
  -- Eve sends a self report dated 30 days earlier; Bob's client honestly reports her real level-up at T0+DAY
  ok(R.add(s, { t = "lv", who = "Eve-R", by = "Eve-R", ts = T0 - 30 * DAY, src = "self", lv = 60 }))
  ok(R.add(s, { t = "lv", who = "Eve-R", by = "Bob-R", ts = T0 + DAY, src = "roster", lv = 60 }))
  local races = R.compute(s, { now = T0 + DAY + 60 })
  local top = races["lvl.all.60"].entries[1]
  eq(top.key, "Ali-R", "Eve is #1 of lvl.all.60 with ts " .. tostring(top.ts) .. " mark " .. tostring(top.mark))
end)

-- squad credit in a boss kill needs corroboration from more than one witness
test("a second reporter cannot inject an absent squad into a boss kill", function()
  local s = R.newStore()
  local honest = { t = "kill", who = "Ali-R", by = "Ali-R", ts = T0, inst = "Foo Keep", it = "raid", enc = 9001,
                   pres = { "Ali-R", "Bob-R", "Cid-R" }, sqm = { "Ali-R>S1", "Bob-R>S1", "Cid-R>S1" } }
  local honest2 = { t = "kill", who = "Bob-R", by = "Bob-R", ts = T0 + 2, inst = "Foo Keep", it = "raid", enc = 9001,
                    pres = { "Ali-R", "Bob-R", "Cid-R" }, sqm = { "Ali-R>S1", "Bob-R>S1", "Cid-R>S1" } }
  -- Eve was not there; she copies the enc/ts she saw on the wire and claims her squad S9 (3 names)
  local inject = { t = "kill", who = "Eve-R", by = "Eve-R", ts = T0 + 5, inst = "Foo Keep", it = "raid", enc = 9001,
                   pres = { "Eve-R", "Dan-R", "Fay-R" }, sqm = { "Eve-R>S9", "Dan-R>S9", "Fay-R>S9" } }
  ok(R.add(s, honest)); ok(R.add(s, honest2)); ok(R.add(s, inject))
  local races = R.compute(s, { now = T0 + 600 })
  local id
  for rid in pairs(races) do if rid:find("^raid%..*%.9001$") then id = rid end end
  ok(id, "race created")
  local e = races[id].entries[1]
  for _, sid in ipairs(e.squads) do ok(sid ~= "S9", "absent squad S9 shares #1 of " .. id .. ": " .. e.key) end
end)

-- closed races converge whatever the arrival order of the catch-up pages
test("closed races converge regardless of arrival order (partial catch-up)", function()
  local evs = {}
  for i = 1, 11 do
    evs[i] = { t = "cnt", who = ("P%02d-R"):format(i), by = ("P%02d-R"):format(i), ts = T0 + (11 - i) * 60, k = "hk", n = 100 }
  end
  local a, b = R.newStore(), R.newStore()
  for i = 1, 11 do R.add(a, evs[i]) end
  R.compute(a, { now = T0 + DAY })
  for i = 1, 10 do R.add(b, evs[i]) end
  R.compute(b, { now = T0 + DAY })   -- page 1 arrived, UI/timer recomputed -> pvp.hk.100 frozen
  R.add(b, evs[11])                  -- the earliest one arrives on page 2
  local ra, rb = R.compute(a, { now = T0 + DAY }), R.compute(b, { now = T0 + DAY })
  local function keys(r) local o = {} for _, e in ipairs(r["pvp.hk.100"].entries) do o[#o + 1] = e.key end return table.concat(o, ",") end
  eq(keys(rb), keys(ra), "clients froze different Tops")
end)

-- every client elects the same announcer for the same event, even with empty hello maps
test("two clients elect the same announcer for the same event", function()
  local function ctxFor(me, heard)
    local users = {}
    for n in pairs(heard) do users[#users + 1] = n end
    users[#users + 1] = me
    return { hasAddon = function(n) return n == me or heard[n] == true end, online = function() return true end,
             rank = function(n) return (roster(n) or {}).rank end, users = users }
  end
  local prot = { "Ali-R" }
  local x = Cel.announcer(prot, ctxFor("Ali-R", { ["Bob-R"] = true }))   -- the protagonist
  local y = Cel.announcer(prot, ctxFor("Bob-R", {}))                      -- Bob never heard Ali's hello
  local z = Cel.announcer(prot, ctxFor("Cid-R", {}))
  eq(y, x, "Bob also announces"); eq(z, x, "Cid also announces")
end)

-- unknown profession / reputation keys do not create races
test("unknown profession keys do not create races", function()
  local s = R.newStore()
  for i = 1, 300 do R.add(s, { t = "cnt", who = "Eve-R", by = "Eve-R", ts = T0 + i, k = "prof", key = "junk" .. i, n = 300 }) end
  local races = R.compute(s, { now = T0 + DAY })
  local n = 0
  for id in pairs(races) do if id:find("^prof%.junk") then n = n + 1 end end
  eq(n, 0, "junk profession races created")
end)

-- bosses taught by a non-GM do not block raid completion
test("fake bosses taught by a non-GM do not block raid completion", function()
  local st = M.newState()
  M.apply(st, { k = "settings", id = "settings", a = "Gm-R", ts = T0 - 10, sq = 1, d = { squadsEnabled = true } }, { roster = roster })
  for i = 1, 6 do
    local okB, why = M.apply(st, { k = "boss", id = "barrow.fake" .. i, a = "Eve-R", ts = T0 + i, sq = 1,
                                   d = { inst = "barrow", name = "fake" .. i, kind = "raid" } }, { roster = roster })
    ok(okB, "precondition: boss record accepted " .. tostring(why))
    C.learnBoss("barrow", nil, "fake" .. i, "raid")
  end
  local b1 = C.learnBoss("barrow", 7001, "First", "raid")
  local b2 = C.learnBoss("barrow", 7002, "Last", "raid")
  C.setFinal(b2.id, true)
  local s = R.newStore()
  local sqm = { "Ali-R>S1", "Bob-R>S1", "Cid-R>S1" }
  for i, enc in ipairs({ 7001, 7002 }) do
    for j, by in ipairs({ "Ali-R", "Bob-R" }) do
      R.add(s, { t = "kill", who = by, by = by, ts = T0 + i * 600 + j, inst = "Barrow Deeps", it = "raid", enc = enc,
                 pres = { "Ali-R", "Bob-R", "Cid-R" }, sqm = sqm })
    end
  end
  local races = R.compute(s, { now = T0 + DAY, isFinal = C.isFinal, hasFinal = C.hasFinal, bossesOf = C.bossesOf })
  local e = races["raid.barrow"].entries[1]
  ok(e and #e.squads == 1 and e.squads[1] == "S1", "S1 cleared every real boss but raid.barrow has no squad entry: "
     .. tostring(e and e.key))
end)

-- a relayed closed race must be complete
test("a relayed closed race must be complete", function()
  local s = R.newStore()
  ok(not R.importClosed(s, "pvp.hk.100", "Eve-R~1~self~Eve-R~~~0", T0), "1-row 'closed' Top 10 imported and frozen")
end)
