-- Guild Squads (MIT) - Core/Roster.lua
-- Pure Lua. Raid rosters of 10 / 20 / 40 built from squads, RSVP, attendance, weekly templates, the
-- one-click invite plan (with an injected API) and the Discord export. No client API is touched here.
--
-- Records (signed, validated by Model.apply through Model.registerKind):
--   roster     id = owner .. ":" .. ts       data = see M.SCHEMA.roster below. Only the owner (while RL/officer),
--                                            the GM, or officers when the GM allows it ("offEdit") may write it.
--   rsvp       id = rid .. "|" .. name       written only by `name` itself; last writer wins.
--   attendance id = rid                      written by whoever may edit the roster (RL/GM), only once the roster is
--                                            closed and up to 7 days after the close; never empty.
--   witness    id = rid .. "#" .. author     what a member who was in the raid saw (author among the names).
--                                            Final attendance = official record + names reported by >= 2 witnesses.
--
-- convergence: roster versions are ordered by (state rank, LWW) with draft < published < closed/cancelled,
-- so a close beats any edit whatever its ts and the arrival order never changes the result.
--
-- Time: `at` is the realm WALL CLOCK encoded as if it were UTC (R.civil). Adding 7 days keeps 20:00 at 20:00
-- across a daylight-saving change; R.wallToEpoch converts to a real timestamp with the realm offset of that moment.
local _, ns = ...
ns = ns or {}

local R = {}
ns.Roster = R
local P, M = ns.Permissions, ns.Model

R.SIZES = { 10, 20, 40 }
R.MAX_BENCH = 10
R.MAX_COMMENT = 60
R.STATES = { "draft", "published", "closed", "cancelled" }
R.NEXT = { draft = { published = true, cancelled = true }, published = { closed = true, cancelled = true },
           closed = {}, cancelled = {} }
R.ANSWERS = { "yes", "maybe", "no", "bench" }
R.ROLES = { "TANK", "HEALER", "DAMAGER" }
R.ROLE_SHORT = { TANK = "T", HEALER = "H", DAMAGER = "D" }
R.WEEK = 7 * 86400
R.CLOSE_AFTER = 3 * 3600      -- attendance closes automatically 3 h after the start
R.REMIND_BEFORE = 3600        -- in-addon reminder 1 h before
R.WINDOW_BEFORE = 1800        -- attendance window opens 30 min before the start
R.STATS_LAST = 8
R.FIX_DAYS = 7 * 86400        -- the RL / GM may sign or correct the attendance up to 7 days after the close
R.PRUNE_AFTER = 8 * R.WEEK    -- closed/cancelled rosters older than 8 weeks lose their RSVPs
R.INVITE_WAIT = 60            -- a pending invite is not repeated for 60 s
R.RANK = { draft = 1, published = 2, closed = 3, cancelled = 3 }
local function terminal(st) return st == "closed" or st == "cancelled" end
R.terminal = terminal

-- composition proposals per size: { min, max } per role
R.TEMPLATES = {
  [10] = { TANK = { 2, 2 }, HEALER = { 2, 3 }, DAMAGER = { 5, 6 } },
  [20] = { TANK = { 2, 3 }, HEALER = { 4, 5 }, DAMAGER = { 12, 14 } },
  [40] = { TANK = { 4, 6 }, HEALER = { 8, 10 }, DAMAGER = { 24, 28 } },
}

-- useful classes per size (data, editable by the GM in settings.rutil as "key:CLASS+CLASS:minSize")
R.DEFAULT_UTIL = {
  { key = "decurse", classes = { "MAGE", "DRUID" }, min = 10 },
  { key = "dispel", classes = { "PRIEST", "PALADIN" }, min = 10 },
  { key = "fort", classes = { "PRIEST" }, min = 10 },
  { key = "int", classes = { "MAGE" }, min = 20 },
  { key = "motw", classes = { "DRUID" }, min = 20 },
  { key = "bless", classes = { "PALADIN", "SHAMAN" }, min = 20 },   -- paladin or shaman by faction
  { key = "summon", classes = { "WARLOCK" }, min = 20 },
  { key = "brez", classes = { "DRUID" }, min = 40 },
}

local function contains(list, v) return P.contains(list, v) end
local function oneOf(v, list) for _, x in ipairs(list) do if x == v then return true end end return false end
local function copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = copy(v) end
  return o
end
R.copy = copy

function R.validSize(n) return n == 10 or n == 20 or n == 40 end
function R.isState(s) return oneOf(s, R.STATES) end
function R.isAnswer(v) return oneOf(v, R.ANSWERS) end
function R.canTransition(from, to)
  if from == to then return true end
  return R.NEXT[from] ~= nil and R.NEXT[from][to] == true
end

