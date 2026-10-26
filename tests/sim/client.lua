-- Guild Squads simulator: per-client glue loaded AFTER the addon files (same fengari state).
-- Exposes the addon namespace and the helpers the driver/scenarios use.
local ns = SIM_ns
local M, S = ns.Model, ns.Serialize
A = ns.Actions
NS = ns

-- every ns.debug line that looks like a Lua error (file:line:) is a caught error (runSafe / Sync / Comm)
local origDebug = ns.debug
ns.debug = function(msg)
  local s = tostring(msg)
  if s:find("%.lua:%d+:") or s:find("^sync error") then SIM_ERRORS[#SIM_ERRORS + 1] = "debug: " .. s end
  if origDebug then return origDebug(msg) end
end

-- canonical text of the replicated model: every record (kind, id, version, data), sorted
function SIM_modelText()
  local list = {}
  for _, r in ipairs(M.allRecords(ns.state)) do
    list[#list + 1] = r.k .. "|" .. r.id .. "|" .. tostring(r.ts) .. "|" .. tostring(r.sq) .. "|" .. tostring(r.a) .. "|" .. S.encode(r.d or {})
  end
  table.sort(list)
  return table.concat(list, "\n")
end
-- the GM's catalog (achdef + achgrant records, canonical text; "" on a client without the catalog) and the model
-- without those two kinds (what a client without the catalog must still share with everybody)
local CAT_KINDS = { achdef = true, achgrant = true }
function SIM_catalogText()
  local list = {}
  for _, r in ipairs(M.allRecords(ns.state)) do
    if CAT_KINDS[r.k] then list[#list + 1] = r.k .. "|" .. r.id .. "|" .. tostring(r.ts) .. "|" .. tostring(r.sq) .. "|" .. S.encode(r.d or {}) end
  end
  table.sort(list)
  return table.concat(list, "\n")
end
function SIM_catalogCount()
  local n, off = 0, 0
  for _, r in pairs(ns.state.achdefs or {}) do n = n + 1; if r.d.on == false then off = off + 1 end end
  return n .. "/" .. off
end
function SIM_coreHash()
  local list = {}
  for _, r in ipairs(M.allRecords(ns.state)) do
    if not CAT_KINDS[r.k] then
      list[#list + 1] = r.k .. "|" .. r.id .. "|" .. tostring(r.ts) .. "|" .. tostring(r.sq) .. "|" .. tostring(r.a) .. "|" .. S.encode(r.d or {})
    end
  end
  table.sort(list)
  return tostring(S.hash(table.concat(list, "\n"))) .. "#" .. #list
end
function SIM_modelHash() return tostring(S.hash(SIM_modelText())) .. "#" .. #M.allRecords(ns.state) end

function SIM_errorCount()
  local n = #SIM_ERRORS
  n = n + (ns.Sync.stats.errors or 0) + (ns.Comm.stats.handlerErrors or 0)
  return n
end
function SIM_errorText() return table.concat(SIM_ERRORS, "\n") end
function SIM_queue() return ns.Comm.queue:size() end

-- one random squad action for this client (r1, r2 in [0,1) from the driver's PRNG). Returns a label.
local function liveSquads()
  local ids = {}
  for id, r in pairs(ns.state.squads) do if not r.d.disbanded then ids[#ids + 1] = id end end
  table.sort(ids)
  return ids
end
function SIM_squadAction(r1, r2)
  local me = ns.me()
  local sid = A.MySquadId()
  local sq = sid and ns.state.squads[sid]
  if sq and sq.d.captain == me then
    -- captain: accept a pending request, or kick someone
    local reqs = {}
    for name, p in pairs(ns.state.profiles) do
      if p.d.squad == sid and not M.isMember(ns.state, sid, name) and name ~= me then reqs[#reqs + 1] = name end
    end
    table.sort(reqs)
    if #reqs > 0 and r1 < 0.8 then local n = reqs[1 + math.floor(r2 * #reqs)]; A.AddMember(sid, n); return "accept " .. n end
    local mem = {}
    for _, n in ipairs(sq.d.members) do if n ~= me then mem[#mem + 1] = n end end
    if #mem > 0 and r1 < 0.3 then local n = mem[1 + math.floor(r2 * #mem)]; A.Kick(sid, n); return "kick " .. n end
    return "idle"
  elseif sid then
    if r1 < 0.25 then A.Leave(); return "leave" end
    return "idle"
  else
    local p = ns.state.profiles[me]
    if p and p.d.squad and p.d.squad ~= "" and ns.state.squads[p.d.squad] and r1 < 0.7 then return "waiting" end
    local ids = liveSquads()
    if #ids > 0 then local id = ids[1 + math.floor(r2 * #ids)]; A.RequestJoin(id); return "request " .. id end
    return "none"
  end
end

-- generate records straight into this client's state (as if received earlier): profiles and squads
function SIM_genRecords(names, nSquads, t0)
  local roster = ns.roster
  local n = 0
  for i, name in ipairs(names) do
    local ok = M.apply(ns.state, { k = "profile", id = name, a = name, ts = t0 + i, sq = 1,
      d = { role = (i % 3 == 0) and "HEALER" or "DAMAGER", avail = "11001100", goals = { "dungeons" }, level = 60 } }, { roster = roster })
    if ok then n = n + 1 end
  end
  for s = 1, nSquads or 0 do
    local cap = names[(s - 1) * 5 + 1]
    local mem = {}
    for j = 1, 5 do mem[j] = names[(s - 1) * 5 + j] end
    local id = cap .. ":" .. (t0 + 1000 + s)
    local ok = M.apply(ns.state, { k = "squad", id = id, a = cap, ts = t0 + 1000 + s, sq = 2,
      d = { name = "Squad " .. s, captain = cap, members = mem, bench = {}, icon = 1, color = 1, border = 1, open = true, approved = true } }, { roster = roster })
    if ok then n = n + 1 end
    for j = 1, 5 do
      local nm = mem[j]
      if M.apply(ns.state, { k = "profile", id = nm, a = nm, ts = t0 + 2000 + s * 5 + j, sq = 3,
        d = { role = "DAMAGER", avail = "11001100", goals = { "dungeons" }, level = 60, squad = id } }, { roster = roster }) then n = n + 1 end
    end
  end
  return n
end

-- score + Top of a wipe, canonical text
function SIM_scoreText(wipe)
  local res = ns.ProgressGlue.Compute(wipe)
  local sids = {}
  for sid in pairs(res.squads or {}) do sids[#sids + 1] = sid end
  table.sort(sids)
  local parts = {}
  for _, sid in ipairs(sids) do
    local x = res.squads[sid]
    parts[#parts + 1] = sid .. "=" .. string.format("%.4f", tonumber(x.general) or 0)
  end
  local top = {}
  for i, e in ipairs(ns.Progress.ranking(res, "general")) do top[i] = tostring(e.sid) end
  return table.concat(parts, ";") .. " top:" .. table.concat(top, ",")
end
