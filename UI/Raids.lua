-- Guild Squads (MIT) - UI/Raids.lua
-- "Bandas" tab (between Ranking and Salón de la fama). Two views on the same panel:
--   list   : upcoming / my raids / past rosters as cards (raid, date, n/size, role counts, my RSVP + one-click RSVP)
--   editor : groups G1-G8 of 5 slots, squads/players panel with "+", composition bar, warnings, RSVP of each player,
--            and ONE red primary button by state: "Publicar" (draft) or "Invitar confirmados" (published).
-- layout: nothing under the portrait (top rows via UI.TopRow), one red button, secondary buttons are grey.
local _, ns = ...
local L, W, UI, M, R = ns.L, ns.W, ns.UI, ns.Model, ns.Roster
local G = ns.RaidGlue
local ICONS = "Interface\\Icons\\"

local rb = { view = "list", filter = "upcoming", rid = nil, draft = nil, dirty = false, role = nil, online = false, search = "" }
UI.RaidsState = function() return rb end

local RAID_OPTS = { { "barrow", 10 }, { "hyjal", 20 }, { "onyxia", 40 }, { "custom", 10 }, { "custom", 20 }, { "custom", 40 } }
local ANS_COLOR = { yes = "|cff33dd33", maybe = "|cffffd100", no = "|cffff4040", bench = "|cff9999ff" }

local function raidLabel(raid, size)
  local C = ns.Content
  local e = raid ~= "custom" and C and C.get(raid)
  return ((e and e.name) or L.RB_CUSTOM) .. " (" .. tostring(size) .. ")"
end
local WEEKDAY = { "RB_WD1", "RB_WD2", "RB_WD3", "RB_WD4", "RB_WD5", "RB_WD6", "RB_WD7" }
local function dateLabel(at)
  local _, m, d, h, mi, wd = R.fields(at)
  return ("%s %02d/%02d %02d:%02d"):format(L[WEEKDAY[wd]], d, m, h, mi)
