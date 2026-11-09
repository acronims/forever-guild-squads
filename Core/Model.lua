-- Guild Squads (MIT) - Core/Model.lua
-- Pure Lua. Records, schema sanitising, last-writer-wins merge and authority validation.
-- Record: { k = kind, id = string, a = author, ts = number, sq = number, d = data }
local _, ns = ...
ns = ns or {}

local M = {}
ns.Model = M
local P = ns.Permissions
local S = ns.Serialize

M.PROTO = 3   -- 2.0 (docs/SPEC-v2.0-identidad.md §4): names are «Name Surname» identities; the 1.x is another network
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
    name = { "s", 24 }, captain = { "s", 64 }, members = { "L", 5, 64 }, bench = { "L", 2, 64 },
    icon = { "n" }, color = { "n" }, border = { "n" }, motto = { "s", 60 }, tags = { "L", 6, 16 },
    open = { "b" }, approved = { "b" }, disbanded = { "b" }, xferFrom = { "s", 64 },
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
  reject = { sid = { "s", 64 }, name = { "s", 64 }, kind = { "s", 3 }, at = { "n" }, on = { "b" } },
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
           rlList = {}, offEdit = false, adoptDays = 30 }
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
  set("adoptDays", clampInt(d.adoptDays, 1, 90, 30))
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
-- sec r3 M1: would applying this squad record evict another squad (maxSquads, name race)? Dry run on a copy of d.
function M.squadEvicts(state, rec, roster, settings)
  if type(rec) ~= "table" or rec.k ~= "squad" or type(rec.d) ~= "table" then return false end
  local d = {}
  for k, v in pairs(rec.d) do d[k] = v end
  local evict = {}
  local okV = pcall(validateSquad, state, { k = rec.k, id = rec.id, a = rec.a, ts = rec.ts, sq = rec.sq, d = d },
    roster, settings or M.settingsOf(state), evict)
  return okV and #evict > 0
end

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

-- AUTHORIAL kinds (v1.1, annex A of docs/SPEC-v1.1-sync-p2p.md): records that only describe their author or a
-- player decision of the author. A closed list, never deduced. Any member may relay them (Core/P2P.lua: quorum of 2,
-- captain nodes, repudiation). Exceptions that stay AUTHORITY because another record leans on them or they depend on
-- someone else's authority: a profile carrying xferTo (it signs a squad transfer, see validateSquad) and a
-- reject of kind "req" (the captain rejects a request).
-- v1.2 (docs/SPEC-v1.2-p2p.md): every other kind may be relayed by any member too, with a higher quorum
M.P2P_AUTH = true
M.P2P_KINDS = { profile = true, rsvp = true, witness = true, presence = true, reject = true, repudiate = true }
function M.isP2P(rec)
  if type(rec) ~= "table" or not M.P2P_KINDS[rec.k] then return false end
  local d = type(rec.d) == "table" and rec.d or {}
  if rec.k == "profile" and d.xferTo ~= nil then return false end
  if rec.k == "reject" and d.kind ~= "inv" then return false end
  return true
end

-- Relay trust. ctx.sender = who physically sent it (nil = unsigned API
-- call: tests/import).
--   live (sender == author) -> ok
--   relayed (sender ~= author) by a GM/officer -> ok. There is no "announced hash" path:
--   a 24-bit non-cryptographic hash can be forged offline in seconds (ctx.announced is ignored on purpose).
--   relayed by anyone else: authority kinds -> "relay" (refused, R06-1); authorial kinds -> "p2p" (Core/P2P.lua).
--   u = the sender forwards a version it holds unverified: never trusted, not even from an officer.
--   no sender = local API call (own writes, own disk, tests); Sync always passes the sender, import passes ns.me().
function M.provenance(rec, ctx, settings, u)
  if ctx.trusted then return true end
  local roster = ctx.roster
  if ctx.sender then
    if ctx.sender == rec.a then return true end
    -- v1.2 annex F: with signed manifests an officer's relay is not trusted on its own (a modified officer client
    -- could forge anyone's record): it goes through Core/P2P.lua like any relay and needs the author's signature
    if M.isP2P(rec) then return false, "p2p" end
    -- v1.2: authority records relayed by a member are not refused either: they wait for QUORUM_AUTH relayers
    -- (Core/P2P.lua). Their validation (validateSquad, canEdit...) runs unchanged when the quorum commits them.
    if M.P2P_AUTH then return false, "p2p" end
    return false, "relay"
  end
  return true
