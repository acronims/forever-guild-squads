-- Guild Squads (MIT) - Core/Match.lua
-- Pure Lua. "Encaje" (fit) score with an explainable list of reasons, plus finder filters.
local _, ns = ...
ns = ns or {}

local X = {}
ns.Match = X

X.WANT = { TANK = 1, HEALER = 1, DAMAGER = 3 }

-- needs from a list of member profile data tables
function X.roleNeeds(memberProfiles)
  local need = { TANK = X.WANT.TANK, HEALER = X.WANT.HEALER, DAMAGER = X.WANT.DAMAGER }
  for _, p in ipairs(memberProfiles or {}) do
    if p.role and need[p.role] and need[p.role] > 0 then need[p.role] = need[p.role] - 1 end
  end
  return need
end

function X.availOverlap(a, b)
  if type(a) ~= "string" or type(b) ~= "string" then return 0 end
  local n = 0
  for i = 1, math.min(#a, #b) do
    if a:sub(i, i) == "1" and b:sub(i, i) == "1" then n = n + 1 end
  end
  return n
end

-- union of availability strings ("1" if any member has the slot)
function X.availUnion(list)
  local out = {}
  for i = 1, 8 do out[i] = "0" end
  for _, a in ipairs(list or {}) do
    if type(a) == "string" then
      for i = 1, 8 do if a:sub(i, i) == "1" then out[i] = "1" end end
    end
  end
  return table.concat(out)
end

-- player: { role, role2, avail, level, goals = {..} }
-- target: { needs = {TANK=n,...} | nil, avail, level, goals = {..} }
-- returns score 0..100 and reasons = { {key, value}, ... }
function X.score(player, target)
  local score, reasons = 0, {}
  if target.needs then
    if player.role and (target.needs[player.role] or 0) > 0 then
      score = score + 40; reasons[#reasons + 1] = { "role", player.role }
    elseif player.role2 and (target.needs[player.role2] or 0) > 0 then
      score = score + 20; reasons[#reasons + 1] = { "role2", player.role2 }
    end
  end
  local ov = X.availOverlap(player.avail, target.avail)
  if ov > 0 then
    score = score + math.min(30, ov * 10); reasons[#reasons + 1] = { "avail", ov }
  end
  if type(player.level) == "number" and type(target.level) == "number" then
    local diff = math.abs(player.level - target.level)
    local pts = (diff <= 2 and 20) or (diff <= 5 and 10) or (diff <= 10 and 5) or 0
    if pts > 0 then score = score + pts; reasons[#reasons + 1] = { "level", diff } end
  end
  local shared = 0
  local tg = {}
  for _, g in ipairs(target.goals or {}) do tg[g] = true end
  for _, g in ipairs(player.goals or {}) do
    if tg[g] then
      shared = shared + 1
      if shared <= 2 then score = score + (shared == 1 and 10 or 5); reasons[#reasons + 1] = { "goal", g } end
    end
  end
  if score > 100 then score = 100 end
  return score, reasons
end

-- L: locale table with keys REASON_role, REASON_role2, REASON_avail, REASON_level, REASON_goal, ROLE_*, GOAL_*
function X.reasonText(reasons, L)
  L = L or {}
  local parts = {}
  for _, r in ipairs(reasons) do
    local k, v = r[1], r[2]
    local fmt = L["REASON_" .. k] or (k .. ": %s")
    if k == "role" or k == "role2" then v = L["ROLE_" .. v] or v
    elseif k == "goal" then v = L["GOAL_" .. v] or v end
    parts[#parts + 1] = string.format(fmt, tostring(v))
  end
  if #parts == 0 then return L.REASON_none or "-" end
  return table.concat(parts, ", ")
end

-- a filter value may be a single string or a set { KEY = true } (OR inside the group).
-- returns nil when the filter is absent or the set is empty (= no filter).
local function asSet(v)
  if v == nil then return nil end
  if type(v) ~= "table" then return { [v] = true } end
  if next(v) == nil then return nil end
  return v
end
X.asSet = asSet

-- filters: { role, class, goal (string or set), minLevel, maxLevel, availWith (string), onlineOnly }
-- entry: { role, role2, class, level, avail, goals, online, needs }
-- groups combine with AND; values inside one group combine with OR.
function X.passes(entry, f)
  if not f then return true end
  local roles = asSet(f.role)
  if roles then
    local hit = (entry.role and roles[entry.role]) or (entry.role2 and roles[entry.role2])
    if not hit and entry.needs then
      for r in pairs(roles) do if (entry.needs[r] or 0) > 0 then hit = true end end
    end
    if not hit then return false end
  end
  local classes = asSet(f.class)
  if classes and not (entry.class and classes[entry.class]) then return false end
  if f.minLevel and (entry.level or 0) < f.minLevel then return false end
  if f.maxLevel and (entry.level or 0) > f.maxLevel then return false end
  if f.availWith and X.availOverlap(entry.avail, f.availWith) == 0 then return false end
  local goals = asSet(f.goal)
  if goals then
    local hit = false
    for _, g in ipairs(entry.goals or {}) do if goals[g] then hit = true end end
    if not hit then return false end
  end
  if f.onlineOnly and not entry.online then return false end
  return true
end

return X
