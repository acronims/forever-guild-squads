-- raid rosters 10 / 20 / 40 (builder, authority, states, RSVP, attendance, schema)
local R, M = NS.Roster, NS.Model
local T0 = 1795000000

-- guild: Gm rank 0, Off rank 1 (officer), Rl rank 4 (in the RL list), Mem rank 4, others rank 5
local ranks = { ["Gm-R"] = 0, ["Off-R"] = 1, ["Rl-R"] = 4, ["Mem-R"] = 4 }
for i = 1, 60 do ranks["P" .. i .. "-R"] = 5 end
local roster = makeRoster(ranks)

local function freshState(offEdit)
  local s = M.newState()
  ok(M.apply(s, { k = "settings", id = "settings", a = "Gm-R", ts = T0, sq = 1,
                  d = { squadsEnabled = true, officerRanks = { 1 }, rlList = { "Rl-R" }, offEdit = offEdit or false } },
             { roster = roster }), "settings")
  return s
end
local seq = 0
local function put(s, kind, id, author, d, ts, sender)
  seq = seq + 1
  return M.apply(s, { k = kind, id = id, a = author, ts = ts or (T0 + seq), sq = seq, d = d }, { roster = roster, sender = sender })
end
local function base(size, raid)
  return R.new({ raid = raid or "custom", size = size, name = "Raid A martes", at = R.civil(2026, 12, 9, 20, 0) })
end
local ROLE = {}
local function roleOf(n) return ROLE[n] end
local CLASS = {}
local function classOf(n) return CLASS[n] end
local function fill(d, t, h, dps)
  local i = 0
  local function add(role, k) for _ = 1, k do i = i + 1; local n = "P" .. i .. "-R"; ROLE[n] = role; ok(R.addPlayer(d, n)) end end
  add("TANK", t); add("HEALER", h); add("DAMAGER", dps)
