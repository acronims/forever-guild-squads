-- Guild Squads (MIT) - Sync.lua
-- Replication over the GUILD addon channel.
--   "D" = records (deltas / replies), "H" = hello with bucketed state hashes.
-- Records are validated locally (Core/Model.lua) before being stored.
--   * every record is shape-checked before use and applied under pcall; broken ones are counted and dropped
--   * relay trust: live = sender is the author; relayed = sender is GM/officer. Nothing else.
--     There is no "announced hash" path (24-bit hashes are forgeable). Records >300 s
--     in the future are refused; refused records are never stored, so they are never relayed.
--     Without a GM/officer online, each client only gets what the authors themselves publish (live or in their
--     hello replies, which only carry their own records).
--   * hello replies page with a per-requester cursor and the requester re-hellos while it keeps learning
local _, ns = ...
ns = ns or {}

local Sync = {}
ns.Sync = Sync
local M, Comm = ns.Model, ns.Comm

local KINDS = { "settings", "squad", "profile", "reject", "boss", "annul" }
-- kinds registered by pure modules (roster, rsvp, attendance) travel the same way. A peer only gets them
-- in hello replies when its hello carries hashes for that kind (older versions would refuse them anyway).
local CORE_KIND = {}
for _, k in ipairs(KINDS) do CORE_KIND[k] = true end
for _, k in ipairs(M.EXT_ORDER or {}) do KINDS[#KINDS + 1] = k end
local MAX_REPLY = 60          -- records per hello reply
local MAX_PENDING = 5000      -- records waiting for the guild roster (own disk + early network)
local MAX_ROUNDS = 6          -- extra hellos while a fresh client keeps learning
local pending = {}            -- { rec, sender } waiting for the guild roster
local seenAfter = {}          -- id -> version string seen on the wire (reply suppression)
local corrections = {}        -- id -> true when a correction is already scheduled
local cursor = {}             -- requester -> last reply key sent (pagination)
local heard = {}              -- sender -> GetTime() of the last addon message (addon detection)
Sync.stats = { bad = 0, relayRefused = 0, future = 0, errors = 0, quarantined = 0 }

local function vkey(r) return tostring(r.ts) .. "." .. tostring(r.sq) .. "." .. tostring(r.a) end
local function serverNow()
  if ns.serverTime then return ns.serverTime() end
  if GetServerTime then return GetServerTime() end
  return nil
end

local function ctxFor(sender)
  return { roster = ns.roster, sender = sender, now = serverNow() }
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
  elseif not ok and why == "future" then
    Sync.stats.future = Sync.stats.future + 1
    -- a record from a peer whose clock is ahead of ours is applied again once it is no
    -- longer in the future (< 30 min ahead); before, it stayed refused until the next hello, which may never come
    local now = serverNow()
    local wait = now and type(rec.ts) == "number" and rec.ts - now - M.MAX_FUTURE + 2
    if wait and wait > 0 and wait <= 1800 and ns.After then ns.After(wait, function() Sync.Apply(rec, sender) end) end
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
  for _, k in ipairs(KINDS) do h[k] = M.bucketHashes(ns.state, k) end
  local msg = { h = h }
  -- per-author MetricEvent counts, so authors can re-send their own events to whoever lacks them
  if ns.ProgressGlue and ns.ProgressGlue.Enabled() then
    msg.ec = ns.ProgressGlue.HelloCounts()
    if ns.ProgressGlue.HelloSummaries then msg.ws = ns.ProgressGlue.HelloSummaries() end
  end
  -- bucket hashes of the race observations / closed races (peers answer with paginated diffs)
  if ns.HallGlue and ns.HallGlue.Enabled() then msg.rh = ns.HallGlue.HelloHashes() end
  Comm.Send("H", msg)
  -- keep asking (with growing delay) while replies keep teaching us records
  if ns.After then
    ns.After(30 + 15 * round, function()
      if learned >= 10 and round < MAX_ROUNDS then round = round + 1; Sync.Hello(true) end
    end)
  end
end

-- records that differ from the requester, starting after the last one we sent it (cursor), at most MAX_REPLY.
-- a non-officer only replies with its own records (anything else would be refused as a relay).
function Sync.ReplyFor(payload, sender, startedAt, onlyAuthor)
  local all = {}
  for ki, k in ipairs(KINDS) do
    local list = (CORE_KIND[k] or payload.h[k] ~= nil) and M.diffRecords(ns.state, k, payload.h[k]) or {}
    for _, r in ipairs(list) do
      local seen = seenAfter[r.id]
      if onlyAuthor and r.a ~= onlyAuthor then
        -- skip: not ours to relay
      elseif queued[r.id] == vkey(r) then
        -- this version is already waiting in our send queue
      elseif not (seen and startedAt and seen.t >= startedAt and seen.v == vkey(r)) then
        all[#all + 1] = { key = ("%03d|%s"):format(ki, r.id), r = r }   -- numeric kind order
      end
    end
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
  ns.After(2 + math.random() * 6, function()
    local out = Sync.ReplyFor(payload, from, startedAt, onlyMe)
    if ns.debug then ns.debug(("hello from %s: replying %d records"):format(tostring(sender), #out)) end
    sendRecords(out)
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
      seenAfter[rec.id] = { t = t, v = vkey(rec) }
      local ok, why = Sync.Apply(rec, from)
      if ok then learned = learned + 1; syncUntil = math.max(syncUntil, t + 60) end
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

function Sync.PendingCount() return #pending end
function Sync.QuarantineCount() return 0 end   -- quarantine removed (kept for /gsq diag)
-- seconds since `name` last sent us an addon message (nil = never heard this session)
function Sync.HeardAgo(name)
  local t = heard[name]
  if not t then return nil end
  return (GetTime and GetTime() or 0) - t
end

return Sync
