-- The GM manages the catalog of achievements and races. Pure Core tests: `achdef` / `achgrant` records and
-- R.def / R.list applying the catalog.
local M, R, Pr = NS.Model, NS.Races, NS.Progress
local Cat = NS.Catalog

local GM, OFF, MEM, MEM2 = "Gm-R", "Of-R", "Mb-R", "Mb2-R"
local ranks = { [GM] = 0, [OFF] = 1, [MEM] = 5, [MEM2] = 5, ["W-R"] = 5 }
for i = 1, 12 do ranks["P" .. i .. "-R"] = 5 end
local roster = makeRoster(ranks)
local T = 1800000000
local seq = 0
local function rec(kind, id, a, ts, d) seq = seq + 1; return { k = kind, id = id, a = a, ts = ts, sq = seq, d = d } end
local function apply(state, r, sender) return M.apply(state, r, { roster = roster, sender = sender }) end
local function fresh()
  local st = M.newState()
  if Cat then Cat.use(st); Cat.sizeGuard = nil end
  return st
end
-- a level milestone reached by `who` (self report) and confirmed by the roster witness W-R (exact time)
local function level(store, who, lv, ts, cls)
  R.add(store, { t = "lv", who = who, by = who, ts = ts, src = "self", lv = lv, cls = cls })
  R.add(store, { t = "lv", who = who, by = "W-R", ts = ts + 5, src = "roster", lv = lv, cls = cls })
end
local function compute(store, st, extra)
  local ctx = { now = T + 10 * 86400, achdefs = st.achdefs or {} }
  for k, v in pairs(extra or {}) do ctx[k] = v end
  return R.compute(store, ctx)
