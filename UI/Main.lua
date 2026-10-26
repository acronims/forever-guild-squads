-- Guild Squads (MIT) - UI/Main.lua
-- Window (portrait + inset + bottom bar + bottom tabs). Screens register in ns.UI.panels.
-- Template chain: PortraitFrameTemplate -> ButtonFrameTemplate -> BasicFrameTemplateWithInset -> BackdropTemplate -> plain.
local _, ns = ...
local L, W = ns.L, ns.W
local UI = { panels = {}, order = {} }
ns.UI = UI

local win, current

-- anchoring. Panel frames start 12 px right of the window edge
-- (inset 8 + 4); the portrait covers window x < ~56 and y > ~-54, so the top row of every screen starts at
-- SAFE_X (panel coordinates) = 70 px from the window edge, or is centred when it fits.
UI.WIN_W, UI.WIN_H = 720, 520
UI.PANEL_X = 12
UI.CONTENT_W = UI.WIN_W - 2 * UI.PANEL_X
UI.SAFE_X = 70 - UI.PANEL_X
local function widthOf(f, fallback)
  local w = f and f.GetWidth and f:GetWidth()
  return (type(w) == "number" and w > 0) and w or (fallback or 80)
end
UI.widthOf = widthOf
-- lay out `items` left to right on the top row of panel frame `f` (y offset `y`), centred in the window when
-- the row fits right of the portrait, otherwise starting at SAFE_X.
function UI.TopRow(f, items, gap, y)
  gap = gap or 6
  local total = 0
  for i, it in ipairs(items) do total = total + widthOf(it) + (i > 1 and gap or 0) end
  local x = math.max(UI.SAFE_X, math.floor((UI.CONTENT_W - total) / 2))
  for i, it in ipairs(items) do
    it:ClearAllPoints()
    if i == 1 then it:SetPoint("TOPLEFT", f, "TOPLEFT", x, y or -8) else it:SetPoint("LEFT", items[i - 1], "RIGHT", gap, 0) end
  end
  return x, total
end

