-- Guild Squads (MIT) - Core/Identity.lua
-- Pure Lua (no WoW API). 2.0 (docs/SPEC-v2.0-identidad.md §2): the identity of a character, one function for
-- every input (sender, roster, unit, typed name, saved 1.x data).
--   forever (WoW Forever: RegionalUniqueNamesEnabled() is true): "Name Surname", no realm, unique in the region
--           (Blizzard: "a full name that is unique within a region"; agents/research-surnames.md).
--   realm   (anything else): "Name-Realm", exactly the 1.2.2 key (the 1.2.2 ns.fullName / M.charName: I.realmKey).
-- I.id(a, b, ctx) -> identity or nil. ctx = { mode = "forever"|"realm", myRealm = "Realm", index = I.newIndex(),
-- isSecret = fn }: no globals. Rules: (a) not a string, empty or secret -> nil; (b) idempotent:
-- I.id(I.id(x)) == I.id(x); (c) never raises; (d) splits with plain string.find, never %s / %w (locale, UTF-8);
-- (e) case-insensitive only for ASCII (I.lower), the roster spelling wins; (f) in forever "X-Y" is a realm when Y is
-- my realm or a realm of the roster, a surname (chat link separator, «Kas-Pitas») otherwise.
local _, ns = ...
ns = ns or {}

local I = {}
ns.Identity = I

local find, sub, byte, gsub = string.find, string.sub, string.byte, string.gsub

-- ASCII-only lower case (rule e): string.lower depends on the C locale, and a non-ASCII byte must never change
local LOWER = {}
for c = 65, 90 do LOWER[string.char(c)] = string.char(c + 32) end
function I.lower(s)
  if type(s) ~= "string" then return s end
  return (gsub(s, "[A-Z]", LOWER))
end

-- surrounding blanks off, runs of spaces inside become one (typed names). Plain bytes, no %s.
local function blank(c) return c == 32 or (c ~= nil and c >= 9 and c <= 13) end
function I.trim(s)
  if type(s) ~= "string" then return s end
  local i, j = 1, #s
  while i <= j and blank(byte(s, i)) do i = i + 1 end
  while j >= i and blank(byte(s, j)) do j = j - 1 end
  if i > 1 or j < #s then s = sub(s, i, j) end
  while find(s, "  ", 1, true) do s = gsub(s, "  ", " ") end
  return s
end

-------------------------------------------------------------------------------
-- realm mode: the 1.2.2 code, unchanged (I.realmKey is the 1.2.2 M.charName; M.whisperTarget wraps I.realmWhisper)

-- "Fire", "Fire Essency", "Fire-Realm", "Fire Essency-Realm", "Fire-Realm Essency" -> "Fire-Realm" (realm = `realm`
-- when the name has none) and the surname (nil when there is none). Character names have no spaces: everything after
-- the first space is the surname.
function I.realmKey(raw, realm)
  if type(raw) ~= "string" or raw == "" then return nil end
  local name, surname = raw, nil
  local sp = find(raw, " ", 1, true)
  if sp then
    local head, tail = sub(raw, 1, sp - 1), sub(raw, sp + 1)
    local dash = find(tail, "-", 1, true)
    if find(head, "-", 1, true) or not dash then
      name, surname = head, tail                                     -- "Fire Essency", "Fire-Realm Essency"
    else
      name, surname = head .. sub(tail, dash), sub(tail, 1, dash - 1) -- "Fire Essency-Realm"
    end
  end
  if name == "" or sub(name, 1, 1) == "-" then return nil end
  if surname == "" then surname = nil end
  if not find(name, "-", 1, true) then name = name .. "-" .. tostring(realm or "") end
  return name, surname
end

-- 1.2.2 whisper target from a realm key and the roster surname: "Name Surname" (any realm); alt = with "-Realm"
function I.realmWhisper(key, surname, myRealm, alt)
  if type(key) ~= "string" or key == "" then return nil end
  local short, realm = string.match(key, "^([^-]+)%-(.+)$")
  if not short then short, realm = key, myRealm end
  local full = (type(surname) == "string" and surname ~= "") and (short .. " " .. surname) or short
  if alt and type(realm) == "string" and realm ~= "" then return full .. "-" .. realm end
  return full
