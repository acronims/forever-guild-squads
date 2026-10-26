-- Guild Squads (MIT) - Core/Diag.lua
-- Pure Lua (no WoW API). Automatic diagnostics stored in GuildSquadsDB.diag: build/interface, which client APIs
-- exist, counters of the events seen, last ENCOUNTER_END arguments, the comm lock observed during an encounter,
-- honorable-kill readings. The report is plain text (copy from /gsq diag or send the SavedVariables file), size-capped.
local _, ns = ...
ns = ns or {}

local D = {}
ns.Diag = D

D.MAX_BYTES = 6000      -- report text cap
D.MAX_EVENTS = 60       -- distinct event names counted
D.MAX_NOTES = 20        -- free notes kept (newest)
D.VERSION = 1

-- API list: the one of GuildSquadsProbe (guild, comms, group, class, PvP, PvE, icons) + what /gsq ui reports
D.APIS = {
  guild = { "IsInGuild", "GetNumGuildMembers", "GetGuildRosterInfo", "GetGuildInfo", "C_GuildInfo.GuildRoster",
            "C_GuildInfo.CanEditOfficerNote", "C_GuildInfo.GetGuildRankOrder", "GuildControlGetNumRanks",
            "GuildControlGetRankName", "C_Club.GetGuildClubId" },
  comms = { "C_ChatInfo.SendAddonMessage", "C_ChatInfo.RegisterAddonMessagePrefix", "C_ChatInfo.InChatMessagingLockdown",
            "IsEncounterInProgress", "C_PvP.IsMatchActive", "C_ChallengeMode.IsChallengeModeActive", "issecretvalue",
            "ChatFrame_SendTell", "ChatFrameUtil.SendTell", "C_DateAndTime.GetSecondsUntilWeeklyReset",
            "C_AddOns.GetAddOnMetadata" },
  group = { "C_PartyInfo.InviteUnit", "IsInRaid", "GetNumGroupMembers", "GetRaidRosterInfo", "UnitInParty", "UnitInRaid",
            "UnitGroupRolesAssigned", "GetInstanceInfo", "IsInInstance" },
  class = { "UnitClass", "UnitLevel", "UnitRace", "GetSpecialization", "C_SpecializationInfo.GetSpecialization",
            "GetTalentTabInfo" },
  pvp = { "GetPVPLifetimeStats", "GetPVPSessionStats", "GetPVPThisWeekStats", "UnitHonor", "UnitPVPRank",
          "GetBattlefieldWinner", "C_PvP.GetActiveMatchWinner", "C_PvP.IsWarModeActive", "UnitFactionGroup" },
  pve = { "C_EncounterJournal", "EJ_GetEncounterInfo", "GetAchievementInfo" },
  ui = { "GetMacroIcons", "C_Texture.GetAtlasInfo", "RaidNotice_AddMessage", "GetServerTime", "GetBuildInfo" },
}
D.SECTIONS = { "guild", "comms", "group", "class", "pvp", "pve", "ui" }

-- events whose counters the report must always show (0 when never seen)
D.KEY_EVENTS = { "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_LEVEL_UP", "PVP_MATCH_COMPLETE", "UPDATE_BATTLEFIELD_SCORE",
                 "PLAYER_PVP_KILLS_CHANGED", "CHAT_MSG_ADDON:own", "CHAT_MSG_ADDON:other" }

function D.new()
  return { v = D.VERSION, apis = {}, events = {}, nEvents = 0, notes = {} }
end

-- keep an existing table (SavedVariables), repair its shape
function D.ensure(db)
  if type(db) ~= "table" or db.v ~= D.VERSION then return D.new() end
  db.apis = type(db.apis) == "table" and db.apis or {}
  db.events = type(db.events) == "table" and db.events or {}
  db.notes = type(db.notes) == "table" and db.notes or {}
  local n = 0
  for _ in pairs(db.events) do n = n + 1 end
  db.nEvents = n
  return db
end

