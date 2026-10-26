-- Regression tests: wipes, renames and numbers. Each test asserts the CORRECT behaviour.
local S, M, P, R = NS.Serialize, NS.Model, NS.Progress, NS.Races
local T0 = 1795000000
local ranks = { ["Gm-R"] = 0, ["Off-R"] = 1, ["A-R"] = 5, ["B-R"] = 5, ["C-R"] = 5, ["Ca-R"] = 5, ["Cb-R"] = 5, ["N-R"] = 5 }
local roster = makeRoster(ranks)
local function rec(kind, id, a, d, ts, sq) return { k = kind, id = id, a = a, ts = ts, sq = sq or 1, d = d } end
local function ap(s, r) return M.apply(s, r, { roster = roster }) end
local function copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = copy(v) end return o end

-- helper: wipe with a raid kill by A and B (squad X = A, B, C at the time of the wipe)
local function wipeEvents()
  local T = T0 + 3 * 86400
  local events = {}
  local function add(ev) events[P.eventId(ev)] = P.sanitize(ev) end
  local pres = { "A-R", "B-R", "C-R" }
  add({ t = "boss", who = "A-R", ts = T, sid = "X", inst = "Barrow Deeps", it = "raid", enc = 777, boss = "Jefe", pres = pres })
  add({ t = "boss", who = "B-R", ts = T + 5, sid = "X", inst = "Barrow Deeps", it = "raid", enc = 777, boss = "Jefe", pres = pres })
  return events, P.wipeOf(T), T
end

-- the wipe summary is computed at prune time (~8 weeks later) with the CURRENT squad record: a member who left
-- after the wipe still counts in that wipe's summary.
test("a member who left AFTER the wipe still counts in that wipe's summary", function()
  local events, wipe, T = wipeEvents()
  local profiles = { ["A-R"] = { ts = T0, d = { squad = "X" } }, ["C-R"] = { ts = T0, d = { squad = "X" } },
                     ["B-R"] = { ts = T + 30 * 86400, d = {} } }                       -- B left a month later
  local squadsThen = { X = { ts = T0, d = { captain = "A-R", members = { "A-R", "B-R", "C-R" }, bench = {} } } }
  local squadsNow  = { X = { ts = T + 30 * 86400, d = { captain = "A-R", members = { "A-R", "C-R" }, bench = {} } } }
  local atWipe = P.wipeSummary(events, wipe, { profiles = profiles, squads = squadsThen })
  local atPrune = P.wipeSummary(events, wipe, { profiles = profiles, squads = squadsNow })
  eq(atPrune.X and atPrune.X.active, atWipe.X and atWipe.X.active, "miembros activos del wipe cambian según cuándo se resume")
  eq(P.roundSum(atPrune.X.raid), P.roundSum(atWipe.X.raid), "puntuación de banda del wipe cambia según cuándo se resume")
end)

-- a squad disbanded after the wipe keeps its summary for that wipe.
test("a squad disbanded AFTER the wipe keeps its summary of that wipe", function()
  local events, wipe, T = wipeEvents()
  local profiles = { ["A-R"] = { ts = T0, d = { squad = "X" } }, ["B-R"] = { ts = T0, d = { squad = "X" } },
                     ["C-R"] = { ts = T0, d = { squad = "X" } } }
  local squadsNow = { X = { ts = T + 40 * 86400, d = { captain = "A-R", members = { "A-R" }, bench = {}, disbanded = true } } }
  local sums = P.wipeSummary(events, wipe, { profiles = profiles, squads = squadsNow })
  ok(sums.X and (sums.X.active or 0) > 0, "el squad disuelto no aparece en el resumen del wipe en el que jugó")
end)

-- a rename onto another squad's name converges on every client (a client that already held the other squad
-- and a fresh client end in the same state).
test("a clashing rename converges on every client (new client vs old client)", function()
  local function fresh() local s = M.newState(); ap(s, rec("settings", "settings", "Gm-R", { squadsEnabled = true }, T0)); return s end
  local b0 = rec("squad", "B", "Cb-R", { name = "Bar", captain = "Cb-R", members = { "Cb-R" } }, T0 + 100)
  local a0 = rec("squad", "A", "Ca-R", { name = "Foo", captain = "Ca-R", members = { "Ca-R" } }, T0 + 200)
  local b1 = rec("squad", "B", "Cb-R", { name = "Foo", captain = "Cb-R", members = { "Cb-R" }, ct = T0 + 100 }, T0 + 300, 2)
  local old, new = fresh(), fresh()
  ap(old, copy(b0)); ap(old, copy(a0)); ap(old, copy(b1))     -- client that already held A
  ap(new, copy(b1)); ap(new, copy(a0))                        -- fresh client (only B's latest version)
  local function ids(s) local t = {} for id, r in pairs(s.squads) do t[#t + 1] = id .. "=" .. r.d.name end table.sort(t) return table.concat(t, ",") end
  eq(ids(new), ids(old), "los clientes divergen")
end)

-- encode and decode accept the same range of numbers.
test("encode and decode accept the same number range", function()
  local okE, txt = pcall(S.encode, { v = 2e15 })
  local okD, back = false, nil
  if okE then okD, back = S.decode(txt) end
  ok(not okE or (okD and back.v == 2e15), "encode aceptó 2e15 y decode lo descartó")
end)
