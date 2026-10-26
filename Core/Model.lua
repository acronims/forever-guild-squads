-- Guild Squads (MIT) - Core/Model.lua
-- Pure Lua. Records, schema sanitising, last-writer-wins merge and authority validation.
-- Record: { k = kind, id = string, a = author, ts = number, sq = number, d = data }
local _, ns = ...
ns = ns or {}

local M = {}
ns.Model = M
local P = ns.Permissions
local S = ns.Serialize

M.PROTO = 1
M.SQUAD_SIZE = 5
M.ROLES = { "TANK", "HEALER", "DAMAGER" }
M.GOALS = { "leveling", "dungeons", "farm", "worldpvp", "bg", "raid" }
M.SLOTS = 8 -- availability: weekday x (morning, afternoon, evening, night), then weekend x same
M.NBUCKETS = 16

-- Whitelisted schema. Anything else is dropped on receipt. (No economy fields by design.)
-- type codes: s=string(max len), n=number, b=boolean, L=list of strings, R=role, A=availability string
M.SCHEMA = {
  profile = {
    class = { "s", 20 }, level = { "n" }, race = { "s", 24 },
    role = { "R" }, role2 = { "R" }, avail = { "A" }, goals = { "L", 6, 12 },
    squad = { "s", 64 }, note = { "s", 60 },
    reqAt = { "n" }, -- when the current join request was made (a Reject points at it)
    xferTo = { "s", 120 }, -- "squadId>NewCaptain" signed by the captain who hands the squad over
  },
  squad = {
    name = { "s", 24 }, captain = { "s", 48 }, members = { "L", 5, 48 }, bench = { "L", 2, 48 },
    icon = { "n" }, color = { "n" }, border = { "n" }, motto = { "s", 60 }, tags = { "L", 6, 16 },
    open = { "b" }, approved = { "b" }, disbanded = { "b" }, xferFrom = { "s", 48 },
    ct = { "n" },          -- creation ts, carried by every edit (deterministic name/limit races)
    nts = { "n" },         -- ts since the squad has its current name (absent = ct)
  },
  settings = {
    squadsEnabled = { "b" }, minCreateRank = { "n" }, bench = { "n" }, requireApproval = { "b" },
    officerRanks = { "L", 10 }, banned = { "L", 50, 24 },
    -- PvE competition
    compEnabled = { "b" }, seasonKind = { "s", 8 }, wLevel = { "n" }, wDungeon = { "n" }, wRaid = { "n" },
    weekCap = { "n" }, guildGoal = { "n" },
    -- PvP + seasons (weekCap = cap per category and wipe)
    wPvp = { "n" }, wWpvp = { "n" }, overlordOn = { "b" },
    seasonName = { "s", 24 }, seasonStart = { "n" }, seasonEnd = { "n" }, seasonsPast = { "L", 8, 64 },
    -- settings UX
    inactiveDays = { "n" }, maxSquads = { "n" }, ovHint = { "b" },
    -- celebrations (guild chat): on/off, scope "first"|"top3"|"any", squad achievements
    celOn = { "b" }, celScope = { "s", 6 }, celSquad = { "b" },
  },
  -- GM annulment of a race entry (mandatory reason, kept as history). id = race .. "|" .. key
  annul = { race = { "s", 64 }, key = { "s", 200 }, reason = { "s", 80 }, on = { "b" } },
  -- learned boss catalog. id = Content.bossId(inst, enc, name). `final` only from the GM.
  boss = { inst = { "s", 64 }, enc = { "n" }, name = { "s", 64 }, kind = { "s", 8 }, final = { "b" } },
  -- durable rejection. id = sid .. "|" .. name .. "|" .. kind ; kind "req" (captain rejects a request)
  -- or "inv" (the invited player declines). at = the reqAt (req) the rejection refers to; on = false withdraws it.
  reject = { sid = { "s", 64 }, name = { "s", 48 }, kind = { "s", 3 }, at = { "n" }, on = { "b" } },
}

-- allowed values (anything else is normalised on receipt)
M.MAX_RANK = 9
M.WEIGHT_FIELDS = { "wLevel", "wDungeon", "wRaid", "wPvp", "wWpvp" }
M.CAPS = { 50, 100, 150, 200 }
M.INACTIVE_DAYS = { 7, 14, 30, 0 }   -- 0 = never
M.MAX_SQUADS = { 0, 10, 20, 50 }     -- 0 = no limit

local ROLESET = { TANK = true, HEALER = true, DAMAGER = true }

M.MAX_TAGS = 3
local GOALSET = {}
for _, g in ipairs(M.GOALS) do GOALSET[g] = true end
function M.isGoal(key) return GOALSET[key] == true end

