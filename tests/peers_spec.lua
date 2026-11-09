-- 1.2.1 (BRO 9-nov-2026, real client: 317 members, ~60 online, 2-3 on 1.2; /gsq diag sample=0, sig verified=0):
-- who answers a hello is a 1.2 client, not any guild member online. The reply probability (8 / n), the cube sample
-- (n > SAMPLE_MIN_ONLINE) and the Hall pages (4 / n) count the 1.2 peers (ns.peerCount), never ns.onlineCount.
-- Checks run inside zload_spec.lua (the whole addon on the fake client: me = Ann-Realm, Bob / Cid online members).

SMOKE_CHECKS = SMOKE_CHECKS or {}

-- GetTime pinned to `t` while fn runs (heard entries older than Sync.PEER_FRESH then fall out of the count)
local function at(t, fn)
  local origT = GetTime
  GetTime = function() return t end
  local okF, err = pcall(fn)
  GetTime = origT
  if not okF then error(err, 0) end
end

local function hashesOf(ns)
  local M, h = ns.Model, {}
  for _, k in ipairs({ "settings", "squad", "profile", "reject", "boss", "annul" }) do h[k] = M.bucketHashes(ns.state, k) end
  for _, k in ipairs(M.EXT_ORDER) do h[k] = M.bucketHashes(ns.state, k) end
  return h
end

SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "1.2.1: ns.peerCount = me + PROTO 2 senders heard in the last PEER_FRESH s, online in the roster", function(c)
  local ns = c.ns
  local S, Comm, Sz, Ch = ns.Sync, ns.Comm, ns.Serialize, ns.Chunk
  ok(type(ns.peerCount) == "function", "ns.peerCount exists")
  ok(type(S.PEER_FRESH) == "number" and S.PEER_FRESH >= 900, "Sync.PEER_FRESH >= 900 s (" .. tostring(S.PEER_FRESH) .. ")")
  local t0 = GetTime() + 100000                     -- far after every sender heard by the earlier checks
  at(t0, function()
    eq(ns.peerCount(), 1, "nobody heard in the window: only me")
    S.OnMessage("X", {}, "Bob-Realm", "GUILD")      -- any PROTO 2 message (an unknown tag is ignored)
    eq(ns.peerCount(), 2, "Bob heard: me + Bob")
    S.OnMessage("X", {}, "Cid", "GUILD")            -- a bare same-realm sender is the same key as the roster's
    eq(ns.peerCount(), 3, "Cid heard: me + Bob + Cid")
    S.OnMessage("X", {}, "Zed-Realm", "GUILD")      -- not in our roster
    eq(ns.peerCount(), 3, "a sender missing from the roster is not a peer")
    S.OnMessage("X", {}, "Ann-Realm", "GUILD")      -- myself
    eq(ns.peerCount(), 3, "I count once")
  end)
  at(t0 + S.PEER_FRESH + 1, function() eq(ns.peerCount(), 1, "after PEER_FRESH s of silence nobody counts") end)
  -- a PROTO 1 client (1.0.x / 1.1) reaches Comm and is dropped there (badProto): never a peer
  at(t0 + 3 * S.PEER_FRESH, function()
    local before = Comm.stats.badProto
    local body = Sz.escape(Sz.encode({ v = 1, t = "H", p = { h = {} } }))
    for _, part in ipairs(Ch.split(body, "q1")) do Comm.OnEvent("CHAT_MSG_ADDON", Comm.PREFIX, part, "GUILD", "Cid-Realm") end
    eq(Comm.stats.badProto, before + 1, "the PROTO 1 hello was counted as badProto")
    eq(ns.peerCount(), 1, "a PROTO 1 sender is not a 1.2 peer")
  end)
  -- a peer that logged off (roster online = false) stops counting at once
  at(t0 + 5 * S.PEER_FRESH, function()
    S.OnMessage("X", {}, "Bob-Realm", "GUILD")
    eq(ns.peerCount(), 2, "Bob heard again")
  end)
  c.roster[2][9] = false; c.fire("GUILD_ROSTER_UPDATE"); c.tick(2) --[[coalesced roster]]
  at(t0 + 5 * S.PEER_FRESH + 3, function() eq(ns.peerCount(), 1, "Bob offline in the roster: not a peer") end)
  c.roster[2][9] = true; c.fire("GUILD_ROSTER_UPDATE"); c.tick(2) --[[coalesced roster]]
end }