end

-------------------------------------------------------------------------------
-- the roster index (ns.rosterIndex): byFirst[lower(first)] = { ids }, byFirstRealm[lower(first) .. "-" .. realm] =
-- { ids }, byLower[lower(id)] = id (false when two ids give the same lower case), byFull["First Surname"] = id (realm
-- mode, the 1.2.2 fullIdx; false when two keys share it), realms[realm] = true
function I.newIndex() return { byFirst = {}, byFirstRealm = {}, byLower = {}, byFull = {}, realms = {} } end

local function addTo(t, k, id)
  local list = t[k]
  if not list then t[k] = { id }; return end
  for _, x in ipairs(list) do if x == id then return end end
  list[#list + 1] = id
end
function I.indexAdd(ix, id, first, surname, realm)
  if type(ix) ~= "table" or type(id) ~= "string" or type(first) ~= "string" or first == "" then return end
  local lf = I.lower(first)
  addTo(ix.byFirst, lf, id)
  if type(realm) == "string" and realm ~= "" then
    addTo(ix.byFirstRealm, lf .. "-" .. realm, id)
    ix.realms[realm] = true
  end
  local low = I.lower(id)
  if ix.byLower[low] == nil then ix.byLower[low] = id elseif ix.byLower[low] ~= id then ix.byLower[low] = false end
  if type(surname) == "string" and surname ~= "" then
    local fk = first .. " " .. surname
    if ix.byFull[fk] == nil then ix.byFull[fk] = id elseif ix.byFull[fk] ~= id then ix.byFull[fk] = false end
  end
end

-- the roster gives "Name Surname-Realm" (forever), "Name-Realm" or the 1.2.0 forms: a dash always starts the realm.
-- -> first, surname, realm (nil when absent)
function I.split(raw)
  if type(raw) ~= "string" then return nil end
  local name, surname = raw, nil
  local sp = find(raw, " ", 1, true)
  if sp then
    local head, tail = sub(raw, 1, sp - 1), sub(raw, sp + 1)
    local dash = find(tail, "-", 1, true)
    if find(head, "-", 1, true) or not dash then name, surname = head, tail
    else name, surname = head .. sub(tail, dash), sub(tail, 1, dash - 1) end
  end
  local first, realm = name, nil
  local d = find(name, "-", 1, true)
  if d then first, realm = sub(name, 1, d - 1), sub(name, d + 1) end
  if surname == "" then surname = nil end
  if realm == "" then realm = nil end
  return first, surname, realm
end

-------------------------------------------------------------------------------
local EMPTY = I.newIndex()

local function isRealm(y, ctx, ix)
  return y == ctx.myRealm or (ix.realms[y] == true)
end

-- forever: "Name Surname"
local function foreverId(a, b, ctx)
  a = I.trim(a)
  if a == "" then return nil end
  if b ~= nil then b = I.trim(b); if b == "" then b = nil end end
  local ix = type(ctx.index) == "table" and ctx.index or EMPTY
  local first, surname, realm, link
  local sp = find(a, " ", 1, true)
  if sp then
    local head, tail = sub(a, 1, sp - 1), sub(a, sp + 1)
    local hd = find(head, "-", 1, true)
    if hd then                                    -- "Kas-Realm Pitas" (the 1.2.0 accepted it)
      first, realm, surname = sub(head, 1, hd - 1), sub(head, hd + 1), tail
    else
      first = head
      local td = find(tail, "-", 1, true)
      if td then surname, realm = sub(tail, 1, td - 1), sub(tail, td + 1)   -- "Kas Pitas-Realm": the realm goes
      else surname = tail end                                                -- "Kas Pitas"
    end
  else
    local d = find(a, "-", 1, true)
    if d then
      first = sub(a, 1, d - 1)
      local y = sub(a, d + 1)
      if isRealm(y, ctx, ix) then realm = y else surname, link = y, true end  -- rule (f)
    else
      first = a
    end
    if b and not surname then                     -- UnitName / UnitFullName: (name, surname)
      if isRealm(b, ctx, ix) then realm = realm or b else surname = b end
    end
  end
  if surname then
    -- nothing after a dash is ever part of the identity, and no blank around the surname (review D, B2: «Kas Pitas
    -- -Realm» gave «Kas Pitas », and the 2nd value «X-Y» an identity with a dash)
    local td = find(surname, "-", 1, true)
    if td then surname = sub(surname, 1, td - 1) end
    surname = I.trim(surname)
  end
  if not first or first == "" then return nil end
  if surname and surname ~= "" then
    local full = first .. " " .. surname
    local hit = ix.byLower[I.lower(full)]
    if hit then return hit end                    -- the roster spelling (also «kas pitas» typed)
    if link then return nil end                   -- «Kas-Pitas» only names a member of the roster
    return full
  end
  -- no surname (sender without it, a unit not cached yet, saved "Name-Realm"): the roster, when unambiguous
  local list
  if realm then list = ix.byFirstRealm[I.lower(first) .. "-" .. realm] else list = ix.byFirst[I.lower(first)] end
  if list and #list == 1 then return list[1] end
  return nil
end

-- realm: the 1.2.2 ns.fullName (plus a unit's (name, realm) pair, which the 1.2.2 glued by hand)
local function realmId(a, b, ctx)
  if type(b) == "string" and b ~= "" and not find(a, "-", 1, true) and not find(a, " ", 1, true) then
    a = a .. "-" .. b
  end
  if find(a, " ", 1, true) then
    if not find(a, "-", 1, true) then
      local ix = ctx.index
      local k = type(ix) == "table" and ix.byFull and ix.byFull[a]
      if k then return k end
    end
    return (I.realmKey(a, ctx.myRealm))
  end
  if find(a, "-", 1, true) then return a end
  return a .. "-" .. tostring(ctx.myRealm or "")
end

local function idCore(a, b, ctx)
  if type(a) ~= "string" or a == "" then return nil end
  local sec = ctx.isSecret
  if type(sec) == "function" and (sec(a) or (b ~= nil and sec(b))) then return nil end
  if type(b) ~= "string" then b = nil end
  if ctx.mode == "forever" then return foreverId(a, b, ctx) end
  if ctx.mode == "realm" then return realmId(a, b, ctx) end
  return nil
end

-- rule (b) by construction (review D, B2): an answer is only given when it is its own identity, so
-- I.id(I.id(x)) == I.id(x) for every x. The second pass is skipped when the answer is the input itself (the common
-- case: an identity asked again). Odd forms whose first answer is not a fixed point («Kas- Realm» in realm mode) -> nil.
function I.id(a, b, ctx)
  if type(ctx) ~= "table" then return nil end
  local ok, r = pcall(idCore, a, b, ctx)
  if not (ok and type(r) == "string" and r ~= "") then return nil end
  if r == a and b == nil then return r end
  local ok2, r2 = pcall(idCore, r, nil, ctx)
  if ok2 and r2 == r then return r end
  return nil
end

-- the first name of an identity ("Kas Pitas" -> "Kas", "Kas-Realm" -> "Kas")
function I.firstOf(id)
  if type(id) ~= "string" then return nil end
  local sp, d = find(id, " ", 1, true), find(id, "-", 1, true)
  local cut = sp and d and math.min(sp, d) or sp or d
  return cut and sub(id, 1, cut - 1) or id
end

-- the surname a name carries (forever: what follows the first space of its identity; realm: I.realmKey's)
function I.surnameOf(raw, ctx)
  if type(raw) ~= "string" or type(ctx) ~= "table" then return nil end
  if ctx.mode == "forever" then
    local id = I.id(raw, nil, ctx)
    local sp = id and find(id, " ", 1, true)
    return sp and sub(id, sp + 1) or nil
  end
  local _, surname = I.realmKey(raw, ctx.myRealm)
  return surname
end

return I
