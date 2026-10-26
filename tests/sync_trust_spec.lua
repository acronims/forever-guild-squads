-- sync trust: channel filter, level window, announcer claims, closed imports, dynamic races, migration
local M, R, Cel, C, P = NS.Model, NS.Races, NS.Celebrate, NS.Content, NS.Permissions
local T0 = 1795000000
local roster = makeRoster({ ["Gm-R"] = 0, ["Off-R"] = 1, ["Ali-R"] = 5, ["Bob-R"] = 5, ["Eve-R"] = 7 })

-- channel filter ------------------------------------------------------------
test("channel filter: GUILD, or WHISPER from a roster member; nothing else reaches the handler", function()
  local frame = { scripts = {} }
  function frame:RegisterEvent() end
  function frame:SetScript(k, fn) self.scripts[k] = fn end
  local savedCF, savedGT, savedCI = CreateFrame, GetTime, C_ChatInfo
  local clock, wire, handled = 0, {}, {}
  CreateFrame = function() return frame end
  GetTime = function() return clock end
  C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end,
                 SendAddonMessage = function(_, msg) wire[#wire + 1] = msg; return 0 end }
  local ns = { Serialize = NS.Serialize, Chunk = NS.Chunk, Queue = NS.Queue,
               roster = function(n) return roster(n) end }
  loadmod("Comm.lua", ns)
  local Comm = ns.Comm
  Comm.Init(function(tag, _, sender, channel) handled[#handled + 1] = { tag, sender, channel } end)
  Comm.Send("D", { a = 1 })
  for _ = 1, 5 do clock = clock + 0.5; frame.scripts.OnUpdate(frame, 0.5) end
  ok(#wire >= 1, "a message on the wire")
  local function recv(channel, sender)
    local n = #handled
    for _, m in ipairs(wire) do frame.scripts.OnEvent(frame, "CHAT_MSG_ADDON", Comm.PREFIX, m, channel, sender) end
    return #handled > n
  end
  ok(recv("GUILD", "Ali-R"), "GUILD accepted")
  ok(recv("WHISPER", "Bob-R"), "WHISPER from a member accepted")
  ok(not recv("WHISPER", "Stranger-X"), "WHISPER from outside the guild ignored")
  ok(not recv("PARTY", "Ali-R"), "PARTY ignored"); ok(not recv("RAID", "Ali-R"), "RAID ignored")
  ok(not recv("CHANNEL", "Ali-R"), "custom channel ignored")
  ok((Comm.stats.badChannel or 0) >= 4, "counted for /gsq diag")
  ok(Comm.ChannelOk("GUILD", "x") and not Comm.ChannelOk(nil, "Ali-R"))
  CreateFrame, GetTime, C_ChatInfo = savedCF, savedGT, savedCI
end)

-- level window --------------------------------------------------------------
test("level window: live only inside [now-600, now+300], never before the last level seen", function()
  local now = T0 + 5000
  local lv = function(ts, l) return { t = "lv", who = "Ali-R", by = "Ali-R", ts = ts, src = "self", lv = l or 60 } end
  ok(R.liveLevelOk(lv(now), now), "now")
  -- the window is measured from the send (sentAt); without a stamp (older client)
  -- sentAt = now, and the event may have waited up to 3 h in the sender's queue
  ok(R.liveLevelOk(lv(now - 3 * 3600), now), "3 h in the queue is the edge")
  ok(not R.liveLevelOk(lv(now - 3 * 3600 - 1), now), "3 h + 1 s refused")
  ok(R.liveLevelOk(lv(now + 300), now) and not R.liveLevelOk(lv(now + 301), now), "future edge 300 s")
  ok(not R.liveLevelOk(lv(now - 30 * 86400), now), "30 days backdated refused")
  -- this client saw Ali at 59 at now-100: a 60 dated before that is refused
  ok(not R.liveLevelOk(lv(now - 200), now, { lv = 59, ts = now - 100 }), "before the last lower level seen")
  ok(R.liveLevelOk(lv(now - 50), now, { lv = 59, ts = now - 100 }), "after it: fine")
  ok(R.liveLevelOk(lv(now - 200), now, { lv = 60, ts = now - 100 }), "roster already at 60 (seen first): fine")
  -- exact mark only when the roster witness is within the window on BOTH sides
  local s = R.newStore()
  R.add(s, lv(T0)); R.add(s, { t = "lv", who = "Ali-R", by = "Bob-R", ts = T0 + 601, src = "roster", lv = 60 })
  local e = R.compute(s, { now = T0 + 9999 })["lvl.all.60"].entries[1]
  ok(not e or e.mark ~= "exact", "witness 601 s later does not make it exact")
end)

-- announcer + claim with 5 simulated clients ----------------------------
local function simulate(names, rnds, latency, preferredName)
  -- event bus: every client schedules its claim timer; CL messages arrive after `latency`
  local books, timeline, sent = {}, {}, {}
  -- every client registers the same ordered candidate list (preferred first)
  local order = {}
  if preferredName then order[1] = preferredName end
  for _, n in ipairs(names) do if n ~= preferredName then order[#order + 1] = n end end
  for _, n in ipairs(names) do books[n] = Cel.newClaims(); Cel.setCandidates(books[n], "ev", order) end
  local function at(t, fn) timeline[#timeline + 1] = { t = t, fn = fn, seq = #timeline } end
  for i, me in ipairs(names) do
    at(Cel.claimDelay(me == preferredName, rnds[i]), function(t)
      if Cel.claimed(books[me], "ev") then return end
      Cel.noteClaim(books[me], "ev", me, t)
      for _, o in ipairs(names) do if o ~= me then at(t + latency, function(t2) Cel.noteClaim(books[o], "ev", me, t2) end) end end
      at(t + Cel.CLAIM_HOLD, function() if Cel.claimWinner(books[me], "ev") == me then sent[#sent + 1] = me end end)
    end)
  end
  local t = 0
  while #timeline > 0 do
    table.sort(timeline, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.seq < b.seq end)
    local ev = table.remove(timeline, 1)
    t = ev.t; ev.fn(t)
  end
  return sent
end

test("claim: with 5 clients exactly one announces (fresh installs, empty hello maps)", function()
  local names = { "Ali-R", "Bob-R", "Cid-R", "Dan-R", "Eve-R" }
  -- nobody preferred (protagonist without the addon): all backups; two timers 0.1 s apart (inside the latency)
  local s1 = simulate(names, { 0.50, 0.52, 0.9, 0.1, 0.7 }, 0.3, nil)
  eq(#s1, 1, "one sender: " .. table.concat(s1, ","))
  -- identical timers: the lowest name wins everywhere
  local s2 = simulate(names, { 0.3, 0.3, 0.3, 0.3, 0.3 }, 0.5, nil)
  eq(#s2, 1); eq(s2[1], "Ali-R")
  -- the preferred announcer (protagonist online) claims first even with the slowest random draw
  local s3 = simulate(names, { 0, 0, 0, 1, 0 }, 0.3, "Dan-R")
  eq(#s3, 1); eq(s3[1], "Dan-R", "preferred announcer wins")
  -- many draws: never 0 and never 2 senders while latency < CLAIM_HOLD
  math.randomseed(61)
  for _ = 1, 200 do
    local r = {}
    for i = 1, 5 do r[i] = math.random() end
    eq(#simulate(names, r, 0.4, nil), 1)
  end
  -- late claims (after the hold window) are ignored, claims expire
  local book = Cel.newClaims()
  Cel.setCandidates(book, "k", { "Ali-R", "Bob-R" })
  ok(Cel.noteClaim(book, "k", "Bob-R", 0)); ok(not Cel.noteClaim(book, "k", "Ali-R", Cel.CLAIM_HOLD + 0.1))
  eq(Cel.claimWinner(book, "k"), "Bob-R")
  Cel.noteClaim(book, "other", "Zed-R", Cel.CLAIM_TTL + 1); ok(not Cel.claimed(book, "k"), "expired")
end)

-- medium / low ----------------------------------------------------------------
test("closed import: complete and non-decreasing dates only", function()
  local rows = {}
  for i = 1, 10 do rows[i] = { key = "P" .. i, ts = T0 + i, chars = { "P" .. i }, squads = {}, sup = {} } end
  local good = R.packClosed({ rows = rows })
  ok(R.importClosed(R.newStore(), "pvp.hk.100", good, T0), "10/10 rows accepted")
  rows[3].ts = T0 + 99
  ok(not R.importClosed(R.newStore(), "pvp.hk.100", R.packClosed({ rows = rows }), T0), "dates out of order refused")
end)

test("no freeze while syncing or within 10 min of the last observation received", function()
  local s = R.newStore()
  for i = 1, 10 do
    -- the first reading of a counter is the unscored baseline
    R.add(s, { t = "cnt", who = "P" .. i, by = "P" .. i, ts = T0 + i - 3600, k = "hk", n = 0 }, T0 + 100)
    R.add(s, { t = "cnt", who = "P" .. i, by = "P" .. i, ts = T0 + i, k = "hk", n = 100 }, T0 + 100)
  end
  R.compute(s, { now = T0 + 200 })
  ok(not s.closed["pvp.hk.100"], "received 100 s ago: not frozen")
  R.compute(s, { now = T0 + 9999, syncing = true })
  ok(not s.closed["pvp.hk.100"], "initial sync: not frozen")
  local r = R.compute(s, { now = T0 + 9999 })["pvp.hk.100"]
  eq(r.state, "closed"); ok(s.closed["pvp.hk.100"], "quiet: frozen")
end)

test("dynamic races: whitelist or >= 2 reporters, cap, per-author store cap", function()
  local s = R.newStore()
  -- a baseline reading first (the first reading never scores)
  R.add(s, { t = "cnt", who = "Ali-R", by = "Ali-R", ts = T0 - 600, k = "prof", key = "Alchemy", n = 140 })
  R.add(s, { t = "cnt", who = "Ali-R", by = "Ali-R", ts = T0, k = "prof", key = "Alchemy", n = 150 })
  for _, b in ipairs({ { "Ali-R", "Unknown Faction" }, { "Bob-R", "Other Faction" }, { "Eve-R", "Other Faction" } }) do
    R.add(s, { t = "cnt", who = b[1], by = b[1], ts = T0 - 600, k = "rep", key = b[2], n = 7 })
  end
  R.add(s, { t = "cnt", who = "Ali-R", by = "Ali-R", ts = T0, k = "rep", key = "Unknown Faction", n = 8 })
  R.add(s, { t = "cnt", who = "Bob-R", by = "Bob-R", ts = T0, k = "rep", key = "Other Faction", n = 8 })
  R.add(s, { t = "cnt", who = "Eve-R", by = "Eve-R", ts = T0, k = "rep", key = "Other Faction", n = 8 })
  local races = R.compute(s, { now = T0 + 99 })
  ok(races["prof.alchemy.150"], "whitelisted profession")
  ok(not races["rep.unknown_faction.exalted"], "one reporter, unknown key: no race")
  ok(races["rep.other_faction.exalted"], "two reporters: race")
  -- level class / race whitelists
  local s2 = R.newStore()
  R.add(s2, { t = "lv", who = "Eve-R", by = "Eve-R", ts = T0, src = "self", lv = 10, cls = "JUNK", race = "JUNKRACE" })
  R.add(s2, { t = "lv", who = "Eve-R", by = "Bob-R", ts = T0 + 5, src = "roster", lv = 10 })
  local r2 = R.compute(s2, { now = T0 + 99 })
  ok(not r2["lvl.class.JUNK.10"] and not r2["lvl.race.JUNKRACE.10"], "unknown class/race keys make no race")
  ok(r2["lvl.all.10"].entries[1], "the level itself still counts")
  -- per-author cap
  local s3 = R.newStore()
  local saved = R.MAX_OBS_PER_AUTHOR; R.MAX_OBS_PER_AUTHOR = 5
  local n = 0
  for i = 1, 9 do if R.add(s3, { t = "cnt", who = "Eve-R", by = "Eve-R", ts = T0 + i, k = "hk", n = i }) then n = n + 1 end end
  R.MAX_OBS_PER_AUTHOR = saved
  eq(n, 5, "per-author cap")
end)

test("final boss: the GM's last decision wins regardless of insertion order (Content replay)", function()
  local saved = C.bosses
  local function run(order)
    C.bosses = {}
    local recs = { { id = "barrow.1", ts = T0 + 10 }, { id = "barrow.2", ts = T0 + 20 } }
    local list = {}
    for _, i in ipairs(order) do list[#list + 1] = recs[i] end
    table.sort(list, function(a, b) if a.ts ~= b.ts then return a.ts < b.ts end return a.id < b.id end)
    for _, r in ipairs(list) do
      local b = C.learnBoss("barrow", tonumber(r.id:match("%d+$")), nil, "raid", true)
      C.setFinal(b.id, true)
    end
    return C.isFinal("barrow", "1") and "1" or (C.isFinal("barrow", "2") and "2" or "-")
  end
  eq(run({ 1, 2 }), "2"); eq(run({ 2, 1 }), "2", "same final whatever the order")
  C.bosses = saved
end)

test("catalog: pending bosses are not required, a witnessed kill or an officer record confirms", function()
  local saved = C.bosses; C.bosses = {}
  C.learnBoss("barrow", nil, "Fake", "raid")
  eq(#C.bossesOf("barrow"), 0, "single report: pending")
  local b = C.learnBoss("barrow", 7001, "Real", "raid", true)
  eq(table.concat(C.bossesOf("barrow"), ","), "7001", "officer record: confirmed")
  ok(b and not b.pending)
  C.bosses = saved
end)

test("migration: the guild must contain the GM of the settings record; no records -> event authors", function()
  local function legacy()
    return { records = { { k = "settings", id = "settings", a = "Gm-R", ts = T0, sq = 1, d = {} },
                         { k = "profile", id = "Ali-R", a = "Ali-R", ts = T0, sq = 1, d = {} },
                         { k = "profile", id = "Bob-R", a = "Bob-R", ts = T0, sq = 1, d = {} } },
             progress = { events = {} } }
  end
  local noGm = function(n) return n == "Ali-R" or n == "Bob-R" end
  local _, m1 = M.guildDB(legacy(), "Alt-R", noGm)
  ok(not m1, "majority of authors but not the GM: not adopted")
  local _, m2 = M.guildDB(legacy(), "Main-R", function(n) return roster(n) ~= nil end)
  ok(m2, "the GM's guild adopts")
  local evOnly = { progress = { events = { a = { t = "level", who = "Ali-R", ts = T0 } } } }
  local _, m3 = M.guildDB(evOnly, "Other-R", function() return false end)
  ok(not m3, "no records: an alt of another guild does not take the legacy progress")
  local _, m4 = M.guildDB(evOnly, "Main-R", function(n) return roster(n) ~= nil end)
  ok(m4, "no records: the authors' guild adopts")
end)

test("queued celebrations expire", function()
  local q = Cel.newQueue()
  Cel.enqueue(q, { key = "a", text = "a", at = 0 }); Cel.enqueue(q, { key = "b", text = "b", at = 500 })
  local ev = Cel.pump(q, Cel.TTL + 10, false)
  eq(ev and ev.key, "b", "the stale one is dropped, the fresh one leaves")
end)

test("provenance: only the author or an officer; no economy fields added", function()
  local rec = { k = "profile", id = "Ali-R", a = "Ali-R", ts = T0, sq = 1, d = {} }
  ok(not M.apply(M.newState(), rec, { roster = roster, sender = "Eve-R", announced = function() return true end }))
  ok(M.apply(M.newState(), rec, { roster = roster, sender = "Off-R" }))
  ok(P.isOfficer(roster, "Off-R", M.settingsOf(M.newState())))
end)