-- the 60 online of BRO's guild with 2 peers: a 1.2 requester must get MAX_REPLY paginated (all 3 answer, p = 1), not
-- 2 of 8 cubes (1.2.0: online 60 > SAMPLE_MIN_ONLINE -> sample=0 / a quarter of the diff per reply)
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "1.2.1: 60 online but 2 peers -> a 1.2 requester gets MAX_REPLY paginated, no cube sample", function(c)
  local ns = c.ns
  local S = ns.Sync
  local h = hashesOf(ns)
  local added = {}
  for i = 1, 200 do
    local id = ("Pp%03d-Realm"):format(i)
    ns.state.profiles[id] = { k = "profile", id = id, a = id, ts = 1795000000, sq = 1, d = { role = "DAMAGER" } }
    added[#added + 1] = id
  end
  h.profile = {}
  local oldOnline = ns.onlineCount
  ns.onlineCount = function() return 60 end       -- guild members online (BRO's diag), only 3 run 1.2
  local okAll, err = pcall(function()
    at(GetTime() + 200000, function()
      S.OnMessage("X", {}, "Bob-Realm", "GUILD"); S.OnMessage("X", {}, "Cid-Realm", "GUILD")
      if ns.peerCount then eq(ns.peerCount(), 3, "3 peers") end
      local seen, union = {}, 0
      for n = 1, 4 do
        local out = S.ReplyFor({ h = h, p2 = 2, nonce = 7000 + n }, "Bob-Realm", nil, nil)
        if n < 4 then eq(#out, 60, "reply " .. n .. " to a 1.2 requester with 60 online and 3 peers") end
        for _, r in ipairs(out) do
          if r.k == "profile" and r.id:find("^Pp") and not seen[r.id] then seen[r.id] = true; union = union + 1 end
        end
      end
      eq(union, 200, "4 paginated replies cover every record")
    end)
  end)
  ns.onlineCount = oldOnline
  for _, id in ipairs(added) do ns.state.profiles[id] = nil end
  if not okAll then error(err, 0) end
end }

-- the reply draw: with 3 peers every node answers (p = min(1, 8 / 3) = 1); 1.2.0 drew 8 / 60 = 0.13
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "1.2.1: 60 online but 3 peers -> every hello gets our reply (p = 1)", function(c)
  local ns = c.ns
  local S, Comm = ns.Sync, ns.Comm
  local h = hashesOf(ns)
  local oldOnline, origSend, origRand, oldMin = ns.onlineCount, Comm.Send, math.random, S.HELLO_MIN
  ns.onlineCount = function() return 60 end
  math.random = function(x, y) if x == nil then return 0.5 end return origRand(x, y) end   -- p must be >= 0.5
  Comm.Send = function(_, _, _, _, onSent) if onSent then onSent() end return true end
  S.HELLO_MIN = 0
  local okAll, err = pcall(function()
    at(GetTime() + 300000, function()
      S.OnMessage("X", {}, "Cid-Realm", "GUILD")
      local before = S.stats.replied
      for n = 1, 5 do S.OnMessage("H", { h = h, p2 = 2, nonce = 8000 + n }, "Bob-Realm", "GUILD") end
      eq(S.stats.replied - before, 5, "5 hellos from Bob, 5 replies")
    end)
  end)
  ns.onlineCount, Comm.Send, math.random, S.HELLO_MIN = oldOnline, origSend, origRand, oldMin
  if not okAll then error(err, 0) end
end }

-- the Hall pages (race observations): 1.2.0 drew 4 / onlineCount; with 3 peers every node sends its page
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "1.2.1: 60 online but 3 peers -> the Hall answers a hello (p = 4 / peers = 1)", function(c)
  local ns = c.ns
  local S, H = ns.Sync, ns.HallGlue
  -- Ann a plain member first (officers always send the page); the coalesced roster read needs the real ns.After
  c.roster[1][3] = 4; c.fire("GUILD_ROSTER_UPDATE"); c.tick(2) --[[coalesced roster]]
  local wasOfficer = ns.Permissions.isOfficer(ns.roster, ns.me(), ns.Model.settingsOf(ns.state))
  local oldOnline, origRand, origAfter, origEnabled = ns.onlineCount, math.random, ns.After, H.Enabled
  ns.onlineCount = function() return 60 end
  math.random = function(x, y) if x == nil then return 0.5 end return origRand(x, y) end
  local scheduled = 0
  ns.After = function(d) if d >= 3 and d <= 11 then scheduled = scheduled + 1 end end
  H.Enabled = function() return true end
  local okAll, err = pcall(function()
    ok(not wasOfficer, "Ann is a plain member for this check")
    at(GetTime() + 400000, function()
      S.OnMessage("X", {}, "Bob-Realm", "GUILD"); S.OnMessage("X", {}, "Cid-Realm", "GUILD")
      H.OnHello({}, "Bob-Realm")
      eq(scheduled, 1, "the Hall reply page was scheduled")
    end)
  end)
  ns.onlineCount, math.random, ns.After, H.Enabled = oldOnline, origRand, origAfter, origEnabled
  c.roster[1][3] = 0; c.fire("GUILD_ROSTER_UPDATE"); c.tick(2) --[[coalesced roster]]
  if not okAll then error(err, 0) end
end }