end

-- review D (A1): the names a record carries, by kind (the fields the 2.0 migration remaps, fixOwn below). With
-- profile.xferTo ("squadId>Name") and the author they must all be identities: M.aliasOf(rec, canon) gives the first one
-- that is not (canon(x) = ns.id(x) == x), nil when there is none. Empty strings are no names (empty raid slots).
M.NAME_FIELDS = {
  squad = { one = { "captain", "xferFrom" }, many = { "members", "bench" } },
  reject = { one = { "name" } },
  roster = { one = { "owner" }, many = { "main", "bench" } },
  rsvp = { one = { "name" } },
  attendance = { many = { "names" } },
  witness = { many = { "names" } },
  achgrant = { one = { "who" } },
  settings = { many = { "rlList" } },
}
function M.aliasOf(rec, canon)
  if not canon(rec.a) then return rec.a end
  local d = type(rec.d) == "table" and rec.d or {}
  local f = M.NAME_FIELDS[rec.k]
  if f then
    for _, k in ipairs(f.one or {}) do
      local v = d[k]
      if type(v) == "string" and v ~= "" and not canon(v) then return v end
    end
    for _, k in ipairs(f.many or {}) do
      local l = d[k]
      if type(l) == "table" then
        for _, v in ipairs(l) do if type(v) == "string" and v ~= "" and not canon(v) then return v end end
      end
    end
  end
  if rec.k == "profile" and type(d.xferTo) == "string" then
    local cut = #d.xferTo
    while cut > 0 and string.sub(d.xferTo, cut, cut) ~= ">" do cut = cut - 1 end
    local cap = cut > 0 and string.sub(d.xferTo, cut + 1) or ""
    if cap ~= "" and not canon(cap) then return cap end
  end
  return nil
end

-- Apply a record. ctx = { roster = fn, canon = fn?, sender?, me?, trusted?, now? }. Returns ok, reason.
-- canon (default ns.isCanon, set by GuildSquads.lua; absent when Core is loaded alone): "alias" for a record with a
-- name that is not an identity (review D, A1), before anything else reads it (also before "notInGuild": an alias is
-- never held as pending)
local applyKind
function M.apply(state, rec, ctx)
  local okS, whyS = M.validShape(rec)
  if not okS then return false, whyS end
  ctx = ctx or {}
  local roster = ctx.roster
  if ctx.now and rec.ts > ctx.now + M.MAX_FUTURE then return false, "future" end
  local data = sanitize(rec.k, rec.d)
  if not data then return false, "shape" end
  local u = rec.u == 1 or rec.u == true
  rec = { k = rec.k, id = rec.id, a = rec.a, ts = rec.ts, sq = rec.sq, d = data }
  local canon = ctx.canon or ns.isCanon
  if type(canon) == "function" then
    local bad = M.aliasOf(rec, canon)
    if bad ~= nil then
      if ns.noteAlias then ns.noteAlias(bad) end
      return false, "alias"
    end
  end
  if not P.inGuild(roster, rec.a) then return false, "notInGuild" end
  local settings = M.settingsOf(state)
  local okP, whyP = M.provenance(rec, ctx, settings, u)
  local X = ns.P2P
  if not okP then
    if whyP == "p2p" then
      if X then return X.offer(state, rec, ctx, settings, u) end
      return false, "relay"
    end
    return false, whyP
  end
  local restore
  if X then
    local okX, whyX, undo = X.before(state, rec, ctx)
    if not okX then return false, whyX end
    restore = undo
  end
  local ok, why = applyKind(state, rec, ctx, roster, settings, data)
  if ok then
    if X and not ctx.trusted then X.after(state, rec) end
  elseif restore then restore() end
  return ok, why
