-- Guild Squads (MIT) - Core/Catalog.lua
-- Pure Lua (no WoW API). The GM adapts the catalog of races and achievements.
--   achdef   (id = race or achievement id): on/off, Top size (open races only), visible name, and the GM's own races
--            ("gm.<slug>", metric level|boss|bg|prof|rep) or badges (metric "manual"). GM only, LWW per id.
--   achgrant (id = ach .. "|" .. who): the GM grants a badge (never a Top entry) with a mandatory reason;
--            on = false withdraws it and the record stays as history. GM only (no officers).
-- Both are extension kinds (M.registerKind, order 12 / 13): older clients refuse them as an unknown kind
-- (Model.validShape -> "kind", counted in Sync.stats.bad) and keep syncing everything else.
-- Disabled entries keep counting: Core/Races computes them as before and only marks them `off`;
-- what was already earned is shown under "Legado".
local _, ns = ...
ns = ns or {}

local C = {}
ns.Catalog = C
local M, P = ns.Model, ns.Permissions
local floor = math.floor

C.MAX_CUSTOM = 50           -- custom achievements / races per guild (the 51st is refused)
C.NAME_MAX = 32             -- visible name, bytes (UTF-8 safe cut)
C.ID_MAX = 64
C.CUSTOM_SIZE = 10          -- default / maximum Top of a custom race (level without filter: 100)
C.METRICS = { "level", "boss", "bg", "prof", "rep", "manual" }
local METRIC = {}
for _, m in ipairs(C.METRICS) do METRIC[m] = true end
-- bulk groups (Ajustes > Logros): nivel, clase, raza, mazmorras, bandas, PvP, profesiones, reputación, squad, personaje
C.GROUPS = { "level", "class", "race", "dungeon", "raid", "pvp", "prof", "rep", "squad", "char" }

-- name: 160 bytes on the wire so colour codes / links can be removed BEFORE the cut; stored <= C.NAME_MAX
C.SCHEMA_DEF = { on = { "b" }, size = { "n" }, name = { "s", 160 }, custom = { "b" }, metric = { "s", 8 },
                 param = { "s", 48 }, thr = { "n" }, scope = { "s", 6 },
                 sts = { "n" } }   -- sts: when the current size was set (Top floor, see R.place); absent = record ts
C.SCHEMA_GRANT = { ach = { "s", 64 }, who = { "s", 48 }, reason = { "s", 80 }, on = { "b" } }

-------------------------------------------------------------------------------
-- the catalog in use: state.achdefs / state.achgrants of C.state (tests) or ns.state (the addon)
function C.use(state) C.state = state end
local function st() return C.state or ns.state end
function C.defs() local s = st(); return (type(s) == "table" and type(s.achdefs) == "table") and s.achdefs or {} end
function C.grants() local s = st(); return (type(s) == "table" and type(s.achgrants) == "table") and s.achgrants or {} end

-------------------------------------------------------------------------------
-- ids and names
-- an id never carries separators used by other ids / packers ( | ~ ; , ), spaces or control characters
function C.validId(id)
  return type(id) == "string" and id ~= "" and #id <= C.ID_MAX and not id:find("[|~;,%s%c]") and true or false
