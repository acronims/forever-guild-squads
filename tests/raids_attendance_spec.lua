-- raid rosters: attendance, witnesses, convergence, RSVP rules, prune, weekly copies, confirmations.
local R, M, Pr, Ra = NS.Roster, NS.Model, NS.Progress, NS.Races
local T0 = 1795000000

local ranks = { ["Gm-R"] = 0, ["Off-R"] = 1, ["Rl-R"] = 4, ["Mem-R"] = 4 }
for i = 1, 40 do ranks["P" .. i .. "-R"] = 5 end
local roster = makeRoster(ranks)

local function fresh()
  local s = M.newState()
  ok(M.apply(s, { k = "settings", id = "settings", a = "Gm-R", ts = T0, sq = 1,
                  d = { squadsEnabled = true, officerRanks = { 1 }, rlList = { "Rl-R" } } }, { roster = roster }), "settings")
  return s
end
local function rec(kind, id, a, d, ts, sq) return { k = kind, id = id, a = a, ts = ts, sq = sq or ts, d = d } end
local function ap(s, r) return M.apply(s, R.copy(r), { roster = roster }) end
local AT = R.civil(2026, 12, 9, 20, 0)
local function rdata(st, extra)
  local d = R.new({ raid = "custom", size = 10, name = "Raid A", at = AT })
  d.st = st; d.owner = "Rl-R"
  for k, v in pairs(extra or {}) do d[k] = v end
  return d
end
local RID = "Rl-R:" .. T0
local function closedRoster(s, closeTs)
  ok(ap(s, rec("roster", RID, "Rl-R", rdata("published", { main = { "P1-R", "P2-R", "P3-R" } }), T0 + 100)))
  ok(ap(s, rec("roster", RID, "Rl-R", rdata("closed", { main = { "P1-R", "P2-R", "P3-R" } }), closeTs or (T0 + 200))))
end

-- attendance and witnesses ------------------------------------------------------------------------------------
test("attendance: never empty, only once closed, 7 days, last signature wins", function()
  local s = fresh()
  ok(ap(s, rec("roster", RID, "Rl-R", rdata("published", { main = { "P1-R", "P2-R" } }), T0 + 100)))
  local okA, why = ap(s, rec("attendance", RID, "Rl-R", { rid = RID, names = { "P1-R" } }, T0 + 150))
  ok(not okA and why == "notClosed", "published: " .. tostring(why))
  ok(ap(s, rec("roster", RID, "Gm-R", rdata("closed", { main = { "P1-R", "P2-R" } }), T0 + 200)), "the GM closes")
  eq(R.attendanceState(s, RID), "pending", "closed by someone who did not see the raid -> pending")
  okA, why = ap(s, rec("attendance", RID, "Gm-R", { rid = RID, names = {} }, T0 + 201)); ok(not okA and why == "empty", tostring(why))
  okA, why = ap(s, rec("attendance", RID, "Gm-R", { rid = RID, names = { "Stranger-X" } }, T0 + 202)); ok(not okA and why == "empty", "non-guild names only")
  eq(R.attendanceStats(s, "P1-R"), nil, "pending attendance does not count as absent")
  ok(ap(s, rec("attendance", RID, "Rl-R", { rid = RID, names = { "P1-R" } }, T0 + 300)), "RL signs when back")
  eq(R.attendanceState(s, RID), "signed")
  ok(ap(s, rec("attendance", RID, "Gm-R", { rid = RID, names = { "P1-R", "P2-R" } }, T0 + 400)), "GM corrects")
  ok(deq(R.attendanceList(s, RID), { "P1-R", "P2-R" }), "last signature wins")
  okA, why = ap(s, rec("attendance", RID, "Rl-R", { rid = RID, names = { "P1-R" } }, T0 + 200 + R.FIX_DAYS + 1))
  ok(not okA and why == "late", "after 7 days: " .. tostring(why))
  ok(R.canFixAttendance(s, RID, T0 + 200 + R.FIX_DAYS) and not R.canFixAttendance(s, RID, T0 + 200 + R.FIX_DAYS + 1))
  okA, why = ap(s, rec("attendance", RID, "Mem-R", { rid = RID, names = { "P1-R" } }, T0 + 500)); ok(not okA and why == "denied")
end)

