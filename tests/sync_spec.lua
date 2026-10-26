-- sync: relay trust, captaincy hand-over, schema fuzz, convergence, hello pagination, per-guild data.
local M, Pr, S = NS.Model, NS.Progress, NS.Serialize
local ranks = { ["Gm-R"] = 0, ["Off-R"] = 1, ["Ali-R"] = 5, ["Bob-R"] = 5, ["Cid-R"] = 5, ["Eve-R"] = 7 }
local roster = makeRoster(ranks)
local T0 = 1795000000

local function squad(id, cap, name, members, ts, a, extra)
  local d = { name = name, captain = cap, members = members, bench = {}, icon = 1, color = 1, border = 1, approved = true }
  for k, v in pairs(extra or {}) do d[k] = v end
  return { k = "squad", id = id, a = a or cap, ts = ts, sq = 1, d = d }
end
local function prof(name, sid, ts, extra)
  local d = { squad = sid, role = "DAMAGER" }
  for k, v in pairs(extra or {}) do d[k] = v end
  return { k = "profile", id = name, a = name, ts = ts, sq = 1, d = d }
end
local function fp(st)  -- fingerprint of a state (order independent)
  local o = {}
  for _, r in ipairs(M.allRecords(st)) do o[#o + 1] = M.versionKey(r) .. (r.d.disbanded and "#X" or "") end
  table.sort(o)
  return table.concat(o, ";")
end

-- relay trust -------------------------------------------------------------------
-- there is no "author's announcement" path; an announced hash does not help
test("live records: sender must be the author; relays need an officer (announcements ignored)", function()
  local rec = prof("Ali-R", "", T0)
  local st = M.newState()
  ok(M.apply(st, rec, { roster = roster, sender = "Ali-R" }), "live by author accepted")
  local st2 = M.newState()
  local okA, why = M.apply(st2, rec, { roster = roster, sender = "Eve-R" })
  ok(not okA); eq(why, "relay", "non-officer relay of an unannounced record")
  ok(M.apply(st2, rec, { roster = roster, sender = "Off-R" }), "officer relay accepted")
  local st3 = M.newState()
  local ann = { ["Ali-R"] = { [M.versionHash(rec)] = true } }
  local okN, whyN = M.apply(st3, rec, { roster = roster, sender = "Bob-R", announced = function(a, h) return ann[a] and ann[a][h] end })
  ok(not okN, "relay of an announced version is refused"); eq(whyN, "relay")
  local forged = prof("Ali-R", "S9", T0 + 1)  -- not the announced version
  local okF, whyF = M.apply(st3, forged, { roster = roster, sender = "Bob-R", announced = function(a, h) return ann[a] and ann[a][h] end })
  ok(not okF); eq(whyF, "relay")
end)

test("records more than 300 s in the future are refused; 299 s is fine", function()
  local st = M.newState()
  local okA, why = M.apply(st, prof("Ali-R", "", T0 + 301), { roster = roster, sender = "Ali-R", now = T0 })
  ok(not okA); eq(why, "future")
  ok(M.apply(st, prof("Ali-R", "", T0 + 299), { roster = roster, sender = "Ali-R", now = T0 }))
  local okB, whyB = M.apply(M.newState(), prof("Ali-R", "", 4e9), { roster = roster })
  ok(not okB); eq(whyB, "ts", "beyond int32 is malformed even without a clock")
end)

local function syncNs(state, me, rosterFn)
  local sent = {}
  local ns = { Model = M, Permissions = NS.Permissions, Serialize = S, state = state, roster = rosterFn or roster,
               rosterReady = true, onlineCount = function() return 1 end, me = function() return me end,
               fullName = function(n) return n end, After = function(_, fn) fn() end, serverTime = function() return T0 + 1000 end,
               Comm = { Send = function(tag, p) sent[#sent + 1] = { tag, p } end } }
  loadmod("Sync.lua", ns)
  return ns, sent
end

-- no quarantine, an announcement never releases a relay; only the author or an officer
test("Sync: a refused relay is never stored nor relayed; announcements release nothing", function()
  local ns, sent = syncNs(M.newState(), "Cid-R")
  local forged = { k = "settings", id = "settings", a = "Gm-R", ts = T0, sq = 1, d = { squadsEnabled = false } }
  ns.Sync.OnMessage("D", { r = { forged } }, "Eve-R")
  ok(ns.state.settings == nil, "forged GM settings relayed by Eve not applied")
  eq(ns.Sync.QuarantineCount(), 0, "no quarantine")
  -- someone says hello: our reply must not carry the refused record
  local h = {}
  for _, k in ipairs({ "settings", "squad", "profile", "reject", "boss", "annul" }) do h[k] = M.bucketHashes(M.newState(), k) end
  ns.Sync.OnMessage("H", { h = h }, "New-R")
  for _, m in ipairs(sent) do
    if m[1] == "D" then for _, r in ipairs(m[2].r) do ok(r.k ~= "settings", "refused record relayed") end end
  end
  -- the GM's hello announces a DIFFERENT version: still refused
  ns.Sync.OnMessage("H", { h = h, an = { "zzzzzz" } }, "Gm-R")
  ok(ns.state.settings == nil)
  -- a genuine record relayed by Eve stays refused even when the GM "announces" it; the GM itself is accepted
  local real = { k = "settings", id = "settings", a = "Gm-R", ts = T0 + 5, sq = 2, d = { squadsEnabled = true } }
  ns.Sync.OnMessage("D", { r = { real } }, "Eve-R")
  ok(ns.state.settings == nil)
  ns.Sync.OnMessage("H", { h = h, an = { M.versionHash(real) } }, "Gm-R")
  ok(ns.state.settings == nil, "announcement releases nothing")
  ns.Sync.OnMessage("D", { r = { real } }, "Gm-R")
  ok(ns.state.settings and ns.state.settings.ts == T0 + 5, "live from the author applied")
end)

-- captaincy -------------------------------------------------------------------
test("captaincy moves only with the current captain's signed hand-over (or the GM)", function()
  local ctx = { roster = roster }
  local st = M.newState()
  ok(M.apply(st, squad("S1", "Ali-R", "Raiders", { "Ali-R", "Bob-R" }, T0), ctx))
  ok(M.apply(st, prof("Bob-R", "S1", T0 + 1), ctx))
  local claim = squad("S1", "Bob-R", "Raiders", { "Ali-R", "Bob-R" }, T0 + 10, "Bob-R", { xferFrom = "Ali-R" })
  local okA, why = M.apply(st, claim, ctx)
  ok(not okA); eq(why, "xfer")
  -- a hand-over to someone else does not count
  ok(M.apply(st, prof("Ali-R", "S1", T0 + 2, { xferTo = "S1>Cid-R" }), ctx))
  ok(not M.apply(st, claim, ctx))
  ok(M.apply(st, prof("Ali-R", "S1", T0 + 3, { xferTo = "S1>Bob-R" }), ctx))
  ok(M.apply(st, claim, ctx), "hand-over signed by Ali")
  eq(st.squads.S1.d.captain, "Bob-R")
  -- the GM can reassign with a record of their own
  ok(M.apply(st, squad("S1", "Ali-R", "Raiders", { "Ali-R", "Bob-R" }, T0 + 20, "Gm-R"), ctx))
  eq(st.squads.S1.d.captain, "Ali-R")
end)

-- schema ----------------------------------------------------------------------
test("schema: malformed records are counted and dropped, never raise (fuzz)", function()
  local ns = syncNs(M.newState(), "Cid-R")
  local junk = { 1, "x", true, {}, { id = "x" }, { k = "squad", id = "x" }, { k = "squad", id = "x", a = "Ali-R" },
                 { k = "squad", id = "x", a = "Ali-R", ts = "1", sq = 1 }, { k = "squad", id = "x", a = {}, ts = 1, sq = 1 },
                 { k = "nope", id = "x", a = "Ali-R", ts = T0, sq = 1, d = {} }, { k = "squad", id = "x", a = "Ali-R", ts = 0 / 0, sq = 1 },
                 { k = "squad", id = "x", a = "Ali-R", ts = T0, sq = 1, d = "str" }, { k = "profile", id = ("x"):rep(400), a = "Ali-R", ts = T0, sq = 1, d = {} } }
  for _, j in ipairs(junk) do
    local okP = pcall(ns.Sync.OnMessage, "D", { r = { j } }, "Ali-R")
    ok(okP, "OnMessage raised")
  end
  for _, p in ipairs({ "x", 5, { r = "x" }, { r = { 1, 2 } }, { h = 3 }, { h = { squad = 5 } } }) do
    for _, tag in ipairs({ "D", "H", "E", "RO", "RP", "C" }) do ok(pcall(ns.Sync.OnMessage, tag, p, "Ali-R")) end
  end
  ok(ns.Sync.stats.bad >= 10, "bad records counted: " .. ns.Sync.stats.bad)
end)

test("schema positive: one valid record of every kind passes validation and applies", function()
  local st = M.newState()
  local ctx = { roster = roster }
  local recs = {
    { k = "settings", id = "settings", a = "Gm-R", ts = T0, sq = 1, d = { squadsEnabled = true } },
    squad("S1", "Ali-R", "Raiders", { "Ali-R" }, T0 + 1),
    prof("Ali-R", "S1", T0 + 2),
    prof("Bob-R", "S1", T0 + 3),
    { k = "reject", id = M.rejectId("S1", "Bob-R", "req"), a = "Ali-R", ts = T0 + 4, sq = 1, d = { sid = "S1", name = "Bob-R", kind = "req", at = 0 } },
    { k = "boss", id = "rfc.7", a = "Ali-R", ts = T0 + 5, sq = 1, d = { inst = "rfc", enc = 7, name = "Taragaman" } },
    { k = "annul", id = "dng.rfc|Ali-R", a = "Gm-R", ts = T0 + 6, sq = 1, d = { race = "dng.rfc", key = "Ali-R", reason = "bug" } },
  }
  for _, r in ipairs(recs) do
    ok(M.validShape(r), "shape " .. r.k)
    local okA, why = M.apply(st, r, ctx)
    ok(okA, r.k .. ": " .. tostring(why))
  end
end)

-- convergence -----------------------------------------------------------------
local function permutations(list)
  local out = {}
  local function rec(a, n)
    if n == 0 then local c = {} for i, v in ipairs(a) do c[i] = v end out[#out + 1] = c return end
    for i = 1, n do a[i], a[n] = a[n], a[i]; rec(a, n - 1); a[i], a[n] = a[n], a[i] end
  end
  rec(list, #list)
  return out
end
local function applyFix(list, settings)
  -- apply until nothing changes (models the hello re-sends between peers)
  local st = M.newState()
  if settings then M.apply(st, settings, { roster = roster }) end
  for _ = 1, #list + 1 do
    local changedAny = false
    for _, r in ipairs(list) do if M.apply(st, r, { roster = roster }) then changedAny = true end end
    if not changedAny then break end
  end
  return st
end

test("convergence: every arrival order of names / limit / disband vs edit gives the same state", function()
  local cfg = { k = "settings", id = "settings", a = "Gm-R", ts = T0 - 100, sq = 1, d = { squadsEnabled = true, maxSquads = 10 } }
  local recs = {
    squad("X", "Ali-R", "Raiders", { "Ali-R" }, T0),
    squad("Y", "Bob-R", "raiders ", { "Bob-R" }, T0 + 1),                        -- same visible name, later
    squad("Z", "Cid-R", "Zeta", { "Cid-R" }, T0 + 2),
    squad("Z", "Cid-R", "Zeta", { "Cid-R" }, T0 + 10, "Off-R", { disbanded = true, ct = T0 + 2 }), -- officer disband
    squad("Z", "Cid-R", "Zeta 2", { "Cid-R" }, T0 + 20, nil, { ct = T0 + 2 }),   -- captain edit after it
  }
  local ref
  for _, p in ipairs(permutations(recs)) do
    local f = fp(applyFix(p, cfg))
    ref = ref or f
    eq(f, ref, "order-dependent result")
  end
  local st = applyFix(recs, cfg)
  ok(st.squads.X and not st.squads.Y, "lower (ct, id) keeps the name")
  ok(st.squads.Z.d.disbanded, "tombstone wins over the later captain edit")
  -- squad limit: with max 2, the two lowest (ct, id) survive whatever the order
  local cfg2 = { k = "settings", id = "settings", a = "Gm-R", ts = T0 - 100, sq = 1, d = { squadsEnabled = true, maxSquads = 10 } }
  local three = { squad("A", "Ali-R", "Alfa", { "Ali-R" }, T0 + 3), squad("B", "Bob-R", "Beta", { "Bob-R" }, T0 + 1),
                  squad("C", "Cid-R", "Gamma", { "Cid-R" }, T0 + 2) }
  local ref2
  for _, p in ipairs(permutations(three)) do
    local st2 = M.newState()
    M.apply(st2, cfg2, { roster = roster })
    st2.settings.d.maxSquads = 2
    for _ = 1, 3 do for _, r in ipairs(p) do M.apply(st2, r, { roster = roster }) end end
    local f = fp(st2)
    ref2 = ref2 or f
    eq(f, ref2, "limit order-dependent")
    ok(st2.squads.B and st2.squads.C and not st2.squads.A, "keeps B and C")
  end
end)

-- pagination ------------------------------------------------------------------
test("hello pagination: a fresh client gets 100 squads + 100 profiles in <= 5 rounds", function()
  local A = M.newState()
  local rk = { ["Gm-R"] = 0 }
  for i = 1, 100 do
    local cap = ("C%03d-R"):format(i); rk[cap] = 5
    A.squads["S" .. i] = squad("S" .. i, cap, ("Squad %03d"):format(i), { cap }, T0 + i, nil, { ct = T0 + i })
    A.profiles[cap] = prof(cap, "S" .. i, T0 + 200 + i)
  end
  local ros = makeRoster(rk)
  local ns, sent = syncNs(A, "Gm-R", ros)   -- the responder is the GM => trusted relay
  local B = M.newState()
  local rounds = 0
  local nB = function() local n = 0 for _ in pairs(B.squads) do n = n + 1 end for _ in pairs(B.profiles) do n = n + 1 end return n end
  while nB() < 200 and rounds < 10 do
    rounds = rounds + 1
    local h = {}
    for _, k in ipairs({ "settings", "squad", "profile", "reject", "boss", "annul" }) do h[k] = M.bucketHashes(B, k) end
    for i = #sent, 1, -1 do sent[i] = nil end
    ns.Sync.OnMessage("H", { h = h }, "New-R")
    for _, m in ipairs(sent) do
      if m[1] == "D" then for _, r in ipairs(m[2].r) do M.apply(B, r, { roster = ros, sender = "Gm-R" }) end end
    end
  end
  eq(nB(), 200, "records known by the fresh client")
  ok(rounds <= 5, "rounds " .. rounds)
end)

-- season totals ---------------------------------------------------------------
test("season total survives prune + reload (12 wipes, summaries)", function()
  local season = { start = Pr.wipeStartTs("W" .. Pr.weekOf(T0)), stop = 0 }
  local store = Pr.newStore()
  local w0 = Pr.weekOf(T0)
  for i = 0, 11 do
    local ts = Pr.wipeStartTs("W" .. (w0 + i)) + 3600
    Pr.add(store, { t = "bg", who = "Ali-R", ts = ts, sid = "S1", inst = "WSG", win = 1 })
    Pr.add(store, { t = "bg", who = "Bob-R", ts = ts + 5, sid = "S1", inst = "WSG", win = 1 })
    Pr.add(store, { t = "level", who = "Ali-R", ts = ts, sid = "S2", lv = 10 + i })
  end
  local now = Pr.wipeStartTs("W" .. (w0 + 11)) + 7200
  local before = Pr.seasonScore(store.events, season, now, {}).squads
  ok(Pr.prune(store, Pr.wipeOf(now), "weekly") > 0, "something was pruned")
  -- "reload": saved table -> new store (summaries kept as is, events re-sanitised)
  local saved = S.decode(S.encode(store.events)) and select(2, S.decode(S.encode(store.events)))
  local re = Pr.newStore()
  for id, ev in pairs(saved) do if Pr.isSummary(ev) then re.events[id] = ev else Pr.add(re, ev) end end
  local after = Pr.seasonScore(re.events, season, now, {}).squads
  eq(after.S1.pvp, before.S1.pvp, "pvp"); eq(after.S2.level, before.S2.level, "level")
  eq(after.S1.bgW, 12)
  -- pruning twice is idempotent
  Pr.prune(re, Pr.wipeOf(now), "weekly")
  eq(Pr.seasonScore(re.events, season, now, {}).squads.S1.pvp, before.S1.pvp)
end)

-- per-guild data --------------------------------------------------------------
test("per-guild SavedVariables: legacy data migrates to its guild; alts of other guilds never touch it", function()
  local legacy = { seq = 7, minimap = { angle = 1 },
                   records = { prof("Ali-R", "", T0), prof("Bob-R", "", T0), squad("S1", "Ali-R", "Raiders", { "Ali-R" }, T0) },
                   progress = { events = { x = 1 } }, races = { obs = {} } }
  -- an alt in ANOTHER guild logs in first: legacy stays where it is
  local other = makeRoster({ ["Zed-R"] = 0 })
  local g2, mig2 = M.guildDB(legacy, M.guildKey("Otra", "R"), function(n) return other(n) ~= nil end)
  ok(not mig2 and g2.records == nil, "other guild does not adopt")
  ok(#legacy.records == 3 and legacy.progress, "legacy untouched")
  -- the main guild adopts it
  local g1, mig1 = M.guildDB(legacy, M.guildKey("Mia", "R"), function(n) return roster(n) ~= nil end)
  ok(mig1, "migrated")
  eq(#g1.records, 3); ok(g1.progress.events.x == 1 and g1.races, "progress + races moved")
  ok(legacy.records == nil and legacy.progress == nil and legacy.races == nil, "top level cleared")
  eq(legacy.seq, 7, "account-wide fields stay"); ok(legacy.minimap)
  -- the two guilds are separate tables and a second call is idempotent
  ok(legacy.guilds["Otra-R"] ~= legacy.guilds["Mia-R"])
  local again, mig3 = M.guildDB(legacy, "Mia-R", function() return true end)
  ok(again == g1 and not mig3)
  -- a legacy file without records is adopted by the first guild
  local empty = { progress = { events = {} } }
  local g3, mig4 = M.guildDB(empty, "Any-R", function() return false end)
  ok(mig4 and g3.progress)
  -- records applied from the guild table re-validate into a state
  local st = M.newState()
  for _, r in ipairs(g1.records) do M.apply(st, r, { roster = roster }) end
  ok(st.squads.S1 and st.profiles["Ali-R"])
end)
