-- Guild Squads (MIT) - Sync.lua
-- Replication over the GUILD addon channel.
--   "D" = records (deltas / replies), "H" = hello with bucketed state hashes.
-- Records are validated locally (Core/Model.lua) before being stored.
--   * every record is shape-checked before use and applied under pcall; broken ones are counted and dropped
--   * relay trust: live = sender is the author; relayed = sender is GM/officer. Nothing else.
--     There is no "announced hash" path (24-bit hashes are forgeable). Records >300 s
--     in the future are refused; refused records are never stored, so they are never relayed.
--   * v1.1 (Core/P2P.lua): AUTHORIAL records (M.P2P_KINDS) relayed by anyone wait as "unverified" until the same
--     version comes from 2 distinct relayers (or the captain of their squad, or the author). Every 1.1 client
--     answers a 1.1 hello (p2 = 1) with authorial records of others too; up to 2 relayed copies of a version go on
--     the wire per hello. Versions held unverified are whispered to the requester flagged u = 1 (shown, never a
--     vote). Authority records keep the old rule: live, or relayed by a GM/officer.
--   * hello replies page with a per-requester cursor and the requester re-hellos while it keeps learning
local _, ns = ...
ns = ns or {}

local Sync = {}
ns.Sync = Sync
local M, Comm, X = ns.Model, ns.Comm, ns.P2P

