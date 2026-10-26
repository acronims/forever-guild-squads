-- robustness: ts ties, import of scalar entries, send lockdown, weekly reset anchor
local M, S = NS.Model, NS.Serialize
local roster = makeRoster({ ["Gm-R"] = 0, ["Off-R"] = 1, ["Ali-R"] = 5, ["Bob-R"] = 5 })
local T0 = 1795000000

test("on a ts tie the higher-authority author wins, whatever the seq", function()
  local cap = { k = "squad", id = "S1", a = "Ali-R", ts = T0 + 5, sq = 900,
                d = { name = "Raiders", captain = "Ali-R", members = { "Ali-R" }, icon = 1, color = 1, border = 1, approved = true } }
  local gm = { k = "squad", id = "S1", a = "Gm-R", ts = T0 + 5, sq = 1,
               d = { name = "Raiders", captain = "Ali-R", members = { "Ali-R" }, icon = 1, color = 1, border = 1, approved = true, motto = "gm" } }
  local a, b = M.newState(), M.newState()
  ok(M.apply(a, { k = "squad", id = "S1", a = "Ali-R", ts = T0, sq = 1, d = cap.d }, { roster = roster }))
  ok(M.apply(b, { k = "squad", id = "S1", a = "Ali-R", ts = T0, sq = 1, d = cap.d }, { roster = roster }))
  M.apply(a, cap, { roster = roster }); M.apply(a, gm, { roster = roster })
  M.apply(b, gm, { roster = roster }); M.apply(b, cap, { roster = roster })
  eq(a.squads.S1.a, "Gm-R"); eq(b.squads.S1.a, "Gm-R")
end)

test("import ignores scalar entries instead of raising", function()
  local text = "GSQ1:" .. S.escape(S.encode({ 5, "x", { k = "profile", id = "Ali-R", a = "Ali-R", ts = T0, sq = 1, d = { role = "TANK" } } }))
  local st = M.newState()
  local okP, applied = pcall(M.import, st, text, { roster = roster })
  ok(okP, "import raised"); eq(applied, 1)
end)

test("lockdown (11) keeps the message and pauses; permanent errors drop at once", function()
  local results, calls = {}, 0
  local saved = C_ChatInfo
  C_ChatInfo = { SendAddonMessage = function() calls = calls + 1; return table.remove(results, 1) or 0 end }
  local ns = { Serialize = NS.Serialize, Chunk = NS.Chunk, Queue = NS.Queue }
  local okL, err = pcall(function()
    loadmod("Comm.lua", ns)
    local C = ns.Comm
    results = { 11 }
    C.Send("D", { r = {} })
    local before = C.Pending()
    C.queue:pump(1000)
    eq(C.Pending(), before, "message kept after lockdown")
    ok(C.queue:blocked(), "queue paused")
    C.queue:setBlocked("lockdown", false)
    results = { 0 }
    C.queue:pump(1010)
    eq(C.Pending(), 0, "sent once the lockdown is over")
    results = { 12 }
    C.Send("D", { r = {} })
    C.queue:pump(1020)
    eq(C.Pending(), 0, "TargetOffline dropped at once"); eq(C.stats.failed, 1)
  end)
  C_ChatInfo = saved
  ok(okL, tostring(err))
end)

test("weekly reset anchor from GetSecondsUntilWeeklyReset; EU keeps Wednesday 09:00 CET", function()
  local Pr = NS.Progress
  local w = Pr.weekOf(T0)
  local nextEU = Pr.wipeStartTs("W" .. (w + 1))
  eq(Pr.weeklyShift(T0, nextEU - T0), 0, "EU reset = CET anchor")
  eq(Pr.weeklyShift(T0, nextEU - T0 + 3600), 0, "DST hour tolerated")
  eq(Pr.weeklyShift(T0, nil), 0, "API missing -> fallback")
  -- US: Tuesday 15:00 UTC = 18 h before Wednesday 09:00 CET (winter)
  local usReset = nextEU - 18 * 3600
  local shift = Pr.weeklyShift(T0, usReset - T0)
  ok(shift ~= 0, "US shift")
  Pr.SHIFT = shift
  local okW = Pr.weekOf(usReset) == Pr.weekOf(usReset - 1) + 1
  local start = Pr.wipeStartTs(Pr.wipeOf(usReset))
  Pr.SHIFT = 0
  ok(okW, "a new wipe starts exactly at the US reset")
  eq(start, usReset, "wipeStartTs follows the shift")
end)
