-- integrity: non-finite numbers, rename collisions, counter index, guild change, geometry.
local S, M, P = NS.Serialize, NS.Model, NS.Progress
local T0 = 1795000000

-- migration to schema 3 drops SavedVariables entries carrying non-finite numbers
test("migration: non-finite numbers are scrubbed from an existing guild DB (v2 -> v3)", function()
  local inf = math.huge
  local good = { k = "profile", id = "A-R", a = "A-R", ts = T0, sq = 3, d = { class = "MAGE", level = 10 } }
  local bad = { k = "profile", id = "B-R", a = "B-R", ts = T0, sq = inf, d = { class = "MAGE" } }
  local badLv = { k = "profile", id = "C-R", a = "C-R", ts = T0, sq = 1, d = { level = -inf } }
  local root = { guilds = { ["G-R"] = {
    v = 2, records = { good, bad, badLv },
    progress = { events = { e1 = { t = "hk", who = "A-R", sid = "S", n = 1, ts = T0 },
                            e2 = { t = "hk", who = "B-R", sid = "S", n = 1, ts = -inf } },
                 pending = { hk = inf, cap = 2 } },
    races = { obs = { o1 = { t = "lv", who = "A-R", by = "A-R", ts = T0, lv = 10 }, o2 = { t = "lv", who = "B-R", by = "B-R", ts = 0 / 0, lv = 10 } } },
  } } }
  local g = M.guildDB(root, "G-R")
  eq(g.v, 3, "schema version bumped")
  eq(#g.records, 1, "records with inf removed"); eq(g.records[1].id, "A-R")
  ok(g.progress.events.e1 and not g.progress.events.e2, "-inf progress event removed, the finite one kept")
  ok(g.races.obs.o1 and not g.races.obs.o2, "NaN observation removed")
  eq(g.progress.pending.hk, nil, "stray non-finite counter removed"); eq(g.progress.pending.cap, 2)
  -- the cleaned data can be serialised again and prune works on it
  ok(pcall(S.encode, g), "the whole guild DB serialises after the migration")
  local store = P.newStore()
  for _, ev in pairs(g.progress.events) do P.add(store, ev) end
  ok(pcall(P.prune, store, P.wipeOf(T0 + 86400 * 120), "weekly", {}), "prune")
  -- idempotent and backward compatible: a schema 3 DB is not touched again, an older or unversioned DB is migrated
  g.records[2] = bad
  M.guildDB(root, "G-R"); eq(#g.records, 2, "v3: no second scrub")
  local root2 = { guilds = { ["H-R"] = { records = { bad, good } } } }
  local g2 = M.guildDB(root2, "H-R"); eq(#g2.records, 1); eq(g2.v, 3)
end)

test("decoder: non-finite values are dropped inside tables, refused as keys or payload", function()
  ok(not S.decode("n1e999;")); ok(not S.decode("nnan;")); ok(not S.decode("n1e16;"))
  local okD, t = S.decode("ts1:an1e999;s1:bn2;e")
  ok(okD); eq(t.a, nil); eq(t.b, 2)
  ok(not S.decode("tn1e999;n1;e"), "non-finite key")
  local okR, r = S.decode(S.encode({ k = "profile", id = "A-R", a = "A-R", ts = T0, sq = 7, d = {} }):gsub("n7;", "n1e999;"))
  ok(okR); ok(not M.validShape(r), "record without a finite sq is refused")
  ok(not M.validShape({ k = "profile", id = "A-R", a = "A-R", ts = T0, sq = 1.5 }), "fractional sq")
  ok(M.validShape({ k = "profile", id = "A-R", a = "A-R", ts = T0, sq = 1 }))
end)

-- a rename onto another squad's name is ACCEPTED on every
-- client (refusing it depended on arrival order) and never evicts: the older name (nts, author, id) keeps it and
-- the renamed squad shows "Name". Creation races keep the (ct, id) rule.
test("a rename colliding with another squad never evicts and is resolved for display; simultaneous creations still converge", function()
  local ranks = { ["Gm-R"] = 0, ["Cx-R"] = 5, ["Cy-R"] = 5, ["Cz-R"] = 5 }
  local roster = makeRoster(ranks)
  local function ap(s, r) return M.apply(s, r, { roster = roster }) end
  local function rec(id, a, d, ts) return { k = "squad", id = id, a = a, ts = ts, sq = 1, d = d } end
  local s = M.newState()
  ap(s, { k = "settings", id = "settings", a = "Gm-R", ts = T0, sq = 1, d = { squadsEnabled = true } })
  ok(ap(s, rec("X", "Cx-R", { name = "Alfa", captain = "Cx-R", members = { "Cx-R" } }, T0 + 100)))
  ok(ap(s, rec("Y", "Cy-R", { name = "Lobos", captain = "Cy-R", members = { "Cy-R" } }, T0 + 200)))
  ok(ap(s, rec("X", "Cx-R", { name = "LOBOS", captain = "Cx-R", members = { "Cx-R" }, ct = T0 + 100, nts = T0 + 300 }, T0 + 300)))
  ok(s.squads.X and s.squads.Y, "nothing evicted")
  eq(M.displayName(s, "Y"), "Lobos", "the older name keeps it"); eq(M.displayName(s, "X"), "LOBOS (2)")
  -- simultaneous creations: same winner whatever the arrival order
  local a = rec("Z1", "Cz-R", { name = "Osos", captain = "Cz-R", members = { "Cz-R" } }, T0 + 500)
  local b = rec("Z2", "Cx-R", { name = "osos", captain = "Cx-R", members = { "Cx-R" } }, T0 + 501)
  local function fresh() local t = M.newState(); ap(t, { k = "settings", id = "settings", a = "Gm-R", ts = T0, sq = 1, d = { squadsEnabled = true } }); return t end
  local s1, s2 = fresh(), fresh()
  ap(s1, a); ap(s1, b); ap(s2, b); ap(s2, a)
  ok(s1.squads.Z1 and not s1.squads.Z2, "older creation wins (order a,b)")
  ok(s2.squads.Z1 and not s2.squads.Z2, "older creation wins (order b,a)")
end)

-- the incoming counter check uses an index (no full scan of obs), same verdicts as before
test("counterOk uses the reporter|counter index and keeps its verdicts", function()
  local R = NS.Races
  local store = { obs = {}, closed = {} }
  for i = 1, 300 do
    store.obs["x" .. i] = { t = "lv", who = "P" .. i .. "-R", by = "P" .. i .. "-R", ts = T0, lv = 10 }
  end
  ok(R.add(store, { t = "cnt", k = "hk", who = "A-R", by = "A-R", ts = T0, n = 100 }, T0))
  ok(R.add(store, { t = "cnt", k = "hk", who = "A-R", by = "A-R", ts = T0 + 3600, n = 120 }, T0 + 3600))
  local okD, why = R.counterOk(store, { t = "cnt", k = "hk", who = "A-R", by = "A-R", ts = T0 + 7200, n = 90 })
  ok(not okD); eq(why, "decrease")
  local okS, whyS = R.counterOk(store, { t = "cnt", k = "hk", who = "A-R", by = "A-R", ts = T0, n = 101 })
  ok(not okS); eq(whyS, "sameTs")
  ok(R.counterOk(store, { t = "cnt", k = "hk", who = "B-R", by = "B-R", ts = T0, n = 1 }), "other reporter")
  -- only the 2 readings of A's hk sit in its index bucket (the 300 level obs are never visited)
  local real = store.obs
  local idx = R.cntIndex(store)
  local n = 0; for _ in pairs(idx["A-R|hk|"]) do n = n + 1 end
  eq(n, 2, "index bucket")
  -- the index follows compaction and a replaced obs table
  R.compact(store); eq(store.cntIdx, nil)
  store.obs = { y = real[R.obsId(R.sanitize({ t = "cnt", k = "hk", who = "A-R", by = "A-R", ts = T0, n = 100 }))] }
  ok(store.obs.y, "copied reading")
  local okR = R.counterOk(store, { t = "cnt", k = "hk", who = "A-R", by = "A-R", ts = T0 + 60, n = 50 })
  ok(not okR, "rebuilt index sees the reading kept in the new obs table")
end)

-- leaving the guild and joining another switches the per-guild partition without /reload
SMOKE_CHECKS = SMOKE_CHECKS or {}
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "guild change in-session: old partition saved, new one loaded, back again", function(c)
  local ns = c.ns
  local function timers()
    local origT, base = GetTime, GetTime()
    GetTime = function() return base + 5 end
    for _, o in ipairs(c.allObjs) do local fn = rawget(o, "_OnUpdate"); if fn then pcall(fn, o, 5) end end
    GetTime = origT
  end
  local function roster() c.fire("GUILD_ROSTER_UPDATE"); timers() end
  local origIn, origInfo = IsInGuild, GetGuildInfo
  local oldKey = ns.guildKey
  local nSquads = 0; for _ in pairs(ns.state.squads) do nSquads = nSquads + 1 end
  ok(nSquads > 0, "the fake guild has squads")
  local okAll, err = pcall(function()
    IsInGuild = function() return false end
    roster()
    eq(ns.gdb, nil, "no partition without a guild"); eq(next(ns.state.squads), nil, "state emptied")
    ok(GuildSquadsDB.guilds[oldKey] and #GuildSquadsDB.guilds[oldKey].records > 0, "old partition saved under its key")
    GetGuildInfo = function() return "Otra Guild", "Member", 4, nil end
    IsInGuild = function() return true end
    roster()
    eq(ns.guildKey, ns.Model.guildKey("Otra Guild", "Realm"), "new guild key")
    ok(ns.rosterReady, "bootstrapped again"); eq(next(ns.state.squads), nil, "no squads of the old guild")
    ok(GuildSquadsDB.guilds[ns.guildKey], "new partition created")
    local foreign = 0
    for _, o in pairs(ns.HallGlue.Store().obs) do if o.by ~= ns.me() then foreign = foreign + 1 end end
    eq(foreign, 0, "Hall store of the new guild holds only this client's fresh readings")
  end)
  IsInGuild, GetGuildInfo = origIn, origInfo
  roster()   -- back to the original guild (direct switch, no guildless step)
  eq(ns.guildKey, oldKey, "switched back")
  local n2 = 0; for _ in pairs(ns.state.squads) do n2 = n2 + 1 end
  eq(n2, nSquads, "the original squads are loaded again")
  if not okAll then error(err, 0) end
end }

-- geometry / fake-API regressions
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "tabs fit the window, comment box clear of the add panel, labels bounded", function(c)
  local ns, UI, G, L = c.ns, c.ns.UI, c.ns.RaidGlue, c.ns.L
  -- tab strip: with every tab visible the total width stays inside the window
  for _, key in ipairs(UI.order) do UI.Select(key) end
  UI.Select("mysquad")
  ok(UI.tabsWidth and UI.tabsWidth <= UI.WIN_W, "tab strip " .. tostring(UI.tabsWidth) .. " px > " .. UI.WIN_W)
  if UI.tabsCompact then
    local p = UI.panels.ranking
    ok(p.tab.tip == p.title, "icon-only tab keeps its name in the tooltip")
  end
  -- comment box: right edge before the add panel (x 452); answers 58 px
  local wall = G.WallNow()
  local rid = G.Create({ raid = "custom", size = 10, name = "Raid geometría", at = wall + 86400 })
  UI.OpenRoster(rid)
  local rb = UI.RaidsState()
  eq(rawget(rb.comment, "_w") or (rb.comment.GetWidth and rb.comment:GetWidth()), 100, "comment width")
  local right = 100 + 4 * 58 + 3 * 2 + 8 + 100
  ok(right < 452, "comment box ends at " .. right)
  -- card title bounded
  UI.Select("raids")
  -- fit badge: no "afinidad" sub-label
  ok(rawget(L, "FIT_SHORT") == nil, "FIT_SHORT key removed with the sub-label")
  -- counter entries: localized label
  ok(rawget(L, "HALL_CNT_hk"), "HALL_CNT_hk")
  -- icons replaced
  ok(not SOURCES["UI/Hall.lua"]:find("INV_Misc_Trophy_03", 1, true) and not SOURCES["UI/Hall.lua"]:find("INV_Misc_Map_02", 1, true))
end }
