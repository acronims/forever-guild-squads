-- Guild Squads (MIT) - Core/Serialize.lua
-- Pure Lua (5.1/5.3 compatible). No WoW API.
-- Deterministic, type-tagged, length-prefixed serializer + transport escaping + hash.
local _, ns = ...
ns = ns or {}

-- resolve a client API at call time. Each argument is a global name ("GuildRoster") or a dotted
-- path ("C_GuildInfo.GuildRoster"); returns the first one that is a function, or nil. Used where WoW Forever
-- 16001 moved or dropped a global, so a missing API never raises "attempt to call a nil value".
function ns.apiFn(...)
  for i = 1, select("#", ...) do
    local name = select(i, ...)
    local v = _G
    for part in string.gmatch(name, "[^%.]+") do
      if type(v) ~= "table" then v = nil; break end
      v = v[part]
    end
    if type(v) == "function" then return v end
  end
  return nil
end
-- IsEncounterInProgress is not a global in 16001; it lives in C_InstanceEncounter
function ns.encounterFn()
  return ns.apiFn("IsEncounterInProgress", "C_InstanceEncounter.IsEncounterInProgress")
end

local S = {}
ns.Serialize = S

local type, tostring, tonumber, pairs, sort, concat = type, tostring, tonumber, pairs, table.sort, table.concat
local floor, format, byte, sub, find = math.floor, string.format, string.byte, string.sub, string.find

local function keyOrder(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return ta < tb end
  return a < b
end

local function encodeNumber(n)
  if n ~= n or n == math.huge or n == -math.huge then error("cannot serialize non-finite number") end
  -- same range as the decoder (which drops |n| >= 1e15)
  if n >= 1e15 or n <= -1e15 then error("cannot serialize number out of range") end
  if n == floor(n) and n > -1e15 and n < 1e15 then return format("%d", n) end
  return format("%.17g", n)
end

local function enc(v, out, depth)
  if depth > 20 then error("table too deep") end
  local t = type(v)
  if t == "nil" then out[#out + 1] = "z"
  elseif t == "boolean" then out[#out + 1] = v and "T" or "F"
  elseif t == "number" then out[#out + 1] = "n" .. encodeNumber(v) .. ";"
  elseif t == "string" then out[#out + 1] = "s" .. #v .. ":" .. v
  elseif t == "table" then
    out[#out + 1] = "t"
    local keys = {}
    for k in pairs(v) do
      local kt = type(k)
      if kt == "string" or kt == "number" then keys[#keys + 1] = k end
    end
    sort(keys, keyOrder)
    for i = 1, #keys do
      enc(keys[i], out, depth + 1)
      enc(v[keys[i]], out, depth + 1)
    end
    out[#out + 1] = "e"
  else
    error("cannot serialize type " .. t)
  end
end

function S.encode(v)
  local out = {}
  enc(v, out, 0)
  return concat(out)
end

S.MAX_NUM = 1e15   -- |n| must stay below this (also excludes +-inf)

local BAD = {}      -- marker for a refused number

local function dec(s, pos, depth)
  if depth > 20 then error("table too deep") end
  local c = sub(s, pos, pos)
  if c == "z" then return nil, pos + 1
  elseif c == "T" then return true, pos + 1
  elseif c == "F" then return false, pos + 1
  elseif c == "n" then
    local e = find(s, ";", pos + 1, true)
    if not e then error("bad number") end
    local n = tonumber(sub(s, pos + 1, e - 1))
    if not n then error("bad number") end
    -- non-finite (strtod overflow "1e999" = inf, NaN) and out-of-range numbers never reach the
    -- addon. As a table value the field is dropped (BAD), so schema validation refuses that record and the rest of
    -- a batch survives; as a key or as the whole payload it is an error.
    if n ~= n or n >= S.MAX_NUM or n <= -S.MAX_NUM then return BAD, e + 1 end
    return n, e + 1
  elseif c == "s" then
    local e = find(s, ":", pos + 1, true)
    if not e then error("bad string") end
    local len = tonumber(sub(s, pos + 1, e - 1))
    if not len or len < 0 or e + len > #s then error("bad string length") end
    return sub(s, e + 1, e + len), e + 1 + len
  elseif c == "t" then
    local t = {}
    pos = pos + 1
    while true do
      if pos > #s then error("unterminated table") end
      if sub(s, pos, pos) == "e" then return t, pos + 1 end
      local k, v
      k, pos = dec(s, pos, depth + 1)
      if k == nil then error("nil key") end
      if k == BAD then error("bad number") end
      v, pos = dec(s, pos, depth + 1)
      if v ~= BAD then t[k] = v end
    end
  end
  error("bad tag at " .. pos)
end

-- Returns ok, value|error
function S.decode(s)
  if type(s) ~= "string" or s == "" then return false, "empty" end
  local ok, v, pos = pcall(dec, s, 1, 0)
  if not ok then return false, v end
  if v == BAD then return false, "bad number" end
  if pos ~= #s + 1 then return false, "trailing data" end
  return true, v
end

-- Transport escaping: removes bytes that are unsafe in addon/chat messages.
local ESC = { ["~"] = "~a", ["|"] = "~b", ["\n"] = "~c", ["\r"] = "~d", ["\0"] = "~e" }
local UNESC = { a = "~", b = "|", c = "\n", d = "\r", e = "\0" }

function S.escape(s)
  return (s:gsub("[~|\n\r%z]", ESC))
end

function S.unescape(s)
  return (s:gsub("~(.)", function(ch) return UNESC[ch] or "" end))
end

-- Simple non-cryptographic hash (two 31-bit polynomial hashes, no bit ops).
function S.hash(s)
  local h1, h2 = 7, 13
  for i = 1, #s do
    local b = byte(s, i)
    h1 = (h1 * 31 + b) % 2147483647
    h2 = (h2 * 37 + b) % 2147483629
  end
  return format("%08x%08x", h1, h2)
end

return S
