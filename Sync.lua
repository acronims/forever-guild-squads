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
local MAX_REPLY = 60          -- records per hello reply (1.0 / 1.1 requesters)
Sync.MAX_SAMPLE = 30          -- v1.2: records per reply to a 1.2 requester (random sample of 2 of 8 cubes)
Sync.CUBES, Sync.CUBES_PICK = 8, 2
-- v1.2 AC3 arreglo 2: a requester catching up (cu = 1 in its hello) gets up to MAX_SAMPLE_CATCHUP records of its
-- 2 cubes, at most once per CATCHUP_COOLDOWN s per requester (a modified client flooding cu hellos gets MAX_SAMPLE).
-- sec r3 M2 (final form): plus at most CATCHUP_BUDGET of them per requester per CATCHUP_WINDOW s, the rounds an
-- honest newcomer asks (MAX_CATCHUP_ROUNDS); a modified client re-sending cu hellos all hour gets the normal sample
-- once it is spent (a 10 min cooldown starved the honest newcomer in S8 r4: 541/600 visible at 600 s)
Sync.MAX_SAMPLE_CATCHUP = 120
Sync.CATCHUP_COOLDOWN = 25
Sync.CATCHUP_BUDGET = 20
Sync.CATCHUP_WINDOW = 3600
-- v1.2 AC3 tail (S8 exp-miss, 826a57a: 596/600 visible from 360 s): a catching-up requester whose diff here is at
-- most CATCHUP_ALL records gets all of it, not 2 of 8 cubes (only newcomers send cu; members keep the sample, AC5)
Sync.CATCHUP_ALL = 30
local bigReply = {}           -- requester -> { last = GetTime() of the last catch-up reply, w = window start, n = count }
Sync.SAMPLE_MIN_ONLINE = 8    -- v1.2 (AC1): the sample only with more peers than this (p < 1); else MAX_REPLY + cursor
                              -- 1.2.1: peers = ns.peerCount() (1.2 clients online), never the guild members online
