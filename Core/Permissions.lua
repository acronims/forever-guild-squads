-- Guild Squads (MIT) - Core/Permissions.lua
-- Pure Lua. All decisions take an injected roster function:
--   roster(name) -> { rank = <0-based guild rank index>, online = bool, class = "WARRIOR", level = n } | nil
local _, ns = ...
ns = ns or {}

local P = {}
ns.Permissions = P

local function contains(list, v)
  if type(list) ~= "table" then return false end
  for i = 1, #list do if list[i] == v then return true end end
  return false
end
P.contains = contains

function P.rankOf(roster, name)
  local r = roster and name and roster(name)
  if not r or type(r.rank) ~= "number" then return nil end
  return r.rank
end

function P.inGuild(roster, name)
  return P.rankOf(roster, name) ~= nil
end

function P.isGM(roster, name)
  return P.rankOf(roster, name) == 0
end

function P.isOfficer(roster, name, settings)
  local rank = P.rankOf(roster, name)
  if rank == nil then return false end
  if rank == 0 then return true end
  return contains(settings and settings.officerRanks, rank)
end

function P.canEditSettings(roster, name)
  return P.isGM(roster, name)
end

function P.canCreateSquad(roster, name, settings)
  if not settings or not settings.squadsEnabled then return false, "disabled" end
  local rank = P.rankOf(roster, name)
  if rank == nil then return false, "notInGuild" end
  if rank > (settings.minCreateRank or 0) then return false, "rank" end
  return true
end

-- Captain-only operations (edit, invite, kick, transfer, disband). GM may always act.
function P.canManageSquad(roster, name, squadData)
  if not squadData then return false end
  if squadData.captain == name then return true end
  return P.isGM(roster, name)
end

return P
