-- Guild Squads (MIT) - UI/Widgets.lua
-- Component kit. Every template / atlas is unverified in the WoW Forever client, so each
-- builder tries the Retail option first (pcall) and falls back to plain frames, files and colours.
local _, ns = ...
local W = {}
ns.W = W
local L = ns.L
local unpack = unpack or table.unpack
local function num(v, d) return type(v) == "number" and v or d end
W.num = num

local WHITE = "Interface\\Buttons\\WHITE8x8"
local ICONS = "Interface\\Icons\\"
W.QUESTION = ICONS .. "INV_Misc_QuestionMark"
W.MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-------------------------------------------------------------------------------
-- low level fallbacks

-- what worked in this client (reported by /gsq ui so fallbacks can be checked in game)
W.report = { tplOK = {}, tplFail = {}, atlasOK = {}, atlasMiss = {} }

-- CreateFrame with the first template that works; returns frame, templateUsed (nil = plain)
function W.Create(kind, parent, templates, name)
  for _, tpl in ipairs(templates or {}) do
    local ok, f = pcall(CreateFrame, kind, name, parent, tpl)
    if ok and f then W.report.tplOK[tpl] = true; return f, tpl end
    W.report.tplFail[tpl] = true
  end
  return CreateFrame(kind, name, parent), nil
end

-- atlas if the client has it, otherwise file (+ tex coords). Returns true when the atlas was used.
function W.SetAtlasOr(tex, atlas, file, l, r, t, b)
  if atlas and C_Texture and C_Texture.GetAtlasInfo then
    local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
    if ok and info and pcall(tex.SetAtlas, tex, atlas) then W.report.atlasOK[atlas] = true; return true end
    W.report.atlasMiss[atlas] = true
  end
  tex:SetTexture(file or W.QUESTION)
  if l then tex:SetTexCoord(l, r, t, b) else tex:SetTexCoord(0, 1, 0, 1) end
  return false
end

-- dark tooltip backdrop; uses BackdropTemplateMixin when the frame was not built with it, else 1px edges
function W.Backdrop(f, r, g, b, a, br, bg, bb)
  if not f.SetBackdrop and Mixin and BackdropTemplateMixin then pcall(Mixin, f, BackdropTemplateMixin) end
  if f.SetBackdrop and pcall(f.SetBackdrop, f, { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } }) then
    f:SetBackdropColor(r or 0, g or 0, b or 0, a or 0.85)
    f:SetBackdropBorderColor(br or 0.5, bg or 0.5, bb or 0.5, 1)
    return
  end
  local t = f:CreateTexture(nil, "BACKGROUND")
  t:SetAllPoints(); t:SetColorTexture(r or 0, g or 0, b or 0, a or 0.85)
  W.Border(f, 1, br or 0.5, bg or 0.5, bb or 0.5, 1)
end

-- 4 edge textures; returns { set = fn(r,g,b,a), show = fn(bool) }
function W.Border(f, size, r, g, b, a)
  local e = {}
  for i = 1, 4 do e[i] = f:CreateTexture(nil, "OVERLAY"); e[i]:SetColorTexture(1, 1, 1, 1) end
  e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(size)
  e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(size)
  e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(size)
  e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(size)
  local bd = { edges = e }
  function bd.set(r2, g2, b2, a2) for i = 1, 4 do e[i]:SetVertexColor(r2, g2, b2, a2 or 1) end end
  function bd.show(v) for i = 1, 4 do e[i]:SetShown(v and true or false) end end
  bd.set(r or 1, g or 1, b or 1, a or 1)
  return bd
end

