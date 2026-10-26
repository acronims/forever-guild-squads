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
