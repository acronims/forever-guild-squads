-- Guild Squads (MIT) - Core/Progress.lua
-- Pure Lua (no WoW API). Rankings: MetricEvent schema, witness rule, daily dedupe, weights, normalisation,
-- cap per wipe, deterministic wipe ids (weekly reset, "W<n>"), seasons (named periods made of wipes) and addon
-- achievements. Every client computes the scores locally from replicated events; totals are never transmitted.
-- the weekly reset is a WIPE (stored with the legacy "season"/week ids); a SEASON is a named period (Temporada 1...).
--
-- MetricEvent (whitelisted fields only, see P.SCHEMA):
--   level: { t="level", who, ts, sid, lv }
--   boss:  { t="boss", who, ts, sid, inst, iid, it="party"|"raid", diff, enc, boss, gs, pres = {names} }
--   bg:    { t="bg", who, ts, sid, inst, win = 1|0, pres }      battleground result, needs >= 2 squad witnesses
--   hk:    { t="hk", who, ts, sid, n }                           honorable kills outside instances (self-reported)
--   cap:   { t="cap", who, ts, sid, n }                          Overlord captures (optional addon, self-reported)
local _, ns = ...
ns = ns or {}

local P = {}
ns.Progress = P
local Content = ns.Content

P.WITNESS_WINDOW = 180      -- seconds between two reports of the same kill
P.MIN_WITNESSES = 2
P.KEEP_SEASONS = 8          -- closed seasons kept (history)
P.RAID_FIRST_BONUS = 10
P.SQUAD_SIZE = 5

local floor, min, max = math.floor, math.min, math.max
local DAY, WEEK = 86400, 604800

-------------------------------------------------------------------------------
-- schema
-- type codes: s = string(max len), n = number, L = list of strings (max n, max len)
P.SCHEMA = {
  t = { "s", 8 }, who = { "s", 48 }, ts = { "n" }, sid = { "s", 80 }, lv = { "n" },
  inst = { "s", 64 }, iid = { "n" }, it = { "s", 8 }, diff = { "n" }, enc = { "n" }, boss = { "s", 64 },
  gs = { "n" }, pres = { "L", 40, 48 },
  win = { "n" }, n = { "n" },             -- bg result, hk / capture count
}
P.MAX_HK_PER_EVENT = 100     -- one hk event never carries more than this (anti-jump)
P.MAX_CAP_PER_EVENT = 20
P.BG_WIN, P.BG_LOSS = 10, 3
P.HK_PER_POINT = 5
P.CAP_POINTS = 2
P.LEVEL_GAP = 60          -- minimum seconds between two counted level-ups of one character

local function norm(s) return type(s) == "string" and s:lower():gsub("^%s+", ""):gsub("%s+$", "") or "" end

function P.eventId(ev)
  local tail
  if ev.t == "level" then tail = tostring(ev.lv)
  elseif ev.t == "bg" then tail = norm(ev.inst) .. "#" .. tostring(ev.win)
  elseif ev.t == "hk" or ev.t == "cap" then tail = tostring(ev.n)
  else tail = (ev.enc and ev.enc > 0) and tostring(ev.enc) or norm(ev.boss) end
  return ev.who .. "|" .. ev.t .. "|" .. tostring(floor(ev.ts)) .. "|" .. tail
end

