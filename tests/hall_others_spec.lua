-- 1.2.2: the «Otros» filter of the Salón de la fama is gone. WoW Forever has no Legacy Points, so the
-- legacy.<N> races ("%d puntos de Legado") leave the default catalog; «Squad con los 5 titulares al 60»
-- (squad.full60) and the profession / reputation races move to «Nivel».
-- Old data still loads: a legacy counter (SavedVariables, a 1.2.1 peer) is accepted as before (same wire format,
-- same sync hashes) but never scored, listed or shown; a closed legacy Top or a GM catalog record for a legacy
-- race is kept and stays inert. Not the "Legado" of the achievements the GM disabled (L.LEGACY): untouched.
local R, Cat = NS.Races, NS.Catalog
local T0 = 1795000000

local function legacyObs(who, ts, n, uv)
  return { t = "cnt", who = who, by = who, ts = ts, k = "legacy", n = n, uv = uv }
end
local function anyLegacy(races)
  for id in pairs(races) do if id:find("^legacy%.") then return id end end
  return nil
end

test("1.2.2 others: no 'other' category, no Legacy-points race in the default catalog, squad.full60 under Nivel", function()
  for _, c in ipairs(R.CATS) do ok(c ~= "other", "category 'other' still listed") end
  eq(#R.CATS, 6, "Nivel · Clase · Raza · Mazmorras · Bandas · PvP")
  -- an old caller may still pass nodata.legacy (1.2.1 glue): no race is created from it
  local races = R.compute(R.newStore(), { now = T0, nodata = { prof = true, rep = true, legacy = true } })
  eq(anyLegacy(races), nil, "legacy race in the default catalog")
  ok(races["squad.full60"], "squad.full60 still in the catalog")
  eq(races["squad.full60"].cat, "level", "squad.full60 in Nivel")
  eq(races["prof.*"].cat, "level", "profession races keep a visible tab")
  eq(races["rep.*"].cat, "level", "reputation races keep a visible tab")
  for id, r in pairs(races) do ok(r.cat ~= "other", "race left in 'other': " .. id) end
  eq(R.def("prof.alchemy.150").cat, "level"); eq(R.def("rep.stormwind.exalted").cat, "level")
  eq(R.def("squad.full60").cat, "level")
  local ids = {}
  for _, r in ipairs(R.list(races, "level")) do ids[r.id] = true end
  ok(ids["squad.full60"] and ids["lvl.all.60"], "Nivel lists the level races and squad.full60")
end)

test("1.2.2 others: saved data with a Legacy race loads without error and is filtered (obs, closed Top, GM catalog)", function()
  -- SavedVariables as 1.2.1 left them: legacy counters (one unverified), a frozen legacy Top, a real level race
  local rows = {}
  for i = 1, 10 do rows[i] = { key = "P" .. i .. "-R", ts = T0 + i, mark = "self", chars = { "P" .. i .. "-R" }, squads = {}, sup = {}, wit = 0 } end
  local gdb = { races = { obs = {}, closed = { ["legacy.100"] = { rows = rows, at = T0 + 20 } } } }
  local saved = {
    legacyObs("Ann-R", T0 + 100, 1000), legacyObs("Bob-R", T0 + 200, 600, 1),
    { t = "lv", who = "Cid-R", by = "Cid-R", ts = T0 + 50, lv = 60, src = "self", cls = "MAGE" },
    { t = "lv", who = "Cid-R", by = "Ann-R", ts = T0 + 70, lv = 60, src = "roster" },
  }
  for _, ev in ipairs(saved) do gdb.races.obs[R.obsId(ev)] = ev end
  local rdb = R.migrate(gdb)
  local store = R.newStore()
  for _, ev in pairs(rdb.obs) do R.add(store, ev) end   -- same as Hall.lua load()
  store.closed = rdb.closed
  -- a GM catalog (achdef) that enabled and renamed a legacy race, plus a live legacy counter from a 1.2.1 peer
  local defs = { ["legacy.100"] = { id = "legacy.100", ts = T0, d = { on = true, name = "Leyenda", size = 5 } },
                 ["legacy.500"] = { id = "legacy.500", ts = T0, d = { on = false } } }
  local okA = pcall(R.add, store, legacyObs("Dan-R", T0 + 300, 1000), T0 + 300)
  ok(okA, "a live legacy counter does not raise")
  local okC, races, info = pcall(R.compute, store, { now = T0 + 5000, achdefs = defs, nodata = { legacy = true } })
  ok(okC, "compute with legacy data: " .. tostring(races))
  eq(anyLegacy(races), nil, "legacy race shown or counted")
  eq(races["lvl.all.60"].entries[1].key, "Cid-R", "the rest of the saved data is intact")
  for id, r in pairs(races) do
    for _, e in ipairs(r.entries) do ok(e.key ~= "Ann-R" and e.key ~= "Dan-R" and e.key ~= "P1-R", "legacy entry counted in " .. id) end
  end
  eq(#R.legacyList(races), 0, "nothing in the GM's 'Legado' list from a legacy-points race")
  for _, x in ipairs(R.unverifiedList(store)) do ok(x.ev.k ~= "legacy", "unverified legacy counter listed") end
  local okAch = pcall(R.achievements, races, info, { now = T0 + 5000 })
  ok(okAch, "achievements with legacy data")
  -- the GM's catalog list does not offer them, even when its saved records name them
  for _, id in ipairs(Cat.knownIds(races, defs)) do ok(not id:find("^legacy%."), "catalog lists " .. id) end
  -- sync and compaction keep working with the old rows (no Lua error); a peer's closed legacy Top is harmless
  ok(pcall(R.compact, store, defs), "compact")
  ok(pcall(R.bucketHashes, store), "bucket hashes")
  local s2 = R.newStore()
  ok(pcall(R.importClosed, s2, "legacy.1000", R.packClosed({ rows = rows }), T0, defs), "import a closed legacy Top")
  local okC2, races2 = pcall(R.compute, s2, { now = T0 + 5000, achdefs = defs })
  ok(okC2 and anyLegacy(races2) == nil, "imported legacy Top not shown")
end)

-- UI, with the whole addon loaded against the fake client (run by zload_spec)
SMOKE_CHECKS = SMOKE_CHECKS or {}
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "1.2.2 hall: no «Otros» tab, squad.full60 under Nivel, no Legacy-points race (old data filtered)", function(c)
  local ns = c.ns
  local H, UI = ns.HallGlue, ns.UI
  UI.Open("hall"); eq(UI.Current(), "hall")
  local hs = UI.HallState()
  eq(hs.chips.other, nil, "«Otros» chip still there")
  local n = 0
  for cat, b in pairs(hs.chips) do n = n + 1; c.click(b); eq(hs.cat, cat); eq(UI.Current(), "hall") end
  eq(n, 6, "filter chips")
  c.click(hs.chips.level)
  local ids = {}
  for _, r in ipairs(UI.HallRaceList(H.Races(), "level")) do ids[r.id] = true end
  ok(ids["squad.full60"], "«Squad con los 5 titulares al 60» under Nivel")
  hs.sel = "squad.full60"; UI.Select("hall")
  eq(rawget(hs.title, "_text"), ns.L.RT_FULL60, "detail of squad.full60 opens from Nivel")
  eq(anyLegacy(H.Races()), nil, "legacy race in the default catalog")
  -- old data: a 1.2.1 peer sends a legacy counter; the GM's saved catalog names a legacy race
  local okO = pcall(H.OnObs, { o = { legacyObs("Bob-Realm", (GetServerTime and GetServerTime()) or time(), 1000) } }, "Bob-Realm", false)
  ok(okO, "legacy counter from a peer: no Lua error")
  ok(H.SetDef("legacy.100", { name = "Leyenda" }), "a GM record for a legacy race is still a valid record")
  UI.Select("hall")
  eq(anyLegacy(H.Races()), nil, "legacy race shown after old data")
  for _, x in ipairs(H.Unverified()) do ok(x.ev.k ~= "legacy", "legacy counter in the unverified list") end
  for _, id in ipairs(H.CatalogIds()) do ok(not id:find("^legacy%."), "GM catalog lists " .. id) end
  for _, row in ipairs(UI.CatalogRows("char")) do ok(not row.id:find("^legacy%."), "Ajustes > Logros lists " .. row.id) end
  for _, r in ipairs(UI.HallLegacyList(H.Races())) do ok(not r.id:find("^legacy%."), "'Legado' lists " .. r.id) end
end }
