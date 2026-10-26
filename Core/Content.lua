-- Guild Squads (MIT) - Core/Content.lua
-- Pure Lua. PvE content catalog for the rankings. Data only, easy to correct: names and level ranges of the
-- WoW Forever dungeons come from fan sources (not confirmed by Blizzard). Forever encounter/instance IDs are
-- unknown, so instances are matched by name (case-insensitive, English + known localized aliases) and by any
-- instanceID learned at runtime. Unknown instances never break anything: they count as classic content, weight 1.
local _, ns = ...
ns = ns or {}

local C = {}
ns.Content = C

-- kind: "dungeon" | "raid"; forever = new Forever content; final = name of the last boss (unknown for now)
C.DUNGEONS = {
  { key = "thanes", name = "Hall of Thanes", min = 13, max = 18 },
  { key = "lordaeron", name = "Ruins of Lordaeron", min = 15, max = 20 },
  { key = "excavation", name = "Excavation Site", min = 24, max = 29 },
  { key = "dalaran", name = "City of Dalaran", min = 28, max = 33 },
  { key = "drowned", name = "The Drowned City", min = 35, max = 40 },
  { key = "kroldok", name = "Krol'dok Stronghold", min = 40, max = 45 },
  { key = "alcaz", name = "Alcaz Prison", min = 48, max = 53 },
  { key = "blackmaw", name = "Blackmaw Hold", min = 55, max = 60 },
  { key = "shaper", name = "Shaper's Terrace", min = 58, max = 60 },
}
C.RAIDS = {
  { key = "barrow", name = "Barrow Deeps", size = 10 },
  { key = "hyjal", name = "Hyjal Summit", size = 20, alias = { "la cima hyjal", "cima hyjal", "monte hyjal" } },
  { key = "onyxia", name = "Onyxia's Lair", size = 40, alias = { "guarida de onyxia" } },
}
-- raids open on 9-Dec-2026 (UTC midnight; only used to show the "opens 9-Dec" notice)
C.RAIDS_OPEN_TS = 1796774400

local byKey, byName = {}, {}
C.learned = {}  -- instanceID -> key (filled at runtime; persisted by the WoW glue)

local function norm(s)
  if type(s) ~= "string" then return nil end
  s = s:lower():gsub("^%s+", ""):gsub("%s+$", "")
  return s
end
C.norm = norm

local function add(e, kind)
  e.kind, e.forever = kind, true
  e.final = e.final or nil
  if kind == "dungeon" then e.weight = 1 + e.min / 20 else e.weight = 1 end
  byKey[e.key] = e
  byName[norm(e.name)] = e
  for _, a in ipairs(e.alias or {}) do byName[norm(a)] = e end
end
for _, e in ipairs(C.DUNGEONS) do add(e, "dungeon") end
for _, e in ipairs(C.RAIDS) do add(e, "raid") end

function C.get(key) return byKey[key] end

-- localized-name map learned in game: name -> key (e.g. the esES name seen next to a known instanceID)
function C.learnName(name, key)
  local n = norm(name)
  if n and byKey[key] and not byName[n] then byName[n] = byKey[key] end
end

function C.learnId(instanceID, key)
  if type(instanceID) == "number" and instanceID > 0 and byKey[key] then C.learned[instanceID] = key end
end

-- name, instanceType ("party"/"raid"), instanceID -> entry. Unknown: classic default with weight 1.
-- noLearn = true for remote reports (only local ENCOUNTER_END data may teach the catalog)
function C.match(name, instanceType, instanceID, noLearn)
  local e = byName[norm(name) or ""]
  if not e and type(instanceID) == "number" and C.learned[instanceID] then e = byKey[C.learned[instanceID]] end
  if e and noLearn then return e end
  if e then
    if type(instanceID) == "number" and instanceID > 0 and not C.learned[instanceID] then C.learned[instanceID] = e.key end
    if name and norm(name) ~= norm(e.name) then C.learnName(name, e.key) end
    return e
  end
  local kind = instanceType == "raid" and "raid" or "dungeon"
  return { key = "classic:" .. (norm(name) or "?"), name = name or "?", kind = kind, weight = 1, forever = false }