-- returns a clean copy (unknown fields dropped) or nil, reason
function P.sanitize(ev)
  if type(ev) ~= "table" then return nil, "shape" end
  local out = {}
  for field, spec in pairs(P.SCHEMA) do
    local v, t = ev[field], spec[1]
    if v ~= nil then
      if t == "s" and type(v) == "string" then out[field] = v:sub(1, spec[2])
      elseif t == "n" and type(v) == "number" and v == v and v < 1e15 and v > -1e15 then out[field] = v
      elseif t == "L" and type(v) == "table" then
        local l = {}
        for i = 1, min(#v, spec[2]) do if type(v[i]) == "string" then l[#l + 1] = v[i]:sub(1, spec[3]) end end
        out[field] = l
      end
    end
  end
  if type(out.who) ~= "string" or out.who == "" or type(out.ts) ~= "number" or type(out.sid) ~= "string" or out.sid == "" then
    return nil, "shape"
  end
  out.ts = floor(out.ts)
  if out.ts < 0 then return nil, "ts" end   -- lower bound (an -inf/negative ts broke prune)
  if out.t == "level" then
    if type(out.lv) ~= "number" or out.lv < 2 or out.lv > 60 or out.lv ~= floor(out.lv) then return nil, "level" end
    out.inst, out.iid, out.it, out.diff, out.enc, out.boss, out.gs, out.pres = nil, nil, nil, nil, nil, nil, nil, nil
    out.win, out.n = nil, nil
  elseif out.t == "boss" then
    if out.it ~= "party" and out.it ~= "raid" then return nil, "instanceType" end
    if not ((out.enc and out.enc > 0) or (out.inst and out.boss)) then return nil, "shape" end
    out.lv, out.win, out.n = nil, nil, nil
    out.pres = out.pres or {}
  elseif out.t == "bg" then
    if out.win ~= 0 and out.win ~= 1 then return nil, "win" end
    out.inst = out.inst or "?"
    out.lv, out.iid, out.it, out.diff, out.enc, out.boss, out.gs, out.n = nil, nil, nil, nil, nil, nil, nil, nil
    out.pres = out.pres or {}
  elseif out.t == "hk" or out.t == "cap" then
    local mx = out.t == "hk" and P.MAX_HK_PER_EVENT or P.MAX_CAP_PER_EVENT
    if type(out.n) ~= "number" or out.n < 1 or out.n > mx or out.n ~= floor(out.n) then return nil, "count" end
    out.lv, out.inst, out.iid, out.it, out.diff, out.enc, out.boss, out.gs, out.pres, out.win =
      nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
  else
    return nil, "type"
  end
  return out
end

-- level events reported by the player are accepted when they match the guild roster level (+-1)
function P.acceptLevel(ev, rosterLevel)
  if type(rosterLevel) ~= "number" then return false end
  return math.abs(ev.lv - rosterLevel) <= 1
end

function P.newStore() return { events = {} } end

function P.add(store, ev)
  local clean, why = P.sanitize(ev)
  if not clean then return false, why end
  local id = P.eventId(clean)
  if store.events[id] then return false, "dup" end
  store.events[id] = clean
  return true, id
end

-------------------------------------------------------------------------------
-- time: realm time = Europe (CET/CEST). EU DST: last Sunday of March 01:00 UTC -> last Sunday of October 01:00 UTC.
function P.daysFromCivil(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = floor(y / 400)
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = floor((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end

function P.civilFromDays(z)
  z = z + 719468
  local era = floor(z / 146097)
  local doe = z - era * 146097
  local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
  local mp = floor((5 * doy + 2) / 153)
  local d = doy - floor((153 * mp + 2) / 5) + 1
  local m = mp < 10 and mp + 3 or mp - 9
  if m <= 2 then y = y + 1 end
  return y, m, d
end

local function lastSunday(y, m)
  local z = P.daysFromCivil(y, m, 31)
  return z - ((z + 4) % 7) -- 1970-01-01 was a Thursday (weekday 4, Sunday = 0)
end

function P.realmOffset(ts)
  local y = P.civilFromDays(floor(ts / DAY))
  local s = lastSunday(y, 3) * DAY + 3600
  local e = lastSunday(y, 10) * DAY + 3600
  if ts >= s and ts < e then return 7200 end
  return 3600
end

local function localTs(ts) return ts + P.realmOffset(ts) end
P.RESET_HOUR = 9
local ANCHOR = 6 * DAY + P.RESET_HOUR * 3600 -- 1970-01-07, a Wednesday, 09:00

-- the anchor follows the game's real weekly reset when the client tells us
-- (C_DateAndTime.GetSecondsUntilWeeklyReset); P.SHIFT = seconds between that reset and Wednesday 09:00 CET/CEST.
-- 0 (the default, and the fallback when the API is missing) = Wednesday 09:00 CET/CEST.
P.SHIFT = 0
function P.weekOf(ts) return floor((localTs(ts) - ANCHOR - P.SHIFT) / WEEK) end
function P.dayOf(ts) return floor((localTs(ts) - P.RESET_HOUR * 3600 - P.SHIFT) / DAY) end

-- kind "weekly" (default) or "monthly" (resets on day 1 at 09:00 realm time)
function P.seasonOf(ts, kind)
  if kind == "monthly" then
    local y, m = P.civilFromDays(P.dayOf(ts))
    return "M" .. (y * 12 + m - 1)
  end
  return "W" .. P.weekOf(ts)
end

function P.parseSeason(id)
  local k, n = tostring(id):match("^([WM])(%-?%d+)$")
  if not k then return nil end
  return k, tonumber(n)
end

function P.prevSeason(id, back)
  local k, n = P.parseSeason(id)
  if not k then return nil end
  return k .. (n - (back or 1))
end

-- realm-local start of a season: y, m, d, hour (for labels) and approximate UTC timestamp
function P.seasonStart(id)
  local k, n = P.parseSeason(id)
  if not k then return nil end
  local lt
  if k == "W" then lt = ANCHOR + n * WEEK
  else lt = P.daysFromCivil(floor(n / 12), n % 12 + 1, 1) * DAY + P.RESET_HOUR * 3600 end
  local y, m, d = P.civilFromDays(floor(lt / DAY))
  return y, m, d, lt - 3600
end

function P.seasonEnd(id)
  local nextId = P.prevSeason(id, -1)
  local _, _, _, ts = P.seasonStart(nextId)
  return ts
end

-------------------------------------------------------------------------------
-- WIPES: the weekly reset (Wednesday 09:00 realm time). Ids "W<n>" are the legacy weekly season ids, unchanged,
-- so older data keeps working. The functions above stay as compatibility aliases.
function P.wipeOf(ts) return "W" .. P.weekOf(ts) end
function P.prevWipe(id, back) return P.prevSeason(id, back) end
function P.wipeList(cur) return P.seasonList(cur) end
-- exact UTC start of a wipe (DST aware)
function P.wipeStartTs(id)
  local k, n = P.parseSeason(id)
  if k ~= "W" then return nil end
  local lt = ANCHOR + P.SHIFT + n * WEEK
  local t = lt - 7200
  if P.weekOf(t) ~= n then t = lt - 3600 end
  return t
end
function P.wipeEndTs(id) return P.wipeStartTs(P.prevWipe(id, -1)) end

-- shift that aligns wipes with the real weekly reset `now + secondsUntil`. Within 90 min of the CET anchor
-- (EU realms, DST edges) the CET anchor is kept, so EU wipe ids never move.
function P.weeklyShift(now, secondsUntil)
  if type(now) ~= "number" or type(secondsUntil) ~= "number" or secondsUntil < 0 or secondsUntil > WEEK then return 0 end
  local saved = P.SHIFT
  P.SHIFT = 0
  local nextReset = now + secondsUntil
  local expected = P.wipeStartTs("W" .. (P.weekOf(nextReset - 1) + 1))
  P.SHIFT = saved
  local diff = (nextReset - expected) % WEEK
  if diff > WEEK / 2 then diff = diff - WEEK end
  if math.abs(diff) <= 5400 then return 0 end
  return floor(diff / 900 + 0.5) * 900
end
P.wipeStart = P.seasonStart

-------------------------------------------------------------------------------
-- SEASONS (Temporadas): named periods aligned with Blizzard's. A wipe belongs to the season that contains
-- its start moment, so every wipe belongs to exactly one season. Season = { name, start, stop (0/nil = open) }.
-- Default: "Temporada 1" from 4-Nov-2026 09:00 CET (08:00 UTC), no end.
P.DEFAULT_SEASON_START = 1793779200

-- realm-local "YYYY-MM-DD HH:MM" <-> UTC ts
function P.formatDate(ts)
  if type(ts) ~= "number" then return "" end
  local lt = localTs(ts)
  local y, m, d = P.civilFromDays(floor(lt / DAY))
  local sec = lt - floor(lt / DAY) * DAY
  return ("%04d-%02d-%02d %02d:%02d"):format(y, m, d, floor(sec / 3600), floor((sec % 3600) / 60))
end
function P.parseDate(text)
  if type(text) ~= "string" then return nil end
  local y, m, d = text:match("^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)")
  if not y then return nil end
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if m < 1 or m > 12 or d < 1 or d > 31 then return nil end
  local hh, mm = text:match("(%d%d?):(%d%d)%s*$")
  hh, mm = tonumber(hh) or P.RESET_HOUR, tonumber(mm) or 0
  if hh > 23 or mm > 59 then return nil end
  local lt = P.daysFromCivil(y, m, d) * DAY + hh * 3600 + mm * 60
  local t = lt - 7200
  if P.realmOffset(t) ~= 7200 then t = lt - 3600 end
  return t
end

-- season config from GuildSettings fields (seasonName, seasonStart, seasonEnd, seasonsPast = { "start:end:name" })
function P.seasonCfg(s)
  s = s or {}
  local cur = { name = (type(s.seasonName) == "string" and s.seasonName ~= "") and s.seasonName or nil,
                start = tonumber(s.seasonStart) or P.DEFAULT_SEASON_START, stop = tonumber(s.seasonEnd) or 0 }
  local past = {}
  for _, e in ipairs(s.seasonsPast or {}) do
    local a, b, name = tostring(e):match("^(%-?%d+):(%-?%d+):(.*)$")
    if a then past[#past + 1] = { start = tonumber(a), stop = tonumber(b), name = name ~= "" and name or nil } end
  end
  table.sort(past, function(x, y) return x.start > y.start end) -- newest first
  return { current = cur, past = past }
end

-- GM "Nueva temporada": closes the current season at `now` and opens a new one. Returns the settings fields.
P.KEEP_PAST_SEASONS = 8
function P.newSeason(s, now, name)
  local cfg = P.seasonCfg(s)
  local cur = cfg.current
  local past = {}
  local closeAt = now
  if cur.start > now then closeAt = cur.start end -- closing a season that never started: empty period
  past[1] = ("%d:%d:%s"):format(cur.start, closeAt, cur.name or "")
  for i, e in ipairs(cfg.past) do
    if i < P.KEEP_PAST_SEASONS then past[#past + 1] = ("%d:%d:%s"):format(e.start, e.stop or 0, e.name or "") end
  end
  return { seasonName = name or "", seasonStart = closeAt, seasonEnd = 0, seasonsPast = past }
end

-- wipe ids of a season, oldest first, up to the wipe containing `now`
function P.seasonWipes(season, now)
  local out = {}
  if not season or type(season.start) ~= "number" then return out end
  local stop = (season.stop and season.stop > 0) and season.stop or nil
  local limit = now or season.start
  if stop and stop < limit + 1 then limit = stop - 1 end
  local first = P.weekOf(season.start)
  if P.wipeStartTs("W" .. first) < season.start then first = first + 1 end
  local last = P.weekOf(limit)
  first = math.max(first, last - 103)   -- the 104 most RECENT wipes of an open season
  for n = first, last do
    local st = P.wipeStartTs("W" .. n)
    if st >= season.start and (not stop or st < stop) and st <= limit then out[#out + 1] = "W" .. n end
    if #out >= 104 then break end
  end
  return out
end

-- season score: sum over its wipes of each wipe's (already capped) score
local SUM_FIELDS = { "level", "dungeon", "raid", "pvp", "wpvp", "general", "levels", "dKills", "rKills", "bonus",
                     "bgW", "bgL", "hk", "caps" }
function P.seasonScore(events, season, now, opts)
  local wipes = P.seasonWipes(season, now)
  local out = { squads = {}, wipes = wipes }
  for _, w in ipairs(wipes) do
    local o = {}
    for k, v in pairs(opts or {}) do o[k] = v end
    o.season, o.kind = w, "weekly"
    local sums = P.summaries(events, w)
    local r = sums and { squads = sums } or (opts and opts.computeWipe) and opts.computeWipe(w) or P.compute(events, o)
    for sid, x in pairs(r.squads) do
      local acc = out.squads[sid]
      if not acc then
        acc = { active = 0, div = 3, raw = {}, capped = {}, nWipes = 0 }
        for _, f in ipairs(SUM_FIELDS) do acc[f] = 0 end
        out.squads[sid] = acc
      end
      for _, f in ipairs(SUM_FIELDS) do acc[f] = acc[f] + (x[f] or 0) end
      acc.active, acc.div = max(acc.active, x.active or 0), max(acc.div, x.div or 3)
      for c in pairs(x.capped or {}) do acc.capped[c] = true end
      acc.nWipes = acc.nWipes + 1
    end
  end
  return out
end

-- Membership per wipe: a member who leaves takes away ONLY their contributions of the CURRENT wipe.
-- Closed wipes use the membership snapshot taken while that wipe was current (the last one = membership at close).
-- snap = { [wipeId] = { [sid] = { [name] = true } } }. A wipe without snapshot (old data, client offline the whole
-- wipe) falls back to the current membership.
P.KEEP_SNAPSHOTS = 10
function P.snapshot(snap, wipe, sid, names)
  snap[wipe] = snap[wipe] or {}
  local set = {}
  for _, n in ipairs(names or {}) do set[n] = true end
  snap[wipe][sid] = set
  local _, cur = P.parseSeason(wipe)
  for w in pairs(snap) do
    local _, n = P.parseSeason(w)
    if not n or n < cur - P.KEEP_SNAPSHOTS then snap[w] = nil end
  end
end
-- returns isMember(sid, name, ts) honouring the rule above
function P.memberAt(snap, isMemberNow, now)
  local curWipe = P.wipeOf(now)
  return function(sid, name, ts)
    local w = ts and P.wipeOf(ts) or curWipe
    if w ~= curWipe then
      local s = snap and snap[w]
      if s and s[sid] then return s[sid][name] == true end
    end
    return isMemberNow(sid, name) and true or false
  end
end

-- PvP helpers ----------------------------------------------------------------
-- winner: GetBattlefieldWinner() (0 = Horde, 1 = Alliance) ; faction: UnitFactionGroup("player")
function P.bgOutcome(winner, faction)
  if winner == nil or (faction ~= "Horde" and faction ~= "Alliance") then return nil end
  if winner == 0 then return faction == "Horde" and 1 or 0 end
  if winner == 1 then return faction == "Alliance" and 1 or 0 end
  return nil -- draw / unknown
end

-- honorable-kill (or capture) counter step. state = { who, v, inst } ; returns delta (>= 0), new state.
-- No points: first reading, other character, counter went down (reset), suspicious jump, or the previous
-- reading was inside an instance (the kills of that interval happened in a BG/dungeon).
P.HK_MAX_JUMP = 60
function P.counterStep(state, who, value, inInstance, maxJump)
  local new = { who = who, v = value, inst = inInstance and true or false }
  if type(value) ~= "number" or value ~= value then return 0, state end
  if type(state) ~= "table" or state.who ~= who or type(state.v) ~= "number" then return 0, new end
  local d = value - state.v
  if d <= 0 then return 0, new end
  if d > (maxJump or P.HK_MAX_JUMP) then return 0, new end
  if state.inst then return 0, new end
  return d, new
end

-- Overlord (optional, read-only): own captures from Overlord.Leaderboard:GetMaxCapturesForDedupName(name).
-- Never calls anything else on Overlord. Returns a number or nil.
function P.overlordCaptures(ov, name)
  if type(ov) ~= "table" then return nil end
  local lb = ov.Leaderboard
  if type(lb) ~= "table" or type(lb.GetMaxCapturesForDedupName) ~= "function" then return nil end
  local okC, v = pcall(lb.GetMaxCapturesForDedupName, lb, name)
  if okC and type(v) == "number" and v == v and v >= 0 then return floor(v) end
  return nil
end
-- the "Recomendado: Overlord Forever" hint: only when Overlord is missing, the GM option is on and not dismissed
function P.overlordHint(present, enabled, dismissed)
  return (not present) and enabled ~= false and not dismissed
end

-------------------------------------------------------------------------------
-- witnesses: a boss kill counts for a squad only when >= 2 squad members report the same encounter
-- (same encounterID, or same boss + instance name) within WITNESS_WINDOW seconds.
local function killKey(ev)
  if ev.t == "bg" then return "b" .. norm(ev.inst) .. "#" .. tostring(ev.win) end
  if ev.enc and ev.enc > 0 then return "e" .. ev.enc end
  return "n" .. norm(ev.inst) .. "|" .. norm(ev.boss)
end
P.killKey = killKey

local function sortedEvents(list)
  table.sort(list, function(a, b)
    if a.ts ~= b.ts then return a.ts < b.ts end
    if a.who ~= b.who then return a.who < b.who end
    if (a.lv or 0) ~= (b.lv or 0) then return (a.lv or 0) < (b.lv or 0) end  -- deterministic order
    return tostring(a.t) < tostring(b.t)
  end)
  return list
end

-- events: list (or id->event map) of sanitized events. opts.isMember(sid, name) optional, opts.t = "boss"|"bg".
-- returns list of kills { sid, key, ts, day, week, inst, it, iid, boss, enc, present, names, witnesses }
function P.kills(events, opts)
  opts = opts or {}
  local isMember = opts.isMember
  local want = opts.t or "boss"
  local groups = {}
  for _, ev in pairs(events) do
    if ev.t == want and (not isMember or isMember(ev.sid, ev.who, ev.ts)) then
      local g = ev.sid .. "#" .. killKey(ev)
      groups[g] = groups[g] or {}
      table.insert(groups[g], ev)
    end
  end
  local out = {}
  for _, list in pairs(groups) do
    sortedEvents(list)
    local i = 1
    while i <= #list do
      local first = list[i]
      local reporters, names, n = {}, {}, 0
      local claims = {}
      local j = i
      while j <= #list and list[j].ts - first.ts <= P.WITNESS_WINDOW do
        local ev = list[j]
        if not reporters[ev.who] then reporters[ev.who] = true; n = n + 1; claims[#claims + 1] = { inst = ev.inst, it = ev.it, iid = ev.iid } end
        names[ev.who] = true
        for _, p in ipairs(ev.pres or {}) do if not isMember or isMember(ev.sid, p, ev.ts) then names[p] = true end end
        j = j + 1
      end
      if n >= P.MIN_WITNESSES then
        local count, nl = 0, {}
        for nm in pairs(names) do count = count + 1; nl[#nl + 1] = nm end
        table.sort(nl)
        out[#out + 1] = { sid = first.sid, key = killKey(first), ts = first.ts, day = P.dayOf(first.ts), week = P.weekOf(first.ts),
                          inst = first.inst, it = first.it, win = first.win, iid = first.iid, boss = first.boss, enc = first.enc,
                          present = min(P.SQUAD_SIZE, count), names = nl, witnesses = n, claims = claims }
      end
      i = j
    end
  end
  table.sort(out, function(a, b) if a.ts ~= b.ts then return a.ts < b.ts end return a.sid < b.sid end)
  return out
end

-- each boss counts once per squad and (realm) day
function P.dedupeDaily(kills)
  local seen, out = {}, {}
  for _, k in ipairs(kills) do
    local id = k.sid .. "#" .. k.key .. "#" .. k.day
    if not seen[id] then seen[id] = true; out[#out + 1] = k end
  end
  return out
end

-- the weight is the consensus of the witnesses = the LOWEST weight among their claims, and remote
-- reports never teach the catalog (noLearn)
local function contentOf(k)
  local e
  for _, c in ipairs(k.claims or { k }) do
    local x = Content and Content.match(c.inst, c.it, c.iid, true)
    if x and (not e or (x.weight or 1) < (e.weight or 1)) then e = x end
  end
  local kind = (k.it == "raid" or (e and e.kind == "raid")) and "raid" or "dungeon"
  return kind, e
end
P.contentOf = contentOf

-------------------------------------------------------------------------------
-- scoring
P.DEFAULTS = { weights = { level = 1, dungeon = 1, raid = 1, pvp = 1, wpvp = 1 }, cap = 100, kind = "weekly" }
P.SCORED = { "level", "dungeon", "raid", "pvp", "wpvp" }   -- 5 categories, cap 100 each per wipe = max 500
P.CATEGORIES = { "level", "dungeon", "raid", "pvp", "wpvp", "general" }

local function bucket(t, sid, cat, week, v)
  local s = t[sid]
  if not s then
    s = { raw = { level = {}, dungeon = {}, raid = {}, pvp = {}, wpvp = {} }, active = {}, levels = 0, dKills = 0,
          rKills = 0, bonus = 0, bgW = 0, bgL = 0, hk = 0, caps = 0 }
    t[sid] = s
  end
  if cat then s.raw[cat][week] = (s.raw[cat][week] or 0) + v end
  return s
end

-- opts = { season = id, kind, weights, cap, isMember }
function P.compute(events, opts)
  opts = opts or {}
  local kind = opts.kind or P.DEFAULTS.kind
  local season = opts.season
  if season then
    local sums = P.summaries(events, season)
    if sums then return { squads = sums, kills = {}, summary = true } end   -- pruned wipe
  end
  local w = opts.weights or P.DEFAULTS.weights
  local cap = opts.cap or P.DEFAULTS.cap
  local isMember = opts.isMember
  local inSeason = {}
  for _, ev in pairs(events) do
    if not season or P.seasonOf(ev.ts, kind) == season then inSeason[#inSeason + 1] = ev end
  end
  local sq = {}
  -- leveling: 1 per level gained, milestones 10/20/.../60 +2.
  -- a character cannot gain two levels within LEVEL_GAP seconds; a burst of back-dated level
  -- events (same ts) scores once.
  local seenLv, lastLv = {}, {}
  for _, ev in ipairs(sortedEvents(inSeason)) do
    if ev.t == "level" and (not isMember or isMember(ev.sid, ev.who, ev.ts)) and not seenLv[ev.who .. "#" .. ev.lv]
       and not (lastLv[ev.who] and ev.ts - lastLv[ev.who] < P.LEVEL_GAP) then
      seenLv[ev.who .. "#" .. ev.lv] = true
      lastLv[ev.who] = ev.ts
      local pts = 1 + ((ev.lv % 10 == 0) and 2 or 0)
      local s = bucket(sq, ev.sid, "level", P.weekOf(ev.ts), pts)
      s.levels = s.levels + 1
      s.active[ev.who] = true
    elseif ev.t == "boss" and (not isMember or isMember(ev.sid, ev.who, ev.ts)) then
      bucket(sq, ev.sid).active[ev.who] = true
    end
  end
  -- world PvP: honorable kills per member and wipe -> 1 point per 5 ; Overlord captures 2 points each
  local hkBy = {}
  for _, ev in ipairs(inSeason) do
    if (ev.t == "hk" or ev.t == "cap") and (not isMember or isMember(ev.sid, ev.who, ev.ts)) then
      local s = bucket(sq, ev.sid)
      s.active[ev.who] = true
      if ev.t == "hk" then
        local k = ev.sid .. "#" .. ev.who .. "#" .. P.weekOf(ev.ts)
        hkBy[k] = hkBy[k] or { sid = ev.sid, week = P.weekOf(ev.ts), n = 0 }
        hkBy[k].n = hkBy[k].n + ev.n
        s.hk = s.hk + ev.n
      else
        bucket(sq, ev.sid, "wpvp", P.weekOf(ev.ts), ev.n * P.CAP_POINTS)
        s.caps = s.caps + ev.n
      end
    end
  end
  for _, h in pairs(hkBy) do
    local pts = floor(h.n / P.HK_PER_POINT)
    if pts > 0 then bucket(sq, h.sid, "wpvp", h.week, pts) end
  end
  -- witnesses are grouped over ALL events and the kill belongs to the wipe of its first report,
  -- so two reports straddling the 09:00 reset still make one witnessed kill
  local function inThis(list)
    if not season then return list end
    local out = {}
    for _, k in ipairs(list) do if P.seasonOf(k.ts, kind) == season then out[#out + 1] = k end end
    return out
  end
  -- battlegrounds: witnessed (>= 2 squad members, 180 s) result, once per match
  for _, k in ipairs(inThis(P.kills(events, { isMember = isMember, t = "bg" }))) do
    local s = bucket(sq, k.sid, "pvp", k.week, k.win == 1 and P.BG_WIN or P.BG_LOSS)
    if k.win == 1 then s.bgW = s.bgW + 1 else s.bgL = s.bgL + 1 end
    for _, n in ipairs(k.names) do s.active[n] = true end
  end
  -- bosses
  local kills = inThis(P.dedupeDaily(P.kills(events, { isMember = isMember })))
  local firstRaid = {}
  for _, k in ipairs(kills) do
    local cat, e = contentOf(k)
    local s
    if cat == "raid" then
      s = bucket(sq, k.sid, "raid", k.week, 5 * k.present / P.SQUAD_SIZE)
      s.rKills = s.rKills + 1
      local f = firstRaid[k.key]
      if not f then firstRaid[k.key] = { ts = k.ts, cands = { k } }
      elseif k.ts - f.ts <= P.WITNESS_WINDOW then f.cands[#f.cands + 1] = k end
    else
      s = bucket(sq, k.sid, "dungeon", k.week, (e and e.weight) or 1)
      s.dKills = s.dKills + 1
    end
    for _, n in ipairs(k.names) do s.active[n] = true end
  end
  -- first guild kill of a raid boss in the season: +10 to the squad with most members present
  for _, f in pairs(firstRaid) do
    local best
    for _, k in ipairs(f.cands) do
      if not best or k.present > best.present or (k.present == best.present and k.sid < best.sid) then best = k end
    end
    local s = bucket(sq, best.sid, "raid", best.week, P.RAID_FIRST_BONUS)
    s.bonus = s.bonus + P.RAID_FIRST_BONUS
  end
  -- normalise and cap per week
  local result = { squads = {}, kills = kills }
  for sid, s in pairs(sq) do
    local active = 0
    for _ in pairs(s.active) do active = active + 1 end
    local div = max(3, active)
    local r = { active = active, div = div, levels = s.levels, dKills = s.dKills, rKills = s.rKills, bonus = s.bonus,
                bgW = s.bgW, bgL = s.bgL, hk = s.hk, caps = s.caps, raw = {}, capped = {} }
    for _, cat in ipairs(P.SCORED) do
      local total, rawT = 0, 0
      for _, v in pairs(s.raw[cat]) do
        rawT = rawT + v
        local n = v / div
        if n > cap then n = cap; r.capped[cat] = true end
        total = total + n
      end
      r[cat], r.raw[cat] = total, rawT
    end
    r.general = 0
    for _, cat in ipairs(P.SCORED) do r.general = r.general + (w[cat] or 1) * r[cat] end
    result.squads[sid] = r
  end
  return result
end

-- sorted list { sid, points, pos } for a category; squads with 0 points are kept (after the others)
function P.ranking(result, cat, squadIds)
  local list = {}
  local seen = {}
  for sid, r in pairs(result.squads) do
    if not squadIds or squadIds[sid] then list[#list + 1] = { sid = sid, points = r[cat] or 0, r = r }; seen[sid] = true end
  end
  for sid in pairs(squadIds or {}) do if not seen[sid] then list[#list + 1] = { sid = sid, points = 0 } end end
  table.sort(list, function(a, b) if a.points ~= b.points then return a.points > b.points end return a.sid < b.sid end)
  for i, e in ipairs(list) do e.pos = i end
  return list
end

-- what the screens show - only squads with points, positions 1..n among them (0-point squads get no
-- position and no trend)
function P.scored(result, cat, squadIds)
  local out = {}
  for _, e in ipairs(P.ranking(result, cat, squadIds)) do
    if (e.points or 0) > 0 then out[#out + 1] = e; e.pos = #out end
  end
  return out
end

-- witnessed, deduped boss kills of all squads in the realm week containing ts (guild goal bar)
function P.weekKills(events, ts, opts)
  local wk = P.weekOf(ts)
  local n = 0
  for _, k in ipairs(P.dedupeDaily(P.kills(events, opts))) do if k.week == wk then n = n + 1 end end
  return n
end

-- before dropping the events of a closed wipe, its result (per squad, already capped) is kept as
-- a summary entry { t = "sum", wipe, sid, ts, r = {fields} } inside store.events, and seasonScore uses it.
P.KEEP_SUMMARIES = 160
P.SUM_FIELDS = { "level", "dungeon", "raid", "pvp", "wpvp", "general", "levels", "dKills", "rKills", "bonus",
                 "bgW", "bgL", "hk", "caps", "active", "div" }
function P.summaries(events, wipe)
  local out, any = {}, false
  for _, ev in pairs(events) do
    if ev.t == "sum" and ev.wipe == wipe then out[ev.sid] = ev.r; any = true end
  end
  return any and out or nil
end
function P.isSummary(ev) return type(ev) == "table" and ev.t == "sum" end

-- canonical wipe summary. A pure function of the wipe's events: they are deduplicated by
-- P.eventId, sorted by (ts, id) and every number is rounded the same way, so two clients holding the
-- same events produce identical summaries (and hashes) whatever the order they received them in. The values are
-- kept exact (the season total adds them up); the canonical text / hash rounds every number to 6 decimals.
local function roundSum(x) if type(x) ~= "number" then return x end return floor(x * 1000000 + 0.5) / 1000000 end
P.roundSum = roundSum
function P.wipeEvents(events, wipe, kind)
  local byId, ids = {}, {}
  for _, ev in pairs(events) do
    if type(ev) == "table" and ev.t ~= "sum" and type(ev.ts) == "number" and ev.who
       and P.seasonOf(ev.ts, kind or "weekly") == wipe then
      local id = P.eventId(ev)
      if not byId[id] then byId[id] = ev; ids[#ids + 1] = id end
    end
  end
  table.sort(ids, function(a, b)
    local x, y = byId[a], byId[b]
    if x.ts ~= y.ts then return x.ts < y.ts end
    return a < b
  end)
  local list = {}
  for i, id in ipairs(ids) do list[i] = byId[id] end
  return list
end
-- membership taken from the RECORDS themselves, never from the local squad
-- snapshot. `name` belongs to `sid` for this wipe when one of their own events of the wipe is tagged with that sid
-- (signed by them), or when their profile record says so and was written before the wipe ended (profiles =
-- name -> profile record { ts, d = { squad } }). Same events + same records -> same membership on every client.
-- with `squads` (sid -> squad record) the captain's side of the double consent is required
-- too: the squad record must list the name (captain, members or bench). A pending request (profile only) is not a
-- member, and its tagged events do not count either. Without `squads` (old callers) the profile-only rule applies.
local function listedIn(sq, name)
  local d = type(sq) == "table" and sq.d
  if type(d) ~= "table" or d.disbanded then return false end
  if d.captain == name then return true end
  for _, f in ipairs({ "members", "bench" }) do
    for _, n in ipairs(type(d[f]) == "table" and d[f] or {}) do if n == name then return true end end
  end
  return false
end
function P.recordMember(list, profiles, wipe, squads)
  local tagged = {}
  for _, ev in ipairs(list or {}) do
    if type(ev.who) == "string" and type(ev.sid) == "string" then tagged[ev.sid .. "\1" .. ev.who] = true end
  end
  local stop = P.wipeEndTs and wipe and P.wipeEndTs(wipe) or nil
  local captainOk = function() return true end
  -- the captain's side only binds when the squad record predates the end of the wipe
  -- (it is the membership that was valid in that wipe). A record edited or disbanded after the wipe says nothing
  -- about that wipe -> the profile-only rule (own tagged events / profile older than the end) applies, so leaving or
  -- disbanding later never erases history, and every client gets the same result whenever it summarises.
  if type(squads) == "table" then
    captainOk = function(sid, name)
      local sq = squads[sid]
      if type(sq) ~= "table" or type(sq.d) ~= "table" then return false end
      if sq.d.disbanded then return true end
      if stop and type(sq.ts) == "number" and sq.ts >= stop then return true end
      return listedIn(sq, name)
    end
  end
  return function(sid, name)
    if not captainOk(sid, name) then return false end
    if tagged[tostring(sid) .. "\1" .. tostring(name)] then return true end
    local p = type(profiles) == "table" and profiles[name] or nil
    if type(p) == "table" and type(p.d) == "table" and p.d.squad == sid and type(p.ts) == "number" then
      return stop == nil or p.ts < stop
    end
    return false
  end
end

-- returns sums (sid -> r with P.SUM_FIELDS + capped), number of canonical events.
-- opts.isMember is ignored on purpose: opts.profiles (the profile records) is used instead.
function P.wipeSummary(events, wipe, opts)
  local list = P.wipeEvents(events, wipe, "weekly")
  local o = {}
  for k, v in pairs(opts or {}) do o[k] = v end
  o.season, o.kind = wipe, "weekly"
  o.isMember = P.recordMember(list, o.profiles, wipe, o.squads)
  o.profiles, o.squads = nil, nil
  local r = P.compute(list, o)
  local sums = {}
  for sid, x in pairs(r.squads) do
    local keep = { capped = {} }
    for _, f in ipairs(P.SUM_FIELDS) do keep[f] = x[f] end
    for c in pairs(x.capped or {}) do keep.capped[c] = true end
    sums[sid] = keep
  end
  return sums, #list
end
-- canonical text of a summary (sorted squads, fixed field order, fixed number format) and its short hash
function P.summaryText(sums)
  local sids = {}
  for sid in pairs(sums or {}) do sids[#sids + 1] = sid end
  table.sort(sids)
  local parts = {}
  for _, sid in ipairs(sids) do
    local r, f = sums[sid], {}
    for i, k in ipairs(P.SUM_FIELDS) do
      local v = r[k]
      f[i] = type(v) == "number" and string.format("%.6f", roundSum(v)) or ""
    end
    local caps = {}
    for c in pairs(r.capped or {}) do caps[#caps + 1] = c end
    table.sort(caps)
    parts[#parts + 1] = sid .. "=" .. table.concat(f, ",") .. "/" .. table.concat(caps, ",")
  end
  return table.concat(parts, ";")
end
function P.summaryHash(sums)
  local text = P.summaryText(sums)
  local S = ns.Serialize
  if S and S.hash then return tostring(S.hash(text)):sub(1, 12) end
  local h = 0
  for i = 1, #text do h = (h * 31 + text:byte(i)) % 2147483647 end
  return tostring(h)
end
-- summary entries of a wipe stored in `events`: { sums, n, hash } or nil
function P.storedSummary(events, wipe)
  local sums, n = P.summaries(events, wipe), 0
  if not sums then return nil end
  for _, ev in pairs(events) do
    if ev.t == "sum" and ev.wipe == wipe and type(ev.n) == "number" and ev.n > n then n = ev.n end
  end
  return { sums = sums, n = n, hash = P.summaryHash(sums) }
end
-- replace the stored summary of a wipe (from P.wipeSummary or from a peer)
function P.setSummary(store, wipe, sums, n)
  for id, ev in pairs(store.events) do if ev.t == "sum" and ev.wipe == wipe then store.events[id] = nil end end
  local ts = P.wipeStartTs(wipe) + 1
  for sid, r in pairs(sums) do
    store.events["~sum|" .. wipe .. "|" .. sid] = { t = "sum", wipe = wipe, sid = sid, ts = ts, r = r, n = n or 0 }
  end
end
-- two clients disagree on a wipe: the one holding MORE events of that wipe is right; on a tie the smaller hash
-- wins (deterministic). Returns true when the peer's summary should replace ours.
function P.peerSummaryWins(mine, theirN, theirHash)
  if type(theirN) ~= "number" or type(theirHash) ~= "string" then return false end
  if not mine then return true end
  if mine.hash == theirHash then return false end
  if theirN ~= mine.n then return theirN > mine.n end
  return theirHash < mine.hash
end

-- drop events older than KEEP_SEASONS closed seasons (weekly kind: summarised first)
function P.prune(store, currentSeason, kind, opts)
  local k0, n0 = P.parseSeason(currentSeason)
  if not k0 then return 0 end
  local removed = 0
  local doomed = {}
  for id, ev in pairs(store.events) do
    if ev.t == "sum" then
      local _, n = P.parseSeason(ev.wipe)
      if n and n < n0 - P.KEEP_SUMMARIES then store.events[id] = nil end
    else
      local w = P.seasonOf(ev.ts, kind)
      local _, n = P.parseSeason(w)
      if not n then store.events[id] = nil; removed = removed + 1   -- unparseable (non-finite ts) -> drop
      elseif n < n0 - P.KEEP_SEASONS then doomed[w] = true end
    end
  end
  for w in pairs(doomed) do
    if (kind or "weekly") == "weekly" and not P.summaries(store.events, w) then
      local sums, n = P.wipeSummary(store.events, w, opts)   -- canonical, replicable
      P.setSummary(store, w, sums, n)
    end
  end
  for id, ev in pairs(store.events) do
    if ev.t ~= "sum" and doomed[P.seasonOf(ev.ts, kind)] then store.events[id] = nil; removed = removed + 1 end
  end
  return removed
end

-- current season + the last KEEP_SEASONS ones, newest first
function P.seasonList(currentSeason)
  local out = { currentSeason }
  for i = 1, P.KEEP_SEASONS do out[#out + 1] = P.prevSeason(currentSeason, i) end
  return out
end

-------------------------------------------------------------------------------
-- achievements (dated). scope "squad" or "char".
P.ACHIEVEMENTS = {
  { key = "first60", scope = "squad" }, { key = "squad60", scope = "squad" }, { key = "firstDungeon", scope = "squad" },
  { key = "forever", scope = "squad" }, { key = "boss10", scope = "squad", n = 10 }, { key = "boss50", scope = "squad", n = 50 },
  { key = "boss100", scope = "squad", n = 100 }, { key = "firstRaid", scope = "squad" }, { key = "sotw", scope = "squad" },
  { key = "guildFirst60", scope = "char" },
  -- ("sotw" is shown as "Squad del wipe"; the key name is kept for stored data)
  { key = "sots", scope = "squad" }, { key = "firstBg", scope = "squad" }, { key = "hk100", scope = "squad", n = 100 },
  { key = "conq", scope = "squad", n = 10 },
}

local function setAch(t, owner, key, ts)
  t[owner] = t[owner] or {}
  if not t[owner][key] or ts < t[owner][key] then t[owner][key] = ts end
end

-- ctx = { now, kind, weights, cap, isMember, members = fn(sid) -> titular names, levelOf = fn(name) }
-- returns { squad = { [sid] = { [key] = ts } }, char = { [name] = { [key] = ts } } }
function P.achievements(events, ctx)
  ctx = ctx or {}
  local out = { squad = {}, char = {} }
  local list = {}
  for _, ev in pairs(events) do list[#list + 1] = ev end
  sortedEvents(list)
  -- level 60s
  local first60, at60 = nil, {}
  for _, ev in ipairs(list) do
    if ev.t == "level" and ev.lv == 60 and (not ctx.isMember or ctx.isMember(ev.sid, ev.who, ev.ts)) then
      if not first60 then first60 = ev end
      at60[ev.who] = at60[ev.who] or ev.ts
      setAch(out.squad, ev.sid, "first60", ev.ts)
    end
  end
  if first60 then setAch(out.char, first60.who, "guildFirst60", first60.ts) end
  if ctx.members and ctx.levelOf then
    local sids = {}
    for _, ev in ipairs(list) do sids[ev.sid] = true end
    for sid in pairs(sids) do
      local mem = ctx.members(sid) or {}
      if #mem >= P.SQUAD_SIZE then
        local all, last = true, 0
        for i = 1, P.SQUAD_SIZE do
          local lv = ctx.levelOf(mem[i])
          if type(lv) ~= "number" or lv < 60 then all = false; break end
          last = max(last, at60[mem[i]] or ctx.now or 0)
        end
        if all then setAch(out.squad, sid, "squad60", last) end
      end
    end
  end
  -- bosses
  local kills = P.dedupeDaily(P.kills(list, { isMember = ctx.isMember }))
  local count, forever = {}, {}
  local need = Content and #Content.foreverDungeonKeys() or 9
  for _, k in ipairs(kills) do
    local cat, e = contentOf(k)
    count[k.sid] = (count[k.sid] or 0) + 1
    local n = count[k.sid]
    if n == 10 then setAch(out.squad, k.sid, "boss10", k.ts) end
    if n == 50 then setAch(out.squad, k.sid, "boss50", k.ts) end
    if n == 100 then setAch(out.squad, k.sid, "boss100", k.ts) end
    if cat == "raid" then setAch(out.squad, k.sid, "firstRaid", k.ts)
    else
      setAch(out.squad, k.sid, "firstDungeon", k.ts)
      if e and e.forever and e.kind == "dungeon" then
        local f = forever[k.sid] or { n = 0 }
        forever[k.sid] = f
        if not f[e.key] then
          f[e.key] = true; f.n = f.n + 1
          if f.n == need then setAch(out.squad, k.sid, "forever", k.ts) end
        end
      end
    end
  end
  -- PvP: first witnessed BG won together, 100 HK of the squad, 10 Overlord captures ("Conquistadores")
  for _, k in ipairs(P.kills(list, { isMember = ctx.isMember, t = "bg" })) do
    if k.win == 1 then setAch(out.squad, k.sid, "firstBg", k.ts) end
  end
  local hkSum, capSum = {}, {}
  for _, ev in ipairs(list) do
    if (ev.t == "hk" or ev.t == "cap") and (not ctx.isMember or ctx.isMember(ev.sid, ev.who, ev.ts)) then
      local t = ev.t == "hk" and hkSum or capSum
      t[ev.sid] = (t[ev.sid] or 0) + ev.n
      if ev.t == "hk" and t[ev.sid] >= 100 then setAch(out.squad, ev.sid, "hk100", ev.ts) end
      if ev.t == "cap" and t[ev.sid] >= 10 then setAch(out.squad, ev.sid, "conq", ev.ts) end
    end
  end
  -- squad of the season: first in the general ranking of every closed season (ctx.seasons = { {start, stop} })
  for _, season in ipairs(ctx.seasons or {}) do
    if season.stop and season.stop > 0 and ctx.now and season.stop <= ctx.now then
      local res = P.seasonScore(list, season, ctx.now, { weights = ctx.weights, cap = ctx.cap, isMember = ctx.isMember })
      local top = P.ranking(res, "general")[1]
      if top and top.points > 0 then setAch(out.squad, top.sid, "sots", season.stop) end
    end
  end
  -- squad of the wipe ("sotw"): first in the general ranking when a (closed) wipe ends
  if ctx.now then
    local cur = P.seasonOf(ctx.now, ctx.kind)
    local seasons = {}
    for _, ev in ipairs(list) do seasons[P.seasonOf(ev.ts, ctx.kind)] = true end
    for sid in pairs(seasons) do
      if sid ~= cur then
        local _, n = P.parseSeason(sid)
        local _, nc = P.parseSeason(cur)
        if n < nc then
          local res = P.compute(list, { season = sid, kind = ctx.kind, weights = ctx.weights, cap = ctx.cap, isMember = ctx.isMember })
          local top = P.ranking(res, "general")[1]
          if top and top.points > 0 then setAch(out.squad, top.sid, "sotw", P.seasonEnd(sid)) end
        end
      end
    end
  end
  return out
end

-- progress towards every squad achievement, for the tooltips ("3/9 mazmorras", "62/100 HK").
-- achievementProgress(sid, events, ctx) -> { [key] = { cur = n, need = n, unit = "boss"|"dungeon"|"hk"|"cap"|"member"|"done" } }
-- ctx as in P.achievements (isMember, members, levelOf). Counts are capped at `need`.
function P.achievementProgress(sid, events, ctx)
  ctx = ctx or {}
  local out = {}
  local list = {}
  for _, ev in pairs(events or {}) do if ev.sid == sid then list[#list + 1] = ev end end
  sortedEvents(list)
  local function put(key, cur, need, unit) out[key] = { cur = math.min(cur, need), need = need, unit = unit } end
  local kills = P.dedupeDaily(P.kills(list, { isMember = ctx.isMember }))
  local nKills, nDungeon, nRaid, forever = 0, 0, 0, {}
  local foreverN = 0
  for _, k in ipairs(kills) do
    if k.sid == sid then
      nKills = nKills + 1
      local cat, e = contentOf(k)
      if cat == "raid" then nRaid = nRaid + 1 else
        nDungeon = nDungeon + 1
        if e and e.forever and e.kind == "dungeon" and not forever[e.key] then forever[e.key] = true; foreverN = foreverN + 1 end
      end
    end
  end
  local need = Content and #Content.foreverDungeonKeys() or 9
  put("boss10", nKills, 10, "boss"); put("boss50", nKills, 50, "boss"); put("boss100", nKills, 100, "boss")
  put("forever", foreverN, need, "dungeon")
  put("firstDungeon", nDungeon > 0 and 1 or 0, 1, "done"); put("firstRaid", nRaid > 0 and 1 or 0, 1, "done")
  local hk, caps, lv60, bgWon = 0, 0, false, false
  for _, ev in ipairs(list) do
    if not ctx.isMember or ctx.isMember(ev.sid, ev.who, ev.ts) then
      if ev.t == "hk" then hk = hk + (ev.n or 0) elseif ev.t == "cap" then caps = caps + (ev.n or 0)
      elseif ev.t == "level" and ev.lv == 60 then lv60 = true end
    end
  end
  for _, k in ipairs(P.kills(list, { isMember = ctx.isMember, t = "bg" })) do if k.win == 1 then bgWon = true end end
  put("hk100", hk, 100, "hk"); put("conq", caps, 10, "cap")
  put("first60", lv60 and 1 or 0, 1, "done"); put("firstBg", bgWon and 1 or 0, 1, "done")
  if ctx.members and ctx.levelOf then
    local n = 0
    for _, name in ipairs(ctx.members(sid) or {}) do
      local lv = ctx.levelOf(name)
      if type(lv) == "number" and lv >= 60 then n = n + 1 end
    end
    put("squad60", n, P.SQUAD_SIZE, "member")
  end
  return out
end

-- keys newly present in `fresh` compared with `known` (both owner -> key -> ts); merges into known
function P.mergeAchievements(known, fresh)
  local new = {}
  for _, scope in ipairs({ "squad", "char", "guild" }) do -- + guild ("Toda la guild a bordo")
    if scope ~= "guild" or fresh.guild then known[scope] = known[scope] or {} end
    for owner, keys in pairs(known[scope] and fresh[scope] or {}) do
      known[scope][owner] = known[scope][owner] or {}
      for key, ts in pairs(keys) do
        local cur = known[scope][owner][key]
        if not cur then new[#new + 1] = { scope = scope, owner = owner, key = key, ts = ts } end
        if not cur or ts < cur then known[scope][owner][key] = ts end
      end
    end
  end
  return new
end

-- SQ flood guard. At most one SQ every 30 s per sender (the rest dropped), and
-- no reply when this requester was already served this summary (same wipe + hash). gate = {} kept by the glue.
P.SQ_GAP = 30
function P.sqGate(gate, from, w, hash, now)
  if type(gate) ~= "table" or type(from) ~= "string" or type(now) ~= "number" then return false end
  gate.last = gate.last or {}
  gate.served = gate.served or {}
  if gate.last[from] and now - gate.last[from] < P.SQ_GAP then return false end
  gate.last[from] = now
  local key = from .. "|" .. tostring(w) .. "|" .. tostring(hash)
  if gate.served[key] then return false end
  gate.served[key] = true
  return true
end

return P
