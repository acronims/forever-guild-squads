-- Guild Squads (MIT) - UI/Panels.lua
-- Screens: Mi squad · Squads · Buscador · Mi perfil · Ajustes (GM) + Crear squad (no tab).
local _, ns = ...
local L, W, M, X, P, A, UI, Logo = ns.L, ns.W, ns.Model, ns.Match, ns.Permissions, ns.Actions, ns.UI, ns.Logo

local ICONS = "Interface\\Icons\\"
local CHECK = "Interface\\Buttons\\UI-CheckBox-Check"
local ROLES = M.ROLES
local num = W.num
local Pr = ns.Progress
local function settings() return M.settingsOf(ns.state) end
local function squadsOn() return settings().squadsEnabled end
local function err(why) if why then ns.ShowError(why) end end   -- never twice
local function inCombat() return InCombatLockdown and InCombatLockdown() == true end
local function profileOf(name) local p = ns.state.profiles[name]; return p and p.d or {} end
local function infoOf(name)
  local r, d = ns.roster(name) or {}, profileOf(name)
  return { name = name, class = r.class or d.class, level = r.level or d.level, online = r.online, zone = r.zone,
           role = d.role, role2 = d.role2, avail = d.avail, goals = d.goals or {}, seen = r.seen }
end
local function nameColored(name, class)
  local _, _, _, hex = W.ClassColor(class)
  return hex .. (ns.displayName and ns.displayName(name) or ns.shortName(name)) .. "|r"   -- with surname
end
-- ChatFrame_SendTell, then ChatFrameUtil.SendTell, then open the chat with "/w name "
local function whisper(name)
  local short = ns.shortName(name)
  if ChatFrame_SendTell and pcall(ChatFrame_SendTell, short) then return end
  if ChatFrameUtil and ChatFrameUtil.SendTell and pcall(ChatFrameUtil.SendTell, short) then return end
  if ChatFrame_OpenChat then pcall(ChatFrame_OpenChat, "/w " .. short .. " "); return end
  -- 16001 only has ChatFrameUtil.OpenChat
  if ChatFrameUtil and type(ChatFrameUtil.OpenChat) == "function" then pcall(ChatFrameUtil.OpenChat, "/w " .. short .. " ") end
end
local function inviteGroup(name)
  if inCombat() then ns.print(L.IN_COMBAT); return end
  if C_PartyInfo and C_PartyInfo.InviteUnit then pcall(C_PartyInfo.InviteUnit, name) end
end

