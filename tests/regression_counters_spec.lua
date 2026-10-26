-- Regression tests: guarded counters, backdated kills and celebration claims. Each test asserts the CORRECT behaviour.
local R, Cel = NS.Races, NS.Celebrate
local T0 = 1795000000
local DAY = 86400

local function cnt(k, n, ts, key, by)
  return { t = "cnt", who = by or "Ali-R", by = by or "Ali-R", ts = ts, k = k, key = key, n = n }
end

-- an HK step crossed while the queue is blocked for a whole battleground is accepted when the match ends
test("a HK step crossed early in a 30-min battleground is accepted when the match ends", function()
  local crossed = T0
  local delivered = T0 + 30 * 60 -- PVP_MATCH_COMPLETE unblocks the queue
  ok(R.liveCounterOk(cnt("hk", 100, crossed), delivered),
     "legit HK step delayed by the PvP-match queue block is refused by every receiver")
end)

-- a fast but plausible profession session is accepted
test("a profession levelled 150 -> 225 in 15 minutes is accepted", function()
  local s = R.newStore()
  ok(R.add(s, cnt("prof", 150, T0, "first_aid"), T0), "150")
  local okA, why = R.add(s, cnt("prof", 225, T0 + 900, "first_aid"), T0 + 900)
  ok(okA, "legit 225 refused: " .. tostring(why))
end)

-- a first-ever counter reading that crosses every step at once is the unscored baseline
test("a first-ever HK reading of 5000 (all steps at once) is refused", function()
  local s = R.newStore()
  local now = T0
  local a = R.add(s, cnt("hk", 100, now, nil, "Eve-R"), now)
  local b = R.add(s, cnt("hk", 1000, now, nil, "Eve-R"), now)
  local c = R.add(s, cnt("hk", 5000, now, nil, "Eve-R"), now)
  ok(not (a and b and c), "forged HK 100/1000/5000 accepted in one go (no earlier reading needed)")
end)

-- kills backdated by colluding members stay unverified and never take #1
test("a kill backdated 30 days by three colluding members does not take #1", function()
  local s = R.newStore()
  local function kill(by, ts, sid, names)
    local sqm = {}
    for _, n in ipairs(names) do sqm[#sqm + 1] = n .. ">" .. sid end
    return { t = "kill", who = by, by = by, ts = ts, inst = "Foo Keep", it = "raid", enc = 9001, pres = names, sqm = sqm }
  end
  local honest = { "Ali-R", "Bob-R", "Cid-R" }
  for i, n in ipairs(honest) do ok(R.add(s, kill(n, T0 + i, "S1", honest), T0 + 10)) end
  local evil = { "Eve-R", "Dan-R", "Fay-R" }
  for i, n in ipairs(evil) do ok(R.add(s, kill(n, T0 - 30 * DAY + i, "S9", evil), T0 + 10)) end
  local races = R.compute(s, { now = T0 + 3600 })
  local id
  for rid in pairs(races) do if rid:find("^raid%..*%.9001$") then id = rid end end
  ok(id, "race created")
  local e = races[id].entries[1]
  ok(e and e.squads and e.squads[1] == "S1", "backdated colluders are #1 of " .. id .. ": " .. tostring(e and e.key))
end)

-- a claim delayed in the outgoing queue never yields two announcers
test("a delayed claim never yields two announcers", function()
  local a, b = Cel.newClaims(), Cel.newClaims()
  local k = "lvl.all.60|Zed-R"
  Cel.noteClaim(a, k, "Zed-R", 6)     -- A (preferred) claims; CL stuck in A's queue
  Cel.noteClaim(b, k, "Abe-R", 8)     -- B (backup) heard nothing yet, claims
  Cel.noteClaim(a, k, "Abe-R", 8.5)   -- A hears B
  Cel.noteClaim(b, k, "Zed-R", 9)     -- B finally hears A
  local wa, wb = Cel.claimWinner(a, k), Cel.claimWinner(b, k)
  ok(not (wa == "Zed-R" and wb == "Abe-R"), "both clients think they won: A=" .. tostring(wa) .. " B=" .. tostring(wb))
end)

-- a claim that is never followed by an announcement does not silence the celebration
test("a claim that is never followed by an announcement does not silence the celebration", function()
  local book = Cel.newClaims()
  local k = "lvl.all.60|Ali-R"
  Cel.noteClaim(book, k, "Eve-R", 1)  -- Eve's /run: SendAddonMessage CL for every new entry
  ok(not Cel.claimed(book, k), "Eve's bare claim cancels every announcer (Hall.lua:468)")
end)
