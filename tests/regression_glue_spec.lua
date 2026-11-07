-- Regression tests: glue. Each check asserts the CORRECT behaviour.
-- They run inside the fake client of tests/zload_spec.lua (registered in SMOKE_CHECKS; see run.js).
-- The pagination check counts only the 100 witness records it adds (the witness check before it leaves a 101st);
-- the guild-change check switches back to the original guild at the end, because other checks run after it.
SMOKE_CHECKS = SMOKE_CHECKS or {}

-- run every OnUpdate script once with the clock moved `dt` seconds ahead (fires ns.After timers: no C_Timer here)
local function runTimers(c, dt)
  local origT = GetTime
  local base = GetTime()
  GetTime = function() return base + dt end
  for _, o in ipairs(c.allObjs) do
    local fn = rawget(o, "_OnUpdate")
    if fn then pcall(fn, o, dt) end
  end
  GetTime = origT
end

-- a witness whose name sorts late still includes itself in the names it reports
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "a witness whose name sorts after size+10 others still signs its report", function(c)
  local ns = c.ns
  local G, Rr = ns.RaidGlue, ns.Roster
  local origTime, origName = GetServerTime, UnitName
  GetServerTime = function() return 1795000000 end
  local cache = ns.rosterList()
  local extra = {}
  for i = 1, 20 do local n = ("Aa%02d-Realm"):format(i); cache[n] = { rank = 5, online = true, level = 20 }; extra[#extra + 1] = n end
  local okAll, err = pcall(function()
    local wall = G.WallNow()
    local rid = G.Create({ raid = "custom", size = 10, name = "Raid testigos", at = wall - 600 })
    ok(rid, "roster created")
    local d = Rr.copy(G.Get(rid).d); Rr.addPlayer(d, "Bob-Realm"); d.st = "published"
    ok(G.Save(rid, d), "published")
    ok(G.Close(rid), "closed by the GM (saw nothing -> pending)")
    -- Bob's client saw 21 guild members during the window (pre-raid party + swaps)
    local seen = {}
    seen["Bob-Realm"] = true
    for _, n in ipairs(extra) do seen[n] = true end
    ns.gdb.raidSeen = ns.gdb.raidSeen or {}
    ns.gdb.raidSeen[rid] = seen
    UnitName = function() return "Bob" end
    G.ReportSeen()
    UnitName = origName
    ok(ns.state.witness and ns.state.witness[Rr.witnessId(rid, "Bob-Realm")], "Bob's witness report was refused (own name cut)")
  end)
  UnitName, GetServerTime = origName, origTime
  for _, n in ipairs(extra) do cache[n] = nil end
  if not okAll then error(err, 0) end
end }

-- a burst of faction / skill / PvP kill events is coalesced into one counter sample
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "a burst of UPDATE_FACTION is coalesced into one counter sample", function(c)
  local ns, H = c.ns, c.ns.HallGlue
  local n = 0
  local origAfter, origS = ns.After, H.SampleCounters
  local probe = function() end
  H.SampleCounters = probe
  ns.After = function(d, fn) if fn == probe then n = n + 1 else return origAfter(d, fn) end end
  local okAll, err = pcall(function() for _ = 1, 50 do c.fire("UPDATE_FACTION") end end)
  ns.After, H.SampleCounters = origAfter, origS
  if not okAll then error(err, 0) end
  ok(n <= 2, n .. " full samples scheduled for 50 UPDATE_FACTION events")
end }