-- round mask (falls back to square)
function W.Round(f, tex)
  if not (f.CreateMaskTexture and tex.AddMaskTexture) then return end
  pcall(function()
    local m = f:CreateMaskTexture()
    m:SetTexture(W.MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(tex)
    tex:AddMaskTexture(m)
  end)
end

-------------------------------------------------------------------------------
-- text, tooltip, colours

function W.Label(parent, text, font)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetText(text or "")
  fs:SetJustifyH("LEFT")
  return fs
end

function W.Icon(path, size) return ("|T%s:%d:%d|t"):format(path, size or 14, size or 14) end

-- tip: string title, or function(owner, GameTooltip)
-- numbers for people. Integers without decimals, otherwise 1 decimal with the locale separator
-- (comma in esES); percentages as "82 %".
function W.Num(n, decimals)
  n = tonumber(n) or 0
  if n == math.floor(n) then return tostring(math.floor(n)) end
  local s = ("%." .. (decimals or 1) .. "f"):format(n)
  s = s:gsub("%.?0+$", "")
  if L.DECIMAL and L.DECIMAL ~= "." then s = s:gsub("%.", L.DECIMAL) end
  return s
end
function W.Pct(n) return W.Num(math.floor((tonumber(n) or 0) + 0.5)) .. " %" end

function W.Tooltip(f, tip, text)
  f.tip, f.tipText = tip, text
  f:SetScript("OnEnter", function(self)
    if not self.tip or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if type(self.tip) == "function" then self.tip(self, GameTooltip)
    else
      GameTooltip:SetText(self.tip, 1, 0.82, 0)
      if self.tipText then GameTooltip:AddLine(self.tipText, 1, 1, 1, true) end
    end
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

-- localized class name for a class token ("WARRIOR" -> "Guerrero"):
-- LOCALIZED_CLASS_NAMES_MALE, then GetClassInfo(1..15), then the token capitalised
function W.ClassName(token)
  if type(token) ~= "string" or token == "" then return "" end
  local t = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
  if type(t) == "table" and type(t[token]) == "string" then return t[token] end
  if type(GetClassInfo) == "function" then
    for id = 1, 15 do
      local okI, name, file = pcall(GetClassInfo, id)
      if okI and file == token and type(name) == "string" then return name end
    end
  end
  return token:sub(1, 1) .. token:sub(2):lower()
end

function W.ClassColor(classFile)
  local c
  if classFile and C_ClassColor and C_ClassColor.GetClassColor then
    local ok, cc = pcall(C_ClassColor.GetClassColor, classFile); if ok then c = cc end
  end
  if not c and classFile and RAID_CLASS_COLORS then c = RAID_CLASS_COLORS[classFile] end
  if type(c) ~= "table" or type(c.r) ~= "number" then return 1, 1, 1, "|cffffffff" end
  return c.r, c.g, c.b, ("|cff%02x%02x%02x"):format(math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
end

W.GOAL_ICON = {
  leveling = ICONS .. "Spell_ChargePositive", dungeons = ICONS .. "INV_Misc_Key_03", farm = ICONS .. "INV_Pick_02",
  worldpvp = ICONS .. "Ability_DualWield", bg = ICONS .. "INV_BannerPVP_02", raid = ICONS .. "INV_Misc_Head_Dragon_01",
}
W.GOAL_COLOR = {
  leveling = { 0.18, 0.43, 0.18 }, dungeons = { 0.18, 0.36, 0.59 }, farm = { 0.55, 0.42, 0.09 },
  worldpvp = { 0.59, 0.17, 0.17 }, bg = { 0.65, 0.33, 0.12 }, raid = { 0.42, 0.24, 0.61 },
}

-------------------------------------------------------------------------------
-- role / class icons
local ROLE_TINY = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }
local ROLE_LARGE = { TANK = "groupfinder-icon-role-large-tank", HEALER = "groupfinder-icon-role-large-heal",
                     DAMAGER = "groupfinder-icon-role-large-dps" }
local ROLE_TC = { TANK = { 0, 0.2617, 0.2617, 0.5234 }, HEALER = { 0.2617, 0.5234, 0, 0.2617 },
                  DAMAGER = { 0.2617, 0.5234, 0.2617, 0.5234 } }
W.ROLE_ICON = { TANK = ICONS .. "INV_Shield_06", HEALER = ICONS .. "Spell_Holy_FlashHeal", DAMAGER = ICONS .. "INV_Sword_04" }

function W.SetRole(tex, role, large)
  if not ROLE_TC[role] then tex:SetTexture(W.QUESTION); tex:SetTexCoord(0, 1, 0, 1); return end
  -- the Blizzard DPS glyph is a red circle that reads like the red Reject button next to it;
  -- Damage uses a plain sword icon (no red circle). Tank / healer keep the standard role icons.
  if role == "DAMAGER" then
    tex:SetTexture(W.ROLE_ICON.DAMAGER)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return
  end
  local tc = ROLE_TC[role]
  if GetTexCoordsForRole then
    local ok, a, b, c, d = pcall(GetTexCoordsForRole, role)
    if ok and type(a) == "number" then tc = { a, b, c, d } end
  end
  W.SetAtlasOr(tex, (large and ROLE_LARGE or ROLE_TINY)[role], "Interface\\LFGFrame\\UI-LFG-ICON-ROLES", tc[1], tc[2], tc[3], tc[4])
end

function W.SetClass(tex, classFile)
  if type(classFile) ~= "string" then tex:SetTexture(W.QUESTION); tex:SetTexCoord(0, 1, 0, 1); return end
  local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
  if tc then
    W.SetAtlasOr(tex, "classicon-" .. classFile:lower(), "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES",
      tc[1], tc[2], tc[3], tc[4])
  else
    W.SetAtlasOr(tex, "classicon-" .. classFile:lower(), ICONS .. "ClassIcon_" .. classFile:sub(1, 1) .. classFile:sub(2):lower())
  end
end

function W.Dim(tex, off, alpha)
  tex:SetDesaturated(off and true or false)
  tex:SetAlpha(off and (alpha or 0.35) or 1)
end

-------------------------------------------------------------------------------
-- buttons

-- secondary buttons use the grey stretch template; only W.Primary is the red panel button
local function makeButton(parent, text, w, h, onClick, templates)
  local b = W.Create("Button", parent, templates)
  b:SetSize(w or 100, h or 22)
  b:SetText(text)
  if onClick then b:SetScript("OnClick", onClick) end
  if b.SetMotionScriptsWhileDisabled then pcall(b.SetMotionScriptsWhileDisabled, b, true) end
  return b
end
W.SECONDARY_TEMPLATES = { "UIMenuButtonStretchTemplate", "UIPanelButtonTemplate" }
W.PRIMARY_TEMPLATES = { "UIPanelButtonTemplate" }
function W.Button(parent, text, w, h, onClick) return makeButton(parent, text, w, h, onClick, W.SECONDARY_TEMPLATES) end

-- selected state of a segmented control / section tab = highlight locked + yellow underline
-- + white text; the selected option is the STATE (no action on click), never a disabled-looking button.
function W.SetSelected(b, on)
  b.selected = on and true or false
  if on then
    if b.LockHighlight then pcall(b.LockHighlight, b) end
  elseif b.UnlockHighlight then pcall(b.UnlockHighlight, b) end
  if not b.selLine and b.CreateTexture then
    local okT, t = pcall(b.CreateTexture, b, nil, "OVERLAY")
    if okT and t then
      b.selLine = t
      if t.SetColorTexture then pcall(t.SetColorTexture, t, 1, 0.82, 0, 1) end
      t:SetHeight(2)
      t:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 4, 1)
      t:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 1)
    end
  end
  if b.selLine then b.selLine:SetShown(on and true or false) end
  local fs = b.GetFontString and b:GetFontString()
  if fs and fs.SetTextColor then
    if on then fs:SetTextColor(1, 1, 1) else fs:SetTextColor(1, 0.82, 0) end
  end