end

function applyKind(state, rec, ctx, roster, settings, data)
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

-- 2.0: the identity lives in Core/Identity.lua (docs/SPEC-v2.0-identidad.md §2). The 1.2.2 M.charName is gone: its
-- realm key is ns.Identity.realmKey, and outside Core/Identity.lua the code asks ns.id (AC9; tests/gates.js fails on
-- a charName / ns.fullName / ns.charKey reference). M.whisperTarget stays as the wrapper of its realm mode: the 1.2.2
-- target "Name Surname" (any realm) from a realm key and the roster surname; alt = with "-Realm". In WoW Forever
-- (mode forever) the target is the identity itself: ns.whisperTarget, never this.
function M.whisperTarget(key, surname, myRealm, alt) return ns.Identity.realmWhisper(key, surname, myRealm, alt) end
-------------------------------------------------------------------------------
-- 2.0 (docs/SPEC-v2.0-identidad.md §5, BRO D1 = drop): the SavedVariables of the 1.x, where a character was
-- "Name-Realm" (and "Name Surname-Realm" in the leftovers of the 1.2.0), move to the WoW Forever identity «Name Surname».
-- It replaces M.sweepSurnames of the 1.2.2. Only in forever mode (realm mode keeps "Name-Realm": nothing to do). An
-- identity never holds a "-" in forever mode, so both steps only touch names in the old form and give the same bytes
-- when they run again, with or without their marks (AC5 f).
--   step 1, guild partition g (g.idv ~= 2; the roster is read: ctx.id remaps through it):
--     1. trust (keys, pend, contested, suspects, alerts), manifests (sig.man, sig.own), certificates (cert.crt,
--        cert.own) and GuildSquadsDB.prevOwnKeys under an old name go: they are learned again in person on PROTO 3.
--     2. signed records of someone else in the old form go (D1), and their unverified copies (p2p.pend): they come
--        back when their author updates and signs them again.
--     3. records of a character of this account (ownKeys, prevOwnKeys, idOld, the one logging in) get their author
--        remapped and wait in g.resign with resign = true: never applied, sent nor relayed until that character logs
--        in (step 2). Unknown or ambiguous in the roster: they go.
--     4. names inside local unsigned data (progress events who / pres, race observations who / by / pres, pend):
--        remapped when the roster gives exactly one identity, otherwise out of the list (or the entry goes, when the
--        name is its subject); two «Kas» on the realm make «Kas-Realm» ambiguous there, even if one is me. The
--        per-character state of this account (hkState, pending, hkBase, sent) maps my old key to me.
--     5. g.idv = 2, g.idMigratedAt = the first ctx.now.
--   step 2, character (GuildSquadsDB.idv[me] ~= 2, or records of mine waiting in g.resign; after step 1):
--     1. ownKeys[old] goes (ns.myPk makes ownKeys[me]); idOld[old] = me (for the other partitions of this account).
--     2. my records in g.resign: a = me, the ids that are my name re-keyed (profile, presence) or rebuilt (reject, rsvp,
--        grant), the names inside remapped (a member without one identity leaves the list; a record whose own name
--        field has none goes), sq + 1 and ts = now (my version wins any copy), resign removed, back to g.records.
--        Repudiations deny 1.x versions: they go. g.sig.fresh = me: Sync.OwnManifest signs n = 1 with the new key.
--     3. GuildSquadsDB.idv[me] = 2.
-- ctx = { mode, id = fn(old) -> identity | nil (ns.id), me = my identity, oldMe = my 1.x key ("Kas-Realm"), now =
--   server time, dry = true (count only: a copy is migrated), eventId / obsId / rsvpId / grantId = the id builders of
--   Progress / Races / Roster / Catalog, note = fn(rec) (the ledger of my versions) }.
-- Returns { swept, dropped, resign, remapped, removed, resigned, guild = step 1 ran, char = step 2 ran }.
M.IDV = 2
local function isOld(n) return type(n) == "string" and string.find(n, "-", 1, true) ~= nil end
M.isOldName = isOld
local function sortedKeys(t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks, function(a, b) return tostring(a) < tostring(b) end)
  return ks