end
local function kinds(w) local o = {}; for _, x in ipairs(w) do o[#o + 1] = x.kind .. ":" .. tostring(x.role or x.key or "") .. ":" .. tostring(x.n or "") end; table.sort(o); return table.concat(o, ",") end

test("coverage vs the template in the 3 sizes", function()
  ok(R.registerOK ~= false and M.EXT.roster and M.EXT.rsvp and M.EXT.attendance, "kinds registered")
  -- 10: exact proposal 2T/2H/6D -> no role warning
  local d = base(10, "barrow"); fill(d, 2, 2, 6)
  local w = R.warnings(d, roleOf, classOf, {})
  eq(kinds(w), "", "10 full and in range")
  -- 20: 1T 4H 12D -> missing 1 T, 3 empty
  d = base(20, "hyjal"); fill(d, 1, 4, 12)
  eq(kinds(R.warnings(d, roleOf, classOf, {})), "empty::3,missing:TANK:1")
  -- 40: 4T 8H 28D +... 6T 8H 26D = 40 -> all within; then 3T 11H 26D -> missing T, extra H
  d = base(40, "onyxia"); fill(d, 6, 8, 26)
  eq(kinds(R.warnings(d, roleOf, classOf, {})), "")
  d = base(40, "onyxia"); fill(d, 3, 11, 26)
  eq(kinds(R.warnings(d, roleOf, classOf, {})), "extra:HEALER:1,missing:TANK:1")
  local c = R.coverage(d, roleOf); eq(c.TANK, 3); eq(c.HEALER, 11); eq(c.DAMAGER, 26); eq(c.filled, 40)
  -- templates: proposals per size, editable, impossible ones fall back
  eq(R.defaultTpl(10), "2-2/2-3/5-6"); eq(R.defaultTpl(20), "2-3/4-5/12-14"); eq(R.defaultTpl(40), "4-6/8-10/24-28")
  eq(R.tplString(R.parseTpl("1-2/2-2/6-7", 10)), "1-2/2-2/6-7", "edited template kept")
  eq(R.tplString(R.parseTpl("9-9/9-9/9-9", 10)), "2-2/2-3/5-6", "impossible template -> default")
  -- utility table: missing decurse in a 10 without mage/druid; GM table replaces the defaults
  d = base(10); fill(d, 2, 2, 6)
  for i = 1, 10 do CLASS["P" .. i .. "-R"] = "WARRIOR" end
  CLASS["P3-R"] = "PRIEST"
  local wk = kinds(R.warnings(d, roleOf, classOf, R.DEFAULT_UTIL))
  ok(wk:find("util:decurse", 1, true) and not wk:find("util:fort", 1, true) and not wk:find("util:motw", 1, true), wk)
  local util = R.utilTable({ rutil = { "decurse:MAGE+DRUID:10", "bad entry", "sstone:WARLOCK:10" } })
  eq(#util, 2); eq(util[2].key, "sstone")
  eq(R.utilTable({ rutil = {} }), R.DEFAULT_UTIL)
  eq(R.utilTable({ rutil = R.utilStrings(R.DEFAULT_UTIL) })[8].key, "brez", "round trip")
end)

test("add a squad: together in one group; when it does not fit, the titulares that fit and a warning", function()
  local d = base(10)
  local r1 = R.addSquad(d, { "A1", "A2", "A3", "A4", "A5" }, { "A6" })
  eq(#r1.added, 6); eq(#r1.notFit, 0); ok(not r1.split)
  ok(deq(R.groups(d)[1], { "A1", "A2", "A3", "A4", "A5" }), "squad 1 = G1")
  eq(d.main[6], "A6", "its bench takes a free slot")
  local r2 = R.addSquad(d, { "B1", "B2", "B3", "B4", "B5" }, { "B6", "B7" })
  ok(r2.split, "does not fit in one group -> split")
  eq(#r2.notFit, 1, "one titular does not fit"); eq(r2.notFit[1], "B5")
  eq(R.filled(d), 10)
  ok(deq(d.bench, { "B6", "B7" }), "squad bench goes to the roster bench")
  -- 20: second squad lands in G2 whole
  local d2 = base(20)
  R.addSquad(d2, { "A1", "A2", "A3" }); R.addSquad(d2, { "B1", "B2", "B3", "B4", "B5" })
  ok(deq(R.groups(d2)[2], { "B1", "B2", "B3", "B4", "B5" }), "B in G2: " .. table.concat(R.groups(d2)[2], ","))
  eq(R.subgroupPlan(d2)["B3"], 2); eq(R.subgroupPlan(d2)["A1"], 1)
end)

test("nobody appears twice (builder and validation)", function()
  local d = base(10)
  ok(R.addPlayer(d, "X-R")); local okA, why = R.addPlayer(d, "X-R"); ok(not okA and why == "dup")
  okA, why = R.addPlayer(d, "X-R", "bench"); ok(not okA and why == "dup", "not on the bench either")
  local r = R.addSquad(d, { "X-R", "Y-R" }); ok(deq(r.added, { "Y-R" }), "already listed member skipped")
  -- validation rejects a forged duplicate
  local s = freshState()
  local bad = R.new({ size = 10, name = "Dup", at = T0 }); bad.main[1] = "P1-R"; bad.bench = { "P1-R" }
  local okP, whyP = put(s, "roster", "Rl-R:1", "Rl-R", bad)
  ok(not okP and whyP == "dupPlayer", tostring(whyP))
  -- full + over-size main refused
  local big = R.new({ size = 10, name = "Big", at = T0 }); for i = 1, 11 do big.main[i] = "P" .. i .. "-R" end
  okP, whyP = put(s, "roster", "Rl-R:2", "Rl-R", big); ok(not okP and whyP == "full", tostring(whyP))
  local full = base(10); for i = 1, 10 do R.addPlayer(full, "Q" .. i) end
  okA, why = R.addPlayer(full, "Q11"); ok(not okA and why == "full")
  ok(R.movePlayer(full, "Q10", "bench") and full.main[10] == "" and full.bench[1] == "Q10", "move to bench")
  ok(R.movePlayer(full, "Q10", 1) and full.main[1] == "Q10" and full.bench[1] == "Q1", "swap from bench")
end)

test("authority: author (RL), GM, officers only when enabled; relay rule unchanged", function()
  local s = freshState(false)
  local d = base(10, "barrow")
  ok(not put(s, "roster", "Mem-R:1", "Mem-R", R.copy(d)), "a plain member cannot create")
  ok(put(s, "roster", "Rl-R:1", "Rl-R", R.copy(d)), "RL creates")
  eq(s.rosters["Rl-R:1"].d.owner, "Rl-R", "owner = author")
  local e = R.copy(s.rosters["Rl-R:1"].d); e.name = "Raid B"
  local okP, why = put(s, "roster", "Rl-R:1", "Off-R", R.copy(e)); ok(not okP and why == "denied", "officer denied by default")
  okP = put(s, "roster", "Rl-R:1", "Mem-R", R.copy(e)); ok(not okP, "member denied")
  e.owner = "Mem-R"
  ok(put(s, "roster", "Rl-R:1", "Rl-R", R.copy(e)), "owner edits")
  eq(s.rosters["Rl-R:1"].d.owner, "Rl-R", "owner immutable")
  e.name = "Raid C"; ok(put(s, "roster", "Rl-R:1", "Gm-R", R.copy(e)), "GM edits")
  -- GM enables officers
  ok(M.apply(s, { k = "settings", id = "settings", a = "Gm-R", ts = T0 + 500, sq = 900,
                  d = { squadsEnabled = true, officerRanks = { 1 }, rlList = { "Rl-R" }, offEdit = true } }, { roster = roster }))
  e.name = "Raid D"; ok(put(s, "roster", "Rl-R:1", "Off-R", R.copy(e), T0 + 600), "officer edits when enabled")
  -- RL removed from the list loses edit rights on their own roster
  ok(M.apply(s, { k = "settings", id = "settings", a = "Gm-R", ts = T0 + 700, sq = 901,
                  d = { squadsEnabled = true, officerRanks = { 1 }, rlList = {}, offEdit = true } }, { roster = roster }))
  e.name = "Raid E"; okP, why = put(s, "roster", "Rl-R:1", "Rl-R", R.copy(e), T0 + 800); ok(not okP and why == "denied", tostring(why))
  -- relays: a member relaying the GM's roster is refused, the author live is fine
  local s2 = freshState()
  okP, why = put(s2, "roster", "Gm-R:9", "Gm-R", base(10), nil, "Mem-R"); ok(not okP and why == "relay", tostring(why))
  ok(put(s2, "roster", "Gm-R:9", "Gm-R", base(10), nil, "Gm-R"), "live from the author")
  -- catalog raid must match its size
  local wrong = base(20, "barrow"); okP, why = put(s2, "roster", "Gm-R:10", "Gm-R", wrong); ok(not okP and why == "raid", tostring(why))
  local badSize = base(10); badSize.size = 25; okP, why = put(s2, "roster", "Gm-R:11", "Gm-R", badSize); ok(not okP and why == "size")
end)

test("states and transitions", function()
  eq(R.canTransition("draft", "published"), true); eq(R.canTransition("published", "closed"), true)
  eq(R.canTransition("draft", "cancelled"), true); eq(R.canTransition("published", "cancelled"), true)
  eq(R.canTransition("draft", "closed"), false); eq(R.canTransition("closed", "published"), false)
  eq(R.canTransition("cancelled", "draft"), false); eq(R.canTransition("published", "draft"), false)
  local s = freshState()
  local d = base(10)
  -- versions are ordered by state rank, so a peer that missed the earlier versions accepts a
  -- close it sees first (ordering by "state" / "transition" would leave those peers diverged forever)
  local okP, why
  d.st = "closed"; ok(put(freshState(), "roster", "Rl-R:1", "Rl-R", R.copy(d)), "a close seen first is accepted")
  d.st = "draft"; ok(put(s, "roster", "Rl-R:1", "Rl-R", R.copy(d)))
  d.st = "published"; ok(put(s, "roster", "Rl-R:1", "Rl-R", R.copy(d)))
  d.st = "draft"; okP, why = put(s, "roster", "Rl-R:1", "Rl-R", R.copy(d)); ok(not okP and why == "transition", tostring(why))
  d.st = "closed"; ok(put(s, "roster", "Rl-R:1", "Rl-R", R.copy(d)))
  d.st = "closed"; d.name = "changed"; okP, why = put(s, "roster", "Rl-R:1", "Rl-R", R.copy(d)); ok(not okP and why == "closed", tostring(why))
  d.st = "bogus"; okP, why = put(s, "roster", "Rl-R:2", "Rl-R", R.copy(d)); ok(not okP and why == "state")
end)

test("RSVP: only yourself, last one wins, yes/maybe/no/bench, comment <= 60", function()
  local s = freshState()
  local d = base(10); R.addPlayer(d, "Mem-R"); d.st = "published"
  ok(put(s, "roster", "Rl-R:1", "Rl-R", d))
  local id = R.rsvpId("Rl-R:1", "Mem-R")
  local okP, why = put(s, "rsvp", id, "Rl-R", { rid = "Rl-R:1", name = "Mem-R", v = "yes" }); ok(not okP and why == "denied", "not for others")
  okP, why = put(s, "rsvp", id, "Mem-R", { rid = "Rl-R:1", name = "Mem-R", v = "Si" }); ok(not okP and why == "shape", "bad answer")
  okP, why = put(s, "rsvp", "x|Mem-R", "Mem-R", { rid = "Rl-R:1", name = "Mem-R", v = "yes" }); ok(not okP and why == "shape", "id mismatch")
  for _, v in ipairs({ "yes", "maybe", "no", "bench" }) do
    ok(put(s, "rsvp", id, "Mem-R", { rid = "Rl-R:1", name = "Mem-R", v = v, c = string.rep("x", 80) }), v)
    eq(R.rsvpOf(s, "Rl-R:1", "Mem-R").v, v, "last wins: " .. v)
  end
  eq(#R.rsvpOf(s, "Rl-R:1", "Mem-R").c, 60, "comment cut to 60")
  -- an older answer arriving late loses
  okP, why = put(s, "rsvp", id, "Mem-R", { rid = "Rl-R:1", name = "Mem-R", v = "yes" }, T0 - 5); ok(not okP and why == "stale")
  ok(put(s, "rsvp", id, "Mem-R", { rid = "Rl-R:1", name = "Mem-R", v = "yes" }, T0 + 9000))
  ROLE["Mem-R"] = "HEALER"
  local c = R.rsvpCount(s, "Rl-R:1", roleOf); eq(c.yes, 1); eq(c.roles.HEALER, 1)
  ok(deq(R.confirmed(s, "Rl-R:1"), { "Mem-R" }))
  -- an answer after the close is stored (same set on every peer) but changes nothing
  d.st = "closed"; ok(put(s, "roster", "Rl-R:1", "Rl-R", d, T0 + 9100))
  ok(put(s, "rsvp", id, "Mem-R", { rid = "Rl-R:1", name = "Mem-R", v = "no" }, T0 + 9200))
  eq(R.rsvpOf(s, "Rl-R:1", "Mem-R"), nil, "the late answer is ignored")
end)

test("attendance: signed by the RL, % of the last 8", function()
  local s = freshState()
  local at0 = R.civil(2026, 12, 1, 20, 0)
  for i = 1, 10 do
    local d = R.new({ size = 10, name = "R" .. i, at = at0 + i * R.WEEK }); R.addPlayer(d, "Mem-R"); d.st = "published"
    ok(put(s, "roster", "Rl-R:" .. i, "Rl-R", d))
    local dc = R.copy(d); dc.st = "closed"; ok(put(s, "roster", "Rl-R:" .. i, "Rl-R", dc))   -- signed once closed
    -- Mem present in raids 1..4 and 9, absent in 5..8 and 10
    local here = (i <= 4 or i == 9) and { "Mem-R", "Rl-R" } or { "Rl-R" }
    if i == 3 then
      local okP, why = put(s, "attendance", "Rl-R:3", "Mem-R", { rid = "Rl-R:3", names = here }); ok(not okP and why == "denied", "only the RL")
    end
    ok(put(s, "attendance", "Rl-R:" .. i, "Rl-R", { rid = "Rl-R:" .. i, names = here, at = d.at }))
  end
  local pct, here, n = R.attendanceStats(s, "Mem-R")
  eq(n, 8, "last 8"); eq(here, 3, "present in 3..4, 9 -> 3 of raids 3..10"); eq(pct, 38)
  pct = R.attendanceStats(s, "Nobody-R"); eq(pct, nil, "no data")
  local okP, why = put(s, "attendance", "Ghost:1", "Rl-R", { rid = "Ghost:1", names = {} }); ok(not okP and why == "noRoster")
  -- duplicates in names are collapsed
  ok(put(s, "attendance", "Rl-R:10", "Rl-R", { rid = "Rl-R:10", names = { "Mem-R", "Mem-R", "Rl-R" } }, T0 + 99999))
  eq(#s.attendance["Rl-R:10"].d.names, 2)
end)

test("weekly template: +7 days at the same realm hour across the DST change", function()
  -- Europe/Madrid offset: CEST until 2026-10-25 01:00 UTC, then CET
  local switch = R.civil(2026, 10, 25, 1, 0)
  local function madrid(epoch) return epoch < switch and 7200 or 3600 end
  local at = R.civil(2026, 10, 20, 20, 0)   -- Tuesday 20:00 realm time
  local nxt = R.nextWeek(at)
  eq(R.fmtWall(nxt), "2026-10-27 20:00", "same wall-clock hour")
  local y, m, d, h, mi, wd = R.fields(nxt); eq(wd, 2, "still a Tuesday"); eq(h, 20)
  eq(R.wallToEpoch(nxt, madrid) - R.wallToEpoch(at, madrid), R.WEEK + 3600, "real gap = 7 d + 1 h over the change")
  eq(R.wallToEpoch(at, madrid), R.civil(2026, 10, 20, 18, 0), "20:00 CEST = 18:00 UTC")
  eq(R.fmtWall(R.civil(2024, 2, 29, 23, 59)), "2024-02-29 23:59", "leap day round trip")
  local s = freshState()
  local d0 = R.new({ size = 20, raid = "hyjal", name = "Raid A martes", at = at, wk = true }); d0.st = "published"
  ok(put(s, "roster", "Rl-R:1", "Rl-R", d0))
  eq(#R.dueRepeats(s, "Rl-R", at - 60), 0, "not yet")
  local due = R.dueRepeats(s, "Rl-R", at + 60); eq(#due, 1)
  local dup = R.duplicate(due[1].d, due[1].id)
  eq(dup.st, "draft"); eq(dup.prev, "Rl-R:1"); eq(R.fmtWall(dup.at), "2026-10-27 20:00")
  ok(put(s, "roster", "Rl-R:2", "Rl-R", dup))
  eq(#R.dueRepeats(s, "Rl-R", at + 60), 0, "one successor only")
  eq(#R.dueRepeats(s, "Gm-R", at + 60), 0, "only the owner's client creates it")
  ok(R.remindDue({ st = "published", at = at }, at - 1800) and not R.remindDue({ st = "published", at = at }, at - 7200))
  ok(R.autoCloseDue({ st = "published", at = at }, at + R.CLOSE_AFTER + 1) and not R.autoCloseDue({ st = "published", at = at }, at + 60))
end)

test("invite: never in combat, batches by group limit, missing ConvertToRaid / SetRaidSubgroup do not error", function()
  local d = base(10)
  R.addSquad(d, { "Me", "A2", "A3", "A4", "A5" }); R.addSquad(d, { "B1", "B2", "B3", "B4", "B5" })
  local names = R.names(d)
  local invited, group, raid, combat = {}, { Me = true }, false, true
  local function size() local n = 0 for _ in pairs(group) do n = n + 1 end return n end
  local api = { inCombat = function() return combat end, invite = function(n) invited[#invited + 1] = n end,
                isRaid = function() return raid end, groupSize = size, inGroup = function(n) return group[n] == true end }
  -- a pending invite is not repeated for 60 s; this test advances the clock 61 s per click
  local clk = 1000
  api.now = function() clk = clk + 61; return clk end
  local r = R.invite(api, d, names, "Me"); eq(r.reason, "combat"); eq(#invited, 0, "nothing in combat")
  api.inCombat = function() error("boom") end
  r = R.invite(api, d, names, "Me"); eq(r.reason, "combat", "a failing combat check counts as combat")
  api.inCombat = function() return false end
  -- party of 1: at most 4 invites
  r = R.invite(api, d, names, "Me"); eq(r.invited, 4); eq(r.remaining, 5); eq(#invited, 4)
  -- two accepted; no ConvertToRaid in this client -> warn, invite only up to 5, no error
  group.A2 = true; group.A3 = true; invited = {}
  r = R.invite(api, d, names, "Me"); ok(r.noConvert, "convert missing flagged"); eq(r.invited, 2, "fills the party")
  -- with ConvertToRaid: converts then invites the rest (40-cap)
  api.convert = function() raid = true end
  invited = {}
  r = R.invite(api, d, names, "Me"); ok(r.converted); eq(r.invited, 7); eq(r.remaining, 0)
  eq(r.sub, "missing", "no SetRaidSubgroup -> skipped and reported")
  -- SetRaidSubgroup present but failing -> "failed", no error; working -> placed by squad
  local members = {}
  for i, n in ipairs(names) do members[#members + 1] = { name = n, index = i, sub = (i % 2) + 1 } end
  api.members = function() return members end
  api.setSub = function() error("protected") end
  r = R.invite(api, d, names, "Me"); eq(r.sub, "failed")
  for i, n in ipairs(names) do members[i] = { name = n, index = i, sub = (i <= 4) and 1 or 2 } end
  local moved = {}
  api.setSub = function(idx, g) moved[#moved + 1] = idx .. ">" .. g end
  api.swapSub = function(a, b) moved[#moved + 1] = a .. "<>" .. b end
  r = R.invite(api, d, names, "Me"); eq(r.sub, "ok")
  local plan = R.subgroupPlan(d)
  for _, m in ipairs(members) do eq(m.sub, plan[m.name], "placed: " .. m.name) end
  -- no InviteUnit at all
  r = R.invite({ inCombat = function() return false end }, d, names, "Me"); eq(r.reason, "noInvite")
end)

test("schema: roster / rsvp / attendance sanitised (positive) and replicated through Model", function()
  local s = freshState()
  local d = base(20, "hyjal"); d.evil = "x"; d.gold = 5; d.name = "  Raid A martes  "; d.tpl = "2-3/4-5/12-14"
  R.addPlayer(d, "Mem-R"); d.st = "published"; d.wk = true
  ok(put(s, "roster", "Rl-R:1", "Rl-R", d))
  local st = s.rosters["Rl-R:1"].d
  eq(st.evil, nil); eq(st.gold, nil); eq(st.name, "Raid A martes"); eq(st.raid, "hyjal"); eq(st.size, 20)
  eq(#st.main, 20, "main padded to the size"); eq(st.main[1], "Mem-R"); eq(st.tpl, "2-3/4-5/12-14"); eq(st.wk, true)
  ok(put(s, "rsvp", R.rsvpId("Rl-R:1", "Mem-R"), "Mem-R", { rid = "Rl-R:1", name = "Mem-R", v = "maybe", c = "llego tarde", x = 1 }))
  local rv = s.rsvps[R.rsvpId("Rl-R:1", "Mem-R")].d
  eq(rv.v, "maybe"); eq(rv.c, "llego tarde"); eq(rv.x, nil)
  local dc = R.copy(st); dc.st = "closed"; ok(put(s, "roster", "Rl-R:1", "Rl-R", dc))   -- attendance once closed
  ok(put(s, "attendance", "Rl-R:1", "Rl-R", { rid = "Rl-R:1", names = { "Mem-R" }, at = st.at, loot = "x" }))
  eq(s.attendance["Rl-R:1"].d.loot, nil); eq(s.attendance["Rl-R:1"].d.names[1], "Mem-R")
  -- export / import and bucket hashes carry the new kinds
  local all = M.allRecords(s)
  local k = {}; for _, r in ipairs(all) do k[r.k] = (k[r.k] or 0) + 1 end
  eq(k.roster, 1); eq(k.rsvp, 1); eq(k.attendance, 1)
  local s2 = M.newState()
  local applied = M.import(s2, M.export(s), { roster = roster })
  eq(applied, 4, "settings + roster + rsvp + attendance imported in order")
  ok(s2.rosters["Rl-R:1"] and s2.rsvps[R.rsvpId("Rl-R:1", "Mem-R")] and s2.attendance["Rl-R:1"])
  ok(deq(M.bucketHashes(s, "roster"), M.bucketHashes(s2, "roster")), "same hashes")
  eq(#M.diffRecords(s, "rsvp", M.bucketHashes(s2, "rsvp")), 0)
  eq(M.stored(s, { k = "roster", id = "Rl-R:1" }), s.rosters["Rl-R:1"])
  -- validShape knows the new kinds; unknown ones are still refused
  ok(M.validShape({ k = "roster", id = "x", a = "Rl-R", ts = 1, sq = 1, d = {} }))
  ok(not M.validShape({ k = "loot", id = "x", a = "Rl-R", ts = 1, sq = 1, d = {} }))
  -- export text for Discord
  ROLE["Mem-R"] = "HEALER"
  local txt = R.exportText(s, "Rl-R:1", roleOf, { group = "G", bench = "Suplentes" })
  ok(txt:find("Raid A martes", 1, true) and txt:find("Hyjal Summit", 1, true) and txt:find("G1: Mem (H)", 1, true), txt)
end)

-- smoke (runs inside tests/zload_spec.lua with the fake client): Bandas tab, roster of 10 with 2 squads, publish,
-- RSVP (own + replicated + forged relay), invite with a mock group API (combat first), close, export, geometry.
SMOKE_CHECKS = SMOKE_CHECKS or {}
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "smoke: Raids tab, 10 with 2 squads, publish, RSVP, invite (mock), close, export, geometry", function(c)
  local ns, click, geo, win = c.ns, c.click, c.geo, c.win
  local UI, G, Rr = ns.UI, ns.RaidGlue, ns.Roster
  -- two squads as fixtures (captains count as members)
  local T = (GetServerTime and GetServerTime() or 0) - 50
  ns.state.squads["S1"] = { k = "squad", id = "S1", a = "Bob-Realm", ts = T, sq = 1, d = { name = "Lobos", captain = "Bob-Realm", members = { "Bob-Realm" }, bench = {} } }
  ns.state.squads["S2"] = { k = "squad", id = "S2", a = "Cid-Realm", ts = T, sq = 1, d = { name = "Osos", captain = "Cid-Realm", members = { "Cid-Realm" }, bench = {} } }
  ok(G.CanLead(), "the GM can lead")
  UI.Select("raids"); eq(UI.Current(), "raids", "Bandas tab opens")
  local rb = UI.RaidsState()
  rb.view, rb.rid, rb.draft, rb.dirty, rb.filter = "list", nil, nil, false, "upcoming"
  rb.role, rb.online, rb.search = nil, false, ""  -- the click-everything pass left it anywhere
  UI.Select("raids"); eq(rb.view, "list")
  -- tab order: Ranking, Bandas, Salón de la fama
  local pos = {}
  for i, k in ipairs(UI.order) do pos[k] = i end
  ok(pos.raids == pos.ranking + 1 and pos.hall == pos.raids + 1, "order ranking < raids < hall")
  -- one red button: "Nueva banda"
  eq(rawget(rb.primary, "_text"), ns.L.RB_NEW)
  click(rb.primary)
  eq(rb.view, "edit", "editor opened"); local rid = rb.rid; ok(rid and G.Get(rid), "draft stored")
  eq(G.Get(rid).d.size, 10); eq(G.Get(rid).d.st, "draft"); eq(G.Get(rid).d.raid, "barrow")
  -- add both squads with the "+" of the add panel
  local function plusFor(sid)
    for _, cell in ipairs(rb.addGrid.cells) do if cell.item and cell.item.squad == sid then return cell.plus end end
  end
  ok(plusFor("S1") and plusFor("S2"), "both squads listed in the add panel")
  click(plusFor("S1")); click(plusFor("S2"))
  eq(rb.draft.main[1], "Bob-Realm", "S1 in G1"); eq(rb.draft.main[2], "Cid-Realm", "S2 fills the same group (fits)")
  ok(rb.dirty, "unsaved changes")
  -- add myself as a player (row with my name)
  rb.search = "ann"; UI.Select("raids")
  for _, cell in ipairs(rb.addGrid.cells) do if cell.item and cell.item.player == "Ann-Realm" then click(cell.plus) end end
  rb.search = ""
  eq(Rr.filled(rb.draft), 3)
  -- publish (red button)
  eq(rawget(rb.primary, "_text"), ns.L.RB_PUBLISH)
  click(rb.primary)
  local rec = G.Get(rid)
  eq(rec.d.st, "published", "published"); eq(Rr.filled(rec.d), 3, "players saved with the publish")
  UI.Select("raids")
  eq(rawget(rb.primary, "_text"), ns.L.RB_INVITE, "primary = Invitar confirmados")
  -- RSVP: mine (click), Bob live over the wire, a forged one relayed by Cid refused
  click(rb.myAns.yes)
  eq(Rr.rsvpOf(ns.state, rid, "Ann-Realm").v, "yes")
  local bob = { k = "rsvp", id = Rr.rsvpId(rid, "Bob-Realm"), a = "Bob-Realm", ts = GetServerTime(), sq = 7, d = { rid = rid, name = "Bob-Realm", v = "yes" } }
  ns.Sync.OnMessage("D", { r = { bob } }, "Cid-Realm")
  eq(Rr.rsvpOf(ns.state, rid, "Bob-Realm"), nil, "relay by a member refused")
  ns.Sync.OnMessage("D", { r = { bob } }, "Bob-Realm")
  eq(Rr.rsvpOf(ns.state, rid, "Bob-Realm").v, "yes", "live answer applied")
  local cnt = Rr.rsvpCount(ns.state, rid, G.roleOf); eq(cnt.yes, 2); eq(cnt.none, 1)
  -- invite: combat first (nothing), then one batch
  local sent = {}
  local origInvite = C_PartyInfo.InviteUnit
  C_PartyInfo.InviteUnit = function(n) sent[#sent + 1] = n end
  local origCombat = InCombatLockdown
  InCombatLockdown = function() return true end
  click(rb.primary); eq(#sent, 0, "no invites in combat")
  InCombatLockdown = origCombat
  click(rb.primary)
  eq(#sent, 1, "one confirmed online player invited"); eq(sent[1], "Bob-Realm")
  C_PartyInfo.InviteUnit = origInvite
  -- attendance seen during the window, then close (confirmation accepted)
  local wall = G.WallNow()
  local d2 = Rr.copy(G.Get(rid).d); d2.at = wall; ok(G.Save(rid, d2), "move the raid to now")
  IsInRaid = function() return true end
  GetNumGroupMembers = function() return 2 end
  GetRaidRosterInfo = function(i) if i == 1 then return "Ann", 2, 1 end return "Bob", 0, 1 end
  G.OnGroupRoster()
  IsInRaid, GetNumGroupMembers, GetRaidRosterInfo = nil, nil, nil
  ok(deq(G.Seen(rid), { "Ann-Realm", "Bob-Realm" }), "seen in the raid: " .. table.concat(G.Seen(rid), ","))
  local origPopup = StaticPopup_Show
  StaticPopup_Show = function(_, _, _, fn) if type(fn) == "function" then fn() end end
  UI.Select("raids"); click(rb.close)
  StaticPopup_Show = origPopup
  eq(G.Get(rid).d.st, "closed", "closed")
  local att = ns.state.attendance[rid]; ok(att and #att.d.names == 2, "attendance record signed by the RL")
  eq(att.a, "Ann-Realm")
  local pct = Rr.attendanceStats(ns.state, "Bob-Realm"); eq(pct, 100)
  -- export for Discord
  local shown
  local origShow = UI.ShowExport
  UI.ShowExport = function(text) shown = text end
  click(rb.export)
  UI.ShowExport = origShow
  ok(shown and shown:find("G1: Bob", 1, true) and shown:find("Barrow Deeps", 1, true), tostring(shown))
  -- geometry: both views of the tab keep their top row clear of the portrait; the bar has one red button
  local root = UI.panels.raids.frame
  local function check(label)
    local n, bad = 0, {}
    for _, o in ipairs(c.allObjs) do
      if o ~= root and c.under(o, root) then
        local left, top, _, _, stretched = geo(o, win)
        if left and not stretched and top > -60 then n = n + 1; if left < 70 then bad[#bad + 1] = math.floor(left) .. "," .. math.floor(top) end end
      end
    end
    ok(n >= 4, label .. " top-row elements measured: " .. n)
    eq(#bad, 0, label .. " inside the portrait zone: " .. tostring(bad[1]))
  end
  UI.Select("raids"); check("editor")
  click(rb.back); eq(rb.view, "list"); check("list")
  local l1 = geo(rb.seg.upcoming, win); local l3, _, w3 = geo(rb.seg.past, win)
  ok(math.abs((l1 + l3 + w3) / 2 - 360) <= 12, "filter row centred: " .. (l1 + l3 + w3) / 2)
  local reds = 0
  for _, o in ipairs(c.allObjs) do if c.under(o, UI.panels.raids.bar) and rawget(o, "isPrimary") then reds = reds + 1 end end
  eq(reds, 1, "one red primary button")
  ok(c.vis(UI.panels.raids.tab) ~= false, "tab visible")
  -- diag lists the group APIs
  ok(G.ApiReport():find("C_PartyInfo.InviteUnit=yes", 1, true) and G.ApiReport():find("SetRaidSubgroup=no", 1, true), G.ApiReport())
end }
