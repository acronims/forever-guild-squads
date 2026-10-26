local S, C, Q, M, P, X = NS.Serialize, NS.Chunk, NS.Queue, NS.Model, NS.Permissions, NS.Match

-- Serializer ---------------------------------------------------------------
test("serialize round-trip nested + separators", function()
  local v = { a = 1, b = -2.5, c = "x:y;z~|e\n\r\0t", d = { 1, 2, { deep = true, s = "" } }, e = false,
              [3] = "three", name = "Los Lobos" }
  local s = S.encode(v)
  local okd, back = S.decode(s)
  ok(okd, tostring(back)); ok(deq(v, back), "deep equal")
  local esc = S.escape(s)
  ok(not esc:find("[|\n\r%z]"), "escaped has no unsafe bytes")
  local ok2, back2 = S.decode(S.unescape(esc))
  ok(ok2 and deq(v, back2), "escape round-trip")
end)
test("serialize deterministic + rejects garbage", function()
  eq(S.encode({ b = 1, a = 2 }), S.encode({ a = 2, b = 1 }))
  ok(not S.decode("t s3:abc"), "garbage rejected")
  ok(not S.decode("s10:abc"), "short string rejected")
  ok(not (S.decode("n1;x")), "trailing rejected")
end)

-- Chunking -----------------------------------------------------------------
test("chunk + reassemble 1000-byte payload", function()
  local t = {}
  for i = 1, 1000 do t[i] = string.char(33 + (i * 7) % 90) end
  local payload = table.concat(t)
  local parts = C.split(payload, "a7")
  ok(#parts >= 4, "several parts")
  for _, p in ipairs(parts) do ok(#p <= 255, "part <= 255 bytes: " .. #p) end
  local asm = C.newAssembler()
  local got
  for i = #parts, 1, -1 do got = C.feed(asm, "Bob", parts[i], 1) or got end -- out of order
  eq(got, payload, "reassembled")
  -- interleaved senders do not mix
  local asm2 = C.newAssembler()
  local p2 = C.split(payload:reverse(), "a7")
  local r1, r2
  for i = 1, #parts do
    r1 = C.feed(asm2, "Bob", parts[i], 1) or r1
    r2 = C.feed(asm2, "Ann", p2[i], 1) or r2
  end
  eq(r1, payload); eq(r2, payload:reverse())
end)

-- Queue / lockdown ---------------------------------------------------
test("queue holds messages while blocked and throttles", function()
  local sent = {}
  local q = Q.new({ rate = 1, burst = 2, now = 0, send = function(m) sent[#sent + 1] = m; return true end })
  q:setBlocked("encounter", true)
  for i = 1, 5 do q:push("m" .. i) end
  eq(q:pump(10), 0, "nothing sent during encounter"); eq(#sent, 0)
  q:setBlocked("encounter", false)
  eq(q:pump(10), 2, "burst of 2")
  eq(q:pump(10.5), 0, "no token yet")
  eq(q:pump(11), 1, "one per second")
  eq(q:pump(20), 2, "rest"); eq(#sent, 5); eq(sent[5], "m5")
end)
test("queue honours external chat lockdown predicate", function()
  local locked = true
  local n = 0
  local q = Q.new({ now = 0, send = function() n = n + 1 end, isLocked = function() return locked end })
  q:push("x"); q:pump(5); eq(n, 0)
  locked = false; q:pump(6); eq(n, 1)
end)

-- LWW ----------------------------------------------------------------------
local roster = makeRoster({ GM = 0, Off = 1, Ann = 4, Bob = 4, Cid = 4, Dan = 4, Eve = 4, Fay = 4, Low = 9 })
local ctx = { roster = roster }
local function prof(name, ts, sq, d) return { k = "profile", id = name, a = name, ts = ts, sq = sq or 1, d = d or { role = "TANK" } } end

test("LWW: newer wins, older rejected, tie-break by author", function()
  local st = M.newState()
  ok(M.apply(st, prof("Ann", 100, 1, { role = "TANK" }), ctx))
  ok(M.apply(st, prof("Ann", 200, 1, { role = "HEALER" }), ctx))
  local okk, why = M.apply(st, prof("Ann", 150, 9, { role = "DAMAGER" }), ctx)
  ok(not okk); eq(why, "stale"); eq(st.profiles.Ann.d.role, "HEALER")
  ok(M.apply(st, prof("Ann", 200, 2, { role = "DAMAGER" }), ctx), "same ts higher seq wins")
  ok(M.newer({ ts = 5, sq = 1, a = "Zed" }, { ts = 5, sq = 1, a = "Abe" }), "author tie-break")
  ok(not M.newer({ ts = 5, sq = 1, a = "Abe" }, { ts = 5, sq = 1, a = "Zed" }))
end)
test("profile can only be written by its owner; unknown author rejected", function()
  local st = M.newState()
  local r = prof("Ann", 1); r.a = "Bob"
  local okk, why = M.apply(st, r, ctx); ok(not okk); eq(why, "denied")
  okk, why = M.apply(st, prof("Stranger", 1), ctx); ok(not okk); eq(why, "notInGuild")
end)

-- Settings authority ------------------------------------------------------
local function settings(author, ts, d) return { k = "settings", id = "settings", a = author, ts = ts, sq = 1, d = d } end
test("only GM (rank 0) can change settings", function()
  local st = M.newState()
  local okk, why = M.apply(st, settings("Off", 10, { squadsEnabled = false }), ctx)
  ok(not okk); eq(why, "denied")
  okk = M.apply(st, settings("Ann", 11, { squadsEnabled = false }), ctx); ok(not okk)
  ok(M.apply(st, settings("GM", 12, { squadsEnabled = false, bench = 5 }), ctx))
  eq(M.settingsOf(st).squadsEnabled, false); eq(M.settingsOf(st).bench, 2, "bench clamped")
end)

-- Squads -------------------------------------------------------------------
local function squad(author, id, ts, d) return { k = "squad", id = id, a = author, ts = ts, sq = 1, d = d } end
local function base(name, captain, members) return { name = name, captain = captain, members = members or { captain }, open = true, icon = 1, color = 1, border = 1 } end

test("create squad, name rules and case-insensitive uniqueness", function()
  local st = M.newState()
  ok(M.apply(st, settings("GM", 1, { squadsEnabled = true, minCreateRank = 4, banned = { "noob" } }), ctx))
  ok(M.apply(st, squad("Ann", "Ann:1", 10, base("Los Lobos", "Ann")), ctx))
  local okk, why = M.apply(st, squad("Bob", "Bob:1", 11, base("los LOBOS", "Bob")), ctx)
  ok(not okk); eq(why, "nameTaken")
  okk, why = M.apply(st, squad("Bob", "Bob:1", 11, base("ab", "Bob")), ctx); eq(why, "nameLength")
  okk, why = M.apply(st, squad("Bob", "Bob:1", 11, base("NoobSquad", "Bob")), ctx); eq(why, "nameBanned")
  okk, why = M.apply(st, squad("Low", "Low:1", 11, base("Lowly", "Low")), ctx); eq(why, "rank")
  okk, why = M.apply(st, squad("Bob", "Bob:1", 11, base("Otros", "Ann")), ctx); eq(why, "denied", "author must be captain")
end)

test("one squad per character", function()
  local st = M.newState()
  ok(M.apply(st, squad("Ann", "Ann:1", 10, base("Alpha", "Ann")), ctx))
  local okk, why = M.apply(st, squad("Ann", "Ann:2", 11, base("Beta", "Ann")), ctx)
  ok(not okk); eq(why, "oneSquad")
  -- Bob joins Alpha (invite + consent), then cannot create another squad
  ok(M.apply(st, squad("Ann", "Ann:1", 12, base("Alpha", "Ann", { "Ann", "Bob" })), ctx))
  ok(M.apply(st, prof("Bob", 13, 1, { role = "HEALER", squad = "Ann:1" }), ctx))
  ok(M.isMember(st, "Ann:1", "Bob"))
  okk, why = M.apply(st, squad("Bob", "Bob:1", 14, base("Gamma", "Bob")), ctx)
  ok(not okk); eq(why, "oneSquad")
  -- a profile holds one squad id: pointing elsewhere drops the old membership
  ok(M.apply(st, prof("Bob", 15, 1, { role = "HEALER", squad = "Other" }), ctx))
  ok(not M.isMember(st, "Ann:1", "Bob"))
end)

test("only captain can kick / edit; officer only moderates; transfer", function()
  local st = M.newState()
  ok(M.apply(st, squad("Ann", "Ann:1", 10, base("Alpha", "Ann", { "Ann", "Bob", "Cid" })), ctx))
  ok(M.apply(st, prof("Bob", 11, 1, { squad = "Ann:1" }), ctx))
  ok(M.apply(st, prof("Cid", 11, 1, { squad = "Ann:1" }), ctx))
  local okk, why = M.apply(st, squad("Bob", "Ann:1", 20, base("Alpha", "Ann", { "Ann", "Bob" })), ctx)
  ok(not okk); eq(why, "denied", "non-captain cannot kick")
  okk = M.apply(st, squad("Off", "Ann:1", 20, base("Alpha", "Ann", { "Ann", "Bob" })), ctx)
  ok(not okk, "officer cannot kick")
  local mod = base("Alpha", "Ann", { "Ann", "Bob", "Cid" }); mod.approved = true
  ok(M.apply(st, squad("Off", "Ann:1", 21, mod), ctx), "officer can approve")
  local kick = base("Alpha", "Ann", { "Ann", "Bob" }); kick.approved = true
  ok(M.apply(st, squad("Ann", "Ann:1", 22, kick), ctx), "captain kicks")
  ok(not M.isMember(st, "Ann:1", "Cid"))
  local tr = base("Alpha", "Bob", { "Ann", "Bob" }); tr.approved = true; tr.xferFrom = "Ann"
  ok(M.apply(st, squad("Ann", "Ann:1", 23, tr), ctx), "transfer")
  okk = M.apply(st, squad("Ann", "Ann:1", 24, base("Alpha2", "Ann", { "Ann", "Bob" })), ctx)
  ok(not okk, "old captain lost rights")
  -- a late joiner that only sees the new captain's record accepts it via xferFrom
  local st2 = M.newState()
  ok(M.apply(st2, squad("Ann", "Ann:1", 10, base("Alpha", "Ann", { "Ann", "Bob" })), ctx))
  local late = base("Alpha", "Bob", { "Ann", "Bob" }); late.xferFrom = "Ann"; late.motto = "hola"
  -- without the old captain's signed hand-over the claim is refused...
  okk, why = M.apply(st2, squad("Bob", "Ann:1", 30, late), ctx)
  ok(not okk); eq(why, "xfer", "claim without hand-over")
  -- ...and accepted once Ann's own record names Bob (profile xferTo, earlier ts)
  ok(M.apply(st2, prof("Ann", 25, 1, { squad = "Ann:1", xferTo = "Ann:1>Bob" }), ctx))
  ok(M.apply(st2, squad("Bob", "Ann:1", 30, late), ctx), "late joiner accepts new captain")
end)

test("squad size cap and bench from settings", function()
  local st = M.newState()
  local six = base("Big", "Ann", { "Ann", "Bob", "Cid", "Dan", "Eve", "Fay" })
  local okk = M.apply(st, squad("Ann", "Ann:1", 10, six), ctx)
  ok(okk, "sanitizer truncates to 5"); eq(#st.squads["Ann:1"].d.members, 5)
  local b = base("Big", "Ann", { "Ann" }); b.bench = { "Fay" }
  local okb, why = M.apply(st, squad("Ann", "Ann:1", 11, b), ctx); ok(not okb); eq(why, "benchFull")
  ok(M.apply(st, settings("GM", 12, { bench = 1 }), ctx))
  ok(M.apply(st, squad("Ann", "Ann:1", 13, b), ctx))
end)

test("disabled squads reject creation; requests and invites", function()
  local st = M.newState()
  ok(M.apply(st, squad("Ann", "Ann:1", 10, base("Alpha", "Ann", { "Ann", "Dan" })), ctx))
  ok(M.apply(st, prof("Bob", 11, 1, { squad = "Ann:1" }), ctx))
  eq(M.requests(st, "Ann:1")[1], "Bob"); eq(M.invites(st, "Dan")[1], "Ann:1")
  ok(M.apply(st, settings("GM", 12, { squadsEnabled = false }), ctx))
  local okk, why = M.apply(st, squad("Cid", "Cid:1", 13, base("Gamma", "Cid")), ctx)
  ok(not okk); eq(why, "disabled")
end)

test("export / import round-trip", function()
  local st = M.newState()
  ok(M.apply(st, settings("GM", 1, { bench = 1 }), ctx))
  ok(M.apply(st, squad("Ann", "Ann:1", 10, base("Los Lobos", "Ann")), ctx))
  ok(M.apply(st, prof("Ann", 11, 1, { role = "TANK", squad = "Ann:1", note = "a|b\nc" }), ctx))
  local text = M.export(st)
  ok(not text:find("\n"), "single line")
  local st2 = M.newState()
  local applied, rejected = M.import(st2, "  " .. text .. "\n", ctx)
  eq(applied, 3); eq(rejected, 0)
  eq(st2.squads["Ann:1"].d.name, "Los Lobos"); eq(st2.profiles.Ann.d.note, "a|b\nc")
  eq(table.concat(M.bucketHashes(st, "squad")), table.concat(M.bucketHashes(st2, "squad")), "hashes match")
end)

test("bucket diff only returns differing records", function()
  local a, b = M.newState(), M.newState()
  for _, n in ipairs({ "Ann", "Bob", "Cid", "Dan", "Eve" }) do
    ok(M.apply(a, prof(n, 5), ctx)); ok(M.apply(b, prof(n, 5), ctx))
  end
  eq(#M.diffRecords(a, "profile", M.bucketHashes(b, "profile")), 0)
  ok(M.apply(a, prof("Eve", 9), ctx))
  local d = M.diffRecords(a, "profile", M.bucketHashes(b, "profile"))
  ok(#d >= 1 and #d < 5, "only the changed bucket"); local found = false
  for _, r in ipairs(d) do if r.id == "Eve" then found = true end end
  ok(found)
end)

-- Encaje -------------------------------------------------------------------
test("encaje score and reasons", function()
  local needs = X.roleNeeds({ { role = "TANK" }, { role = "DAMAGER" } })
  eq(needs.HEALER, 1); eq(needs.TANK, 0); eq(needs.DAMAGER, 2)
  local player = { role = "HEALER", avail = "00110000", level = 30, goals = { "dungeons", "raid" } }
  local target = { needs = needs, avail = "00100001", level = 32, goals = { "dungeons" } }
  local score, reasons = X.score(player, target)
  eq(score, 40 + 10 + 20 + 10)
  local L = { REASON_role = "fills %s", REASON_avail = "%s shared slots", REASON_level = "level diff %s",
              REASON_goal = "goal %s", ROLE_HEALER = "healer", GOAL_dungeons = "dungeons" }
  eq(X.reasonText(reasons, L), "fills healer, 1 shared slots, level diff 2, goal dungeons")
  local s2, r2 = X.score({ role = "TANK", role2 = "DAMAGER", level = 60 }, target)
  eq(s2, 20); eq(r2[1][1], "role2")
  local s3 = X.score({ role = "TANK", level = 10 }, { needs = { TANK = 0 }, level = 60 })
  eq(s3, 0)
end)
test("finder filters", function()
  local e = { role = "TANK", class = "WARRIOR", level = 25, avail = "10000000", goals = { "bg" }, online = true }
  ok(X.passes(e, { role = "TANK", class = "WARRIOR", minLevel = 20, maxLevel = 30, availWith = "11000000", goal = "bg", onlineOnly = true }))
  ok(not X.passes(e, { role = "HEALER" })); ok(not X.passes(e, { availWith = "01000000" }))
  ok(not X.passes(e, { maxLevel = 20 })); ok(not X.passes(e, { goal = "raid" }))
end)

test("finder filters accept sets (OR inside a group, AND between groups)", function()
  local e = { role = "TANK", role2 = "DAMAGER", class = "WARRIOR", level = 25, goals = { "bg", "raid" }, online = false }
  ok(X.passes(e, { role = { HEALER = true, DAMAGER = true } }), "role2 matches inside set")
  ok(not X.passes(e, { role = { HEALER = true } }))
  ok(X.passes(e, { class = { MAGE = true, WARRIOR = true } })); ok(not X.passes(e, { class = { MAGE = true } }))
  ok(X.passes(e, { goal = { dungeons = true, raid = true } })); ok(not X.passes(e, { goal = { farm = true } }))
  ok(X.passes(e, { role = {}, class = {}, goal = {} }), "empty sets = no filter")
  ok(not X.passes(e, { class = { WARRIOR = true }, goal = { farm = true } }), "AND between groups")
  ok(not X.passes(e, { role = { TANK = true }, onlineOnly = true }))
  -- squad entries match a role set through their needs
  ok(X.passes({ needs = { TANK = 0, HEALER = 1, DAMAGER = 0 } }, { role = { TANK = true, HEALER = true } }))
  ok(not X.passes({ needs = { TANK = 0, HEALER = 0, DAMAGER = 0 } }, { role = { TANK = true } }))
  -- squad fit uses its tags as goals
  local s = X.score({ goals = { "raid" } }, { goals = { "raid", "bg" } }); eq(s, 10)
end)
test("tags: canonical keys, max 3, legacy text kept apart", function()
  local t = M.cleanTags({ "raid", "raid", "Fun people", "bg", "farm", "dungeons" })
  ok(deq(t, { "raid", "bg", "farm" }), "dedup + only goal keys + max 3")
  eq(#M.cleanTags(nil), 0)
  local known, legacy = M.splitTags({ "dungeons", "chill", "dungeons", "Raid nights" })
  ok(deq(known, { "dungeons" })); ok(deq(legacy, { "chill", "Raid nights" }))
  ok(M.isGoal("worldpvp")); ok(not M.isGoal("WorldPvP"))
  -- a legacy squad with free-text tags still sanitizes and keeps the text (backward compat)
  local d = M.sanitize("squad", { name = "Old", captain = "A", tags = { "casual", "dungeons" } })
  ok(deq(d.tags, { "casual", "dungeons" }))
end)
test("call to squad: cooldown, anti-spam and payload", function()
  local C = NS.Call
  ok(C.canSend(nil, 100)); local okS, left = C.canSend(100, 160); ok(not okS); eq(left, 240)
  ok((C.canSend(100, 400))); eq(C.fmtLeft(192), "3:12"); eq(C.fmtLeft(-5), "0:00")
  local seen = {}
  ok(C.accept(seen, "Bob", 10)); ok(not C.accept(seen, "Bob", 200)); ok(C.accept(seen, "Eve", 200))
  ok(C.accept(seen, "Bob", 310)); ok(not C.accept(seen, nil, 1))
  local p = C.payload("Los Baldíos", "Cruce", 0.5214, 0.3041)
  eq(p.x, 52.1); eq(p.y, 30.4); eq(C.text(p), "Los Baldíos (Cruce) 52.1, 30.4")
  eq(C.text(C.payload("Orgrimmar", "Orgrimmar")), "Orgrimmar")
  eq(C.text(C.payload("A|cffff0000x", "")), "Acffff0000x"); eq(C.text("junk"), nil)
end)

-- Compliance (positive test) -----------------------------------------------------
test("schemas contain no money/gold/trade fields", function()
  local bad = { "gold", "money", "copper", "silver", "trade", "price", "bid", "pot", "cut", "gdkp", "auction", "cost", "pay" }
  local n = 0
  for kind, fields in pairs(M.SCHEMA) do
    for f in pairs(fields) do
      n = n + 1
      for _, w in ipairs(bad) do ok(not f:lower():find(w, 1, true), kind .. "." .. f .. " contains " .. w) end
    end
  end
  ok(n >= 20, "schema actually inspected (" .. n .. " fields)")
  -- and sanitize strips unknown economic fields injected by a peer
  local d = M.sanitize("profile", { role = "TANK", gold = 100, money = 5 })
  eq(d.gold, nil); eq(d.money, nil); eq(d.role, "TANK")
end)