end
local function deepCopy(v, seen)
  if type(v) ~= "table" then return v end
  if seen[v] then return seen[v] end
  local out = {}
  seen[v] = out
  for k, x in pairs(v) do out[deepCopy(k, seen)] = deepCopy(x, seen) end
  return out
end
-- old name -> identity | nil (identities and other values pass unchanged).
--   strict: ctx.id alone (the roster index): «Kas-Realm» with two «Kas» on the realm is nil, even when one is me (in
--           data of others nobody can tell which one it was). For the names inside shared unsigned data.
--   own:    for what is this account's by construction (its records, its per-character state): my old key is me, an
--           account character already migrated is in root.idOld, the rest goes through ctx.id.
local function mappers(root, ctx)
  local idOld = type(root.idOld) == "table" and root.idOld or {}
  local function strict(n)
    if not isOld(n) then return n end
    if type(ctx.id) ~= "function" then return nil end
    local okI, v = pcall(ctx.id, n)
    if okI and type(v) == "string" and v ~= "" and not isOld(v) then return v end
    return nil
  end
  local function own(n)
    if not isOld(n) then return n end
    if n == ctx.oldMe then return ctx.me end
    local m = idOld[n]
    if type(m) == "string" and m ~= "" and not isOld(m) then return m end
    return strict(n)
  end
  return strict, own