local function squadCtx(id)
  local profiles, avails, levels = {}, {}, 0
  local mem = M.members(ns.state, id)
  local online = 0
  for _, n in ipairs(mem) do
    local i = infoOf(n)
    profiles[#profiles + 1] = i
    avails[#avails + 1] = i.avail
    levels = levels + (i.level or 0)
    if i.online then online = online + 1 end
  end
  local d = ns.state.squads[id].d
  local known = M.splitTags(d.tags)
  return { needs = X.roleNeeds(profiles), avail = X.availUnion(avails), level = #mem > 0 and math.floor(levels / #mem) or 0,
           goals = known, count = #mem, online = online > 0, onlineN = online, profiles = profiles, members = mem }
end
local function squadState(d, ctx)
  if d.approved == false then return "pending" end
  if ctx.count >= M.SQUAD_SIZE then return "full" end
  return d.open and "open" or "closed"
end
local STATE_COLOR = { open = { 0.15, 0.45, 0.15 }, closed = { 0.55, 0.12, 0.12 }, full = { 0.6, 0.42, 0.05 },
                      pending = { 0.12, 0.3, 0.6 } }
local function stateChip(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(74, 18)
  b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
  b.text = W.Label(b, "", "GameFontHighlightSmall"); b.text:SetPoint("CENTER")
  function b:SetState(s)
    local c = STATE_COLOR[s] or STATE_COLOR.closed
    self.bg:SetColorTexture(c[1], c[2], c[3], 0.9)
    self.text:SetText(L["STATE_" .. s:upper()])
  end
  return b
end
local function activeSquads()
  local out = {}
  for id, r in pairs(ns.state.squads) do if not r.d.disbanded then out[#out + 1] = id end end
  table.sort(out, function(a, b) return ns.state.squads[a].d.name:lower() < ns.state.squads[b].d.name:lower() end)
  return out
end
local function myInfo()
  local i = infoOf(ns.me())
  local d = A.MyProfile()
  i.role, i.role2, i.avail, i.goals = d.role, d.role2, d.avail, d.goals or {}
  i.level = i.level or (UnitLevel and UnitLevel("player"))
  return i
end
local function roleList(needs)
  local out = {}
  for _, r in ipairs(ROLES) do for _ = 1, (needs[r] or 0) do out[#out + 1] = r end end
  return out
end
-- "visto por última vez" from the guild roster (omitted when the client does not expose it)
local function seenText(i)
  if i.online or type(i.seen) ~= "number" then return nil end
  local d = math.floor(i.seen)
  if d < 1 then return L.SEEN_HOURS:format(math.max(1, math.floor(i.seen * 24 + 0.5))) end
  return L.SEEN_DAYS:format(d)
end
UI.seenText = seenText
local function memberTooltip(name)
  return function(_, tt)
    local i = infoOf(name)
    local r, g, b = W.ClassColor(i.class)
    tt:SetText(ns.shortName(name), r, g, b)
    tt:AddLine(("%s %s · %s"):format(i.class and W.ClassName(i.class) or "?", tostring(i.level or "?"), tostring(i.zone or "")), 1, 1, 1)
    if i.role then tt:AddLine(W.Icon(W.ROLE_ICON[i.role]) .. " " .. L["ROLE_" .. i.role] .. " (" .. L.ROLE_MAIN .. ")", 1, 1, 1) end
    if i.role2 then tt:AddLine(W.Icon(W.ROLE_ICON[i.role2]) .. " " .. L["ROLE_" .. i.role2] .. " (" .. L.ROLE_SEC .. ")", 1, 1, 1) end
    local a = i.avail or "00000000"
    for half = 0, 1 do
      local parts = {}
      for s = 1, 4 do if a:sub(half * 4 + s, half * 4 + s) == "1" then parts[#parts + 1] = L["SLOT_" .. s] end end
      if #parts > 0 then tt:AddLine((half == 0 and L.WEEKDAY or L.WEEKEND) .. ": " .. table.concat(parts, ", "), 0.7, 0.7, 0.7) end
    end
    local seen = seenText(i)
    if seen then tt:AddLine(seen, 0.7, 0.7, 0.7) end
    tt:AddLine(L.RIGHTCLICK_TIP, 0.5, 0.5, 0.5)
  end
end

UI.filters = { withRoom = false }

-------------------------------------------------------------------------------
-- Mi squad
local sq = {}
-- rejecting is a synced Reject record (A.Reject); nothing is hidden locally any more

local function memberMenu(id, name, captain)
  local items = { { text = ns.shortName(name), title = true },
    { text = L.WHISPER, func = function() whisper(name) end },
    { text = L.INVITE_PARTY, func = function() inviteGroup(name) end } }
  if captain and name ~= ns.me() then
    -- actions that take rights away are confirmed
    items[#items + 1] = { text = L.MAKE_CAPTAIN, danger = true, confirm = L.CONFIRM_TRANSFER:format(ns.shortName(name)),
                          func = function() local _, why = A.Transfer(id, name); err(why) end }
    items[#items + 1] = { text = L.MOVE_BENCH, confirm = L.CONFIRM_BENCH:format(ns.shortName(name)),
                          func = function() local _, why = A.MoveToBench(id, name); err(why) end }
    items[#items + 1] = { text = L.KICK, danger = true, confirm = L.CONFIRM_KICK:format(ns.shortName(name)),
                          func = function() local _, why = A.Kick(id, name); err(why) end }
  end
  items[#items + 1] = { text = CANCEL or L.CANCEL }
  return items
end

local function makeSlot(parent)
  local c = W.Card(parent)
  c:SetSize(128, 148)
  c.dot = c:CreateTexture(nil, "OVERLAY"); c.dot:SetSize(8, 8); c.dot:SetPoint("TOPLEFT", 6, -6)
  c.crown = c:CreateTexture(nil, "OVERLAY"); c.crown:SetSize(14, 14); c.crown:SetPoint("TOPRIGHT", -6, -4)
  c.crown:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
  c.class = c:CreateTexture(nil, "ARTWORK"); c.class:SetSize(44, 44); c.class:SetPoint("TOP", 0, -14)
  c.role = c:CreateTexture(nil, "OVERLAY"); c.role:SetSize(22, 22); c.role:SetPoint("CENTER", c.class, "BOTTOMRIGHT", 0, 2)
  c.name = W.Label(c, "", "GameFontNormal"); c.name:SetPoint("TOP", 0, -66); c.name:SetJustifyH("CENTER")
  c.line2 = W.Label(c, ""); c.line2:SetPoint("TOP", 0, -84); c.line2:SetTextColor(0.7, 0.7, 0.7)
  c.line3 = W.Label(c, ""); c.line3:SetPoint("TOP", 0, -100)
  c.plus = W.Label(c, "+", "GameFontNormalHuge"); c.plus:SetPoint("TOP", 0, -24)
  return c
end

local function fillSlot(c, id, name, d, captain, needs)
  if name then
    local i = infoOf(name)
    c.plus:Hide(); c.class:Show(); c.role:Show(); c.dot:Show()
    c.role:ClearAllPoints(); c.role:SetPoint("CENTER", c.class, "BOTTOMRIGHT", 0, 2)
    W.SetClass(c.class, i.class); c.class:SetDesaturated(not i.online); c.class:SetAlpha(i.online and 1 or 0.6)
    if i.role then W.SetRole(c.role, i.role) else c.role:Hide() end
    if i.online then c.dot:SetTexture("Interface\\FriendsFrame\\StatusIcon-Online")
    else c.dot:SetTexture("Interface\\FriendsFrame\\StatusIcon-Offline") end
    c.crown:SetShown(name == d.captain)
    c.name:SetText(nameColored(name, i.class))
    c.line2:SetText(L.LEVEL_ROLE:format(tostring(i.level or "?"), i.role and L["ROLE_" .. i.role] or "-"))
    c.line3:SetText(i.online and (i.zone or "") or (seenText(i) or L.OFFLINE))
    c.line3:SetTextColor(i.online and 1 or 0.5, i.online and 1 or 0.5, i.online and 1 or 0.5)
    if name == d.captain then c.border.set(0.8, 0.65, 0.2, 1) else c.border.set(0.3, 0.3, 0.3, 1) end
    W.Tooltip(c, memberTooltip(name))
    c:SetScript("OnClick", function(_, button)
      if button == "RightButton" then W.Menu(c, memberMenu(id, name, captain)) end
    end)
  else
    c.plus:Show(); c.class:Hide(); c.crown:Hide(); c.dot:Hide(); c.role:Hide()
    local missing = roleList(needs)[1]
    c.name:SetText(L.SLOT_FREE)
    c.line2:SetText(missing and L.SLOT_MISSING:format(W.Icon(W.ROLE_ICON[missing], 12) .. " " .. L["ROLE_" .. missing]) or "")
    c.line3:SetText(captain and L.SLOT_CLICK or ""); c.line3:SetTextColor(0.5, 0.5, 0.5)
    c.border.set(0.5, 0.45, 0.3, 0.5)
    W.Tooltip(c, nil)
    c:SetScript("OnClick", function(_, button)
      if not captain or button ~= "LeftButton" then return end
      -- suggestions: online guild members without a squad who cover the missing role
      local sug = {}
      for full, r in pairs(ns.rosterList()) do
        if r.online and full ~= ns.me() and not M.squadOf(ns.state, full) and #sug < 4 then
          local pd = profileOf(full)
          if not missing or pd.role == missing or pd.role2 == missing then sug[#sug + 1] = ns.shortName(full) end
        end
      end
      local text = L.PROMPT_INVITE .. (#sug > 0 and ("\n" .. L.SUGGEST .. ": " .. table.concat(sug, ", ")) or "")
      W.Prompt(text, function(n) if n and n ~= "" then local _, why = A.AddMember(id, n); err(why) end end)
    end)
  end
end

local function smallRow(parent, w)
  local r = W.Card(parent); r:SetSize(w, 28)
  r.dot = r:CreateTexture(nil, "OVERLAY"); r.dot:SetSize(8, 8); r.dot:SetPoint("LEFT", 6, 0)
  r.class = r:CreateTexture(nil, "ARTWORK"); r.class:SetSize(20, 20); r.class:SetPoint("LEFT", 18, 0)
  r.name = W.Label(r, "", "GameFontNormalSmall"); r.name:SetPoint("LEFT", 42, 0)
  r.role = r:CreateTexture(nil, "ARTWORK"); r.role:SetSize(16, 16); r.role:SetPoint("LEFT", 150, 0)
  r.right = W.Label(r, ""); r.right:SetPoint("RIGHT", -8, 0); r.right:SetTextColor(0.6, 0.6, 0.6)
  return r
end

UI.Register("mysquad", L.TAB_MYSQUAD, function(f, bar)
  -- empty state
  local e = CreateFrame("Frame", nil, f); e:SetAllPoints(); sq.empty = e
  sq.eLogo = W.Logo(e, 72); sq.eLogo:SetPoint("TOP", 0, -40); sq.eLogo:SetEmpty()
  local t = W.Label(e, L.NO_SQUAD, "GameFontNormalLarge"); t:SetPoint("TOP", sq.eLogo, "BOTTOM", 0, -12)
  local s = W.Label(e, L.NO_SQUAD_SUB); s:SetPoint("TOP", t, "BOTTOM", 0, -6)
  sq.seeOpen = W.Link(e, L.SEE_OPEN, function() UI.filters.withRoom = true; UI.Select("squads") end)
  sq.seeOpen:SetPoint("TOP", s, "BOTTOM", 0, -10)
  sq.invTitle = W.Label(e, L.INVITED_YOU, "GameFontNormal"); sq.invTitle:SetPoint("TOPLEFT", 180, -230)
  sq.inv = {}
  for i = 1, 3 do
    local c = W.Card(e); c:SetSize(335, 56); c:SetPoint("TOPLEFT", 180, -250 - (i - 1) * 60)
    c.logo = W.Logo(c, 40); c.logo:SetPoint("LEFT", 8, 0)
    c.name = W.Label(c, "", "GameFontNormal"); c.name:SetPoint("TOPLEFT", 56, -10)
    c.sub = W.Label(c, ""); c.sub:SetPoint("TOPLEFT", 56, -28); c.sub:SetTextColor(0.7, 0.7, 0.7)
    c.yes = W.IconButton(c, 26, "Interface\\RaidFrame\\ReadyCheck-Ready", L.ACCEPT); c.yes:SetPoint("RIGHT", -38, 0)
    c.no = W.IconButton(c, 26, "Interface\\RaidFrame\\ReadyCheck-NotReady", L.REJECT); c.no:SetPoint("RIGHT", -8, 0)
    sq.inv[i] = c
  end
  -- squad view
  local m = CreateFrame("Frame", nil, f); m:SetAllPoints(); sq.manage = m
  -- the header starts right of the window portrait (UI.SAFE_X)
  local hx = UI.SAFE_X
  sq.logo = W.Logo(m, 72); sq.logo:SetPoint("TOPLEFT", hx, -10)
  sq.title = W.Label(m, "", "GameFontNormalHuge"); sq.title:SetPoint("TOPLEFT", hx + 84, -14)
  sq.inactive = W.Label(m, L.INACTIVE, "GameFontNormalSmall"); sq.inactive:SetPoint("LEFT", sq.title, "RIGHT", 8, 0)
  sq.inactive:SetTextColor(0.6, 0.6, 0.6)
  sq.motto = W.Label(m, "", "GameFontDisableSmall"); sq.motto:SetPoint("TOPLEFT", hx + 84, -42)
  sq.motto:SetWidth(300); if sq.motto.SetWordWrap then sq.motto:SetWordWrap(false) end
  sq.chips = W.ChipRow(m, 6); sq.chips:SetPoint("TOPLEFT", m, "TOPLEFT", hx + 84, -62)
  sq.pending = W.Label(m, L.PENDING_BAND, "GameFontNormal"); sq.pending:SetPoint("TOPLEFT", 300, -86)
  sq.pending:SetTextColor(1, 0.82, 0)
  sq.gear = W.IconButton(m, 26, "Interface\\Icons\\INV_Misc_Gear_01", L.SQUAD_OPTIONS, nil, function(self)
    local id = A.MySquadId(); if not id then return end
    local d = ns.state.squads[id].d
    local cap = d.captain == ns.me()
    local items = { { text = d.name, title = true } }
    if cap then
      items[#items + 1] = { text = L.EDIT_SQUAD, func = function() UI.OpenCreate("edit") end }
      items[#items + 1] = { text = L.EDIT_LOGO, func = function() UI.OpenCreate("logo") end }
      items[#items + 1] = { text = L.DISBAND, danger = true, confirm = L.CONFIRM_DISBAND,
                            func = function() local _, why = A.Disband(id); err(why) end }
    else
      items[#items + 1] = { text = L.LEAVE, danger = true, confirm = L.CONFIRM_LEAVE,
                            func = function() local _, why = A.Leave(); err(why) end }
    end
    items[#items + 1] = { text = CANCEL or L.CANCEL }
    W.Menu(self, items)
  end)
  sq.gear:SetPoint("TOPRIGHT", -12, -12)
  sq.call = W.IconButton(m, 26, ICONS .. "Ability_Warrior_BattleShout", L.CALL_SQUAD, L.CALL_TIP, function()
    A.CallSquad()
    UI.Select("mysquad")
  end)
  sq.call:SetPoint("RIGHT", sq.gear, "LEFT", -4, 0)
  sq.state = stateChip(m); sq.state:SetPoint("RIGHT", sq.call, "LEFT", -6, 0)
  sq.state:SetScript("OnClick", function()
    local id = A.MySquadId(); if not id then return end
    local d = ns.state.squads[id].d
    if d.captain ~= ns.me() then return end
    local v = not d.open
    local _, why = A.EditSquad(id, function(x) x.open = v end); err(why)
  end)
  sq.ach = UI.AchStrip(m, 10); sq.ach:SetPoint("TOPRIGHT", -12, -44) -- achievements strip
  sq.members = W.Label(m, "", "GameFontNormal"); sq.members:SetPoint("TOPLEFT", 12, -104)
  local hint = W.Label(m, L.HINT_RIGHTCLICK); hint:SetPoint("TOPRIGHT", -12, -104); hint:SetTextColor(0.5, 0.5, 0.5)
  sq.slots = {}
  for i = 1, 5 do
    local c = makeSlot(m); c:SetPoint("TOPLEFT", 10 + (i - 1) * 136, -124)
    sq.slots[i] = c
  end
  sq.benchT = W.Label(m, "", "GameFontNormal"); sq.benchT:SetPoint("TOPLEFT", 12, -280)
  sq.bench = {}
  for i = 1, 2 do local r = smallRow(m, 330); r:SetPoint("TOPLEFT", 10, -298 - (i - 1) * 28); sq.bench[i] = r end
  sq.reqT = W.Label(m, L.REQUESTS, "GameFontNormal"); sq.reqT:SetPoint("TOPLEFT", 352, -280)
  sq.reqBadge = W.Badge(m); sq.reqBadge:SetPoint("LEFT", sq.reqT, "RIGHT", 4, 0)
  sq.req = {}
  for i = 1, 3 do
    local r = smallRow(m, 330); r:SetPoint("TOPLEFT", 350, -298 - (i - 1) * 28)
    -- the chip ends 6 px before the accept button (row 330, button at RIGHT -30, 22 px wide)
    r.reason = W.ReasonChip(r, 330 - 30 - 22 - 6 - 172); r.reason:SetPoint("LEFT", 172, 0)
    r.yes = W.IconButton(r, 22, "Interface\\RaidFrame\\ReadyCheck-Ready", L.ACCEPT); r.yes:SetPoint("RIGHT", -30, 0)
    r.no = W.IconButton(r, 22, "Interface\\RaidFrame\\ReadyCheck-NotReady", L.REJECT); r.no:SetPoint("RIGHT", -4, 0)
    sq.req[i] = r
  end
  -- "Este wipe": 5 categories + total (points/cap, position in the guild; capped = highlighted, weight 0 = dimmed)
  sq.wipe = UI.WipePanel and UI.WipePanel(m)
  if sq.wipe then sq.wipe:SetPoint("TOPLEFT", m, "TOPLEFT", 8, -386) end
  -- bottom bar
  sq.primary = W.Primary(bar, L.INVITE_GROUP, function()
    local id = A.MySquadId()
    if id then A.InviteSquadToGroup(id) else UI.OpenCreate("new") end
  end)
end, function(f, bar)
  local id = A.MySquadId()
  sq.empty:SetShown(not id); sq.manage:SetShown(id and true or false)
  if not id then
    sq.primary:SetText(L.CREATE_SQUAD)
    local can, whyC = P.canCreateSquad(ns.roster, ns.me(), settings())
    sq.primary:SetEnabled(can and true or false)
    -- the real cause: no guild, squads disabled by the GM, or the rank
    local cause
    if not can then
      if not (IsInGuild and IsInGuild()) or not ns.gdb then cause = L.NO_GUILD
      elseif whyC == "disabled" then cause = L.SQUADS_DISABLED
      else cause = ns.ErrText(whyC or "rank") end
    end
    W.Tooltip(sq.primary, cause)
    bar.status:SetText(cause and (cause == L.NO_GUILD or cause == L.SQUADS_DISABLED) and cause or "")
    local inv = {}
    for _, sid in ipairs(M.invites(ns.state, ns.me())) do inv[#inv + 1] = sid end
    sq.invTitle:SetShown(#inv > 0)
    for i, c in ipairs(sq.inv) do
      local sid = inv[i]
      if sid then
        local d = ns.state.squads[sid].d
        c.logo:SetLogo(d.icon, d.color, d.border)
        c.name:SetText(M.displayName(ns.state, sid) or d.name); c.sub:SetText(L.CAPTAIN .. ": " .. ns.shortName(d.captain))
        c.yes:SetScript("OnClick", function() local _, why = A.RequestJoin(sid); err(why) end)
        c.no:SetScript("OnClick", function() local _, why = A.Reject(sid, ns.me(), "inv"); err(why); UI.Select("mysquad") end)
        c:Show()
      else c:Hide() end
    end
    return
  end
  local d = ns.state.squads[id].d
  local ctx = squadCtx(id)
  local captain = d.captain == ns.me()
  sq.logo:SetLogo(d.icon, d.color, d.border)
  sq.title:SetText(M.displayName(ns.state, id) or d.name)
  sq.ach:SetSquad(id)
  sq.inactive:SetShown(A.IsInactive(id))
  if sq.wipe then sq.wipe:SetSquad(id) end
  sq.motto:SetText(d.motto and d.motto ~= "" and ("«" .. d.motto .. "»") or "")
  local known, legacy = M.splitTags(d.tags)
  for _, t in ipairs(legacy) do known[#known + 1] = t end
  sq.chips:SetKeys(known)
  sq.pending:SetShown(d.approved == false)
  sq.state:SetState(squadState(d, ctx))
  W.Tooltip(sq.state, captain and L.TOGGLE_OPEN or nil)
  local okCall, left = A.CallReady()
  sq.call:SetUsable(okCall and not inCombat())
  sq.call.tipText = okCall and L.CALL_TIP or L.CALL_CD:format(ns.Call.fmtLeft(left))
  sq.members:SetText(L.MEMBERS_N:format(ctx.count))
  local slotNames = {}
  for _, n in ipairs(ctx.members) do slotNames[#slotNames + 1] = n end
  for i = 1, 5 do fillSlot(sq.slots[i], id, slotNames[i], d, captain, ctx.needs) end
  local bench = M.benchMembers(ns.state, id)
  sq.benchT:SetText(L.BENCH_N:format(#bench, settings().bench or 0))
  sq.benchT:SetShown((settings().bench or 0) > 0)
  for i, r in ipairs(sq.bench) do
    local n = bench[i]
    if n then
      local inf = infoOf(n)
      W.SetClass(r.class, inf.class)
      r.dot:SetTexture(inf.online and "Interface\\FriendsFrame\\StatusIcon-Online" or "Interface\\FriendsFrame\\StatusIcon-Offline")
      r.name:SetText(nameColored(n, inf.class) .. "  |cffaaaaaa" .. L.LV_SHORT:format(tostring(inf.level or "?")) .. "|r")
      if inf.role then W.SetRole(r.role, inf.role); r.role:Show() else r.role:Hide() end
      r.right:SetText(inf.zone or "")
      W.Tooltip(r, memberTooltip(n))
      r:SetScript("OnClick", function(_, b) if b == "RightButton" then W.Menu(r, memberMenu(id, n, captain)) end end)
      r:Show()
    else r:Hide() end
  end
  local reqs = {}
  if captain then for _, n in ipairs(M.requests(ns.state, id)) do reqs[#reqs + 1] = n end end
  sq.reqT:SetShown(captain); sq.reqBadge:SetCount(#reqs)
  for i, r in ipairs(sq.req) do
    local n = reqs[i]
    if n then
      local inf = infoOf(n)
      W.SetClass(r.class, inf.class); r.dot:Hide()
      r.name:SetText(nameColored(n, inf.class) .. "  |cffaaaaaa" .. L.LV_SHORT:format(tostring(inf.level or "?")) .. "|r")
      if inf.role then W.SetRole(r.role, inf.role); r.role:Show() else r.role:Hide() end
      local _, reasons = X.score(inf, ctx)
      if reasons[1] then r.reason:SetReason(reasons[1]); r.reason:Show() else r.reason:Hide() end
      r.right:SetText("")
      r.yes:SetScript("OnClick", function() local _, why = A.AddMember(id, n); err(why) end)
      r.no:SetScript("OnClick", function() local _, why = A.Reject(id, n, "req"); err(why); UI.Select("mysquad") end)
      W.Tooltip(r, memberTooltip(n))
      r:Show()
    else r:Hide() end
  end
  -- bottom bar
  local myZone = GetRealZoneText and GetRealZoneText()
  local inZone, others = 0, 0
  for _, n in ipairs(ctx.members) do
    local inf = infoOf(n)
    if n ~= ns.me() and inf.online then others = others + 1; if myZone and inf.zone == myZone then inZone = inZone + 1 end end
  end
  bar.status:SetText(L.ONLINE_SUMMARY:format(ctx.onlineN, ctx.count, inZone))
  sq.primary:SetText(L.INVITE_GROUP)
  sq.primary:SetEnabled(others > 0 and not inCombat())
  -- disabled because nobody else is online -> say so
  if inCombat() then W.Tooltip(sq.primary, L.IN_COMBAT)
  elseif others == 0 then W.Tooltip(sq.primary, L.WHY_DISABLED, L.WHY_NO_ONE_ONLINE)
  else W.Tooltip(sq.primary, nil) end
end, squadsOn, { icon = ICONS .. "INV_Banner_02" })

function UI.MySquadState() return sq end

-------------------------------------------------------------------------------
-- Squads (directory)
local dir = { tags = {} }
local function squadMenu(id, d)
  local me = ns.me()
  local mine = A.MySquadId()
  local requested = profileOf(me).squad == id and not mine
  local items = { { text = d.name, title = true } }
  if not mine and d.open and d.approved ~= false then
    items[#items + 1] = requested and { text = L.CANCEL_REQUEST, func = function() local _, why = A.SaveProfile({ squad = "" }); err(why) end }
                                  or { text = L.REQUEST_JOIN, func = function() local _, why = A.RequestJoin(id); err(why) end }
  end
  items[#items + 1] = { text = L.WHISPER_CAPTAIN, func = function() whisper(d.captain) end }
  if P.isOfficer(ns.roster, me, settings()) then
    if d.approved == false then items[#items + 1] = { text = L.APPROVE, func = function() local _, why = A.Approve(id); err(why) end } end
    items[#items + 1] = { text = L.HIDE_SQUAD, danger = true, confirm = L.CONFIRM_HIDE,
                          func = function() local _, why = A.Disband(id); err(why) end }
  end
  items[#items + 1] = { text = CANCEL or L.CANCEL }
  return items
end

-- dimming of a squad card: inactive 0.5, full 0.6, both -> the lowest
function UI.SquadCardAlpha(inactive, state)
  return math.min(inactive and 0.5 or 1, state == "full" and 0.6 or 1)
end

local function makeSquadCard(parent)
  local c = W.Card(parent)
  c.logo = W.Logo(c, 52); c.logo:SetPoint("TOPLEFT", 8, -8)
  c.name = W.Label(c, "", "GameFontNormal"); c.name:SetPoint("TOPLEFT", 68, -10); c.name:SetWidth(210)
  if c.name.SetWordWrap then c.name:SetWordWrap(false) end
  c.motto = W.Label(c, "", "GameFontDisableSmall"); c.motto:SetPoint("TOPLEFT", 68, -26); c.motto:SetWidth(210)
  c.fit = W.FitBadge(c); c.fit:SetPoint("TOPRIGHT", -6, -6)
  c.chips = W.ChipRow(c, 4); c.chips:SetPoint("TOPLEFT", c, "TOPLEFT", 68, -44)
  c.roles = {}
  for i = 1, 5 do
    local t = c:CreateTexture(nil, "ARTWORK"); t:SetSize(18, 18); t:SetPoint("BOTTOMLEFT", 8 + (i - 1) * 20, 10)
    c.roles[i] = t
  end
  c.count = W.Label(c, ""); c.count:SetPoint("BOTTOMLEFT", 112, 13)
  c.captain = W.Label(c, ""); c.captain:SetPoint("BOTTOMLEFT", 150, 13)
  c.state = stateChip(c); c.state:SetPoint("BOTTOMRIGHT", -8, 8); c.state:EnableMouse(false)
  -- grey "Inactivo · N d" chip instead of 10 px grey text
  c.inactive = CreateFrame("Frame", nil, c); c.inactive:SetSize(90, 16)
  c.inactive:SetPoint("BOTTOMRIGHT", c.state, "TOPRIGHT", 0, 4)
  c.inactive.bg = c.inactive:CreateTexture(nil, "BACKGROUND"); c.inactive.bg:SetAllPoints()
  c.inactive.bg:SetColorTexture(0.35, 0.35, 0.35, 1)
  c.inactive.text = W.Label(c.inactive, L.INACTIVE, "GameFontHighlightSmall"); c.inactive.text:SetPoint("CENTER", 0, 0)
  return c
end

local function fillSquadCard(c, item)
  local id, d, ctx = item.id, item.d, item.ctx
  c.logo:SetLogo(d.icon, d.color, d.border)
  c.name:SetText(M.displayName(ns.state, id) or d.name)
  c.motto:SetText(d.motto or "")
  if c.fit then c.fit:SetFit(item.score, item.reasons) end
  local known, legacy = M.splitTags(d.tags)
  for _, t in ipairs(legacy) do known[#known + 1] = t end
  c.chips:SetKeys(known)
  local filled = {}
  for _, p in ipairs(ctx.profiles) do filled[#filled + 1] = p.role or "DAMAGER" end
  local missing = roleList(ctx.needs)
  for i = 1, 5 do
    local t = c.roles[i]
    local r = filled[i] or missing[i - #filled] or "DAMAGER"
    W.SetRole(t, r); W.Dim(t, filled[i] == nil)
  end
  c.count:SetText(("%d/%d"):format(ctx.count, M.SQUAD_SIZE))
  local ci = infoOf(d.captain)
  c.captain:SetText(W.Icon("Interface\\GroupFrame\\UI-Group-LeaderIcon", 12) .. " " .. nameColored(d.captain, ci.class))
  local st = squadState(d, ctx)
  c.state:SetState(st)
  c.inactive:SetShown(item.inactive and true or false)
  -- an inactive squad also loses the colour of its logo (alpha alone was not enough)
  if c.logo and c.logo.icon and c.logo.icon.SetDesaturated then pcall(c.logo.icon.SetDesaturated, c.logo.icon, item.inactive and true or false) end
  if item.inactive then
    local days = tonumber(item.inactiveDays)
    c.inactive.text:SetText(days and L.INACTIVE_DAYS_CHIP:format(math.floor(days)) or L.INACTIVE)
    c.inactive:SetWidth(math.max(60, (tonumber(c.inactive.text:GetStringWidth()) or 60) + 12))
  end
  c:SetAlpha(UI.SquadCardAlpha(item.inactive, st)) -- inactive and full combine (the second call overwrote the first)
  if dir.selected == id then c.border.set(1, 0.82, 0, 1) else c.border.set(0.3, 0.3, 0.3, 1) end
  W.Tooltip(c, function(_, tt)
    tt:SetText(d.name, 1, 0.82, 0)
    tt:AddLine(("%s · %d/5 · %s %d"):format(ns.shortName(d.captain), ctx.count, L.LV_LABEL, ctx.level), 1, 1, 1)
    local miss = {}
    for _, r in ipairs(missing) do miss[#miss + 1] = W.Icon(W.ROLE_ICON[r]) end
    if #miss > 0 then tt:AddLine(L.MISSING .. ": " .. table.concat(miss, " "), 1, 1, 1) end
    for _, r in ipairs(item.reasons or {}) do tt:AddLine(X.reasonText({ r }, L), 0.4, 0.9, 0.4) end
  end)
  c:SetScript("OnClick", function(_, button)
    if button == "RightButton" then W.Menu(c, squadMenu(id, d)); return end
    dir.selected = id; UI.Select(UI.Current())
  end)
  c:SetScript("OnDoubleClick", function()
    if not A.MySquadId() and st == "open" then local _, why = A.RequestJoin(id); err(why) end
  end)
end

-- shared by Squads and the finder's squad mode
local function squadItems(filter)
  local me = myInfo()
  local items = {}
  for _, id in ipairs(activeSquads()) do
    local d = ns.state.squads[id].d
    local ctx = squadCtx(id)
    if filter(id, d, ctx) then
      local score, reasons = X.score(me, ctx)
      items[#items + 1] = { id = id, d = d, ctx = ctx, score = score, reasons = reasons }
    end
  end
  for _, it in ipairs(items) do
    it.inactive = A.IsInactive(it.id)
    if it.inactive and ns.lastSeenDays then   -- days since the most recent member was seen
      local best
      for _, n in ipairs(M.members(ns.state, it.id) or {}) do
        local okD, dd = pcall(ns.lastSeenDays, n)
        if okD and type(dd) == "number" and (not best or dd < best) then best = dd end
      end
      it.inactiveDays = best
    end
  end
  -- inactive squads go last
  table.sort(items, function(a, b)
    if a.inactive ~= b.inactive then return not a.inactive end
    if a.score ~= b.score then return a.score > b.score end
    return a.d.name < b.d.name
  end)
  return items
end

UI.Register("squads", L.TAB_SQUADS, function(f, bar)
  dir.search = W.Edit(f, 130, 24, true); dir.search:SetPoint("TOPLEFT", UI.SAFE_X, -8)
  local onText = function() if dir.ready then UI.Select("squads") end end
  if dir.search.HookScript then dir.search:HookScript("OnTextChanged", onText) else dir.search:SetScript("OnTextChanged", onText) end
  dir.chips = {}
  local prev = dir.search
  for i, g in ipairs(M.GOALS) do
    local c = W.Chip(f, g, function(self, on) dir.tags[self.key] = on or nil; UI.Select("squads") end)
    c:SetOn(false)
    c:SetPoint("LEFT", prev, "RIGHT", i == 1 and 10 or 4, 0)
    dir.chips[i] = c; prev = c
  end
  dir.room = W.Check(f, L.WITH_ROOM, function(self) UI.filters.withRoom = self:GetChecked() and true or false; UI.Select("squads") end)
  dir.room:SetPoint("TOPRIGHT", -130, -30)
  dir.sub = W.Label(f, ""); dir.sub:SetPoint("TOPLEFT", 14, -36); dir.sub:SetTextColor(0.6, 0.6, 0.6)
  local area = CreateFrame("Frame", nil, f); area:SetPoint("TOPLEFT", 6, -54); area:SetPoint("BOTTOMRIGHT", -6, 4)
  dir.grid = W.Grid(area, 2, 3, 335, 112, 8, 8, makeSquadCard, fillSquadCard)
  dir.empty = W.Label(f, "", "GameFontNormal"); dir.empty:SetPoint("CENTER", 0, 20)
  dir.clear = W.Link(f, L.CLEAR_FILTERS, function()
    dir.tags = {}; for _, c in ipairs(dir.chips) do c:SetOn(false) end
    UI.filters.withRoom = false; dir.search:SetText(""); UI.Select("squads")
  end)
  dir.clear:SetPoint("TOP", dir.empty, "BOTTOM", 0, -8)
  dir.mine = W.Link(bar, L.CREATE_MINE, function() UI.OpenCreate("new") end); dir.mine:SetPoint("LEFT", 14, 2)
  dir.primary = W.Primary(bar, L.REQUEST_JOIN, function()
    local id = dir.selected; if not id or not ns.state.squads[id] then return end
    local d = ns.state.squads[id].d
    if d.approved == false and P.isOfficer(ns.roster, ns.me(), settings()) then local _, why = A.Approve(id); err(why)
    elseif profileOf(ns.me()).squad == id then local _, why = A.SaveProfile({ squad = "" }); err(why)
    else local _, why = A.RequestJoin(id); err(why) end
  end)
  dir.ready = true
end, function(f, bar)
  dir.room:SetChecked(UI.filters.withRoom)
  local q = (dir.search:GetText() or ""):lower()
  local isMod = P.isOfficer(ns.roster, ns.me(), settings())
  local total = 0
  local items = squadItems(function(id, d, ctx)
    if d.approved == false and not isMod and d.captain ~= ns.me() then return false end
    total = total + 1
    if q ~= "" and not (d.name:lower():find(q, 1, true) or (d.motto or ""):lower():find(q, 1, true)) then return false end
    if UI.filters.withRoom and (squadState(d, ctx) ~= "open") then return false end
    if next(dir.tags) then
      local hit = false
      for _, t in ipairs(d.tags or {}) do if dir.tags[t] then hit = true end end
      if not hit then return false end
    end
    return true
  end)
  dir.sub:SetText(L.SORTED_FIT:format(total))
  dir.grid:SetItems(items)
  local filtered = q ~= "" or UI.filters.withRoom or next(dir.tags) ~= nil
  dir.empty:SetShown(#items == 0)
  dir.empty:SetText(total == 0 and L.EMPTY_SQUADS or L.EMPTY_TAGS)
  dir.clear:SetShown(#items == 0 and filtered)
  local mine = A.MySquadId()
  dir.mine:SetShown(not mine)
  local sel = dir.selected and ns.state.squads[dir.selected]
  if total == 0 and not mine then
    dir.primary:SetText(L.CREATE_SQUAD); dir.primary:SetEnabled(true)
    dir.primary:SetScript("OnClick", function() UI.OpenCreate("new") end)
    W.Tooltip(dir.primary, nil)   -- no stale "why is it disabled" tooltip
    return
  end
  dir.primary:SetScript("OnClick", nil)
  local d = sel and sel.d
  local text, enabled = L.REQUEST_JOIN, false
  local why = L.WHY_SELECT_SQUAD          -- a disabled main button says why
  if d then
    local ctx = squadCtx(dir.selected)
    if d.approved == false and isMod then text, enabled = L.APPROVE, true
    elseif profileOf(ns.me()).squad == dir.selected and not mine then text, enabled = L.CANCEL_REQUEST, true
    else
      enabled = not mine and squadState(d, ctx) == "open"
      if mine then why = L.WHY_HAVE_SQUAD:format(tostring((ns.state.squads[mine] and ns.state.squads[mine].d.name) or mine))
      else why = L.WHY_NOT_OPEN end
    end
  end
  dir.primary:SetText(text); dir.primary:SetEnabled(enabled)
  W.Tooltip(dir.primary, (not enabled) and L.WHY_DISABLED or nil, (not enabled) and why or nil)
  dir.primary:SetScript("OnClick", function()
    local id = dir.selected; if not id or not ns.state.squads[id] then return end
    local sd = ns.state.squads[id].d
    if sd.approved == false and isMod then local _, why = A.Approve(id); err(why)
    elseif profileOf(ns.me()).squad == id then local _, why = A.SaveProfile({ squad = "" }); err(why)
    else local _, why = A.RequestJoin(id); err(why) end
  end)
end, squadsOn, { icon = ICONS .. "INV_Misc_GroupNeedMore" })

-------------------------------------------------------------------------------
-- Buscador
local fd = { role = {}, class = {}, goal = {} }
function UI.FinderState() return fd end
local function forClasses()
  local list = {}
  local src = CLASS_SORT_ORDER or { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
  for _, c in ipairs(src) do
    local keep = true
    if C_CreatureInfo and C_CreatureInfo.GetClassInfo and GetNumClasses then
      keep = false
      local ok, n = pcall(GetNumClasses)
      for i = 1, (ok and type(n) == "number" and n or 0) do
        local ok2, info = pcall(C_CreatureInfo.GetClassInfo, i)
        if ok2 and type(info) == "table" and info.classFile == c then keep = true end
      end
      if not ok or type(n) ~= "number" then keep = true end
    end
    if keep and #list < 9 then list[#list + 1] = c end
  end
  return list
end
local function finderDefaultMode()
  local id = A.MySquadId()
  if id and ns.state.squads[id].d.captain == ns.me() and #M.members(ns.state, id) < M.SQUAD_SIZE then return "players" end
  return "squads"
end

local function makeResult(parent)
  local c = W.Card(parent)
  c.class = c:CreateTexture(nil, "ARTWORK"); c.class:SetSize(36, 36); c.class:SetPoint("LEFT", 10, 0)
  c.logo = W.Logo(c, 40); c.logo:SetPoint("LEFT", 8, 0)
  c.dot = c:CreateTexture(nil, "OVERLAY"); c.dot:SetSize(8, 8); c.dot:SetPoint("TOPLEFT", 4, -4)
  c.name = W.Label(c, "", "GameFontNormal"); c.name:SetPoint("TOPLEFT", 56, -8)
  c.role = c:CreateTexture(nil, "ARTWORK"); c.role:SetSize(18, 18); c.role:SetPoint("TOPLEFT", 230, -6)
  c.role2 = c:CreateTexture(nil, "ARTWORK"); c.role2:SetSize(13, 13); c.role2:SetPoint("LEFT", c.role, "RIGHT", 2, -2)
  c.reasons = {}
  for i = 1, 3 do
    local r = W.ReasonChip(c)
    if i == 1 then r:SetPoint("BOTTOMLEFT", 56, 8) else r:SetPoint("LEFT", c.reasons[i - 1], "RIGHT", 4, 0) end
    c.reasons[i] = r
  end
  c.fit = W.FitBadge(c); c.fit:SetPoint("RIGHT", -10, 0)
  -- goal chips end 8 px left of the fit badge (they grew under it from x=470 with 3 chips)
  -- at most 2 goal chips + "+N" (the full list is in the tooltip), so they never cover the badge
  c.more = W.Label(c, "", "GameFontHighlightSmall"); c.more:SetPoint("RIGHT", c.fit, "LEFT", -6, 0)
  c.chips = W.ChipRow(c, 3); c.chips.alignRight = true; c.chips:SetPoint("RIGHT", c.more, "LEFT", -4, 0)
  return c
end
local function twoChips(c, keys)
  keys = keys or {}
  local shown = { keys[1], keys[2] }
  c.chips:SetKeys(shown)
  c.more:SetText(#keys > 2 and ("+" .. (#keys - 2)) or "")
end
local function fillResult(c, item)
  for i, r in ipairs(c.reasons) do
    if item.reasons[i] then r:SetReason(item.reasons[i]); r:Show() else r:Hide() end
  end
  c.fit:SetFit(item.score, item.reasons)
  if item.player then
    local i = item.player
    c.logo:Hide(); c.class:Show(); c.dot:Show()
    W.SetClass(c.class, i.class)
    c.dot:SetTexture(i.online and "Interface\\FriendsFrame\\StatusIcon-Online" or "Interface\\FriendsFrame\\StatusIcon-Offline")
    c.name:SetText(nameColored(i.name, i.class) .. "  |cffaaaaaa" .. L.LV_SHORT:format(tostring(i.level or "?")) .. "|r")
    if i.role then W.SetRole(c.role, i.role); c.role:Show() else c.role:Hide() end
    if i.role2 then W.SetRole(c.role2, i.role2); c.role2:Show() else c.role2:Hide() end
    twoChips(c, i.goals)
    W.Tooltip(c, memberTooltip(i.name))
    c:SetScript("OnClick", function(_, b)
      fd.selected = i.name
      if b == "RightButton" then
        local items = { { text = ns.shortName(i.name), title = true },
          { text = L.WHISPER, func = function() whisper(i.name) end },
          { text = L.INVITE_PARTY, func = function() inviteGroup(i.name) end } }
        local my = A.MySquadId()
        if my and ns.state.squads[my].d.captain == ns.me() then
          items[#items + 1] = { text = L.INVITE_SQUAD, func = function() local _, why = A.AddMember(my, i.name); err(why) end }
        end
        items[#items + 1] = { text = CANCEL or L.CANCEL }
        W.Menu(c, items)
      else UI.Select("finder") end
    end)
    c.border.set(fd.selected == i.name and 1 or 0.3, fd.selected == i.name and 0.82 or 0.3, fd.selected == i.name and 0 or 0.3, 1)
  else
    local d = item.d
    c.class:Hide(); c.dot:Hide(); c.role2:Hide(); c.logo:Show()
    c.logo:SetLogo(d.icon, d.color, d.border)
    c.name:SetText((M.displayName(ns.state, item.id) or d.name) .. "  |cffaaaaaa" .. ("%d/%d"):format(item.ctx.count, M.SQUAD_SIZE) .. "|r")
    local miss = roleList(item.ctx.needs)[1]
    if miss then W.SetRole(c.role, miss); c.role:Show() else c.role:Hide() end
    twoChips(c, (M.splitTags(d.tags)))
    W.Tooltip(c, d.name, d.motto)
    c:SetScript("OnClick", function(_, b)
      fd.selected = item.id
      if b == "RightButton" then W.Menu(c, squadMenu(item.id, d)) else UI.Select("finder") end
    end)
    c.border.set(fd.selected == item.id and 1 or 0.3, fd.selected == item.id and 0.82 or 0.3, fd.selected == item.id and 0 or 0.3, 1)
  end
end

UI.Register("finder", L.TAB_FINDER, function(f, bar)
  fd.mP = W.Button(f, L.FINDER_PLAYERS, 170, 22, function() fd.mode = "players"; fd.selected = nil; UI.Select("finder") end)
  fd.mP:SetPoint("TOPLEFT", 10, -8)
  fd.mS = W.Button(f, L.FINDER_SQUADS, 170, 22, function() fd.mode = "squads"; fd.selected = nil; UI.Select("finder") end)
  UI.TopRow(f, { fd.mP, fd.mS }, 4, -8) -- centred, clear of the portrait
  local fb = CreateFrame("Frame", nil, f); fb:SetPoint("TOPLEFT", 10, -40); fb:SetSize(674, 54)
  local fbg = fb:CreateTexture(nil, "BACKGROUND"); fbg:SetAllPoints(); fbg:SetColorTexture(0.08, 0.07, 0.06, 1)
  local function group(label, x) local t = W.Label(fb, label); t:SetPoint("TOPLEFT", x, -3); t:SetTextColor(0.6, 0.6, 0.6) end
  local refresh = function() UI.Select("finder") end
  group(L.F_ROLE, 6)
  fd.roleT = {}
  for i, r in ipairs(ROLES) do
    local t = W.IconToggle(fb, 26, W.ROLE_ICON[r], L["ROLE_" .. r], function(self, on) fd.role[r] = on or nil; refresh() end)
    W.SetRole(t.icon, r)
    t:SetPoint("TOPLEFT", 6 + (i - 1) * 28, -18); fd.roleT[i] = t
  end
  group(L.F_CLASS, 96)
  fd.classT = {}
  for i, c in ipairs(forClasses()) do
    local t = W.IconToggle(fb, 22, W.QUESTION, (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c]) or c,
      function(self, on) fd.class[c] = on or nil; refresh() end)
    W.SetClass(t.icon, c)
    t:SetPoint("TOPLEFT", 96 + (i - 1) * 24, -20); fd.classT[i] = t
  end
  group(L.F_GOAL, 318)
  fd.goalT = {}
  for i, g in ipairs(M.GOALS) do
    local t = W.IconToggle(fb, 22, W.GOAL_ICON[g], L["GOAL_" .. g], function(self, on) fd.goal[g] = on or nil; refresh() end)
    t:SetPoint("TOPLEFT", 318 + (i - 1) * 24, -20); fd.goalT[i] = t
  end
  group(L.F_LEVEL, 474)
  local function lvl(x)
    local e = W.Edit(fb, 32, 2); e:SetPoint("TOPLEFT", x, -22); e:SetNumeric(true)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus(); refresh() end)
    e:SetScript("OnEditFocusLost", function() refresh() end)
    return e
  end
  fd.minL = lvl(478); fd.maxL = lvl(518)
  fd.avail = W.IconToggle(fb, 24, ICONS .. "Spell_Holy_BorrowedTime", L.F_AVAIL, function() refresh() end)
  fd.avail:SetPoint("TOPLEFT", 584, -20)
  fd.online = W.IconToggle(fb, 24, "Interface\\FriendsFrame\\StatusIcon-Online", L.F_ONLINE, function() refresh() end)
  fd.online:SetPoint("LEFT", fd.avail, "RIGHT", 6, 0)
  local area = CreateFrame("Frame", nil, f); area:SetPoint("TOPLEFT", 10, -102); area:SetPoint("BOTTOMRIGHT", -6, 22)
  fd.grid = W.Grid(area, 1, 4, 674, 58, 0, 8, makeResult, fillResult)
  fd.foot = W.Label(f, ""); fd.foot:SetPoint("BOTTOMLEFT", 12, 6); fd.foot:SetTextColor(0.6, 0.6, 0.6)
  fd.empty = W.Label(f, L.EMPTY_FILTER, "GameFontNormal"); fd.empty:SetPoint("CENTER", 0, -20)
  local function clear()
    fd.role, fd.class, fd.goal = {}, {}, {}
    for _, l in ipairs({ fd.roleT, fd.classT, fd.goalT }) do for _, t in ipairs(l) do t:SetChecked(false) end end
    fd.avail:SetChecked(false); fd.online:SetChecked(false); fd.minL:SetText(""); fd.maxL:SetText("")
    refresh()
  end
  fd.clear = W.Link(bar, L.CLEAR_FILTERS, clear); fd.clear:SetPoint("LEFT", 14, 2)
  fd.primary = W.Primary(bar, L.INVITE_SQUAD, function()
    if not fd.selected then return end
    if fd.mode == "players" then local _, why = A.AddMember(A.MySquadId(), fd.selected); err(why)
    else local _, why = A.RequestJoin(fd.selected); err(why) end
  end)
  local lv = UnitLevel and UnitLevel("player")
  if type(lv) == "number" then fd.minL:SetText(tostring(math.max(1, lv - 3))); fd.maxL:SetText(tostring(lv + 3)) end
  -- removable chip for the level filter (top right of the results)
  fd.lvChip = W.Button(f, "", 120, 18, function() fd.minL:SetText(""); fd.maxL:SetText(""); refresh() end)
  fd.lvChip:SetPoint("BOTTOMRIGHT", area, "TOPRIGHT", -4, 2)
  W.Tooltip(fd.lvChip, L.LEVEL_CHIP_TIP)
  fd.lvChip:Hide()
end, function(f, bar)
  fd.mode = fd.mode or finderDefaultMode()
  if not squadsOn() then fd.mode = "players" end
  fd.mP:SetEnabled(fd.mode ~= "players"); fd.mS:SetEnabled(fd.mode ~= "squads"); fd.mS:SetShown(squadsOn())
  local me = myInfo()
  local filters = { role = fd.role, class = fd.class, goal = fd.goal,
    minLevel = tonumber(fd.minL:GetText() or ""), maxLevel = tonumber(fd.maxL:GetText() or ""),
    availWith = fd.avail:GetChecked() and me.avail or nil, onlineOnly = fd.online:GetChecked() and true or nil }
  local items, total = {}, 0
  if fd.mode == "squads" then
    items = squadItems(function(id, d, ctx)
      if d.approved == false or squadState(d, ctx) ~= "open" then return false end
      total = total + 1
      local f2 = { role = filters.role, goal = filters.goal, minLevel = filters.minLevel, maxLevel = filters.maxLevel,
                   availWith = filters.availWith, onlineOnly = filters.onlineOnly }
      return X.passes({ needs = ctx.needs, level = ctx.level, avail = ctx.avail, goals = ctx.goals, online = ctx.online, role = "-" }, f2)
    end)
  else
    local myId = A.MySquadId()
    local target = myId and squadCtx(myId) or { avail = me.avail, level = me.level, goals = me.goals }
    for name in pairs(ns.state.profiles) do
      local r = ns.roster(name)
      if r and name ~= ns.me() and not M.squadOf(ns.state, name) then
        total = total + 1
        local i = infoOf(name)
        if X.passes(i, filters) then
          local score, reasons = X.score(i, target)
          items[#items + 1] = { player = i, score = score, reasons = reasons }
        end
      end
    end
    table.sort(items, function(a, b)
      if a.score ~= b.score then return a.score > b.score end
      if (a.player.online and 1 or 0) ~= (b.player.online and 1 or 0) then return a.player.online and true or false end
      return a.player.name < b.player.name
    end)
  end
  fd.grid:SetItems(items)
  fd.empty:SetShown(#items == 0)
  local active = {}
  for _, set in ipairs({ { fd.role, "ROLE_" }, { fd.class }, { fd.goal, "GOAL_" } }) do
    for k in pairs(set[1]) do active[#active + 1] = set[2] and L[set[2] .. k] or k end
  end
  if filters.minLevel or filters.maxLevel then active[#active + 1] = L.F_LEVEL .. " " .. tostring(filters.minLevel or "") .. "-" .. tostring(filters.maxLevel or "") end
  if filters.availWith then active[#active + 1] = L.F_AVAIL end
  if filters.onlineOnly then active[#active + 1] = L.F_ONLINE end
  fd.foot:SetText(L.RESULTS_N:format(#items, total, fd.mode == "squads" and L.SQUADS_WORD or L.PLAYERS_WORD)
    .. (#active > 0 and (" · " .. L.FILTERS .. ": " .. table.concat(active, ", ")) or ""))
  local my = A.MySquadId()
  local why                              -- a disabled main button says why
  if fd.mode == "players" then
    fd.primary:SetText(L.INVITE_SQUAD)
    if my == nil then why = L.WHY_NO_SQUAD
    elseif ns.state.squads[my].d.captain ~= ns.me() then why = L.WHY_NOT_CAPTAIN
    elseif #M.members(ns.state, my) >= M.SQUAD_SIZE then why = L.WHY_SQUAD_FULL
    elseif fd.selected == nil then why = L.WHY_SELECT_PLAYER end
  else
    fd.primary:SetText(L.REQUEST_JOIN)
    if my ~= nil then why = L.WHY_HAVE_SQUAD:format(tostring((ns.state.squads[my] and ns.state.squads[my].d.name) or my))
    elseif fd.selected == nil then why = L.WHY_SELECT_SQUAD end
  end
  fd.primary:SetEnabled(why == nil)
  W.Tooltip(fd.primary, why and L.WHY_DISABLED or nil, why)
  -- the level filter is a visible chip that can be removed
  if fd.lvChip then
    local lvOn = filters.minLevel or filters.maxLevel
    fd.lvChip:SetShown(lvOn and true or false)
    if lvOn then fd.lvChip:SetText(L.LEVEL_CHIP:format(tostring(filters.minLevel or "1"), tostring(filters.maxLevel or "60"))) end
  end
end, nil, { icon = ICONS .. "INV_Misc_Key_03" })

-------------------------------------------------------------------------------
-- Mi perfil
local prof = { roles = {}, slots = {}, goals = {} }
UI.profileState = prof -- exposed for the smoke tests
function UI.ProfileState() return prof end
local function profDraft()
  local cur = A.MyProfile()
  local a = {}
  for i = 1, 8 do a[i] = prof.slots[i].on and "1" or "0" end
  local g = {}
  for _, c in ipairs(prof.goals) do if c.on then g[#g + 1] = c.key end end
  local d = { role = prof.role, role2 = prof.role2, avail = table.concat(a), goals = g }
  local changes = 0
  if d.role ~= cur.role then changes = changes + 1 end
  if d.role2 ~= cur.role2 then changes = changes + 1 end
  for i = 1, 8 do if d.avail:sub(i, i) ~= (cur.avail or "00000000"):sub(i, i) then changes = changes + 1 end end
  local had = {}
  for _, x in ipairs(cur.goals or {}) do had[x] = true end
  for _, c in ipairs(prof.goals) do if (had[c.key] or false) ~= c.on then changes = changes + 1 end end
  return d, changes
end
local function profUpdate()
  for i, r in ipairs(ROLES) do
    local b = prof.roles[i]
    local st = (prof.role == r and "main") or (prof.role2 == r and "sec") or nil
    b.icon:SetDesaturated(st == nil); b.icon:SetAlpha(st and 1 or 0.45)
    b.ring.show(st ~= nil)
    if st == "main" then b.ring.set(1, 0.82, 0, 1) else b.ring.set(0.75, 0.75, 0.8, 1) end
    b.state:SetText(st == "main" and L.ROLE_MAIN or st == "sec" and L.ROLE_SEC or "-")
  end
  for _, t in ipairs(prof.slots) do
    if t.on then t.bg:SetColorTexture(0.14, 0.35, 0.14, 1); t.edge.set(0.25, 0.62, 0.25, 1); t.text:SetText(W.Icon(CHECK, 12) .. " |cff88ff88" .. t.label .. "|r")
    else t.bg:SetColorTexture(0.05, 0.05, 0.05, 1); t.edge.set(0.2, 0.2, 0.2, 1); t.text:SetText("|cff777777" .. t.label .. "|r") end
  end
  local _, changes = profDraft()
  prof.bar.status:SetText(changes > 0 and L.UNSAVED:format(changes) or L.SAVED_SHORT)
  prof.save:SetEnabled(changes > 0)
  W.Tooltip(prof.save, changes == 0 and L.WHY_DISABLED or nil, changes == 0 and L.WHY_NO_CHANGES or nil)
end

UI.Register("profile", L.TAB_PROFILE, function(f, bar)
  prof.bar = bar
  local left = CreateFrame("Frame", nil, f); left:SetPoint("TOPLEFT", 8, -30); left:SetSize(200, 394) -- below the portrait
  local lbg = left:CreateTexture(nil, "BACKGROUND"); lbg:SetAllPoints(); lbg:SetColorTexture(0.06, 0.05, 0.04, 1)
  prof.classIcon = left:CreateTexture(nil, "ARTWORK"); prof.classIcon:SetSize(66, 66); prof.classIcon:SetPoint("TOP", 0, -14)
  prof.name = W.Label(left, "", "GameFontNormalLarge"); prof.name:SetPoint("TOP", 0, -88)
  prof.sub = W.Label(left, ""); prof.sub:SetPoint("TOP", 0, -110)
  prof.zone = W.Label(left, ""); prof.zone:SetPoint("TOP", 0, -126); prof.zone:SetTextColor(0.7, 0.7, 0.7)
  local note = W.Label(left, L.PROFILE_AUTO); note:SetPoint("TOPLEFT", 10, -156); note:SetWidth(180); note:SetTextColor(0.55, 0.55, 0.55)
  prof.squad = W.Label(left, ""); prof.squad:SetPoint("TOPLEFT", 10, -250); prof.squad:SetWidth(180)
  -- one line, truncated (a long squad name wrapped over the "Mi squad" link at -268)
  if prof.squad.SetWordWrap then pcall(prof.squad.SetWordWrap, prof.squad, false) end
  if prof.squad.SetMaxLines then pcall(prof.squad.SetMaxLines, prof.squad, 1) end
  prof.squad:SetHeight(14)
  prof.squadLink = W.Link(left, L.TAB_MYSQUAD, function() UI.Select("mysquad") end); prof.squadLink:SetPoint("TOPLEFT", 10, -268)
  local rt = W.Label(f, L.MAIN_ROLE .. " · " .. L.ROLE_CYCLE, "GameFontNormal"); rt:SetPoint("TOPLEFT", 224, -10)
  for i, r in ipairs(ROLES) do
    local b = CreateFrame("Button", nil, f); b:SetSize(60, 60); b:SetPoint("TOPLEFT", 228 + (i - 1) * 110, -32)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(54, 54); b.icon:SetPoint("CENTER")
    W.SetRole(b.icon, r, true); W.Round(b, b.icon)
    b.ring = W.Border(b, 2, 1, 0.82, 0, 1)
    b.label = W.Label(b, L["ROLE_" .. r], "GameFontNormal"); b.label:SetPoint("TOP", b, "BOTTOM", 0, -4)
    b.state = W.Label(b, ""); b.state:SetPoint("TOP", b.label, "BOTTOM", 0, -2)
    W.Tooltip(b, L["ROLE_" .. r], L.ROLE_CYCLE)
    b:SetScript("OnClick", function()
      if prof.role == r then prof.role = nil; prof.role2 = r                   -- main -> secondary
      elseif prof.role2 == r then prof.role2 = nil                             -- secondary -> none
      else if prof.role then prof.role2 = prof.role end; prof.role = r end      -- none -> main (old main -> secondary)
      profUpdate()
    end)
    prof.roles[i] = b
  end
  local at = W.Label(f, L.AVAILABILITY .. " (" .. L.REALM_TIME .. ")", "GameFontNormal"); at:SetPoint("TOPLEFT", 224, -146)
  for half = 0, 1 do
    local rl = W.Label(f, half == 0 and L.WEEKDAY or L.WEEKEND); rl:SetPoint("TOPLEFT", 224, -176 - half * 40)
    for s = 1, 4 do
      local t = CreateFrame("Button", nil, f); t:SetSize(86, 34); t:SetPoint("TOPLEFT", 314 + (s - 1) * 90, -166 - half * 40)
      t.bg = t:CreateTexture(nil, "BACKGROUND"); t.bg:SetAllPoints()
      t.edge = W.Border(t, 1, 0.2, 0.2, 0.2, 1)
      t.label = L["SLOT_" .. s]
      t.text = W.Label(t, ""); t.text:SetPoint("CENTER")
      t:SetScript("OnClick", function(self) self.on = not self.on; profUpdate() end)
      prof.slots[half * 4 + s] = t
    end
  end
  local gt = W.Label(f, L.GOALS, "GameFontNormal"); gt:SetPoint("TOPLEFT", 224, -262)
  local prev
  for i, g in ipairs(M.GOALS) do
    local c = W.Chip(f, g, function() profUpdate() end, { big = true })
    if prev then c:SetPoint("LEFT", prev, "RIGHT", 6, 0) else c:SetPoint("TOPLEFT", 224, -284) end
    prof.goals[i] = c; prev = c
  end
  prof.last = W.Label(f, ""); prof.last:SetPoint("BOTTOMLEFT", 224, 8); prof.last:SetTextColor(0.5, 0.5, 0.5)
  -- "Mis logros": grid of badges with progress (UI/Hall.lua builds it once that file is loaded)
  prof.achT = W.Label(f, L.MY_ACH, "GameFontNormal"); prof.achT:SetPoint("TOPLEFT", 224, -318)
  prof.save = W.Primary(bar, L.SAVE, function()
    local d = profDraft()
    if A.SaveProfile(d) then ns.print(L.SAVED) end
    profUpdate()
    if ns.UpdateBadge then pcall(ns.UpdateBadge) end
  end)
end, function()
  local d = A.MyProfile()
  local i = myInfo()
  -- a background refresh never wipes unsaved edits
  local keepEdits = prof.editing and select(2, profDraft()) > 0
  W.SetClass(prof.classIcon, i.class)
  prof.name:SetText(nameColored(ns.me() or "?", i.class))
  local race = UnitRace and UnitRace("player")
  prof.sub:SetText(("%s %s · %s"):format(W.ClassName(i.class), tostring(race or ""), L.LV_SHORT:format(tostring(i.level or "?"))))
  prof.zone:SetText((GetRealZoneText and GetRealZoneText()) or "")
  local sid = A.MySquadId()
  prof.squad:SetText(L.SQUAD_LABEL .. ": " .. (sid and ns.state.squads[sid].d.name or L.NONE))
  if not keepEdits then
    prof.role, prof.role2 = d.role, d.role2
    local a = d.avail or "00000000"
    for k = 1, 8 do prof.slots[k].on = a:sub(k, k) == "1" end
    local has = {}
    for _, g in ipairs(d.goals or {}) do has[g] = true end
    for _, c in ipairs(prof.goals) do c:SetOn(has[c.key] or false) end
  end
  prof.editing = true
  local rec = ns.state.profiles[ns.me() or ""]
  local now = (GetServerTime and GetServerTime()) or 0
  if not prof.ach and UI.AchGrid then
    prof.ach = UI.AchGrid(UI.panels.profile.frame, 18, 2); prof.ach:SetPoint("TOPLEFT", UI.panels.profile.frame, "TOPLEFT", 224, -336)
  end
  if prof.ach then local got, n = prof.ach:Fill(); prof.achT:SetText(L.MY_ACH .. " (" .. got .. "/" .. n .. ")") end
  prof.last:SetText(rec and L.LAST_SHARED:format(L.MINUTES:format(math.max(0, math.floor((now - rec.ts) / 60)))) or "")
  profUpdate()
end, nil, { icon = function()
  local _, class = UnitClass("player")
  return class and ("Interface\\Icons\\ClassIcon_" .. class:sub(1, 1) .. class:sub(2):lower()) or W.QUESTION
end,
  -- leaving Mi perfil with unsaved changes asks (save / discard / keep editing)
  beforeLeave = function(nextKey)
    if not prof.editing or select(2, profDraft()) == 0 then prof.editing = false; return false end
    -- third button "Guardar y salir" saves the draft, then leaves (stays if the save is refused)
    W.Confirm(L.PROFILE_UNSAVED, function() prof.editing = false; UI.Select(nextKey, true) end, L.DISCARD, L.KEEP_EDITING,
      L.SAVE_AND_EXIT, function()
        local d = profDraft()
        if not A.SaveProfile(d) then return end
        ns.print(L.SAVED)
        prof.editing = false
        if ns.UpdateBadge then pcall(ns.UpdateBadge) end
        UI.Select(nextKey, true)
      end)
    return true
  end,
  onHide = function()
    if prof.editing and select(2, profDraft()) > 0 then ns.print(L.PROFILE_UNSAVED_BAR) end
    -- edits stay (prof.editing) until saved or discarded
  end })

-------------------------------------------------------------------------------
-- Ajustes: visible to every guild member; only the GM (rank 0) can change it (validated again on every
-- client by Core/Model.lua). Sections: Squads · Competición · Temporada · Integraciones · Moderación.
-- Edits go to a local draft; "Guardar y compartir" publishes one settings record. Leaving with unsaved changes asks.
local st = { officers = {}, ctl = {}, sec = {}, secBtn = {}, seg = {}, dirty = false, draft = nil, cur = "squads" }
local function isGM() return P.isGM(ns.roster, ns.me()) and true or false end
local function isMod() return P.isOfficer(ns.roster, ns.me(), settings()) and true or false end
local function rankName(i)
  if GuildControlGetRankName then local ok, n = pcall(GuildControlGetRankName, i + 1); if ok and type(n) == "string" and n ~= "" then return n end end
  if ns.rankNames and type(ns.rankNames[i]) == "string" then return ns.rankNames[i] end   -- names from the roster
  return L.RANK .. " " .. i
end
local function numRanks()
  if GuildControlGetNumRanks then local ok, n = pcall(GuildControlGetNumRanks); if ok and type(n) == "number" and n > 0 then return math.min(n, 10) end end
  return 10
end
local SECTIONS = { "squads", "comp", "season", "integ", "mod", "cel", "content", "raids", "ach" } -- Logros is GM only
UI.SEC_W = 68 -- 9 section buttons (68 px + 3 px gap) fit right of the portrait and inside the window
local function copyDeep(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = copyDeep(v) end
  return o
end
local settingsRefresh
local function draft()
  if not st.draft then st.draft = copyDeep(settings()) end
  return st.draft
end
local function markDirty()
  if not isGM() then return end
  st.dirty = true
  if st.bar then st.bar.status:SetText("|cffff9933" .. L.S_UNSAVED_BAR .. "|r") end
end
UI.SettingsDirty = function() return st.dirty end
local function ctl(c) st.ctl[#st.ctl + 1] = c; return c end
local function setEnabled(c, v)
  if c.SetEnabled then pcall(c.SetEnabled, c, v) elseif v and c.Enable then pcall(c.Enable, c) elseif c.Disable then pcall(c.Disable, c) end
end
-- segmented control: label + one button per value; the selected value is shown in yellow brackets
-- fixed label column (options of every row start at the same x) and buttons as wide as their
-- longest option incl. the [selected] brackets (~7 px per character, at least 46 px)
UI.SEG_LABEL_W = 200
local function textChars(t) return #(tostring(t):gsub("[\128-\191]", "")) end
function UI.SegButtonWidth(labels)
  local n = 0
  for _, t in ipairs(labels) do n = math.max(n, textChars(t) + 2) end
  return math.max(46, 7 * n + 12)
end
local function seg(parent, x, y, label, field, values, show)
  local lb = W.Label(parent, label); lb:SetPoint("TOPLEFT", x, y - 5); lb:SetWidth(UI.SEG_LABEL_W - 8)
  if lb.SetWordWrap then pcall(lb.SetWordWrap, lb, false) end
  local s = { field = field, values = values, show = show, buttons = {} }
  local bx = x + UI.SEG_LABEL_W
  local labels = {}
  for i, v in ipairs(values) do labels[i] = show(v) end
  local bw = UI.SegButtonWidth(labels)
  s.width = bw
  for i, v in ipairs(values) do
    local b = ctl(W.Button(parent, show(v), bw, 22, function(self)
      if not isGM() or self.selected then return end
      draft()[field] = v; markDirty(); s:Update()
    end))
    b:SetPoint("TOPLEFT", bx + (i - 1) * (bw + 2), y)
    s.buttons[i] = b
  end
  function s:Update()
    for i, v in ipairs(self.values) do
      local on = st.draft and st.draft[self.field] == v
      self.buttons[i]:SetText(self.show(v))
      W.SetSelected(self.buttons[i], on)
    end
  end
  st.seg[#st.seg + 1] = s
  return s
end
local function check(parent, x, y, label, field, invert)
  local c = ctl(W.Check(parent, label, function(self)
    if not isGM() then self:SetChecked(not self:GetChecked()); return end
    local v = self:GetChecked() and true or false
    if invert then v = not v end
    draft()[field] = v; markDirty()
  end))
  c:SetPoint("TOPLEFT", x, y)
  c.field, c.invert = field, invert
  return c
end
local function plain(v) return tostring(v) end
local function xw(v) return "x" .. v end

-- simple date picker (realm time): day, month, year with arrows + hour. value = server timestamp or 0
local function daysIn(y, m)
  local ny, nm = y, m + 1
  if nm > 12 then ny, nm = y + 1, 1 end
  return Pr.daysFromCivil(ny, nm, 1) - Pr.daysFromCivil(y, m, 1)
end
local function datePicker(parent, x, y, label, field, allowNone)
  local dp = { field = field }
  local lb = W.Label(parent, label); lb:SetPoint("TOPLEFT", x, y - 5)
  dp.text = W.Label(parent, "", "GameFontHighlight"); dp.text:SetPoint("TOPLEFT", x + 120, y - 5)
  local function parts()
    local ts = draft()[field] or 0
    if ts <= 0 then ts = (GetServerTime and GetServerTime()) or Pr.DEFAULT_SEASON_START end
    local lt = ts + Pr.realmOffset(ts)
    local yy, mm, dd = Pr.civilFromDays(math.floor(lt / 86400))
    return { yy, mm, dd, math.floor((lt % 86400) / 3600) }
  end
  local function setParts(p)
    if p[2] < 1 then p[1], p[2] = p[1] - 1, 12 elseif p[2] > 12 then p[1], p[2] = p[1] + 1, 1 end
    p[3] = math.max(1, math.min(daysIn(p[1], p[2]), p[3])); p[4] = p[4] % 24
    local ts = Pr.parseDate(("%04d-%02d-%02d %02d:00"):format(p[1], p[2], p[3], p[4]))
    if ts then draft()[field] = ts; markDirty() end
    dp:Update()
  end
  -- direct entry "AAAA-MM-DD HH:MM" (validated) + quick "+1 semana / +1 mes" instead of 8 arrow pairs
  dp.edit = ctl(W.Edit(parent, 130, 16)); dp.edit:SetPoint("TOPLEFT", x + 270, y)
  W.Tooltip(dp.edit, L.S_SEASON_TITLE, L.S_DATE_EDIT_TIP)
  local function commit(self)
    if not isGM() then dp:Update(); return end
    local ts = Pr.parseDate(self:GetText() or "")
    if ts then draft()[field] = ts; markDirty()
    elseif UIErrorsFrame and UIErrorsFrame.AddMessage then pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, L.S_SEASON_BAD, 1, 0.3, 0.3) end
    self:ClearFocus(); dp:Update()
  end
  dp.edit:SetScript("OnEnterPressed", commit)
  dp.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); dp:Update() end)
  local function addDays(n, months)
    if not isGM() then return end
    if months then local p = parts(); p[2] = p[2] + months; setParts(p); return end
    local cur = draft()[field] or 0
    if cur <= 0 then cur = (GetServerTime and GetServerTime()) or Pr.DEFAULT_SEASON_START end
    draft()[field] = cur + n * 86400; markDirty(); dp:Update()
  end
  dp.week = ctl(W.Button(parent, L.S_DATE_WEEK, 84, 20, function() addDays(7) end))
  dp.week:SetPoint("LEFT", dp.edit, "RIGHT", 8, 0)
  dp.month = ctl(W.Button(parent, L.S_DATE_MONTH1, 70, 20, function() addDays(0, 1) end))
  dp.month:SetPoint("LEFT", dp.week, "RIGHT", 4, 0)
  if allowNone then
    dp.none = ctl(W.Check(parent, L.S_DATE_NONE, function(self)
      if not isGM() then self:SetChecked(not self:GetChecked()); return end
      if self:GetChecked() then draft()[field] = 0 else draft()[field] = (GetServerTime and GetServerTime()) or Pr.DEFAULT_SEASON_START end
      markDirty(); dp:Update()
    end))
    dp.none:SetPoint("TOPLEFT", x + 590, y + 1)
  end
  function dp:Update()
    local ts = draft()[field] or 0
    self.text:SetText(ts > 0 and Pr.formatDate(ts) or L.S_DATE_NONE)
    if self.edit and not (self.edit.HasFocus and self.edit:HasFocus() == true) then
      self.edit:SetText(ts > 0 and Pr.formatDate(ts) or "")
    end
    if self.none then self.none:SetChecked(ts <= 0) end
  end
  return dp
end

local function buildSquads(f)
  check(f, 8, -4, L.S_ENABLED, "squadsEnabled")
  check(f, 330, -4, L.S_APPROVAL, "requireApproval")
  local mr = W.Label(f, L.S_MINRANK); mr:SetPoint("TOPLEFT", 12, -42)
  st.minRank = ctl(W.Button(f, "", 200, 22, function(self)
    if not isGM() then return end
    local items = { { text = L.S_MINRANK, title = true } }
    for i = 0, numRanks() - 1 do
      items[#items + 1] = { text = i .. " · " .. rankName(i), func = function()
        draft().minCreateRank = i; markDirty(); settingsRefresh(nil, nil, true)
      end }
    end
    W.Menu(self, items)
  end))
  st.minRank:SetPoint("TOPLEFT", 200, -38)
  seg(f, 12, -72, L.S_BENCH, "bench", { 0, 1, 2 }, plain)
  local ol = W.Label(f, L.S_OFFICERS); ol:SetPoint("TOPLEFT", 12, -106)
  for i = 1, 9 do
    local c = ctl(W.Check(f, "", function(self)
      if not isGM() then self:SetChecked(not self:GetChecked()); return end
      local list = {}
      for j, o in ipairs(st.officers) do if j < numRanks() and o:GetChecked() then list[#list + 1] = j end end
      draft().officerRanks = list; markDirty()
    end))
    c:SetPoint("TOPLEFT", 12 + ((i - 1) % 5) * 134, -122 - math.floor((i - 1) / 5) * 24)
    st.officers[i] = c
  end
  local function days(v) return v == 0 and L.S_NEVER or tostring(v) end
  seg(f, 12, -180, L.S_INACTIVE_DAYS, "inactiveDays", M.INACTIVE_DAYS, days)
  local function maxs(v) return v == 0 and L.S_NOLIMIT or tostring(v) end
  seg(f, 12, -212, L.S_MAX_SQUADS, "maxSquads", M.MAX_SQUADS, maxs)
  -- adoption, so the GM can encourage installing the addon
  st.adopt = W.Label(f, "", "GameFontNormal"); st.adopt:SetPoint("TOPLEFT", 12, -248)
end

local function buildComp(f)
  check(f, 8, -4, L.S_COMP, "compEnabled")
  local cats = { { "wLevel", "level" }, { "wDungeon", "dungeon" }, { "wRaid", "raid" }, { "wPvp", "pvp" }, { "wWpvp", "wpvp" } }
  for i, c in ipairs(cats) do seg(f, 12, -36 - (i - 1) * 28, L.S_WEIGHT:format(L["CAT_" .. c[2]]), c[1], { 0, 1, 2, 3 }, xw) end
  seg(f, 12, -184, L.S_CAP, "weekCap", M.CAPS, plain)
  seg(f, 12, -214, L.S_GOAL, "guildGoal", { 10, 20, 30, 50, 100 }, plain)
  local reset = W.Label(f, L.S_RESET_NOTE); reset:SetPoint("TOPLEFT", 12, -250); reset:SetTextColor(0.7, 0.7, 0.7)
end

local function buildSeason(f)
  local nl = W.Label(f, L.S_SEASON_NAME); nl:SetPoint("TOPLEFT", 12, -8)
  st.seasonName = ctl(W.Edit(f, 220, 24)); st.seasonName:SetPoint("TOPLEFT", 132, -4)
  st.seasonName:SetScript("OnTextChanged", function(self, user)
    if user == false or not st.draft or not isGM() then return end
    local t = (self:GetText() or ""):sub(1, 24)
    if t ~= (st.draft.seasonName or "") then draft().seasonName = t; markDirty() end
  end)
  st.dStart = datePicker(f, 12, -40, L.S_SEASON_START_SHORT, "seasonStart")
  st.dEnd = datePicker(f, 12, -70, L.S_SEASON_END_SHORT, "seasonEnd", true)
  st.newSeason = ctl(W.Button(f, L.S_SEASON_NEW, 160, 22, function()
    if not isGM() then return end
    W.Confirm(L.S_SEASON_NEW_CONFIRM, function()
      local now = (GetServerTime and GetServerTime()) or 0
      local fresh = Pr.newSeason(draft(), now, "")
      for k, v in pairs(fresh) do draft()[k] = v end
      UI.SaveSettingsNow()
    end)
  end))
  st.newSeason:SetPoint("TOPLEFT", 12, -104)
  local pl = W.Label(f, L.S_SEASONS_PAST, "GameFontNormal"); pl:SetPoint("TOPLEFT", 12, -140)
  st.past = {}
  for i = 1, 8 do
    local l = W.Label(f, ""); l:SetPoint("TOPLEFT", 16, -158 - (i - 1) * 16); l:SetTextColor(0.75, 0.75, 0.75)
    st.past[i] = l
  end
end

local function buildInteg(f)
  check(f, 8, -4, L.S_OVERLORD, "overlordOn")
  check(f, 8, -32, L.S_OVHINT, "ovHint")
  local n = W.Label(f, L.S_INTEG_NOTE); n:SetPoint("TOPLEFT", 12, -66); n:SetWidth(640); n:SetTextColor(0.7, 0.7, 0.7)
end

local function modRow(parent, i)
  local r = CreateFrame("Frame", nil, parent); r:SetSize(660, 22)
  r:SetPoint("TOPLEFT", 12, -168 - (i - 1) * 24)
  r.name = W.Label(r, ""); r.name:SetPoint("LEFT", 0, 0); r.name:SetWidth(300)
  -- "Restablecer nombre/logo" needs ~180 px
  r.reset = W.Button(r, L.S_RESET_LOGO, UI.SegButtonWidth({ L.S_RESET_LOGO }) - 2, 20); r.reset:SetPoint("RIGHT", 0, 0)
  r.disband = W.Button(r, L.DISBAND, 120, 20); r.disband:SetPoint("RIGHT", r.reset, "LEFT", -6, 0)
  return r
end
-- Bandas: RL list (guild characters, one per line), officers may edit other rosters, useful-classes table
local function listEdit(f, x, y, w, h, label, field, max, maxLen, norm)
  local lb = W.Label(f, label); lb:SetPoint("TOPLEFT", x, y)
  lb:SetWidth(w); if lb.SetWordWrap then lb:SetWordWrap(false) end   -- no overlap
  local sf = W.Create("ScrollFrame", f, { "UIPanelScrollFrameTemplate", "ScrollFrameTemplate" })
  sf:SetPoint("TOPLEFT", x + 2, y - 18); sf:SetSize(w, h)
  if not sf.SetBackdrop then W.Backdrop(sf, 0, 0, 0, 0.6, 0.4, 0.4, 0.4) end
  local eb = CreateFrame("EditBox", nil, sf)
  eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal); eb:SetWidth(w - 10); eb:SetAutoFocus(false); eb:SetMaxLetters(1500)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnTextChanged", function(self, user)
    if user == false or not st.draft or not isGM() then return end
    local list = {}
    for part in (self:GetText() or ""):gmatch("[^,\r\n]+") do
      part = part:gsub("^%s+", ""):gsub("%s+$", "")
      if norm then part = norm(part) end
      if part and part ~= "" and #list < max then list[#list + 1] = part:sub(1, maxLen) end
    end
    if table.concat(list, "\n") ~= table.concat(st.draft[field] or {}, "\n") then draft()[field] = list; markDirty() end
  end)
  sf:SetScrollChild(eb)
  eb.listField = field
  return ctl(eb)
end
local function buildRaids(f)
  st.rlList = listEdit(f, 12, -6, 250, 120, L.S_RL_LIST, "rlList", 20, 48, function(n) return (ns.charKey or ns.fullName)(n) end)
  check(f, 8, -160, L.S_OFF_EDIT, "offEdit")
  st.rutil = listEdit(f, 300, -6, 360, 120, L.S_RUTIL, "rutil", 30, 60, nil)
  local n = W.Label(f, L.S_RAIDS_NOTE); n:SetPoint("TOPLEFT", 12, -196); n:SetWidth(640); n:SetTextColor(0.7, 0.7, 0.7)
  if n.SetJustifyH then n:SetJustifyH("LEFT") end
end
local function buildMod(f)
  local bw = W.Label(f, L.S_BANNED_LINES); bw:SetPoint("TOPLEFT", 12, -6)
  local sf = W.Create("ScrollFrame", f, { "UIPanelScrollFrameTemplate", "ScrollFrameTemplate" })
  sf:SetPoint("TOPLEFT", 14, -24); sf:SetSize(330, 110)
  if not sf.SetBackdrop then W.Backdrop(sf, 0, 0, 0, 0.6, 0.4, 0.4, 0.4) end
  local eb = CreateFrame("EditBox", nil, sf)
  eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal); eb:SetWidth(320); eb:SetAutoFocus(false); eb:SetMaxLetters(1200)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnTextChanged", function(self, user)
    if user == false or not st.draft or not isGM() then return end
    local list = {}
    for part in (self:GetText() or ""):gmatch("[^,\r\n]+") do
      part = part:gsub("^%s+", ""):gsub("%s+$", ""); if part ~= "" and #list < 50 then list[#list + 1] = part:sub(1, 24) end
    end
    if table.concat(list, "\n") ~= table.concat(st.draft.banned or {}, "\n") then draft().banned = list; markDirty() end
  end)
  sf:SetScrollChild(eb)
  st.banned = ctl(eb)
  local dl = W.Label(f, L.S_DATA, "GameFontNormal"); dl:SetPoint("TOPLEFT", 370, -6)
  local ex = W.IconButton(f, 30, ICONS .. "INV_Misc_Note_01", L.EXPORT, L.EXPORT_TIP, function() SlashCmdList.GUILDSQUADS("export") end)
  ex:SetPoint("TOPLEFT", 370, -26)
  local im = W.IconButton(f, 30, ICONS .. "INV_Letter_15", L.IMPORT, L.IMPORT_TIP, function() SlashCmdList.GUILDSQUADS("import") end)
  im:SetPoint("LEFT", ex, "RIGHT", 8, 0)
  local sy = W.IconButton(f, 30, ICONS .. "Spell_Nature_Lightning", L.SYNC_NOW, L.SYNC_TIP, function() SlashCmdList.GUILDSQUADS("sync") end)
  sy:SetPoint("LEFT", im, "RIGHT", 8, 0)
  -- short text labels under the Data icons
  for _, pair in ipairs({ { ex, L.S_DATA_EXPORT }, { im, L.S_DATA_IMPORT }, { sy, L.S_DATA_SYNC } }) do
    local t = W.Label(f, pair[2], "GameFontHighlightSmall"); t:SetPoint("TOP", pair[1], "BOTTOM", 0, -2)
  end
  local ml = W.Label(f, L.S_MOD_SQUADS, "GameFontNormal"); ml:SetPoint("TOPLEFT", 12, -148)
  st.modRows = {}
  for i = 1, 8 do st.modRows[i] = modRow(f, i) end
  st.modMore = W.Label(f, ""); st.modMore:SetPoint("TOPLEFT", 16, -364); st.modMore:SetTextColor(0.6, 0.6, 0.6)
end

-- Celebraciones (GM): guild-chat announcements on/off, what (puesto 1 / Top 3 / cualquier entrada), squad
-- achievements. One client announces each event; 1 message / 10 s; never during an encounter.
local function buildCel(f)
  check(f, 8, -4, L.S_CEL_ON, "celOn")
  seg(f, 12, -40, L.S_CEL_SCOPE, "celScope", { "first", "top3", "any" }, function(v) return L["S_CEL_" .. v] end)
  check(f, 8, -72, L.S_CEL_SQUAD, "celSquad")
  local n = W.Label(f, L.S_CEL_NOTE); n:SetPoint("TOPLEFT", 12, -110); n:SetWidth(640); n:SetTextColor(0.7, 0.7, 0.7)
  st.celAdopt = W.Label(f, "", "GameFontNormal"); st.celAdopt:SetPoint("TOPLEFT", 12, -170)
end

-- Contenido: the learned boss catalog; the GM marks the final boss of each instance ("jefe final")
local CONTENT_ROWS = 10
local function buildContent(f)
  local t = W.Label(f, L.S_CONTENT_TITLE, "GameFontNormal"); t:SetPoint("TOPLEFT", 12, -6)
  local n = W.Label(f, L.S_CONTENT_NOTE); n:SetPoint("TOPLEFT", 12, -24); n:SetWidth(640); n:SetTextColor(0.7, 0.7, 0.7)
  st.bossRows, st.bossOff = {}, 0
  for i = 1, CONTENT_ROWS do
    local r = CreateFrame("Frame", nil, f); r:SetSize(660, 24); r:SetPoint("TOPLEFT", 12, -50 - (i - 1) * 26)
    r.inst = W.Label(r, ""); r.inst:SetPoint("LEFT", 0, 0); r.inst:SetWidth(220)
    r.name = W.Label(r, ""); r.name:SetPoint("LEFT", 230, 0); r.name:SetWidth(260)
    r.final = W.Check(r, L.S_FINAL_BOSS, function(self)
      if not isGM() or not r.boss then self:SetChecked(r.boss and r.boss.final or false); return end
      local on = not r.boss.final -- toggle the stored state (the checkbox only shows it)
      self:SetChecked(r.boss.final or false)
      W.Confirm(L.S_FINAL_CONFIRM:format(r.boss.name or r.boss.id), function()
        if ns.HallGlue then ns.HallGlue.SetFinal(r.boss.id, on) end
        settingsRefresh(nil, nil, true)
      end)
    end)
    r.final:SetPoint("LEFT", 500, 0)
    st.bossRows[i] = r
  end
  st.bossEmpty = W.Label(f, L.S_CONTENT_EMPTY); st.bossEmpty:SetPoint("TOPLEFT", 16, -56); st.bossEmpty:SetTextColor(0.6, 0.6, 0.6)
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta)
    st.bossOff = math.max(0, st.bossOff - delta); settingsRefresh(nil, nil, true)
  end)
end

local function contentRefresh()
  local list = ns.Content.bossList()
  st.bossOff = math.min(st.bossOff or 0, math.max(0, #list - CONTENT_ROWS))
  local gm = isGM()
  for i, r in ipairs(st.bossRows) do
    local b = list[st.bossOff + i]
    r.boss = b
    if b then
      local e = ns.Content.get(b.inst)
      r.inst:SetText(e and e.name or b.inst)
      r.name:SetText((b.name or "?") .. (b.enc and (" |cff888888#" .. b.enc .. "|r") or ""))
      r.final:SetChecked(b.final and true or false); setEnabled(r.final, gm)
      r:Show()
    else r:Hide() end
  end
  st.bossEmpty:SetShown(#list == 0)
  if ns.HallGlue then
    local x, y = ns.HallGlue.Adoption()
    st.celAdopt:SetText(L.ADOPTION:format(x, y))
    if st.adopt then st.adopt:SetText(L.ADOPTION:format(x, y)) end
  end
end

local function showSection(key)
  if key == "ach" and not isGM() then key = "squads" end   -- Logros is GM only
  st.cur = key
  for _, k in ipairs(SECTIONS) do
    st.sec[k]:SetShown(k == key)
    local b = st.secBtn[k]
    b:SetText(L["S_TAB_" .. k])
    W.SetSelected(b, k == key)
  end
end
UI.SettingsSection = function(key) if key then showSection(key) end; return st.cur end

UI.Register("settings", L.TAB_SETTINGS, function(f, bar)
  st.bar = bar
  local row = {}
  for _, k in ipairs(SECTIONS) do
    local b = W.Button(f, L["S_TAB_" .. k], UI.SEC_W, 22, function() showSection(k) end)
    st.secBtn[k] = b; row[#row + 1] = b
    local fr = CreateFrame("Frame", nil, f); fr:SetPoint("TOPLEFT", 0, -36); fr:SetPoint("BOTTOMRIGHT", 0, 0); fr:Hide()
    st.sec[k] = fr
  end
  UI.TopRow(f, row, 3, -8)
  buildRaids(st.sec.raids)
  buildSquads(st.sec.squads); buildComp(st.sec.comp); buildSeason(st.sec.season); buildInteg(st.sec.integ); buildMod(st.sec.mod)
  buildCel(st.sec.cel); buildContent(st.sec.content)
  if UI.BuildCatalog then UI.BuildCatalog(st.sec.ach) end   -- Ajustes > Logros (UI/Catalog.lua)
  st.ro = W.Label(bar, L.S_READONLY, "GameFontNormal"); st.ro:SetPoint("RIGHT", bar, "RIGHT", -180, 2); st.ro:SetTextColor(1, 0.5, 0.3)
  st.primary = W.Primary(bar, L.SAVE_SHARE, function() UI.SaveSettingsNow() end)
  showSection("squads")
end, function(f, bar) return settingsRefresh(f, bar) end, function() return ns.rosterReady and P.inGuild(ns.roster, ns.me()) and true or false end,
{ icon = ICONS .. "INV_Misc_Gear_01",
  beforeLeave = function(nextKey)
    if not (st.dirty and isGM()) then return false end
    W.Confirm(L.S_UNSAVED, function() st.dirty = false; st.draft = nil; UI.Select(nextKey, true) end, L.DISCARD, L.KEEP_EDITING)
    return true
  end,
  onHide = function() if st.dirty and isGM() then ns.print(L.S_UNSAVED_BAR) end end })

-- build a settings record from the draft (+ extra fields) and publish it. GM only (validated again on receipt).
function UI.SaveSettingsNow(extra)
  if not isGM() then return false end
  local s = copyDeep(st.draft or settings())
  s.seasonKind = "weekly"
  for k, v in pairs(extra or {}) do s[k] = v end
  M.normalizeSettings(s)
  if A.SaveSettings(s) then
    st.dirty = false; st.draft = nil
    ns.print(L.S_SAVED)
    return true
  end
  return false
end

-- Ajustes > Temporada popup (kept for /gsq compatibility): name, start, end (realm time "YYYY-MM-DD HH:MM")
local se = {}
function UI.OpenSeasonEditor()
  if not se.box then
    local box = CreateFrame("Frame", "GuildSquadsSeasonFrame", UIParent)
    box:SetSize(420, 200); box:SetPoint("CENTER"); box:SetFrameStrata("FULLSCREEN_DIALOG")
    box:EnableMouse(true)
    W.Backdrop(box, 0, 0, 0, 0.95, 0.6, 0.6, 0.6)
    local t = W.Label(box, L.S_SEASON_TITLE, "GameFontNormal"); t:SetPoint("TOPLEFT", 12, -10)
    local close = W.Create("Button", box, { "UIPanelCloseButton" }); close:SetSize(24, 24); close:SetPoint("TOPRIGHT", 2, 2)
    if not close:GetScript("OnClick") then close:SetScript("OnClick", function() box:Hide() end) end
    local function row(label, y)
      local l = W.Label(box, label); l:SetPoint("TOPLEFT", 16, y - 4)
      local e = W.Edit(box, 220, 24); e:SetPoint("TOPLEFT", 170, y)
      return e
    end
    se.name = row(L.S_SEASON_NAME, -40)
    se.start = row(L.S_SEASON_START, -70)
    se.stop = row(L.S_SEASON_END, -100)
    se.err = W.Label(box, "", "GameFontHighlightSmall"); se.err:SetPoint("TOPLEFT", 16, -130); se.err:SetTextColor(1, 0.3, 0.3)
    se.save = W.Button(box, L.SAVE_SETTINGS, 120, 22, function()
      local st0 = Pr.parseDate(se.start:GetText() or "")
      local txt = se.stop:GetText() or ""
      local sp = (txt:match("^%s*$") and 0) or Pr.parseDate(txt)
      if not st0 or not sp or (sp > 0 and sp <= st0) then se.err:SetText(L.S_SEASON_BAD); return end
      se.err:SetText("")
      if UI.SaveSettingsNow({ seasonName = (se.name:GetText() or ""):sub(1, 24), seasonStart = st0, seasonEnd = sp }) then box:Hide() end
    end)
    se.save:SetPoint("BOTTOMRIGHT", -12, 12)
    se.new = W.Button(box, L.S_SEASON_NEW, 150, 22, function()
      W.Confirm(L.S_SEASON_NEW_CONFIRM, function()
        local now = (GetServerTime and GetServerTime()) or 0
        if UI.SaveSettingsNow(Pr.newSeason(settings(), now, "")) then box:Hide() end
      end)
    end)
    se.new:SetPoint("BOTTOMLEFT", 12, 12)
    se.box = box
  end
  local s = settings()
  se.name:SetText(s.seasonName or "")
  se.start:SetText(Pr.formatDate(s.seasonStart or Pr.DEFAULT_SEASON_START))
  se.stop:SetText((s.seasonEnd or 0) > 0 and Pr.formatDate(s.seasonEnd) or "")
  se.err:SetText("")
  se.box:Show()
end
function UI.SeasonEditorState() return se end
function UI.SettingsState() return st end

-- keepDraft: re-render controls from the current draft (after a local edit) instead of reloading the record
settingsRefresh = function(f, bar, keepDraft)
  if not (st.dirty or keepDraft) or not st.draft then st.draft = copyDeep(settings()); st.dirty = false end
  local s = st.draft
  local gm = isGM()
  for _, c in ipairs(st.ctl) do setEnabled(c, gm) end
  st.primary:SetEnabled(gm); st.ro:SetShown(not gm)
  for _, c in ipairs(st.ctl) do if c.field then
    local v = s[c.field]; if c.invert then v = not v end
    c:SetChecked(v ~= false and v ~= nil)
  end end
  for _, sgm in ipairs(st.seg) do sgm:Update() end
  local n = numRanks()
  local mr = math.max(0, math.min(n - 1, tonumber(s.minCreateRank) or 9))
  st.minRank:SetText(mr .. " · " .. rankName(mr))
  local isOff = {}
  for _, r in ipairs(s.officerRanks or {}) do isOff[r] = true end
  for i, c in ipairs(st.officers) do c:SetShown(i < n); c.label:SetText(rankName(i)); c:SetChecked(isOff[i] or false) end
  if not keepDraft then
    st.banned:SetText(table.concat(s.banned or {}, "\n"))
    st.rlList:SetText(table.concat(s.rlList or {}, "\n"))
    local util = (type(s.rutil) == "table" and #s.rutil > 0) and s.rutil or (ns.Roster and ns.Roster.utilStrings() or {})
    st.rutil:SetText(table.concat(util, "\n"))
    st.seasonName:SetText(s.seasonName or "")
  end
  st.dStart:Update(); st.dEnd:Update()
  contentRefresh()
  -- Ajustes > Logros exists only for the GM
  if st.secBtn.ach then st.secBtn.ach:SetShown(gm) end
  if st.cur == "ach" and not gm then showSection("squads") end
  if gm and UI.CatalogRefresh then UI.CatalogRefresh() end
  local cfg = Pr.seasonCfg(s)
  for i, l in ipairs(st.past) do
    local p = cfg.past[i]
    l:SetText(p and UI.TemporadaLabel and UI.TemporadaLabel(p, #cfg.past + 1 - i) or (i == 1 and L.S_NO_PAST or ""))
  end
  -- moderation list (GM and officers)
  local mod = isMod()
  local ids = activeSquads()
  for i, r in ipairs(st.modRows) do
    local id = ids[i]
    if id then
      local d = ns.state.squads[id].d
      r.name:SetText(d.name .. "  |cff999999" .. ns.shortName(d.captain) .. "|r")
      r.disband:SetEnabled(mod); r.reset:SetEnabled(mod)
      r.disband:SetScript("OnClick", function()
        if not isMod() then return end
        W.Confirm(L.S_CONFIRM_MOD_DISBAND:format(d.name), function()
          local _, why = A.EditSquad(id, function(x) x.disbanded = true end); err(why)
        end)
      end)
      r.reset:SetScript("OnClick", function()
        if not isMod() then return end
        W.Confirm(L.S_CONFIRM_RESET:format(d.name), function()
          local _, why = A.EditSquad(id, function(x) x.name = M.resetName(id); x.icon, x.color, x.border, x.motto = 1, 1, 1, "" end); err(why)
        end)
      end)
      r:Show()
    else r:Hide() end
  end
  st.modMore:SetText(#ids > #st.modRows and L.S_MOD_MORE:format(#ids - #st.modRows) or (#ids == 0 and L.EMPTY_SQUADS or ""))
  bar = bar or st.bar
  if st.dirty then bar.status:SetText("|cffff9933" .. L.S_UNSAVED_BAR .. "|r")
  else
    local rec = ns.state.settings
    local now = (GetServerTime and GetServerTime()) or 0
    bar.status:SetText(rec and L.SETTINGS_FOOT:format(rec.sq or 0, L.MINUTES:format(math.max(0, math.floor((now - rec.ts) / 60)))) or "")
  end
end

-------------------------------------------------------------------------------
-- Crear squad (2 steps) · also "Editar squad" (step 1) and "Cambiar escudo" (step 2)
local cr = { tags = {} }
local function crTags()
  local out = {}
  for _, g in ipairs(M.GOALS) do if cr.tags[g] then out[#out + 1] = g end end
  return out
end
local function crValidate()
  local name = cr.name:GetText() or ""
  local ok, why = M.checkName(name, settings())
  local exceptId = cr.mode ~= "new" and A.MySquadId() or nil
  if ok and M.nameTaken(ns.state, name, exceptId) then ok, why = false, "nameTaken" end
  cr.err:SetText(ok and "" or ns.ErrText(why))
  return ok, why
end
local function crPreview()
  cr.prevLogo:SetLogo(cr.icon, cr.color, cr.border)
  cr.prevName:SetText(cr.name:GetText() or "")
  cr.prevMotto:SetText(cr.motto:GetText() or "")
  cr.prevChips:SetKeys(crTags())
  local fake = { needs = { TANK = 1, HEALER = 1, DAMAGER = 2 }, profiles = { { role = "DAMAGER" } }, count = 1 }
  fillSquadCard(cr.card, { id = "preview", d = { name = cr.name:GetText() or "", motto = cr.motto:GetText(), icon = cr.icon,
    color = cr.color, border = cr.border, tags = crTags(), open = cr.open:GetChecked() and true or false, captain = ns.me() or "?" },
    ctx = fake, score = 0, reasons = {} })
  for i, b in ipairs(cr.iconBtns) do b:SetChecked(i == cr.icon) end
  for i, b in ipairs(cr.colorBtns) do b.sel.show(i == cr.color) end
  for i, b in ipairs(cr.borderBtns) do b.sel.show(i == cr.border); b.logo:SetLogo(cr.icon, cr.color, i) end
end
local function crStep(n)
  cr.step = n
  cr.s1:SetShown(n == 1); cr.s2:SetShown(n == 2)
  cr.dot1.bg:SetColorTexture(n == 1 and 1 or 0.2, n == 1 and 0.82 or 0.6, n == 1 and 0 or 0.2, 1)
  cr.dot1.text:SetText(n == 1 and "1" or W.Icon(CHECK, 12))
  cr.dot2.bg:SetColorTexture(n == 2 and 1 or 0.3, n == 2 and 0.82 or 0.3, n == 2 and 0 or 0.3, 1)
  cr.back:SetShown(n == 2 and cr.mode == "new")
  local label = (n == 1 and cr.mode == "new" and L.NEXT) or (cr.mode == "logo" and L.SAVE_LOGO) or (cr.mode == "edit" and L.SAVE_SQUAD)
                or L.CREATE_SQUAD
  cr.primary:SetText(label)
  -- the disabled "Next" says why (same text as the inline error)
  if n == 1 then
    local ok, why = crValidate()
    cr.primary:SetEnabled(ok and true or false)
    W.Tooltip(cr.primary, (not ok) and L.WHY_DISABLED or nil, (not ok) and ns.ErrText(why) or nil)
  else cr.primary:SetEnabled(true); W.Tooltip(cr.primary, nil) end
  crPreview()
end

function UI.CreateState() return cr end
function UI.OpenCreate(mode)
  cr.mode = mode or "new"
  cr.pendingInit = true
  UI.Open("create")
end

local function dot(parent, n, label, x)
  local d = CreateFrame("Frame", nil, parent); d:SetSize(20, 20); d:SetPoint("TOPLEFT", x, -8)
  d.bg = d:CreateTexture(nil, "ARTWORK"); d.bg:SetAllPoints(); W.Round(d, d.bg)
  d.text = W.Label(d, tostring(n), "GameFontHighlightSmall"); d.text:SetPoint("CENTER")
  local l = W.Label(parent, label, "GameFontNormal"); l:SetPoint("LEFT", d, "RIGHT", 6, 0)
  return d
end

UI.Register("create", L.CREATE_SQUAD, function(f, bar)
  cr.dot1 = dot(f, 1, L.STEP1, UI.SAFE_X); cr.dot2 = dot(f, 2, L.STEP2, UI.SAFE_X + 260)
  -- step 1
  local s1 = CreateFrame("Frame", nil, f); s1:SetPoint("TOPLEFT", 0, -40); s1:SetPoint("BOTTOMRIGHT"); cr.s1 = s1
  local nl = W.Label(s1, L.NAME, "GameFontNormal"); nl:SetPoint("TOPLEFT", 16, -10)
  cr.name = W.Edit(s1, 260, 24); cr.name:SetPoint("TOPLEFT", 20, -28)
  local onName = function()
    if cr.ready and cr.step == 1 then
      local ok, why = crValidate()
      cr.primary:SetEnabled(ok and true or false)
      W.Tooltip(cr.primary, (not ok) and L.WHY_DISABLED or nil, (not ok) and ns.ErrText(why) or nil)
      crPreview()
    end
  end
  if cr.name.HookScript then cr.name:HookScript("OnTextChanged", onName) else cr.name:SetScript("OnTextChanged", onName) end
  cr.err = W.Label(s1, ""); cr.err:SetPoint("TOPLEFT", 20, -52); cr.err:SetTextColor(1, 0.3, 0.3)
  local ml = W.Label(s1, L.MOTTO, "GameFontNormal"); ml:SetPoint("TOPLEFT", 16, -76)
  cr.motto = W.Edit(s1, 400, 60); cr.motto:SetPoint("TOPLEFT", 20, -94)
  local tl = W.Label(s1, L.TAGS_LABEL, "GameFontNormal"); tl:SetPoint("TOPLEFT", 16, -130)
  cr.tagMax = W.Label(s1, L.TAGS_MAX); cr.tagMax:SetPoint("LEFT", tl, "RIGHT", 10, 0); cr.tagMax:SetTextColor(0.6, 0.6, 0.6)
  cr.tagChips = {}
  local prev
  for i, g in ipairs(M.GOALS) do
    local c = W.Chip(s1, g, function(self, on)
      if on and #crTags() >= M.MAX_TAGS then self:SetOn(false); cr.tagMax:SetTextColor(1, 0.3, 0.3); return end
      cr.tagMax:SetTextColor(0.6, 0.6, 0.6)
      cr.tags[self.key] = on or nil; crPreview()
    end, { big = true })
    if prev then c:SetPoint("LEFT", prev, "RIGHT", 6, 0) else c:SetPoint("TOPLEFT", 20, -150) end
    cr.tagChips[i] = c; prev = c
  end
  cr.open = W.Check(s1, L.OPEN); cr.open:SetPoint("TOPLEFT", 16, -190)
  -- step 2 (LogoPicker)
  local s2 = CreateFrame("Frame", nil, f); s2:SetPoint("TOPLEFT", 0, -36); s2:SetPoint("BOTTOMRIGHT"); cr.s2 = s2
  local pv = CreateFrame("Frame", nil, s2); pv:SetPoint("TOPLEFT", 8, -4); pv:SetSize(228, 386)
  local pbg = pv:CreateTexture(nil, "BACKGROUND"); pbg:SetAllPoints(); pbg:SetColorTexture(0.06, 0.05, 0.04, 1)
  local pt = W.Label(pv, L.PREVIEW, "GameFontNormal"); pt:SetPoint("TOP", 0, -6)
  cr.prevLogo = W.Logo(pv, 112); cr.prevLogo:SetPoint("TOP", 0, -26)
  cr.prevName = W.Label(pv, "", "GameFontNormalLarge"); cr.prevName:SetPoint("TOP", 0, -146)
  cr.prevMotto = W.Label(pv, "", "GameFontDisableSmall"); cr.prevMotto:SetPoint("TOP", 0, -168)
  cr.prevChips = W.ChipRow(pv, 3); cr.prevChips:SetPoint("TOPLEFT", pv, "TOPLEFT", 10, -188)
  local pl = W.Label(pv, L.PREVIEW_LIST); pl:SetPoint("TOPLEFT", 6, -222); pl:SetTextColor(0.6, 0.6, 0.6)
  local cardHolder = CreateFrame("Frame", nil, pv); cardHolder:SetSize(335, 112); cardHolder:SetPoint("TOPLEFT", 4, -240)
  cardHolder:SetScale(0.65)
  cr.card = makeSquadCard(cardHolder); cr.card:SetSize(335, 112); cr.card:SetPoint("TOPLEFT"); cr.card:EnableMouse(false)
  local il = W.Label(s2, L.ICON, "GameFontNormal"); il:SetPoint("TOPLEFT", 248, -4)
  cr.iconBtns = {}
  for i = 1, #Logo.ICONS do
    local b = W.IconToggle(s2, 32, Logo.ICONS[i], nil, function() cr.icon = i; crPreview() end)
    b:SetPoint("TOPLEFT", 248 + ((i - 1) % 12) * 34, -20 - math.floor((i - 1) / 12) * 34)
    cr.iconBtns[i] = b
  end
  local rowsY = -20 - math.ceil(#Logo.ICONS / 12) * 34 - 10
  local cl = W.Label(s2, L.COLOR, "GameFontNormal"); cl:SetPoint("TOPLEFT", 248, rowsY)
  cr.colorBtns = {}
  for i, c in ipairs(Logo.COLORS) do
    local b = CreateFrame("Button", nil, s2); b:SetSize(26, 26); b:SetPoint("TOPLEFT", 248 + (i - 1) * 32, rowsY - 18)
    local t = b:CreateTexture(nil, "ARTWORK"); t:SetAllPoints(); t:SetColorTexture(c[1], c[2], c[3], 1)
    b.sel = W.Border(b, 2, 1, 0.82, 0, 1)
    b:SetScript("OnClick", function() cr.color = i; crPreview() end)
    cr.colorBtns[i] = b
  end
  local bl = W.Label(s2, L.BORDER, "GameFontNormal"); bl:SetPoint("TOPLEFT", 248, rowsY - 56)
  cr.borderBtns = {}
  for i = 1, #Logo.BORDERS do
    local b = CreateFrame("Button", nil, s2); b:SetSize(90, 40); b:SetPoint("TOPLEFT", 248 + (i - 1) * 96, rowsY - 74)
    b.logo = W.Logo(b, 34); b.logo:SetPoint("LEFT", 2, 0); b.logo:EnableMouse(false)
    b.text = W.Label(b, L["BORDER_" .. i]); b.text:SetPoint("LEFT", b.logo, "RIGHT", 4, 0)
    b.sel = W.Border(b, 1, 1, 0.82, 0, 1)
    b:SetScript("OnClick", function() cr.border = i; crPreview() end)
    cr.borderBtns[i] = b
  end
  cr.back = W.Link(bar, L.BACK, function() crStep(1) end); cr.back:SetPoint("LEFT", 14, 2)
  cr.primary = W.Primary(bar, L.NEXT, function()
    if cr.step == 1 and not crValidate() then return end
    if cr.step == 1 and cr.mode == "new" then crStep(2); return end
    local id = A.MySquadId()
    if cr.mode == "new" then
      local ok, why = A.CreateSquad({ name = cr.name:GetText(), motto = cr.motto:GetText(), tags = crTags(), icon = cr.icon,
        color = cr.color, border = cr.border, open = cr.open:GetChecked() })
      if not ok then err(why); return end
      local sid = A.MySquadId()
      if sid and ns.state.squads[sid] and ns.state.squads[sid].d.approved == false then ns.print(L.CREATED_PENDING) end
    elseif cr.mode == "edit" and id then
      local name, motto, tags, open = cr.name:GetText(), cr.motto:GetText(), crTags(), cr.open:GetChecked() and true or false
      local _, legacy = M.splitTags(ns.state.squads[id].d.tags)
      for _, t in ipairs(legacy) do tags[#tags + 1] = t end -- keep legacy free-text tags (shown grey)
      local _, why = A.EditSquad(id, function(d) d.name = name; d.motto = motto; d.tags = tags; d.open = open end); err(why)
    elseif cr.mode == "logo" and id then
      local _, why = A.EditSquad(id, function(d) d.icon = cr.icon; d.color = cr.color; d.border = cr.border end); err(why)
    end
    UI.Select("mysquad")
  end)
  cr.ready = true
end, function()
  if cr.pendingInit or not cr.step then
    cr.pendingInit = false
    cr.mode = cr.mode or "new"
    local id = A.MySquadId()
    local d = (cr.mode ~= "new" and id and ns.state.squads[id]) and ns.state.squads[id].d or nil
    cr.icon, cr.color, cr.border = d and d.icon or 1, d and d.color or 1, d and d.border or 1
    cr.tags = {}
    for _, t in ipairs(d and M.splitTags(d.tags) or {}) do cr.tags[t] = true end
    cr.name:SetText(d and d.name or ""); cr.motto:SetText(d and d.motto or "")
    cr.open:SetChecked(d == nil or d.open == true)
    for _, c in ipairs(cr.tagChips) do c:SetOn(cr.tags[c.key] or false) end
    crStep(cr.mode == "logo" and 2 or 1)
  else
    crStep(cr.step)
  end
end, nil, { noTab = true })