-- opts = { icon = path|function, noTab = bool, visible = fn }
function UI.Register(key, title, build, refresh, visible, opts)
  opts = opts or {}
  UI.panels[key] = { key = key, title = title, build = build, refresh = refresh, visible = visible, opts = opts }
  UI.order[#UI.order + 1] = key
end

local function tabText(p)
  local icon = p.opts.icon
  if type(icon) == "function" then icon = icon() end
  return icon and (W.Icon(icon, 16) .. " " .. p.title) or p.title
end

local function visible(p) return not p.visible or p.visible() end

-- bottom tabs centred under the window (texts and sizes first, then the anchors)
local TAB_GAP = 2
UI.TAB_ICON_W = 44   -- icon-only tab width
local function layoutTabs()
  local idx, sel, shown, total = 0, nil, {}, 0
  for _, key in ipairs(UI.order) do
    local p = UI.panels[key]
    local b = p.tab
    if b then
      local show = visible(p)
      b:SetShown(show)
      idx = idx + 1
      if key == current then sel = idx end
      if not win.panelTabs then b:SetEnabled(key ~= current) end
      if b.SetText then b:SetText(tabText(p)) end
      if win.panelTabs and PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, b, 0) end
      if show then
        total = total + widthOf(b, 100) + (#shown > 0 and TAB_GAP or 0)
        shown[#shown + 1] = b
      end
    end
  end
  -- 8 tabs in esES (~790 px) overflow the 720 px window: every tab but the selected one
  -- becomes icon-only (name in the tooltip) until the strip fits
  UI.tabsCompact = total > UI.WIN_W - 8
  if UI.tabsCompact then
    total = 0
    for i, b in ipairs(shown) do
      local p = b.panel
      if p and p.key ~= current then
        local icon = p.opts.icon
        if type(icon) == "function" then icon = icon() end
        if icon and b.SetText then b:SetText(W.Icon(icon, 16)) end
        if win.panelTabs and PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, b, 0, UI.TAB_ICON_W) end
        b:SetWidth(UI.TAB_ICON_W)
        if W.Tooltip then W.Tooltip(b, p.title) end
      elseif p and W.Tooltip then W.Tooltip(b, nil) end
      total = total + widthOf(b, 100) + (i > 1 and TAB_GAP or 0)
    end
  else
    for _, b in ipairs(shown) do if b.panel and W.Tooltip then W.Tooltip(b, nil) end end
  end
  UI.tabsWidth = total
  for i, b in ipairs(shown) do
    b:ClearAllPoints()
    if i == 1 then b:SetPoint("TOPLEFT", win, "BOTTOM", -math.floor(total / 2), 2)
    else b:SetPoint("LEFT", shown[i - 1], "RIGHT", TAB_GAP, 0) end
  end
  if win.panelTabs then
    if not (sel and pcall(PanelTemplates_SetTab, win, sel)) then
      for _, key in ipairs(UI.order) do local t = UI.panels[key].tab; if t then t:SetEnabled(key ~= current) end end
    end
  end
end

function UI.Current() return current end

-- a panel may veto leaving it (opts.beforeLeave(nextKey) -> true = stay; e.g. unsaved settings)
function UI.Select(key, force)
  local cur = current and UI.panels[current]
  if not force and cur and key ~= current and cur.opts.beforeLeave and cur.opts.beforeLeave(key) then return end
  local p = UI.panels[key]
  if not p or not visible(p) then key = nil end
  if not key then
    for _, k in ipairs(UI.order) do if UI.panels[k].tab and visible(UI.panels[k]) then key = k; break end end
    p = UI.panels[key]
  end
  current = key
  W.CloseMenu()
  for k, other in pairs(UI.panels) do
    if other.frame then other.frame:SetShown(k == key); other.bar:SetShown(k == key) end
  end
  layoutTabs()
  if win.SetTitle then pcall(win.SetTitle, win, L.TITLE .. " - " .. p.title) end
  if win.titleFS then win.titleFS:SetText(L.TITLE .. " - " .. p.title) end
  UI.RefreshPortrait()
  if ns.UpdateBadge then ns.UpdateBadge() end
  if p.refresh then p.refresh(p.frame, p.bar) end
  UI.ShowFlash()
end

-- action feedback in the status bar of the current panel (kept 8 s across refreshes)
local flash, flashUntil
function UI.Flash(text)
  flash, flashUntil = text, (GetTime and GetTime() or 0) + 8
  UI.ShowFlash()
end
function UI.ShowFlash()
  if not flash or not win or not current then return end
  if (GetTime and GetTime() or 0) > flashUntil then flash = nil; return end
  local p = UI.panels[current]
  if p and p.bar and p.bar.status then p.bar.status:SetText("|cffffd100" .. flash .. "|r") end
end

-- portrait = my squad's logo icon, else my class icon
function UI.RefreshPortrait()
  if not win or not win.portraitTex then return end
  local id = ns.Actions.MySquadId()
  local r = id and ns.state.squads[id]
  local path
  if r then path = ns.Logo.icon(r.d.icon)
  else
    local _, class = UnitClass("player")
    path = class and ("Interface\\Icons\\ClassIcon_" .. class:sub(1, 1) .. class:sub(2):lower()) or W.QUESTION
  end
  if SetPortraitToTexture and pcall(SetPortraitToTexture, win.portraitTex, path) then return end
  win.portraitTex:SetTexture(path)
end

function UI.SetBadge(n) if win and win.badge then win.badge:SetCount(n) end end
-- "!" marker on the Mi perfil tab while the profile is incomplete
function UI.SetProfileMarker(on)
  local p = UI.panels and UI.panels.profile
  if not p or not p.tab then return end
  if not UI.profileMarker then
    UI.profileMarker = W.Badge(p.tab); UI.profileMarker:SetPoint("TOPRIGHT", p.tab, "TOPRIGHT", -4, 2)
  end
  local m = UI.profileMarker
  m.text:SetText("!")
  m:SetShown(on and true or false)
end

local function findTitle(f)
  if type(f.TitleContainer) == "table" and type(f.TitleContainer.TitleText) == "table" then return f.TitleContainer.TitleText end
  if type(f.TitleText) == "table" then return f.TitleText end
end

local function build()
  local tpl
  win, tpl = W.Create("Frame", UIParent, { "PortraitFrameTemplate", "ButtonFrameTemplate", "BasicFrameTemplateWithInset",
                                           "BackdropTemplate" }, "GuildSquadsFrame")
  UI.template = tpl or "plain"
  win:SetSize(UI.WIN_W, UI.WIN_H)
  win:SetPoint("CENTER")
  win:SetFrameStrata("HIGH")
  win:SetToplevel(true)
  win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  win:SetClampedToScreen(true)
  if tpl == "BackdropTemplate" or not tpl then
    W.Backdrop(win, 0.05, 0.05, 0.07, 0.95, 0.7, 0.6, 0.3)
    local close = W.Create("Button", win, { "UIPanelCloseButton" })
    close:SetSize(24, 24); close:SetPoint("TOPRIGHT", -2, -2)
    if not close:GetScript("OnClick") then close:SetScript("OnClick", function() win:Hide() end) end
  end
  -- title
  if not (tpl and win.SetTitle) then
    local t = findTitle(win)
    if not t then t = W.Label(win, L.TITLE, "GameFontNormal"); t:SetPoint("TOP", 0, -6) end
    win.titleFS = t
  end
  -- portrait
  local pc = type(win.PortraitContainer) == "table" and win.PortraitContainer
  local ptex = (pc and type(pc.portrait) == "table" and pc.portrait) or (type(win.portrait) == "table" and win.portrait)
  if not ptex then
    ptex = win:CreateTexture(nil, "OVERLAY")
    ptex:SetSize(60, 60); ptex:SetPoint("TOPLEFT", -6, 8)
    W.Round(win, ptex)
  end
  win.portraitTex = ptex
  -- content inset C
  local inset = type(win.Inset) == "table" and win.Inset or nil
  if not inset then
    inset = W.Create("Frame", win, { "InsetFrameTemplate" })
    if not inset.Bg and not inset.NineSlice then W.Backdrop(inset, 0, 0, 0, 0.8, 0.4, 0.4, 0.4) end
  end
  inset:ClearAllPoints()
  inset:SetPoint("TOPLEFT", win, "TOPLEFT", UI.PANEL_X - 4, -30)
  inset:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -(UI.PANEL_X - 4), 48)
  win.content = inset
  tinsert(UISpecialFrames, "GuildSquadsFrame") -- Esc closes

  -- tabs
  local tabs, n = {}, 0
  for _, key in ipairs(UI.order) do
    local p = UI.panels[key]
    if not p.opts.noTab then
      n = n + 1
      local b, ttpl = W.Create("Button", win, { "PanelTabButtonTemplate", "CharacterFrameTabButtonTemplate", "UIPanelButtonTemplate" },
                               "GuildSquadsFrameTab" .. n)
      if ttpl == "UIPanelButtonTemplate" or not ttpl then b:SetSize(120, 26) end
      b:SetID(n)
      b:SetText(tabText(p))
      b:SetScript("OnClick", function() UI.Select(key) end)
      p.tab = b; b.panel = p   -- compact tabs need the panel
      tabs[#tabs + 1] = b
      if ttpl == "PanelTabButtonTemplate" or ttpl == "CharacterFrameTabButtonTemplate" then win.panelTabs = true end
    end
    local fr = CreateFrame("Frame", nil, inset)
    fr:SetPoint("TOPLEFT", 4, -4); fr:SetPoint("BOTTOMRIGHT", -4, 4)
    fr:Hide()
    local bar = CreateFrame("Frame", nil, win)
    bar:SetPoint("BOTTOMLEFT", 0, 0); bar:SetPoint("BOTTOMRIGHT", 0, 0); bar:SetHeight(48)
    bar.status = W.Label(bar, ""); bar.status:SetPoint("LEFT", 14, 2); bar.status:SetTextColor(0.8, 0.8, 0.8)
    bar:Hide()
    p.frame, p.bar = fr, bar
  end
  win.Tabs = tabs
  if win.panelTabs and PanelTemplates_SetNumTabs then
    if not pcall(PanelTemplates_SetNumTabs, win, n) then win.panelTabs = nil end
  else win.panelTabs = nil end
  local first = UI.panels[UI.order[1]]
  if first and first.tab then
    win.badge = W.Badge(first.tab); win.badge:SetPoint("TOPRIGHT", first.tab, "TOPRIGHT", -4, 2)
  end
  for _, key in ipairs(UI.order) do local p = UI.panels[key]; p.build(p.frame, p.bar) end
  win:SetScript("OnShow", function() UI.Select(current or UI.order[1]); pcall(UI.MaybeGuide) end)
  win:SetScript("OnHide", function()
    W.CloseMenu()
    local cur = current and UI.panels[current]
    if cur and cur.opts.onHide then pcall(cur.opts.onHide) end
  end)
end

-------------------------------------------------------------------------------
-- first-use welcome (per character) with one button per step, plus a 4th step for
-- the GM; after an update, a one-time "what's new" box. State: GuildSquadsDB.ui (account-wide).
local guide
local function uiDB()
  GuildSquadsDB = GuildSquadsDB or {}
  GuildSquadsDB.ui = type(GuildSquadsDB.ui) == "table" and GuildSquadsDB.ui or {}
  local u = GuildSquadsDB.ui
  u.welcomed = type(u.welcomed) == "table" and u.welcomed or {}
  return u
end
UI.uiDB = uiDB

function UI.GuideSteps(isGM)
  local steps = {
    { text = L.GUIDE_1, btn = L.GUIDE_1_BTN, key = "profile" },
    { text = L.GUIDE_2, btn = L.GUIDE_2_BTN, key = "squads" },
    { text = L.GUIDE_3, btn = L.GUIDE_3_BTN, key = "ranking" },
  }
  if isGM then steps[#steps + 1] = { text = L.GUIDE_4, btn = L.GUIDE_4_BTN, key = "settings" } end
  return steps
end

local function buildGuide()
  local g = CreateFrame("Frame", nil, win)
  g:SetSize(460, 280); g:SetPoint("CENTER", win, "CENTER", 0, 10)
  g:EnableMouse(true)   -- clicks do not go through to the cards underneath
  if g.SetFrameLevel and win.GetFrameLevel then pcall(g.SetFrameLevel, g, (win:GetFrameLevel() or 1) + 20) end
  local bg = g:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.04, 0.03, 0.97)
  W.Border(g, 2, 1, 0.82, 0, 1)
  g.title = W.Label(g, "", "GameFontNormalLarge"); g.title:SetPoint("TOP", 0, -14)
  g.body = W.Label(g, ""); g.body:SetPoint("TOPLEFT", 18, -44); g.body:SetWidth(424); g.body:SetJustifyH("LEFT")
  g.rows = {}
  for i = 1, 4 do
    local r = CreateFrame("Frame", nil, g); r:SetSize(424, 34); r:SetPoint("TOPLEFT", 18, -44 - (i - 1) * 42)
    r.text = W.Label(r, ""); r.text:SetPoint("LEFT", 0, 0); r.text:SetWidth(280); r.text:SetJustifyH("LEFT")
    r.btn = W.Button(r, "", 130, 22); r.btn:SetPoint("RIGHT", 0, 0)
    g.rows[i] = r
  end
  g.close = W.Primary(g, L.GUIDE_OK, function() UI.HideGuide() end)
  g:Hide()
  return g
end

-- kind = "welcome" | "news"
function UI.ShowGuide(kind)
  if not win then return end
  guide = guide or buildGuide()
  local P = ns.Permissions
  local gm = P and ns.roster and ns.me and P.isGM(ns.roster, ns.me()) or false
  if kind == "news" then
    guide.title:SetText(L.NEWS_TITLE:format(tostring(ns.VERSION or "")))
    guide.body:SetText(L.NEWS_BODY); guide.body:Show()
    for _, r in ipairs(guide.rows) do r:Hide() end
  else
    guide.title:SetText(L.GUIDE_TITLE)
    guide.body:Hide()
    local steps = UI.GuideSteps(gm)
    for i, r in ipairs(guide.rows) do
      local st = steps[i]
      r:SetShown(st ~= nil)
      if st then
        r.text:SetText(("%d. %s"):format(i, st.text))
        r.btn:SetText(st.btn)
        r.btn:SetScript("OnClick", function() UI.HideGuide(); UI.Select(st.key) end)
      end
    end
  end
  guide.kind, guide.open = kind, true
  guide:Show()
end
function UI.HideGuide() if guide then guide.open = false; guide:Hide() end end
function UI.GuideShown() return guide and guide.open and guide.kind or nil end
function UI.GuideFrame() return guide end

function UI.MaybeGuide()
  local u = uiDB()
  local me = ns.me and ns.me() or "?"
  if not u.welcomed[me] then
    u.welcomed[me] = true
    u.lastVersion = ns.VERSION
    UI.ShowGuide("welcome")
  elseif ns.VERSION and u.lastVersion ~= ns.VERSION then
    u.lastVersion = ns.VERSION
    UI.ShowGuide("news")
  end
end

function UI.Open(key)
  if not win then build() end
  if not win:IsShown() then current = key or current; win:Show() end
  if key then UI.Select(key) end
end

function UI.Window() return win end

function UI.Toggle()
  if not win then build() end
  if win:IsShown() then win:Hide() else win:Show() end
end

-- coalesce refreshes (many records may arrive in a burst)
local dirty = false
-- the badge is recomputed at most once per second, not once per applied record
local badgeQueued = false
function UI.Dirty()
  if ns.UpdateBadge and not badgeQueued then
    badgeQueued = true
    ns.After(1, function() badgeQueued = false; pcall(ns.UpdateBadge) end)
  end
  if dirty or not win or not win:IsShown() then return end
  dirty = true
  ns.After(0.5, function()
    dirty = false
    if win:IsShown() and current then UI.Select(current) end
  end)
end

-- export / import box
local box
function UI.ShowExport(text, importMode, helpText)
  if not box then
    box = CreateFrame("Frame", "GuildSquadsExportFrame", UIParent)
    box:SetSize(560, 300); box:SetPoint("CENTER"); box:SetFrameStrata("FULLSCREEN_DIALOG")
    box:SetMovable(true); box:EnableMouse(true); box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", box.StartMoving); box:SetScript("OnDragStop", box.StopMovingOrSizing)
    W.Backdrop(box, 0, 0, 0, 0.95, 0.6, 0.6, 0.6)
    box.help = W.Label(box, L.EXPORT_HELP); box.help:SetPoint("TOPLEFT", 10, -10)
    local close = W.Create("Button", box, { "UIPanelCloseButton" }); close:SetSize(24, 24); close:SetPoint("TOPRIGHT", 2, 2)
    if not close:GetScript("OnClick") then close:SetScript("OnClick", function() box:Hide() end) end
    local sf = W.Create("ScrollFrame", box, { "UIPanelScrollFrameTemplate", "ScrollFrameTemplate" })
    sf:SetPoint("TOPLEFT", 10, -30); sf:SetPoint("BOTTOMRIGHT", -30, 40)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal); eb:SetWidth(510); eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function() box:Hide() end)
    sf:SetScrollChild(eb)
    box.eb = eb
    box.import = W.Button(box, L.IMPORT, 120, 22, function() ns.ImportText(eb:GetText()); box:Hide() end)
    box.import:SetPoint("BOTTOMRIGHT", -10, 10)
    tinsert(UISpecialFrames, "GuildSquadsExportFrame")
  end
  box.import:SetShown(importMode and true or false)
  box.help:SetText(helpText or L.EXPORT_HELP)
  box.eb:SetText(text or "")
  box:Show()
  box.eb:SetFocus()
  if not importMode then box.eb:HighlightText() end
end
