-- Guild Squads (MIT) - UI/Hall.lua
-- "Salón de la fama" tab: centred filter chips (Nivel · Clase · Raza · Mazmorras · Bandas · PvP · Otros) +
-- export on the top row (nothing under the portrait), race list with state and n/N, detail with first/second/third
-- place medals, time and mark (exacta / aprox. / testigos / informado por el jugador), tooltip with participants
-- and support, GM right-click "Anular entrada (motivo)" with confirmation. Plus "Mis logros" (profile grid).
local _, ns = ...
local L, W, UI, M, P, Pr, R, Content = ns.L, ns.W, ns.UI, ns.Model, ns.Permissions, ns.Progress, ns.Races, ns.Content
local ICONS = "Interface\\Icons\\"

local FILTERS = { "level", "class", "race", "dungeon", "raid", "pvp", "other" }
local F_ICON = { level = ICONS .. "Spell_ChargePositive", class = ICONS .. "INV_Misc_Book_09", race = ICONS .. "INV_Misc_Head_Human_01",
                 dungeon = ICONS .. "INV_Misc_Key_03", raid = ICONS .. "INV_Misc_Head_Dragon_01", pvp = ICONS .. "INV_Sword_27",
                 other = ICONS .. "INV_Misc_Note_01" }
local MEDAL = { "|cffffd100", "|cffc0c0c0", "|cffcd7f32" } -- 1st / 2nd / 3rd
local hall = { cat = "level", sel = nil }
local function H() return ns.HallGlue end
local function isGM() return P.isGM(ns.roster, ns.me()) and true or false end

-------------------------------------------------------------------------------
-- labels
local function className(token)
  token = tostring(token or "")
  local t = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
  if type(t) == "table" and type(t[token]) == "string" then return t[token] end
  return token:sub(1, 1) .. token:sub(2):lower()
end
UI.ClassName = className
local function raceName(token)
  token = tostring(token or "")
  return rawget(L, "RACE_" .. token:upper()) or (token:sub(1, 1) .. token:sub(2):lower())
end
UI.RaceName = raceName
local function instName(key)
  local e = Content.get(key)
  return e and e.name or tostring(key):gsub("_", " ")
end
local function bossName(ik, slug)
  local b = Content.bosses[ik .. "." .. slug]
  return (b and b.name) or tostring(slug):gsub("_", " ")
end

function UI.RaceTitle(id)
  local lab = ns.Catalog and ns.Catalog.label(id)   -- the GM's visible name (the id never changes)
  if lab then return lab end
  local h = id:match("^lvl%.all%.(%d+)$")
  if h then return L.RT_LVL_ALL:format(tonumber(h)) end
  local c, hc = id:match("^lvl%.class%.([^.]+)%.(%d+)$")
  if c then return L.RT_LVL_OF:format(className(c), tonumber(hc)) end
  local rc, hr = id:match("^lvl%.race%.([^.]+)%.(%d+)$")
  if rc then return L.RT_LVL_OF:format(raceName(rc), tonumber(hr)) end
  if id == "dng.all" then return L.RT_DNG_ALL end
  if id == "raid.all" then return L.RT_RAID_ALL end
  local fs = id:match("^full%.(%d+)$")
  if fs then return L.RT_FULL:format(tonumber(fs)) end
  local kind, ik, b = id:match("^(%a+)%.([^.]+)%.([^.]+)$")
  if (kind == "dng" or kind == "raid") and ik then return instName(ik) .. " · " .. bossName(ik, b) end
  local k2, ik2 = id:match("^(%a+)%.([^.]+)$")
  if (k2 == "dng" or k2 == "raid") and ik2 then return L.RT_COMPLETE:format(instName(ik2)) end
  local cr, sea = id:match("^pvp%.rank%.class%.([^.]+)%.14%.s(.+)$")
  if cr then return L.RT_RANK_CLASS:format(className(cr), sea) end
  local rk, sea2 = id:match("^pvp%.rank%.(%d+)%.s(.+)$")
  if rk then return L.RT_RANK:format(tonumber(rk), sea2) end
  local n = id:match("^pvp%.hk%.(%d+)$"); if n then return L.RT_HK:format(tonumber(n)) end
  n = id:match("^pvp%.bg%.(%d+)$"); if n then return L.RT_BG:format(tonumber(n)) end
  local map = id:match("^pvp%.bgmap%.(.+)$"); if map then return L.RT_BGMAP:format((map:gsub("_", " "))) end
  n = id:match("^wpvp%.caps%.(%d+)$"); if n then return L.RT_CAPS:format(tonumber(n)) end
  local pf, pn = id:match("^prof%.([^.]+)%.(%d+)$"); if pf then return L.RT_PROF:format(pf:gsub("_", " "), tonumber(pn)) end
  local rf = id:match("^rep%.([^.]+)%.exalted$"); if rf then return L.RT_REP:format((rf:gsub("_", " "))) end
  n = id:match("^legacy%.(%d+)$"); if n then return L.RT_LEGACY:format(tonumber(n)) end
  if id == "squad.full60" then return L.RT_FULL60 end
  if id == "prof.*" then return L.RT_PROF_ANY end
  if id == "rep.*" then return L.RT_REP_ANY end
  return id
