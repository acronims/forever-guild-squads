-- Guild Squads (MIT) - UI/Ranking.lua
-- "Ranking" tab (5 categories + General, Wipe/Temporada selector, Overlord hint): category chips, period selector, pinned "your squad" card, ranked list with
-- logo/points/trend and a breakdown tooltip, guild goal bar. Plus the achievements strip used in "Mi squad".
-- Read-only screen: no primary button. Scores come from ns.ProgressGlue (computed locally from events).
local _, ns = ...
local L, W, UI, M, Pr, Content = ns.L, ns.W, ns.UI, ns.Model, ns.Progress, ns.Content
local ICONS = "Interface\\Icons\\"

local CATS = { "general", "level", "dungeon", "raid", "pvp", "wpvp" }
local CAT_ICON = { level = ICONS .. "Spell_ChargePositive", dungeon = ICONS .. "INV_Misc_Key_03",
                   raid = ICONS .. "INV_Misc_Head_Dragon_01", general = ICONS .. "INV_Jewelry_Talisman_07",
                   pvp = ICONS .. "INV_Sword_27", wpvp = ICONS .. "Ability_Warrior_BattleShout" }
local CAT_COLOR = { level = { 0.18, 0.43, 0.18 }, dungeon = { 0.18, 0.36, 0.59 }, raid = { 0.42, 0.24, 0.61 },
                    general = { 0.6, 0.45, 0.1 }, pvp = { 0.6, 0.15, 0.15 }, wpvp = { 0.5, 0.3, 0.12 } }
UI.ACH_ICON = {
  first60 = ICONS .. "Spell_ChargePositive", squad60 = ICONS .. "Spell_Holy_PrayerOfFortitude",
  firstDungeon = ICONS .. "INV_Misc_Key_03", forever = ICONS .. "INV_Misc_Map_01", boss10 = ICONS .. "INV_Sword_04",
  boss50 = ICONS .. "INV_Sword_39", boss100 = ICONS .. "INV_Sword_62", firstRaid = ICONS .. "INV_Misc_Head_Dragon_01",
  sotw = ICONS .. "INV_Jewelry_Talisman_07", guildFirst60 = ICONS .. "Spell_Holy_SealOfWrath",
  sots = ICONS .. "INV_Crown_01", firstBg = ICONS .. "INV_Sword_27", hk100 = ICONS .. "Ability_Warrior_BattleShout",
  conq = ICONS .. "INV_BannerPVP_02",
}

local rk = { cat = "general", back = 0, mode = "wipe" } -- mode: "wipe" | "season"
local function G() return ns.ProgressGlue end
local function serverNow() return (GetServerTime and GetServerTime()) or time() end

local function fmt(n) return (W and W.Num) and W.Num(n) or ("%.1f"):format(n or 0) end   -- "12", "12,5" (esES)

local function dateText(ts)
  if not ts then return "" end
  local y, m, d = Pr.civilFromDays(math.floor((ts + Pr.realmOffset(ts)) / 86400))
  return ("%d %s %d"):format(d, L["MONTH_" .. m], y)
end

function UI.SeasonLabel(id)
  local k = Pr.parseSeason(id)
  local y, m, d = Pr.seasonStart(id)
  if not y then return tostring(id) end
  if k == "M" then return L.SEASON_MONTH:format(L["MONTHL_" .. m], y) end
  return L.WIPE_LABEL:format(d, L["MONTH_" .. m])
end

local function shortDate(ts)
  if not ts or ts <= 0 then return "" end
  local lt = ts + Pr.realmOffset(ts)
  local _, m, d = Pr.civilFromDays(math.floor(lt / 86400))
  return d .. " " .. L["MONTH_" .. m]
end
function UI.TemporadaLabel(season, index)
  if not season then return "?" end
  local name = season.name or L.SEASON_N:format(index or 1)
  local stop = (season.stop and season.stop > 0) and shortDate(season.stop) or "..."
  return name .. " (" .. shortDate(season.start) .. " - " .. stop .. ")"
end

local function squadIds()
  local out = {}
  for id, r in pairs(ns.state.squads) do if not r.d.disbanded then out[id] = true end end
  return out
end