-- v1.2: fine bucket hashes (h2) of the big kinds in a 1.2 hello; a 1.2 replier diffs on them, so it does not resend
-- a whole coarse bucket (~1/16 of the guild) the requester already holds (S8: members relay P2P now)
Sync.FINE_NB = 64
Sync.FINE_KINDS = { profile = true, squad = true }
local MAX_PENDING = 5000      -- records waiting for the guild roster (own disk + early network)
local MAX_ROUNDS = 6          -- extra hellos while a fresh client keeps learning
-- v1.2 AC3 arreglo 1: only a client catching up (its first hello round taught >= CATCHUP_MIN records, e.g. a
-- newcomer) asks every 30 s while it learns anything or holds pending copies, up to MAX_CATCHUP_ROUNDS (10 min);
-- the members keep the 1.1 rounds (their pending rounds were 1960 parts of hellos in AC5)
Sync.CATCHUP_MIN = 50
local MAX_CATCHUP_ROUNDS = 20
local catchup = false
local MAX_FORWARD = 20        -- unverified versions (u = 1) whispered per hello reply
local pending = {}            -- { rec, sender } waiting for the guild roster
local seenAfter = {}          -- id -> version string seen on the wire (reply suppression)
local corrections = {}        -- id -> true when a correction is already scheduled
local cursor = {}             -- requester -> last reply key sent (pagination)
local heard = {}              -- sender -> GetTime() of the last addon message (addon detection)
-- 1.2.1 (BRO's guild, 9-nov: 317 members, ~60 online, 2-3 on 1.2; diag sample=0, sig verified=0): who answers a hello
-- is a client of this protocol, not any member online. ns.peerCount() = me + the distinct senders of PROTO 2 messages
-- (Comm hands only those to Sync.OnMessage) heard in the last PEER_FRESH s that the roster still shows online. It
-- drives the reply draw (8 / n), the cube sample (n > SAMPLE_MIN_ONLINE) and the Hall pages (4 / n); 1.2.0 used
-- ns.onlineCount(), the guild members online, so 3 peers among 60 online answered 13 % of the hellos with 2 of 8
-- cubes. PEER_FRESH covers one anti-entropy period (a quiet peer hellos every 600-1200 s); a peer heard less
-- recently only makes the count lower, i.e. more replies, never fewer.
Sync.PEER_FRESH = 1200
function Sync.PeerCount()
  local t, me, n = GetTime and GetTime() or 0, ns.me and ns.me(), 1
  for name, at in pairs(heard) do
    if name ~= me and t >= at and t - at <= Sync.PEER_FRESH then
      local r = ns.roster and ns.roster(name)
      if r and r.online then n = n + 1 end
    end
  end
  return n
end
ns.peerCount = Sync.PeerCount
-- /gsq diag: senders heard this session and how many of them the roster does not know (a realm-name mismatch
-- between CHAT_MSG_ADDON and the roster would show here), with the first such name
function Sync.PeerDiag()
  local n, unknown, sample = 0, 0, nil
  for name in pairs(heard) do
    n = n + 1
    if not (ns.roster and ns.roster(name)) then unknown = unknown + 1; sample = sample or name end
  end
  return Sync.PeerCount(), n, unknown, sample
end
Sync.stats = { hellos = 0, replied = 0, bad = 0, relayRefused = 0, future = 0, errors = 0, quarantined = 0, pending = 0, mine = 0,
  sampled = 0, suppressed = 0 }  -- v1.2 point 8: records sent in sampled replies to 1.2 hellos / not sent (heard since the hello)

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

-- v1.2 annex F: defined below with the manifests
local envelope
local ownDirty = true
-- local write: apply then broadcast
function Sync.Publish(rec)
  local ok, why = M.apply(ns.state, rec, { roster = ns.roster })
  if not ok then return false, why end
  ownDirty = true
  -- signing costs one ed25519 sign + a hash per own record: not on every click. Peers that hear the record from us
  -- need no signature; the manifest (for relays) follows MAN_DEBOUNCE s later, once for a burst of edits
  local ks, kr = Sync.KeysFor({ rec }, nil)
  Comm.Send("D", { r = { rec }, ks = ks, kr = kr }, nil, nil, nil, true)
  Sync.QueueOwnManifest()   -- own fresh records skip the reply backlog
  if ns.UI and ns.UI.Dirty then ns.UI.Dirty() end
  return true
end

-- a record version already waiting in our send queue is not queued again for the next
-- hello (otherwise 30 logins would queue 30 copies of the same records: ~470 messages, 8 minutes of backlog per officer)
local queued = {}             -- id -> version string waiting in the send queue
-- v1.2 annex F: the strong keys of the authors of a batch (`ks`, hex), our own included. Weak keys are never
-- relayed (a relayer vouches only for keys heard in person); one copy per author and destination every KEY_EVERY s.
Sync.KEY_EVERY = 600
local keySent = {}
function Sync.KeysFor(batch, to)
  local T, db = ns.Trust, ns.trustDB
  if not (T and db) then return nil end
  local now, me, ks, kr = GetTime and GetTime() or 0, ns.me and ns.me(), nil, nil
  for _, r in ipairs(batch) do
    local a = r.a
    local pk, rs
    if a == me then
      pk = ns.myPk and ns.myPk()
      local o = type(db.ownRot) == "table" and db.ownRot[me]
      if pk and type(o) == "table" and o.pk == T.hex(pk) then rs = o.s end
    else
      local k, s = T.keyOf(db, a)
      if s == "strong" or s == "cert" then pk = k; rs = T.rotSig and T.rotSig(db, a) end
    end
    local tag = (to or "*") .. "|" .. tostring(a)
    if pk and not (ks and ks[a]) and (not keySent[tag] or now - keySent[tag] >= Sync.KEY_EVERY) then
      keySent[tag] = now
      ks = ks or {}
      ks[a] = T.hex(pk)
      if rs then kr = kr or {}; kr[a] = rs end    -- AF5: the old key's signature over this one
    end
  end
  return ks, kr
end
-- AF5: /gsq trust newkey signs the new key with the old one; our relayed records carry it (kr) so whoever holds the
-- old key strong accepts the new one without meeting us
function Sync.OwnRotation(oldSk, oldPk, newPk)
  local T, db, me = ns.Trust, ns.trustDB, ns.me and ns.me()
  if not (T and db and me and oldSk and oldPk and newPk) then return end
  local okS, sig = pcall(T.signRotation, oldSk, oldPk, me, newPk)
  if not okS or not sig then return end
  db.ownRot = type(db.ownRot) == "table" and db.ownRot or {}
  db.ownRot[me] = { pk = T.hex(newPk), s = T.hex(sig) }
end
-- QA D4 / sec F8: a rotation costs one ed25519 verify; never inside the message handler (a D with 20 fake `kr`
-- froze every receiver): queued (ROT_Q_MAX, deduped) and verified by Sync.SigStep, the one-verify-per-frame step
-- that pauses in combat and encounters (QA r2 N3: it used to run on its own After(0) timer, so a frame could hold
-- two verifies and encounters did not pause it). A rotation that failed is remembered (ROT_BAD_MAX tags).
-- sec r2 R4: at most ROT_PER_SENDER queued rotations per sender, so one member cannot fill the queue
Sync.ROT_Q_MAX, Sync.ROT_BAD_MAX, Sync.ROT_PER_SENDER = 20, 200, 4
local rotQ, rotQueued, rotBad, rotBadN, rotBy = {}, {}, {}, 0, {}
function Sync.RotPending() return #rotQ end
local function rotStep()
  if #rotQ == 0 then return nil end
  local e = table.remove(rotQ, 1)
  rotQueued[e.tag] = nil
  local fk = e.from or "?"
  rotBy[fk] = (rotBy[fk] or 1) - 1
  if rotBy[fk] <= 0 then rotBy[fk] = nil end
  local T, db = ns.Trust, ns.trustDB
  if not (T and db) then return nil end      -- QA r3 Q3-3: the guild was unloaded
  local cur, cs = T.keyOf(db, e.a)
  -- still the same strong key we held when it was queued (a hello in person may have changed it meanwhile)
  if cur and cs == "strong" and cur ~= e.pk then
    local now = (ns.serverTime and ns.serverTime()) or (GetServerTime and GetServerTime()) or 0
    if T.rotate(db, e.a, e.pk, e.sig, now) then
      if ns.Sig and ns.sigDB then ns.Sig.dropKey(ns.sigDB, e.a, cur) end
      if ns.OnKeyReplaced then ns.OnKeyReplaced(e.a, cur) end
    else
      if rotBadN >= Sync.ROT_BAD_MAX then rotBad, rotBadN = {}, 0 end
      rotBad[e.tag], rotBadN = true, rotBadN + 1
    end
  end
  return e.a
end
-- QA r3 Q3-3: the queue belongs to the guild that heard it (GuildSquads unloadGuild runs ns.guildUnloadHooks)
function Sync.ResetRotations() rotQ, rotQueued, rotBy = {}, {}, {} end
ns.guildUnloadHooks = ns.guildUnloadHooks or {}
table.insert(ns.guildUnloadHooks, Sync.ResetRotations)
function Sync.QueueRotation(a, pk, sig, from)
  local tag = a .. "|" .. pk .. "|" .. sig
  if rotBad[tag] or rotQueued[tag] then return end
  local fk = from or "?"
  if #rotQ >= Sync.ROT_Q_MAX or (rotBy[fk] or 0) >= Sync.ROT_PER_SENDER then
    Sync.stats.rotDropped = (Sync.stats.rotDropped or 0) + 1; return
  end
  rotQ[#rotQ + 1] = { a = a, pk = pk, sig = sig, tag = tag, from = from }
  rotQueued[tag] = true
  rotBy[fk] = (rotBy[fk] or 0) + 1
end
-- `ks` of a D message: only for authors of records in it and roster members; the sender itself = in person
local function learnKeys(payload, from)
  local T, db = ns.Trust, ns.trustDB
  if not (T and db and type(payload.ks) == "table") then return end
  local authors, now = {}, (ns.serverTime and ns.serverTime()) or (GetServerTime and GetServerTime()) or 0
  for i = 1, math.min(#payload.r, 20) do local r = payload.r[i]; if type(r) == "table" then authors[r.a] = true end end
  for a in pairs(authors) do
    local h = payload.ks[a]
    if type(a) == "string" and type(h) == "string" and a ~= (ns.me and ns.me()) and (a == from or (ns.roster and ns.roster(a))) then
      local pk = T.unhex(h)
      if pk then
        local cur, cs = T.keyOf(db, a)
        if a == from then Sync.OnOwnerKey(a, T.hearOwner(db, a, pk, now))
        elseif cur and cs == "strong" and cur ~= pk then
          -- AF5: a strong key changes only with the old key's signature over the new one
          local kr = type(payload.kr) == "table" and payload.kr[a]
          local sig = type(kr) == "string" and #kr == 128 and T.unhex(kr)
          if not sig then T.unsignedChange(db, a, from)
          else Sync.QueueRotation(a, pk, sig, from) end
        elseif T.hearRelayed(db, a, pk, from, now) == "pending" then Sync.CertEval(a) end
      end
    end
  end
end
-- what hearOwner said; "replaced" drops what the old weak key signed (manifests, annex F); a manifest verified with
-- a weak key that is now the owner's strong key becomes strong
-- sec F4: the key heard in person always wins (BRO 8-nov 03:09), but a name flipping its key every few seconds must
-- not make every client re-sign and broadcast its certificate each time: one broadcast per name per FLIP_MIN s for
-- "replaced" (the certificate still lists the latest key at our next broadcast or whispered reply)
Sync.FLIP_MIN = 600
local flipAt = {}
function Sync.OnOwnerKey(name, res, old)
  local G, db = ns.Sig, ns.sigDB
  if res == "new" or res == "replaced" then
    Sync.DropOwnCertCache()
    local t = serverNow() or 0
    local last = res == "replaced" and flipAt[name]
    if last and t >= last and t - last < Sync.FLIP_MIN then
      Sync.stats.flipCapped = (Sync.stats.flipCapped or 0) + 1
    else
      if res == "replaced" then flipAt[name] = t end
      Sync.QueueOwnCert()
    end
  end
  if res == "replaced" then
    if G and db then G.dropKey(db, name, old) end
    if ns.OnKeyReplaced then ns.OnKeyReplaced(name, old) end
  elseif G and db and ns.Trust and ns.trustDB then
    local pk, s = ns.Trust.keyOf(ns.trustDB, name)
    if pk and s == "strong" then G.promote(db, name, pk) end
  end
  -- S8 (4 / 16 members): a manifest relayed before its author's key reached us (the relayer's `ks` copy went out
  -- earlier, KEY_EVERY per destination) waits parked; the key heard in person makes it verifiable now, not only a
  -- certified one (annex G). A parked fake fails its verify like any other.
  if G and G.unpark and (res == "new" or res == "replaced" or res == "same") then G.unpark(name) end
end

-- v1.2 annex F, manifests. Our own: rebuilt when one of our records changed (dirty), re-signed with n + 1 only if
-- the hashes differ; n = max(n + 1, server time) so a lost SavedVariables does not leave us below what others hold.
-- Kept in the guild's sig db (sigDB.own[name]).
function Sync.MarkOwnDirty() ownDirty = true end
-- a new own key (/gsq trust newkey, BRO 8-nov 03:09): re-sign with it even if no record changed; n keeps growing
local forceSign = false
function Sync.ResignOwn() forceSign = true; ownDirty = true end
-- fix/perf (runtime review A2): the hash of each own record, cached per kid with the version it was computed for (the
-- record table and its ts / sq / a): an edit writes a new version, so it re-hashes only that record. Rebuilt on each
-- pass with only the current records (no growth).
local ownHash = {}
function Sync.OwnManifest()
  local G, db = ns.Sig, ns.sigDB
  local me = ns.me and ns.me()
  if not (G and db and me and ns.mySk and ns.myPk) then return nil end
  db.own = type(db.own) == "table" and db.own or {}
  local cur = db.own[me]
  if cur and not ownDirty then return cur end
  local sk, pk = ns.mySk(), ns.myPk()
  if not (sk and pk) then return cur end
  local mine = {}
  for _, r in ipairs(M.allRecords(ns.state)) do if r.a == me then mine[#mine + 1] = r end end
  if #mine == 0 then ownDirty = false; return cur end
  mine = G.pick(me, mine)   -- sec F7: the MAN_CAP most recent (the same set G.build signs)
  local h, hc = {}, {}
  for _, r in ipairs(mine) do
    local kid = r.k .. ":" .. r.id
    local e = ownHash[kid]
    if not (e and e.r == r and e.ts == r.ts and e.sq == r.sq and e.a == r.a) then
      e = { r = r, ts = r.ts, sq = r.sq, a = r.a, h = G.recHash(r) }
    end
    hc[kid], h[kid] = e, e.h
  end
  ownHash = hc
  local same = not forceSign and cur and type(cur.h) == "table"
  if same then
    for kid, v in pairs(h) do if cur.h[kid] ~= v then same = false; break end end
    if same then for kid in pairs(cur.h) do if h[kid] == nil then same = false; break end end end
  end
  ownDirty = false
  if same then return cur end
  local n = math.max((cur and tonumber(cur.n) or 0) + 1, math.floor(serverNow() or 0))
  local okS, m = pcall(G.build, me, n, mine, sk, pk, h)
  if not okS or not m then return cur end
  forceSign = false
  db.own[me] = m
  return m
end
-- fix/perf (runtime review M2): what signs (a sign ~10 ms plus a hash per entry) waits for the end of combat and
-- encounters, like the verifies (GuildSquads.lua sigFrame): re-checked every SIGN_RETRY s
Sync.SIGN_RETRY = 5
function Sync.SignBusy()
  if InCombatLockdown and InCombatLockdown() then return true end
  -- ns.encounterFn() gives the API function (C_InstanceEncounter in 16001), like the verify gate in GuildSquads.lua
  local enc = ns.encounterFn and ns.encounterFn()
  if type(enc) ~= "function" then return false end
  local okE, v = pcall(enc)
  return (okE and v) and true or false
end
local function whenIdle(fn)
  if Sync.SignBusy() and ns.After then return ns.After(Sync.SIGN_RETRY, function() whenIdle(fn) end) end
  fn()
end
Sync.WhenIdle = whenIdle
Sync.MAN_DEBOUNCE = 5
local manSent = {}
local manQueued = false
function Sync.QueueOwnManifest()
  if manQueued or not ns.After then return end
  manQueued = true
  ns.After(Sync.MAN_DEBOUNCE, function() whenIdle(function()
    manQueued = false
    local m, me = Sync.OwnManifest(), ns.me and ns.me()
    if not (m and me) then return end
    manSent["*|" .. me] = { n = m.n, t = GetTime and GetTime() or 0 }
    local w = { a = m.a, n = m.n, h = m.h, s = m.s }
    Comm.Send("D", { r = {}, m = { w } }, nil, nil, function() Sync.NoteManHeard(w) end)
  end) end)
end
-- `m` of a D message: the manifests of the authors of its records (ours or the last verified one we hold), one per
-- author and destination every MAN_EVERY s or when its n changes
Sync.MAN_EVERY = 600
function Sync.ManifestsFor(batch, to)
  local G, db = ns.Sig, ns.sigDB
  if not (G and db) then return nil end
  local now, me, out, seen = GetTime and GetTime() or 0, ns.me and ns.me(), nil, {}
  for _, r in ipairs(batch) do
    local a = r.a
    if type(a) == "string" and not seen[a] then
      seen[a] = true
      local m
      if a == me then m = Sync.OwnManifest() else m = G.manifestOf(db, a) end
      local tag = (to or "*") .. "|" .. a
      local last = manSent[tag]
      if m and (not last or last.n ~= m.n or now - last.t >= Sync.MAN_EVERY) then
        manSent[tag] = { n = m.n, t = now }
        out = out or {}
        out[#out + 1] = { a = m.a, n = m.n, h = m.h, s = m.s }
      end
    end
  end
  return out
end
-- AF4 (s8t2: the `m` of hello replies were ~4600 of 9642 parts): a GUILD hello reply sends each manifest apart,
-- with a skip check run at the head of the send queue: dropped if the same manifest (author, n, signature) was heard
-- on GUILD (sent by us or by another replier) after the requester's hello, since he got it then too.
local manHeard, helloAt = {}, {}  -- author -> { n, s, t } heard on GUILD; requester -> GetTime of his last hello
function Sync.HelloHeard(from, t) helloAt[from] = t or (GetTime and GetTime() or 0) end
local function noteManHeard(m)
  if type(m) == "table" and type(m.a) == "string" and type(m.s) == "string" then
    manHeard[m.a] = { n = m.n, s = m.s, m = m, t = GetTime and GetTime() or 0 }
  end
end
Sync.NoteManHeard = noteManHeard
function Sync.ManHeardSince(m, req)
  local h, t0 = manHeard[m.a], helloAt[req]
  -- sec F6: the same body too (a forged copy can reuse the real signature over another list)
  return (h and t0 and h.n == m.n and h.s == m.s and h.t > t0 and (h.m == m or (ns.Sig and ns.Sig.sameBody(h.m, m)))) and true or false
end
local function sendManifestsApart(list, req)
  for _, m in ipairs(list) do
    Comm.Send("D", { r = {}, m = { m } }, nil, nil, function() noteManHeard(m) end, nil,
      function() return Sync.ManHeardSince(m, req) end)
  end
end
-- `m` of a received D: only for authors of records in it (first 20), roster members, not us; queued for 1 verify.
-- A message with no records (a manifest sent apart, AF4) may carry any roster member's manifest.
local function offerManifests(payload, from)
  local G, db, T = ns.Sig, ns.sigDB, ns.Trust
  if not (G and db and T and type(payload.m) == "table") then return end
  local authors, me = {}, ns.me and ns.me()
  for i = 1, math.min(#payload.r, 20) do local r = payload.r[i]; if type(r) == "table" and type(r.a) == "string" then authors[r.a] = true end end
  local keyOf = function(name) if ns.trustDB then return T.keyOf(ns.trustDB, name) end end
  for i = 1, math.min(#payload.m, 20) do
    local m = payload.m[i]
    if type(m) == "table" and type(m.a) == "string" and (authors[m.a] or m.a == from or #payload.r == 0) and m.a ~= me and (m.a == from or (ns.roster and ns.roster(m.a))) then
      pcall(G.offer, db, m, keyOf, from)
    end
  end
end
-- one verification (call once per frame, never in combat): an accepted manifest re-applies that author's pending copies
local rotTurn = false
function Sync.SigStep()
  if ns.Cert and ns.certDB and ns.Cert.pending() > 0 then return Sync.CertStep() end
  -- rotations and manifests take turns (a flood of fake `kr` cannot starve the manifests, nor the other way)
  rotTurn = not rotTurn
  if #rotQ > 0 and (rotTurn or not (ns.Sig and ns.sigDB and ns.Sig.pending() > 0)) then return rotStep() end
  local G, db = ns.Sig, ns.sigDB
  if not (G and db) or G.pending() == 0 then return nil end
  local okS, who = pcall(G.step, db, function(author)
    if X and X.retry then
      local n = X.retry(ns.state, author, ctxFor(nil))
      if n > 0 and ns.UI and ns.UI.Dirty then pcall(ns.UI.Dirty) end
    end
  end)
  return okS and who or nil
end
-- v1.2 annex G: certificates. Ours lists the keys we heard in person (30 days); it goes in our hello and, when it
-- changes (someone new heard in person), once by GUILD after CERT_DEBOUNCE s. Only the issuer's own certificate is
-- taken (c.i == sender): an issuer counts only if we heard him in person, so relaying certificates adds nothing.
Sync.CERT_DEBOUNCE = 30
-- a certificate that changed reached only who was online then (S16b): when we answer a 1.2 hello (we are one of
-- the <=8 repliers) we also WHISPER it to the requester (not by GUILD: s8t6/s8t7, the GUILD copy re-verified keys
-- and unparked records on every client and nearly doubled the S8 cable), at most once per requester per
-- CERT_REHELLO s and at most CERT_REHELLO_MAX per window (a flood of hellos from many names costs <= 10 D per minute);
-- an empty certificate is not re-sent, nor while our own GUILD broadcast of a change is pending.
Sync.CERT_REHELLO = 60
Sync.CERT_REHELLO_MAX = 10
local certQueued, certSentN, certRehelloAt, certRehelloTo, certRehelloN = false, nil, nil, {}, 0
-- sec F5: C.own hashes every key heard in person; a hello flood must not run it per hello. Cached OWN_CERT_TTL s,
-- dropped when a key heard in person changes (Sync.OnOwnerKey -> QueueOwnCert) or our own key changes
Sync.OWN_CERT_TTL = 10
local ownCache
function Sync.OwnCert()
  local C, db, T = ns.Cert, ns.certDB, ns.Trust
  local me = ns.me and ns.me()
  if not (C and db and T and ns.trustDB and me and ns.mySk and ns.myPk) then return nil end
  local sk, pk = ns.mySk(), ns.myPk()
  if not (sk and pk) then return nil end
  local t = serverNow() or 0
  if ownCache and ownCache.pk == pk and ownCache.me == me and ownCache.db == db and t >= ownCache.t
    and t - ownCache.t < Sync.OWN_CERT_TTL then return ownCache.c end
  db.own = type(db.own) == "table" and db.own or {}
  db.own[me] = type(db.own[me]) == "table" and db.own[me] or {}
  local okC, c = pcall(C.own, db.own[me], ns.trustDB, me, sk, pk, math.floor(t))
  c = okC and c or nil
  ownCache = { pk = pk, me = me, db = db, t = t, c = c }
  return c
end
function Sync.DropOwnCertCache() ownCache = nil end
function Sync.QueueOwnCert()
  ownCache = nil
  if certQueued or not ns.After or not ns.certDB then return end
  certQueued = true
  ns.After(Sync.CERT_DEBOUNCE, function() whenIdle(function()
    certQueued = false
    local c = Sync.OwnCert()
    if not c or c.n == certSentN then return end
    certSentN = c.n
    Comm.Send("D", { r = {}, c = { i = c.i, n = c.n, e = c.e, s = c.s } })
  end) end)
end
-- fix/perf (runtime review A3): the hello carries only a reference to our certificate (n and the first 12 chars of
-- its signature). The whole certificate (~25 B per key heard in person) made a 400-key hello 64 parts, and Comm.Send
-- drops those. Who lacks it asks (Sync.OnCertRef -> a whispered D with ca = 1); we answer a burst of asks with one
-- GUILD send (Sync.CertAsked); a changed certificate still goes by GUILD (QueueOwnCert).
function Sync.HelloCertRef()
  local c = Sync.OwnCert()
  -- an empty certificate is never sent (RehelloCert, CertAsked): no reference either, nobody would ask for nothing
  if c and type(c.s) == "string" and #c.e > 0 then return { n = c.n, h = c.s:sub(1, 12) } end
end
Sync.CERT_ASK_MIN = 60         -- one ask per issuer per minute; one GUILD answer per certificate n per minute
Sync.CERT_ASK_DEBOUNCE = 3     -- the asks of a login burst get one GUILD send
local certAskAt, certAskN, certAskQ, certAnsweredAt, certAnsweredN = {}, 0, false, nil, nil
function Sync.OnCertRef(cr, from)
  local C, db, T = ns.Cert, ns.certDB, ns.Trust
  if not (C and db and T and ns.trustDB and type(cr) == "table" and type(cr.n) == "number" and type(from) == "string") then return end
  if from == (ns.me and ns.me()) or not T.inPerson(ns.trustDB, from) or C.knows(db, from, cr.n) then return end
  local t = serverNow() or 0
  local last = certAskAt[from]
  if last and t >= last and t - last < Sync.CERT_ASK_MIN then return end
  if certAskN >= 2000 then certAskAt, certAskN = {}, 0 end
  certAskAt[from], certAskN = t, certAskN + 1
  local function ask() if not C.knows(db, from, cr.n) then Comm.Send("D", { r = {}, ca = 1 }, "WHISPER", from) end end
  if ns.After then ns.After(1 + math.random() * 3, ask) else ask() end
end
function Sync.CertAsked(from)
  if not ns.certDB or type(from) ~= "string" or from == (ns.me and ns.me()) then return end
  if certQueued or certAskQ then return end      -- a GUILD send of it is already on its way
  local c = Sync.OwnCert()
  if not c or #c.e == 0 then return end
  local t = serverNow() or 0
  if certAnsweredN == c.n and certAnsweredAt and t >= certAnsweredAt and t - certAnsweredAt < Sync.CERT_ASK_MIN then
    return Sync.RehelloCert(from)                -- answered by GUILD a moment ago: a whisper (rate-limited)
  end
  certAskQ = true
  local function send()
    certAskQ = false
    local c2 = Sync.OwnCert()
    if not c2 or #c2.e == 0 then return end
    certAnsweredAt, certAnsweredN, certSentN = serverNow() or 0, c2.n, c2.n
    Comm.Send("D", { r = {}, c = { i = c2.i, n = c2.n, e = c2.e, s = c2.s } })
  end
  if ns.After then ns.After(Sync.CERT_ASK_DEBOUNCE, function() whenIdle(send) end) else send() end
end
-- a 1.2 hello lists the certificates the requester holds (`cn`): 8-char tokens = 24-bit hash of the issuer + n mod
-- 2^24 (base64), newest first, at most CN_MAX. A replier re-sends its own only if its token is not there (missing or
-- another n). A collision only skips one re-send (the next hello of a later certificate fixes it); a lying cn only
-- hurts the liar. Malformed / oversized cn = empty.
Sync.CN_MAX = 32
local B64C = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b24(v)
  v = math.floor(v) % 16777216
  local o = {}
  for j = 3, 0, -1 do local d = math.floor(v / 64 ^ j) % 64; o[#o + 1] = B64C:sub(d + 1, d + 1) end
  return table.concat(o)
end
function Sync.CertTok(issuer, n)
  local h = 5381
  issuer = tostring(issuer)
  for i = 1, #issuer do h = (h * 33 + issuer:byte(i)) % 16777216 end
  return b24(h) .. b24(tonumber(n) or 0)
end
function Sync.HelloCn()
  local db = ns.certDB
  if not (db and type(db.crt) == "table") then return nil end
  local l = {}
  for i, c in pairs(db.crt) do if type(c) == "table" and type(c.n) == "number" then l[#l + 1] = { i, c.n } end end
  if #l == 0 then return nil end
  table.sort(l, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return tostring(a[1]) < tostring(b[1]) end)
  local o = {}
  for k = 1, math.min(#l, Sync.CN_MAX) do o[k] = Sync.CertTok(l[k][1], l[k][2]) end
  return table.concat(o)
end
function Sync.CertKnownBy(cn)
  if type(cn) ~= "string" or #cn > Sync.CN_MAX * 8 or #cn % 8 ~= 0 then return false end
  local c = Sync.OwnCert()
  if not c then return true end           -- nothing to re-send anyway
  local t = Sync.CertTok(c.i, c.n)
  for k = 1, #cn, 8 do if cn:sub(k, k + 7) == t then return true end end
  return false
end
function Sync.RehelloCert(to)
  if not ns.certDB or type(to) ~= "string" then return end
  local now = serverNow() or 0
  if not certRehelloAt or now - certRehelloAt >= Sync.CERT_REHELLO then certRehelloAt, certRehelloTo, certRehelloN = now, {}, 0 end
  if certRehelloTo[to] or certRehelloN >= Sync.CERT_REHELLO_MAX then return end
  -- our GUILD broadcast of a changed certificate is pending: the requester is online and gets that one (s8t9: in a
  -- login burst every hello heard in person changes the certificate, and whispering each version doubled the cable)
  if certQueued then return end
  local c = Sync.OwnCert()
  if not c or #c.e == 0 then return end
  certRehelloTo[to], certRehelloN = true, certRehelloN + 1
  Comm.Send("D", { r = {}, c = { i = c.i, n = c.n, e = c.e, s = c.s } }, "WHISPER", to)
end
function Sync.OfferCert(c, from)
  local C, db = ns.Cert, ns.certDB
  if not (C and db and type(c) == "table" and c.i == from and from ~= (ns.me and ns.me())) then return end
  pcall(C.offer, db, c)
end
-- a key dropped by the certificates (disputed, or certified to another key): forget what it signed
local function certDrop(name, old)
  if ns.Sig and ns.sigDB then ns.Sig.dropKey(ns.sigDB, name, old) end
  if ns.OnKeyReplaced then ns.OnKeyReplaced(name, old) end
end
local function certOk(name) if ns.Sig then ns.Sig.unpark(name) end end
function Sync.CertEval(name)
  local C, db = ns.Cert, ns.certDB
  if not (C and db and ns.trustDB) then return end
  local okE, r = pcall(C.eval, db, ns.trustDB, name, math.floor(serverNow() or 0), certDrop)
  if okE and r == "cert" then certOk(name) end
end
function Sync.CertStep()
  local C, db = ns.Cert, ns.certDB
  if not (C and db and ns.trustDB) or C.pending() == 0 then return nil end
  local now = math.floor(serverNow() or 0)
  local okS, who = pcall(C.step, db, ns.trustDB, now)
  if okS and who then pcall(C.evalAll, db, ns.trustDB, now, certDrop, certOk) end
  return okS and who or nil
end

function envelope(batch, to)
  local ks, kr = Sync.KeysFor(batch, to)
  return { r = batch, ks = ks, kr = kr, m = Sync.ManifestsFor(batch, to) }
end

-- `req`: the hello requester a GUILD reply is for. The `ks` / `m` throttle counts per requester: a GUILD copy sent
-- before he logged in never reached him (S16: Mb9 got Mb7's new profile without its manifest and kept it pending)
local function sendRecords(list, to, urgent, req)
  -- group a few records per message; Comm chunks large payloads
  local batch = {}
  local function flush()
    local ids = {}
    for i, r in ipairs(batch) do ids[i] = { r.id, vkey(r) }; queued[r.id] = vkey(r) end
    local function done() for _, x in ipairs(ids) do if queued[x[1]] == x[2] then queued[x[1]] = nil end end end
    local msg = envelope(batch, req or to)
    -- AF4: a GUILD hello reply sends its manifests apart (each one skipped if heard on GUILD after the hello)
    local apart = (req and not to) and msg.m or nil
    if apart then msg.m = nil end
    local guildM = (not to) and msg.m or nil
    local function sent() done(); if guildM then for _, m in ipairs(guildM) do noteManHeard(m) end end end
    if Comm.Send("D", msg, to and "WHISPER" or nil, to, sent, urgent) == false then done() end
    if apart then sendManifestsApart(apart, req) end
    batch = {}
  end
  for _, b in ipairs(Sync.PackRecords(list)) do batch = b; flush() end
end
Sync.SendRecords = sendRecords
-- v1.2 AC5: records go Sync.PACK per D message (the receiver reads at most 20); Comm chunks it in 255-byte parts,
-- so fewer, fuller messages waste fewer half-empty last parts than the old 3 per message
Sync.PACK = 8
function Sync.PackRecords(list)
  local out, b = {}, {}
  for _, r in ipairs(list or {}) do
    b[#b + 1] = r
    if #b >= Sync.PACK then out[#out + 1] = b; b = {} end
  end
  if #b > 0 then out[#out + 1] = b end
  return out
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
    ownDirty = true
    sendRecords(okList)
    if ns.UI and ns.UI.Dirty then pcall(ns.UI.Dirty) end
    if ns.HallGlue and ns.HallGlue.MarkDirty then pcall(ns.HallGlue.MarkDirty) end
  end
  return #okList, refused
end
-- messages (parts) that list would take in the queue = seconds at 1 msg/s
function Sync.EstimateParts(list)
  local parts = 0
  for _, b in ipairs(Sync.PackRecords(list)) do parts = parts + Comm.Parts("D", { r = b }) end
  return parts
end
function Sync.Resend(rec) if rec then sendRecords({ rec }) end end
function Sync.QueuedCount() local n = 0 for _ in pairs(queued) do n = n + 1 end return n end

local round, learned = 0, 0
local syncUntil = 0

-- v1.2 AC3 (BRO 7-nov 19:04): the sync runs in the background; when the client is synced (a hello round with no
-- differences, or SYNCED_QUIET s without new records after the last round) it writes ONE local chat line per
-- session (DEFAULT_CHAT_FRAME, never sent to anyone): L.SYNCED with the records held and the ones pending.
Sync.SYNCED_QUIET = 60
local synced = { done = false, waitFrom = nil, lastNew = 0, checks = 0 }
function Sync.ResetSynced() synced = { done = false, waitFrom = nil, lastNew = 0, checks = 0 } end
function Sync.SyncedDone() return synced.done end
function Sync.SyncedCounts()
  local n = 0
  for _, r in ipairs(M.allRecords(ns.state or {})) do if r.k ~= "presence" then n = n + 1 end end
  local m = (X and X.stats and ns.state) and X.stats(ns.state).pend or 0
  return n, m
end
local function fireSynced()
  if synced.done then return end
  synced.done = true
  local n, m = Sync.SyncedCounts()
  local fmt = (ns.L and ns.L.SYNCED) or "Guild Squads: synced (%d records, %d pending verification)"
  local lines = { fmt:format(n, m) }
  local old = Sync.OldPeersLine()
  if old then lines[2] = old end
  for _, line in ipairs(lines) do Sync.ChatLine(line) end
end
function Sync.ChatLine(line)
  if Sync.chatSink then Sync.chatSink(line); return end
  local f = DEFAULT_CHAT_FRAME
  if f and f.AddMessage then pcall(f.AddMessage, f, line) end
end
-- v1.2 (BRO 7-nov 21:20): members still on 1.0.x / 1.1 cannot sync with us (PROTO 2); say how many, locally,
-- once per session: with the "synced" line, or OLD_PEERS_WAIT s after the first one is heard if that comes later
Sync.OLD_PEERS_WAIT = 30
function Sync.OldPeersLine()
  local old = ns.Comm and ns.Comm.OldPeerCount and ns.Comm.OldPeerCount() or 0
  if old == 0 or synced.oldTold then return nil end
  synced.oldTold = true
  return ((ns.L and ns.L.OLD_PEERS) or "Guild Squads: %d guild members use an old version and cannot sync until they update"):format(old)
end
function Sync.OnOldPeer()
  if synced.oldTold or synced.oldWait or not ns.After then return end
  synced.oldWait = true
  ns.After(Sync.OLD_PEERS_WAIT, function()
    synced.oldWait = nil
    if synced.done then local line = Sync.OldPeersLine(); if line then Sync.ChatLine(line) end end
  end)
end
function Sync.NoteRecord(now) synced.lastNew = now end
-- end of a hello round: `n` records learned in it; `more` = another round follows
-- v1.2 AC3 (S8): with guild traffic a round always teaches a record or two and the 60 s of silence never come, so a
-- round that teaches <= SYNCED_FEW records counts as one with no differences
Sync.SYNCED_FEW = 2
function Sync.NoteRound(n, now, more)
  if synced.done then return end
  if n <= Sync.SYNCED_FEW then fireSynced(); return end
  if not more then synced.waitFrom = now end
end
function Sync.CheckSynced(now)
  if synced.done or not synced.waitFrom then return true end
  if now - math.max(synced.waitFrom, synced.lastNew) >= Sync.SYNCED_QUIET then fireSynced(); return true end
  return false
end
-- the watcher stops after 40 checks (~11 min); if records were still trickling in, it writes the line anyway
function Sync.GiveUpSynced() fireSynced() end
-- v1.2 AC3 (S8, CI 42505121559): a newcomer catching up keeps its rounds going while it holds pending copies (up to
-- MAX_CATCHUP_ROUNDS x 30 s) and each round teaches > SYNCED_FEW (second copies), so neither NoteRound nor the
-- watcher (armed after the last round) fire in time. The first hello of the session arms a deadline: SYNCED_MAX s
-- later the line is written anyway (fireSynced is idempotent). ResetSynced (new session) makes it stale.
Sync.SYNCED_MAX = 480
function Sync.ArmSyncedDeadline()
  if synced.done or synced.deadline or not ns.After then return end
  local mine = synced
  mine.deadline = true
  ns.After(Sync.SYNCED_MAX, function() if synced == mine then fireSynced() end end)
end
local function now() return GetTime and GetTime() or 0 end
local function watchSynced()
  synced.checks = synced.checks + 1
  if Sync.CheckSynced(now()) or not ns.After then return end
  if synced.checks > 40 then Sync.GiveUpSynced(); return end
  ns.After(15, watchSynced)
end
-- "initial sync" = 2 min after a hello, extended while replies keep teaching us records
function Sync.Syncing() return (GetTime and GetTime() or 0) < syncUntil end
-- v1.2 AC3 (margin): a client holding fewer than CATCHUP_MIN profiles + squads is catching up from its first hello
function Sync.Fresh()
  local n = 0
  for _, k in ipairs({ "profile", "squad" }) do
    for _ in pairs(M.kindTable(ns.state, k)) do n = n + 1; if n >= Sync.CATCHUP_MIN then return false end end
  end
  return true
end

function Sync.Hello(again)
  if not again then round = 0; catchup = X and Sync.Fresh() or false; Sync.ArmSyncedDeadline() end
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
    msg.nonce = math.random(1, 2147483646)          -- v1.2: the cubes the repliers pick from (Sync.CubeOf)
    local ph
    for _, k in ipairs(KINDS) do
      if M.P2P_KINDS[k] or M.P2P_AUTH then           -- v1.2: authority kinds wait as pending too
        local hs, any = X.pendHashes(ns.state, k)
        if any then ph = ph or {}; ph[k] = hs end
      end
    end
    msg.ph = ph
    local h2
    for k in pairs(Sync.FINE_KINDS) do
      if next(M.kindTable(ns.state, k)) then h2 = h2 or {}; h2[k] = M.bucketHashes(ns.state, k, Sync.FINE_NB) end
    end
    msg.h2 = h2
    msg.cn = Sync.HelloCn()                        -- v1.2 annex G: certificates we hold (Sync.CertKnownBy)
    if catchup then msg.cu = 1 end      -- AC3 arreglo 2: bigger samples while catching up
  end
  -- v1.2 annex F: our public key, learned strong by whoever hears it from us (WoW guarantees the sender)
  if ns.Trust and ns.myPk then local pk = ns.myPk(); if pk then msg.pk = ns.Trust.hex(pk) end end
  msg.cr = Sync.HelloCertRef()                      -- v1.2 annex G: a reference to our certificate (fix/perf A3)
  Comm.Send("H", msg)
  -- keep asking (with growing delay) while replies keep teaching us records
  if ns.After then
    -- v1.2 (AC3): while catching up, a flat +30 s and no need to have learned anything new: the second copies
    -- only come as answers to the pending hashes (ph) of the next hello
    ns.After(catchup and 30 or (30 + 15 * round), function()
      if round == 0 and learned >= Sync.CATCHUP_MIN then catchup = true end
      local more
      if catchup then
        more = round < MAX_CATCHUP_ROUNDS and (learned > 0 or (X and X.hasPend and X.hasPend(ns.state)) and true or false)
      else
        more = learned >= 10 and round < MAX_ROUNDS
      end
      Sync.NoteRound(learned, now(), more)
      if more then
        round = round + 1; Sync.Hello(true)
      elseif not synced.done then
        synced.checks = 0; ns.After(Sync.SYNCED_QUIET, watchSynced)
      end
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

-- v1.2: the cube (0..CUBES-1) of a record for a hello nonce; every replier picks CUBES_PICK cubes at random, so
-- each record goes out from ~2 distinct nodes and two nodes rarely send the same thing
function Sync.CubeOf(id, nonce)
  local h = ns.Serialize.hash(tostring(id) .. "/" .. tostring(nonce))
  return (tonumber(h:sub(1, 8), 16) + tonumber(h:sub(9, 16), 16)) % Sync.CUBES
end
local function pickCubes(base)
  local c, n = {}, 0
  for x in pairs(base or {}) do c[x] = true; n = n + 1 end
  while n < Sync.CUBES_PICK * (base and 2 or 1) do
    local x = math.random(0, Sync.CUBES - 1)
    if not c[x] then c[x] = true; n = n + 1 end
  end
  return c
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
  local auth = p2p and proto >= 2          -- v1.2 requester: authority records of others too (quorum 2)
  local me = ns.me and ns.me() or nil
  local pres = {}               -- indexes in all of others' presences (candidates)
  for ki, k in ipairs(KINDS) do
    local fine = proto >= 2 and Sync.FINE_KINDS[k] and type(payload.h2) == "table" and payload.h2[k]
    if not (type(fine) == "table" and #fine == Sync.FINE_NB) then fine = nil end
    local list = fine and M.diffRecords(ns.state, k, fine, Sync.FINE_NB)
      or (CORE_KIND[k] or payload.h[k] ~= nil) and M.diffRecords(ns.state, k, payload.h[k]) or {}
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
      elseif suppressed(r, startedAt, otherPres and p2pReq or p2p, auth) then
        Sync.stats.suppressed = Sync.stats.suppressed + 1
      else
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
  -- v1.2 requester (nonce): a random sample of 2 of 8 cubes, at most MAX_SAMPLE records, no cursor
  local nonce = proto >= 2 and tonumber(payload.nonce) or nil
  local peers = ns.peerCount and ns.peerCount() or 1     -- 1.2.1: the 1.2 clients that answer, not the guild online
  if nonce and peers > Sync.SAMPLE_MIN_ONLINE then
    -- v1.2 (AC3 intento 3): records in a bucket where the requester holds pending copies (ph) are the ones it
    -- needs a second / third copy of: twice the cubes for them, and they go first (the tail of S8g is pending)
    local cubes = pickCubes()
    local wide = pickCubes(cubes)
    if payload.cu == 1 and #all <= Sync.CATCHUP_ALL then
      for i = 0, Sync.CUBES - 1 do cubes[i] = true end
    end
    local ph = type(payload.ph) == "table" and payload.ph or {}
    local prio, rest = {}, {}
    for _, e in ipairs(all) do
      local cb = Sync.CubeOf(e.r.id, nonce)
      local pk = ph[e.r.k]
      local inPend = type(pk) == "table" and pk[M.bucketOf(e.r.id, M.NBUCKETS)]
      if inPend and inPend ~= "0" and wide[cb] then prio[#prio + 1] = e.r
      elseif cubes[cb] then rest[#rest + 1] = e.r end
    end
    local function shuffle(t)
      for i = 1, #t - 1 do local j = math.random(i, #t); t[i], t[j] = t[j], t[i] end
    end
    shuffle(prio); shuffle(rest)
    local cap, big = Sync.MAX_SAMPLE, nil
    if payload.cu == 1 then
      local t = GetTime and GetTime() or 0
      local b = bigReply[sender]
      if not b or t < (b.last or b.w) or t - b.w >= Sync.CATCHUP_WINDOW then b = { last = nil, w = t, n = 0 }; bigReply[sender] = b end
      if b.n < Sync.CATCHUP_BUDGET and (not b.last or t - b.last >= Sync.CATCHUP_COOLDOWN) then
        b.last, b.n = t, b.n + 1; cap = Sync.MAX_SAMPLE_CATCHUP; big = true
      end
    end
    local out = {}
    for _, t in ipairs({ prio, rest }) do
      for _, r in ipairs(t) do if #out < cap then out[#out + 1] = r end end
    end
    Sync.stats.sampled = Sync.stats.sampled + #out
    return out, big
  end
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

Sync.HELLO_MIN = 20
local helloReplyAt = {}           -- requester -> serverNow of the last hello we considered answering
local function onHello(payload, sender)
  if type(payload) ~= "table" or type(payload.h) ~= "table" then return end
  local from = (ns.fullName and ns.fullName(sender)) or sender
  Sync.HelloHeard(from)
  if ns.ProgressGlue and type(payload.ec) == "table" then ns.ProgressGlue.OnHello(payload.ec, sender) end
  if ns.ProgressGlue and ns.ProgressGlue.OnSummaries and type(payload.ws) == "table" then
    ns.ProgressGlue.OnSummaries(payload.ws, sender)
  end
  if ns.HallGlue then ns.HallGlue.OnHello(payload.rh, sender) end
  if ns.Trust and ns.trustDB and type(payload.pk) == "string" and from ~= (ns.me and ns.me()) then
    local pk = ns.Trust.unhex(payload.pk)
    if pk then
      local now = (ns.serverTime and ns.serverTime()) or (GetServerTime and GetServerTime()) or 0
      Sync.OnOwnerKey(from, ns.Trust.hearOwner(ns.trustDB, from, pk, now))
    end
  end
  Sync.OfferCert(payload.c, from)
  Sync.OnCertRef(payload.cr, from)
  -- only a fraction of the guild answers, after random jitter, to avoid a reply storm. Officers always answer a
  -- 1.0 / 1.1 requester (their relays are the trusted ones there); a 1.2 requester gets them as one more node.
  local peers = ns.peerCount and ns.peerCount() or 1     -- 1.2.1: the 1.2 clients that answer, not the guild online
  local p = math.min(1, 8 / math.max(1, peers))
  local officer = isOfficerMe()
  Sync.stats.hellos = Sync.stats.hellos + 1
  -- v1.2 (D2): officers keep answering every 1.0 / 1.1 requester; a 1.2 requester gets them as one more node
  local always = officer and not (X and X.protoOf(payload) >= 2)
  -- sec F5: one reply per requester per HELLO_MIN s (a client's own hellos are >= 30 s apart; a flood from one
  -- name, with or without cu, gets no more). Officers answering a 1.0 / 1.1 requester keep the same limit.
  local tnow = serverNow() or 0
  local lastH = helloReplyAt[from]
  if lastH and tnow >= lastH and tnow - lastH < Sync.HELLO_MIN then Sync.stats.helloCapped = (Sync.stats.helloCapped or 0) + 1; return end
  helloReplyAt[from] = tnow
  if not always and math.random() > p then return end
  Sync.stats.replied = Sync.stats.replied + 1
  if X and (tonumber(payload.p2) or 0) >= 2 and from ~= (ns.me and ns.me()) and not Sync.CertKnownBy(payload.cn) then
    Sync.RehelloCert(from)
  end
  local startedAt = GetTime and GetTime() or 0
  local onlyMe = (not officer) and ns.me and ns.me() or nil
  -- v1.1: while a GM/officer with the addon is online, their trusted relays already serve the requester: a member
  -- answers like 1.0 (own records only, no unverified forwards). P2P relaying is for the hours without them.
  -- v1.2: only for 1.0 / 1.1 requesters; a 1.2 requester is served P2P whoever is online (officers are one more node)
  local p2pOff = (not officer) and (not X or X.protoOf(payload) < 2) and Sync.TrustedOnline()
  ns.After(2 + math.random() * 6, function()
    -- AC3 arreglo 3: the catch-up sized reply (once per cooldown per requester) skips our send queue, like
    -- Sync.Publish; otherwise it waits behind the S8 backlog (~150 s at 1 msg/s) and the newcomer stalls
    local out, urgent = Sync.ReplyFor(payload, from, startedAt, onlyMe, p2pOff, officer)
    if ns.debug then ns.debug(("hello from %s: replying %d records"):format(tostring(sender), #out)) end
    -- v1.2 (AC6): a member's relay of someone else's authority record goes by WHISPER to the 1.2 requester only; on
    -- the GUILD channel every 1.0 / 1.1 client online would take it and refuse it as "relay"
    local pub, priv = out, nil
    if not officer then
      pub, priv = {}, {}
      for _, r in ipairs(out) do
        if r.a == onlyMe or M.isP2P(r) then pub[#pub + 1] = r else priv[#priv + 1] = r end
      end
    end
    sendRecords(pub, nil, urgent, from)
    if priv and #priv > 0 then sendRecords(priv, from, urgent) end
    if p2pOff then return end
    -- unverified versions only go to the requester (a 1.0 client would trust them from an officer)
    local fw = Sync.ForwardsFor(payload)
    for _, b in ipairs(Sync.PackRecords(fw)) do Comm.Send("D", { r = b }, "WHISPER", from) end
  end)
end

local function stored(rec) return M.stored(ns.state, rec) end

local function onRecords(payload, sender, channel)
  if type(payload) ~= "table" or type(payload.r) ~= "table" then return end
  local from = (ns.fullName and ns.fullName(sender)) or sender
  local t = GetTime and GetTime() or 0
  if channel == "GUILD" and type(payload.m) == "table" then
    for i = 1, math.min(#payload.m, 20) do
      local m = payload.m[i]
      if type(m) == "table" and type(m.a) == "string" and (not ns.roster or ns.roster(m.a)) then noteManHeard(m) end
    end
  end
  learnKeys(payload, from)
  Sync.OfferCert(payload.c, from)
  if payload.ca and channel == "WHISPER" then Sync.CertAsked(from) end
  offerManifests(payload, from)
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
      -- presences do not keep the hello rounds going (one per member, low value; the next hello brings them).
      -- v1.2 (AC3): a new pending copy counts too: a newcomer's first replies come from members (quorum), and
      -- without more rounds it never gets the second copies that verify them
      if (ok or why == "pending") and rec.k ~= "presence" then learned = learned + 1; syncUntil = math.max(syncUntil, t + 60); synced.lastNew = t end
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

local function dispatch(tag, payload, sender, sentAt, channel)
  if tag == "D" then onRecords(payload, sender, channel)
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
function Sync.OnMessage(tag, payload, sender, channel, sentAt)
  if type(sender) == "string" then heard[(ns.fullName and ns.fullName(sender)) or sender] = GetTime and GetTime() or 0 end
  local ok, err = pcall(dispatch, tag, payload, sender, sentAt, channel)
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