test("witnesses: own record, author among the names, a name counts from 2 witnesses", function()
  local s = fresh()
  closedRoster(s)
  local okW, why = ap(s, rec("witness", R.witnessId(RID, "P1-R"), "P1-R", { rid = RID, names = { "P2-R" } }, T0 + 300))
  ok(not okW and why == "notThere", "a witness must be in the raid: " .. tostring(why))
  okW, why = ap(s, rec("witness", R.witnessId(RID, "P2-R"), "P1-R", { rid = RID, names = { "P1-R" } }, T0 + 300))
  ok(not okW and why == "shape", "only for yourself")
  ok(ap(s, rec("witness", R.witnessId(RID, "P1-R"), "P1-R", { rid = RID, names = { "P1-R", "P2-R", "P9-R" } }, T0 + 300)))
  eq(R.attendanceState(s, RID), "pending", "one witness is not enough")
  ok(ap(s, rec("witness", R.witnessId(RID, "P2-R"), "P2-R", { rid = RID, names = { "P1-R", "P2-R" } }, T0 + 310)))
  eq(R.attendanceState(s, RID), "witness")
  ok(deq(R.attendanceList(s, RID), { "P1-R", "P2-R" }), "P9 seen by one witness only: " .. table.concat(R.attendanceList(s, RID), ","))
  -- the RL record plus the witnesses
  ok(ap(s, rec("attendance", RID, "Rl-R", { rid = RID, names = { "P3-R" } }, T0 + 320)))
  ok(deq(R.attendanceList(s, RID), { "P1-R", "P2-R", "P3-R" }), "union")
  local pct = R.attendanceStats(s, "P2-R"); eq(pct, 100)
end)