local function breakdown(tt, sid, r, name)
  tt:SetText(name or "?", 1, 0.82, 0)
  if not r then tt:AddLine(L.RANK_NO_POINTS, 0.7, 0.7, 0.7); return end
  tt:AddLine(L.BD_LEVEL:format(fmt(r.level), r.levels), 1, 1, 1)
  tt:AddLine(L.BD_DUNGEON:format(fmt(r.dungeon), r.dKills), 1, 1, 1)
  tt:AddLine(L.BD_RAID:format(fmt(r.raid), r.rKills), 1, 1, 1)
  tt:AddLine(L.BD_PVP:format(fmt(r.pvp), r.bgW or 0, r.bgL or 0), 1, 1, 1)
  tt:AddLine(L.BD_WPVP:format(fmt(r.wpvp), r.hk or 0, r.caps or 0), 1, 1, 1)
  if r.nWipes then tt:AddLine(L.BD_WIPES:format(r.nWipes), 0.7, 0.7, 0.7) end
  if (r.bonus or 0) > 0 then tt:AddLine(L.BD_BONUS:format(r.bonus), 0.4, 1, 0.4) end
  tt:AddLine(L.BD_ACTIVE:format(r.active, r.div), 0.7, 0.7, 0.7)
  if next(r.capped) then tt:AddLine(L.BD_CAPPED, 1, 0.5, 0.2) end
  tt:AddLine(L.BD_GENERAL:format(fmt(r.general)), 1, 0.82, 0)
end

local function trendText(pos, prevPos)
  if not prevPos then return "|cff888888" .. L.TREND_NEW .. "|r" end
  local d = prevPos - pos
  if d > 0 then return "|cff33ff33+" .. d .. "|r" end
  if d < 0 then return "|cffff4444" .. d .. "|r" end
  return "|cff888888=|r"
end

-- category chip: icon + text, coloured when selected
local function catChip(parent, cat)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(24)
  b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(20, 20); b.icon:SetPoint("LEFT", 3, 0)
  b.icon:SetTexture(CAT_ICON[cat])
  b.text = W.Label(b, L["CAT_" .. cat], "GameFontHighlightSmall"); b.text:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
  b:SetWidth(W.num(b.text:GetStringWidth(), 60) + 34)
  function b:SetOn(v)
    local c = CAT_COLOR[cat]
    if v then self.bg:SetColorTexture(c[1], c[2], c[3], 0.95); self.text:SetTextColor(1, 1, 1); self.icon:SetDesaturated(false)
    else self.bg:SetColorTexture(0.1, 0.1, 0.1, 0.9); self.text:SetTextColor(0.6, 0.6, 0.6); self.icon:SetDesaturated(true) end
  end
  b:SetScript("OnClick", function() rk.cat = cat; UI.Select("ranking") end)
  b.cat = cat
  W.Tooltip(b, L["CAT_" .. cat], L["CATD_" .. cat])
  return b
end

local function makeRow(parent)
  local c = W.Card(parent)
  c.pos = W.Label(c, "", "GameFontNormalLarge"); c.pos:SetPoint("LEFT", 8, 0); c.pos:SetWidth(34)
  c.logo = W.Logo(c, 24); c.logo:SetPoint("LEFT", 44, 0)
  c.name = W.Label(c, "", "GameFontNormal"); c.name:SetPoint("LEFT", 76, 0)
  c.trend = W.Label(c, "", "GameFontHighlightSmall"); c.trend:SetPoint("RIGHT", -10, 0)
  c.points = W.Label(c, "", "GameFontHighlight"); c.points:SetPoint("RIGHT", -60, 0)
  return c
end

local function fillRow(c, item)
  local r = ns.state.squads[item.sid]
  local d = r and r.d or {}
  c.pos:SetText(item.pos <= 3 and ("|cffffd100#" .. item.pos .. "|r") or ("#" .. item.pos))
  if r then c.logo:SetLogo(d.icon, d.color, d.border) else c.logo:SetEmpty() end
  local mine = item.sid == ns.Actions.MySquadId()
  c.name:SetText((mine and "|cff33ccff" or "") .. (M.displayName(ns.state, item.sid) or d.name or "?") .. (mine and "|r" or ""))
  c.points:SetText(fmt(item.points) .. " " .. L.PTS)
  c.trend:SetText(trendText(item.pos, item.prevPos))
  c.border.set(mine and 0.2 or 0.3, mine and 0.6 or 0.3, mine and 1 or 0.3, 1)
  W.Tooltip(c, function(_, tt) breakdown(tt, item.sid, item.r, d.name) end)