-------------------------------------------------------------------------------
-- templates "2-2/2-3/5-6" (T / H / D, min-max)
function R.tplString(t)
  local parts = {}
  for _, role in ipairs(R.ROLES) do
    local mm = t[role] or { 0, 0 }
    parts[#parts + 1] = mm[1] .. "-" .. mm[2]
  end
  return table.concat(parts, "/")
end
function R.defaultTpl(size) return R.tplString(R.TEMPLATES[size] or R.TEMPLATES[10]) end
-- parse a template; invalid or impossible (min sum > size) -> the default of the size
function R.parseTpl(s, size)
  local def = copy(R.TEMPLATES[size] or R.TEMPLATES[10])
  if type(s) ~= "string" then return def end
  local a1, b1, a2, b2, a3, b3 = s:match("^(%d+)%-(%d+)/(%d+)%-(%d+)/(%d+)%-(%d+)$")
  if not a1 then return def end
  local t = { TANK = { tonumber(a1), tonumber(b1) }, HEALER = { tonumber(a2), tonumber(b2) },
              DAMAGER = { tonumber(a3), tonumber(b3) } }
  local minSum = 0
  for _, role in ipairs(R.ROLES) do
    if t[role][1] > t[role][2] or t[role][2] > (size or 40) then return def end
    minSum = minSum + t[role][1]
  end
  if minSum > (size or 40) then return def end
  return t
end

-- GM utility table: list of "key:CLASS+CLASS:minSize" (anything malformed is skipped); nil/empty -> defaults
function R.utilTable(settings)
  local list = settings and settings.rutil
  if type(list) ~= "table" or #list == 0 then return R.DEFAULT_UTIL end
  local out = {}
  for _, e in ipairs(list) do
    if type(e) == "string" then
      local key, cls, min = e:match("^([%w_]+):([%u+]+):(%d+)$")
      if key then
        local classes = {}
        for c in cls:gmatch("[%u]+") do classes[#classes + 1] = c end
        if #classes > 0 then out[#out + 1] = { key = key, classes = classes, min = tonumber(min) } end
      end
    end
  end
  return #out > 0 and out or R.DEFAULT_UTIL
end
function R.utilStrings(tbl)
  local out = {}
  for _, u in ipairs(tbl or R.DEFAULT_UTIL) do out[#out + 1] = u.key .. ":" .. table.concat(u.classes, "+") .. ":" .. u.min end
  return out
end

-------------------------------------------------------------------------------
-- wall clock (realm local time encoded as UTC seconds)
local function daysFromCivil(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = math.floor((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end
function R.civil(y, m, d, h, mi) return daysFromCivil(y, m, d) * 86400 + (h or 0) * 3600 + (mi or 0) * 60 end
-- -> y, m, d, h, mi, weekday (1 = Monday .. 7 = Sunday)
function R.fields(wall)
  local days = math.floor(wall / 86400)
  local secs = wall - days * 86400
  local z = days + 719468
  local era = math.floor(z / 146097)
  local doe = z - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local d = doy - math.floor((153 * mp + 2) / 5) + 1
  local m = mp < 10 and mp + 3 or mp - 9
  if m <= 2 then y = y + 1 end
  local wd = (days + 3) % 7 + 1   -- 1970-01-01 was a Thursday
  return y, m, d, math.floor(secs / 3600), math.floor((secs % 3600) / 60), wd
end
function R.fmtWall(wall)
  local y, m, d, h, mi = R.fields(wall)
  return ("%04d-%02d-%02d %02d:%02d"):format(y, m, d, h, mi)
end
-- "YYYY-MM-DD HH:MM" (realm time) -> wall seconds, or nil when malformed / impossible
function R.parseWall(str)
  if type(str) ~= "string" then return nil end
  local y, m, d, h, mi = str:match("^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s+(%d%d?):(%d%d)%s*$")
  if not y then return nil end
  y, m, d, h, mi = tonumber(y), tonumber(m), tonumber(d), tonumber(h), tonumber(mi)
  if m < 1 or m > 12 or d < 1 or h > 23 or mi > 59 then return nil end
  local wall = R.civil(y, m, d, h, mi)
  local y2, m2, d2 = R.fields(wall)
  if y2 ~= y or m2 ~= m or d2 ~= d then return nil end   -- 31-Feb and friends
  return wall
end
-- the next week, same wall-clock hour (DST-proof by construction)
function R.nextWeek(at) return at + R.WEEK end
-- realm wall clock -> real epoch. offsetAt(epoch) = realm UTC offset in seconds at that epoch (e.g. 7200 in CEST).
function R.wallToEpoch(wall, offsetAt)
  if type(offsetAt) ~= "function" then return wall end
  local guess = wall - (offsetAt(wall) or 0)
  return wall - (offsetAt(guess) or 0)
end

-------------------------------------------------------------------------------
-- slots: d.main has exactly `size` entries ("" = empty); slot i is in group ceil(i / 5)
function R.normalize(d)
  d.main = type(d.main) == "table" and d.main or {}
  d.bench = type(d.bench) == "table" and d.bench or {}
  local size = d.size or 10
  for i = 1, size do if type(d.main[i]) ~= "string" then d.main[i] = "" end end
  for i = #d.main, size + 1, -1 do table.remove(d.main, i) end
  return d
end

function R.new(f)
  f = f or {}
  local size = R.validSize(f.size) and f.size or 10
  local d = { raid = f.raid or "custom", size = size, name = f.name or "", at = f.at or 0, wk = f.wk and true or false,
              tpl = f.tpl or R.defaultTpl(size), main = {}, bench = {}, st = "draft", owner = f.owner }
  return R.normalize(d)
end

function R.where(d, name)
  for i, n in ipairs(d.main or {}) do if n == name then return "main", i end end
  for i, n in ipairs(d.bench or {}) do if n == name then return "bench", i end end
  return nil
end
function R.names(d)
  local out = {}
  for _, n in ipairs(d.main or {}) do if n ~= "" then out[#out + 1] = n end end
  for _, n in ipairs(d.bench or {}) do if n ~= "" then out[#out + 1] = n end end
  return out
end
function R.filled(d)
  local n = 0
  for _, x in ipairs(d.main or {}) do if x ~= "" then n = n + 1 end end
  return n
end
function R.groupOf(slot) return math.floor((slot - 1) / 5) + 1 end
function R.groups(d)
  local out = {}
  for i = 1, (d.size or 10) / 5 do out[i] = {} end
  for i, n in ipairs(d.main or {}) do if n ~= "" then local g = out[R.groupOf(i)]; if g then g[#g + 1] = n end end end
  return out
end
local function freeIn(d, g)
  local n = 0
  for i = (g - 1) * 5 + 1, g * 5 do if d.main[i] == "" then n = n + 1 end end
  return n
end
local function firstFree(d, from)
  for i = from or 1, #d.main do if d.main[i] == "" then return i end end
  return nil
end

-- add one player. where = "main" (default) | "bench". -> ok, why ("dup" | "full" | "name")
function R.addPlayer(d, name, where)
  if type(name) ~= "string" or name == "" then return false, "name" end
  R.normalize(d)
  if R.where(d, name) then return false, "dup" end
  if where == "bench" then
    if #d.bench >= R.MAX_BENCH then return false, "full" end
    d.bench[#d.bench + 1] = name
    return true
  end
  local i = firstFree(d)
  if not i then return false, "full" end
  d.main[i] = name
  return true
end

function R.removePlayer(d, name)
  local w, i = R.where(d, name)
  if w == "main" then d.main[i] = "" elseif w == "bench" then table.remove(d.bench, i) end
  return w ~= nil
end

-- move to slot (swapping with whoever is there) or to the bench (slot = "bench")
function R.movePlayer(d, name, slot)
  R.normalize(d)
  local w, i = R.where(d, name)
  if not w then return false end
  if slot == "bench" then
    if w == "bench" then return true end
    if #d.bench >= R.MAX_BENCH then return false, "full" end
    d.main[i] = ""; d.bench[#d.bench + 1] = name
    return true
  end
  if type(slot) ~= "number" or slot < 1 or slot > #d.main then return false end
  local other = d.main[slot]
  if w == "main" then d.main[i] = other; d.main[slot] = name
  else
    table.remove(d.bench, i); d.main[slot] = name
    if other ~= "" then d.bench[#d.bench + 1] = other end
  end
  return true
end

-- add a whole squad: titulares together in the first group with room (else split over free slots); its bench
-- players take free slots if any, else the roster bench. -> { added = {...}, notFit = {...}, split = bool }
function R.addSquad(d, titulares, suplentes)
  R.normalize(d)
  local res = { added = {}, notFit = {}, split = false }
  local todo = {}
  for _, n in ipairs(titulares or {}) do if n ~= "" and not R.where(d, n) then todo[#todo + 1] = n end end
  local placed = false
  if #todo > 0 and #todo <= 5 then
    for g = 1, d.size / 5 do
      if freeIn(d, g) >= #todo then
        local i = (g - 1) * 5 + 1
        for _, n in ipairs(todo) do
          i = firstFree(d, i); d.main[i] = n; res.added[#res.added + 1] = n
        end
        placed = true
        break
      end
    end
  end
  if not placed then
    if #todo > 0 then res.split = true end
    for _, n in ipairs(todo) do
      local i = firstFree(d)
      if i then d.main[i] = n; res.added[#res.added + 1] = n else res.notFit[#res.notFit + 1] = n end
    end
  end
  for _, n in ipairs(suplentes or {}) do
    if n ~= "" and not R.where(d, n) then
      local i = firstFree(d)
      if i then d.main[i] = n; res.added[#res.added + 1] = n
      elseif #d.bench < R.MAX_BENCH then d.bench[#d.bench + 1] = n; res.added[#res.added + 1] = n end
    end
  end
  return res
end

-------------------------------------------------------------------------------
-- composition: roleOf(name) -> "TANK"|"HEALER"|"DAMAGER"|nil, classOf(name) -> class file | nil
function R.coverage(d, roleOf)
  local c = { TANK = 0, HEALER = 0, DAMAGER = 0, unknown = 0, filled = 0 }
  for _, n in ipairs(d.main or {}) do
    if n ~= "" then
      c.filled = c.filled + 1
      local r = roleOf and roleOf(n)
      if c[r] and r ~= "unknown" and r ~= "filled" then c[r] = c[r] + 1 else c.unknown = c.unknown + 1 end
    end
  end
  return c
end

-- warnings: { kind = "missing"|"extra"|"util"|"empty", role?, n?, key? }
function R.warnings(d, roleOf, classOf, util)
  local out = {}
  local tpl = R.parseTpl(d.tpl, d.size)
  local c = R.coverage(d, roleOf)
  for _, role in ipairs(R.ROLES) do
    local mm = tpl[role]
    if c[role] < mm[1] then out[#out + 1] = { kind = "missing", role = role, n = mm[1] - c[role] }
    elseif c[role] > mm[2] then out[#out + 1] = { kind = "extra", role = role, n = c[role] - mm[2] } end
  end
  if c.filled < d.size then out[#out + 1] = { kind = "empty", n = d.size - c.filled } end
  local classes = {}
  for _, n in ipairs(d.main or {}) do
    if n ~= "" then local cl = classOf and classOf(n); if cl then classes[cl] = true end end
  end
  for _, u in ipairs(util or R.DEFAULT_UTIL) do
    if d.size >= (u.min or 10) then
      local have = false
      for _, cl in ipairs(u.classes) do if classes[cl] then have = true end end
      if not have then out[#out + 1] = { kind = "util", key = u.key } end
    end
  end
  return out
end

-------------------------------------------------------------------------------
-- authority
function R.canLead(roster, name, settings)
  if P.isOfficer(roster, name, settings) then return true end
  return P.inGuild(roster, name) and contains(settings and settings.rlList, name)
end
-- may `name` edit roster data `sd` (stored)?
function R.canEdit(roster, name, sd, settings)
  if P.isGM(roster, name) then return true end
  if sd.owner == name and R.canLead(roster, name, settings) then return true end
  return settings and settings.offEdit == true and P.isOfficer(roster, name, settings) or false
end

-------------------------------------------------------------------------------
-- record validation (registered into Model)
R.SCHEMA = {
  roster = { raid = { "s", 16 }, size = { "n" }, name = { "s", 32 }, at = { "n" }, wk = { "b" }, tpl = { "s", 20 },
             main = { "L", 40, 48 }, bench = { "L", 10, 48 }, st = { "s", 10 }, owner = { "s", 48 }, prev = { "s", 80 },
             open = { "b" } },
  rsvp = { rid = { "s", 80 }, name = { "s", 48 }, v = { "s", 6 }, c = { "s", 60 } },
  attendance = { rid = { "s", 80 }, names = { "L", 80, 48 }, at = { "n" } },
  witness = { rid = { "s", 80 }, names = { "L", 50, 48 } },
}

local function validRosterData(d)
  if not R.validSize(d.size) then return false, "size" end
  if d.raid ~= "custom" then
    local C = ns.Content
    local e = C and C.get and C.get(d.raid or "")
    if not e or e.kind ~= "raid" or e.size ~= d.size then return false, "raid" end
  end
  if not R.isState(d.st) then return false, "state" end
  -- finite and in range (inf / nan would break Serialize on every relay)
  if type(d.at) ~= "number" or d.at ~= d.at or d.at <= 0 or d.at > M.MAX_TS then return false, "at" end
  -- player lists hold names only
  for _, l in ipairs({ d.main or {}, d.bench or {} }) do
    for _, n in ipairs(l) do if type(n) ~= "string" then return false, "name" end end
  end
  d.name = (d.name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if d.name == "" or d.name:find("[|~%c]") then return false, "name" end
  d.main = d.main or {}; d.bench = d.bench or {}
  local filled = 0
  for _, n in ipairs(d.main) do if n ~= "" then filled = filled + 1 end end
  if #d.main > d.size then
    -- trailing empties beyond the size are tolerated; players are not
    for i = d.size + 1, #d.main do if d.main[i] ~= "" then return false, "full" end end
  end
  R.normalize(d)
  if #d.bench > R.MAX_BENCH then return false, "benchFull" end
  local seen = {}
  for _, n in ipairs(R.names(d)) do if seen[n] then return false, "dupPlayer" end seen[n] = true end
  if d.tpl then d.tpl = R.tplString(R.parseTpl(d.tpl, d.size)) else d.tpl = R.defaultTpl(d.size) end
  return true
end

local function lww(tbl, rec, roster)
  local cur = tbl[rec.id]
  if M.same(rec, cur) then return false, "dup" end
  if not M.newer(rec, cur, roster) then return false, "stale" end
  return true
end

function R.applyRoster(state, rec, roster, settings)
  local d = rec.d
  state.rosters = state.rosters or {}
  local ok, why = validRosterData(d)
  if not ok then return false, why end
  local cur = state.rosters[rec.id]
  if M.same(rec, cur) then return false, "dup" end
  if not cur then
    if not R.canLead(roster, rec.a, settings) and not P.isGM(roster, rec.a) then return false, "denied" end
    if d.owner ~= nil and d.owner ~= rec.a and not P.isGM(roster, rec.a) then return false, "denied" end
    d.owner = d.owner or rec.a
    -- the id is bound to its owner ("Owner:ts"), nobody can squat someone else's id
    if rec.id:sub(1, #d.owner + 1) ~= d.owner .. ":" then return false, "denied" end
    -- a peer that missed the earlier versions may first see the close: accept it when its author may edit
    if terminal(d.st) and not R.canEdit(roster, rec.a, d, settings) then return false, "denied" end
  else
    d.owner = cur.d.owner   -- immutable
    if not R.canEdit(roster, rec.a, cur.d, settings) then return false, "denied" end
    -- total order (state rank, then LWW). A close / cancel is a tombstone that beats any
    -- edit, whatever its ts; between versions of the same rank the newer wins. Order of arrival is irrelevant.
    local rc, rn = R.RANK[cur.d.st], R.RANK[d.st]
    if rn < rc then return false, terminal(cur.d.st) and "closed" or "transition" end
    if rn == rc then
      -- between two terminal versions the FIRST one stays (the close is final; its ts opens the 7-day window)
      if terminal(cur.d.st) then if not M.newer(cur, rec, roster) then return false, "closed" end
      elseif not M.newer(rec, cur, roster) then return false, "stale" end
    end
  end
  state.rosters[rec.id] = rec
  return true, "applied"
end

function R.rsvpId(rid, name) return tostring(rid) .. "|" .. tostring(name) end
function R.applyRsvp(state, rec, roster)
  local d = rec.d
  if type(d.rid) ~= "string" or type(d.name) ~= "string" or rec.id ~= R.rsvpId(d.rid, d.name) then return false, "shape" end
  if not R.isAnswer(d.v) then return false, "shape" end
  if rec.a ~= d.name then return false, "denied" end           -- only the player answers for themselves
  -- only for a roster that exists and was published; a list-only roster (open = false)
  -- takes answers from listed players only. One answer per character and roster (the id), the last one wins.
  -- An answer that arrives after the close is stored (so every peer holds the same set) but changes nothing.
  local ro = state.rosters and state.rosters[d.rid]
  if not ro then return false, "noRoster" end
  if ro.d.st == "draft" then return false, "draft" end
  if state.pruned and state.pruned[d.rid] then return false, "pruned" end
  if ro.d.open == false and not R.where(ro.d, d.name) and not (state.rsvps and state.rsvps[rec.id]) then
    return false, "notListed"
  end
  state.rsvps = state.rsvps or {}
  local okL, whyL = lww(state.rsvps, rec, roster)
  if not okL then return false, whyL end
  state.rsvps[rec.id] = rec
  return true, "applied"
end

function R.applyAttendance(state, rec, roster, settings)
  local d = rec.d
  if type(d.rid) ~= "string" or rec.id ~= d.rid then return false, "shape" end
  local ro = state.rosters and state.rosters[d.rid]
  if not ro then return false, "noRoster" end
  if not R.canEdit(roster, rec.a, ro.d, settings) then return false, "denied" end
  -- only for a closed roster, within 7 days of the close, guild members only, at most
  -- size + bench names and never empty. Each new signature replaces the previous one (LWW).
  if ro.d.st ~= "closed" then return false, "notClosed" end
  if rec.ts > ro.ts + R.FIX_DAYS then return false, "late" end
  local clean = R.cleanNames(d.names, roster)
  if #clean == 0 then return false, "empty" end
  if #clean > (ro.d.size or 10) + R.MAX_BENCH then return false, "tooMany" end
  d.names = clean
  state.attendance = state.attendance or {}
  local okL, whyL = lww(state.attendance, rec, roster)
  if not okL then return false, whyL end
  state.attendance[rec.id] = rec
  return true, "applied"
end

-- strings, not empty, in the guild (when a roster function is known), no duplicates
function R.cleanNames(list, roster)
  local seen, clean = {}, {}
  for _, n in ipairs(type(list) == "table" and list or {}) do
    if type(n) == "string" and n ~= "" and not seen[n] and (type(roster) ~= "function" or roster(n)) then
      seen[n] = true; clean[#clean + 1] = n
    end
  end
  return clean
end

-- a member who was in the raid reports what they saw (their own signed record)
function R.witnessId(rid, name) return tostring(rid) .. "#" .. tostring(name) end
function R.applyWitness(state, rec, roster)
  local d = rec.d
  if type(d.rid) ~= "string" or rec.id ~= R.witnessId(d.rid, rec.a) then return false, "shape" end
  local ro = state.rosters and state.rosters[d.rid]
  if not ro then return false, "noRoster" end
  if ro.d.st ~= "closed" then return false, "notClosed" end
  if rec.ts > ro.ts + R.FIX_DAYS then return false, "late" end
  local clean = R.cleanNames(d.names, roster)
  local self = false
  for _, n in ipairs(clean) do if n == rec.a then self = true end end
  if not self then return false, "notThere" end
  if #clean > (ro.d.size or 10) + R.MAX_BENCH then return false, "tooMany" end
  d.names = clean
  state.witness = state.witness or {}
  local okL, whyL = lww(state.witness, rec, roster)
  if not okL then return false, whyL end
  state.witness[rec.id] = rec
  return true, "applied"
end

if M and M.registerKind then
  M.registerKind("roster", R.SCHEMA.roster, "rosters", 7, R.applyRoster)
  M.registerKind("rsvp", R.SCHEMA.rsvp, "rsvps", 8, R.applyRsvp)
  M.registerKind("attendance", R.SCHEMA.attendance, "attendance", 9, R.applyAttendance)
  M.registerKind("witness", R.SCHEMA.witness, "witness", 10, R.applyWitness)
  M.SCHEMA.settings.rlList = { "L", 20, 48 }
  M.SCHEMA.settings.offEdit = { "b" }
  M.SCHEMA.settings.rutil = { "L", 30, 60 }
end

-------------------------------------------------------------------------------
-- queries
function R.rsvpOf(state, rid, name)
  local r = state.rsvps and state.rsvps[R.rsvpId(rid, name)]
  if not r then return nil end
  -- an answer signed after the close is kept but changes nothing
  local ro = state.rosters and state.rosters[rid]
  if ro and terminal(ro.d.st) and r.ts > ro.ts then return nil end
  return r.d
end

-- RSVP count by answer and, for "yes", by role
function R.rsvpCount(state, rid, roleOf)
  local c = { yes = 0, maybe = 0, no = 0, bench = 0, none = 0, roles = { TANK = 0, HEALER = 0, DAMAGER = 0 } }
  local ro = state.rosters and state.rosters[rid]
  if not ro then return c end
  local listed = {}
  for _, n in ipairs(R.names(ro.d)) do listed[n] = true end
  for _, r in pairs(state.rsvps or {}) do
    if r.d.rid == rid and R.rsvpOf(state, rid, r.d.name) then
      listed[r.d.name] = true
    end
  end
  for n in pairs(listed) do
    local a = R.rsvpOf(state, rid, n)
    local v = a and a.v or "none"
    c[v] = (c[v] or 0) + 1
    if v == "yes" then local role = roleOf and roleOf(n); if c.roles[role] then c.roles[role] = c.roles[role] + 1 end end
  end
  return c
end

-- confirmed ("yes") players of the roster, roster order (main first, then bench)
function R.confirmed(state, rid)
  local ro = state.rosters and state.rosters[rid]
  local out = {}
  if not ro then return out end
  for _, n in ipairs(R.names(ro.d)) do
    local a = R.rsvpOf(state, rid, n)
    if a and a.v == "yes" then out[#out + 1] = n end
  end
  return out
end

-- rosters sorted by date; filter(rec) optional
function R.list(state, filter)
  local out = {}
  for _, r in pairs(state.rosters or {}) do if not filter or filter(r) then out[#out + 1] = r end end
  table.sort(out, function(a, b) if a.d.at ~= b.d.at then return a.d.at < b.d.at end return a.id < b.id end)
  return out
end

-- "my raids": rosters where I am listed or answered, not cancelled
function R.mine(state, me)
  return R.list(state, function(r)
    if r.d.st == "cancelled" or r.d.st == "draft" then return false end
    return R.where(r.d, me) ~= nil or R.rsvpOf(state, r.id, me) ~= nil
  end)
end

-- final attendance of a roster = the RL/GM record + every name reported by >= 2 witnesses.
-- -> set { [name] = true } or nil when nothing is known (closed roster = "attendance pending")
function R.attendanceOf(state, rid)
  local set, any = {}, false
  local a = state.attendance and state.attendance[rid]
  if a then for _, n in ipairs(a.d.names or {}) do set[n] = true; any = true end end
  local votes = {}
  for _, w in pairs(state.witness or {}) do
    if w.d.rid == rid then
      for _, n in ipairs(w.d.names or {}) do
        votes[n] = (votes[n] or 0) + 1
        if votes[n] >= 2 then set[n] = true; any = true end
      end
    end
  end
  return any and set or nil
end
function R.attendanceList(state, rid)
  local out = {}
  for n in pairs(R.attendanceOf(state, rid) or {}) do out[#out + 1] = n end
  table.sort(out)
  return out
end
-- "signed" (RL/GM record), "witness" (only witnesses), "pending" (closed, nothing signed) or nil (not closed)
function R.attendanceState(state, rid)
  local ro = state.rosters and state.rosters[rid]
  if not ro or ro.d.st ~= "closed" then return nil end
  if state.attendance and state.attendance[rid] then return "signed" end
  if R.attendanceOf(state, rid) then return "witness" end
  return "pending"
end
-- the RL / GM may still sign or correct it (closed, within 7 days of the close)
function R.canFixAttendance(state, rid, nowTs)
  local ro = state.rosters and state.rosters[rid]
  return ro ~= nil and ro.d.st == "closed" and (nowTs or 0) <= ro.ts + R.FIX_DAYS
end

-- attendance % over the last `n` recorded raids where the player was rostered or present
function R.attendanceStats(state, name, n)
  n = n or R.STATS_LAST
  local recs = {}
  local rids = {}
  for rid in pairs(state.attendance or {}) do rids[rid] = true end
  for _, w in pairs(state.witness or {}) do rids[w.d.rid] = true end
  for rid in pairs(rids) do
    local set = R.attendanceOf(state, rid)
    local ro = state.rosters and state.rosters[rid]
    local a = state.attendance and state.attendance[rid]
    if set then
      local listed = ro and R.where(ro.d, name) ~= nil
      local present = set[name] == true
      if listed or present then recs[#recs + 1] = { at = (ro and ro.d.at) or (a and (a.d.at or a.ts)) or 0, present = present } end
    end
  end
  table.sort(recs, function(x, y) return x.at > y.at end)
  local count, here = 0, 0
  for i = 1, math.min(n, #recs) do count = count + 1; if recs[i].present then here = here + 1 end end
  if count == 0 then return nil, 0, 0 end
  return math.floor(here * 100 / count + 0.5), here, count
end

-- weekly: copy of a roster one week later (draft, same players and template, no RSVPs).
-- with nowWall, the first weekly date after now (never a cascade of past weeks)
function R.duplicate(d, prevId, nowWall)
  local o = copy(d)
  o.at = R.nextWeek(d.at)
  if type(nowWall) == "number" and o.at <= nowWall then
    o.at = o.at + math.ceil((nowWall - o.at + 1) / R.WEEK) * R.WEEK
  end
  o.st = "draft"
  o.prev = prevId
  return o
end
-- repeating rosters owned by `me` whose date has passed and that have no successor yet
function R.dueRepeats(state, me, nowWall)
  local hasNext = {}
  for _, r in pairs(state.rosters or {}) do if r.d.prev then hasNext[r.d.prev] = true end end
  local out = {}
  for _, r in ipairs(R.list(state)) do
    -- only published / closed rosters repeat; a weekly draft that was never published is not copied
    if r.d.wk and r.d.owner == me and (r.d.st == "published" or r.d.st == "closed") and nowWall >= r.d.at
       and not hasNext[r.id] then
      out[#out + 1] = r
    end
  end
  return out
end

-- closed / cancelled rosters older than 8 weeks keep their record and their attendance
-- (the summary used by the %) but lose their RSVPs; later RSVPs for them are refused ("pruned"). -> removed count
function R.prune(state, nowWall)
  local old = {}
  for rid, r in pairs(state.rosters or {}) do
    if terminal(r.d.st) and r.d.at + R.CLOSE_AFTER + R.PRUNE_AFTER < nowWall then old[rid] = true end
  end
  local n = 0
  if next(old) then
    state.pruned = state.pruned or {}
    for rid in pairs(old) do state.pruned[rid] = true end
    for id, a in pairs(state.rsvps or {}) do if old[a.d.rid] then state.rsvps[id] = nil; n = n + 1 end end
  end
  return n
end

-- the ONE roster the current raid is playing. Candidates: published, in its window,
-- whose owner or a listed player is in the group; the one with most listed players present wins, then the
-- closest start. members = list of names in the group.
function R.activeRoster(state, members, nowWall, me)
  local inGroup = {}
  for _, n in ipairs(members or {}) do inGroup[n] = true end
  local best, bestN, bestDist
  for _, r in pairs(state.rosters or {}) do
    if r.d.st == "published" and R.inWindow(r.d, nowWall) and (R.where(r.d, me) or r.d.owner == me) then
      local n = 0
      for _, x in ipairs(R.names(r.d)) do if inGroup[x] then n = n + 1 end end
      if inGroup[r.d.owner] then n = n + 1 end
      local dist = math.abs(nowWall - r.d.at)
      if n > 0 and (not best or n > bestN or (n == bestN and (dist < bestDist or (dist == bestDist and r.id < best.id)))) then
        best, bestN, bestDist = r, n, dist
      end
    end
  end
  return best
end

-- players that would leave the roster when its size goes down to `size`
function R.shrinkLoss(d, size)
  local out = {}
  if not R.validSize(size) or size >= (d.size or 10) then return out end
  local free = R.MAX_BENCH - #(d.bench or {})
  for i = size + 1, #(d.main or {}) do
    local n = d.main[i]
    if n ~= "" then
      -- players beyond the new size go to the bench while it has room; the rest would be lost
      free = free - 1
      if free < 0 then out[#out + 1] = n end
    end
  end
  return out
end

-- attendance window (wall clock): [at - 30 min, at + 3 h]
function R.inWindow(d, nowWall) return nowWall >= d.at - R.WINDOW_BEFORE and nowWall <= d.at + R.CLOSE_AFTER end
function R.autoCloseDue(d, nowWall) return d.st == "published" and nowWall > d.at + R.CLOSE_AFTER end
function R.remindDue(d, nowWall) return d.st == "published" and nowWall >= d.at - R.REMIND_BEFORE and nowWall < d.at end

-------------------------------------------------------------------------------
-- invite plan. api (all optional except inCombat/invite):
--   inCombat() -> bool, invite(name), isRaid() -> bool, groupSize() -> n (incl. me), inGroup(name) -> bool,
--   convert(), members() -> { { name, index, sub } }, setSub(index, sub), swapSub(index1, index2)
-- One call = one user click: never loops on its own, never acts in combat.
-- -> { reason = "combat"|"noInvite"|nil, invited = n, remaining = n, converted, noConvert, sub = "ok"|"missing"|"failed"|nil }
R.pendingInvites = {}   -- name -> time of the last invite (not repeated for 60 s)
local function clock(api)
  if type(api.now) == "function" then local ok, v = pcall(api.now); if ok and type(v) == "number" then return v end end
  if type(GetTime) == "function" then local ok, v = pcall(GetTime); if ok and type(v) == "number" then return v end end
  if type(time) == "function" then return time() end
  return os and os.time and os.time() or 0
end
function R.invite(api, d, names, me)
  local res = { invited = 0, remaining = 0 }
  if type(api) ~= "table" then return { reason = "noInvite", invited = 0, remaining = 0 } end
  local okC, combat = pcall(api.inCombat or function() return false end)
  if not okC or combat then res.reason = "combat"; return res end
  if type(api.invite) ~= "function" then res.reason = "noInvite"; return res end
  -- in a group only the leader / an assistant can invite
  if type(api.canInvite) == "function" then
    local okI, can = pcall(api.canInvite)
    if okI and can == false then res.reason = "notLeader"; return res end
  end
  local t = clock(api)
  local pend = R.pendingInvites
  local function call(fn, ...) if type(fn) ~= "function" then return false end return pcall(fn, ...) end
  local function val(fn, default) if type(fn) ~= "function" then return default end local ok, v = pcall(fn); if ok and v ~= nil then return v end return default end
  local todo = {}
  for _, n in ipairs(names or {}) do
    if n ~= me then
      local okG, inG = false, false
      if type(api.inGroup) == "function" then okG, inG = pcall(api.inGroup, n) end
      if not (okG and inG) then
        local at = pend[n]
        if at and t - at < R.INVITE_WAIT and t >= at then res.pending = (res.pending or 0) + 1
        else todo[#todo + 1] = n end
      end
    end
  end
  local raid = val(api.isRaid, false) and true or false
  local size = val(api.groupSize, 1)
  if not raid and size >= 2 and size + #todo > 5 then
    if type(api.convert) == "function" then
      -- the conversion is asynchronous; until isRaid() is true the party cap still applies
      if call(api.convert) then res.converted = true; raid = val(api.isRaid, false) and true or false
      else res.noConvert = true end
    else res.noConvert = true end
  end
  local cap = (raid and 40 or 5) - size
  for _, n in ipairs(todo) do
    if res.invited < cap and call(api.invite, n) then res.invited = res.invited + 1; pend[n] = t end
  end
  res.remaining = #todo - res.invited + (res.pending or 0)
  if raid and val(api.isRaid, false) then res.sub = R.placeSubgroups(api, d) end
  return res
end

-- desired subgroup per name: roster slot group (squads were placed together by addSquad)
function R.subgroupPlan(d)
  local plan = {}
  for i, n in ipairs(d.main or {}) do if n ~= "" then plan[n] = R.groupOf(i) end end
  return plan
end

function R.placeSubgroups(api, d)
  if type(api.setSub) ~= "function" or type(api.members) ~= "function" then return "missing" end
  local okM, list = pcall(api.members)
  if not okM or type(list) ~= "table" then return "failed" end
  local plan = R.subgroupPlan(d)
  local count, at = {}, {}
  for g = 1, 8 do count[g] = 0 end
  for _, m in ipairs(list) do count[m.sub] = (count[m.sub] or 0) + 1; at[m.name] = m end
  local failed = false
  for _, m in ipairs(list) do
    local want = plan[m.name]
    if want and want ~= m.sub then
      if (count[want] or 0) < 5 then
        if pcall(api.setSub, m.index, want) then
          count[m.sub] = count[m.sub] - 1; count[want] = count[want] + 1; m.sub = want
        else failed = true end
      elseif type(api.swapSub) == "function" then
        local other
        for _, o in ipairs(list) do if o.sub == want and plan[o.name] ~= want then other = o; break end end
        if other and pcall(api.swapSub, m.index, other.index) then other.sub, m.sub = m.sub, want
        else failed = true end
      else failed = true end
    end
  end
  return failed and "failed" or "ok"
end

-------------------------------------------------------------------------------
-- Discord export: title, date, groups with role letters, bench and RSVP counts. labels = { group, bench, ... }
function R.exportText(state, rid, roleOf, labels)
  local ro = state.rosters and state.rosters[rid]
  if not ro then return "" end
  local d = ro.d
  labels = labels or {}
  local short = function(n) return (n:match("^([^-]+)")) or n end
  local raidName = d.raid
  local C = ns.Content
  local e = C and C.get and C.get(d.raid)
  if e then raidName = e.name end
  local lines = { ("**%s** · %s (%d) · %s"):format(d.name, raidName ~= "custom" and raidName or (labels.custom or "custom"), d.size, R.fmtWall(d.at)) }
  local c = R.coverage(d, roleOf)
  lines[#lines + 1] = ("%d/%d · %dT %dH %dD"):format(c.filled, d.size, c.TANK, c.HEALER, c.DAMAGER)
  for g, list in ipairs(R.groups(d)) do
    if #list > 0 then
      local parts = {}
      for _, n in ipairs(list) do parts[#parts + 1] = short(n) .. " (" .. (R.ROLE_SHORT[roleOf and roleOf(n) or ""] or "?") .. ")" end
      lines[#lines + 1] = ("%s%d: %s"):format(labels.group or "G", g, table.concat(parts, ", "))
    end
  end
  if #d.bench > 0 then
    local parts = {}
    for _, n in ipairs(d.bench) do parts[#parts + 1] = short(n) end
    lines[#lines + 1] = (labels.bench or "Bench") .. ": " .. table.concat(parts, ", ")
  end
  local a = state.attendance and state.attendance[rid]
  if a then lines[#lines + 1] = (labels.attendance or "Attendance") .. ": " .. #a.d.names end
  return table.concat(lines, "\n")
end

return R
