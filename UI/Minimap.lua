-- Guild Squads (MIT) - UI/Minimap.lua
-- Own minimap button (no LibDBIcon): drag around the minimap, left-click toggles, right-click menu.
local _, ns = ...
local L, W = ns.L, ns.W
local MM = {}
ns.Minimap = MM
local btn

local function db() GuildSquadsDB.minimap = GuildSquadsDB.minimap or { angle = 200 }; return GuildSquadsDB.minimap end

local function place()
  local a = math.rad(db().angle or 200)
  btn:ClearAllPoints()
  -- real minimap radius (Retail ~200 px) instead of a fixed 80 px; 80 when the size is unknown
  local r = 80
  if Minimap and Minimap.GetWidth then
    local okW, w = pcall(Minimap.GetWidth, Minimap)
    if okW and type(w) == "number" and w > 0 then r = w / 2 + 10 end
  end
  btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function onDrag()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local s = UIParent:GetEffectiveScale()
  if type(mx) ~= "number" or type(cx) ~= "number" or type(s) ~= "number" or s == 0 then return end
  local dx, dy = cx / s - mx, cy / s - my
  local deg = math.deg(math.atan2 and math.atan2(dy, dx) or math.atan(dy, dx))
  db().angle = deg % 360
  place()
end

function MM.Create()
  if btn or not Minimap then return end
  btn = CreateFrame("Button", "GuildSquadsMinimapButton", Minimap)
  btn:SetSize(31, 31)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  local bg = btn:CreateTexture(nil, "BACKGROUND"); bg:SetSize(20, 20); bg:SetPoint("CENTER")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  local icon = btn:CreateTexture(nil, "ARTWORK"); icon:SetSize(18, 18); icon:SetPoint("CENTER")
  icon:SetTexture("Interface\\Icons\\INV_Banner_02"); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local border = btn:CreateTexture(nil, "OVERLAY"); border:SetSize(53, 53); border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  pcall(btn.SetHighlightTexture, btn, "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")
  btn:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDrag) end)
  btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  btn:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      W.Menu(self, {
        { text = L.TITLE, title = true },
        { text = L.TAB_MYSQUAD, func = function() ns.UI.Open("mysquad") end },
        { text = L.TAB_FINDER, func = function() ns.UI.Open("finder") end },
        { text = L.MINIMAP_HIDE, func = function() db().hide = true; btn:Hide(); ns.print(L.MINIMAP_HIDDEN) end },
        { text = CANCEL or L.CANCEL },
      })
    else ns.UI.Toggle() end
  end)
  W.Tooltip(btn, function(_, tt)
    tt:SetText(L.TITLE, 1, 0.82, 0)
    local id = ns.Actions.MySquadId()
    if id then
      local mem = ns.Model.members(ns.state, id)
      local on = 0
      for _, n in ipairs(mem) do local r = ns.roster(n); if r and r.online then on = on + 1 end end
      tt:AddLine(L.MINIMAP_SQUAD:format(ns.state.squads[id].d.name, on, #mem), 1, 1, 1)
    end
    local p = ns.Actions.PendingCount()
    if p > 0 then tt:AddLine(L.MINIMAP_REQ:format(p), 1, 1, 1) end
    tt:AddLine(L.MINIMAP_TIP, 0.6, 0.6, 0.6)
  end)
  place()
  if db().hide then btn:Hide() end
end

function MM.Show() MM.Create(); if btn then btn:Show(); place() end end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() pcall(MM.Create) end)