-- has(path) -> boolean, e.g. has("C_PvP.GetActiveMatchWinner") ; lookup is a function(name) -> value
function D.scanApis(db, lookup)
  for _, sec in ipairs(D.SECTIONS) do
    db.apis[sec] = {}
    for _, name in ipairs(D.APIS[sec]) do
      local t, okAll = nil, true
      for part in name:gmatch("[^%.]+") do
        if t == nil then t = lookup(part) elseif type(t) == "table" then t = t[part] else okAll = false; break end
      end
      db.apis[sec][name] = (okAll and t ~= nil) and true or false
    end
  end
end

function D.count(db, event, now)
  if type(event) ~= "string" then return end
  local e = db.events[event]
  if not e then
    if db.nEvents >= D.MAX_EVENTS then return end
    e = { n = 0 }
    db.events[event] = e
    db.nEvents = db.nEvents + 1
  end
  e.n = e.n + 1
  e.last = now
end

local function argText(v)
  local t = type(v)
  if t == "string" then return '"' .. v:sub(1, 40) .. '"' end
  if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
  return t
end
-- store a short, typed copy of event arguments (never tables / functions)
function D.args(...)
  local out = {}
  for i = 1, math.min(select("#", ...), 10) do out[i] = argText((select(i, ...))) end
  return table.concat(out, ", ")
end

function D.note(db, key, text, now)
  db[key] = { text = tostring(text):sub(1, 200), ts = now }
end

function D.addNote(db, text, now)
  local n = db.notes
  n[#n + 1] = (now and (tostring(now) .. " ") or "") .. tostring(text):sub(1, 160)
  while #n > D.MAX_NOTES do table.remove(n, 1) end
end

-- the report: fixed sections, always the key event counters, capped at MAX_BYTES
function D.report(db, extra)
  db = D.ensure(db)
  local lines = { "== Guild Squads diag v" .. D.VERSION .. " ==" }
  local function add(s) lines[#lines + 1] = s end
  add("[build] " .. tostring(db.build or "?") .. " | interface " .. tostring(db.interface or "?") ..
      " | addon " .. tostring(db.addon or "?") .. " | locale " .. tostring(db.locale or "?"))
  add("[session] logins " .. tostring(db.logins or 0) .. " | last " .. tostring(db.lastLogin or "?"))
  add("[apis]")
  for _, sec in ipairs(D.SECTIONS) do
    local yes, no = {}, {}
    for _, name in ipairs(D.APIS[sec]) do
      local v = db.apis[sec] and db.apis[sec][name]
      if v == true then yes[#yes + 1] = name elseif v == false then no[#no + 1] = name end
    end
    add("  " .. sec .. " OK: " .. table.concat(yes, " ") .. " | NO: " .. table.concat(no, " "))
  end
  add("[events]")
  local seen = {}
  local row = {}
  for _, ev in ipairs(D.KEY_EVENTS) do
    seen[ev] = true
    row[#row + 1] = ev .. "=" .. tostring(db.events[ev] and db.events[ev].n or 0)
  end
  add("  " .. table.concat(row, " "))
  local others = {}
  for ev, e in pairs(db.events) do if not seen[ev] then others[#others + 1] = ev .. "=" .. tostring(e.n) end end
  table.sort(others)
  if #others > 0 then add("  " .. table.concat(others, " ")) end
  add("[encounter] last ENCOUNTER_END: " .. (db.lastEncounter and db.lastEncounter.text or "none"))
  add("[encounter] comm during encounter: " .. (db.encComm and db.encComm.text or "not observed yet"))
  add("[pvp] honorable kills: " .. (db.hk and db.hk.text or "no reading"))
  add("[pvp] last battleground: " .. (db.lastBg and db.lastBg.text or "none"))
  add("[overlord] " .. (db.overlord and db.overlord.text or "not checked"))
  add("[ui] " .. (db.ui and db.ui.text or "window not built yet"))
  for _, l in ipairs(extra or {}) do  -- a line that already has its own "[tag]" keeps it ("[roster] ...")
    l = tostring(l)
    add(l:sub(1, 1) == "[" and l or ("[extra] " .. l))
  end
  if #db.notes > 0 then
    add("[notes]")
    for _, nt in ipairs(db.notes) do add("  " .. nt) end
  end
  local text = table.concat(lines, "\n")
  if #text > D.MAX_BYTES then text = text:sub(1, D.MAX_BYTES - 16) .. "\n[truncated]" end
  return text
end

return D