end

local function stateText(r)
  if r.state == "nodata" then return "|cff999999" .. L.HALL_NODATA .. "|r" end
  if r.state == "closed" then return "|cffff8040" .. L.HALL_CLOSED .. "|r" end
  return L.HALL_OPEN:format(#r.entries, r.size)
end
UI.RaceStateText = stateText

local function timeText(ts) return ts and Pr.formatDate(ts) or "" end

-------------------------------------------------------------------------------
-- filter chip
local function chip(parent, cat)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(24)
  b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(20, 20); b.icon:SetPoint("LEFT", 3, 0); b.icon:SetTexture(F_ICON[cat])
  b.text = W.Label(b, L["HF_" .. cat], "GameFontHighlightSmall"); b.text:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
  b:SetWidth(math.min(74, W.num(b.text:GetStringWidth(), 44) + 28)) -- 7 chips + export fit centred (<= 580 px)
  function b:SetOn(v)
    if v then self.bg:SetColorTexture(0.6, 0.45, 0.1, 0.95); self.text:SetTextColor(1, 1, 1); self.icon:SetDesaturated(false)
    else self.bg:SetColorTexture(0.1, 0.1, 0.1, 0.9); self.text:SetTextColor(0.6, 0.6, 0.6); self.icon:SetDesaturated(true) end
  end
  b:SetScript("OnClick", function() hall.cat = cat; hall.sel = nil; UI.Select("hall") end)
  b.cat = cat
  W.Tooltip(b, L["HF_" .. cat], L.HALL_FILTER_TIP)
  return b
end

-- race list row
local function makeRace(parent)
  local c = W.Card(parent)
  c.name = W.Label(c, "", "GameFontHighlightSmall"); c.name:SetPoint("LEFT", 8, 0); c.name:SetWidth(170)
  if c.name.SetWordWrap then c.name:SetWordWrap(false) end
  c.state = W.Label(c, "", "GameFontHighlightSmall"); c.state:SetPoint("RIGHT", -8, 0); c.state:SetWidth(96)
  if c.state.SetJustifyH then c.state:SetJustifyH("RIGHT") end
  return c
end
local function fillRace(c, r)
  local title = UI.RaceTitle(r.id)
  -- a disabled race with entries is listed under "Legado", dimmed, with the "legacy" tag
  if r.off then title = "|cff888888" .. title .. " (" .. L.LEGACY_TAG .. ")|r" end
  c.name:SetText((hall.sel == r.id and "|cffffd100" or "") .. title .. (hall.sel == r.id and "|r" or ""))
  c.state:SetText(stateText(r))
  c.border.set(hall.sel == r.id and 1 or 0.3, hall.sel == r.id and 0.82 or 0.3, hall.sel == r.id and 0 or 0.3, 1)
  c:SetScript("OnClick", function() hall.sel = r.id; UI.Select("hall") end)
  W.Tooltip(c, title, stateText(r) .. (#(r.pending or {}) > 0 and ("\n" .. L.HALL_PENDING:format(#r.pending)) or ""))
end

local function entryTip(tt, e)
  tt:SetText(H().EntryLabel(e), 1, 0.82, 0)
  tt:AddLine(timeText(e.ts) .. " · " .. (L["MARK_" .. tostring(e.mark)] or tostring(e.mark)), 0.8, 0.8, 0.8)
  if e.wit then tt:AddLine(L.HALL_WIT:format(e.wit), 0.7, 0.7, 0.7) end
  local names = {}
  for _, n in ipairs(e.chars or {}) do names[#names + 1] = ns.shortName(n) end
  if #names > 0 then tt:AddLine(L.HALL_PARTICIPANTS .. ": " .. table.concat(names, ", "), 1, 1, 1, true) end
  local sup = {}
  for _, n in ipairs(e.sup or {}) do sup[#sup + 1] = ns.shortName(n) end
  if #sup > 0 then tt:AddLine(L.HALL_SUPPORT .. ": " .. table.concat(sup, ", "), 0.6, 0.8, 1, true) end
  if e.ex then tt:AddLine(L.HALL_EX, 0.6, 0.6, 0.6) end
  if isGM() then tt:AddLine(L.HALL_ANNUL_HINT, 0.5, 0.5, 0.5) end
end

function UI.HallAnnul(raceId, e)
  if not isGM() then return false end
  W.Prompt(L.HALL_ANNUL_REASON:format(H().EntryLabel(e)), function(reason)
    if type(reason) ~= "string" or reason:gsub("%s", "") == "" then ns.print(L.HALL_ANNUL_NEEDS_REASON); return end
    W.Confirm(L.HALL_ANNUL_CONFIRM:format(H().EntryLabel(e), reason), function()
      local okA, why = H().Annul(raceId, e.key, reason)
      if not okA then ns.ShowError(why) end   -- translated text, once
      UI.Select("hall")
    end)
  end, L.HALL_ANNUL_OK, 80)
  return true
end

local function makeEntry(parent)
  local c = W.Card(parent)
  c.pos = W.Label(c, "", "GameFontNormal"); c.pos:SetPoint("LEFT", 6, 0); c.pos:SetWidth(30)
  c.name = W.Label(c, "", "GameFontHighlight"); c.name:SetPoint("LEFT", 38, 0); c.name:SetWidth(170)
  if c.name.SetWordWrap then c.name:SetWordWrap(false) end
  c.time = W.Label(c, "", "GameFontHighlightSmall"); c.time:SetPoint("RIGHT", -8, 0); c.time:SetWidth(150)
  if c.time.SetJustifyH then c.time:SetJustifyH("RIGHT") end
  if c.time.SetWordWrap then c.time:SetWordWrap(false) end   -- one line in the 28 px row
  return c
end
-- an unverified observation: grey "?" + tooltip; GM / officers get "Confirmar" on click
local UV_GREY = "|cffbfbfbf"   -- contrast
local function uvLabel(ev)
  local who = ns.shortName(ev.who or ev.by or "?")
  -- localized counter name, not the raw key ("hk 100")
  local what = ev.t == "cnt" and ((rawget(L, "HALL_CNT_" .. tostring(ev.k)) or tostring(ev.k or "")) .. " " .. tostring(ev.n or ""))
               or (ev.boss or ev.inst or ev.t or "")
  return who .. " · " .. what
end
function UI.HallConfirm(oid)
  if not H().CanConfirm() then return false end
  local okC, why = H().Confirm(oid)
  if not okC then ns.ShowError(why) else ns.Feedback(true, L.HALL_UV_CONFIRMED) end
  UI.Select("hall")
  return okC
end
local function fillUv(c, e)
  c.pos:SetText(UV_GREY .. "?|r")
  c.name:SetText(UV_GREY .. uvLabel(e.ev) .. "|r")
  c.time:SetText(timeText(e.ev.ts))
  c.border.set(0.3, 0.3, 0.3, 1)
  W.Tooltip(c, function(_, tt)
    tt:SetText(uvLabel(e.ev), 0.8, 0.8, 0.8)
    tt:AddLine(L.HALL_UV_TIP, 0.6, 0.6, 0.6, true)
    if H().CanConfirm() then tt:AddLine(L.HALL_UV_HINT, 0.5, 0.5, 0.5) end
  end)
  c:SetScript("OnClick", function()
    if not H().CanConfirm() then return end
    W.Menu(c, { { text = uvLabel(e.ev), title = true },
                { text = L.HALL_UV_CONFIRM, func = function() UI.HallConfirm(e.id) end } })
  end)
end
local function fillEntry(c, e)
  if e.uvItem then return fillUv(c, e) end
  local medal = MEDAL[e.pos]
  c.pos:SetText(medal and (medal .. "#" .. e.pos .. "|r") or ("#" .. e.pos))
  c.name:SetText(H().EntryLabel(e) .. (e.ex and (" |cff888888" .. L.HALL_EX_SHORT .. "|r") or ""))
  c.time:SetText(timeText(e.ts) .. " · " .. (L["MARK_" .. tostring(e.mark)] or ""))
  c.border.set(medal and 0.6 or 0.3, medal and 0.5 or 0.3, medal and 0.2 or 0.3, 1)
  W.Tooltip(c, function(_, tt) entryTip(tt, e) end)
  c:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" and isGM() then
      W.Menu(c, { { text = H().EntryLabel(e), title = true },
                  { text = L.HALL_ANNUL, func = function() UI.HallAnnul(hall.sel, e) end } })
    end
  end)
end

UI.Register("hall", L.TAB_HALL, function(f, bar)
  hall.chips = {}
  local row = {}
  for _, cat in ipairs(FILTERS) do local b = chip(f, cat); hall.chips[cat] = b; row[#row + 1] = b end
  hall.export = W.IconButton(f, 24, ICONS .. "INV_Misc_Note_01", L.HALL_EXPORT, L.HALL_EXPORT_TIP, function()
    if hall.sel then UI.ShowExport(H().ExportText(hall.sel), false, L.RANK_EXPORT_HELP) else ns.print(L.HALL_PICK) end
  end)
  row[#row + 1] = hall.export
  UI.TopRow(f, row, 4, -8)
  -- left: races (below the portrait zone), right: detail
  local lt = W.Label(f, L.HALL_RACES, "GameFontNormalSmall"); lt:SetPoint("TOPLEFT", 12, -66)
  local area = CreateFrame("Frame", nil, f); area:SetPoint("TOPLEFT", 10, -82); area:SetSize(290, 340)
  hall.list = W.Grid(area, 1, 12, 290, 25, 0, 3, makeRace, fillRace)
  hall.title = W.Label(f, "", "GameFontNormal"); hall.title:SetPoint("TOPLEFT", 316, -40); hall.title:SetWidth(370)
  if hall.title.SetJustifyH then hall.title:SetJustifyH("LEFT") end
  hall.state = W.Label(f, "", "GameFontHighlightSmall"); hall.state:SetPoint("TOPLEFT", 316, -60)
  if hall.state.SetWidth then hall.state:SetWidth(240) end
  -- toggle between the Top and the observations pending verification (grey "?")
  hall.uvBtn = W.Button(f, "", 120, 18, function()
    hall.uvMode = not hall.uvMode; UI.Select("hall")
  end)
  hall.uvBtn:SetPoint("TOPRIGHT", -8, -60)
  W.Tooltip(hall.uvBtn, L.HALL_UV_BTN_T, L.HALL_UV_TIP)
  hall.uvBtn:Hide()
  -- "Legado" = races disabled by the GM that already had entries
  hall.legacyBtn = W.Button(f, "", 110, 18, function() hall.legacy = not hall.legacy; hall.sel = nil; UI.Select("hall") end)
  hall.legacyBtn:SetPoint("TOPLEFT", 190, -62)
  W.Tooltip(hall.legacyBtn, L.LEGACY, L.LEGACY_TIP)
  hall.legacyBtn:Hide()
  local det = CreateFrame("Frame", nil, f); det:SetPoint("TOPLEFT", 312, -82); det:SetSize(376, 310)
  hall.detail = W.Grid(det, 1, 10, 376, 28, 0, 3, makeEntry, fillEntry)
  hall.notice = W.Label(f, "", "GameFontNormal"); hall.notice:SetPoint("TOP", det, "TOP", 0, -60); hall.notice:SetWidth(360)
  hall.notice:SetTextColor(1, 0.82, 0)
  hall.history = W.Label(f, "", "GameFontDisableSmall"); hall.history:SetPoint("TOPLEFT", 316, -400); hall.history:SetWidth(290)
  -- the GM can revert an annulment from the history
  hall.restore = W.Button(f, L.HALL_RESTORE, 80, 18, function(self)
    local r = hall.sel and H().Races()[hall.sel]
    if not (r and isGM()) then return end
    local items = { { text = L.HALL_RESTORE, title = true } }
    for _, h in ipairs(r.history or {}) do
      local label = H().EntryLabel(h)
      items[#items + 1] = { text = label, func = function()
        W.Confirm(L.HALL_RESTORE_CONFIRM:format(label), function()
          local okR, why = H().Restore(r.id, h.key)
          if not okR then ns.ShowError(why) end
          UI.Select("hall")
        end)
      end }
    end
    items[#items + 1] = { text = CANCEL or L.CANCEL }
    W.Menu(self, items)
  end)
  hall.restore:SetPoint("TOPRIGHT", -8, -396)
  hall.restore:Hide()
  bar.status:SetText("")
end, function(f, bar)
  local g = H()
  local races = g.Races()
  for cat, b in pairs(hall.chips) do b:SetOn(cat == hall.cat) end
  local nLegacy = #R.legacyList(races)
  if nLegacy == 0 then hall.legacy = nil end
  hall.legacyBtn:SetShown(nLegacy > 0)
  hall.legacyBtn:SetText(hall.legacy and L.LEGACY_BACK or L.LEGACY_BTN:format(nLegacy))
  local list = hall.legacy and UI.HallLegacyList(races) or UI.HallRaceList(races, hall.cat)
  hall.list:SetItems(list)
  if not hall.sel or not races[hall.sel] or (not hall.legacy and races[hall.sel].cat ~= hall.cat) then hall.sel = list[1] and list[1].id or nil; hall.list:Render() end
  local r = hall.sel and races[hall.sel]
  hall.title:SetText(r and UI.RaceTitle(r.id) or L.HALL_EMPTY)
  hall.state:SetText(r and (stateText(r) .. (r.season and (" · " .. L.HALL_SEASON:format(r.season)) or "")
    .. (#(r.pending or {}) > 0 and (" · " .. L.HALL_PENDING:format(#r.pending)) or "")) or "")
  local uv = g.Unverified and g.Unverified() or {}
  if #uv == 0 then hall.uvMode = nil end
  hall.uvBtn:SetShown(#uv > 0)
  hall.uvBtn:SetText(hall.uvMode and L.HALL_UV_BACK or ("? " .. L.HALL_UV_BTN:format(#uv)))
  if hall.uvMode then
    local items = {}
    for _, x in ipairs(uv) do items[#items + 1] = { uvItem = true, id = x.id, ev = x.ev } end
    hall.detail:SetItems(items)
  else
    hall.detail:SetItems(r and r.entries or {})
  end
  local msg = ""
  if r and #r.entries == 0 and not hall.uvMode then msg = r.state == "nodata" and L.HALL_NODATA_LONG or L.HALL_NOBODY end
  hall.notice:SetText(msg); hall.notice:SetShown(msg ~= "")
  local hist = {}
  for _, h in ipairs(r and r.history or {}) do
    hist[#hist + 1] = L.HALL_HISTORY_LINE:format(H().EntryLabel(h), ns.shortName(h.by or "?"), h.reason or "")
  end
  hall.history:SetText(#hist > 0 and (L.HALL_HISTORY .. ": " .. table.concat(hist, " · ")) or "")
  hall.restore:SetShown(#hist > 0 and isGM())
  local x, y = g.Adoption()
  bar.status:SetText(L.ADOPTION:format(x, y))
end, function() return M.settingsOf(ns.state).squadsEnabled and ns.HallGlue and ns.HallGlue.Enabled() end,
   { icon = ICONS .. "INV_Misc_Trophy_Argent" })

-- tab order: Salón de la fama right after Ranking (after Bandas when that tab exists)
do
  local order = UI.order
  for i = #order, 1, -1 do if order[i] == "hall" then table.remove(order, i) end end
  local at = #order + 1
  for i, k in ipairs(order) do if k == "ranking" or k == "raids" then at = i + 1 end end
  table.insert(order, at, "hall")
end
function UI.HallState() return hall end

-------------------------------------------------------------------------------
-- "Mis logros" (Mi perfil): grid of badges, earned first (dated), then progress ("3/9 mazmorras")
UI.ACH_ICON = UI.ACH_ICON or {}
for k, v in pairs({ allRoles = ICONS .. "INV_Shield_06", allClasses = ICONS .. "INV_Misc_Gem_Variety_01",
                    wipeTopAll = ICONS .. "INV_Misc_Rune_01", wipes4 = ICONS .. "INV_Misc_PocketWatch_01",
                    hallOfFame = ICONS .. "INV_Misc_Trophy_Argent", top10class = ICONS .. "INV_Misc_Book_09",
                    top10race = ICONS .. "INV_Misc_Head_Human_01", first1 = ICONS .. "INV_Crown_02",
                    dungeonsAll = ICONS .. "INV_Misc_Map01", raider = ICONS .. "INV_Misc_Head_Dragon_Black",
                    allAboard = ICONS .. "INV_Misc_GroupNeedMore" }) do UI.ACH_ICON[k] = v end

-- without UnitPVPRank (WoW Forever 1.60.1) the pvpRank* achievements and pvp.rank.* races cannot be
-- earned: they are hidden from the lists. The data is untouched (pvprank records are accepted as before).
local function pvpRankShown()
  local g = H()
  return not (g and g.PvPRankSupported) or g.PvPRankSupported()
end
function UI.HallRaceList(races, cat)
  local list = R.list(races, cat)
  if pvpRankShown() then return list end
  local out = {}
  for _, r in ipairs(list) do if not r.id:find("^pvp%.rank%.") then out[#out + 1] = r end end
  return out
end

function UI.HallLegacyList(races)
  local out = {}
  for _, r in ipairs(R.legacyList(races)) do if pvpRankShown() or not r.id:find("^pvp%.rank%.") then out[#out + 1] = r end end
  return out
end

function UI.MyAchievementList()
  local g, pg = H(), ns.ProgressGlue
  local me, sid = ns.me(), ns.Actions.MySquadId()
  local out = {}
  local prog = g and g.AchProgress() or { squad = {}, char = {}, guild = {} }
  local oldProg = (pg and sid and pg.AchievementProgress(sid)) or {}
  local function add(scope, owner, key)
    local ts = (owner and g.Achievements(scope, owner)[key]) or (scope ~= "guild" and pg and owner and pg.Achievements(scope, owner)[key]) or nil
    local p = (owner and prog[scope][owner] and prog[scope][owner][key]) or (scope == "squad" and oldProg[key]) or nil
    out[#out + 1] = { key = key, ts = ts, p = p, scope = scope }
  end
  if sid then
    for _, a in ipairs(Pr.ACHIEVEMENTS) do if a.scope == "squad" then add("squad", sid, a.key) end end
    for _, k in ipairs(R.SQUAD_ACH) do add("squad", sid, k) end
  end
  add("char", me, "guildFirst60")
  for _, h in ipairs(R.LEVELS) do add("char", me, "lvl" .. h) end
  for _, h in ipairs(R.LEVELS) do add("char", me, "top100." .. h) end
  for _, k in ipairs(R.CHAR_ACH) do add("char", me, k) end
  if pvpRankShown() then for _, n in ipairs(R.PVP_RANKS) do add("char", me, "pvpRank" .. n) end end
  add("guild", "guild", "allAboard")
  -- the GM's own badges (metric "manual"), granted to me or to my squad
  local Cat = ns.Catalog
  for id, rec in pairs(Cat and Cat.defs() or {}) do
    if Cat.isCustom(id) and rec.d.metric == "manual" then
      if rec.d.scope == "squad" then if sid then add("squad", sid, id) end else add("char", me, id) end
    end
  end
  for _, a in ipairs(out) do
    a.grant = g and g.GrantOf and g.GrantOf(a.scope == "squad" and sid or (a.scope == "char" and me or "guild"), a.key) or nil
  end
  local function less(a, b)
    if (a.ts ~= nil) ~= (b.ts ~= nil) then return a.ts ~= nil end
    if a.ts and b.ts and a.ts ~= b.ts then return a.ts > b.ts end
    return a.key < b.key
  end
  -- disabled = hidden; disabled but earned = "Legado", after the rest
  local shown, legacy = out, {}
  if Cat then shown, legacy = Cat.splitLegacy(out) end
  table.sort(shown, less); table.sort(legacy, less)
  for _, a in ipairs(legacy) do shown[#shown + 1] = a end
  return shown
end

local function achTitle(key)
  local lab = ns.Catalog and ns.Catalog.label(key)   -- the GM's visible name
  if lab then
    local _, desc = UI.AchTitleDefault(key)
    return lab, desc
  end
  return UI.AchTitleDefault(key)
end
function UI.AchTitleDefault(key)
  if ns.Catalog and ns.Catalog.isCustom(key) then return key, "" end
  local h = key:match("^lvl(%d+)$"); if h then return L.ACH_LVL:format(tonumber(h)), L.ACHD_LVL:format(tonumber(h)) end
  h = key:match("^top100%.(%d+)$"); if h then return L.ACH_TOP100:format(tonumber(h)), L.ACHD_TOP100:format(tonumber(h)) end
  h = key:match("^pvpRank(%d+)$"); if h then return L.ACH_PVPRANK:format(tonumber(h)), L.ACHD_PVPRANK:format(tonumber(h)) end
  return L["ACH_" .. key] or key, L["ACHD_" .. key] or ""
end
UI.AchTitle = achTitle

function UI.AchGrid(parent, cols, rows)
  local s = CreateFrame("Frame", nil, parent)
  s:SetSize(cols * 24, rows * 24)
  s.icons = {}
  for i = 1, cols * rows do
    local b = CreateFrame("Button", nil, s)
    b:SetSize(22, 22); b:SetPoint("TOPLEFT", s, "TOPLEFT", ((i - 1) % cols) * 24, -math.floor((i - 1) / cols) * 24)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
    b:Hide()
    s.icons[i] = b
  end
  function s:Fill()
    local list = UI.MyAchievementList()
    local earned = 0
    for _, a in ipairs(list) do if a.ts then earned = earned + 1 end end   -- all, not the 36 shown
    for i, b in ipairs(self.icons) do
      local a = list[i]
      if a then
        local icon = UI.ACH_ICON[a.key] or (a.key:find("^lvl") and UI.ACH_ICON.first60) or (a.key:find("^top100") and UI.ACH_ICON.guildFirst60)
                     or (a.key:find("^pvpRank") and UI.ACH_ICON.firstBg) or W.QUESTION
        b.icon:SetTexture(icon)
        b.icon:SetDesaturated(a.ts == nil or a.legacy == true); b:SetAlpha((a.ts and not a.legacy) and 1 or (a.legacy and 0.35 or 0.45))
        local title, desc = achTitle(a.key)
        local line = a.ts and Pr.formatDate(a.ts) or (a.p and UI.ProgressText and UI.ProgressText(a.p)) or L.ACH_LOCKED
        if a.grant then line = line .. "\n" .. L.ACH_GRANTED:format(a.grant.reason or "") end
        if a.legacy then line = line .. "\n" .. L.LEGACY_ACH end
        W.Tooltip(b, title, desc .. "\n" .. line)
        b:Show()
      else b:Hide() end
    end
    return earned, #list
  end
  return s
end