end

-- the one red action button of a screen, bottom-right of the bottom bar
function W.Primary(bar, text, onClick)
  local b = makeButton(bar, text, 150, 26, onClick, W.PRIMARY_TEMPLATES)
  b.isPrimary = true
  b:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -14, 12)
  return b
end

-- clickable text
function W.Link(parent, text, onClick)
  local b = CreateFrame("Button", nil, parent)
  b.text = W.Label(b, text, "GameFontNormalSmall")
  b.text:SetPoint("LEFT")
  b:SetSize(math.max(40, num(b.text:GetStringWidth(), 80) + 4), 16)
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
  b:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 0.82, 0) end)
  function b:SetLabel(t) self.text:SetText(t); self:SetWidth(math.max(40, num(self.text:GetStringWidth(), 80) + 4)) end
  return b
end

function W.IconButton(parent, size, icon, tipTitle, tipText, onClick)
  local b = CreateFrame("Button", nil, parent)
  size = size or 26
  b:SetSize(size, size)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 3, -3); b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
  b.icon:SetTexture(icon or W.QUESTION)
  b.frame = b:CreateTexture(nil, "BACKGROUND")
  b.frame:SetAllPoints(); b.frame:SetColorTexture(0.25, 0.25, 0.25, 1)
  pcall(b.SetHighlightTexture, b, "Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:SetScript("OnMouseDown", function(self) if self:IsEnabled() == true then self.icon:SetPoint("TOPLEFT", 4, -4) end end)
  b:SetScript("OnMouseUp", function(self) self.icon:SetPoint("TOPLEFT", 3, -3) end)
  if onClick then b:SetScript("OnClick", onClick) end
  if b.SetMotionScriptsWhileDisabled then pcall(b.SetMotionScriptsWhileDisabled, b, true) end
  W.Tooltip(b, tipTitle, tipText)
  function b:SetUsable(v)
    self:SetEnabled(v and true or false)
    self.icon:SetDesaturated(not v); self:SetAlpha(v and 1 or 0.5)
  end
  return b
end

function W.IconToggle(parent, size, icon, tip, onChange)
  local b = W.IconButton(parent, size or 28, icon, tip)
  b.glow = W.Border(b, 2, 1, 0.82, 0, 1)
  b.checked = false
  function b:SetChecked(v)
    self.checked = v and true or false
    self.icon:SetDesaturated(not self.checked)
    if self.checked then self.icon:SetVertexColor(1, 1, 1) else self.icon:SetVertexColor(0.45, 0.45, 0.45) end
    self.glow.show(self.checked)
  end
  function b:GetChecked() return self.checked end
  b:SetScript("OnClick", function(self) self:SetChecked(not self.checked); if onChange then onChange(self, self.checked) end end)
  b:SetChecked(false)
  return b
end

function W.Check(parent, label, onClick)
  local c = W.Create("CheckButton", parent, { "UICheckButtonTemplate" })
  c:SetSize(24, 24)
  c.label = W.Label(c, label)
  c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
  if onClick then c:SetScript("OnClick", onClick) end
  return c
end

function W.Edit(parent, w, maxLetters, search)
  local e = W.Create("EditBox", parent, search and { "SearchBoxTemplate", "InputBoxTemplate" } or { "InputBoxTemplate" })
  e:SetSize(w or 160, 20)
  e:SetAutoFocus(false)
  if not e.SetBackdrop and e.GetRegions and select("#", e:GetRegions()) == 0 then W.Backdrop(e, 0, 0, 0, 0.6) end
  if maxLetters then e:SetMaxLetters(maxLetters) end
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return e
end

-------------------------------------------------------------------------------
-- chips and badges

-- key = goal key (coloured) or any other text (legacy tag, grey). opts.big = 24 px tall
function W.Chip(parent, key, onChange, opts)
  opts = opts or {}
  local h = opts.big and 24 or 18
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(h)
  b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(h - 4, h - 4); b.icon:SetPoint("LEFT", 3, 0)
  b.text = W.Label(b, "", "GameFontHighlightSmall"); b.text:SetPoint("LEFT", b.icon, "RIGHT", 3, 0)
  b.on = true
  function b:SetKey(k)
    self.key = k
    local known = W.GOAL_COLOR[k] ~= nil
    self.legacy = not known
    self.icon:SetShown(known)
    if known then self.icon:SetTexture(W.GOAL_ICON[k]) end
    local short = known and L["GOALSHORT_" .. k] or tostring(k)
    self.text:ClearAllPoints()
    if known then self.text:SetPoint("LEFT", self.icon, "RIGHT", 3, 0) else self.text:SetPoint("LEFT", 6, 0) end
    self.text:SetText(short)
    self:SetWidth(num(self.text:GetStringWidth(), 40) + (known and h + 6 or 12))
    self.tip = known and L["GOAL_" .. k] or (L.UNKNOWN_TAG or "")
    self:SetOn(self.on)
  end
  function b:SetOn(v)
    self.on = v and true or false
    local c = (not self.legacy) and W.GOAL_COLOR[self.key]
    if self.on and c then
      self.bg:SetColorTexture(c[1], c[2], c[3], 0.9); self.text:SetTextColor(1, 1, 1); self.icon:SetDesaturated(false)
    else
      self.bg:SetColorTexture(0.1, 0.1, 0.1, 0.9); self.text:SetTextColor(0.6, 0.6, 0.6); self.icon:SetDesaturated(true)
    end
  end
  function b:GetChecked() return self.on end
  W.Tooltip(b, nil)
  if onChange then
    b:SetScript("OnClick", function(self) self:SetOn(not self.on); onChange(self, self.on) end)
  else
    b:EnableMouse(true)
  end
  b:SetKey(key)
  return b
end

-- a row of chips that re-uses its children. :SetKeys(list)
function W.ChipRow(parent, max, onChange, opts)
  local row = { chips = {} }
  for i = 1, max do row.chips[i] = W.Chip(parent, "leveling", onChange, opts); row.chips[i]:Hide() end
  function row:SetPoint(...) self.anchor = { ... } end
  -- right-aligned rows grow to the left from the anchor (RIGHT point), keeping the key order
  function row:SetKeys(keys, onState)
    local prev
    local n = 0
    for i = 1, #self.chips do if keys and keys[i] then n = i end end
    for i, c in ipairs(self.chips) do
      local k = keys and keys[i]
      if k then
        c:SetKey(k); c:SetOn(onState == nil and true or onState(k)); c:ClearAllPoints(); c:Show()
      else c:Hide() end
    end
    if self.alignRight then
      for i = n, 1, -1 do
        local c = self.chips[i]
        if prev then c:SetPoint("RIGHT", prev, "LEFT", -4, 0) else c:SetPoint(unpack(self.anchor)) end
        prev = c
      end
      return
    end
    for i = 1, n do
      local c = self.chips[i]
      if prev then c:SetPoint("LEFT", prev, "RIGHT", 4, 0) else c:SetPoint(unpack(self.anchor)) end
      prev = c
    end
  end
  function row:SetShown(v) for _, c in ipairs(self.chips) do if not v then c:Hide() end end end
  return row
end

-- maxW (optional) caps the chip width; the text is truncated to one line and the full text goes to the tooltip
function W.ReasonChip(parent, maxW)
  local f = CreateFrame("Frame", nil, parent)
  f.maxW = maxW
  f:SetHeight(16)
  f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints(); f.bg:SetColorTexture(0.11, 0.16, 0.11, 1)
  f.icon = f:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(13, 13); f.icon:SetPoint("LEFT", 2, 0)
  f.text = W.Label(f, ""); f.text:SetPoint("LEFT", f.icon, "RIGHT", 3, 0); f.text:SetTextColor(0.55, 0.9, 0.55)
  -- reason = { key, value } from Match.score
  function f:SetReason(r)
    local k, v = r[1], r[2]
    if k == "role" or k == "role2" then W.SetRole(self.icon, v)
    elseif k == "avail" then self.icon:SetTexture(ICONS .. "INV_Misc_PocketWatch_01"); self.icon:SetTexCoord(0, 1, 0, 1)
    elseif k == "level" then self.icon:SetTexture(ICONS .. "Spell_ChargePositive"); self.icon:SetTexCoord(0, 1, 0, 1)
    else self.icon:SetTexture(W.GOAL_ICON[v] or W.QUESTION); self.icon:SetTexCoord(0, 1, 0, 1) end
    local full = ns.Match.reasonText({ r }, L)
    self.text:SetText(full)
    local w = num(self.text:GetStringWidth(), 60) + 22
    if self.maxW and w > self.maxW then
      w = self.maxW
      self.text:SetWidth(w - 22)
      if self.text.SetWordWrap then pcall(self.text.SetWordWrap, self.text, false) end
    end
    self:SetWidth(w)
    W.Tooltip(self, full)
  end
  return f
end

function W.Badge(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(17, 17)
  f:SetFrameLevel(num(parent:GetFrameLevel(), 1) + 5)
  f.bg = f:CreateTexture(nil, "ARTWORK"); f.bg:SetAllPoints(); f.bg:SetColorTexture(0.77, 0.12, 0.12, 1)
  W.Round(f, f.bg)
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); f.text:SetPoint("CENTER", 0, 0)
  function f:SetCount(n)
    n = tonumber(n) or 0
    self.text:SetText(n > 9 and "9+" or tostring(n))
    self:SetShown(n > 0)
  end
  f:SetCount(0)
  return f
end

function W.FitBadge(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(38, 38)
  f:EnableMouse(true)
  f.bg = f:CreateTexture(nil, "ARTWORK"); f.bg:SetAllPoints()
  W.Round(f, f.bg)
  -- "afinidad" did not fit the 38 px badge: only "82 %", the word goes to the tooltip
  f.num = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.num:SetPoint("CENTER", 0, 0)
  function f:SetFit(score, reasons)
    self.reasons = reasons or {}
    score = score or 0
    self.score = score
    self.num:SetText(W.Pct(score))   -- "82 %"
    if score >= 70 then self.bg:SetColorTexture(0.25, 0.75, 0.25, 1)
    elseif score >= 40 then self.bg:SetColorTexture(0.82, 0.69, 0.13, 1)
    else self.bg:SetColorTexture(0.4, 0.4, 0.4, 1) end
  end
  W.Tooltip(f, function(self, tt)
    tt:SetText(L.FIT .. ": " .. W.Pct(self.score or 0), 1, 0.82, 0)
    if #self.reasons == 0 then tt:AddLine(L.REASON_none, 0.6, 0.6, 0.6) end
    for _, r in ipairs(self.reasons) do tt:AddLine(ns.Match.reasonText({ r }, L), 0.4, 0.9, 0.4) end
  end)
  f:SetFit(0)
  return f
end

-- squad logo: background colour + icon + border
function W.Logo(parent, size)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.bg:SetTexture(WHITE)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  local inset = math.max(2, math.floor(size * 0.08))
  f.icon:SetPoint("TOPLEFT", inset, -inset)
  f.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
  f.edge = W.Border(f, 1, 1, 1, 1, 1)
  function f:SetLogo(icon, color, border)
    local c, b = ns.Logo.color(color), ns.Logo.border(border)
    self.bg:SetVertexColor(c[1], c[2], c[3], 1)
    self.icon:SetTexture(ns.Logo.icon(icon))
    self.icon:SetDesaturated(false)
    for i = 1, 4 do
      local e = self.edge.edges[i]
      if i <= 2 then e:SetHeight(math.max(1, b.size)) else e:SetWidth(math.max(1, b.size)) end
    end
    self.edge.show(b.size > 0)
    self.edge.set(b.r, b.g, b.b, 1)
  end
  function f:SetEmpty()
    self.bg:SetVertexColor(0.15, 0.15, 0.15, 1)
    self.icon:SetTexture(W.QUESTION); self.icon:SetDesaturated(true)
    self.edge.show(true); self.edge.set(0.4, 0.4, 0.4, 1)
  end
  return f
end

-------------------------------------------------------------------------------
-- context menu: our own frame (no MenuUtil / UIDropDownMenu dependency)
-- items = { { text=, func=, danger=, title=, disabled= }, ... }
local menu
W.MENU_TICK = 0.25
-- close after the cursor stays away for 1.5 s (pure step, also used by the tests)
function W.MenuIdleTick(m, dt)
  local over = m.IsMouseOver and m:IsMouseOver() == true
  if over then m.idle = 0 else m.idle = (m.idle or 0) + (dt or 0) end
  if m.idle > 1.5 then m:Hide(); return true end
  return false
end
function W.Menu(owner, items)
  if not menu then
    menu = CreateFrame("Frame", "GuildSquadsMenu", UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    W.Backdrop(menu, 0.03, 0.03, 0.05, 0.95, 0.6, 0.6, 0.6)
    menu.buttons = {}
    menu.idle = 0
    -- the auto-close check runs on a 0.25 s timer (C_Timer.NewTicker; ns.Every falls back to OnUpdate)
    -- that only exists while the menu is shown, instead of an every-frame OnUpdate. Created in OnShow
    -- so it also restarts when a hidden parent (Alt+Z) is shown again.
    menu:SetScript("OnShow", function(self)
      self.idle = 0
      if not self.ticker and ns.Every then
        self.ticker = ns.Every(W.MENU_TICK, function() W.MenuIdleTick(self, W.MENU_TICK) end, self)
      end
    end)
    menu:SetScript("OnHide", function(self)
      if self.ticker and self.ticker.Cancel then pcall(self.ticker.Cancel, self.ticker) end
      self.ticker = nil
    end)
    tinsert(UISpecialFrames, "GuildSquadsMenu")
  end
  for _, b in ipairs(menu.buttons) do b:Hide() end
  local y = -6
  for i, it in ipairs(items) do
    local b = menu.buttons[i]
    if not b then
      b = CreateFrame("Button", nil, menu)
      b:SetHeight(18)
      b.text = W.Label(b, "", "GameFontHighlightSmall"); b.text:SetPoint("LEFT", 8, 0)
      pcall(b.SetHighlightTexture, b, "Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      menu.buttons[i] = b
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 4, y); b:SetPoint("RIGHT", menu, "RIGHT", -4, 0)
    b.text:SetText(it.text)
    if it.title then b.text:SetTextColor(1, 0.82, 0)
    elseif it.danger then b.text:SetTextColor(1, 0.3, 0.3)
    elseif it.disabled then b.text:SetTextColor(0.5, 0.5, 0.5)
    else b.text:SetTextColor(1, 1, 1) end
    b:SetEnabled(not it.title and not it.disabled)
    b:SetScript("OnClick", function()
      menu:Hide()
      if not it.func then return end
      if it.danger then W.Confirm(it.confirm or it.text, it.func) else it.func() end
    end)
    b:Show()
    y = y - 18
  end
  menu:SetSize(160, -y + 6)
  menu:ClearAllPoints()
  local x, cy = 0, 0
  if GetCursorPosition then x, cy = GetCursorPosition() end
  local s = num(UIParent.GetEffectiveScale and UIParent:GetEffectiveScale(), 1)
  if type(x) == "number" and type(cy) == "number" and s and s > 0 then
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s + 2, cy / s - 2)
  else
    menu:SetPoint("TOPLEFT", owner, "CENTER")
  end
  menu.idle = 0
  menu:Show()
  return menu
end
function W.CloseMenu() if menu then menu:Hide() end end

-------------------------------------------------------------------------------
-- confirmation / prompt (StaticPopup)
local function popups()
  if not StaticPopupDialogs or StaticPopupDialogs.GUILDSQUADS_CONFIRM then return end
  StaticPopupDialogs.GUILDSQUADS_CONFIRM = {
    text = "%s", button1 = OKAY or "OK", button2 = CANCEL or "Cancel",
    OnAccept = function(_, data) if data then data() end end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1,
  }
  StaticPopupDialogs.GUILDSQUADS_PROMPT = {
    text = "%s", button1 = L.INVITE, button2 = CANCEL or "Cancel", hasEditBox = 1, maxLetters = 48,
    OnAccept = function(self, data)
      local eb = self.editBox or self.EditBox or (self.GetName and _G[self:GetName() .. "EditBox"])
      if data and eb then data(eb:GetText()) end
    end,
    EditBoxOnEnterPressed = function(eb, data)
      local p = eb:GetParent()
      if data then data(eb:GetText()) end
      if p then p:Hide() end
    end,
    EditBoxOnEscapePressed = function(eb) local p = eb:GetParent(); if p then p:Hide() end end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
  }
end

-- optional verb labels ("Descartar" / "Seguir editando") instead of OK / Cancel
-- optional third button (StaticPopup button3 / OnAlt), e.g. "Guardar y salir"
function W.Confirm(text, fn, okText, cancelText, altText, altFn)
  popups()
  if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs.GUILDSQUADS_CONFIRM then
    local dlg = StaticPopupDialogs.GUILDSQUADS_CONFIRM
    dlg.button1 = okText or OKAY or "OK"
    dlg.button2 = cancelText or CANCEL or "Cancel"
    if altText and altFn then
      dlg.button3, dlg.OnAlt = altText, function() altFn() end
    else
      dlg.button3, dlg.OnAlt = nil, nil
    end
    StaticPopup_Show("GUILDSQUADS_CONFIRM", text, nil, fn)
  else
    ns.print(text) -- no popup system: refuse silently rather than act without confirmation
  end
end

-- okText: label of the accept button (default "Invitar"); maxLetters optional
function W.Prompt(text, fn, okText, maxLetters)
  popups()
  if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs.GUILDSQUADS_PROMPT then
    StaticPopupDialogs.GUILDSQUADS_PROMPT.button1 = okText or L.INVITE
    StaticPopupDialogs.GUILDSQUADS_PROMPT.maxLetters = maxLetters or 48
    StaticPopup_Show("GUILDSQUADS_PROMPT", text, nil, fn)
  end
end

-------------------------------------------------------------------------------
-- virtual grid: fixed pool of cells, mouse wheel scrolls by one row
function W.Grid(parent, cols, rows, cellW, cellH, gapX, gapY, make, fill)
  local g = { cells = {}, items = {}, offset = 0, cols = cols, rows = rows }
  for i = 1, cols * rows do
    local c = make(parent, i)
    c:SetSize(cellW, cellH)
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", col * (cellW + gapX), -row * (cellH + gapY))
    g.cells[i] = c
  end
  parent:EnableMouseWheel(true)
  parent:SetScript("OnMouseWheel", function(_, delta)
    local maxOff = math.max(0, math.ceil(#g.items / cols) - rows)
    g.offset = math.max(0, math.min(maxOff, g.offset - delta))
    g:Render()
  end)
  function g:SetItems(items) self.items = items or {}; self.offset = 0; self:Render() end
  function g:Render()
    for i, c in ipairs(self.cells) do
      local item = self.items[self.offset * self.cols + i]
      if item then fill(c, item); c:Show() else c:Hide() end
    end
  end
  return g
end

-- a card: button with dark background, 1px border, highlight and right-click
function W.Card(parent)
  local c = CreateFrame("Button", nil, parent)
  c.bg = c:CreateTexture(nil, "BACKGROUND"); c.bg:SetAllPoints(); c.bg:SetColorTexture(0.08, 0.07, 0.06, 0.9)
  c.border = W.Border(c, 1, 0.3, 0.3, 0.3, 1)
  pcall(c.SetHighlightTexture, c, "Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  if c.RegisterForClicks then c:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  return c
end

-- one-line summary per category for /gsq ui
function W.ReportLines()
  local function keys(t) local o = {}; for k in pairs(t) do o[#o + 1] = k end; table.sort(o); return table.concat(o, ", ") end
  local r = W.report
  return { "templates OK: " .. keys(r.tplOK), "templates missing: " .. keys(r.tplFail),
           "atlas OK: " .. keys(r.atlasOK), "atlas missing (file fallback): " .. keys(r.atlasMiss),
           "window template: " .. tostring(ns.UI and ns.UI.template) }
end