end

-- keys of the 9 Forever dungeons (the "Ruta Forever" achievement)
function C.foreverDungeonKeys()
  local out = {}
  for _, e in ipairs(C.DUNGEONS) do out[#out + 1] = e.key end
  return out
end

-------------------------------------------------------------------------------
-- boss catalog that learns by itself: the first witnessed kill stores encounterID, name and instance;
-- the list is replicated (Model record kind "boss") so every client has the same one. `final` comes from the
-- static catalog (C.DUNGEONS[i].final = boss name) or from the GM (Ajustes > Contenido).
-- boss = { id, enc?, name, inst (instance key), kind, final? }
C.bosses = {}

-- id used by the races (dng.<M>.<JEFE>): encounterID when known, else the normalised boss name
function C.bossId(instKey, enc, name)
  local slug
  if type(enc) == "number" and enc > 0 then slug = tostring(enc)
  else slug = (norm(name) or "?"):gsub("%s+", "_"):gsub("[%.|~;,>@:%+]", "") end
  return tostring(instKey) .. "." .. slug, slug
end

-- returns the boss entry and true when it is new (no duplicates: same id = same boss).
-- a learned boss is `pending` (listed, but it neither counts as a required boss nor makes races)
-- until it is confirmed: a GM/officer record (confirmed = true) or a kill witnessed by >= 2 reporters (C.confirmBoss).
function C.learnBoss(instKey, enc, name, kind, confirmed)
  if type(instKey) ~= "string" or instKey == "" then return nil, false end
  if not ((type(enc) == "number" and enc > 0) or (type(name) == "string" and name ~= "")) then return nil, false end
  local id, slug = C.bossId(instKey, enc, name)
  local b = C.bosses[id]
  if b then
    if not b.name and type(name) == "string" then b.name = name end
    if confirmed then b.pending = nil end
    return b, false
  end
  local e = byKey[instKey]
  b = { id = id, slug = slug, enc = (type(enc) == "number" and enc > 0) and enc or nil,
        name = type(name) == "string" and name:sub(1, 64) or nil, inst = instKey, kind = kind or (e and e.kind) or "dungeon" }
  if e and e.final and b.name and norm(e.final) == norm(b.name) then b.final = true end
  if not confirmed and not b.final then b.pending = true end
  C.bosses[id] = b
  return b, true
end

-- GM: mark / unmark the final boss of an instance (only one final per instance)
function C.setFinal(id, on)
  local b = C.bosses[id]
  if not b then return false end
  if on then for _, o in pairs(C.bosses) do if o.inst == b.inst then o.final = nil end end end
  b.final = on and true or nil
  return true
end

function C.confirmBoss(id)
  local b = C.bosses[id]
  if b then b.pending = nil end
  return b ~= nil
end

-- confirmed bosses of an instance (the "required" list of the raid completion rule)
function C.bossesOf(instKey)
  local out = {}
  for _, b in pairs(C.bosses) do if b.inst == instKey and not b.pending then out[#out + 1] = b.slug end end
  table.sort(out)
  return out
end

function C.isFinal(instKey, slug, name)
  local b = C.bosses[tostring(instKey) .. "." .. tostring(slug)]
  if b and b.final then return true end
  local e = byKey[instKey]
  return (e and e.final and name and norm(e.final) == norm(name)) and true or false
end

function C.hasFinal(instKey)
  local e = byKey[instKey]
  if e and e.final then return true end
  for _, b in pairs(C.bosses) do if b.inst == instKey and b.final then return true end end
  return false
end

-- sorted list for Ajustes > Contenido
function C.bossList()
  local out = {}
  for _, b in pairs(C.bosses) do out[#out + 1] = b end
  table.sort(out, function(a, b) if a.inst ~= b.inst then return a.inst < b.inst end return a.id < b.id end)
  return out
end

return C