-- convergence -------------------------------------------------------------------------------------------------
test("permutations: create, GM edit, close, early and late RSVP, attendance converge in every order", function()
  local recs = {
    rec("roster", RID, "Rl-R", rdata("published", { main = { "P1-R" } }), T0 + 100),
    rec("roster", RID, "Gm-R", rdata("published", { main = { "P1-R", "P2-R" } }), T0 + 201),
    rec("roster", RID, "Rl-R", rdata("closed", { main = { "P1-R" } }), T0 + 200),
    rec("rsvp", R.rsvpId(RID, "P1-R"), "P1-R", { rid = RID, name = "P1-R", v = "yes", c = "" }, T0 + 150),
    rec("rsvp", R.rsvpId(RID, "P2-R"), "P2-R", { rid = RID, name = "P2-R", v = "no", c = "" }, T0 + 250),
    rec("attendance", RID, "Rl-R", { rid = RID, names = { "P1-R" } }, T0 + 260),
  }
  -- every permutation of the 6 records; a record refused because it came too early is retried in a second pass
  -- (what the bucket resync does), and then the state must be identical
  local ref
  local n = 0
  local function sig(s)
    local parts = {}
    for _, k in ipairs({ "roster", "rsvp", "attendance" }) do parts[#parts + 1] = table.concat(M.bucketHashes(s, k), ",") end
    local ro = s.rosters[RID]
    return (ro and ro.d.st or "-") .. "|" .. table.concat(parts, "/") .. "|" .. tostring(R.rsvpOf(s, RID, "P2-R"))
  end
  local function permute(a, k)
    if k > #a then
      local s = fresh()
      for _ = 1, 2 do for _, i in ipairs(a) do ap(s, recs[i]) end end
      local x = sig(s)
      n = n + 1
      if not ref then ref = x else eq(x, ref, "order " .. table.concat(a, "")) end
      return
    end
    for i = k, #a do a[k], a[i] = a[i], a[k]; permute(a, k + 1); a[k], a[i] = a[i], a[k] end
  end
  permute({ 1, 2, 3, 4, 5, 6 }, 1)
  eq(n, 720)
  ok(ref:find("^closed|"), "the close wins over the later edit: " .. ref)
  ok(ref:find("|nil$"), "the late answer changes nothing")
end)

test("a converged record is not resent: no bucket differs after convergence", function()
  local a, b = fresh(), fresh()
  local create = rec("roster", RID, "Rl-R", rdata("published"), T0 + 100)
  local close = rec("roster", RID, "Rl-R", rdata("closed"), T0 + 200)
  local edit = rec("roster", RID, "Gm-R", rdata("published", { name = "Other" }), T0 + 201)
  ap(a, create); ap(a, close); ap(a, edit)
  ap(b, create); ap(b, edit); ap(b, close)
  eq(#M.diffRecords(a, "roster", M.bucketHashes(b, "roster")), 0, "nothing to resend")
end)

-- RSVP and prune ----------------------------------------------------------------------------------------------
test("RSVP: roster must exist and be published, list-only rosters, 1 per character", function()
  local s = fresh()
  ok(ap(s, rec("roster", RID, "Rl-R", rdata("draft"), T0 + 100)))
  local okR, why = ap(s, rec("rsvp", R.rsvpId(RID, "Mem-R"), "Mem-R", { rid = RID, name = "Mem-R", v = "yes" }, T0 + 110))
  ok(not okR and why == "draft", tostring(why))
  ok(ap(s, rec("roster", RID, "Rl-R", rdata("published", { open = false, main = { "P1-R" } }), T0 + 120)))
  okR, why = ap(s, rec("rsvp", R.rsvpId(RID, "Mem-R"), "Mem-R", { rid = RID, name = "Mem-R", v = "yes" }, T0 + 130))
  ok(not okR and why == "notListed", tostring(why))
  ok(ap(s, rec("rsvp", R.rsvpId(RID, "P1-R"), "P1-R", { rid = RID, name = "P1-R", v = "yes" }, T0 + 140)))
  ok(ap(s, rec("rsvp", R.rsvpId(RID, "P1-R"), "P1-R", { rid = RID, name = "P1-R", v = "no" }, T0 + 150)))
  local n = 0
  for _ in pairs(s.rsvps) do n = n + 1 end
  eq(n, 1, "one answer per character"); eq(R.rsvpOf(s, RID, "P1-R").v, "no")
  -- open roster (default, as every legacy roster): anyone in the guild answers
  local s2 = fresh()
  ok(ap(s2, rec("roster", RID, "Rl-R", rdata("published"), T0 + 100)))
  ok(ap(s2, rec("rsvp", R.rsvpId(RID, "Mem-R"), "Mem-R", { rid = RID, name = "Mem-R", v = "maybe" }, T0 + 110)))
end)

test("prune: closed rosters older than 8 weeks keep record and attendance, lose RSVPs", function()
  local s = fresh()
  ok(ap(s, rec("roster", RID, "Rl-R", rdata("published", { main = { "P1-R" } }), T0 + 100)))
  ok(ap(s, rec("rsvp", R.rsvpId(RID, "P1-R"), "P1-R", { rid = RID, name = "P1-R", v = "yes" }, T0 + 110)))
  local open = "Rl-R:" .. (T0 + 1)
  local dOpen = rdata("published"); dOpen.at = AT + 20 * R.WEEK
  ok(ap(s, rec("roster", open, "Rl-R", dOpen, T0 + 120)))
  ok(ap(s, rec("rsvp", R.rsvpId(open, "P1-R"), "P1-R", { rid = open, name = "P1-R", v = "yes" }, T0 + 130)))
  ok(ap(s, rec("roster", RID, "Rl-R", rdata("closed", { main = { "P1-R" } }), T0 + 200)))
  ok(ap(s, rec("attendance", RID, "Rl-R", { rid = RID, names = { "P1-R" } }, T0 + 210)))
  eq(R.prune(s, AT + 7 * R.WEEK), 0, "7 weeks: nothing pruned")
  eq(R.prune(s, AT + R.CLOSE_AFTER + R.PRUNE_AFTER + 60), 1, "8 weeks: its RSVP goes")
  ok(s.rosters[RID] and s.attendance[RID], "record and attendance (the summary) stay")
  ok(s.rsvps[R.rsvpId(open, "P1-R")], "RSVPs of live rosters stay")
  local okR, why = ap(s, rec("rsvp", R.rsvpId(RID, "P1-R"), "P1-R", { rid = RID, name = "P1-R", v = "yes" }, T0 + 110))
  ok(not okR and why == "pruned", "a peer resending it is refused: " .. tostring(why))
  eq(R.attendanceStats(s, "P1-R"), 100, "the % still counts it")
end)

-- weekly copies and the active roster -------------------------------------------------------------------------
test("weekly copy lands on the first future week; a never-published draft is not copied", function()
  local d = rdata("published", { wk = true })
  local now = AT + 10 * R.WEEK + 3600
  local c = R.duplicate(d, RID, now)
  ok(c.at > now and c.at <= now + R.WEEK, "next future week: " .. R.fmtWall(c.at))
  eq((c.at - AT) % R.WEEK, 0, "same weekday and hour")
  eq(R.duplicate(d, RID, AT - 60).at, AT + R.WEEK, "on time: just +7 days")
  local s = fresh()
  ok(ap(s, rec("roster", RID, "Rl-R", rdata("draft", { wk = true }), T0 + 1)))
  eq(#R.dueRepeats(s, "Rl-R", now), 0, "draft never published")
end)

test("one active roster, shrink loss list, leader check", function()
  local s = fresh()
  local a = rdata("published", { main = { "P1-R", "P2-R", "P3-R" } })
  local b = rdata("published", { main = { "P4-R", "P5-R" }, at = AT + 5400 })
  ok(ap(s, rec("roster", "Rl-R:1", "Rl-R", a, T0 + 1))); ok(ap(s, rec("roster", "Rl-R:2", "Rl-R", b, T0 + 2)))
  local act = R.activeRoster(s, { "Rl-R", "P1-R", "P2-R", "P3-R" }, AT + 5000, "Rl-R")
  eq(act and act.id, "Rl-R:1", "the roster whose players are in the group, not every overlapping one")
  eq(R.activeRoster(s, { "Mem-R" }, AT + 5000, "Mem-R"), nil, "not listed: nothing")
  local big = R.new({ size = 40, name = "Ony", at = AT })
  for i = 1, 30 do R.addPlayer(big, "P" .. i .. "-R") end
  local lost = R.shrinkLoss(big, 10)
  eq(#lost, 10, "30 players -> 10 kept, 10 to the bench, 10 lost")
  eq(#R.shrinkLoss(big, 40), 0)
  R.pendingInvites = {}
  local res = R.invite({ inCombat = function() return false end, invite = function() error("must not invite") end,
                         canInvite = function() return false end }, {}, { "P1-R" }, "Rl-R")
  eq(res.reason, "notLeader")
end)

-- wipe summary ------------------------------------------------------------------------------------
test("wipe summary: two different local snapshots, same records -> identical summary", function()
  local w = "W" .. Pr.weekOf(T0)
  local base = Pr.wipeStartTs(w) + 3600
  local events = {
    { t = "boss", who = "Ali-R", ts = base, sid = "S1", inst = "Molten Core", iid = 409, it = "raid", enc = 663, boss = "Lucifron", pres = { "Ali-R", "Bob-R", "Zed-R" } },
    { t = "boss", who = "Bob-R", ts = base + 5, sid = "S1", inst = "Molten Core", iid = 409, it = "raid", enc = 663, boss = "Lucifron", pres = { "Ali-R", "Bob-R", "Zed-R" } },
    { t = "level", who = "Cid-R", ts = base + 60, sid = "S2", lv = 30 },
    { t = "bg", who = "Ali-R", ts = base + 600, sid = "S1", inst = "WSG", win = 1, pres = { "Ali-R", "Bob-R" } },
    { t = "bg", who = "Bob-R", ts = base + 607, sid = "S1", inst = "WSG", win = 1, pres = { "Ali-R", "Bob-R" } },
  }
  local profiles = { ["Zed-R"] = { ts = base - 86400, d = { squad = "S1" } }, ["Cid-R"] = { ts = base, d = { squad = "S2" } } }
  local snapA = function() return true end                                      -- everyone is a member
  local snapB = function(sid, name) return name == "Ali-R" end                  -- a stale snapshot
  local sa = Pr.wipeSummary(events, w, { isMember = snapA, profiles = profiles })
  local sb = Pr.wipeSummary(events, w, { isMember = snapB, profiles = profiles })
  eq(Pr.summaryHash(sb), Pr.summaryHash(sa), "same records -> same summary")
  ok(sa.S1 and sa.S2, "both squads summarised")
  -- the records really decide: without Zed's profile he is not counted present
  local sc = Pr.wipeSummary(events, w, { isMember = snapA, profiles = { ["Cid-R"] = profiles["Cid-R"] } })
  ok(Pr.summaryHash(sc) ~= Pr.summaryHash(sa), "membership comes from the profile records")
end)

-- confirmations -----------------------------------------------------------------------------------------------
test("Confirm: only GM or officers sign it; it clears the unverified mark", function()
  local s = fresh()
  local store = Ra.newStore()
  local ev = { t = "kill", who = "Ali-R", by = "Ali-R", ts = T0 - 30 * 86400, inst = "Ragefire Chasm", it = "party", enc = 1, boss = "Taragaman", pres = { "Ali-R" } }
  local okA, id = Ra.add(store, ev, T0)
  ok(okA, "stored: " .. tostring(id))
  eq(store.obs[id].uv, 1, "backdated -> unverified")
  eq(#Ra.unverifiedList(store), 1)
  local okC, why = ap(s, rec("vconfirm", id, "Mem-R", { oid = id }, T0 + 1)); ok(not okC and why == "denied", "a member: " .. tostring(why))
  okC, why = ap(s, rec("vconfirm", id, "Rl-R", { oid = id }, T0 + 2)); ok(not okC and why == "denied", "a raid leader: " .. tostring(why))
  okC, why = ap(s, rec("vconfirm", "other", "Off-R", { oid = id }, T0 + 3)); ok(not okC and why == "shape", "id = observation id")
  ok(ap(s, rec("vconfirm", id, "Off-R", { oid = id }, T0 + 4)), "an officer confirms")
  ok(ap(fresh(), rec("vconfirm", id, "Gm-R", { oid = id }, T0 + 5)), "the GM too")
  eq(Ra.applyConfirms(store, s.vconfirm), 1)
  eq(store.obs[id].uv, nil, "verified"); eq(#Ra.unverifiedList(store), 0)
  local all = M.allRecords(s)
  local k = {}
  for _, r in ipairs(all) do k[r.k] = true end
  ok(k.vconfirm, "replicated like any record")
end)

-- migration: legacy SavedVariables (records saved in M.allRecords order) load
test("migration: legacy rosters, RSVPs and signed attendance load; an empty attendance becomes pending", function()
  local RID2 = "Rl-R:" .. (T0 + 5)
  local saved = {
    rec("roster", RID, "Rl-R", rdata("closed", { main = { "P1-R", "P2-R" } }), T0 + 200),          -- no `open` field
    rec("roster", RID2, "Rl-R", rdata("closed", { main = { "P1-R" } }), T0 + 300),
    rec("roster", "Rl-R:" .. (T0 + 6), "Rl-R", rdata("published", { wk = true }), T0 + 310),
    rec("rsvp", R.rsvpId(RID, "P1-R"), "P1-R", { rid = RID, name = "P1-R", v = "yes", c = "" }, T0 + 150),
    rec("rsvp", R.rsvpId(RID, "Mem-R"), "Mem-R", { rid = RID, name = "Mem-R", v = "maybe", c = "" }, T0 + 160),
    rec("attendance", RID, "Rl-R", { rid = RID, names = { "P1-R" }, at = AT }, T0 + 201),
    rec("attendance", RID2, "Gm-R", { rid = RID2, names = {}, at = AT }, T0 + 301),               -- the A1 bug output
  }
  local s = fresh()
  local n = 0
  for _, r in ipairs(saved) do if ap(s, r) then n = n + 1 end end
  eq(n, 6, "everything but the empty attendance")
  eq(R.rsvpOf(s, RID, "P1-R").v, "yes"); eq(R.rsvpOf(s, RID, "Mem-R").v, "maybe", "legacy rosters are open to the guild")
  eq(R.attendanceState(s, RID), "signed"); eq(R.attendanceState(s, RID2), "pending")
  eq(R.attendanceStats(s, "P1-R"), 100, "the empty record no longer counts P1 as absent")
end)

-- glue (runs inside tests/zload_spec.lua with the fake client; Ann-Realm is the GM)
SMOKE_CHECKS = SMOKE_CHECKS or {}
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "glue: auto-close without seeing the raid leaves attendance pending; the RL/GM signs it; Confirm", function(c)
  local ns, click = c.ns, c.click
  local UI, G, Rr = ns.UI, ns.RaidGlue, ns.Roster
  local origTime = GetServerTime
  local fakeNow = 1795000000
  GetServerTime = function() return fakeNow end
  local wall = G.WallNow()
  local rid = G.Create({ raid = "custom", size = 10, name = "Raid pendiente", at = wall - Rr.CLOSE_AFTER - 600 })
  ok(rid, "roster created")
  local d = Rr.copy(G.Get(rid).d); Rr.addPlayer(d, "Bob-Realm"); d.st = "published"
  ok(G.Save(rid, d), "published")
  G.Tick()
  eq(G.Get(rid).d.st, "closed", "auto-closed by the tick")
  eq(ns.state.attendance and ns.state.attendance[rid], nil, "nothing seen -> no attendance signed (no empty record)")
  eq(Rr.attendanceState(ns.state, rid), "pending")
  -- the detail shows the pending state and the red button signs the corrected attendance
  UI.OpenRoster(rid)
  local rb = UI.RaidsState()
  UI.Select("raids")
  ok(rb.attMode, "correction mode for the GM within 7 days")
  ok(tostring(rawget(rb.state, "_text")):find(ns.L.RB_ST_closed_pending, 1, true), "label: " .. tostring(rawget(rb.state, "_text")))
  eq(rawget(rb.primary, "_text"), ns.L.RB_SIGN_ATT)
  local slot
  for _, box in ipairs(rb.groups) do for _, s in ipairs(box.slots) do if s.name == "Bob-Realm" then slot = s end end end
  ok(slot, "Bob's slot"); click(slot)
  ok(rb.att["Bob-Realm"], "marked present")
  click(rb.primary)
  local att = ns.state.attendance[rid]
  ok(att and att.d.names[1] == "Bob-Realm", "attendance signed with the correction")
  eq(Rr.attendanceState(ns.state, rid), "signed")
  click(rb.back)
  GetServerTime = origTime
  -- the Salón lists unverified observations with "?" and the GM confirms one
  local Hg, Ra = ns.HallGlue, ns.Races
  if Hg and Hg.Store and Hg.Confirm then
    local store = Hg.Store()
    local okA, oid = Ra.add(store, { t = "kill", who = "Bob-Realm", by = "Bob-Realm", ts = GetServerTime() - 30 * 86400,
                                     inst = "Ragefire Chasm", it = "party", enc = 1, boss = "Taragaman", pres = { "Bob-Realm" } }, GetServerTime())
    ok(okA and store.obs[oid].uv == 1, "unverified observation held")
    ok(#Hg.Unverified() >= 1)
    ok(Hg.Confirm(oid), "the GM confirms")
    ok(ns.state.vconfirm and ns.state.vconfirm[oid], "signed vconfirm record")
    Hg.MarkDirty(); Hg.Races()
    eq(store.obs[oid].uv, nil, "verified after the confirmation")
  end
end }