-- tags: canonical goal keys only, no duplicates, at most MAX_TAGS (used when creating/editing)
function M.cleanTags(list)
  local out, seen = {}, {}
  for _, t in ipairs(list or {}) do
    if type(t) == "string" and GOALSET[t] and not seen[t] and #out < M.MAX_TAGS then
      seen[t] = true; out[#out + 1] = t
    end
  end
  return out
end

-- split stored tags into canonical keys and legacy free text; legacy text is kept, shown as a grey chip
function M.splitTags(list)
  local known, legacy, seen = {}, {}, {}
  for _, t in ipairs(list or {}) do
    if type(t) == "string" and not seen[t] then
      seen[t] = true
      if GOALSET[t] then known[#known + 1] = t else legacy[#legacy + 1] = t end
    end
  end
  return known, legacy
end

function M.defaultSettings()
  return { squadsEnabled = true, minCreateRank = 9, bench = 0, requireApproval = false,
           officerRanks = { 1 }, banned = {},
           compEnabled = true, seasonKind = "weekly", wLevel = 1, wDungeon = 1, wRaid = 1, weekCap = 100, guildGoal = 30,
           wPvp = 1, wWpvp = 1, overlordOn = true, seasonName = "", seasonStart = 1793779200, seasonEnd = 0, seasonsPast = {},
           inactiveDays = 14, maxSquads = 0, ovHint = true, celOn = false, celScope = "first", celSquad = true,
           rlList = {}, offEdit = false }
end

function M.newState()
  return { profiles = {}, squads = {}, settings = nil, rejects = {}, annuls = {}, bosses = {} }
end

-- finite and inside the range the serializer can round-trip
function M.finite(v) return type(v) == "number" and v == v and v < 1e15 and v > -1e15 end

local function oneOf(v, list, default)
  for _, x in ipairs(list) do if v == x then return v end end
  return default
end
local function clampInt(v, lo, hi, default)
  if type(v) ~= "number" or v ~= v then return default end
  v = math.floor(v)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- normalise a (sanitised) settings table in place: ranks within 0..MAX_RANK, weights 0..3,
-- caps / inactivity / max squads from the allowed lists. Missing fields stay nil (defaults fill them later).
-- Returns the table and the list of fields that were changed.
function M.normalizeSettings(d)
  local fixed = {}
  local function set(k, v) if d[k] ~= nil and d[k] ~= v then fixed[#fixed + 1] = k end; if d[k] ~= nil then d[k] = v end end
  set("minCreateRank", clampInt(d.minCreateRank, 0, M.MAX_RANK, 9))
  set("bench", clampInt(d.bench, 0, 2, 0))
  for _, k in ipairs(M.WEIGHT_FIELDS) do set(k, clampInt(d[k], 0, 3, 1)) end
  set("weekCap", oneOf(d.weekCap, M.CAPS, 100))
  set("guildGoal", clampInt(d.guildGoal, 1, 1000, 30))
  set("inactiveDays", oneOf(d.inactiveDays, M.INACTIVE_DAYS, 14))
  set("maxSquads", oneOf(d.maxSquads, M.MAX_SQUADS, 0))
  set("celScope", oneOf(d.celScope, { "first", "top3", "any" }, "first"))
  if type(d.officerRanks) == "table" then
    local out, seen = {}, {}
    for _, r in ipairs(d.officerRanks) do
      if type(r) == "number" and r == math.floor(r) and r >= 1 and r <= M.MAX_RANK and not seen[r] then seen[r] = true; out[#out + 1] = r end
    end
    if #out ~= #d.officerRanks then fixed[#fixed + 1] = "officerRanks" end
    d.officerRanks = out
  end
  return d, fixed
end

-- moderation: the neutral name/logo an officer may reset a squad to
function M.resetName(id) return "Squad " .. S.hash(tostring(id)):sub(1, 4) end

-- number of live squads (for the "max squads" setting)
function M.liveSquads(state)
  local n = 0
  for _, r in pairs(state.squads) do if not r.d.disbanded then n = n + 1 end end
  return n
end

-- inactivity: a squad is inactive when every member's last connection is known and at least `days` ago.
-- lastSeenDays(name) -> days since last online (0 = online now) or nil (unknown => not inactive).
function M.isInactive(state, sid, lastSeenDays, days)
  if not days or days <= 0 or type(lastSeenDays) ~= "function" then return false end
  local mem = M.members(state, sid)
  if #mem == 0 then return false end
  for _, n in ipairs(mem) do
    local d = lastSeenDays(n)
    if type(d) ~= "number" or d < days then return false end
  end
  return true
end

function M.settingsOf(state)
  local s = state.settings and state.settings.d
  local d = M.defaultSettings()
  if not s then return d end
  for k, v in pairs(d) do if s[k] == nil then s[k] = v end end
  return s
end

local function sanitize(kind, data)
  local schema = M.SCHEMA[kind]
  if not schema or type(data) ~= "table" then return nil end
  local out = {}
  for field, spec in pairs(schema) do
    local v, t = data[field], spec[1]
    if v ~= nil then
      if t == "s" and type(v) == "string" then out[field] = v:sub(1, spec[2])
      elseif t == "n" and type(v) == "number" and M.finite(v) then out[field] = v
      elseif t == "b" and type(v) == "boolean" then out[field] = v
      elseif t == "R" and ROLESET[v] then out[field] = v
      elseif t == "A" and type(v) == "string" and #v == M.SLOTS and not v:find("[^01]") then out[field] = v
      elseif t == "L" and type(v) == "table" then
        local l = {}
        for i = 1, math.min(#v, spec[2]) do
          local e = v[i]
          if type(e) == "string" then l[#l + 1] = spec[3] and e:sub(1, spec[3]) or e
          elseif type(e) == "number" and M.finite(e) then l[#l + 1] = e end
        end
        out[field] = l
      end
    end
  end
  return out
end
M.sanitize = sanitize

-- true if record a should replace record b (LWW: ts, then seq, then author name)
-- on a ts tie the author with more authority wins (lower guild rank index), then seq, then name
function M.newer(a, b, roster)
  if not b then return true end
  if a.ts ~= b.ts then return a.ts > b.ts end
  if roster and a.a ~= b.a then
    local ra, rb = P.rankOf(roster, a.a), P.rankOf(roster, b.a)
    if ra and rb and ra ~= rb then return ra < rb end
  end
  if a.sq ~= b.sq then return a.sq > b.sq end
  return a.a > b.a
end

-- deterministic "first writer" order: lower (ts, author, sq) is earlier
function M.earlier(a, b)
  if not b then return true end
  if a.ts ~= b.ts then return a.ts < b.ts end
  if a.a ~= b.a then return a.a < b.a end
  return a.sq < b.sq
end

function M.same(a, b)
  return b ~= nil and a.ts == b.ts and a.sq == b.sq and a.a == b.a
end

local function lower(s) return (s or ""):lower() end

-- visible-name key = trimmed, lower-case, common accented capitals folded
local UPPER = { ["Á"] = "á", ["É"] = "é", ["Í"] = "í", ["Ó"] = "ó", ["Ú"] = "ú", ["Ü"] = "ü", ["Ñ"] = "ñ", ["Ç"] = "ç",
                ["À"] = "à", ["È"] = "è", ["Ò"] = "ò", ["Ï"] = "ï", ["Â"] = "â", ["Ê"] = "ê", ["Ô"] = "ô", ["Ö"] = "ö", ["Ä"] = "ä" }
function M.trimName(name) return ((name or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
function M.nameKey(name)
  local n = M.trimName(name):lower()
  for up, lo in pairs(UPPER) do n = n:gsub(up, lo) end
  return n
end

function M.checkName(name, settings)
  if type(name) ~= "string" then return false, "name" end
  local n = name:gsub("^%s+", ""):gsub("%s+$", "")
  if #n < 3 or #n > 24 then return false, "nameLength" end
  if n:find("[|~%c]") then return false, "nameChars" end
  local ln = n:lower()
  for _, w in ipairs((settings and settings.banned) or {}) do
    if w ~= "" and ln:find(lower(w), 1, true) then return false, "nameBanned" end
  end
  return true
end

function M.nameTaken(state, name, exceptId)
  return M.nameRival(state, name, exceptId) ~= nil
end

-- the live squad (other than exceptId) whose visible name collides with `name`
function M.nameRival(state, name, exceptId)
  local ln = M.nameKey(name)
  for id, r in pairs(state.squads) do
    if id ~= exceptId and not r.d.disbanded and M.nameKey(r.d.name) == ln then return r end
  end
  return nil
end

-- name ownership. Two live squads may share a visible name after a rename (accepting
-- both is the only order-independent rule). The one with the lower (nts, author, id) owns it; the others show
-- "Name", "Name"... locally. Pure function of the stored records -> the same on every client, nothing deleted.
local function nameTs(r) return tonumber(r.d.nts) or tonumber(r.d.ct) or r.ts or 0 end
function M.nameKeyLess(a, b)
  local na, nb = nameTs(a), nameTs(b)
  if na ~= nb then return na < nb end
  if (a.a or "") ~= (b.a or "") then return (a.a or "") < (b.a or "") end
  return a.id < b.id
end
function M.displayName(state, id)
  local r = state and state.squads and state.squads[id]
  if not r then return nil end
  local name = r.d.name or "?"
  if r.d.disbanded then return name end
  local key, pos = M.nameKey(name), 1
  for oid, o in pairs(state.squads) do
    if oid ~= id and not o.d.disbanded and M.nameKey(o.d.name) == key and M.nameKeyLess(o, r) then pos = pos + 1 end
  end
  return pos > 1 and (name .. " (" .. pos .. ")") or name
end
-- a record that is the untouched creation of its squad (never edited): only those take part in creation races
local function pureCreation(r) return r.d.nts == nil and r.d.ct ~= nil and r.ts == r.d.ct end

-- deterministic precedence between squads = (creation ts, id); lower wins
function M.squadKeyLess(a, b)
  local ca, cb = (a.d and a.d.ct) or 0, (b.d and b.d.ct) or 0
  if ca ~= cb then return ca < cb end
  return a.id < b.id
end

local function inList(list, v) return P.contains(list, v) end

-- Effective membership needs consent from both sides: the squad lists the character
-- (captain-authored) AND the character's profile points at the squad (self-authored).
-- The captain always counts. A profile holds a single squad id => one squad per character.
function M.isMember(state, squadId, name)
  local r = state.squads[squadId]
  if not r or r.d.disbanded then return false end
  if r.d.captain == name then return true end
  if not (inList(r.d.members, name) or inList(r.d.bench, name)) then return false end
  local p = state.profiles[name]
  return p ~= nil and p.d.squad == squadId
end

function M.squadOf(state, name)
  local p = state.profiles[name]
  if p and p.d.squad and M.isMember(state, p.d.squad, name) then return p.d.squad end
  for id, r in pairs(state.squads) do
    if not r.d.disbanded and r.d.captain == name then return id end
  end
  return nil
end

function M.members(state, squadId)
  local r = state.squads[squadId]
  local out = {}
  if not r then return out end
  for _, n in ipairs(r.d.members or {}) do if M.isMember(state, squadId, n) then out[#out + 1] = n end end
  if not inList(out, r.d.captain) and not r.d.disbanded then table.insert(out, 1, r.d.captain) end
  return out
end

function M.benchMembers(state, squadId)
  local r = state.squads[squadId]
  local out = {}
  if not r then return out end
  for _, n in ipairs(r.d.bench or {}) do if M.isMember(state, squadId, n) then out[#out + 1] = n end end
  return out
end

-- rejections
function M.rejectId(sid, name, kind) return tostring(sid) .. "|" .. tostring(name) .. "|" .. tostring(kind) end
function M.isRejected(state, sid, name, kind)
  local r = state.rejects and state.rejects[M.rejectId(sid, name, kind)]
  if not r or r.d.on == false then return false end
  if kind == "req" then
    local p = state.profiles[name]
    return (r.d.at or 0) == ((p and p.d.reqAt) or 0)
  end
  return true
end

-- profiles pointing at the squad but not listed by the captain = join requests
function M.requests(state, squadId)
  local r = state.squads[squadId]
  local out = {}
  if not r or r.d.disbanded then return out end
  for name, p in pairs(state.profiles) do
    if p.d.squad == squadId and name ~= r.d.captain and not inList(r.d.members, name) and not inList(r.d.bench, name)
       and not M.isRejected(state, squadId, name, "req") then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

-- squads listing the character while its profile does not point there = invitations
function M.invites(state, name)
  local out = {}
  for id, r in pairs(state.squads) do
    if not r.d.disbanded and r.d.captain ~= name and (inList(r.d.members, name) or inList(r.d.bench, name)) then
      local p = state.profiles[name]
      if (not p or p.d.squad ~= id) and not M.isRejected(state, id, name, "inv") then out[#out + 1] = id end
    end
  end
  table.sort(out)
  return out
end

local function sameField(a, b)
  if type(a) == "table" and type(b) == "table" then return S.encode(a) == S.encode(b) end
  return a == b
end

local MOD_FIELDS = { approved = true, disbanded = true }
local RESET_FIELDS = { name = true, icon = true, color = true, border = true, motto = true }

local function validateSquad(state, rec, roster, settings, evict)
  local d, author = rec.d, rec.a
  if type(d.captain) ~= "string" or type(d.name) ~= "string" then return false, "shape" end
  d.name = M.trimName(d.name)
  d.members = d.members or {}
  d.bench = d.bench or {}
  if #d.bench > (settings.bench or 0) then return false, "benchFull" end
  if #d.members > M.SQUAD_SIZE then return false, "squadFull" end
  local seen = {}
  for _, n in ipairs(d.members) do if seen[n] then return false, "dup" end seen[n] = true end
  for _, n in ipairs(d.bench) do if seen[n] then return false, "dup" end seen[n] = true end
  if not d.disbanded and not seen[d.captain] then return false, "captainNotMember" end

  local stored = state.squads[rec.id]
  if not stored then
    if not d.ct or d.ct > rec.ts then d.ct = rec.ts end
    if d.disbanded then
      if author ~= d.captain and not P.isOfficer(roster, author, settings) then return false, "denied" end
      return true
    end
    if author ~= d.captain then return false, "denied" end
    local ok, why = P.canCreateSquad(roster, author, settings)
    if not ok then return false, why end
    local other = M.squadOf(state, author)
    if other and other ~= rec.id then return false, "oneSquad" end
    if (settings.maxSquads or 0) > 0 and M.liveSquads(state) >= settings.maxSquads then
      -- the limit keeps the squads with the lowest (ct, id), whatever the arrival order
      local worst
      for _, r in pairs(state.squads) do
        if not r.d.disbanded and (not worst or M.squadKeyLess(worst, r)) then worst = r end
      end
      if not worst or not M.squadKeyLess(rec, worst) then return false, "maxSquads" end
      evict[#evict + 1] = worst.id
    end
    if settings.requireApproval and not P.isOfficer(roster, author, settings) then d.approved = false end
  else
    local sd = stored.d
    d.ct = sd.ct or d.ct  -- creation ts is immutable once known
    if sd.disbanded and not P.isGM(roster, author) then return false, "disbanded" end
    -- a disband by the captain, an officer or the GM is a tombstone; its other fields do not matter
    if d.disbanded and not sd.disbanded then
      if author == sd.captain or P.isOfficer(roster, author, settings) then return true end
      return false, "denied"
    end
    if author == sd.captain or P.isGM(roster, author) then
      -- captain (or GM) may edit; only officers/GM may change approval when it is required
      if settings.requireApproval and d.approved ~= sd.approved and not P.isOfficer(roster, author, settings) then
        return false, "denied"
      end
    elseif author == d.captain and d.xferFrom == sd.captain then
      -- new captain writing after a transfer we never saw. Only valid when the CURRENT captain
      -- signed an earlier record (their own profile, xferTo = "squadId>NewCaptain") naming this player.
      local cp = state.profiles[sd.captain]
      if not (cp and cp.d.xferTo == rec.id .. ">" .. author and cp.ts <= rec.ts) then return false, "xfer" end
    elseif P.isOfficer(roster, author, settings) then
      -- an officer may also reset name/logo/motto to the neutral values (moderation)
      local reset = d.name == M.resetName(rec.id) and d.icon == 1 and d.color == 1 and d.border == 1 and (d.motto or "") == ""
      for f in pairs(M.SCHEMA.squad) do
        if f ~= "ct" and not MOD_FIELDS[f] and not (reset and RESET_FIELDS[f]) and not sameField(d[f], sd[f]) then
          return false, "denied"
        end
      end
    else
      return false, "denied"
    end
    if d.captain ~= sd.captain and not d.disbanded then
      -- transfer: new captain must already be a member and cannot captain another squad
      if author == sd.captain and not M.isMember(state, rec.id, d.captain) then return false, "notMember" end
      local other = M.squadOf(state, d.captain)
      if other and other ~= rec.id then return false, "oneSquad" end
    end
  end
  if not d.disbanded then
    local ok, why = M.checkName(d.name, settings)
    if not ok then return false, why end
    -- a name collision between CREATIONS is won by the lower (ct, id), independent of
    -- arrival order. An edit/rename of an existing squad never evicts another squad: it
    -- is refused with nameTaken (evicting would delete the younger squad on every client).
    -- refusing a rename depended on what each client already held (a client that only
    -- got the renamed version accepted it, the others refused it -> divergence forever). Now only a race between
    -- two untouched creation records keeps the (ct, id) rule; any other collision is accepted on every client and
    -- resolved for display by M.displayName (lower (nts, author, id) keeps the name). The UI still refuses to
    -- pick a taken name locally.
    local rival = M.nameRival(state, d.name, rec.id)
    if rival and not stored and pureCreation(rec) and pureCreation(rival) then
      if M.squadKeyLess(rival, rec) then return false, "nameTaken" end
      evict[#evict + 1] = rival.id
    end
  end
  return true
end

-------------------------------------------------------------------------------
-- record shape, timestamp bounds and provenance.
M.MIN_TS = 0                   -- negative timestamps are malformed
M.MAX_TS = 2147483647          -- int32 limit
M.MIN_SQ, M.MAX_SQ = -2147483648, 2147483647
M.MAX_FUTURE = 300             -- seconds a record may be ahead of GetServerTime()
local KIND = { settings = true, profile = true, squad = true, reject = true, annul = true, boss = true }

-- extra record kinds registered by other pure modules (Core/Roster.lua: roster, rsvp, attendance).
-- spec = { kind, tbl = state table name, order = import/flush order, apply = fn(state, rec, roster, settings, ctx) }
M.EXT, M.EXT_ORDER = {}, {}
function M.registerKind(kind, schema, tbl, order, applyFn)
  if KIND[kind] and not M.EXT[kind] then return false end
  M.SCHEMA[kind] = schema
  KIND[kind] = true
  if not M.EXT[kind] then M.EXT_ORDER[#M.EXT_ORDER + 1] = kind end
  M.EXT[kind] = { kind = kind, tbl = tbl, order = order or 9, apply = applyFn }
  return true
end
M.ORDER = { settings = 1, squad = 2, profile = 3, reject = 4, boss = 5, annul = 6 }
function M.kindOrder(k)
  if M.ORDER[k] then return M.ORDER[k] end
  local e = M.EXT[k]
  return e and e.order or 99
end

-- cheap structural check before anything else touches the record (never raises)
function M.validShape(rec)
  if type(rec) ~= "table" then return false, "shape" end
  if type(rec.k) ~= "string" or not KIND[rec.k] then return false, "kind" end
  if type(rec.id) ~= "string" or rec.id == "" or #rec.id > 300 then return false, "shape" end
  if type(rec.a) ~= "string" or rec.a == "" or #rec.a > 64 then return false, "shape" end
  if type(rec.ts) ~= "number" or rec.ts ~= rec.ts or type(rec.sq) ~= "number" or rec.sq ~= rec.sq then return false, "shape" end
  if rec.d ~= nil and type(rec.d) ~= "table" then return false, "shape" end
  if rec.ts < M.MIN_TS or rec.ts > M.MAX_TS then return false, "ts" end
  -- the sequence number is a finite integer in range (1e999 would break every re-encode)
  if rec.sq ~= math.floor(rec.sq) or rec.sq < M.MIN_SQ or rec.sq > M.MAX_SQ then return false, "shape" end
  return true
end

-- version string of a record ("kind:id@ts.sq.author"); hellos announce short hashes of the author's own versions
function M.versionKey(r) return r.k .. ":" .. r.id .. "@" .. r.ts .. "." .. r.sq .. "." .. r.a end
function M.versionHash(r) return S.hash(M.versionKey(r)):sub(1, 6) end

-- hashes of the records authored by `me` (newest first, at most `max`)
function M.announce(state, me, max)
  local mine = {}
  for _, r in ipairs(M.allRecords(state)) do if r.a == me then mine[#mine + 1] = r end end
  table.sort(mine, function(x, y) if x.ts ~= y.ts then return x.ts > y.ts end return x.id < y.id end)
  local out = {}
  for i = 1, math.min(#mine, max or 40) do out[#out + 1] = M.versionHash(mine[i]) end
  return out
end

-- Relay trust. ctx.sender = who physically sent it (nil = unsigned API
-- call: tests/import).
--   live (sender == author) -> ok
--   relayed (sender ~= author) -> ok only if the relayer is GM/officer. There is no "announced hash" path:
--   a 24-bit non-cryptographic hash can be forged offline in seconds (ctx.announced is ignored on purpose).
--   no sender = local API call (own writes, own disk, tests); Sync always passes the sender, import passes ns.me().
function M.provenance(rec, ctx, settings)
  if ctx.trusted then return true end
  local roster = ctx.roster
  if ctx.sender then
    if ctx.sender == rec.a then return true end
    if P.isOfficer(roster, ctx.sender, settings) then return true end
    return false, "relay"
  end
  return true
end

-- Apply a record. ctx = { roster = fn, sender?, trusted?, now? }. Returns ok, reason.
function M.apply(state, rec, ctx)
  local okS, whyS = M.validShape(rec)
  if not okS then return false, whyS end
  ctx = ctx or {}
  local roster = ctx.roster
  if ctx.now and rec.ts > ctx.now + M.MAX_FUTURE then return false, "future" end
  local data = sanitize(rec.k, rec.d)
  if not data then return false, "shape" end
  rec = { k = rec.k, id = rec.id, a = rec.a, ts = rec.ts, sq = rec.sq, d = data }
  if not P.inGuild(roster, rec.a) then return false, "notInGuild" end
  local settings = M.settingsOf(state)
  local okP, whyP = M.provenance(rec, ctx, settings)
  if not okP then return false, whyP end

  if rec.k == "settings" then
    if rec.id ~= "settings" then return false, "shape" end
    if M.same(rec, state.settings) then return false, "dup" end
    if not M.newer(rec, state.settings, roster) then return false, "stale" end
    if not P.canEditSettings(roster, rec.a) then return false, "denied" end
    M.normalizeSettings(data)
    state.settings = rec
    return true, "applied"
  elseif rec.k == "profile" then
    if rec.a ~= rec.id then return false, "denied" end
    local cur = state.profiles[rec.id]
    if M.same(rec, cur) then return false, "dup" end
    if not M.newer(rec, cur) then return false, "stale" end
    state.profiles[rec.id] = rec
    return true, "applied"
  elseif rec.k == "squad" then
    local cur = state.squads[rec.id]
    if M.same(rec, cur) then return false, "dup" end
    local tombstoneWins = data.disbanded and cur and not cur.d.disbanded and not P.isGM(roster, cur.a)
    if cur and cur.d.disbanded and not data.disbanded and not P.isGM(roster, rec.a) then return false, "disbanded" end
    if not tombstoneWins and not M.newer(rec, cur, roster) then return false, "stale" end
    if not settings.squadsEnabled and not P.isGM(roster, rec.a) and not data.disbanded then
      return false, "disabled"
    end
    local evict = {}
    local ok, why = validateSquad(state, rec, roster, settings, evict)
    if not ok then return false, why end
    for _, id in ipairs(evict) do state.squads[id] = nil; state.evicted = state.evicted or {}; state.evicted[id] = rec.id end
    state.squads[rec.id] = rec
    return true, "applied"
  elseif rec.k == "reject" then
    local d = data
    if type(d.sid) ~= "string" or type(d.name) ~= "string" or (d.kind ~= "req" and d.kind ~= "inv") then return false, "shape" end
    if rec.id ~= M.rejectId(d.sid, d.name, d.kind) then return false, "shape" end
    state.rejects = state.rejects or {}
    local cur = state.rejects[rec.id]
    if M.same(rec, cur) then return false, "dup" end
    if not M.newer(rec, cur, roster) then return false, "stale" end
    if d.kind == "inv" then
      if rec.a ~= d.name then return false, "denied" end           -- only the invited player declines
    else
      local sq = state.squads[d.sid]                                -- only the captain (or the GM) rejects a request
      if not sq or (sq.d.captain ~= rec.a and not P.isGM(roster, rec.a)) then return false, "denied" end
    end
    state.rejects[rec.id] = rec
    return true, "applied"
  elseif rec.k == "annul" then
    -- GM only, mandatory reason, id must match; validated locally on every client
    local d = data
    if type(d.race) ~= "string" or type(d.key) ~= "string" or rec.id ~= d.race .. "|" .. d.key then return false, "shape" end
    if type(d.reason) ~= "string" or d.reason:gsub("%s", "") == "" then return false, "reason" end
    if not P.isGM(roster, rec.a) then return false, "denied" end
    state.annuls = state.annuls or {}
    local cur = state.annuls[rec.id]
    if M.same(rec, cur) then return false, "dup" end
    if not M.newer(rec, cur, roster) then return false, "stale" end
    state.annuls[rec.id] = rec
    return true, "applied"
  elseif rec.k == "boss" then
    -- anyone in the guild teaches a boss once (no duplicates); only the GM changes it later / marks `final`
    local d = data
    if type(d.inst) ~= "string" or d.inst == "" or not ((d.enc and d.enc > 0) or (type(d.name) == "string" and d.name ~= "")) then
      return false, "shape"
    end
    if rec.id:sub(1, #d.inst + 1) ~= d.inst .. "." then return false, "shape" end
    state.bosses = state.bosses or {}
    local cur = state.bosses[rec.id]
    local gm = P.isGM(roster, rec.a)
    if not gm then d.final = nil end
    if M.same(rec, cur) then return false, "dup" end
    if cur and not gm then
      -- deterministic first writer. A non-GM record replaces a non-GM one only when it is
      -- earlier (ts, author, sq): every peer converges on the same record whatever the arrival order.
      if P.isGM(roster, cur.a) or not M.earlier(rec, cur) then return false, "dup" end
      state.bosses[rec.id] = rec
      return true, "applied"
    end
    -- a GM record always replaces a non-GM one, whatever the ts: otherwise a GM who taught the same boss at the
    -- same moment as a member (skewed clocks) would keep his own record while every other client kept the
    -- member's: two catalogs forever. Between GM records the newer one wins.
    if cur and P.isGM(roster, cur.a) and not M.newer(rec, cur, roster) then return false, "stale" end
    state.bosses[rec.id] = rec
    return true, "applied"
  end
  local ext = M.EXT[rec.k]
  if ext and ext.apply then return ext.apply(state, rec, roster, settings, ctx) end
  return false, "kind"
end

-------------------------------------------------------------------------------
-- Sync helpers: bucketed state hashes so peers only resend what differs.
local function bucketOf(id, nb)
  local h = 0
  for i = 1, #id do h = (h * 31 + id:byte(i)) % 65521 end
  return (h % nb) + 1
end
M.bucketOf = bucketOf

local function kindTable(state, kind)
  if kind == "profile" then return state.profiles end
  if kind == "squad" then return state.squads end
  if kind == "settings" then return state.settings and { settings = state.settings } or {} end
  if kind == "reject" then state.rejects = state.rejects or {}; return state.rejects end
  if kind == "annul" then state.annuls = state.annuls or {}; return state.annuls end
  if kind == "boss" then state.bosses = state.bosses or {}; return state.bosses end
  local ext = M.EXT[kind]
  if ext then state[ext.tbl] = state[ext.tbl] or {}; return state[ext.tbl] end
  return {}
end
M.kindTable = kindTable
-- the stored record with the same kind and id (nil when none)
function M.stored(state, rec)
  if rec.k == "settings" then return state.settings end
  local t = kindTable(state, rec.k)
  return t and t[rec.id]
end

function M.bucketHashes(state, kind, nb)
  nb = nb or M.NBUCKETS
  local lists = {}
  for i = 1, nb do lists[i] = {} end
  for id, r in pairs(kindTable(state, kind)) do
    local b = lists[bucketOf(id, nb)]
    b[#b + 1] = id .. "@" .. r.ts .. "." .. r.sq .. "." .. r.a
  end
  local out = {}
  for i = 1, nb do
    table.sort(lists[i])
    out[i] = #lists[i] == 0 and "0" or S.hash(table.concat(lists[i], ",")):sub(1, 6)
  end
  return out
end

-- records of `kind` whose bucket hash differs from `remote` (list of hashes)
function M.diffRecords(state, kind, remote, nb)
  nb = nb or M.NBUCKETS
  local mine = M.bucketHashes(state, kind, nb)
  local out = {}
  for id, r in pairs(kindTable(state, kind)) do
    local b = bucketOf(id, nb)
    if not remote or remote[b] ~= mine[b] then out[#out + 1] = r end
  end
  table.sort(out, function(x, y) return x.id < y.id end)
  return out
end

function M.allRecords(state)
  local out = {}
  if state.settings then out[#out + 1] = state.settings end
  for _, r in pairs(state.squads) do out[#out + 1] = r end
  for _, r in pairs(state.profiles) do out[#out + 1] = r end
  for _, r in pairs(state.rejects or {}) do out[#out + 1] = r end
  for _, r in pairs(state.annuls or {}) do out[#out + 1] = r end
  for _, r in pairs(state.bosses or {}) do out[#out + 1] = r end
  for _, k in ipairs(M.EXT_ORDER) do
    for _, r in pairs(state[M.EXT[k].tbl] or {}) do out[#out + 1] = r end
  end
  return out
end

-------------------------------------------------------------------------------
-- SavedVariables are per account, data is per guild: GuildSquadsDB.guilds[guildKey].
-- legacy top-level data (records/progress/races) is adopted by the first guild whose roster contains at least
-- half of the legacy record authors AND the author (GM) of the settings record; with no records, half of the
-- authors of the progress events / race observations; with no authors at all (empty data), any
-- guild. Otherwise it stays untouched for the character of the right guild. inGuild(name) -> bool.
M.LEGACY_KEYS = { "records", "progress", "races" }

-- WoW Forever surnames. GetGuildRosterInfo returns "Fire Essency" (character +
-- space + surname) while UnitName / CHAT_MSG_ADDON give "Fire". Character names have no spaces, so everything after
-- the first space is the surname. Accepted: "Fire", "Fire Essency", "Fire-Realm", "Fire Essency-Realm",
-- "Fire-Realm Essency". Returns the character key ("Fire-Realm", the same as ns.fullName of the bare name) and the
-- surname (nil when there is none). Plain find, never %s patterns: the split must not depend on the locale.
function M.charName(raw, realm)
  if type(raw) ~= "string" or raw == "" then return nil end
  local name, surname = raw, nil
  local sp = string.find(raw, " ", 1, true)
  if sp then
    local head, tail = string.sub(raw, 1, sp - 1), string.sub(raw, sp + 1)
    local dash = string.find(tail, "-", 1, true)
    if string.find(head, "-", 1, true) or not dash then
      name, surname = head, tail                                                   -- "Fire Essency", "Fire-Realm Essency"
    else
      name, surname = head .. string.sub(tail, dash), string.sub(tail, 1, dash - 1) -- "Fire Essency-Realm"
    end
  end
  if name == "" or string.sub(name, 1, 1) == "-" then return nil end
  if surname == "" then surname = nil end
  if not string.find(name, "-", 1, true) then name = name .. "-" .. tostring(realm or "") end
  return name, surname
end
function M.guildKey(name, realm)
  if type(name) ~= "string" or name == "" then return nil end
  return name .. "-" .. ((type(realm) == "string" and realm ~= "") and realm or "?")
end
function M.guildDB(root, key, inGuild)
  if type(root) ~= "table" or type(key) ~= "string" then return nil, false end
  root.guilds = type(root.guilds) == "table" and root.guilds or {}
  local g = type(root.guilds[key]) == "table" and root.guilds[key] or {}
  root.guilds[key] = g
  local migrated = false
  local legacy = false
  for _, k in ipairs(M.LEGACY_KEYS) do if root[k] ~= nil then legacy = true end end
  if legacy and g.records == nil and g.progress == nil and g.races == nil then
    local function member(n) return type(inGuild) == "function" and inGuild(n) and true or false end
    local total, mine, gm = 0, 0, nil
    for _, r in ipairs(type(root.records) == "table" and root.records or {}) do
      if type(r) == "table" and type(r.a) == "string" then
        total = total + 1
        if member(r.a) then mine = mine + 1 end
        if r.k == "settings" and (not gm or (tonumber(r.ts) or 0) > (tonumber(gm.ts) or 0)) then gm = r end
      end
    end
    -- with no records, the authors of the legacy progress events / race observations decide
    if total == 0 then
      local ev = type(root.progress) == "table" and type(root.progress.events) == "table" and root.progress.events or {}
      local ob = type(root.races) == "table" and type(root.races.obs) == "table" and root.races.obs or {}
      for _, e in pairs(ev) do if type(e) == "table" and type(e.who) == "string" then total = total + 1; if member(e.who) then mine = mine + 1 end end end
      for _, e in pairs(ob) do if type(e) == "table" and type(e.by) == "string" then total = total + 1; if member(e.by) then mine = mine + 1 end end end
    end
    local okGuild = total == 0 or mine * 2 >= total
    -- the guild must contain the author (the GM) of the settings record, when there is one
    if gm and not member(gm.a) then okGuild = false end
    if okGuild then
      for _, k in ipairs(M.LEGACY_KEYS) do g[k] = root[k]; root[k] = nil end
      migrated = true
    end
  end
  -- drop SavedVariables entries carrying non-finite numbers (once, when upgrading to schema 3)
  if (tonumber(g.v) or 0) < 3 then M.scrubNonFinite(g) end
  g.v = 3
  return g, migrated
end

-- migration: an older format stored +-inf / NaN (decoded "n1e999;") in records, progress events and
-- race observations; they broke prune and every re-encode. Whole entries of those lists are dropped (they are
-- re-synced if valid elsewhere); any other non-finite number is removed from its table. Returns the count removed.
local function badNum(v) return type(v) == "number" and not M.finite(v) end
local function hasBad(t, depth)
  if depth > 20 then return false end
  for k, v in pairs(t) do
    if badNum(k) or badNum(v) then return true end
    if type(v) == "table" and hasBad(v, depth + 1) then return true end
  end
  return false
end
local function scrubIn(t, depth, n)
  if depth > 20 then return n end
  local drop = {}
  for k, v in pairs(t) do
    if badNum(k) or badNum(v) then drop[#drop + 1] = k
    elseif type(v) == "table" then n = scrubIn(v, depth + 1, n) end
  end
  for _, k in ipairs(drop) do t[k] = nil; n = n + 1 end
  return n
end
local function dropEntries(list, isArray)
  if type(list) ~= "table" then return 0 end
  local n = 0
  if isArray then
    local keep = {}
    for _, e in ipairs(list) do
      if type(e) == "table" and hasBad(e, 0) then n = n + 1 else keep[#keep + 1] = e end
    end
    for i = #list, 1, -1 do list[i] = nil end
    for i, e in ipairs(keep) do list[i] = e end
  else
    local drop = {}
    for k, e in pairs(list) do if type(e) == "table" and hasBad(e, 0) then drop[#drop + 1] = k end end
    for _, k in ipairs(drop) do list[k] = nil; n = n + 1 end
  end
  return n
end
function M.scrubNonFinite(g)
  if type(g) ~= "table" then return 0 end
  local n = dropEntries(g.records, true)
  if type(g.progress) == "table" then n = n + dropEntries(g.progress.events, false) end
  if type(g.races) == "table" then n = n + dropEntries(g.races.obs, false) end
  return scrubIn(g, 0, n)
end

-- Export/import (manual backup of the guild data). Text is escaped, single line.
function M.export(state)
  return "GSQ1:" .. S.escape(S.encode(M.allRecords(state)))
end

function M.import(state, text, ctx)
  if type(text) ~= "string" then return 0, 0 end
  local body = text:gsub("[\r\n]", ""):match("^%s*GSQ1:(.-)%s*$")
  if not body then return 0, 0, "format" end
  local ok, list = S.decode(S.unescape(body))
  if not ok or type(list) ~= "table" then return 0, 0, "decode" end
  -- drop non-table entries before sorting
  local clean = {}
  for _, r in ipairs(list) do if type(r) == "table" then clean[#clean + 1] = r end end
  list = clean
  -- settings first, then squads, then profiles keeps validation order sane
  table.sort(list, function(a, b)
    local oa, ob = M.kindOrder(a.k), M.kindOrder(b.k)
    if oa ~= ob then return oa < ob end
    return (tonumber(a.ts) or 0) < (tonumber(b.ts) or 0)
  end)
  local applied, rejected = 0, 0
  for _, r in ipairs(list) do
    if M.apply(state, r, ctx) then applied = applied + 1 else rejected = rejected + 1 end
  end
  return applied, rejected
end

return M
