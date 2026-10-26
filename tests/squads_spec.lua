-- achievementProgress, durable Reject (sync, authority, idempotent), inactivity, settings validation,
-- settings records migrated, moderation reset by officers, max squads. Pure Core: no WoW API.
local M, Pr, S = NS.Model, NS.Progress, NS.Serialize
local T0 = 1792566000
local roster = makeRoster({ GM = 0, Off = 1, Cap = 4, Bob = 4, Cid = 4, Dan = 4 })
local ctx = { roster = roster }
local seq = 0
local function rec(k, id, a, d, ts) seq = seq + 1; return { k = k, id = id, a = a, ts = ts or (1000 + seq), sq = seq, d = d } end
local function world()
  local st = M.newState()
  assert(M.apply(st, rec("settings", "settings", "GM", { squadsEnabled = true, minCreateRank = 9, bench = 0, officerRanks = { 1 } }), ctx))
  assert(M.apply(st, rec("squad", "S1", "Cap", { name = "Lobos", captain = "Cap", members = { "Cap" }, bench = {}, icon = 3, color = 2, border = 2 }), ctx))
  assert(M.apply(st, rec("profile", "Cap", "Cap", { squad = "S1" }), ctx))
  return st
end

test("achievementProgress: bosses, forever dungeons, HK, captures, squad60, capped at need", function()
  local s = Pr.newStore()
  local function add(e) assert(Pr.add(s, e)) end
  local fk = NS.Content.foreverDungeonKeys()
  ok(#fk >= 3, "forever dungeons known")
  for i = 1, 3 do
    local e = NS.Content.get(fk[i])
    for _, who in ipairs({ "Ann", "Bob" }) do
      add({ t = "boss", who = who, sid = "S1", ts = T0 + i * 86400 + (who == "Bob" and 5 or 0), inst = e.name,
            it = "party", enc = 100 + i, boss = "B" .. i, gs = 5, pres = {} })
    end
  end
  add({ t = "hk", who = "Ann", sid = "S1", ts = T0 + 10, n = 62 })
  add({ t = "cap", who = "Ann", sid = "S1", ts = T0 + 11, n = 3 })
  for i = 1, 3 do add({ t = "hk", who = "Zed", sid = "S2", ts = T0 + 12 + i, n = 40 }) end -- other squad: ignored
  local lv = { Ann = 60, Bob = 60, Cid = 42 }
  local p = Pr.achievementProgress("S1", s.events, { members = function() return { "Ann", "Bob", "Cid" } end,
                                                       levelOf = function(n) return lv[n] end })
  eq(p.boss10.cur, 3, "3 witnessed kills"); eq(p.boss10.need, 10); eq(p.boss50.need, 50)
  eq(p.forever.need, #fk); eq(p.forever.unit, "dungeon")
  eq(p.hk100.cur, 62, "62/100 HK"); eq(p.hk100.need, 100); eq(p.conq.cur, 3); eq(p.conq.need, 10)
  eq(p.squad60.cur, 2); eq(p.squad60.need, 5)
  eq(p.firstDungeon.cur, 1)
  local p2 = Pr.achievementProgress("S2", s.events, {})
  eq(p2.hk100.cur, 100, "capped at need"); eq(p2.boss10.cur, 0); eq(p2.squad60, nil, "no roster ctx: omitted")
  eq(p.forever.cur, 3, "3/9 mazmorras")
end)

test("Reject: request rejected by captain is durable, synced, idempotent, re-request shows again", function()
  local st = world()
  assert(M.apply(st, rec("profile", "Bob", "Bob", { squad = "S1", reqAt = 500 }), ctx))
  eq(#M.requests(st, "S1"), 1, "Bob requested")
  -- authority: only the captain (or GM) rejects a request
  local forged = rec("reject", M.rejectId("S1", "Bob", "req"), "Cid", { sid = "S1", name = "Bob", kind = "req", at = 500, on = true })
  local okF, why = M.apply(st, forged, ctx); ok(not okF); eq(why, "denied")
  local r = rec("reject", M.rejectId("S1", "Bob", "req"), "Cap", { sid = "S1", name = "Bob", kind = "req", at = 500, on = true })
  ok(M.apply(st, r, ctx)); eq(#M.requests(st, "S1"), 0, "rejected")
  ok(M.isRejected(st, "S1", "Bob", "req"))
  -- repeated rejection: same record = dup, nothing changes
  local okD, whyD = M.apply(st, r, ctx); ok(not okD); eq(whyD, "dup")
  eq(#M.requests(st, "S1"), 0)
  -- bad id / shape
  ok(not M.apply(st, rec("reject", "x", "Cap", { sid = "S1", name = "Bob", kind = "req", at = 1 }), ctx), "id must match")
  ok(not M.apply(st, rec("reject", M.rejectId("S1", "Bob", "zz"), "Cap", { sid = "S1", name = "Bob", kind = "zz" }), ctx))
  -- sync: a second client converges via records / export (durable between sessions)
  local st2 = world()
  assert(M.apply(st2, rec("profile", "Bob", "Bob", { squad = "S1", reqAt = 500 }), ctx))
  local a = M.import(st2, M.export(st), ctx)
  ok(a >= 1); eq(#M.requests(st2, "S1"), 0, "rejection replicated")
  eq(#M.diffRecords(st, "reject", M.bucketHashes(st2, "reject")), 0, "reject buckets agree")
  -- Bob asks again later: new reqAt => visible again
  assert(M.apply(st, rec("profile", "Bob", "Bob", { squad = "S1", reqAt = 900 }), ctx))
  eq(#M.requests(st, "S1"), 1, "new request after rejection is shown")
end)

test("Reject: invitation declined only by the invited player, durable", function()
  local st = world()
  assert(M.apply(st, rec("squad", "S1", "Cap", { name = "Lobos", captain = "Cap", members = { "Cap", "Dan" }, bench = {}, icon = 3, color = 2, border = 2 }), ctx))
  eq(#M.invites(st, "Dan"), 1)
  ok(not M.apply(st, rec("reject", M.rejectId("S1", "Dan", "inv"), "Cap", { sid = "S1", name = "Dan", kind = "inv", on = true }), ctx), "captain cannot decline for Dan")
  ok(M.apply(st, rec("reject", M.rejectId("S1", "Dan", "inv"), "Dan", { sid = "S1", name = "Dan", kind = "inv", on = true }), ctx))
  eq(#M.invites(st, "Dan"), 0, "declined")
  local again = rec("reject", M.rejectId("S1", "Dan", "inv"), "Dan", { sid = "S1", name = "Dan", kind = "inv", on = true })
  ok(M.apply(st, again, ctx)); eq(#M.invites(st, "Dan"), 0, "repeated decline changes nothing")
  ok(M.apply(st, rec("reject", M.rejectId("S1", "Dan", "inv"), "Dan", { sid = "S1", name = "Dan", kind = "inv", on = false }), ctx))
  eq(#M.invites(st, "Dan"), 1, "withdrawn")
end)

test("inactivity: all members seen >= N days ago; unknown or 'never' => active", function()
  local st = world()
  assert(M.apply(st, rec("squad", "S1", "Cap", { name = "Lobos", captain = "Cap", members = { "Cap", "Bob" }, bench = {}, icon = 3, color = 2, border = 2 }), ctx))
  assert(M.apply(st, rec("profile", "Bob", "Bob", { squad = "S1" }), ctx))
  local seen = { Cap = 20, Bob = 15 }
  local f = function(n) return seen[n] end
  ok(M.isInactive(st, "S1", f, 14)); ok(not M.isInactive(st, "S1", f, 30)); ok(not M.isInactive(st, "S1", f, 0), "never")
  seen.Bob = 0; ok(not M.isInactive(st, "S1", f, 14), "one member online")
  seen.Bob = nil; ok(not M.isInactive(st, "S1", f, 7), "unknown last online")
end)

test("settings validation: ranks clamped, weights 0..3, caps / days / max squads from allowed lists", function()
  local st = M.newState()
  ok(M.apply(st, rec("settings", "settings", "GM", { minCreateRank = 15, bench = 7, wLevel = 5, wDungeon = -2, wRaid = 1.7,
     wPvp = 0, weekCap = 120, inactiveDays = 9, maxSquads = 33, officerRanks = { 1, 1, 12, 0, 3 }, guildGoal = -4 }), ctx))
  local s = M.settingsOf(st)
  eq(s.minCreateRank, 9); eq(s.bench, 2); eq(s.wLevel, 3); eq(s.wDungeon, 0); eq(s.wRaid, 1); eq(s.wPvp, 0)
  eq(s.weekCap, 100, "cap not allowed -> default"); eq(s.inactiveDays, 14); eq(s.maxSquads, 0); eq(s.guildGoal, 1)
  ok(deq(s.officerRanks, { 1, 3 }), "officer ranks deduped and within 1..9")
  ok(M.apply(st, rec("settings", "settings", "GM", { minCreateRank = -3, weekCap = 150, inactiveDays = 30, maxSquads = 10, wWpvp = 2 }), ctx))
  s = M.settingsOf(st)
  eq(s.minCreateRank, 0); eq(s.weekCap, 150); eq(s.inactiveDays, 30); eq(s.maxSquads, 10); eq(s.wWpvp, 2)
  local _, fixed = M.normalizeSettings({ weekCap = 200, wLevel = 2 }); eq(#fixed, 0, "valid input untouched")
  -- authority unchanged: only rank 0
  local okO, why = M.apply(st, rec("settings", "settings", "Off", { minCreateRank = 1 }), ctx); ok(not okO); eq(why, "denied")
end)

test("backward compatibility: older settings and SavedVariables state without the newer fields", function()
  local v4 = { k = "settings", id = "settings", a = "GM", ts = 10, sq = 1,
               d = { squadsEnabled = true, weekCap = 100, wPvp = 1, overlordOn = true, seasonName = "T1", seasonStart = 1, seasonEnd = 0 } }
  local st = { profiles = {}, squads = {}, settings = nil } -- state shape: no rejects table
  ok(M.apply(st, v4, ctx))
  local s = M.settingsOf(st)
  eq(s.inactiveDays, 14); eq(s.maxSquads, 0); eq(s.ovHint, true); eq(s.seasonName, "T1")
  eq(#M.requests(st, "none"), 0); eq(#M.allRecords(st), 1)
  ok(M.bucketHashes(st, "reject"), "reject kind hashes on an older state")
end)

test("moderation: officer may reset name/logo to neutral or disband, nothing else; max squads", function()
  local st = world()
  local cur = st.squads.S1.d
  local function with(t) local d = {}; for k, v in pairs(cur) do d[k] = v end; for k, v in pairs(t) do d[k] = v end; return d end
  ok(not M.apply(st, rec("squad", "S1", "Off", with({ name = "Otro" })), ctx), "officer cannot rename freely")
  ok(M.apply(st, rec("squad", "S1", "Off", with({ name = M.resetName("S1"), icon = 1, color = 1, border = 1, motto = "" })), ctx))
  eq(st.squads.S1.d.name, M.resetName("S1"))
  ok(M.apply(st, rec("settings", "settings", "GM", { squadsEnabled = true, minCreateRank = 9, officerRanks = { 1 }, maxSquads = 10 }), ctx))
  for i = 1, 9 do
    local n = "P" .. i
    local r2 = makeRoster({ [n] = 4 })
    assert(M.apply(st, rec("squad", "X" .. i, n, { name = "Squad nr " .. i, captain = n, members = { n }, bench = {} }), { roster = r2 }))
  end
  eq(M.liveSquads(st), 10)
  local okM, why = M.apply(st, rec("squad", "X10", "Bob", { name = "Once", captain = "Bob", members = { "Bob" }, bench = {} }), ctx)
  ok(not okM); eq(why, "maxSquads")
end)

test("schema: positive whitelist includes reject; no economy fields anywhere", function()
  ok(M.SCHEMA.reject and M.SCHEMA.reject.sid and M.SCHEMA.reject.kind and M.SCHEMA.reject.at, "reject schema")
  ok(M.SCHEMA.settings.inactiveDays and M.SCHEMA.settings.maxSquads and M.SCHEMA.profile.reqAt)
  for kind, fields in pairs(M.SCHEMA) do
    for f in pairs(fields) do ok(not f:lower():find("gold") and not f:lower():find("money") and not f:lower():find("trade"), kind .. "." .. f) end
  end
  local d = M.sanitize("reject", { sid = "S", name = "N", kind = "req", at = 1, gold = 5, extra = "x" })
  eq(d.gold, nil); eq(d.extra, nil); eq(d.sid, "S")
end)