end
-- a list of names with an old one: remapped, deduplicated, the ones without an identity out (untouched otherwise)
local function remapList(l, map, r)
  if type(l) ~= "table" then return l end
  local any = false
  for _, n in ipairs(l) do if isOld(n) then any = true; break end end
  if not any then return l end
  local out, seen = {}, {}
  for _, n in ipairs(l) do
    local m = n
    if isOld(n) then
      m = map(n)
      if m then r.remapped = r.remapped + 1 else r.removed = r.removed + 1 end
    end
    if m ~= nil and not seen[m] then seen[m] = true; out[#out + 1] = m end
  end
  return out
end
-- e[f] in the old form: remapped; false when it has no identity (the caller drops the entry or the field)
local function remapField(e, f, map, r)
  if not isOld(e[f]) then return true end
  local m = map(e[f])
  if not m then return false end
  e[f] = m
  r.remapped = r.remapped + 1
  return true
end
-- a map keyed by names (hkBase, sent): old keys re-keyed, the ones without an identity go
local function remapKeys(t, map, r)
  if type(t) ~= "table" then return end
  for _, k in ipairs(sortedKeys(t)) do
    if isOld(k) then
      local m, v = map(k), t[k]
      t[k] = nil
      if m and t[m] == nil then t[m] = v; r.remapped = r.remapped + 1 else r.removed = r.removed + 1 end
    end
  end
end
-- entries of a map keyed by an id built from their fields (progress events, race observations): the fields remapped,
-- the entry re-keyed with idOf; one whose subject (`must`) has no identity goes. Returns old id -> new id | false.
local function remapEntries(t, must, lists, idOf, map, r)
  local moved = {}
  if type(t) ~= "table" then return moved end
  for _, id in ipairs(sortedKeys(t)) do
    local e = t[id]
    if type(e) == "table" then
      local touched, keep = false, true
      for _, f in ipairs(must) do
        if isOld(e[f]) then touched = true; if not remapField(e, f, map, r) then keep = false end end
      end
      for _, f in ipairs(lists) do
        local l = e[f]
        local nl = keep and remapList(l, map, r) or l
        if nl ~= l then touched = true; e[f] = nl end
      end
      if not keep then
        t[id] = nil; moved[id] = false; r.removed = r.removed + 1
      elseif touched then
        local okI, nid = false, nil
        if type(idOf) == "function" then okI, nid = pcall(idOf, e) end
        if okI and type(nid) == "string" and nid ~= id then
          t[id] = nil
          if t[nid] == nil then t[nid] = e; moved[id] = nid else moved[id] = false end
        end
      end
    end
  end
  return moved
end

local function step1(root, g, ctx, strict, map, r)
  -- the characters of this account, by their old name (before prevOwnKeys is swept)
  local own = {}
  for _, t in ipairs({ root.ownKeys, root.prevOwnKeys, root.idOld }) do
    if type(t) == "table" then for n in pairs(t) do if isOld(n) then own[n] = true end end end
  end
  if isOld(ctx.oldMe) then own[ctx.oldMe] = true end
  -- 1. keys, manifests and certificates under an old name
  local function sweep(t)
    if type(t) ~= "table" then return end
    for _, k in ipairs(sortedKeys(t)) do if isOld(k) then t[k] = nil; r.swept = r.swept + 1 end end
  end
  local tr = type(g.trust) == "table" and g.trust or nil
  if tr then
    sweep(tr.keys); sweep(tr.pend); sweep(tr.contested); sweep(tr.suspects)
    if type(tr.alerts) == "table" then   -- "kind name" lines (Trust.lua alert): the ones naming an old name go
      local keep = {}
      for _, a in ipairs(tr.alerts) do
        local sp = type(a) == "string" and string.find(a, " ", 1, true)
        if sp and isOld(string.sub(a, sp + 1)) then r.swept = r.swept + 1 else keep[#keep + 1] = a end
      end
      if #keep ~= #tr.alerts then tr.alerts = keep end
    end
  end
  if type(g.sig) == "table" then sweep(g.sig.man); sweep(g.sig.own) end
  if type(g.cert) == "table" then sweep(g.cert.crt); sweep(g.cert.own) end
  sweep(root.prevOwnKeys)
  -- 2. and 3. signed records in the old form: someone else's go (D1); this account's wait in g.resign
  if type(g.records) == "table" then
    local keep, aside = {}, type(g.resign) == "table" and g.resign or {}
    for _, rec in ipairs(g.records) do
      if type(rec) == "table" and isOld(rec.a) then
        local n = own[rec.a] and map(rec.a) or nil
        if n then rec.a = n; rec.resign = true; aside[#aside + 1] = rec; r.resign = r.resign + 1
        else r.dropped = r.dropped + 1 end
      else keep[#keep + 1] = rec end
    end
    g.records = keep
    if #aside > 0 then g.resign = aside end
  end
  local pend = type(g.p2p) == "table" and type(g.p2p.pend) == "table" and g.p2p.pend or nil
  if pend then
    for _, kid in ipairs(sortedKeys(pend)) do
      local byV = pend[kid]
      if type(byV) == "table" then
        for _, vk in ipairs(sortedKeys(byV)) do
          local e = byV[vk]
          if type(e) == "table" and type(e.r) == "table" and isOld(e.r.a) then byV[vk] = nil; r.dropped = r.dropped + 1 end
        end
        if next(byV) == nil then pend[kid] = nil end
      end
    end
  end
  -- 4. names inside local unsigned data
  local pr = type(g.progress) == "table" and g.progress or nil
  if pr then
    remapEntries(pr.events, { "who" }, { "pres" }, ctx.eventId, strict, r)
    local hs = pr.hkState
    if type(hs) == "table" and type(hs.who) == "string" then        -- "<id>:<src>" (Progress.lua counterStep)
      local i = #hs.who
      while i > 0 and string.sub(hs.who, i, i) ~= ":" do i = i - 1 end
      local name = i > 0 and string.sub(hs.who, 1, i - 1) or hs.who
      if isOld(name) then
        local m = map(name)
        if m then hs.who = m .. string.sub(hs.who, i); r.remapped = r.remapped + 1 else pr.hkState = nil; r.removed = r.removed + 1 end
      end
    end
    if type(pr.pending) == "table" and isOld(pr.pending.who) then
      if not remapField(pr.pending, "who", map, r) then pr.pending.who, pr.pending.hk, pr.pending.cap = nil, 0, 0; r.removed = r.removed + 1 end
    end
  end
  local ra = type(g.races) == "table" and g.races or nil
  if ra then
    local moved = remapEntries(ra.obs, { "who", "by" }, { "pres" }, ctx.obsId, strict, r)
    if type(ra.pend) == "table" then                                 -- observation id -> t (Hall.lua retries)
      for _, id in ipairs(sortedKeys(ra.pend)) do
        local to = moved[id]
        local bar = type(id) == "string" and string.find(id, "|", 1, true)
        if to == false or (to == nil and bar and isOld(string.sub(id, 1, bar - 1))) then ra.pend[id] = nil; r.removed = r.removed + 1
        elseif to then local v = ra.pend[id]; ra.pend[id] = nil; if ra.pend[to] == nil then ra.pend[to] = v end end
      end
    end
    remapKeys(ra.hkBase, map, r)
    remapKeys(ra.sent, map, r)
  end
  -- 5. the mark
  g.idv = M.IDV
  g.idMigratedAt = g.idMigratedAt or ctx.now
end

-- my record r, waiting for its re-signature: the names inside remapped; false = it must go
local NAME_ID = { profile = true, presence = true }
local function fixOwn(rec, ctx, map, r)
  local d = type(rec.d) == "table" and rec.d or {}
  local k = rec.k
  if k == "repudiate" then return false end                         -- it denies a 1.x version: nothing left to deny
  if NAME_ID[k] and isOld(rec.id) then
    if map(rec.id) ~= ctx.me then return false end
    rec.id = ctx.me
  end
  local function single(f) return remapField(d, f, map, r) end
  local function many(f) local l = d[f]; if type(l) == "table" then d[f] = remapList(l, map, r) end end
  if k == "squad" then
    if not single("captain") then return false end
    many("members"); many("bench")
    if not single("xferFrom") then d.xferFrom = nil; r.removed = r.removed + 1 end
  elseif k == "profile" then
    if type(d.xferTo) == "string" then                              -- "squadId>NewCaptain" (the squad id is opaque)
      local cut = #d.xferTo
      while cut > 0 and string.sub(d.xferTo, cut, cut) ~= ">" do cut = cut - 1 end
      local cap = cut > 0 and string.sub(d.xferTo, cut + 1) or nil
      if cap and isOld(cap) then
        local m = map(cap)
        if m then d.xferTo = string.sub(d.xferTo, 1, cut) .. m; r.remapped = r.remapped + 1 else d.xferTo = nil; r.removed = r.removed + 1 end
      end
    end
  elseif k == "reject" then
    local was = d.name
    if not single("name") then return false end
    if d.name ~= was then rec.id = M.rejectId(d.sid, d.name, d.kind) end
  elseif k == "roster" then
    if not single("owner") then return false end
    many("main"); many("bench")
  elseif k == "rsvp" then
    local was = d.name
    if not single("name") then return false end
    if d.name ~= was and type(ctx.rsvpId) == "function" then rec.id = ctx.rsvpId(d.rid, d.name) end
  elseif k == "attendance" or k == "witness" then many("names")
  elseif k == "achgrant" then
    local was = d.who
    if not single("who") then return false end
    if d.who ~= was and type(ctx.grantId) == "function" then rec.id = ctx.grantId(d.ach, d.who) end
  elseif k == "settings" then many("rlList")
  end
  return true
end

local function step2(root, g, ctx, map, r)
  local me, oldMe = ctx.me, ctx.oldMe
  -- 1. the 1.x key of this character
  if isOld(oldMe) then
    if type(root.ownKeys) == "table" and root.ownKeys[oldMe] ~= nil then root.ownKeys[oldMe] = nil; r.swept = r.swept + 1 end
    root.idOld = type(root.idOld) == "table" and root.idOld or {}
    root.idOld[oldMe] = me
  end
  -- 2. my records waiting in g.resign (the ones of the other characters of this account keep waiting)
  local back, rest = {}, {}
  for _, rec in ipairs(type(g.resign) == "table" and g.resign or {}) do
    if type(rec) == "table" and (rec.a == me or (oldMe ~= nil and rec.a == oldMe)) then back[#back + 1] = rec else rest[#rest + 1] = rec end
  end
  if g.resign ~= nil then g.resign = (#rest > 0) and rest or nil end
  if #back > 0 then
    g.records = type(g.records) == "table" and g.records or {}
    local at = {}                                                    -- kid -> index in g.records (one version per kid)
    for i, rec in ipairs(g.records) do if type(rec) == "table" then at[tostring(rec.k) .. ":" .. tostring(rec.id)] = i end end
    for _, rec in ipairs(back) do
      if fixOwn(rec, ctx, map, r) then
        rec.a = me
        rec.sq = (tonumber(rec.sq) or 0) + 1
        rec.ts = math.max(tonumber(rec.ts) or 0, tonumber(ctx.now) or 0)
        rec.resign = nil
        local kid = tostring(rec.k) .. ":" .. tostring(rec.id)
        local i = at[kid]
        local cur = i and g.records[i]
        if not cur or (rec.ts > (tonumber(cur.ts) or 0)) or (rec.ts == (tonumber(cur.ts) or 0) and rec.sq > (tonumber(cur.sq) or 0)) then
          if i then g.records[i] = rec else g.records[#g.records + 1] = rec; at[kid] = #g.records end
          if type(ctx.note) == "function" then pcall(ctx.note, rec) end
        end
        r.resigned = r.resigned + 1
      else
        r.dropped = r.dropped + 1
      end
    end
    g.sig = type(g.sig) == "table" and g.sig or {}
    g.sig.fresh = me
  end
  -- 3. the mark
  root.idv = type(root.idv) == "table" and root.idv or {}
  root.idv[me] = M.IDV
end

function M.migrateIdentity(root, g, ctx)
  local r = { swept = 0, dropped = 0, resign = 0, remapped = 0, removed = 0, resigned = 0 }
  ctx = type(ctx) == "table" and ctx or {}
  if ctx.mode ~= "forever" or type(root) ~= "table" or type(g) ~= "table" then return r end
  if type(ctx.me) ~= "string" or ctx.me == "" or isOld(ctx.me) then return r end   -- no identity yet: nothing written
  if ctx.dry then
    local seen = {}
    local root2 = deepCopy(root, seen)
    local c2 = {}
    for k, v in pairs(ctx) do c2[k] = v end
    c2.dry, c2.note = nil, nil
    return M.migrateIdentity(root2, seen[g] or deepCopy(g, seen), c2)
  end
  local strict, map = mappers(root, ctx)
  if g.idv ~= M.IDV then step1(root, g, ctx, strict, map, r); r.guild = true end
  local mine = false
  for _, rec in ipairs(type(g.resign) == "table" and g.resign or {}) do
    if type(rec) == "table" and (rec.a == ctx.me or rec.a == ctx.oldMe) then mine = true; break end
  end
  if mine or not (type(root.idv) == "table" and root.idv[ctx.me] == M.IDV) then step2(root, g, ctx, map, r); r.char = true end
  return r
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