end

-- "3/9 mazmorras", "62/100 HK", "1/1"
function UI.ProgressText(p)
  local unit = L["PROG_" .. tostring(p.unit)]
  if p.unit == "done" or unit == "PROG_" .. tostring(p.unit) then return L.PROG_FMT:format(p.cur, p.need, ""):gsub("%s+$", "") end
  return L.PROG_FMT:format(p.cur, p.need, unit)
end

-- "Este wipe" panel for "Mi squad": one cell per category + total. Points are the capped, normalised
-- points of the current wipe; position = place in the guild ranking of that category.
function UI.WipePanel(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(676, 38)
  f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints(); f.bg:SetColorTexture(0.08, 0.07, 0.06, 0.9)
  f.title = W.Label(f, L.THIS_WIPE, "GameFontNormal"); f.title:SetPoint("LEFT", 8, 0); f.title:SetWidth(78)
  f.cells = {}
  local cats = { "level", "dungeon", "raid", "pvp", "wpvp", "general" }
  for i, cat in ipairs(cats) do
    local c = CreateFrame("Button", nil, f)
    c:SetSize(96, 34); c:SetPoint("LEFT", f, "LEFT", 90 + (i - 1) * 98, 0)
    c.icon = c:CreateTexture(nil, "ARTWORK"); c.icon:SetSize(22, 22); c.icon:SetPoint("LEFT", 2, 0); c.icon:SetTexture(CAT_ICON[cat])
    c.pts = W.Label(c, "", "GameFontHighlightSmall"); c.pts:SetPoint("TOPLEFT", 28, -3)
    c.pos = W.Label(c, "", "GameFontDisableSmall"); c.pos:SetPoint("TOPLEFT", 28, -18)
    c.edge = W.Border(c, 1, 1, 0.82, 0, 1)
    c.cat = cat
    f.cells[i] = c
  end
  function f:SetSquad(sid)
    local g = G()
    if not (g and g.Enabled and g.Enabled() and sid) then self:Hide(); return end
    self:Show()
    local s = M.settingsOf(ns.state)
    local cap = s.weekCap or 100
    local res = g.Compute()
    local ids = squadIds()
    local r = res.squads[sid]
    local wkey = { level = "wLevel", dungeon = "wDungeon", raid = "wRaid", pvp = "wPvp", wpvp = "wWpvp" }
    for _, c in ipairs(self.cells) do
      local pts = r and r[c.cat] or 0
      local pos
      for _, e in ipairs(Pr.scored(res, c.cat, ids)) do if e.sid == sid then pos = e.pos end end
      local n = 0
      for _ in pairs(ids) do n = n + 1 end
      local weight = wkey[c.cat] and (s[wkey[c.cat]] or 1) or 1
      local capped = r and r.capped and r.capped[c.cat]
      if c.cat == "general" then c.pts:SetText(("%.0f"):format(pts)) else c.pts:SetText(("%.0f/%d"):format(pts, cap)) end
      c.pos:SetText((pos and pts > 0) and L.POS_OF:format(pos, n) or "–") -- no position without points
      c.edge.show(capped and true or false)
      c.pts:SetTextColor(capped and 1 or 1, capped and 0.82 or 1, capped and 0 or 1)
      c:SetAlpha(weight == 0 and 0.35 or 1)
      c.icon:SetDesaturated(weight == 0)
      local tip = L["CATD_" .. c.cat] or ""
      if weight == 0 then tip = tip .. "\n" .. L.WEIGHT_ZERO end
      if capped then tip = tip .. "\n" .. L.BD_CAPPED end
      W.Tooltip(c, L["CAT_" .. c.cat], tip)
    end
    return r
  end
  return f
end

-- the strip's list: earned (incl. badges granted by the GM) newest first, then the closest in progress, then
-- the disabled ones already earned ("Legado"). Disabled ones never earned are not shown. -> list, earned, prog
function UI.StripList(sid)
  local list = {}
  local g, hg, Cat = G(), ns.HallGlue, ns.Catalog
  local got = {}
  local function addSet(set, owner)
    for key, ts in pairs(set or {}) do
      if not got[key] then
        got[key] = true
        list[#list + 1] = { key = key, ts = ts, grant = hg and hg.GrantOf and hg.GrantOf(owner, key) or nil }
      end
    end
  end
  if g and sid then
    addSet(g.Achievements("squad", sid), sid)
    addSet(g.Achievements("char", ns.me()), ns.me())
  end
  if Cat and sid then
    for key, x in pairs(Cat.grantsFor(sid)) do if not got[key] then got[key] = true; list[#list + 1] = { key = key, ts = x.ts, grant = x } end end
    for key, x in pairs(Cat.grantsFor(ns.me())) do if not got[key] then got[key] = true; list[#list + 1] = { key = key, ts = x.ts, grant = x } end end
  end
  local legacy = {}
  if Cat then list, legacy = Cat.splitLegacy(list) end
  table.sort(list, function(a, b) if a.ts ~= b.ts then return a.ts > b.ts end return a.key < b.key end)
  local earned = #list
  local prog = (g and g.AchievementProgress and sid) and g.AchievementProgress(sid) or {}
  local pending = {}
  for key, p in pairs(prog) do
    if not got[key] and p.need > 0 and (not Cat or Cat.isOn(key)) then pending[#pending + 1] = { key = key, p = p, r = p.cur / p.need } end
  end
  table.sort(pending, function(a, b) if a.r ~= b.r then return a.r > b.r end return a.key < b.key end)
  for _, e in ipairs(pending) do list[#list + 1] = e end
  for _, e in ipairs(legacy) do list[#list + 1] = e end
  return list, earned, prog
end

-- achievements strip ("Mi squad"): up to 10 icons with tooltip (title, description, date)
function UI.AchStrip(parent, n)
  local s = CreateFrame("Frame", nil, parent)
  n = n or 10
  s:SetSize(n * 22, 20)
  s.icons = {}
  for i = 1, n do
    local b = CreateFrame("Button", nil, s)
    b:SetSize(20, 20); b:SetPoint("RIGHT", s, "RIGHT", -(i - 1) * 22, 0)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
    b:Hide()
    s.icons[i] = b
  end
  -- earned achievements first (dated), then the closest ones still in progress (greyed, "3/9 mazmorras")
  -- list built by UI.StripList (GM grants, disabled ones hidden or under "Legado")
  function s:SetSquad(sid)
    local list, earned, prog = UI.StripList(sid)
    for i, b in ipairs(self.icons) do
      local a = list[i]
      if a then
        b.icon:SetTexture(UI.ACH_ICON[a.key] or W.QUESTION)
        b.icon:SetDesaturated(a.p ~= nil or a.legacy == true); b:SetAlpha((a.p or a.legacy) and 0.55 or 1)
        local p = a.p or prog[a.key]
        local line = a.ts and dateText(a.ts) or ""
        if p then line = line .. (line ~= "" and "\n" or "") .. UI.ProgressText(p) end
        if a.grant then line = line .. "\n" .. L.ACH_GRANTED:format(a.grant.reason or "") end
        if a.legacy then line = line .. "\n" .. L.LEGACY_ACH end
        local title, desc = L["ACH_" .. a.key], L["ACHD_" .. a.key]
        if UI.AchTitle then title, desc = UI.AchTitle(a.key) end
        W.Tooltip(b, title, (desc or "") .. "\n" .. line)
        b:Show()
      else b:Hide() end
    end
    return earned
  end
  return s
end

UI.Register("ranking", L.TAB_RANKING, function(f, bar)
  rk.chips = {}
  local row = {}
  for _, cat in ipairs(CATS) do
    local b = catChip(f, cat)
    rk.chips[cat] = b; row[#row + 1] = b
  end
  -- export (top 10 as text) at the end of the chip row; the row is centred / clear of the portrait
  rk.export = W.IconButton(f, 24, ICONS .. "INV_Misc_Note_01", L.RANK_EXPORT, L.RANK_EXPORT_TIP, function()
    UI.ShowExport(UI.RankingText(), false, L.RANK_EXPORT_HELP)
  end)
  row[#row + 1] = rk.export
  UI.TopRow(f, row, 6, -8)
  -- period selector: [Wipe][Temporada] < label >   (row 2, right)
  rk.next = W.IconButton(f, 24, "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", L.SEASON_NEWER, nil, function()
    rk.back = math.max(0, rk.back - 1); UI.Select("ranking")
  end)
  rk.next:SetPoint("TOPRIGHT", -10, -34)
  rk.season = W.Label(f, "", "GameFontNormal"); rk.season:SetPoint("RIGHT", rk.next, "LEFT", -6, 0)
  rk.prev = W.IconButton(f, 24, "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up", L.SEASON_OLDER, nil, function()
    rk.back = math.min(rk.maxBack or Pr.KEEP_SEASONS, rk.back + 1); UI.Select("ranking")
  end)
  rk.prev:SetPoint("RIGHT", rk.season, "LEFT", -6, 0)
  rk.modeSeason = W.Button(f, L.MODE_SEASON, 90, 22, function() if rk.mode ~= "season" then rk.mode = "season"; rk.back = 0; UI.Select("ranking") end end)
  rk.modeSeason:SetPoint("RIGHT", rk.prev, "LEFT", -10, 0)
  rk.modeWipe = W.Button(f, L.MODE_WIPE, 70, 22, function() if rk.mode ~= "wipe" then rk.mode = "wipe"; rk.back = 0; UI.Select("ranking") end end)
  rk.modeWipe:SetPoint("RIGHT", rk.modeSeason, "LEFT", -4, 0)
  -- pinned "your squad" card
  local yt = W.Label(f, L.YOUR_SQUAD, "GameFontNormalSmall"); yt:SetPoint("TOPLEFT", 12, -40)
  rk.mine = makeRow(f); rk.mine:SetSize(676, 34); rk.mine:SetPoint("TOPLEFT", 10, -60)
  rk.mineEmpty = W.Label(f, L.RANK_NO_SQUAD); rk.mineEmpty:SetPoint("TOPLEFT", 16, -72); rk.mineEmpty:SetTextColor(0.6, 0.6, 0.6)
  -- list
  local lt = W.Label(f, L.RANK_LIST, "GameFontNormalSmall"); lt:SetPoint("TOPLEFT", 12, -102)
  -- "How is it scored?" button (icon) that opens a plain-language explanation (no formulas)
  rk.how = W.IconButton(f, 18, "Interface\\Icons\\INV_Misc_QuestionMark", L.HOW_BTN, nil, function() UI.ToggleHowScored() end)
  rk.how:SetPoint("TOPRIGHT", -10, -99)
  rk.hint = W.Label(f, L.RANK_HINT); rk.hint:SetPoint("RIGHT", rk.how, "LEFT", -6, 0); rk.hint:SetTextColor(0.5, 0.5, 0.5)
  local hp = CreateFrame("Frame", nil, f)
  hp:SetPoint("TOPLEFT", 40, -60); hp:SetPoint("BOTTOMRIGHT", -40, 10)
  hp:SetFrameLevel((tonumber(f:GetFrameLevel()) or 1) + 20)
  hp:EnableMouse(true)
  W.Backdrop(hp, 0.05, 0.05, 0.07, 0.97, 0.7, 0.6, 0.3)
  hp.title = W.Label(hp, L.HOW_TITLE, "GameFontNormalLarge"); hp.title:SetPoint("TOPLEFT", 14, -12)
  hp.body = W.Label(hp, L.HOW_BODY, "GameFontHighlight"); hp.body:SetPoint("TOPLEFT", 14, -40); hp.body:SetPoint("RIGHT", hp, "RIGHT", -14, 0)
  hp.body:SetJustifyH("LEFT")
  if hp.body.SetWordWrap then pcall(hp.body.SetWordWrap, hp.body, true) end
  hp.close = W.IconButton(hp, 20, "Interface\\Buttons\\UI-StopButton", CLOSE or "x", nil, function() hp:Hide() end)
  hp.close:SetPoint("TOPRIGHT", -8, -8)
  hp:Hide()
  rk.howPanel = hp
  function UI.ToggleHowScored() hp:SetShown(not (hp:IsShown() == true)) end
  -- "Recomendado: Overlord Forever" (no link), dismissible forever; only in the PvP de mundo category
  rk.ovHint = CreateFrame("Frame", nil, f)
  rk.ovHint:SetSize(420, 16); rk.ovHint:SetPoint("TOPLEFT", 120, -102)
  rk.ovHint.text = W.Label(rk.ovHint, L.OVERLORD_HINT, "GameFontHighlightSmall")
  rk.ovHint.text:SetPoint("LEFT", 0, 0); rk.ovHint.text:SetTextColor(0.75, 0.75, 0.75)
  rk.ovHint.close = W.IconButton(rk.ovHint, 16, "Interface\\Buttons\\UI-StopButton", L.OVERLORD_HINT_HIDE, nil, function()
    if ns.ProgressGlue then ns.ProgressGlue.DismissOverlordHint() end
    UI.Select("ranking")
  end)
  rk.ovHint.close:SetPoint("LEFT", rk.ovHint.text, "RIGHT", 6, 0)
  rk.ovHint:Hide()
  local area = CreateFrame("Frame", nil, f)
  area:SetPoint("TOPLEFT", 10, -118); area:SetSize(676, 306)
  rk.grid = W.Grid(area, 1, 10, 676, 28, 0, 3, makeRow, fillRow)
  rk.notice = W.Label(f, "", "GameFontNormal"); rk.notice:SetPoint("TOP", area, "TOP", 0, -60)
  rk.notice:SetTextColor(1, 0.82, 0)
  rk.notice2 = W.Label(f, "", "GameFontHighlight"); rk.notice2:SetPoint("TOP", rk.notice, "BOTTOM", 0, -6)
  rk.notice2:SetTextColor(0.7, 0.7, 0.7)
  -- guild goal bar (bottom bar, left)
  local gb = CreateFrame("Frame", nil, bar)
  gb:SetSize(240, 12); gb:SetPoint("LEFT", bar, "LEFT", 14, -8)
  gb.bg = gb:CreateTexture(nil, "BACKGROUND"); gb.bg:SetAllPoints(); gb.bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)
  gb.fill = gb:CreateTexture(nil, "ARTWORK"); gb.fill:SetPoint("TOPLEFT"); gb.fill:SetPoint("BOTTOMLEFT")
  gb.fill:SetColorTexture(0.77, 0.12, 0.12, 1); gb.fill:SetWidth(1)
  W.Border(gb, 1, 0.4, 0.4, 0.4, 1)
  rk.goal = gb
  bar.status:ClearAllPoints(); bar.status:SetPoint("BOTTOMLEFT", gb, "TOPLEFT", 0, 3)
end, function(f, bar)
  local g = G()
  for cat, b in pairs(rk.chips) do b:SetOn(cat == rk.cat) end
  local ids = squadIds()
  local cur, prevRes
  if rk.mode == "season" then
    local cfg = g.SeasonCfg()
    rk.maxBack = #cfg.past
    rk.back = math.min(rk.back, rk.maxBack)
    local season = g.SeasonAt(rk.back)
    rk.season:SetText(UI.TemporadaLabel(season, #cfg.past + 1 - rk.back) .. (rk.back == 0 and (" " .. L.SEASON_CURRENT) or ""))
    cur = g.ComputeSeason(season)
    local older = g.SeasonAt(rk.back + 1)
    prevRes = older and g.ComputeSeason(older) or { squads = {} }
    rk.periodEmpty = #cur.wipes == 0 and (season.start > g.Now()) and L.SEASON_NOT_STARTED:format(shortDate(season.start)) or nil
  else
    rk.maxBack = Pr.KEEP_SEASONS
    local wipe = Pr.prevWipe(g.Wipe(), rk.back)
    rk.season:SetText(UI.SeasonLabel(wipe) .. (rk.back == 0 and (" " .. L.SEASON_CURRENT) or ""))
    cur = g.Compute(wipe)
    prevRes = g.Compute(Pr.prevWipe(wipe))
    rk.periodEmpty = nil
  end
  -- segmented control - the highlighted option IS the current mode (the period label matches it)
  W.SetSelected(rk.modeWipe, rk.mode == "wipe"); W.SetSelected(rk.modeSeason, rk.mode == "season")
  rk.prev:SetUsable(rk.back < rk.maxBack); rk.next:SetUsable(rk.back > 0)
  local list = Pr.scored(cur, rk.cat, ids) -- 0-point squads are not ranked (no position, no trend)
  local prevPos = {}
  for _, e in ipairs(Pr.scored(prevRes, rk.cat, ids)) do
    if e.r then prevPos[e.sid] = e.pos end
  end
  local showHint = rk.cat == "wpvp" and g.OverlordHint()
  rk.ovHint:SetShown(showHint and true or false); rk.hint:SetShown(not showHint)
  local mySid = ns.Actions.MySquadId()
  local mineItem
  for _, e in ipairs(list) do
    e.prevPos = prevPos[e.sid]
    if e.sid == mySid then mineItem = e end
  end
  -- before the raids open, the Raids category shows a centred empty state instead of 0-point rows
  local raidsClosed = false
  if rk.cat == "raid" and serverNow() < Content.RAIDS_OPEN_TS then
    raidsClosed = true
    for _, e in ipairs(list) do if e.r and (e.r.rKills or 0) > 0 then raidsClosed = false end end
    if raidsClosed then list = {} end
  end
  rk.grid:SetItems(list)
  rk.mine:SetShown(mineItem ~= nil); rk.mineEmpty:SetShown(mineItem == nil)
  if mineItem then fillRow(rk.mine, mineItem) end
  -- raids not open yet and nothing scored: notice
  local anyRaid = false
  for _, e in ipairs(list) do if e.r and (e.r.rKills or 0) > 0 then anyRaid = true end end
  local msg = ""
  -- the notice is only drawn over an empty list
  if #list == 0 then
    if rk.periodEmpty then msg = rk.periodEmpty
    elseif rk.cat == "raid" and not anyRaid and serverNow() < Content.RAIDS_OPEN_TS then msg = L.RAIDS_SOON
    else msg = L.RANK_EMPTY end
  end
  if raidsClosed and not rk.periodEmpty then msg = L.RAIDS_SOON end
  rk.notice:SetText(msg); rk.notice:SetShown(msg ~= "")
  rk.notice2:SetText(msg == L.RAIDS_SOON and L.RAIDS_SOON_HINT or ""); rk.notice2:SetShown(msg == L.RAIDS_SOON)
  local done, goal = g.GoalProgress()
  goal = math.max(1, goal or 30)
  rk.goal.fill:SetWidth(math.max(1, 240 * math.min(1, done / goal)))
  bar.status:SetText(L.GOAL:format(done, goal))
  W.Tooltip(rk.goal, L.GOAL_TITLE, L.GOAL_TIP)
end, function() return M.settingsOf(ns.state).squadsEnabled and ns.ProgressGlue and ns.ProgressGlue.Enabled() end,
   { icon = CAT_ICON.general })

-- tab order: Ranking right after Squads
do
  local order = UI.order
  for i = #order, 1, -1 do if order[i] == "ranking" then table.remove(order, i) end end
  local at = #order + 1
  for i, k in ipairs(order) do if k == "squads" then at = i + 1 end end
  table.insert(order, at, "ranking")
end

function UI.RankingState() return rk end

-- plain-text top 10 of the shown category / period, for Discord
function UI.RankingText()
  local g = G()
  if not g then return "" end
  local res, label
  if rk.mode == "season" then
    local season = g.SeasonAt(rk.back) or g.SeasonAt(0)
    res = g.ComputeSeason(season); label = UI.TemporadaLabel(season, 1)
  else
    local wipe = Pr.prevWipe(g.Wipe(), rk.back)
    res = g.Compute(wipe); label = UI.SeasonLabel(wipe)
  end
  local lines = { ("**%s · %s · %s**"):format(L.TITLE, L["CAT_" .. rk.cat], label) }
  for i, e in ipairs(Pr.scored(res, rk.cat, squadIds())) do
    if i > 10 then break end
    local r = ns.state.squads[e.sid]
    lines[#lines + 1] = ("%d. %s - %s %s"):format(e.pos, r and r.d.name or "?", fmt(e.points), L.PTS)
  end
  return table.concat(lines, "\n")
end
