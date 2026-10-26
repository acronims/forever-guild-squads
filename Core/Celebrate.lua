-- Guild Squads (MIT) - Core/Celebrate.lua
-- Pure Lua. Celebrations (docs/en/ACHIEVEMENTS.md §7): what gets announced (GM settings), who announces (a single
-- client per event), rate limit (1 message / 10 s) and the plain message text. The WoW glue decides when it may
-- talk (never during an encounter, never under C_ChatInfo.InChatMessagingLockdown).
-- CelebrationMsg = { key, kind = "race"|"ach", pos?, who (protagonists), what } - no economy fields.
local _, ns = ...
ns = ns or {}

local C = {}
ns.Celebrate = C

C.GAP = 10                  -- seconds between two guild-chat messages
C.SCOPES = { "first", "top3", "any" }
C.MAX_LEN = 120
C.MAX_QUEUE = 20
C.TTL = 600                 -- a queued celebration older than 10 min is dropped, never sent late

-- settings fields (GM): celOn (guild chat on/off), celScope ("first"/"top3"/"any"), celSquad (squad achievements)
function C.eligible(ev, s)
  if type(ev) ~= "table" or type(s) ~= "table" or s.celOn ~= true then return false end
  if ev.kind == "ach" then return s.celSquad == true end
  if ev.kind ~= "race" or type(ev.pos) ~= "number" then return false end
  local scope = s.celScope or "first"
  if scope == "first" then return ev.pos == 1 end
  if scope == "top3" then return ev.pos <= 3 end
  return scope == "any"
end

-- the announcer does not depend on the local hello map.
-- Preferred announcer (same on every client that sees the same guild roster):
--   1. the first protagonist (alphabetical) online in the guild roster;
--   2. otherwise the online addon user (heard in the last 15 min, see ctx.users) with the highest guild rank, ties by
--      name. With nobody known, nil (nobody is preferred: the claim below decides).
-- ctx = { hasAddon(name), online(name), rank(name) -> n, users = { names with the addon online } }
-- The preferred announcer only sets priority: every message is preceded by a CLAIM (C.claim*), so even clients that
-- disagree (different roster snapshot, fresh install) end up with exactly one sender.
function C.announcer(protagonists, ctx)
  local list = {}
  for _, n in ipairs(protagonists or {}) do list[#list + 1] = n end
  table.sort(list)
  for _, n in ipairs(list) do
    if ctx.online(n) then return n end
  end
  local best, br
  for _, n in ipairs(ctx.users or {}) do
    if ctx.online(n) and ctx.hasAddon(n) then
      local r = ctx.rank(n) or 99
      if not best or r < br or (r == br and n < best) then best, br = n, r end
    end
  end
  return best
end

-- CLAIM protocol: before announcing, wait a random 2-6 s (backups: after the preferred announcer had its chance),
-- send "CL <event>" on the GUILD addon channel, wait CLAIM_HOLD s and announce only if we are the winner: the
-- lowest name among the claims heard within CLAIM_HOLD of the first one. A claim heard before our own timer fires
-- cancels ours.
C.CLAIM_MIN, C.CLAIM_MAX = 2, 6
C.BACKUP_DELAY = 6          -- backups claim in [6+2, 6+6] s: the preferred announcer (2-6 s) goes first
C.CLAIM_HOLD = 2
C.CLAIM_TTL = 120           -- claims are forgotten after 2 min
function C.claimDelay(preferred, rnd)
  rnd = type(rnd) == "number" and math.min(1, math.max(0, rnd)) or 0.5
  local d = C.CLAIM_MIN + (C.CLAIM_MAX - C.CLAIM_MIN) * rnd
  if not preferred then d = d + C.BACKUP_DELAY end
  return d
end
function C.newClaims() return {} end
-- note a claim (ours or heard) at local time t; late claims (after the hold window) are ignored
function C.noteClaim(book, key, by, t)
  if type(key) ~= "string" or type(by) ~= "string" then return false end
  for k, c in pairs(book) do
    if k ~= "cand" and t - c.first > C.CLAIM_TTL then book[k] = nil; if book.cand then book.cand[k] = nil end end
  end
  local c = book[key]
  if not c then c = { first = t, names = {} }; book[key] = c end
  if t - c.first > C.CLAIM_HOLD then return false end
  c.names[by] = true
  return true
end
-- only CANDIDATES count. Every client derives the same ordered list
-- (C.candidates: preferred announcer first, then up to 2 backups) and registers it with C.setCandidates. A claim
-- from anyone else is ignored (a bare /run claim silences nothing), and with no list registered nothing counts yet.
-- The winner among the claims heard inside the hold window is the best-placed candidate (not the lowest name), so a
-- client whose own claim left its queue late (noted when it really left: Comm onSent) agrees with the others.
C.MAX_CANDIDATES = 3
function C.candidates(protagonists, ctx, busy)
  local out, seen = {}, {}
  local function add(n) if n and not seen[n] and #out < C.MAX_CANDIDATES then seen[n] = true; out[#out + 1] = n end end
  local list = {}
  for _, n in ipairs(protagonists or {}) do list[#list + 1] = n end
  table.sort(list)
  -- the first protagonist online in the roster (same on every client, addon heard or not), as C.announcer
  for _, n in ipairs(list) do if ctx.online(n) and not (busy and busy(n)) then add(n); break end end
  local users = {}
  for _, n in ipairs(ctx.users or {}) do
    if ctx.online(n) and ctx.hasAddon(n) and not (busy and busy(n)) then users[#users + 1] = n end
  end
  table.sort(users, function(a, b)
    local ra, rb = ctx.rank(a) or 99, ctx.rank(b) or 99
    if ra ~= rb then return ra < rb end
    return a < b
  end)
  for _, n in ipairs(users) do add(n) end
  return out
end
function C.setCandidates(book, key, list)
  book.cand = book.cand or {}
  local idx = {}
  for i, n in ipairs(list or {}) do idx[n] = i end
  book.cand[key] = idx
end
local function place(book, key, n) return book.cand and book.cand[key] and book.cand[key][n] end
function C.claimed(book, key)
  local c = book[key]
  if type(c) ~= "table" or not c.names then return false end
  for n in pairs(c.names) do if place(book, key, n) then return true end end
  return false
end
function C.claimWinner(book, key)
  local c = book[key]
  if type(c) ~= "table" or not c.names then return nil end
  local best, bp
  for n in pairs(c.names) do
    local p = place(book, key, n)
    if p and (not best or p < bp) then best, bp = n, p end
  end
  return best
end

function C.newQueue() return { items = {}, keys = {}, last = -1e9 } end

function C.enqueue(q, ev)
  if q.keys[ev.key] or #q.items >= C.MAX_QUEUE then return false end
  q.keys[ev.key] = true
  q.items[#q.items + 1] = ev
  return true
end

-- next message to send now, or nil. blocked = encounter / chat lockdown / disabled: nothing leaves.
function C.pump(q, now, blocked)
  while #q.items > 0 and type(q.items[1].at) == "number" and now - q.items[1].at > C.TTL do table.remove(q.items, 1) end
  if blocked or #q.items == 0 or now - q.last < C.GAP then return nil end
  q.last = now
  return table.remove(q.items, 1)
end

-- plain short text: no links, no escape sequences, capped length
function C.clean(text)
  text = tostring(text or ""):gsub("|", ""):gsub("[\r\n]", " ")
  if #text > C.MAX_LEN then text = text:sub(1, C.MAX_LEN) end
  return text
end

function C.text(fmt, ...)
  local ok, s = pcall(string.format, fmt, ...)
  return C.clean(ok and s or fmt)
end

return C