-- hello-reply pagination reaches every witness record
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "hello-reply pagination reaches every witness record", function(c)
  local ns = c.ns
  local S, M = ns.Sync, ns.Model
  local h = {}
  for _, k in ipairs({ "settings", "squad", "profile", "reject", "boss", "annul" }) do h[k] = M.bucketHashes(ns.state, k) end
  for _, k in ipairs(M.EXT_ORDER) do h[k] = M.bucketHashes(ns.state, k) end
  local added = {}
  for i = 1, 50 do
    local id = ("Pz%02d-Realm"):format(i)
    ns.state.profiles[id] = { k = "profile", id = id, a = id, ts = 1795000000, sq = 1, d = { role = "DAMAGER" } }
    added[#added + 1] = id
  end
  ns.state.witness = ns.state.witness or {}
  local wids = {}
  for i = 1, 100 do
    local id = ("Ann-Realm:1795000000#W%03d"):format(i)
    ns.state.witness[id] = { k = "witness", id = id, a = "Bob-Realm", ts = 1795000000, sq = i, d = { rid = "x", names = { "Bob-Realm" } } }
    wids[#wids + 1] = id
  end
  h.profile, h.witness = {}, {}   -- the requester holds none of them (and cannot store the profiles)
  local got, n = {}, 0
  local okAll, err = pcall(function()
    for _ = 1, 5 do
      for _, r in ipairs(S.ReplyFor({ h = h }, "Zed-Realm", nil, nil)) do
        if r.k == "witness" and r.id:find("#W", 1, true) and not got[r.id] then got[r.id] = true; n = n + 1 end
      end
    end
  end)
  for _, id in ipairs(added) do ns.state.profiles[id] = nil end
  for _, id in ipairs(wids) do ns.state.witness[id] = nil end
  if not okAll then error(err, 0) end
  eq(n, 100, "distinct witness records sent in 5 replies (300 slots)")
end }

-- v1.2 AC2/AC5: a 1.2 requester (p2 = 2, nonce) gets a random sample of 2 of 8 cubes, at most MAX_SAMPLE records
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "v1.2: hello reply to a 1.2 requester = 2 of 8 cubes by nonce, <= MAX_SAMPLE", function(c)
  local ns = c.ns
  local S, M = ns.Sync, ns.Model
  local h = {}
  for _, k in ipairs({ "settings", "squad", "profile", "reject", "boss", "annul" }) do h[k] = M.bucketHashes(ns.state, k) end
  for _, k in ipairs(M.EXT_ORDER) do h[k] = M.bucketHashes(ns.state, k) end
  local added = {}
  for i = 1, 200 do
    local id = ("Pc%03d-Realm"):format(i)
    ns.state.profiles[id] = { k = "profile", id = id, a = id, ts = 1795000000, sq = 1, d = { role = "DAMAGER" } }
    added[#added + 1] = id
  end
  h.profile = {}
  local nonce = 123457
  local oldOnline = ns.onlineCount
  ns.onlineCount = function() return 40 end        -- sampling only with more than SAMPLE_MIN_ONLINE online
  local okAll, err = pcall(function()
    local seen, union = {}, 0
    for _ = 1, 100 do
      local out = S.ReplyFor({ h = h, p2 = 2, nonce = nonce }, "Zed-Realm", nil, nil)
      ok(#out <= S.MAX_SAMPLE, #out .. " records in a 1.2 reply")
      local cubes, nc = {}, 0
      for _, r in ipairs(out) do
        local cb = S.CubeOf(r.id, nonce)
        if not cubes[cb] then cubes[cb] = true; nc = nc + 1 end
        if r.k == "profile" and r.id:find("^Pc") and not seen[r.id] then seen[r.id] = true; union = union + 1 end
      end
      ok(nc <= S.CUBES_PICK, nc .. " cubes in one reply")
    end
    eq(union, 200, "100 sampled replies cover every record")
    local old = S.ReplyFor({ h = h, p2 = 1, nonce = nonce }, "Old-Realm", nil, nil)
    eq(#old, 60, "a 1.1 requester still gets MAX_REPLY = 60, paginated")
  end)
  ns.onlineCount = oldOnline
  for _, id in ipairs(added) do ns.state.profiles[id] = nil end
  if not okAll then error(err, 0) end
end }

-- v1.2 AC1 (S11/S15 regression since 73862fd): with few members online every node replies (p = 1), so a random
-- sample of 30 without a cursor does not cover the backlog in 3 sessions; a 1.2 requester then gets MAX_REPLY with
-- the cursor, like 1.1 (traffic in big guilds, where the sample matters, does not change)
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "v1.2: with <= SAMPLE_MIN_ONLINE online a 1.2 requester gets MAX_REPLY paginated", function(c)
  local ns = c.ns
  local S, M = ns.Sync, ns.Model
  local h = {}
  for _, k in ipairs({ "settings", "squad", "profile", "reject", "boss", "annul" }) do h[k] = M.bucketHashes(ns.state, k) end
  for _, k in ipairs(M.EXT_ORDER) do h[k] = M.bucketHashes(ns.state, k) end
  local added = {}
  for i = 1, 200 do
    local id = ("Pd%03d-Realm"):format(i)
    ns.state.profiles[id] = { k = "profile", id = id, a = id, ts = 1795000000, sq = 1, d = { role = "DAMAGER" } }
    added[#added + 1] = id
  end
  h.profile = {}
  local oldOnline = ns.onlineCount
  ns.onlineCount = function() return 4 end
  local okAll, err = pcall(function()
    ok(S.SAMPLE_MIN_ONLINE and S.SAMPLE_MIN_ONLINE >= 8, "SAMPLE_MIN_ONLINE defined (>= 8, where p < 1)")
    local seen, union = {}, 0
    for n = 1, 4 do
      local out = S.ReplyFor({ h = h, p2 = 2, nonce = 1000 + n }, "Few-Realm", nil, nil)
      if n < 4 then eq(#out, 60, "reply " .. n .. " to a 1.2 requester with 4 online") end
      for _, r in ipairs(out) do
        if r.k == "profile" and r.id:find("^Pd") and not seen[r.id] then seen[r.id] = true; union = union + 1 end
      end
    end
    eq(union, 200, "4 paginated replies cover every record")
  end)
  ns.onlineCount = oldOnline
  for _, id in ipairs(added) do ns.state.profiles[id] = nil end
  if not okAll then error(err, 0) end
end }

-- v1.2 AC3 (S8g newcomer stuck, d5a17e9): an empty newcomer of a big guild gets its first replies from members, as
-- pending copies (quorum), not verified records; the extra hello rounds must go on while replies bring new pending
-- copies, or the newcomer never gets the second copies that verify them
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "v1.2: hello rounds go on while replies bring new pending copies", function(c)
  local ns = c.ns
  local S, Comm = ns.Sync, ns.Comm
  local cache = ns.rosterList()
  local extra = {}
  for i = 1, 40 do local n = ("Pr%02d-Realm"):format(i); cache[n] = { rank = 5, online = true, level = 20 }; extra[#extra + 1] = n end
  local origSend = Comm.Send
  local hellos = 0
  Comm.Send = function(tag, ...) if tag == "H" then hellos = hellos + 1 end end
  local okAll, err = pcall(function()
    S.Hello()
    eq(hellos, 1, "first hello")
    -- one member relays 12 profiles of others: they stay pending (quorum 2), none verified
    local recs = {}
    for i = 1, 12 do
      local a = extra[i + 1]
      recs[#recs + 1] = { k = "profile", id = a, a = a, ts = GetServerTime() - 1000 + i, sq = 1, d = { note = "r" .. i } }
    end
    S.OnMessage("D", { r = recs }, "Pr01-Realm")
    ok(ns.state.profiles[extra[2]] == nil, "a relayed profile is not verified by a single relayer")
    ok(ns.state.p2p and ns.state.p2p.pend and ns.state.p2p.pend["profile:" .. extra[2]], "it is held pending")
    runTimers(c, 31)
    eq(hellos, 2, "a second hello after replies that only brought pending copies")
  end)
  Comm.Send = origSend
  for _, n in ipairs(extra) do cache[n] = nil; ns.state.profiles[n] = nil end
  if ns.state.p2p and ns.state.p2p.pend then
    for k in pairs(ns.state.p2p.pend) do if k:find("Pr%d%d%-Realm") then ns.state.p2p.pend[k] = nil end end
  end
  if not okAll then error(err, 0) end
end }

-- v1.2 AC5 (S8 load): a 1.2 hello carries fine buckets h2 (Sync.FINE_NB) for the big kinds; a 1.2 replier diffs
-- on them, so it does not resend a whole coarse bucket the requester already holds
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "v1.2: a 1.2 replier diffs profiles on the fine buckets h2 of the hello", function(c)
  local ns = c.ns
  local S, M = ns.Sync, ns.Model
  local added = {}
  for i = 1, 200 do
    local id = ("Pf%03d-Realm"):format(i)
    ns.state.profiles[id] = { k = "profile", id = id, a = id, ts = 1795000000, sq = 1, d = { role = "DAMAGER" } }
    added[#added + 1] = id
  end
  local okAll, err = pcall(function()
    ok(type(S.FINE_NB) == "number" and S.FINE_NB >= 64, "Sync.FINE_NB >= 64")
    local h, h2 = {}, {}
    for _, k in ipairs({ "settings", "squad", "profile", "reject", "boss", "annul" }) do h[k] = M.bucketHashes(ns.state, k) end
    for _, k in ipairs(M.EXT_ORDER) do h[k] = M.bucketHashes(ns.state, k) end
    -- the requester lacks one profile: its hashes are ours without it
    local gone = ns.state.profiles["Pf007-Realm"]
    ns.state.profiles["Pf007-Realm"] = nil
    h.profile = M.bucketHashes(ns.state, "profile")
    h2.profile = M.bucketHashes(ns.state, "profile", S.FINE_NB)
    ns.state.profiles["Pf007-Realm"] = gone
    local coarse = M.diffRecords(ns.state, "profile", h.profile)
    local fineB = M.bucketOf("Pf007-Realm", S.FINE_NB)
    for _ = 1, 50 do
      local out = S.ReplyFor({ h = h, h2 = h2, p2 = 2, nonce = math.random(1, 1e9) }, "Zed-Realm", nil, nil)
      for _, r in ipairs(out) do
        if r.k == "profile" then ok(M.bucketOf(r.id, S.FINE_NB) == fineB, r.id .. " is outside the differing fine bucket") end
      end
    end
    ok(#coarse > 5, #coarse .. " records in the differing coarse bucket (the waste h2 avoids)")
    local old = S.ReplyFor({ h = h, h2 = h2, p2 = 1, nonce = 1 }, "Old-Realm", nil, nil)
    eq(#old, #coarse, "a 1.1 requester is diffed on the coarse buckets (h2 ignored)")
  end)
  for _, id in ipairs(added) do ns.state.profiles[id] = nil end
  if not okAll then error(err, 0) end
end }

-- v1.2 AC5 (traffic, attempt 3): replies are packed, Sync.PACK records per D message (<= 20, the receiver's cap), so
-- the small replies of many members do not each waste a half-empty last part
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "v1.2: records are packed Sync.PACK per D message, fewer parts than 3 per message", function(c)
  local ns = c.ns
  local S, Comm = ns.Sync, ns.Comm
  ok(type(S.PACK) == "number" and S.PACK >= 6 and S.PACK <= 20, "Sync.PACK in [6, 20]")
  ok(type(S.PackRecords) == "function", "Sync.PackRecords exists")
  local list = {}
  for i = 1, 24 do
    local id = ("Pk%03d-Realm"):format(i)
    list[i] = { k = "profile", id = id, a = id, ts = 1795000000 + i, sq = 1, d = { role = "DAMAGER", note = "x" } }
  end
  local batches = S.PackRecords(list)
  local n, packed, old = 0, 0, 0
  for _, b in ipairs(batches) do
    ok(#b <= S.PACK, #b .. " records in one D")
    n = n + #b
    packed = packed + Comm.Parts("D", { r = b })
  end
  eq(n, 24, "every record is sent once")
  for i = 1, 24, 3 do old = old + Comm.Parts("D", { r = { list[i], list[i + 1], list[i + 2] } }) end
  ok(packed < old, packed .. " parts packed vs " .. old .. " at 3 per message")
  eq(S.EstimateParts(list), packed, "EstimateParts matches the packing")
end }

-- leaving the guild and joining another in-session switches the per-guild data partition
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "leaving the guild and joining another in-session switches the per-guild data", function(c)
  local ns = c.ns
  local origIn, origInfo = IsInGuild, GetGuildInfo
  local oldKey = ns.guildKey
  ok(oldKey, "a guild key was selected at bootstrap")
  IsInGuild = function() return false end
  c.fire("GUILD_ROSTER_UPDATE"); runTimers(c, 5)
  GetGuildInfo = function() return "Otra Guild", "Member", 4, nil end
  IsInGuild = function() return true end
  c.fire("GUILD_ROSTER_UPDATE"); runTimers(c, 5)
  local newKey = ns.Model.guildKey("Otra Guild", "Realm")
  local now = ns.guildKey
  IsInGuild, GetGuildInfo = origIn, origInfo
  c.fire("GUILD_ROSTER_UPDATE"); runTimers(c, 5)   -- back to the original guild
  eq(ns.guildKey, oldKey, "back to the original guild")
  eq(now, newKey, "guild key after joining another guild (old: " .. tostring(oldKey) .. ")")
end }