-- /gsq diag (1.2.1): the peers counted, the senders heard and those the roster does not know (a realm-name mismatch
-- between CHAT_MSG_ADDON and the roster shows as notInRoster > 0, with the first name), and the realms of the roster
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "1.2.1: /gsq diag has the peers line (n, heard, notInRoster) and the roster realms", function(c)
  local ns = c.ns
  at(GetTime() + 500000, function()
    ns.Sync.OnMessage("X", {}, "Bob-Realm", "GUILD")
    local out = ns.DiagGlue.Report()
    ok(type(out) == "string" and out:find("peers n=2 heard=%d+ notInRoster=%d+"), "peers line: " .. tostring(out):sub(1, 80))
    ok(out:find("notInRoster=%d+ %(Zed%-Realm%)") or out:find("notInRoster=%d+ %([%w%-]+%)"), "the first sender missing from the roster is named")
    ok(out:find("[roster] me=Ann-Realm found=yes entries=3 surnames=0 online=3 realms=Realm:3", 1, true), "roster realms")
  end)
end }

-- 1.2.1 (BRO's chat, 9-nov: «No hay ningún jugador con el nombre Magic Essency-CAMWOWEU4Realm6PvP», repeated, with
-- the names of guildmates on 1.2): WoW Forever gives the roster surname in the sender of CHAT_MSG_ADDON too ("Cid
-- Essency", "Cid Essency-Realm"). A sender is the character key ("Cid-Realm": the author of his records, the roster
-- key, the name a whisper reaches): his key is pinned under it, every whisper goes to it, our own echo is ours.
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "1.2.1: a sender with a surname is the character: key, roster, whisper target, own echo", function(c)
  local ns = c.ns
  local S, Comm, T = ns.Sync, ns.Comm, ns.Trust
  eq(ns.id("Cid Essency"), "Cid-Realm", "bare name + surname")
  eq(ns.id("Cid Essency-Realm"), "Cid-Realm", "surname before the realm")
  eq(ns.id("Cid-Realm Essency"), "Cid-Realm", "surname after the realm")
  eq(ns.id("Cid"), "Cid-Realm", "a name without surname as before")
  ok(ns.roster("Cid Essency") ~= nil, "the roster finds a sender with a surname")
  ok(ns.isSelf("Ann Essency"), "our own echo with a surname is ours")
  ok(Comm.ChannelOk("WHISPER", "Cid Essency-Realm"), "a whisper from a member with a surname is accepted")
  -- the last line of defence: Comm.Send never whispers a name with a surname
  local q = Comm.queue
  local origPush, got = q.pushMessage, nil
  q.pushMessage = function(_, parts) got = parts[1] and parts[1].target; return true end
  local okQ, errQ = pcall(Comm.Send, "D", { r = {}, z = 1 }, "WHISPER", "Cid Essency-Realm")
  q.pushMessage = origPush
  -- 1.2.2: the target is the roster name of the character key (with the surname when the roster has one; none here)
  ok(okQ, tostring(errQ)); eq(got, ns.whisperTarget("Cid-Realm"), "Comm.Send whispers the roster name of Cid-Realm")
  local origSend, origAfter = Comm.Send, ns.After
  local wh = {}
  Comm.Send = function(_, _, ch, to, onSent) if ch == "WHISPER" then wh[#wh + 1] = tostring(to) end if onSent then onSent() end return true end
  ns.After = function(_, fn) fn() end
  local okAll, err = pcall(function()
    at(GetTime() + 600000, function()
      -- a hello from "Cid Essency" with his key and a reference to his certificate (we lack it: we ask by whisper)
      S.OnMessage("H", { h = {}, p2 = 2, nonce = 99, pk = T.hex(string.rep("\7", 32)), cr = { n = 777, h = "abcdefabcdef" } }, "Cid Essency", "GUILD")
      local _, s = T.keyOf(ns.trustDB, "Cid-Realm")
      eq(s, "strong", "Cid's key pinned under Cid-Realm")
      ok(T.keyOf(ns.trustDB, "Cid Essency-Realm") == nil, "nothing pinned under the name with the surname")
      ok(#wh >= 1, "the certificate ask (and the rest of the reply) was whispered: " .. #wh)
      for _, to in ipairs(wh) do eq(to, "Cid-Realm", "whisper target") end
    end)
  end)
  Comm.Send, ns.After = origSend, origAfter
  if ns.trustDB then T.reset(ns.trustDB, "Cid-Realm"); T.reset(ns.trustDB, "Cid Essency-Realm") end
  if not okAll then error(err, 0) end
end }