end
local function keys(r) local o = {} for _, e in ipairs(r.entries) do o[#o + 1] = e.key end return table.concat(o, ",") end
local function listed(races, cat, id) for _, r in ipairs(R.list(races, cat)) do if r.id == id then return true end end return false end
local function nobs(store) local n = 0 for _ in pairs(store.obs) do n = n + 1 end return n end

-------------------------------------------------------------------------------
test("achdef{on=false} hides the race in R.list; observations stay; on=true brings it back with the same entries", function()
  local st, store = fresh(), R.newStore()
  for i = 1, 3 do level(store, "P" .. i .. "-R", 10, T + i * 60) end
  local races = compute(store, st)
  ok(listed(races, "level", "lvl.all.10"), "listed before")
  local before = keys(races["lvl.all.10"])
  eq(#races["lvl.all.10"].entries, 3, "3 entries")
  local n0 = nobs(store)
  local okA, why = apply(st, rec("achdef", "lvl.all.10", GM, T + 1000, { on = false }))
  ok(okA, "GM achdef applied: " .. tostring(why))
  races = compute(store, st)
  ok(not listed(races, "level", "lvl.all.10"), "hidden in R.list")
  eq(nobs(store), n0, "observations untouched")
  eq(keys(races["lvl.all.10"]), before, "it keeps counting (D1)")
  ok(R.legacyList and #R.legacyList(races, "level") == 1, "shown under Legado (has entries)")
  -- a 4th character keeps counting while it is off
  level(store, "P4-R", 10, T + 2000)
  ok(apply(st, rec("achdef", "lvl.all.10", GM, T + 3000, { on = true })), "re-enabled")
  races = compute(store, st)
  ok(listed(races, "level", "lvl.all.10"), "listed again")
  eq(keys(races["lvl.all.10"]), before .. ",P4-R", "same entries (+ the one earned while hidden)")
end)

test("achievements: a disabled achievement is hidden, the one already earned goes to Legado", function()
  local st = fresh()
  ok(apply(st, rec("achdef", "hallOfFame", GM, T, { on = false })), "GM disables hallOfFame")
  ok(apply(st, rec("achdef", "allRoles", GM, T + 1, { on = false })), "GM disables allRoles")
  local shown, legacy = Cat.splitLegacy({ { key = "hallOfFame", ts = T - 50 }, { key = "allRoles" }, { key = "first60", ts = T - 10 } }, st.achdefs)
  eq(#shown, 1, "only first60 shown"); eq(shown[1].key, "first60")
  eq(#legacy, 1, "earned + disabled -> legacy"); eq(legacy[1].key, "hallOfFame"); eq(legacy[1].legacy, true)
end)

-------------------------------------------------------------------------------
test("achdef / achgrant written by an officer or a member are refused (live and relayed)", function()
  local st = fresh()
  local _, w1 = apply(st, rec("achdef", "lvl.all.10", OFF, T, { on = false }), OFF)
  eq(w1, "denied", "officer, live")
  local _, w2 = apply(st, rec("achdef", "lvl.all.10", MEM, T, { on = false }), MEM)
  eq(w2, "denied", "member, live")
  local _, w3 = apply(st, rec("achdef", "lvl.all.10", MEM, T, { on = false }), OFF)
  eq(w3, "denied", "member's record relayed by an officer")
  local _, w4 = apply(st, rec("achdef", "lvl.all.10", GM, T, { on = false }), MEM)
  eq(w4, "relay", "GM's record relayed by a member (or forged with a = GM)")
  local _, w5 = apply(st, rec("achgrant", "first60|" .. MEM, OFF, T, { ach = "first60", who = MEM, reason = "x", on = true }), OFF)
  eq(w5, "denied", "achgrant by an officer")
  eq(next(st.achdefs or {}), nil, "nothing stored"); eq(next(st.achgrants or {}), nil)
  local okG = apply(st, rec("achdef", "lvl.all.10", GM, T, { on = false }), OFF)
  ok(okG, "GM record relayed by an officer is fine")
end)

-------------------------------------------------------------------------------
test("size: open race with 3 entries takes size=5 and closes at the 5th; 2 and 11 refused; closed = refused, snapshot unchanged", function()
  local st, store = fresh(), R.newStore()
  local id = "lvl.class.WARRIOR.10"
  for i = 1, 3 do level(store, "P" .. i .. "-R", 10, T + i * 60, "WARRIOR") end
  local races = compute(store, st, { syncing = true })
  eq(#races[id].entries, 3); eq(races[id].size, 10)
  if Cat then Cat.sizeGuard = Cat.guardFor(store, races) end
  ok(apply(st, rec("achdef", id, GM, T + 1000, { size = 5 })), "size 5 accepted")
  local okS, wS = apply(st, rec("achdef", id, GM, T + 1001, { size = 2 }))
  ok(not okS and wS == "catEntries", "size 2 refused (below its 3 entries): " .. tostring(wS))
  local okB, wB = apply(st, rec("achdef", "dng.ragefire_chasm.9901", GM, T + 1002, { size = 11 }))
  ok(not okB and wB == "catSize", "size 11 on dng.* refused: " .. tostring(wB))
  eq(st.achdefs[id].d.size, 5, "the stored size is 5")
  level(store, "P4-R", 10, T + 2000, "WARRIOR")
  races = compute(store, st, { syncing = true })
  eq(races[id].state, "open"); eq(races[id].size, 5)
  level(store, "P5-R", 10, T + 2100, "WARRIOR")
  level(store, "P6-R", 10, T + 2200, "WARRIOR")
  races = compute(store, st)   -- quiet: closed races are frozen
  eq(races[id].state, "closed", "closes at the 5th entry"); eq(#races[id].entries, 5)
  ok(store.closed[id], "frozen snapshot")
  local snap = R.packClosed(store.closed[id])
  if Cat then Cat.sizeGuard = Cat.guardFor(store, races) end
  local okC, wC = apply(st, rec("achdef", id, GM, T + 3000, { size = 7 }))
  ok(not okC and wC == "catClosed", "size change on a closed race refused: " .. tostring(wC))
  eq(st.achdefs[id].d.size, 5)
  races = compute(store, st)
  eq(R.packClosed(store.closed[id]), snap, "snapshot unchanged, byte for byte")
  eq(#races[id].entries, 5)
  -- toggling a closed race (same size) is still allowed
  ok(apply(st, rec("achdef", id, GM, T + 3100, { size = 5, on = false })), "on/off of a closed race allowed")
  if Cat then Cat.sizeGuard = nil end
end)

test("deterministic Top size on a client without the guard (floor = entries at the change, closed = keeps its size)", function()
  local st, store = fresh(), R.newStore()
  local id = "lvl.class.MAGE.10"
  for i = 1, 3 do level(store, "P" .. i .. "-R", 10, T + i * 60, "MAGE") end
  ok(apply(st, rec("achdef", id, GM, T + 1000, { size = 2 })), "no guard: accepted")
  level(store, "P4-R", 10, T + 2000, "MAGE")
  local races = compute(store, st, { syncing = true })
  eq(races[id].size, 3, "never below the 3 entries it had"); eq(races[id].state, "closed")
  -- a race already full with its family size before the change keeps it
  local st2, store2 = fresh(), R.newStore()
  local id2 = "lvl.class.ROGUE.10"
  for i = 1, 11 do level(store2, "P" .. i .. "-R", 10, T + i * 60, "ROGUE") end
  ok(apply(st2, rec("achdef", id2, GM, T + 5000, { size = 3 })))
  races = compute(store2, st2, { syncing = true })
  eq(races[id2].size, 10, "closed before the change: 10"); eq(#races[id2].entries, 10)
  ok(R.importClosed(R.newStore(), id2, R.packClosed({ rows = (function() local o = {} for i, e in ipairs(races[id2].entries) do o[i] = e end return o end)() }), 0, st2.achdefs) == false,
     "a 10-row snapshot vs an effective size of 3 (catalog) is refused by importClosed")
end)

-------------------------------------------------------------------------------
test("name: 40 characters are cut, |c / |H codes cleaned; the replicated id never changes", function()
  local st = fresh()
  local long = string.rep("abcdefghij", 4)
  ok(apply(st, rec("achdef", "lvl.all.20", GM, T, { name = long })))
  local n = st.achdefs["lvl.all.20"].d.name
  ok(#n <= 32, "cut to 32 bytes: " .. #n)
  ok(apply(st, rec("achdef", "lvl.all.30", GM, T, { name = "|cffff0000Rojo|r |Hitem:19019|h[Espada]|h" })))
  eq(st.achdefs["lvl.all.30"].d.name, "Rojo [Espada]", "codes removed")
  ok(apply(st, rec("achdef", "lvl.all.40", GM, T, { name = "Señor de la niebla ñññññññññññññ" })))
  local u = st.achdefs["lvl.all.40"].d.name
  ok(#u <= 32 and not u:find("[\195]$"), "UTF-8 safe cut: " .. u)
  eq(st.achdefs["lvl.all.30"].id, "lvl.all.30", "id unchanged")
  local races = R.compute(R.newStore(), { now = T, achdefs = st.achdefs })
  eq(races["lvl.all.30"].id, "lvl.all.30"); eq(races["lvl.all.30"].label, "Rojo [Espada]", "label applied")
  local okBad = apply(st, rec("achdef", "bad|id", GM, T, { on = false }))
  ok(not okBad, "an id with | is refused")
end)

-------------------------------------------------------------------------------
test("custom prof 'primeros 3 en 300 de herrería' from existing prof observations", function()
  local st, store = fresh(), R.newStore()
  for i = 1, 4 do   -- baseline 100 (never scored), then 300 later at a plausible pace
    local who = "P" .. i .. "-R"
    R.add(store, { t = "cnt", who = who, by = who, ts = T, k = "prof", key = "Herrería", n = 100 })
    R.add(store, { t = "cnt", who = who, by = who, ts = T + 4000 + i * 100, k = "prof", key = "Herrería", n = 300 })
  end
  local okA, why = apply(st, rec("achdef", "gm.herreros", GM, T - 10, { custom = true, metric = "prof", param = "Herrería",
                                                                       thr = 300, size = 3, name = "Primeros 3 herreros" }))
  ok(okA, "custom created: " .. tostring(why))
  local races = compute(store, st)
  local r = races["gm.herreros"]
  ok(r, "custom race computed")
  eq(keys(r), "P1-R,P2-R,P3-R", "the first three"); eq(r.state, "closed"); eq(r.size, 3)
  eq(r.label, "Primeros 3 herreros")
end)

test("custom boss needs >= 2 witnesses; custom rep without API -> nodata, no error", function()
  local st, store = fresh(), R.newStore()
  local ev = { t = "kill", who = "P1-R", by = "P1-R", ts = T, it = "party", inst = "Ragefire Chasm", enc = 9901,
               pres = { "P1-R", "P2-R" }, sqm = {} }
  local clean = R.sanitize(ev)
  local param = R.instKey(clean) .. "." .. R.bossSlug(clean)
  ok(apply(st, rec("achdef", "gm.ragefire", GM, T - 10, { custom = true, metric = "boss", param = param, size = 5, name = "Ragefire" })))
  R.add(store, ev)
  local races = compute(store, st)
  eq(#races["gm.ragefire"].entries, 0, "one report: no entry")
  R.add(store, { t = "kill", who = "P2-R", by = "P2-R", ts = T + 20, it = "party", inst = "Ragefire Chasm", enc = 9901,
                 pres = { "P1-R", "P2-R" }, sqm = {} })
  races = compute(store, st)
  eq(#races["gm.ragefire"].entries, 1, "two witnesses: one entry")
  eq(races["gm.ragefire"].entries[1].wit, 2)
  ok(apply(st, rec("achdef", "gm.exaltados", GM, T, { custom = true, metric = "rep", param = "Darnassus", thr = 8, size = 3 })))
  local okC, res = pcall(compute, store, st, { nodata = { rep = true, prof = true } })
  ok(okC, "no error: " .. tostring(res))
  eq(res["gm.exaltados"].state, "nodata", "pending data")
end)

-------------------------------------------------------------------------------
test("at most 50 custom achievements: the 51st is refused", function()
  local st = fresh()
  for i = 1, 50 do
    local okA, why = apply(st, rec("achdef", "gm.c" .. i, GM, T + i, { custom = true, metric = "manual", name = "C" .. i }))
    ok(okA, "custom " .. i .. ": " .. tostring(why))
  end
  local okX, wX = apply(st, rec("achdef", "gm.c51", GM, T + 99, { custom = true, metric = "manual", name = "C51" }))
  ok(not okX and wX == "maxCustom", "51st refused: " .. tostring(wX))
  ok(apply(st, rec("achdef", "gm.c7", GM, T + 100, { custom = true, metric = "manual", name = "C7 bis" })), "editing one of the 50 is fine")
  ok(apply(st, rec("achdef", "lvl.all.10", GM, T + 101, { on = false })), "built-in entries do not count")
end)

-------------------------------------------------------------------------------
test("achgrant: GM + reason grants; no reason refused; on=false withdraws and stays; never a Top entry", function()
  local st, store = fresh(), R.newStore()
  for i = 1, 3 do level(store, "P" .. i .. "-R", 10, T + i * 60) end
  local function topText(races)
    local ids, out = {}, {}
    for id in pairs(races) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do out[#out + 1] = id .. "=" .. keys(races[id]) end
    return table.concat(out, ";")
  end
  local before = topText(compute(store, st))
  local _, wR = apply(st, rec("achgrant", "first60|" .. MEM, GM, T, { ach = "first60", who = MEM, reason = "   ", on = true }))
  eq(wR, "reason", "no reason refused")
  local okG, why = apply(st, rec("achgrant", "first60|" .. MEM, GM, T + 1, { ach = "first60", who = MEM, reason = "evento", on = true }))
  ok(okG, "granted: " .. tostring(why))
  local g = Cat.grantsFor(MEM, st.achgrants)
  ok(g.first60 and g.first60.reason == "evento", "the badge is granted with its reason")
  local _, wN = apply(st, rec("achgrant", "lvl.all.10|" .. MEM, GM, T + 2, { ach = "lvl.all.10", who = MEM, reason = "x", on = true }))
  eq(wN, "notBadge", "a race id is never granted")
  eq(topText(compute(store, st)), before, "no entry in any Top")
  ok(apply(st, rec("achgrant", "first60|" .. MEM, GM, T + 3, { ach = "first60", who = MEM, reason = "error", on = false })), "withdrawn")
  eq(Cat.grantsFor(MEM, st.achgrants).first60, nil, "not granted any more")
  local h = Cat.grantHistory(st.achgrants)
  eq(#h, 1); eq(h[1].d.on, false, "history keeps the withdrawal"); eq(h[1].d.reason, "error")
end)

-------------------------------------------------------------------------------
test("extension kinds: order after vconfirm, old hello order unchanged, compaction keeps custom levels", function()
  ok(M.kindOrder("achdef") > M.kindOrder("vconfirm") and M.kindOrder("achgrant") > M.kindOrder("achdef"))
  local core = { "settings", "squad", "profile", "reject", "boss", "annul" }
  for i, k in ipairs(core) do eq(M.ORDER[k], i) end
  local n = #M.EXT_ORDER
  eq(M.EXT_ORDER[n - 1], "achdef"); eq(M.EXT_ORDER[n], "achgrant")
  local st, store = fresh(), R.newStore()
  ok(apply(st, rec("achdef", "gm.lvl40", GM, T, { custom = true, metric = "level", thr = 40, size = 10 })))
  level(store, "P1-R", 40, T + 10)
  store.closed["lvl.all.40"] = { rows = {} }; store.closed["lvl.class.WARRIOR.40"] = { rows = {} }
  R.compact(store, st.achdefs)
  ok(nobs(store) == 2, "level 40 observations kept for gm.lvl40")
  Cat.use(nil)
end)