local KINDS = { "settings", "squad", "profile", "reject", "boss", "annul" }
-- kinds registered by pure modules (roster, rsvp, attendance) travel the same way. A peer only gets them
-- in hello replies when its hello carries hashes for that kind (older versions would refuse them anyway).
local CORE_KIND = {}
for _, k in ipairs(KINDS) do CORE_KIND[k] = true end
for _, k in ipairs(M.EXT_ORDER or {}) do KINDS[#KINDS + 1] = k end
local MAX_REPLY = 60          -- records per hello reply
local MAX_PENDING = 5000      -- records waiting for the guild roster (own disk + early network)
local MAX_ROUNDS = 6          -- extra hellos while a fresh client keeps learning
local MAX_FORWARD = 20        -- unverified versions (u = 1) whispered per hello reply
local pending = {}            -- { rec, sender } waiting for the guild roster
local seenAfter = {}          -- id -> version string seen on the wire (reply suppression)
local corrections = {}        -- id -> true when a correction is already scheduled
local cursor = {}             -- requester -> last reply key sent (pagination)
local heard = {}              -- sender -> GetTime() of the last addon message (addon detection)
Sync.stats = { bad = 0, relayRefused = 0, future = 0, errors = 0, quarantined = 0, pending = 0, mine = 0 }

local function vkey(r) return tostring(r.ts) .. "." .. tostring(r.sq) .. "." .. tostring(r.a) end
local function serverNow()
  if ns.serverTime then return ns.serverTime() end
  if GetServerTime then return GetServerTime() end
  return nil
end

local function ctxFor(sender)
  return { roster = ns.roster, sender = sender, me = ns.me and ns.me() or nil, now = serverNow(),
           ledger = ns.gdb and ns.gdb.mine or nil }
end

local function applyRaw(rec, ctx)
  local okC, ok, why = pcall(M.apply, ns.state, rec, ctx)
  if not okC then Sync.stats.errors = Sync.stats.errors + 1; return false, "error" end
  return ok, why
end

local function afterApply(rec, ok)
  if ok and ns.UI and ns.UI.Dirty then pcall(ns.UI.Dirty) end
  if ok and (rec.k == "annul" or rec.k == "boss" or rec.k == "vconfirm" or rec.k == "achdef" or rec.k == "achgrant")
     and ns.HallGlue then pcall(ns.HallGlue.MarkDirty) end
  if ok and ns.RaidGlue and ns.RaidGlue.OnRecord and M.EXT[rec.k] then pcall(ns.RaidGlue.OnRecord, rec) end
end

-- sender = physical sender (nil = local/own disk)
function Sync.Apply(rec, sender)
  local ok, why = applyRaw(rec, sender and ctxFor(sender) or { roster = ns.roster })
  if not ok and why == "notInGuild" and not ns.rosterReady then
    if #pending < MAX_PENDING then pending[#pending + 1] = { rec = rec, sender = sender } end
  elseif not ok and why == "relay" then
    Sync.stats.relayRefused = Sync.stats.relayRefused + 1
  elseif not ok and (why == "pending" or why == "conflict") then
    Sync.stats.pending = Sync.stats.pending + 1
  elseif not ok and why == "mine" then
    -- a relayed version with my name that I never wrote: deny it (repudiate) and resend mine
    Sync.stats.mine = Sync.stats.mine + 1
    if ns.OnMine then pcall(ns.OnMine, rec) end
  elseif not ok and why == "future" then
    Sync.stats.future = Sync.stats.future + 1
    -- a record from a peer whose clock is ahead of ours is applied again once it is no
    -- longer in the future (< 30 min ahead); before, it stayed refused until the next hello, which may never come
    local now = serverNow()
    local wait = now and type(rec.ts) == "number" and rec.ts - now - M.MAX_FUTURE + 2
    if wait and wait > 0 and wait <= 1800 and ns.After then ns.After(wait, function() Sync.Apply(rec, sender) end) end
  end
  -- the author contradicted a version we had by relay: whisper that version to the author (u = 1) so its client
  -- can repudiate it everywhere
  if ok and sender and X and X.outbox and #X.outbox > 0 then
    for _, r in ipairs(X.popContra()) do
      Comm.Send("D", { r = { { k = r.k, id = r.id, a = r.a, ts = r.ts, sq = r.sq, d = r.d, u = 1 } } }, "WHISPER", sender)
    end
  end
  afterApply(rec, ok)
  return ok, why
end

function Sync.FlushPending()
  local list = pending
  pending = {}
  table.sort(list, function(a, b)
    local x, y = a.rec, b.rec
    local ox, oy = M.kindOrder(x.k), M.kindOrder(y.k)
    if ox ~= oy then return ox < oy end
    return (tonumber(x.ts) or 0) < (tonumber(y.ts) or 0)
  end)
  for _, p in ipairs(list) do Sync.Apply(p.rec, p.sender) end
end

-- hellos carry no announced hashes; an `an` list from a peer is ignored
function Sync.OnAnnounce() end

-- local write: apply then broadcast
function Sync.Publish(rec)
  local ok, why = M.apply(ns.state, rec, { roster = ns.roster })
  if not ok then return false, why end
  Comm.Send("D", { r = { rec } }, nil, nil, nil, true)   -- own fresh records skip the reply backlog
  if ns.UI and ns.UI.Dirty then ns.UI.Dirty() end
  return true
end

-- a record version already waiting in our send queue is not queued again for the next
-- hello (otherwise 30 logins would queue 30 copies of the same records: ~470 messages, 8 minutes of backlog per officer)
local queued = {}             -- id -> version string waiting in the send queue
local function sendRecords(list, to)
  -- group a few records per message; Comm chunks large payloads
  local batch = {}
  local function flush()
    local ids = {}
    for i, r in ipairs(batch) do ids[i] = { r.id, vkey(r) }; queued[r.id] = vkey(r) end
    local function done() for _, x in ipairs(ids) do if queued[x[1]] == x[2] then queued[x[1]] = nil end end end
    if Comm.Send("D", { r = batch }, nil, nil, done) == false then done() end
    batch = {}
  end
  for _, r in ipairs(list) do
    batch[#batch + 1] = r
    if #batch >= Sync.BATCH then flush() end
  end
  if #batch > 0 then flush() end
end
-- a bulk write (the GM's "activar/desactivar todo") = N ordinary records, applied locally and
-- sent 3 per message through the normal throttled queue (1 msg/s, burst 4), no special record. -> applied, refused
Sync.BATCH = 3
Sync.MAX_PRESENCE_REPLY = 6
function Sync.PublishMany(list)
  local okList, refused = {}, 0
  for _, rec in ipairs(list or {}) do
    if M.apply(ns.state, rec, { roster = ns.roster }) then okList[#okList + 1] = rec else refused = refused + 1 end
  end
  if #okList > 0 then
    sendRecords(okList)
    if ns.UI and ns.UI.Dirty then pcall(ns.UI.Dirty) end
    if ns.HallGlue and ns.HallGlue.MarkDirty then pcall(ns.HallGlue.MarkDirty) end
  end
  return #okList, refused
end
-- messages (parts) that list would take in the queue = seconds at 1 msg/s
function Sync.EstimateParts(list)
  local parts, batch = 0, {}
  for i, rec in ipairs(list or {}) do
    batch[#batch + 1] = rec
    if #batch >= Sync.BATCH or i == #list then parts = parts + Comm.Parts("D", { r = batch }); batch = {} end
  end
  return parts
end
function Sync.Resend(rec) if rec then sendRecords({ rec }) end end
function Sync.QueuedCount() local n = 0 for _ in pairs(queued) do n = n + 1 end return n end

local round, learned = 0, 0
local syncUntil = 0
-- "initial sync" = 2 min after a hello, extended while replies keep teaching us records
function Sync.Syncing() return (GetTime and GetTime() or 0) < syncUntil end
function Sync.Hello(again)
  if not again then round = 0 end
  learned = 0
  syncUntil = (GetTime and GetTime() or 0) + 120
  local h = {}
  for _, k in ipairs(KINDS) do
    h[k] = M.bucketHashes(ns.state, k)
    -- v1.1 kinds: an empty table when we hold none (same meaning as 16 "0" buckets, fewer bytes; 1.0 peers ignore them)
    if (k == "presence" or k == "repudiate") and not next(M.kindTable(ns.state, k)) then h[k] = {} end
  end
  local msg = { h = h }
  -- per-author MetricEvent counts, so authors can re-send their own events to whoever lacks them
  if ns.ProgressGlue and ns.ProgressGlue.Enabled() then
    msg.ec = ns.ProgressGlue.HelloCounts()
    if ns.ProgressGlue.HelloSummaries then msg.ws = ns.ProgressGlue.HelloSummaries() end
  end
  -- bucket hashes of the race observations / closed races (peers answer with paginated diffs)
  if ns.HallGlue and ns.HallGlue.Enabled() then msg.rh = ns.HallGlue.HelloHashes() end
  -- v1.1: we take authorial relays from anyone; bucket hashes of the versions we hold unverified
  if X then
    msg.p2 = X.PROTO
    local ph
    for _, k in ipairs(KINDS) do
      if M.P2P_KINDS[k] or M.P2P_AUTH then           -- v1.2: authority kinds wait as pending too
        local hs, any = X.pendHashes(ns.state, k)
        if any then ph = ph or {}; ph[k] = hs end
      end
    end
    msg.ph = ph
  end
  Comm.Send("H", msg)
  -- keep asking (with growing delay) while replies keep teaching us records
  if ns.After then
    ns.After(30 + 15 * round, function()
      if learned >= 10 and round < MAX_ROUNDS then round = round + 1; Sync.Hello(true) end
    end)
  end
end

-- already on the wire since the hello: any copy for authority records (and for 1.0 requesters); for authorial
-- records sent to a 1.1 requester, a copy from the author / an officer, or copies from 2 distinct relayers
-- (v1.2: and for authority records sent to a 1.2 requester, copies from QUORUM_AUTH distinct relayers)
local function suppressed(r, startedAt, p2p, auth)
  local seen = seenAfter[r.id]
  if not (seen and startedAt and seen.v == vkey(r)) then return false end
  if not (p2p and (M.isP2P(r) or auth)) then return seen.t >= startedAt end
  if (seen.tt or -1) >= startedAt then return true end
  local n = 0
  for _, t in pairs(seen.by or {}) do if t >= startedAt then n = n + 1 end end
  return n >= X.quorumFor(r)
end

-- records that differ from the requester, starting after the last one we sent it (cursor), at most MAX_REPLY.
-- a non-officer replies with its own records, plus (v1.1, to a 1.1 requester) the authorial records of others.
-- presences of others (v1.1, BRO 7-nov): an officer never relays them (S8: officers relaying them on every hello
-- filled their queues past 500); a member relays them to a 1.1 requester even while an officer is online
-- (p2pOff), at most MAX_PRESENCE_REPLY per reply, picked at random among the candidates.
function Sync.ReplyFor(payload, sender, startedAt, onlyAuthor, p2pOff, officer)
  local all = {}
  local proto = X and X.protoOf(payload) or 0
  local p2pReq = proto >= 1
  local p2p = p2pReq and not p2pOff
  local auth = p2p and proto >= 2          -- v1.2 requester: authority records of others too (quorum 3)
  local me = ns.me and ns.me() or nil
  local pres = {}               -- indexes in all of others' presences (candidates)
  for ki, k in ipairs(KINDS) do
    local list = (CORE_KIND[k] or payload.h[k] ~= nil) and M.diffRecords(ns.state, k, payload.h[k]) or {}
    for _, r in ipairs(list) do
      local otherPres = r.k == "presence" and r.a ~= me
      if otherPres and officer then
        -- skip: officers never relay others' presences
      elseif otherPres and onlyAuthor and r.a ~= onlyAuthor and not p2pReq then
        -- skip: a 1.0 requester only takes a member's own records
      elseif not otherPres and onlyAuthor and r.a ~= onlyAuthor and not (p2p and (auth or M.isP2P(r))) then
        -- skip: not ours to relay
      elseif queued[r.id] == vkey(r) then
        -- this version is already waiting in our send queue
      elseif not suppressed(r, startedAt, otherPres and p2pReq or p2p, auth) then
        all[#all + 1] = { key = ("%03d|%s"):format(ki, r.id), r = r }   -- numeric kind order
        if otherPres then pres[#pres + 1] = #all end
      end
    end
  end
  if #pres > Sync.MAX_PRESENCE_REPLY then
    -- keep MAX_PRESENCE_REPLY of them at random (partial Fisher-Yates), drop the rest; order of all is kept
    for i = 1, Sync.MAX_PRESENCE_REPLY do
      local j = math.random(i, #pres)
      pres[i], pres[j] = pres[j], pres[i]
    end
    local drop = {}
    for i = Sync.MAX_PRESENCE_REPLY + 1, #pres do drop[pres[i]] = true end
    local kept = {}
    for i, e in ipairs(all) do if not drop[i] then kept[#kept + 1] = e end end
    all = kept
  end
  if #all == 0 then return {} end
  local last = cursor[sender]
  local start = 1
  if last then
    start = #all + 1
    for i, e in ipairs(all) do if e.key > last then start = i; break end end
    if start > #all then start = 1 end
  end
  local out = {}
  local i = start
  repeat
    out[#out + 1] = all[i].r
    cursor[sender] = all[i].key
    i = i % #all + 1
  until #out >= MAX_REPLY or i == start
  return out
end

-- versions we hold unverified that a 1.1 requester lacks (copies flagged u = 1), at most MAX_FORWARD
function Sync.ForwardsFor(payload)
  local proto = X and X.protoOf(payload) or 0
  if proto < 1 then return {} end
  local ph = type(payload.ph) == "table" and payload.ph or {}
  local all = {}
  for _, k in ipairs(KINDS) do
    -- authority versions held pending only go to a 1.2 requester (a 1.1 one refuses a member's relay of them)
    if M.P2P_KINDS[k] or (proto >= 2 and M.P2P_AUTH) then
      for _, r in ipairs(X.pendDiff(ns.state, k, type(ph[k]) == "table" and ph[k] or nil)) do all[#all + 1] = r end
    end
  end
  if #all <= MAX_FORWARD then return all end
  local out, start = {}, math.random(1, #all)
  for i = 0, MAX_FORWARD - 1 do out[#out + 1] = all[(start + i - 1) % #all + 1] end
  return out
end

local function isOfficerMe()
  local P = ns.Permissions
  return P and ns.me and ns.roster and P.isOfficer(ns.roster, ns.me(), M.settingsOf(ns.state)) or false
end

local function onHello(payload, sender)
  if type(payload) ~= "table" or type(payload.h) ~= "table" then return end
  local from = (ns.fullName and ns.fullName(sender)) or sender
  if ns.ProgressGlue and type(payload.ec) == "table" then ns.ProgressGlue.OnHello(payload.ec, sender) end
  if ns.ProgressGlue and ns.ProgressGlue.OnSummaries and type(payload.ws) == "table" then
    ns.ProgressGlue.OnSummaries(payload.ws, sender)
  end
  if ns.HallGlue then ns.HallGlue.OnHello(payload.rh, sender) end
  -- only a fraction of the guild answers, after random jitter, to avoid a reply storm. Officers always answer:
  -- their relays are trusted, so a fresh client can converge even when the authors are offline.
  local online = ns.onlineCount and ns.onlineCount() or 1
  local p = math.min(1, 8 / math.max(1, online))
  local officer = isOfficerMe()
  if not officer and math.random() > p then return end
  local startedAt = GetTime and GetTime() or 0
  local onlyMe = (not officer) and ns.me and ns.me() or nil
  -- v1.1: while a GM/officer with the addon is online, their trusted relays already serve the requester: a member
  -- answers like 1.0 (own records only, no unverified forwards). P2P relaying is for the hours without them.
  -- v1.2: only for 1.0 / 1.1 requesters; a 1.2 requester is served P2P whoever is online (officers are one more node)
  local p2pOff = (not officer) and (not X or X.protoOf(payload) < 2) and Sync.TrustedOnline()
  ns.After(2 + math.random() * 6, function()
    local out = Sync.ReplyFor(payload, from, startedAt, onlyMe, p2pOff, officer)
    if ns.debug then ns.debug(("hello from %s: replying %d records"):format(tostring(sender), #out)) end
    sendRecords(out)
    if p2pOff then return end
    -- unverified versions only go to the requester (a 1.0 client would trust them from an officer)
    local fw = Sync.ForwardsFor(payload)
    for i = 1, #fw, Sync.BATCH do
      local batch = {}
      for j = i, math.min(#fw, i + Sync.BATCH - 1) do batch[#batch + 1] = fw[j] end
      Comm.Send("D", { r = batch }, "WHISPER", from)
    end
  end)
end

local function stored(rec) return M.stored(ns.state, rec) end

local function onRecords(payload, sender)
  if type(payload) ~= "table" or type(payload.r) ~= "table" then return end
  local from = (ns.fullName and ns.fullName(sender)) or sender
  local t = GetTime and GetTime() or 0
  for i = 1, math.min(#payload.r, 20) do
    local rec = payload.r[i]
    if not M.validShape(rec) then
      Sync.stats.bad = Sync.stats.bad + 1
    else
      if rec.u == nil then
        -- who put this version on the wire since the hello (reply suppression, see suppressed())
        local v = vkey(rec)
        local seen = seenAfter[rec.id]
        if not seen or seen.v ~= v then seen = { v = v, by = {} }; seenAfter[rec.id] = seen end
        seen.t = t
        local P = ns.Permissions
        if from == rec.a or (P and P.isOfficer(ns.roster, from, M.settingsOf(ns.state))) then seen.tt = t
        else seen.by[from] = t end
      end
      local ok, why = Sync.Apply(rec, from)
      -- presences do not keep the hello rounds going (one per member, low value; the next hello brings them)
      if ok and rec.k ~= "presence" then learned = learned + 1; syncUntil = math.max(syncUntil, t + 60) end
      if ns.debug then ns.debug(("rec %s/%s from %s: %s"):format(tostring(rec.k), rec.id, tostring(sender), ok and "applied" or tostring(why))) end
      if why == "stale" and not corrections[rec.id] then
        -- the sender has an older copy; re-broadcast ours unless someone else does it first
        corrections[rec.id] = true
        ns.After(3 + math.random() * 7, function()
          corrections[rec.id] = nil
          local mine = stored(rec)
          local seen = seenAfter[rec.id]
          if mine and not (seen and seen.v == vkey(mine)) then sendRecords({ mine }) end
        end)
      end
    end
  end
end

local function dispatch(tag, payload, sender, sentAt)
  if tag == "D" then onRecords(payload, sender)
  elseif tag == "H" then onHello(payload, sender)
  elseif tag == "C" and ns.OnCall then ns.OnCall(payload, sender)
  elseif tag == "E" and ns.ProgressGlue then ns.ProgressGlue.OnEvents(payload, sender)
  elseif tag == "RO" and ns.HallGlue then ns.HallGlue.OnObs(payload, sender, false, sentAt)
  elseif tag == "RP" and ns.HallGlue then ns.HallGlue.OnObs(payload, sender, true, sentAt)
  elseif tag == "SQ" and ns.ProgressGlue and ns.ProgressGlue.OnSummaryRequest then ns.ProgressGlue.OnSummaryRequest(payload, sender)
  elseif tag == "SR" and ns.ProgressGlue and ns.ProgressGlue.OnSummary then ns.ProgressGlue.OnSummary(payload, sender)
  elseif tag == "CL" and ns.HallGlue and ns.HallGlue.OnClaim then ns.HallGlue.OnClaim(payload, sender, sentAt) end
end

-- the CHAT_MSG_ADDON entry point: never raises (a broken peer cannot spam Lua errors on the whole guild)
-- sentAt = server time stamped by the sender when the message left its queue (nil from older clients)
function Sync.OnMessage(tag, payload, sender, _, sentAt)
  if type(sender) == "string" then heard[(ns.fullName and ns.fullName(sender)) or sender] = GetTime and GetTime() or 0 end
  local ok, err = pcall(dispatch, tag, payload, sender, sentAt)
  if not ok then
    Sync.stats.errors = Sync.stats.errors + 1
    if ns.debug then ns.debug("sync error: " .. tostring(err)) end
  end
end

-- a GM/officer (by the roster) online that sent us an addon message in the last 15 min
Sync.TRUSTED_FRESH = 900
function Sync.TrustedOnline()
  local P = ns.Permissions
  if not (P and ns.roster) then return false end
  local now, settings = GetTime and GetTime() or 0, M.settingsOf(ns.state)
  for name, t in pairs(heard) do
    if now - t <= Sync.TRUSTED_FRESH and name ~= (ns.me and ns.me()) then
      local r = ns.roster(name)
      if r and r.online and P.isOfficer(ns.roster, name, settings) then return true end
    end
  end
  return false
end

function Sync.PendingCount() return #pending end
function Sync.QuarantineCount() return 0 end   -- quarantine removed (kept for /gsq diag)
-- seconds since `name` last sent us an addon message (nil = never heard this session)
function Sync.HeardAgo(name)
  local t = heard[name]
  if not t then return nil end
  return (GetTime and GetTime() or 0) - t
end

return Sync
