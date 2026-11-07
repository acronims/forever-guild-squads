-- Guild Squads (MIT) - Core/P2P.lua
-- Pure Lua. v1.1: peer-to-peer relay of AUTHORIAL records (M.P2P_KINDS, annex A of docs/SPEC-v1.1-sync-p2p.md).
--   * live (sender = author) or a GM/officer relay: unchanged (Model.provenance).
--   * any other member relaying an authorial record: the version waits in state.p2p.pend ("unverified": shown grey,
--     never counted) until the SAME version (vkey = kind:id@ts.sq.author#content hash) arrives from 2 distinct
--     relayers, none of them the author. Two contents with the same ts.sq.author = conflict: nothing applies until the
--     author. The current captain of the record's squad is an authority node: one relay from him is enough.
--   * a copy forwarded with u = 1 (the sender itself holds it unverified) is stored for display but never votes.
--   * the author always wins: a live record of the author replaces a version that came by relay, whatever its ts.
--     The author's own client refuses ("mine") a relayed version with its name that it does not hold and publishes a
--     `repudiate` {t = kind:id, v = vkey}; that version is removed everywhere and every relayer that brought it is
--     counted. A relayer with 3+ repudiations does not vote on this client for 7 days.
--   * `presence` {ver, day}: published by each client at most once a day; the real installed counter.
local _, ns = ...
ns = ns or {}

local X = {}
ns.P2P = X
local M, S, P = ns.Model, ns.Serialize, ns.Permissions

X.PROTO = 2                    -- v1.2 hellos carry p2 = 2: they take every kind relayed by anyone (quorum)
X.PROTO_AUTHORIAL = 1          -- 1.1 hellos carry p2 = 1: authorial relays from anyone, authority only from officers
X.QUORUM = 2
X.QUORUM_AUTH = 3              -- v1.2 D1: distinct relayers for an authority record (squad, settings, annul...)
-- relayers needed for this record: authorial kinds 2, authority kinds 3
function X.quorumFor(rec) return M.isP2P(rec) and X.QUORUM or X.QUORUM_AUTH end
-- what a hello payload can take: 0 = 1.0 (authors / officers only), 1 = 1.1 (+ authorial), 2 = 1.2 (+ authority)
function X.protoOf(payload)
  local p = type(payload) == "table" and tonumber(payload.p2) or nil
  if not p or p < 1 then return 0 end
  return p >= 2 and 2 or 1
end
X.PEND_TTL = 7 * 86400
X.MAX_PEND = 2000
X.BLOCK_AT = 3
X.BLOCK_TTL = 7 * 86400
X.CONTRA_TTL = 7 * 86400
X.PRESENCE_TTL = 60 * 86400
X.REPUDIATE_TTL = 30 * 86400
X.ADOPT_DAYS = 30

local function num(n) if type(n) == "number" and n == math.floor(n) and n > -1e15 and n < 1e15 then return string.format("%d", n) end return tostring(n) end
local function kidOf(rec) return rec.k .. ":" .. rec.id end
X.kid = kidOf

-- the version key with a hash of the content: same ts.sq.author with other data = another version
function X.vkey(rec)
  return kidOf(rec) .. "@" .. num(rec.ts) .. "." .. num(rec.sq) .. "." .. tostring(rec.a) .. "#" .. S.hash(S.encode(rec.d or {})):sub(1, 8)
end

function X.st(state)
  local st = state.p2p
  if type(st) ~= "table" then st = {}; state.p2p = st end
  st.pend = type(st.pend) == "table" and st.pend or {}     -- kid -> vkey -> { r, by = { relayer = ts }, t, from, cf }
  st.via = type(st.via) == "table" and st.via or {}        -- kid -> { v, by = { relayers }, t } (applied by relay)
  st.rep = type(st.rep) == "table" and st.rep or {}        -- relayer -> { n, t } repudiations counted on this client
  st.contra = type(st.contra) == "table" and st.contra or {} -- vkey -> { by, t } relayed versions the author contradicted
  st.verified = tonumber(st.verified) or 0
  st.repudiated = tonumber(st.repudiated) or 0
  return st
end

local function pendCount(st)
  local n = 0
  for _, byId in pairs(st.pend) do for _ in pairs(byId) do n = n + 1 end end
  return n
end

function X.blocked(state, name, now)
  local st = state.p2p
  local e = st and st.rep and st.rep[name]
  return e ~= nil and (e.n or 0) >= X.BLOCK_AT and (now or 0) - (e.t or 0) < X.BLOCK_TTL
end
function X.relayerScore(state, name)
  local e = state.p2p and state.p2p.rep and state.p2p.rep[name]
  return e and e.n or 0
end

-- the squad a record belongs to (captain nodes): profile -> d.squad, reject inv -> d.sid,
-- rsvp / witness -> the squad of the owner of the event's roster
function X.squadOfRecord(state, rec)
  local d = rec.d or {}
  if rec.k == "profile" then return d.squad end
  if rec.k == "reject" then return d.sid end
  if rec.k == "rsvp" or rec.k == "witness" then
    local ro = state.rosters and type(d.rid) == "string" and state.rosters[d.rid]
    local owner = ro and ro.d and ro.d.owner
    return owner and M.squadOf(state, owner) or nil
  end
  return nil
end
-- the current captain of the squad (stored, not disbanded, not handed over with xferTo)
function X.captainNode(state, rec, sender)
  if type(sender) ~= "string" then return false end
  local sid = X.squadOfRecord(state, rec)
  if type(sid) ~= "string" then return false end
  local sq = state.squads and state.squads[sid]
  if not sq or sq.d.disbanded or sq.d.captain ~= sender then return false end
  local cp = state.profiles[sender]
  local xf = cp and cp.d and cp.d.xferTo
  if type(xf) == "string" and xf:sub(1, #sid + 1) == sid .. ">" then return false end
  return true
end

-- pending versions not newer than `rec` are obsolete once `rec` is stored
local function clearPend(st, kid, rec)
  local byId = st.pend[kid]
  if not byId then return end
  for vk, e in pairs(byId) do
    if not M.newer(e.r, rec) or M.same(e.r, rec) then byId[vk] = nil end
  end
  if next(byId) == nil then st.pend[kid] = nil end
end

local function evictOldest(st)
  local okid, ovk, ot
  for kid, byId in pairs(st.pend) do
    for vk, e in pairs(byId) do
      if not ot or (e.t or 0) < ot then okid, ovk, ot = kid, vk, e.t or 0 end
    end
  end
  if okid then st.pend[okid][ovk] = nil; if next(st.pend[okid]) == nil then st.pend[okid] = nil end end
end

local function commit(state, rec, ctx, vk, kid, voters)
  local st = X.st(state)
  local okA, why = M.apply(state, rec, { roster = ctx.roster, trusted = true, now = ctx.now })
  if not okA then return false, why end
  table.sort(voters)
  st.via[kid] = { v = vk, by = voters, t = ctx.now or rec.ts }
  clearPend(st, kid, rec)
  st.verified = st.verified + 1
  return true, "verified"
end

-- Model.apply hands over an authorial record relayed by a non-officer (or forwarded unverified, u = 1).
-- rec is already sanitized. -> ok, why ("verified" | "pending" | "conflict" | "mine" | "repudiated" | ...)
function X.offer(state, rec, ctx, settings, u)
  local st = X.st(state)
  local now = ctx.now or rec.ts
  local sender = ctx.sender
  local kid, vk = kidOf(rec), X.vkey(rec)
  if state.repudiates and state.repudiates[vk] then return false, "repudiated" end
  local stored = M.stored(state, rec)
  if stored and M.same(rec, stored) then
    if X.vkey(stored) == vk then return false, "dup" end
    if ctx.me and rec.a == ctx.me then return false, "mine" end      -- my signature, not my content
    return false, "conflict"
  end
  if ctx.me and rec.a == ctx.me and type(ctx.ledger) == "table" and X.ledgerSays(ctx.ledger, rec, vk) == false then
    return false, "mine"
  end
  if stored and not M.newer(rec, stored) then return false, "stale" end
  -- my own record in a version I never wrote (I hold an older one): refuse it and repudiate it
  if ctx.me and rec.a == ctx.me and stored then return false, "mine" end
  -- my name, a version newer than my ledger start and not in it: I never wrote it (whatever its ts)
  if ctx.me and rec.a == ctx.me and type(ctx.ledger) == "table" and X.ledgerSays(ctx.ledger, rec, vk) == false then
    return false, "mine"
  end
  if not u and M.isP2P(rec) and X.captainNode(state, rec, sender) then return commit(state, rec, ctx, vk, kid, { sender }) end
  local byId = st.pend[kid]
  if not byId then byId = {}; st.pend[kid] = byId end
  local e = byId[vk]
  if not e then
    if pendCount(st) >= X.MAX_PEND then evictOldest(st) end
    byId = st.pend[kid] or {}; st.pend[kid] = byId
    e = { r = rec, by = {}, t = now, from = sender }
    byId[vk] = e
  end
  if not u and type(sender) == "string" and sender ~= rec.a then e.by[sender] = now end
  for ovk, o in pairs(byId) do
    if ovk ~= vk and o.r.ts == rec.ts and o.r.sq == rec.sq and o.r.a == rec.a then e.cf = true; o.cf = true end
  end
  if e.cf then return false, "conflict" end
  local voters = {}
  for n in pairs(e.by) do if not X.blocked(state, n, now) then voters[#voters + 1] = n end end
  if #voters >= X.quorumFor(rec) then return commit(state, rec, ctx, vk, kid, voters) end
  return false, "pending"
end

-- before any authorial record is applied: repudiated versions never come back, and a live record of the author
-- replaces a version that came by relay. -> ok, why, restore (fn to undo the replacement if the apply fails)
function X.before(state, rec, ctx)
  if rec.k == "repudiate" or not (M.P2P_KINDS[rec.k] or M.P2P_AUTH) then return true end
  if state.repudiates and next(state.repudiates) and state.repudiates[X.vkey(rec)] then return false, "repudiated" end
  local st = state.p2p
  if not (st and st.via and ctx.sender and ctx.sender == rec.a) then return true end
  local kid = kidOf(rec)
  local via = st.via[kid]
  if not via then return true end
  local t = M.kindTable(state, rec.k)
  local cur = t[rec.id]
  st.via[kid] = nil                                       -- the author speaks for this record from now on
  if cur and X.vkey(cur) ~= X.vkey(rec) then
    st.contra[via.v] = { by = via.by, t = ctx.now or rec.ts }
    -- the contradicted version goes back to the author (Sync whispers it, u = 1): its client repudiates it
    X.outbox = X.outbox or {}
    X.outbox[#X.outbox + 1] = cur
    t[rec.id] = nil
    return true, nil, function() t[rec.id] = cur; st.via[kid] = via; st.contra[via.v] = nil; X.outbox[#X.outbox] = nil end
  end
  return true
end

-- the ledger of the versions I signed (per guild, SavedVariables): { since = ts, v = { [vkey] = ts } }.
-- -> true (mine), false (newer than the ledger start and not in it: I never wrote it), nil (cannot tell)
X.LEDGER_MAX = 3000
function X.ledgerSays(ledger, rec, vk)
  if type(ledger.v) ~= "table" or type(ledger.since) ~= "number" then return nil end
  if ledger.v[vk or X.vkey(rec)] then return true end
  if rec.ts >= ledger.since then return false end
  return nil
end
function X.ledgerNote(ledger, rec, now)
  ledger.since = tonumber(ledger.since) or now or rec.ts
  ledger.v = type(ledger.v) == "table" and ledger.v or {}
  ledger.v[X.vkey(rec)] = rec.ts
  ledger.n = (tonumber(ledger.n) or 0) + 1
  if ledger.n > X.LEDGER_MAX * 1.2 then
    local list = {}
    for k, t in pairs(ledger.v) do list[#list + 1] = { k, t } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    local keep = {}
    for i = 1, math.min(#list, X.LEDGER_MAX) do keep[list[i][1]] = list[i][2] end
    -- the forgotten ones are older than the new start: "cannot tell" again, never "not mine"
    if list[X.LEDGER_MAX + 1] then ledger.since = list[X.LEDGER_MAX][2] end
    ledger.v, ledger.n = keep, math.min(#list, X.LEDGER_MAX)
  end
end

-- contradicted versions waiting to be shown to their author (transient, not saved)
function X.popContra()
  local out = X.outbox or {}
  X.outbox = {}
  return out
end

-- after a successful apply that was not a relay commit: pending versions not newer are obsolete
function X.after(state, rec)
  local st = state.p2p
  if st and st.pend then clearPend(st, kidOf(rec), rec) end
end

-- pending / unverified version of a record (newest), for the grey display: { r, from, by }
function X.unverified(state, kind, id)
  local st = state.p2p
  local byId = st and st.pend and st.pend[kind .. ":" .. id]
  if not byId then return nil end
  local best
  for _, e in pairs(byId) do if not best or M.newer(e.r, best.r) then best = e end end
  return best
end
function X.pendingList(state, kind)
  local out = {}
  for kid, byId in pairs(state.p2p and state.p2p.pend or {}) do
    if kid:sub(1, #kind + 1) == kind .. ":" then for _, e in pairs(byId) do out[#out + 1] = e end end
  end
  return out
end

function X.expire(state, now)
  local st = X.st(state)
  for kid, byId in pairs(st.pend) do
    for vk, e in pairs(byId) do if now - (e.t or 0) > X.PEND_TTL then byId[vk] = nil end end
    if next(byId) == nil then st.pend[kid] = nil end
  end
  for vk, c in pairs(st.contra) do if now - (c.t or 0) > X.CONTRA_TTL then st.contra[vk] = nil end end
  -- relay provenance of verified records: kept 30 days (the author's live version wins over it meanwhile)
  for kid, v in pairs(st.via) do if now - (v.t or 0) > X.REPUDIATE_TTL then st.via[kid] = nil end end
  for n, e in pairs(st.rep) do if now - (e.t or 0) > X.BLOCK_TTL then st.rep[n] = nil end end
  for id, r in pairs(state.repudiates or {}) do if now - r.ts > X.REPUDIATE_TTL then state.repudiates[id] = nil end end
end

function X.stats(state, now)
  local st = X.st(state)
  local blocked = 0
  for n in pairs(st.rep) do if X.blocked(state, n, now or 0) then blocked = blocked + 1 end end
  return { pend = pendCount(st), verified = st.verified, repudiated = st.repudiated, blocked = blocked }
end
function X.diagLine(state, now)
  local s = X.stats(state, now)
  local list = {}
  for n, e in pairs(state.p2p.rep) do list[#list + 1] = n .. ":" .. e.n .. (X.blocked(state, n, now or 0) and "!" or "") end
  table.sort(list)
  return ("p2p pend=%d verified=%d repudiated=%d blocked=%d"):format(s.pend, s.verified, s.repudiated, s.blocked)
    .. (#list > 0 and (" relayers=" .. table.concat(list, ",")) or "")
end

-------------------------------------------------------------------------------
-- bucket hashes of the pending versions (hello field `ph`): peers forward what we lack, unverified (u = 1)
function X.pendHashes(state, kind, nb)
  nb = nb or M.NBUCKETS
  local lists = {}
  for i = 1, nb do lists[i] = {} end
  for kid, byId in pairs(state.p2p and state.p2p.pend or {}) do
    if kid:sub(1, #kind + 1) == kind .. ":" then
      local b = lists[M.bucketOf(kid:sub(#kind + 2), nb)]
      for vk in pairs(byId) do b[#b + 1] = vk end
    end
  end
  local out, any = {}, false
  for i = 1, nb do
    table.sort(lists[i])
    out[i] = #lists[i] == 0 and "0" or S.hash(table.concat(lists[i], ",")):sub(1, 6)
    if out[i] ~= "0" then any = true end
  end
  return out, any
end
-- pending records of `kind` whose bucket differs from `remote` (a copy flagged u = 1)
function X.pendDiff(state, kind, remote, nb)
  nb = nb or M.NBUCKETS
  local mine = X.pendHashes(state, kind, nb)
  local out = {}
  for kid, byId in pairs(state.p2p and state.p2p.pend or {}) do
    if kid:sub(1, #kind + 1) == kind .. ":" then
      local b = M.bucketOf(kid:sub(#kind + 2), nb)
      if not remote or remote[b] ~= mine[b] then
        for _, e in pairs(byId) do
          if not e.cf then
            local r = e.r
            out[#out + 1] = { k = r.k, id = r.id, a = r.a, ts = r.ts, sq = r.sq, d = r.d, u = 1 }
          end
        end
      end
    end
  end
  table.sort(out, function(x, y) if x.id ~= y.id then return x.id < y.id end return x.ts < y.ts end)
  return out
end

-- SavedVariables: the pending store, relay provenance and the counters (records themselves are saved as usual)
function X.export(state)
  local st = X.st(state)
  return { pend = st.pend, via = st.via, rep = st.rep, contra = st.contra, verified = st.verified, repudiated = st.repudiated }
end
function X.import(state, saved)
  if type(saved) ~= "table" then return end
  state.p2p = saved
  local st = X.st(state)
  -- drop malformed entries (hand-edited / older files)
  for kid, byId in pairs(st.pend) do
    if type(byId) ~= "table" then st.pend[kid] = nil
    else
      for vk, e in pairs(byId) do
        if type(e) ~= "table" or not M.validShape(e.r) or type(e.by) ~= "table" then byId[vk] = nil end
      end
    end
  end
  while pendCount(st) > X.MAX_PEND do evictOldest(st) end
end

-------------------------------------------------------------------------------
-- repudiate {t = "kind:id", v = vkey}: signed by the author of the version it denies. id = vkey.
X.SCHEMA_REPUDIATE = { t = { "s", 320 }, v = { "s", 400 } }
function X.repudiation(rec, author, ts, sq)
  local vk = X.vkey(rec)
  return { k = "repudiate", id = vk, a = author, ts = ts, sq = sq, d = { t = kidOf(rec), v = vk } }
end

local function enforce(state, d, now)
  local st = X.st(state)
  local kind = d.t:match("^([^:]+):")
  local id = d.t:sub(#kind + 2)
  local relayers = {}
  local function add(list) for _, n in ipairs(list or {}) do relayers[n] = true end end
  local t = M.kindTable(state, kind)
  local cur = t[id]
  if cur and X.vkey(cur) == d.v then
    t[id] = nil
    local via = st.via[d.t]
    if via and via.v == d.v then add(via.by); st.via[d.t] = nil end
  end
  if st.contra[d.v] then add(st.contra[d.v].by); st.contra[d.v] = nil end
  local byId = st.pend[d.t]
  local e = byId and byId[d.v]
  if e then
    for n in pairs(e.by) do relayers[n] = true end
    if e.from then relayers[e.from] = true end
    byId[d.v] = nil
    if next(byId) == nil then st.pend[d.t] = nil end
  end
  local any = false
  for n in pairs(relayers) do
    local r = st.rep[n] or { n = 0 }
    r.n = (r.n or 0) + 1; r.t = now
    st.rep[n] = r
    any = true
  end
  if any or cur then st.repudiated = st.repudiated + 1 end
end

function X.applyRepudiate(state, rec, roster, settings, ctx)
  local d = rec.d
  if type(d.t) ~= "string" or type(d.v) ~= "string" or rec.id ~= d.v then return false, "shape" end
  if d.v:sub(1, #d.t + 1) ~= d.t .. "@" then return false, "shape" end
  local kind = d.t:match("^([^:]+):")
  if not kind or not M.P2P_KINDS[kind] or kind == "repudiate" then return false, "shape" end
  -- only the author of the denied version signs its repudiation
  local tail = "." .. rec.a .. "#"
  local p = d.v:find(tail, #d.t + 2, true)
  if not p or not d.v:sub(p + #tail):match("^%w+$") then return false, "denied" end
  state.repudiates = state.repudiates or {}
  if state.repudiates[rec.id] then return false, "dup" end
  state.repudiates[rec.id] = rec
  enforce(state, d, (ctx and ctx.now) or rec.ts)
  return true, "applied"
end

-------------------------------------------------------------------------------
-- presence {ver, day}: id = author. The installed counter = roster members with a presence in the last adoptDays.
X.SCHEMA_PRESENCE = { ver = { "s", 16 }, day = { "n" } }
function X.applyPresence(state, rec, roster, settings, ctx)
  if rec.id ~= rec.a then return false, "denied" end
  if ctx and ctx.now and ctx.now - rec.ts > X.PRESENCE_TTL then return false, "old" end
  state.presence = state.presence or {}
  local cur = state.presence[rec.id]
  if M.same(rec, cur) then return false, "dup" end
  if not M.newer(rec, cur) then return false, "stale" end
  state.presence[rec.id] = rec
  return true, "applied"
end

-- members = roster map name -> { rank, ... }. -> { n, total, days, list = { { name, ver, ts } }, gmMissing }
function X.adoption(state, members, now, extra)
  local days = tonumber(M.settingsOf(state).adoptDays) or X.ADOPT_DAYS
  local out = { n = 0, total = 0, days = days, list = {}, gmMissing = false }
  local gmSeen, gmHas = false, false
  for name, r in pairs(members or {}) do
    out.total = out.total + 1
    local p = state.presence and state.presence[name]
    local has = p and now - p.ts <= days * 86400
    local ver = p and p.d.ver
    if not has and extra then local okE, v = extra(name, days); if okE then has, ver = true, v or "?" end end
    if has then out.n = out.n + 1; out.list[#out.list + 1] = { name = name, ver = ver or "?", ts = p and p.ts } end
    if type(r) == "table" and r.rank == 0 then gmSeen = true; if has then gmHas = true end end
  end
  out.gmMissing = gmSeen and not gmHas
  table.sort(out.list, function(a, b) return a.name < b.name end)
  return out
end
function X.counterText(a, L)
  L = L or {}
  local fmt = L.ADOPTION or "Guild Squads: %d/%d members (%d days)"
  return fmt:format(a.n, a.total, a.days)
end
-- a presence of someone who left the guild, or older than 60 days, is dropped -> number dropped
function X.prunePresence(state, members, now)
  local n = 0
  for name, r in pairs(state.presence or {}) do
    if not (members and members[name]) or now - r.ts > X.PRESENCE_TTL then state.presence[name] = nil; n = n + 1 end
  end
  return n
end

if M and M.registerKind then
  M.registerKind("presence", X.SCHEMA_PRESENCE, "presence", 14, X.applyPresence)
  M.registerKind("repudiate", X.SCHEMA_REPUDIATE, "repudiates", 15, X.applyRepudiate)
  M.SCHEMA.settings.adoptDays = { "n" }
end

return X