end
local RACE_PREFIX = { "lvl.", "dng.", "raid.", "full.", "pvp.", "wpvp.", "prof.", "rep.", "legacy.", "squad." }
function C.isCustom(id) return type(id) == "string" and id:sub(1, 3) == "gm." end
-- a built-in race id (by prefix). Custom ids are races unless their metric is "manual".
function C.isRaceId(id, defs)
  if type(id) ~= "string" then return false end
  if C.isCustom(id) then
    local r = (defs or C.defs())[id]
    return not (r and r.d and r.d.metric == "manual")
  end
  for _, p in ipairs(RACE_PREFIX) do if id:sub(1, #p) == p then return true end end
  return false
end

-- visible name: colour codes, links, textures and any other "|" escape are removed, control characters dropped,
-- trimmed, at most C.NAME_MAX bytes without cutting a UTF-8 character
function C.cleanName(s)
  if type(s) ~= "string" then return nil end
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  s = s:gsub("|H.-|h(.-)|h", "%1"):gsub("|H[^|]*", ""):gsub("|h", "")
  s = s:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|n", " ")
  s = s:gsub("|", ""):gsub("%c", "")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  if #s > C.NAME_MAX then
    local cut = C.NAME_MAX
    -- step back over UTF-8 continuation bytes so the last character is complete
    while cut > 0 and s:byte(cut + 1) and s:byte(cut + 1) >= 128 and s:byte(cut + 1) < 192 do cut = cut - 1 end
    s = s:sub(1, cut):gsub("%s+$", "")
  end
  return s
end

-------------------------------------------------------------------------------
-- badges (insignias): the achievements of Core/Progress (P.ACHIEVEMENTS) and Core/Races
function C.badges()
  local out, R, Pr = {}, ns.Races, ns.Progress
  for _, a in ipairs(Pr and Pr.ACHIEVEMENTS or {}) do out[#out + 1] = { key = a.key, scope = a.scope } end
  for _, k in ipairs(R and R.SQUAD_ACH or {}) do out[#out + 1] = { key = k, scope = "squad" } end
  for _, h in ipairs(R and R.LEVELS or {}) do out[#out + 1] = { key = "lvl" .. h, scope = "char" } end
  for _, h in ipairs(R and R.LEVELS or {}) do out[#out + 1] = { key = "top100." .. h, scope = "char" } end
  for _, k in ipairs(R and R.CHAR_ACH or {}) do out[#out + 1] = { key = k, scope = "char" } end
  for _, n in ipairs(R and R.PVP_RANKS or {}) do out[#out + 1] = { key = "pvpRank" .. n, scope = "char" } end
  out[#out + 1] = { key = "allAboard", scope = "guild" }
  return out
end
local badgeScope
function C.badgeScope(key)
  if not badgeScope then
    badgeScope = {}
    for _, b in ipairs(C.badges()) do badgeScope[b.key] = b.scope end
  end
  return badgeScope[key]
end

-------------------------------------------------------------------------------
-- custom definitions
local function isInt(v) return type(v) == "number" and v == floor(v) end
local function upperSlug(s) return ns.Races and ns.Races.slug(s):upper() or tostring(s):upper() end
C.LEVELS_OK = {}
for _, h in ipairs({ 10, 20, 30, 40, 50, 60 }) do C.LEVELS_OK[h] = true end
function C.sizeMax(id, d)
  if C.isCustom(id) then
    if d and d.metric == "level" and (d.param or "") == "" then return 100 end
    return C.CUSTOM_SIZE
  end
  if id:find("^lvl%.all%.") then return 100 end
  if id:find("^full%.") then return 3 end
  return 10
end
-- built-in base size (Core/Races R.def without a catalog): the default Top of the family
function C.baseSize(id) return C.sizeMax(id) end

-- scope of a custom: char (level/prof/rep), group (boss), squad (bg), manual = char|squad
function C.scopeOf(d)
  if d.metric == "boss" then return "group" end
  if d.metric == "bg" then return "squad" end
  if d.metric == "manual" then return d.scope == "squad" and "squad" or "char" end
  return "char"
end

-- validates and normalises the custom fields in place (d already sanitised). -> true | false, why
function C.checkCustom(id, d)
  if d.custom ~= true or not METRIC[d.metric] then return false, "metric" end
  local m, p = d.metric, d.param or ""
  if m == "level" then
    if not C.LEVELS_OK[d.thr] then return false, "thr" end
    local kind, tok = p:match("^(%a+):(.+)$")
    if p ~= "" and not ((kind == "class" or kind == "race") and tok) then return false, "param" end
    if kind then p = kind .. ":" .. upperSlug(tok) end
  elseif m == "boss" then
    if not p:find("^[^.|]+%.[^.|]+$") then return false, "param" end
    d.thr = 1
  elseif m == "bg" then
    if not isInt(d.thr) or d.thr < 1 or d.thr > 1000 then return false, "thr" end
    if p ~= "" and ns.Races then p = ns.Races.slug(p) end
  elseif m == "prof" or m == "rep" then
    if p == "" then return false, "param" end
    if ns.Races then p = ns.Races.slug(p) end
    local hi = m == "rep" and 8 or 1000
    if not isInt(d.thr) or d.thr < 1 or d.thr > hi then return false, "thr" end
  else -- manual badge: no Top
    if d.size ~= nil or p ~= "" then return false, "shape" end
    d.thr = nil
  end
  d.param = p ~= "" and p or nil
  d.scope = C.scopeOf(d)
  if m ~= "manual" and d.size == nil then d.size = C.CUSTOM_SIZE end
  return true
end

-------------------------------------------------------------------------------
-- record validation (Model.apply -> ext.apply). GM only (rank 0, like `settings`), live or relayed alike: the
-- relay rule (sender = author, or a GM/officer relaying) runs before this in Model.provenance.
-- C.sizeGuard(id, size, sts) -> ok, why: optional local check installed by the glue (open race, not below the
-- entries it already has). Every client also applies the deterministic rule of R.place, so a client without the
-- guard (or with other data) shows the same Top.
local function countCustom(defs, except)
  local n = 0
  for id in pairs(defs) do if id ~= except and C.isCustom(id) then n = n + 1 end end
  return n
end
C.countCustom = countCustom

function C.applyDef(state, rec, roster)
  local d = rec.d
  if not C.validId(rec.id) then return false, "shape" end
  if not P.isGM(roster, rec.a) then return false, "denied" end
  if d.name ~= nil then
    d.name = C.cleanName(d.name)
    if d.name == "" then d.name = nil end
  end
  if d.sts ~= nil and (not isInt(d.sts) or d.sts > rec.ts) then d.sts = rec.ts end
  state.achdefs = state.achdefs or {}
  local cur = state.achdefs[rec.id]
  if C.isCustom(rec.id) then
    local okC, whyC = C.checkCustom(rec.id, d)
    if not okC then return false, whyC end
    -- the definition (metric, parameter, threshold) is fixed once created: only on/size/name change later
    if cur and cur.d and (cur.d.metric ~= d.metric or (cur.d.param or "") ~= (d.param or "") or cur.d.thr ~= d.thr) then
      return false, "immutable"
    end
  else
    if d.custom or d.metric or d.param or d.thr then return false, "shape" end
    d.scope = nil
    if d.size ~= nil and not C.isRaceId(rec.id) then return false, "catSize" end
  end
  if d.size ~= nil then
    if not isInt(d.size) or d.size < 1 or d.size > C.sizeMax(rec.id, d) then return false, "catSize" end
    local curSize = (cur and cur.d and cur.d.size) or (not C.isCustom(rec.id) and C.baseSize(rec.id)) or nil
    if curSize ~= d.size and C.sizeGuard then
      local okG, whyG = C.sizeGuard(rec.id, d.size, d.sts or rec.ts)
      if not okG then return false, whyG end
    end
  end
  if M.same(rec, cur) then return false, "dup" end
  if not M.newer(rec, cur, roster) then return false, "stale" end
  if C.isCustom(rec.id) and not cur and countCustom(state.achdefs, rec.id) >= C.MAX_CUSTOM then return false, "maxCustom" end
  state.achdefs[rec.id] = rec
  return true, "applied"
end

function C.grantId(ach, who) return tostring(ach) .. "|" .. tostring(who) end
function C.applyGrant(state, rec, roster)
  local d = rec.d
  if type(d.ach) ~= "string" or type(d.who) ~= "string" or d.who == "" or d.who:find("[|%c]") then return false, "shape" end
  if not C.validId(d.ach) or rec.id ~= C.grantId(d.ach, d.who) then return false, "shape" end
  if type(d.reason) ~= "string" or d.reason:gsub("%s", "") == "" then return false, "reason" end
  if not P.isGM(roster, rec.a) then return false, "denied" end
  -- badges only: a built-in achievement, or a custom one ("gm.*"; a custom RACE is refused when known)
  if C.isCustom(d.ach) then
    local def = state.achdefs and state.achdefs[d.ach]
    if def and def.d.metric ~= "manual" then return false, "notBadge" end
  elseif not C.badgeScope(d.ach) then return false, "notBadge" end
  state.achgrants = state.achgrants or {}
  local cur = state.achgrants[rec.id]
  if M.same(rec, cur) then return false, "dup" end
  if not M.newer(rec, cur, roster) then return false, "stale" end
  state.achgrants[rec.id] = rec
  return true, "applied"
end

if M and M.registerKind then
  M.registerKind("achdef", C.SCHEMA_DEF, "achdefs", 12, C.applyDef)
  M.registerKind("achgrant", C.SCHEMA_GRANT, "achgrants", 13, C.applyGrant)
end

-------------------------------------------------------------------------------
-- queries
function C.def(id, defs) local r = (defs or C.defs())[id]; return r and r.d or nil end
function C.isOn(id, defs)
  local d = C.def(id, defs)
  return not (d and d.on == false)
end
function C.label(id, defs)
  local d = C.def(id, defs)
  return d and type(d.name) == "string" and d.name ~= "" and d.name or nil
end

-- R.def decoration: effective size, label, off flag, custom category / scope
local CAT_OF = { level = "level", boss = "dungeon", bg = "pvp", prof = "other", rep = "other" }
function C.decorate(r, defs)
  local rec = (defs or C.defs())[r.id]
  r.base = r.size
  if not rec or not rec.d then return r end
  local d = rec.d
  if C.isCustom(r.id) then
    local cat = CAT_OF[d.metric] or "other"
    if d.metric == "level" and d.param then cat = d.param:match("^(%a+):") or "level" end
    if d.metric == "boss" then
      local b = ns.Content and ns.Content.bosses and ns.Content.bosses[d.param or ""]
      if b and b.kind == "raid" then cat = "raid" end
    end
    r.cat, r.scope, r.custom, r.metric = cat, d.scope or C.scopeOf(d), true, d.metric
    r.size = d.size or C.CUSTOM_SIZE
    r.base = r.size
    r.sizeTs = d.sts or rec.ts
  elseif type(d.size) == "number" and d.size >= 1 and d.size <= C.sizeMax(r.id) then
    r.size = d.size
    r.sizeTs = d.sts or rec.ts
  end
  if d.on == false then r.off = true end
  if type(d.name) == "string" and d.name ~= "" then r.label = d.name end
  return r
end

-- custom races grouped by metric for R.compute: { level = { [lv] = {...} }, boss = { [bossId] = {...} }, bg = {...},
-- prof = { [slug] = {...} }, rep = { [slug] = {...} }, all = {...} }
function C.customRaces(defs)
  local out = { level = {}, boss = {}, bg = {}, prof = {}, rep = {}, all = {} }
  local ids = {}
  for id in pairs(defs or C.defs()) do if C.isCustom(id) then ids[#ids + 1] = id end end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local d = (defs or C.defs())[id].d
    if d.metric ~= "manual" and METRIC[d.metric] then
      local cu = { id = id, metric = d.metric, param = d.param or "", thr = d.thr }
      out.all[#out.all + 1] = cu
      if d.metric == "level" then
        out.level[d.thr] = out.level[d.thr] or {}; table.insert(out.level[d.thr], cu)
      elseif d.metric == "bg" then table.insert(out.bg, cu)
      else
        local t = out[d.metric]
        t[cu.param] = t[cu.param] or {}; table.insert(t[cu.param], cu)
      end
    end
  end
  return out
end
function C.levelMatch(cu, cls, race)
  local kind, tok = cu.param:match("^(%a+):(.+)$")
  if not kind then return true end
  if kind == "class" then return cls ~= nil and upperSlug(cls) == tok end
  return race ~= nil and upperSlug(race) == tok
end

-- group of an id for the GM list and the bulk buttons
function C.groupOf(id, defs)
  if C.isCustom(id) then
    local d = C.def(id, defs) or {}
    if d.metric == "manual" then return d.scope == "squad" and "squad" or "char" end
    if d.metric == "level" then return (d.param and d.param:match("^(%a+):")) or "level" end
    if d.metric == "boss" then
      local b = ns.Content and ns.Content.bosses and ns.Content.bosses[d.param or ""]
      return (b and b.kind == "raid") and "raid" or "dungeon"
    end
    if d.metric == "bg" then return "pvp" end
    return d.metric
  end
  if id:find("^lvl%.all%.") then return "level" end
  if id:find("^lvl%.class%.") then return "class" end
  if id:find("^lvl%.race%.") then return "race" end
  if id:find("^dng%.") then return "dungeon" end
  if id:find("^raid%.") or id:find("^full%.") then return "raid" end
  if id:find("^pvp%.") or id:find("^wpvp%.") then return "pvp" end
  if id:find("^prof%.") then return "prof" end
  if id:find("^rep%.") then return "rep" end
  if id:find("^squad%.") then return "squad" end
  if id:find("^legacy%.") then return "char" end
  local sc = C.badgeScope(id)
  if sc == "squad" then return "squad" end
  return "char"
end

-- every id the GM can manage: computed races (pseudo rows "prof.*"/"rep.*" excluded), every badge, every custom
-- definition. -> sorted list of ids. hide(id) -> true skips it (e.g. pvp.rank.* in WoW Forever)
function C.knownIds(races, defs, hide)
  local seen, out = {}, {}
  local function add(id) if not seen[id] and not id:find("%*") and not (hide and hide(id)) then seen[id] = true; out[#out + 1] = id end end
  for id in pairs(races or {}) do add(id) end
  for _, b in ipairs(C.badges()) do add(b.key) end
  for id in pairs(defs or C.defs()) do add(id) end
  table.sort(out)
  return out
end

-- bulk: the records "on = <on>" for every id of `group` (nil = all) whose state differs. Each keeps its size and
-- name (LWW replaces the whole record). -> list of { id, d }
function C.bulk(ids, group, on, defs)
  defs = defs or C.defs()
  local out = {}
  for _, id in ipairs(ids) do
    if (group == nil or C.groupOf(id, defs) == group) and C.isOn(id, defs) ~= on then
      local cur = defs[id] and defs[id].d or {}
      local d = {}
      for k, v in pairs(cur) do d[k] = v end
      d.on = on
      out[#out + 1] = { id = id, d = d }
    end
  end
  return out
end

-- grants: active ones for an owner -> { [ach] = { ts, reason, by } }; history (all, newest first)
function C.grantsFor(owner, grants)
  local out = {}
  for _, rec in pairs(grants or C.grants()) do
    local d = rec.d
    if d and d.who == owner and d.on ~= false then out[d.ach] = { ts = rec.ts, reason = d.reason, by = rec.a } end
  end
  return out
end
function C.grantHistory(grants)
  local out = {}
  for _, rec in pairs(grants or C.grants()) do out[#out + 1] = rec end
  table.sort(out, function(a, b) if a.ts ~= b.ts then return a.ts > b.ts end return a.id < b.id end)
  return out
end

-- split an achievement list ({ key, ts? }) into what is shown and what goes to "Legado": a disabled
-- achievement is hidden, unless it was earned (ts) -> legacy
function C.splitLegacy(list, defs)
  local shown, legacy = {}, {}
  for _, a in ipairs(list or {}) do
    if C.isOn(a.key, defs) then shown[#shown + 1] = a
    elseif a.ts then a.legacy = true; legacy[#legacy + 1] = a end
  end
  return shown, legacy
end

-- the size guard of the glue, from the races it last computed (pure: tests build it the same way).
-- -> function(id, size, sts) -> ok | false, "catClosed" | "catEntries"
function C.guardFor(store, races)
  return function(id, size, sts)
    if store and store.closed and store.closed[id] then return false, "catClosed" end
    local r = races and races[id]
    if r then
      if r.state == "closed" then return false, "catClosed" end
      local n = 0
      for _, e in ipairs(r.entries or {}) do if not sts or (e.ts or 0) <= sts then n = n + 1 end end
      if size < n then return false, "catEntries" end
    end
    return true
  end
end

-- /gsq diag: achdef=<n> custom=<n> grants=<n> off=<n>
function C.stats(defs, grants)
  local n, custom, off, g = 0, 0, 0, 0
  for id, r in pairs(defs or C.defs()) do
    n = n + 1
    if C.isCustom(id) then custom = custom + 1 end
    if r.d and r.d.on == false then off = off + 1 end
  end
  for _ in pairs(grants or C.grants()) do g = g + 1 end
  return n, custom, g, off
end
function C.debugLine()
  return ("catalog achdef=%d custom=%d grants=%d off=%d"):format(C.stats())
end

-- slug id for a new custom from its name (unique against the current definitions)
function C.newId(name, defs)
  defs = defs or C.defs()
  local base = "gm." .. ((ns.Races and ns.Races.slug(name or "")) or "x"):gsub("[^%w_\128-\255]", ""):sub(1, 40)
  if base == "gm." or base == "gm.?" then base = "gm.logro" end
  local id, i = base, 1
  while defs[id] do i = i + 1; id = base .. "_" .. i end
  return id
end

return C