end
local function short(n) return ns.shortName(n) end
local function ansText(v) return v and ((ANS_COLOR[v] or "") .. (L["RB_ANS_" .. v] or v) .. "|r") or ("|cff888888" .. L.RB_NO_ANSWER .. "|r") end
local function roleCounts(c) return ("%dT %dH %dD"):format(c.TANK, c.HEALER, c.DAMAGER) end
local function warnText(w)
  local out = {}
  for _, x in ipairs(w) do
    if x.kind == "missing" then out[#out + 1] = L.RB_W_MISSING:format(x.n, R.ROLE_SHORT[x.role])
    elseif x.kind == "extra" then out[#out + 1] = L.RB_W_EXTRA:format(x.n, R.ROLE_SHORT[x.role])
    elseif x.kind == "empty" then out[#out + 1] = L.RB_W_EMPTY:format(x.n)
    elseif x.kind == "util" then out[#out + 1] = L.RB_W_UTIL:format(L["RB_U_" .. x.key] or x.key) end
  end
  return table.concat(out, " · ")
end

-------------------------------------------------------------------------------
-- list view
local function listItems()
  local wall, me = G.WallNow(), ns.me()
  local canLead = G.CanLead()
  local out = {}
  if rb.filter == "mine" then
    for _, r in ipairs(R.mine(ns.state, me)) do if r.d.at + R.CLOSE_AFTER >= wall then out[#out + 1] = r end end
  elseif rb.filter == "past" then
    for _, r in ipairs(R.list(ns.state, function(r) return r.d.st == "closed" or r.d.st == "cancelled" or r.d.at + R.CLOSE_AFTER < wall end)) do
      table.insert(out, 1, r)
    end
  else
    out = R.list(ns.state, function(r)
      if r.d.st == "closed" or r.d.st == "cancelled" or r.d.at + R.CLOSE_AFTER < wall then return false end
      return r.d.st == "published" or (canLead and G.CanEdit(r.id))
    end)
  end
  return out
end

local function makeCard(parent)
  local c = W.Card(parent)
  c.title = W.Label(c, "", "GameFontNormal"); c.title:SetPoint("TOPLEFT", 10, -5)
  c.title:SetWidth(285); if c.title.SetWordWrap then c.title:SetWordWrap(false) end
  c.sub = W.Label(c, "", "GameFontHighlightSmall"); c.sub:SetPoint("TOPLEFT", 10, -22)
  c.count = W.Label(c, "", "GameFontHighlight"); c.count:SetPoint("TOPLEFT", 300, -5)
  c.roles = W.Label(c, "", "GameFontHighlightSmall"); c.roles:SetPoint("TOPLEFT", 300, -22)
  c.my = W.Label(c, "", "GameFontHighlightSmall"); c.my:SetPoint("TOPLEFT", 400, -5)
  c.ans = {}
  local prev
  for i, v in ipairs(R.ANSWERS) do
    local b = W.Button(c, L["RB_ANS_" .. v], 64, 18, function() if c.rid then G.Answer(c.rid, v); UI.Select("raids") end end)
    if i == 1 then b:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -6 - 3 * 66, 4) else b:SetPoint("LEFT", prev, "RIGHT", 2, 0) end
    prev = b
    c.ans[v] = b
  end
  c:SetScript("OnClick", function() if c.rid then UI.OpenRoster(c.rid) end end)
  return c
end
local function fillCard(c, r)
  local d = r.d
  c.rid = r.id
  local cov = R.coverage(d, G.roleOf)
  c.title:SetText(d.name .. "  |cffaaaaaa" .. raidLabel(d.raid, d.size) .. "|r")
  -- the card says "asistencia pendiente" like the editor
  local stc = (R.attendanceState(ns.state, r.id) == "pending") and L.RB_ST_closed_pending or (L["RB_ST_" .. d.st] or d.st)
  c.sub:SetText(dateLabel(d.at) .. "  ·  " .. stc .. (d.wk and ("  ·  " .. L.RB_WEEKLY) or ""))
  c.count:SetText(("%d/%d"):format(cov.filled, d.size))
  c.roles:SetText(roleCounts(cov))
  local me = ns.me()
  local a = R.rsvpOf(ns.state, r.id, me)
  local listed = R.where(d, me) ~= nil
  c.my:SetText((listed or a) and (L.RB_YOUR_ANSWER .. " " .. ansText(a and a.v)) or "")
  local canAnswer = d.st == "published" and (listed or a ~= nil)
  for v, b in pairs(c.ans) do
    b:SetShown(canAnswer)
    W.SetSelected(b, a ~= nil and a.v == v)
  end
end

-------------------------------------------------------------------------------
-- editor view
local function draftOf(rid)
  local r = G.Get(rid)
  return r and R.copy(r.d) or nil
end
local function markDirty() rb.dirty = true; UI.Select("raids") end
-- light refresh while typing (name, Cada semana): Guardar on and "sin guardar" shown
local function touch()
  rb.dirty = true
  if rb.save then rb.save:SetEnabled(true) end
  if rb.state and rb.stBase then rb.state:SetText(rb.stBase .. "  |cffff9933" .. L.RB_UNSAVED .. "|r") end
end

local function resize(d, raid, size)
  -- going down to a smaller size asks first and lists who would leave the roster
  local lost = R.shrinkLoss(d, size)
  if #lost > 0 and not rb.shrinkOk then
    local names = {}
    for _, n in ipairs(lost) do names[#names + 1] = short(n) end
    W.Confirm(L.RB_SHRINK_CONFIRM:format(#lost, table.concat(names, ", ")), function()
      rb.shrinkOk = true; resize(d, raid, size); rb.shrinkOk = nil; markDirty()
    end)
    return false
  end
  local overflow = {}
  for i = size + 1, #d.main do if d.main[i] ~= "" then overflow[#overflow + 1] = d.main[i] end end
  d.raid, d.size = raid, size
  R.normalize(d)
  for _, n in ipairs(overflow) do
    if not R.addPlayer(d, n) then R.addPlayer(d, n, "bench") end
  end
  d.tpl = R.defaultTpl(size)
end

local function slotMenu(slot, name)
  return {
    { text = short(name), title = true },
    { text = L.RB_TO_BENCH, func = function() R.movePlayer(rb.draft, name, "bench"); markDirty() end },
    { text = L.RB_REMOVE, danger = true, func = function() R.removePlayer(rb.draft, name); markDirty() end },
  }
end

local function makeSlot(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(102, 16)
  b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
  b.role = b:CreateTexture(nil, "ARTWORK"); b.role:SetSize(14, 14); b.role:SetPoint("LEFT", 1, 0)
  b.text = W.Label(b, "", "GameFontHighlightSmall"); b.text:SetPoint("LEFT", 17, 0); b.text:SetWidth(84)
  if b.text.SetJustifyH then b.text:SetJustifyH("LEFT") end
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  b:SetScript("OnClick", function(self)
    -- on a closed roster the RL / GM mark who was there (7 days), then sign
    if self.name and rb.attMode and rb.att then
      rb.att[self.name] = not rb.att[self.name] or nil; UI.Select("raids"); return
    end
    if not self.name or not rb.editable then return end
    W.Menu(self, slotMenu(self.slot, self.name))
  end)
  b:SetScript("OnEnter", function(self)
    if not self.name or not GameTooltip then return end
    pcall(GameTooltip.SetOwner, GameTooltip, self, "ANCHOR_RIGHT")
    local a = rb.rid and R.rsvpOf(ns.state, rb.rid, self.name)
    pcall(GameTooltip.SetText, GameTooltip, short(self.name))
    pcall(GameTooltip.AddLine, GameTooltip, ansText(a and a.v) .. ((a and a.c and a.c ~= "") and (" - " .. a.c) or ""))
    pcall(GameTooltip.Show, GameTooltip)
  end)
  b:SetScript("OnLeave", function() if GameTooltip then pcall(GameTooltip.Hide, GameTooltip) end end)
  return b
end

local function fillSlot(b, slot, name)
  b.slot, b.name = slot, (name ~= "" and name or nil)
  if b.name then
    local _, _, _, hex = W.ClassColor(G.classOf(name))
    local a = rb.rid and R.rsvpOf(ns.state, rb.rid, name)
    local mark = a and ((ANS_COLOR[a.v] or "") .. "•|r ") or ""
    if rb.attMode and rb.att then mark = rb.att[name] and "|cff33dd33+|r " or "|cff888888-|r " end
    b.text:SetText(mark .. hex .. short(name) .. "|r")
    W.SetRole(b.role, G.roleOf(name) or "?")
    b.role:Show()
  else
    b.text:SetText("|cff999999" .. L.RB_EMPTY_SLOT .. "|r"); b.role:Hide()
  end
end

-- add panel items: squads first (whole blocks), then guild players (filters: role, online, text / min level)
local function addItems()
  local out = {}
  local d = rb.draft
  if not d then return out end
  local q = (rb.search or ""):lower()
  local minLevel = tonumber(q)
  for id, s in pairs(ns.state.squads) do
    if not s.d.disbanded and (q == "" or minLevel or s.d.name:lower():find(q, 1, true)) then
      out[#out + 1] = { squad = id, name = s.d.name, n = #M.members(ns.state, id) }
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  local players = {}
  for name, info in pairs(ns.rosterList and ns.rosterList() or {}) do
    if not R.where(d, name) then
      local role = G.roleOf(name)
      local okRole = not rb.role or role == rb.role
      local okOn = not rb.online or info.online
      local okQ = q == "" or (minLevel and (info.level or 0) >= minLevel) or (not minLevel and (name:lower():find(q, 1, true) or (info.class or ""):lower():find(q, 1, true)))
      if okRole and okOn and okQ then players[#players + 1] = { player = name, info = info, role = role } end
    end
  end
  table.sort(players, function(a, b) return a.player < b.player end)
  for _, p in ipairs(players) do out[#out + 1] = p end
  return out
end

local function addSquadToDraft(id)
  local d = rb.draft
  local res = R.addSquad(d, M.members(ns.state, id), M.benchMembers(ns.state, id))
  if #res.notFit > 0 then
    local names = {}
    for _, n in ipairs(res.notFit) do names[#names + 1] = short(n) end
    ns.Feedback(true, L.RB_NOT_FIT:format(table.concat(names, ", ")))
  elseif res.split then ns.Feedback(true, L.RB_SPLIT) end
  markDirty()
end

local function makeAddRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(0.08, 0.07, 0.06, 0.8)
  r.plus = W.Button(r, "+", 22, 18, function()
    if not rb.editable or not r.item then return end
    if r.item.squad then addSquadToDraft(r.item.squad)
    else
      local okA, why = R.addPlayer(rb.draft, r.item.player)
      if not okA and why == "full" then okA = R.addPlayer(rb.draft, r.item.player, "bench") end
      markDirty()
    end
  end)
  r.plus:SetPoint("RIGHT", -2, 0)
  r.role = r:CreateTexture(nil, "ARTWORK"); r.role:SetSize(14, 14); r.role:SetPoint("LEFT", 2, 0)
  r.text = W.Label(r, "", "GameFontHighlightSmall"); r.text:SetPoint("LEFT", 20, 0); r.text:SetWidth(180)
  if r.text.SetJustifyH then r.text:SetJustifyH("LEFT") end
  return r
end
local function fillAddRow(r, item)
  r.item = item
  if item.squad then
    r.role:SetTexture(ICONS .. "INV_Banner_02")
    r.text:SetText("|cffffd100" .. item.name .. "|r  (" .. item.n .. ")")
  else
    W.SetRole(r.role, item.role or "?")
    local _, _, _, hex = W.ClassColor(item.info.class)
    r.text:SetText(hex .. short(item.player) .. "|r  " .. tostring(item.info.level or "") .. (item.info.online and "" or "  |cff777777" .. L.RB_OFFLINE .. "|r"))
  end
end

-------------------------------------------------------------------------------
UI.Register("raids", L.TAB_RAIDS, function(f, bar)
  rb.f, rb.bar = f, bar
  -- list view
  local lv = CreateFrame("Frame", nil, f); lv:SetAllPoints(); rb.lv = lv
  rb.seg = {}
  local row = {}
  for _, k in ipairs({ "upcoming", "mine", "past" }) do
    local b = W.Button(lv, L["RB_F_" .. k], 110, 22, function() rb.filter = k; UI.Select("raids") end)
    rb.seg[k] = b; row[#row + 1] = b
  end
  UI.TopRow(lv, row, 4, -8)
  local area = CreateFrame("Frame", nil, lv); area:SetPoint("TOPLEFT", 10, -40); area:SetSize(676, 380)
  rb.grid = W.Grid(area, 1, 8, 676, 44, 0, 3, makeCard, fillCard)
  rb.empty = W.Label(lv, "", "GameFontNormal"); rb.empty:SetPoint("TOP", area, "TOP", 0, -60); rb.empty:SetTextColor(1, 0.82, 0)
  rb.empty2 = W.Label(lv, "", "GameFontHighlight"); rb.empty2:SetPoint("TOP", rb.empty, "BOTTOM", 0, -6); rb.empty2:SetTextColor(0.7, 0.7, 0.7)

  -- editor view
  local ed = CreateFrame("Frame", nil, f); ed:SetAllPoints(); ed:Hide(); rb.ed = ed
  rb.back = W.Button(ed, L.RB_BACK, 80, 22, function()
    local function go() rb.view, rb.rid, rb.draft, rb.dirty = "list", nil, nil, false; UI.Select("raids") end
    if rb.dirty and rb.editable then W.Confirm(L.S_UNSAVED, go, L.DISCARD, L.KEEP_EDITING) else go() end
  end)
  rb.name = W.Edit(ed, 150, 32)
  rb.name:SetScript("OnTextChanged", function(self, user)
    if user == false or not rb.draft or not rb.editable then return end
    local t = self:GetText() or ""
    if t ~= rb.draft.name then rb.draft.name = t; touch() end
  end)
  W.Tooltip(rb.name, L.RB_NAME, L.RB_NAME_TIP)
  rb.raidBtn = W.Button(ed, "", 160, 22, function()
    if not rb.draft or not rb.editable then return end
    local cur = 1
    for i, o in ipairs(RAID_OPTS) do if o[1] == rb.draft.raid and o[2] == rb.draft.size then cur = i end end
    local o = RAID_OPTS[cur % #RAID_OPTS + 1]
    if resize(rb.draft, o[1], o[2]) ~= false then markDirty() end
  end)
  W.Tooltip(rb.raidBtn, L.RB_RAID, L.RB_RAID_TIP)
  rb.date = W.Edit(ed, 120, 16)
  W.Tooltip(rb.date, L.RB_DATE, L.RB_DATE_TIP)
  local function commitDate(self)
    if rb.draft and rb.editable then
      local w = R.parseWall(self:GetText() or "")
      if w then rb.draft.at = w; rb.dirty = true
      elseif UIErrorsFrame and UIErrorsFrame.AddMessage then pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, L.RB_DATE_BAD, 1, 0.3, 0.3) end
    end
    self:ClearFocus(); UI.Select("raids")
  end
  rb.date:SetScript("OnEnterPressed", commitDate)
  UI.TopRow(ed, { rb.back, rb.name, rb.raidBtn, rb.date }, 6, -8)
  -- row 2: template, weekly, composition bar, state
  local tl = W.Label(ed, L.RB_TEMPLATE, "GameFontNormalSmall"); tl:SetPoint("TOPLEFT", 10, -42)
  rb.tpl = W.Edit(ed, 90, 20); rb.tpl:SetPoint("TOPLEFT", 70, -38)
  W.Tooltip(rb.tpl, L.RB_TEMPLATE, L.RB_TEMPLATE_TIP)
  rb.tpl:SetScript("OnEnterPressed", function(self)
    if rb.draft and rb.editable then rb.draft.tpl = R.tplString(R.parseTpl(self:GetText() or "", rb.draft.size)); rb.dirty = true end
    self:ClearFocus(); UI.Select("raids")
  end)
  rb.weekly = W.Check(ed, L.RB_WEEKLY, function(self)
    if not rb.draft or not rb.editable then self:SetChecked(rb.draft and rb.draft.wk or false); return end
    rb.draft.wk = self:GetChecked() and true or false; touch()
  end)
  rb.weekly:SetPoint("TOPLEFT", 170, -36)
  rb.comp = W.Label(ed, "", "GameFontHighlight"); rb.comp:SetPoint("TOPLEFT", 290, -42)
  rb.state = W.Label(ed, "", "GameFontNormalSmall"); rb.state:SetPoint("TOPRIGHT", -10, -42)
  -- groups G1..G8 (4 x 2 boxes of 5 slots)
  rb.groups = {}
  for g = 1, 8 do
    local col, line = (g - 1) % 4, math.floor((g - 1) / 4)
    local box = CreateFrame("Frame", nil, ed); box:SetSize(106, 102)
    box:SetPoint("TOPLEFT", 10 + col * 110, -64 - line * 106)
    box.title = W.Label(box, "G" .. g, "GameFontNormalSmall"); box.title:SetPoint("TOPLEFT", 2, 0)
    box.slots = {}
    for i = 1, 5 do
      local s = makeSlot(box); s:SetPoint("TOPLEFT", 2, -14 - (i - 1) * 17)
      box.slots[i] = s
    end
    rb.groups[g] = box
  end
  rb.bench = W.Label(ed, "", "GameFontHighlightSmall"); rb.bench:SetPoint("TOPLEFT", 12, -280); rb.bench:SetWidth(430)
  if rb.bench.SetJustifyH then rb.bench:SetJustifyH("LEFT") end
  rb.warn = W.Label(ed, "", "GameFontHighlightSmall"); rb.warn:SetPoint("TOPLEFT", 12, -300); rb.warn:SetWidth(430)
  rb.warn:SetTextColor(1, 0.6, 0.2)
  if rb.warn.SetJustifyH then rb.warn:SetJustifyH("LEFT") end
  rb.rsvp = W.Label(ed, "", "GameFontHighlightSmall"); rb.rsvp:SetPoint("TOPLEFT", 12, -336); rb.rsvp:SetWidth(430)
  if rb.rsvp.SetJustifyH then rb.rsvp:SetJustifyH("LEFT") end
  -- my answer
  local ml = W.Label(ed, L.RB_YOUR_ANSWER, "GameFontNormalSmall"); ml:SetPoint("TOPLEFT", 12, -364); rb.myLabel = ml
  rb.myAns = {}
  local prev
  for i, v in ipairs(R.ANSWERS) do
    local b = W.Button(ed, L["RB_ANS_" .. v], 58, 20, function()   -- 58 px
      if rb.rid then G.Answer(rb.rid, v, rb.comment:GetText()); UI.Select("raids") end
    end)
    if i == 1 then b:SetPoint("TOPLEFT", 100, -360) else b:SetPoint("LEFT", prev, "RIGHT", 2, 0) end
    prev = b; rb.myAns[v] = b
  end
  -- the comment box ends before the add panel (x 452): 100 + 4*58 + 3*2 + 8 + 100 = 446
  rb.comment = W.Edit(ed, 100, R.MAX_COMMENT); rb.comment:SetPoint("LEFT", prev, "RIGHT", 8, 0)
  W.Tooltip(rb.comment, L.RB_COMMENT, L.RB_COMMENT_TIP)
  -- add panel (right)
  local ap = CreateFrame("Frame", nil, ed); ap:SetPoint("TOPLEFT", 452, -64); ap:SetSize(234, 360); rb.addPanel = ap
  local at = W.Label(ap, L.RB_ADD, "GameFontNormalSmall"); at:SetPoint("TOPLEFT", 0, 0)
  rb.roleBtn = W.Button(ap, L.RB_ROLE_ALL, 60, 18, function()
    local order = { nil, "TANK", "HEALER", "DAMAGER" }
    local idx = 1
    for i = 1, 4 do if order[i] == rb.role then idx = i end end
    rb.role = order[idx % 4 + 1]
    UI.Select("raids")
  end)
  rb.roleBtn:SetPoint("TOPLEFT", 0, -16)
  rb.onlineChk = W.Check(ap, L.RB_ONLINE, function(self) rb.online = self:GetChecked() and true or false; UI.Select("raids") end)
  rb.onlineChk:SetPoint("LEFT", rb.roleBtn, "RIGHT", 4, 0)
  rb.searchBox = W.Edit(ap, 70, 20, true); rb.searchBox:SetPoint("TOPRIGHT", 0, -16)
  W.Tooltip(rb.searchBox, L.RB_SEARCH, L.RB_SEARCH_TIP)
  rb.searchBox:SetScript("OnTextChanged", function(self, user)
    if user == false then return end
    rb.search = self:GetText() or ""; UI.Select("raids")
  end)
  local lst = CreateFrame("Frame", nil, ap); lst:SetPoint("TOPLEFT", 0, -40); lst:SetSize(234, 300)
  rb.addGrid = W.Grid(lst, 1, 13, 234, 20, 0, 2, makeAddRow, fillAddRow)
  -- bottom bar: secondary actions + the one red primary button
  rb.save = W.Button(bar, L.RB_SAVE, 80, 22, function()
    if rb.draft and rb.editable then
      if G.Save(rb.rid, rb.draft) then rb.dirty = false; ns.Feedback(true, L.RB_FB_SAVED) end
      UI.Select("raids")
    end
  end)
  rb.close = W.Button(bar, L.RB_CLOSE, 80, 22, function()
    if not rb.rid then return end
    W.Confirm(rb.dirty and (L.RB_CLOSE_CONFIRM .. "\n" .. L.RB_CLOSE_UNSAVED) or L.RB_CLOSE_CONFIRM, function() G.Close(rb.rid); rb.dirty = false; rb.draft = draftOf(rb.rid); UI.Select("raids") end)
  end)
  rb.cancel = W.Button(bar, L.RB_CANCEL, 80, 22, function()
    if not rb.rid then return end
    W.Confirm(L.RB_CANCEL_CONFIRM, function() G.Cancel(rb.rid); rb.dirty = false; rb.draft = draftOf(rb.rid); UI.Select("raids") end)
  end)
  rb.dup = W.Button(bar, L.RB_DUPLICATE, 80, 22, function()
    if not rb.rid then return end
    local id = G.Duplicate(rb.rid)
    if id then UI.OpenRoster(id) end
  end)
  rb.export = W.IconButton(bar, 22, ICONS .. "INV_Misc_Note_01", L.RB_EXPORT, L.RB_EXPORT_TIP, function()
    if rb.rid then UI.ShowExport(G.ExportText(rb.rid), false, L.RB_EXPORT_HELP) end
  end)
  rb.primary = W.Primary(bar, L.RB_NEW, function() UI.RaidPrimary() end)
  rb.save:SetPoint("RIGHT", rb.primary, "LEFT", -8, 0)
  rb.close:SetPoint("RIGHT", rb.save, "LEFT", -4, 0)
  rb.cancel:SetPoint("RIGHT", rb.close, "LEFT", -4, 0)
  rb.dup:SetPoint("RIGHT", rb.cancel, "LEFT", -4, 0)
  rb.export:SetPoint("RIGHT", rb.dup, "LEFT", -6, 0)
end, function(f, bar)
  local list = rb.view == "list"
  rb.lv:SetShown(list); rb.ed:SetShown(not list)
  local canLead = G.CanLead()
  if list then
    for k, b in pairs(rb.seg) do W.SetSelected(b, k == rb.filter) end
    local items = listItems()
    rb.grid:SetItems(items)
    local msg, msg2 = "", ""
    if #items == 0 then
      msg = L["RB_EMPTY_" .. rb.filter] or L.RB_EMPTY_upcoming
      if rb.filter == "upcoming" then msg2 = canLead and L.RB_EMPTY_LEAD or L.RB_EMPTY_MEMBER end
    end
    rb.empty:SetText(msg); rb.empty:SetShown(msg ~= "")
    rb.empty2:SetText(msg2); rb.empty2:SetShown(msg2 ~= "")
    for _, b in ipairs({ rb.save, rb.close, rb.cancel, rb.dup, rb.export }) do b:Hide() end
    rb.primary:SetText(L.RB_NEW); rb.primary:SetShown(canLead); rb.primary:SetEnabled(true); W.Tooltip(rb.primary, nil)
    bar.status:SetWidth(0)
    bar.status:SetText(L.RB_STATUS:format(#items))
    return
  end
  -- editor / detail
  local rec = rb.rid and G.Get(rb.rid)
  if not rec then rb.view = "list"; return UI.Select("raids") end
  -- a remote version of the open roster refreshes a clean draft; a dirty one is flagged
  if rb.draft and rb.draftTs and rec.ts ~= rb.draftTs and not rb.dirty then rb.draft = nil end
  if not rb.draft then rb.draft = R.copy(rec.d); rb.dirty = false; rb.draftTs = rec.ts end
  local remote = rb.dirty and rb.draftTs and rec.ts ~= rb.draftTs
  local d = rb.draft
  local st = rec.d.st
  rb.editable = G.CanEdit(rb.rid) and (st == "draft" or st == "published")
  -- attendance correction mode (closed, RL / GM, 7 days)
  rb.attMode = st == "closed" and G.CanFixAttendance(rb.rid)
  if rb.attMode and rb.attRid ~= rb.rid then
    rb.attRid, rb.att = rb.rid, {}
    local known = R.attendanceList(ns.state, rb.rid)
    if #known == 0 then known = G.Seen(rb.rid) end
    for _, n in ipairs(known) do rb.att[n] = true end
  elseif not rb.attMode then rb.attRid, rb.att = nil, nil end
  if not rb.name:HasFocus() then rb.name:SetText(d.name or "") end
  rb.raidBtn:SetText(raidLabel(d.raid, d.size))
  if not rb.date:HasFocus() then rb.date:SetText(R.fmtWall(d.at)) end
  if not rb.tpl:HasFocus() then rb.tpl:SetText(d.tpl or R.defaultTpl(d.size)) end
  rb.weekly:SetChecked(d.wk and true or false)
  for _, c in ipairs({ rb.name, rb.raidBtn, rb.date, rb.tpl, rb.weekly }) do
    if c.SetEnabled then pcall(c.SetEnabled, c, rb.editable) end
  end
  local cov = R.coverage(d, G.roleOf)
  local tpl = R.parseTpl(d.tpl, d.size)
  local function part(role)
    local mm = tpl[role]
    local n = cov[role]
    local col = (n < mm[1] and "|cffff6040") or (n > mm[2] and "|cffff9933") or "|cff33dd33"
    return ("%s%s %d|r/%s"):format(col, R.ROLE_SHORT[role], n, mm[1] == mm[2] and mm[1] or (mm[1] .. "-" .. mm[2]))
  end
  rb.comp:SetText(("%d/%d   %s  %s  %s"):format(cov.filled, d.size, part("TANK"), part("HEALER"), part("DAMAGER")))
  local stText = L["RB_ST_" .. st] or st
  if R.attendanceState(ns.state, rb.rid) == "pending" then stText = L.RB_ST_closed_pending end
  rb.stBase = stText
  rb.state:SetText(stText .. (rb.dirty and ("  |cffff9933" .. (remote and L.RB_REMOTE or L.RB_UNSAVED) .. "|r") or ""))
  local ngroups = d.size / 5
  for g, box in ipairs(rb.groups) do
    box:SetShown(g <= ngroups)
    for i, s in ipairs(box.slots) do local slot = (g - 1) * 5 + i; fillSlot(s, slot, d.main[slot] or "") end
  end
  local bn = {}
  for _, n in ipairs(d.bench) do
    local a = R.rsvpOf(ns.state, rb.rid, n)
    bn[#bn + 1] = (a and (ANS_COLOR[a.v] or "") or "") .. short(n) .. (a and "|r" or "")
  end
  rb.bench:SetText(L.RB_BENCH .. " (" .. #d.bench .. "/" .. R.MAX_BENCH .. "): " .. (#bn > 0 and table.concat(bn, ", ") or "-"))
  local w = R.warnings(d, G.roleOf, G.classOf, G.Util())
  rb.warn:SetText(#w > 0 and (L.RB_WARN .. " " .. warnText(w)) or ("|cff33dd33" .. L.RB_OK .. "|r"))
  local c = R.rsvpCount(ns.state, rb.rid, G.roleOf)
  rb.rsvp:SetText(L.RB_RSVP_COUNT:format(c.yes, roleCounts(c.roles), c.maybe, c.no, c.bench, c.none))
  -- my answer row
  local me = ns.me()
  local a = R.rsvpOf(ns.state, rb.rid, me)
  local canAnswer = st == "published"
  rb.myLabel:SetShown(canAnswer)
  for v, b in pairs(rb.myAns) do b:SetShown(canAnswer); W.SetSelected(b, a ~= nil and a.v == v) end
  rb.comment:SetShown(canAnswer)
  if canAnswer and not rb.comment:HasFocus() then rb.comment:SetText(a and a.c or "") end
  -- add panel (editors only)
  rb.addPanel:SetShown(rb.editable)
  if rb.editable then
    rb.roleBtn:SetText(rb.role and R.ROLE_SHORT[rb.role] or L.RB_ROLE_ALL)
    rb.onlineChk:SetChecked(rb.online)
    rb.addGrid:SetItems(addItems())
  end
  -- bar
  local edit = G.CanEdit(rb.rid)
  rb.save:SetShown(rb.editable); rb.save:SetEnabled(rb.dirty)
  rb.close:SetShown(edit and st == "published")
  rb.cancel:SetShown(edit and (st == "draft" or st == "published"))
  rb.dup:SetShown(canLead)
  rb.export:Show()
  rb.primary:SetEnabled(true); W.Tooltip(rb.primary, nil)
  if edit and st == "draft" then rb.primary:SetText(L.RB_PUBLISH); rb.primary:Show()
  elseif edit and st == "published" then
    rb.primary:SetText(L.RB_INVITE); rb.primary:Show()
    -- like "Invitar al grupo": off in combat, the tooltip says why
    local fight = InCombatLockdown and InCombatLockdown() == true
    rb.primary:SetEnabled(not fight); W.Tooltip(rb.primary, fight and L.IN_COMBAT or nil)
  elseif rb.attMode then rb.primary:SetText(L.RB_SIGN_ATT); rb.primary:Show()
  else rb.primary:Hide() end
  -- the status never runs under the bar buttons (x >= 188)
  bar.status:SetWidth(170); if bar.status.SetWordWrap then bar.status:SetWordWrap(false) end
  bar.status:SetText(L.RB_DETAIL_STATUS:format(dateLabel(d.at), short(d.owner or "?")))
end, function()
  if not ns.rosterReady then return false end
  -- members see the tab once there is a roster for them; GM / officers / RL always
  if G.CanLead() then return true end
  for _, r in pairs(ns.state.rosters or {}) do if r.d.st == "published" then return true end end
  return false
end, { icon = ICONS .. "INV_Misc_Head_Dragon_01",
  beforeLeave = function(nextKey)
    if not (rb.dirty and rb.editable) then return false end
    W.Confirm(L.S_UNSAVED, function() rb.dirty = false; rb.draft = nil; UI.Select(nextKey, true) end, L.DISCARD, L.KEEP_EDITING)
    return true
  end })

-- the one red button: "Nueva banda" (list), "Publicar" (draft), "Invitar confirmados" (published)
function UI.RaidPrimary()
  if rb.view == "list" then
    if not G.CanLead() then return end
    local wall = G.WallNow()
    local y, m, d = R.fields(wall + 86400)
    local id = G.Create({ raid = "barrow", size = 10, name = L.RB_DEFAULT_NAME, at = R.civil(y, m, d, 20, 0) })
    if id then UI.OpenRoster(id) end
    return id
  end
  local rec = rb.rid and G.Get(rb.rid)
  if not rec then return end
  if rec.d.st == "draft" then
    local d = rb.draft or R.copy(rec.d)
    d.st = "published"
    local okS, why = G.Save(rb.rid, d)
    if okS then rb.dirty = false; rb.draft = nil; ns.Feedback(true, L.RB_FB_PUBLISHED)
    elseif why then d.st = "draft" end
  elseif rec.d.st == "published" then
    if rb.dirty and rb.draft then if G.Save(rb.rid, rb.draft) then rb.dirty = false end end
    G.Invite(rb.rid)   -- user click: the only place invites are sent from
  elseif rec.d.st == "closed" and rb.attMode and rb.att then
    local names = {}
    for n in pairs(rb.att) do names[#names + 1] = n end
    table.sort(names)
    local okA, whyA = G.SignAttendance(rb.rid, names)
    if okA then ns.Feedback(true, L.RB_FB_SIGNED:format(#names))   -- it was closed already
    elseif whyA == "empty" or #names == 0 then
      -- a refused signature is never silent
      ns.print(L.RB_ATT_EMPTY); if UI.Flash then UI.Flash(L.RB_ATT_EMPTY) end
    elseif whyA then ns.ShowError(whyA) end
  end
  UI.Select("raids")
end

function UI.OpenRoster(rid)
  rb.view, rb.rid, rb.draft, rb.dirty = "edit", rid, nil, false
  UI.Open("raids")
  UI.Select("raids")
end

-- badge on the tab: published raids where I am listed and have not answered
function UI.SetRaidBadge(n)
  local p = UI.panels.raids
  if not p or not p.tab then return end
  if not rb.badge then rb.badge = W.Badge(p.tab); rb.badge:SetPoint("TOPRIGHT", p.tab, "TOPRIGHT", -4, 2) end
  rb.badge:SetCount(n)
end

-- tab order: Bandas right after Ranking (UI/Hall.lua, loaded later, puts Salón de la fama after Bandas)
do
  local order = UI.order
  for i = #order, 1, -1 do if order[i] == "raids" then table.remove(order, i) end end
  local at = #order + 1
  for i, k in ipairs(order) do if k == "ranking" then at = i + 1 end end
  table.insert(order, at, "raids")
end
