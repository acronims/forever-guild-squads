-- Guild Squads (MIT) - UI/Catalog.lua
-- Ajustes > Logros, GM only (members see the names and on/off already
-- applied in the Salón, the Ranking strip and Mis logros). Each change is written at once as an `achdef` /
-- `achgrant` record (no "Guardar y compartir"): validated again on every client by Core/Catalog.
--   * list by group (nivel, clase, raza, mazmorras, bandas, PvP, profesiones, reputación, squad, personaje): checkbox
--     on/off, Top size (open races only; a closed race explains why in the tooltip), name, state (abierta n/N ·
--     cerrada · pendiente);
--   * bulk buttons per group and global, with a confirmation that says how many records and the estimated seconds;
--   * "Nuevo logro": 4 steps (metric -> parameter -> threshold and size -> name);
--   * "Otorgar": badge, character or squad, mandatory reason; history with "Retirar".
-- Every WoW API is reached through the widget kit (UI/Widgets.lua) or guarded here.
local _, ns = ...
local L, W, UI, P, R, Cat = ns.L, ns.W, ns.UI, ns.Permissions, ns.Races, ns.Catalog
local cg = { group = "level", view = "list", off = 0 }
local ROWS = 11
local function H() return ns.HallGlue end
local function isGM() return P.isGM(ns.roster, ns.me()) and true or false end
UI.CATALOG_ROWS = ROWS

-------------------------------------------------------------------------------
-- labels
function UI.CatalogTitle(id)
  local lab = Cat.label(id)
  if lab then return lab end
  if Cat.isCustom(id) then return id end
  if Cat.isRaceId(id) and UI.RaceTitle then return UI.RaceTitle(id) end
  if UI.AchTitle then return (UI.AchTitle(id)) end
  return id
end
local function stateOf(row)
  local r = row.r
  if not row.race then return L.CAT_BADGE end
  if not r then return "|cff999999" .. L.HALL_NODATA .. "|r" end
  return UI.RaceStateText and UI.RaceStateText(r) or tostring(r.state)
end

-- rows of a group: { id, on, race, r = computed race or nil, title }
function UI.CatalogRows(group)
  local g = H()
  local races = g and g.Races() or {}
  local out = {}
  for _, id in ipairs(g and g.CatalogIds() or {}) do
    if Cat.groupOf(id) == group then
      out[#out + 1] = { id = id, on = Cat.isOn(id), race = Cat.isRaceId(id), r = races[id], title = UI.CatalogTitle(id) }
    end
  end
  return out
end
function UI.CatalogState() return cg end

-------------------------------------------------------------------------------
-- actions (each one asks the glue; errors are shown translated, once)
local function done(okW, why) if not okW and why then ns.ShowError(why) end; if UI.CatalogRefresh then UI.CatalogRefresh() end end
function UI.CatalogToggle(id, on) if not isGM() then return false end; done(H().SetOn(id, on)); return true end
function UI.CatalogSize(row)
  if not isGM() or not row.race then return false end
  if row.r and row.r.state == "closed" then ns.print(L.CAT_CLOSED_TIP); return false end
  W.Prompt(L.CAT_SIZE_PROMPT:format(UI.CatalogTitle(row.id), Cat.sizeMax(row.id, Cat.def(row.id))), function(text)
    local n = tonumber(text)
    if not n then ns.print(L.ERR_catSize); return end
    done(H().SetDef(row.id, { size = math.floor(n) }))
  end, L.CAT_OK, 3)
  return true
end
function UI.CatalogRename(row)
  if not isGM() then return false end
  W.Prompt(L.CAT_NAME_PROMPT:format(UI.CatalogTitle(row.id)), function(text)
    done(H().SetDef(row.id, { name = text or "" }))
  end, L.CAT_OK, Cat.NAME_MAX)
  return true
end
-- bulk: confirmation with N records and the estimated time (1 msg/s queue)
function UI.CatalogBulk(group, on)
  if not isGM() then return false end
  local items, secs = H().BulkPlan(group, on)
  if #items == 0 then ns.print(L.CAT_BULK_NONE); return false end
  local what = group and (L["CG_" .. group] or group) or L.CAT_ALL
  W.Confirm(L.CAT_BULK_CONFIRM:format(on and L.CAT_ON or L.CAT_OFF, what, #items, secs), function()
    local okB, n = H().Bulk(group, on)
    if okB then ns.Feedback(true, L.CAT_BULK_DONE:format(n or 0)) end
    done(okB)
  end)
  return true
end

-------------------------------------------------------------------------------
-- "Nuevo logro": metric -> parameter -> threshold and size -> name (menus anchored to the button + one prompt)
local function sizes(spec)
  if spec.metric == "level" and (spec.param or "") == "" then return { 1, 3, 5, 10, 25, 50, 100 } end
  return { 1, 3, 5, 10 }
end
local function sortedKeys(t) local o = {} for k in pairs(t) do o[#o + 1] = k end table.sort(o) return o end
local function seenKeys(kind)   -- keys reported in the observations we hold (professions / factions / BG maps)
  local out = {}
  local store = H().Store and H().Store()
  for _, ev in pairs(store and store.obs or {}) do
    if kind == "bg" and ev.t == "bg" and ev.inst then out[R.slug(ev.inst)] = true
    elseif ev.t == "cnt" and ev.k == kind and ev.key then out[R.slug(ev.key)] = true end
  end
  return out
end
local function paramItems(spec, nextStep)
  local items = {}
  local function add(text, param) items[#items + 1] = { text = text, func = function() spec.param = param; nextStep() end } end
  if spec.metric == "level" then
    add(L.CAT_P_ANY, "")
    local classes = {}
    for _, r in pairs(ns.rosterList and ns.rosterList() or {}) do if type(r.class) == "string" then classes[r.class] = true end end
    for _, c in ipairs(sortedKeys(classes)) do add(L.CAT_P_CLASS:format(UI.ClassName and UI.ClassName(c) or c), "class:" .. c) end
    for _, rc in ipairs(sortedKeys(R.RACE_OK)) do
      if #items < 30 then add(L.CAT_P_RACE:format(rc:sub(1, 1) .. rc:sub(2):lower()), "race:" .. rc) end
    end
  elseif spec.metric == "boss" then
    for _, b in ipairs(ns.Content.bossList and ns.Content.bossList() or {}) do
      if #items < 30 then
        local e = ns.Content.get(b.inst)
        add((e and e.name or b.inst) .. " · " .. (b.name or b.id), b.id)
      end
    end
  elseif spec.metric == "bg" then
    add(L.CAT_P_ANYMAP, "")
    for _, m in ipairs(sortedKeys(seenKeys("bg"))) do if #items < 30 then add((m:gsub("_", " ")), m) end end
  elseif spec.metric == "prof" or spec.metric == "rep" then
    local keys = seenKeys(spec.metric)
    local white = spec.metric == "prof" and R.PROF_OK or R.REP_OK
    for _, k in ipairs(sortedKeys(keys)) do if #items < 30 then add((k:gsub("_", " ")), k) end end
    for _, k in ipairs(sortedKeys(white)) do if not keys[k] and #items < 30 then add((k:gsub("_", " ")), k) end end
  elseif spec.metric == "manual" then
    items[#items + 1] = { text = L.CAT_SCOPE_char, func = function() spec.scope = "char"; nextStep() end }
    items[#items + 1] = { text = L.CAT_SCOPE_squad, func = function() spec.scope = "squad"; nextStep() end }
  end
  return items
end
local function thrValues(spec)
  if spec.metric == "level" then return R.LEVELS end
  if spec.metric == "bg" then return { 1, 5, 10, 25, 50, 100 } end
  if spec.metric == "prof" then return { 75, 150, 225, 300 } end
  return nil
end
function UI.CatalogWizard(owner)
  if not isGM() then return false end
  if Cat.countCustom(Cat.defs()) >= Cat.MAX_CUSTOM then ns.ShowError("maxCustom"); return false end
  local spec = {}
  local function step4()
    W.Prompt(L.CAT_W4, function(text)
      spec.name = text
      local id, why = H().CreateCustom(spec)
      if id then ns.Feedback(true, L.CAT_CREATED:format(Cat.label(id) or id)) end
      done(id and true or false, why)
    end, L.CAT_CREATE, Cat.NAME_MAX)
  end
  local function stepSize()
    if spec.metric == "manual" then return step4() end
    local items = { { text = L.CAT_W3_SIZE, title = true } }
    for _, n in ipairs(sizes(spec)) do items[#items + 1] = { text = "Top " .. n, func = function() spec.size = n; step4() end } end
    W.Menu(owner, items)
  end
  local function step3()
    if spec.metric == "rep" then spec.thr = R.EXALTED; return stepSize() end
    local vals = thrValues(spec)
    if not vals then return stepSize() end
    local items = { { text = L["CAT_W3_" .. spec.metric] or L.CAT_W3, title = true } }
    for _, v in ipairs(vals) do items[#items + 1] = { text = tostring(v), func = function() spec.thr = v; stepSize() end } end
    W.Menu(owner, items)
  end
  local function step2()
    local items = paramItems(spec, step3)
    if #items == 0 then ns.print(L.CAT_W2_EMPTY); return end
    table.insert(items, 1, { text = L.CAT_W2, title = true })
    W.Menu(owner, items)
  end
  local items = { { text = L.CAT_W1, title = true } }
  for _, m in ipairs(Cat.METRICS) do
    items[#items + 1] = { text = L["CAT_M_" .. m], func = function() spec.metric = m; step2() end }
  end
  W.Menu(owner, items)
  return true
end

-------------------------------------------------------------------------------
-- "Otorgar": badge -> character or squad -> reason -> confirm
local function badgeList()
  local out = {}
  for _, b in ipairs(Cat.badges()) do if b.scope ~= "guild" and Cat.isOn(b.key) then out[#out + 1] = b end end
  for id, rec in pairs(Cat.defs()) do
    if Cat.isCustom(id) and rec.d.metric == "manual" and rec.d.on ~= false then out[#out + 1] = { key = id, scope = rec.d.scope or "char" } end
  end
  return out
end
function UI.CatalogGrantFlow(owner)
  if not isGM() then return false end
  local function reason(b, who, label)
    W.Prompt(L.CAT_GRANT_REASON:format(UI.CatalogTitle(b.key), label), function(text)
      if type(text) ~= "string" or text:gsub("%s", "") == "" then ns.print(L.ERR_reason); return end
      W.Confirm(L.CAT_GRANT_CONFIRM:format(UI.CatalogTitle(b.key), label, text), function()
        local okG, why = H().Grant(b.key, who, text)
        if okG then ns.Feedback(true, L.CAT_GRANTED_FB) end
        done(okG, why)
      end)
    end, L.CAT_OK, 80)
  end
  local function pickWho(b)
    if b.scope == "squad" then
      local items = { { text = L.CAT_GRANT_SQUAD, title = true } }
      for sid, r in pairs(ns.state.squads or {}) do
        if not r.d.disbanded and #items < 30 then
          items[#items + 1] = { text = r.d.name or sid, func = function() reason(b, sid, r.d.name or sid) end }
        end
      end
      if #items < 2 then ns.print(L.CAT_W2_EMPTY); return end
      W.Menu(owner, items)
    else
      W.Prompt(L.CAT_GRANT_WHO, function(text)
        local name = (ns.charKey or ns.fullName)(((text or ""):gsub("^%s+", ""):gsub("%s+$", "")))
        if not (name and ns.roster(name)) then ns.ShowError("notGuildMember"); return end
        reason(b, name, ns.shortName(name))
      end, L.CAT_OK, 48)
    end
  end
  local items = { { text = L.CAT_GRANT_PICK, title = true } }
  for _, b in ipairs(badgeList()) do
    if #items < 40 then items[#items + 1] = { text = UI.CatalogTitle(b.key), func = function() pickWho(b) end } end
  end
  if #items < 2 then ns.print(L.CAT_BULK_NONE); return false end
  W.Menu(owner, items)
  return true
end
function UI.CatalogUngrant(rec)
  if not isGM() or not rec or rec.d.on == false then return false end
  W.Confirm(L.CAT_UNGRANT_CONFIRM:format(UI.CatalogTitle(rec.d.ach), ns.shortName(rec.d.who)), function()
    done(H().Ungrant(rec.d.ach, rec.d.who))
  end)
  return true
end

-------------------------------------------------------------------------------
-- build / refresh (called by UI/Panels.lua for the "ach" section)
local function makeRow(parent, i)
  local r = CreateFrame("Frame", nil, parent); r:SetSize(660, 24); r:SetPoint("TOPLEFT", 12, -64 - (i - 1) * 26)
  r.check = W.Check(r, "", function(self)
    if not (isGM() and r.row) then self:SetChecked(r.row and r.row.on or false); return end
    UI.CatalogToggle(r.row.id, not r.row.on)
  end)
  r.check:SetPoint("LEFT", 0, 0)
  r.name = W.Label(r, ""); r.name:SetPoint("LEFT", 28, 0); r.name:SetWidth(280)
  if r.name.SetWordWrap then r.name:SetWordWrap(false) end
  r.state = W.Label(r, "", "GameFontHighlightSmall"); r.state:SetPoint("LEFT", 314, 0); r.state:SetWidth(120)
  r.size = W.Button(r, "", 76, 20, function() if r.row then UI.CatalogSize(r.row) end end)
  r.size:SetPoint("LEFT", 440, 0)
  r.rename = W.Button(r, L.CAT_RENAME, 100, 20, function() if r.row then UI.CatalogRename(r.row) end end)
  r.rename:SetPoint("LEFT", 522, 0)
  return r
end
local function makeGrantRow(parent, i)
  local r = CreateFrame("Frame", nil, parent); r:SetSize(660, 24); r:SetPoint("TOPLEFT", 12, -64 - (i - 1) * 26)
  r.text = W.Label(r, ""); r.text:SetPoint("LEFT", 0, 0); r.text:SetWidth(540)
  if r.text.SetWordWrap then r.text:SetWordWrap(false) end
  r.undo = W.Button(r, L.CAT_UNGRANT, 100, 20, function() if r.rec then UI.CatalogUngrant(r.rec) end end)
  r.undo:SetPoint("LEFT", 552, 0)
  return r
end

function UI.BuildCatalog(f)
  cg.frame = f
  cg.groupBtn = W.Button(f, "", 130, 22, function(self)
    local items = { { text = L.CAT_GROUP, title = true } }
    for _, g in ipairs(Cat.GROUPS) do
      items[#items + 1] = { text = L["CG_" .. g], func = function() cg.group = g; cg.off = 0; cg.view = "list"; UI.CatalogRefresh() end }
    end
    W.Menu(self, items)
  end)
  cg.groupBtn:SetPoint("TOPLEFT", 12, -4)
  cg.allOn = W.Button(f, L.CAT_ALL_ON, 104, 22, function() UI.CatalogBulk(cg.group, true) end)
  cg.allOn:SetPoint("LEFT", cg.groupBtn, "RIGHT", 6, 0)
  cg.allOff = W.Button(f, L.CAT_ALL_OFF, 104, 22, function() UI.CatalogBulk(cg.group, false) end)
  cg.allOff:SetPoint("LEFT", cg.allOn, "RIGHT", 4, 0)
  cg.global = W.Button(f, L.CAT_GLOBAL, 80, 22, function(self)
    W.Menu(self, { { text = L.CAT_GLOBAL_T, title = true },
                   { text = L.CAT_ALL_ON, func = function() UI.CatalogBulk(nil, true) end },
                   { text = L.CAT_ALL_OFF, func = function() UI.CatalogBulk(nil, false) end } })
  end)
  cg.global:SetPoint("LEFT", cg.allOff, "RIGHT", 4, 0)
  cg.new = W.Button(f, L.CAT_NEW, 104, 22, function(self) UI.CatalogWizard(self) end)
  cg.new:SetPoint("LEFT", cg.global, "RIGHT", 10, 0)
  cg.grantBtn = W.Button(f, L.CAT_GRANT_TAB, 96, 22, function()
    cg.view = cg.view == "grants" and "list" or "grants"; cg.off = 0; UI.CatalogRefresh()
  end)
  cg.grantBtn:SetPoint("LEFT", cg.new, "RIGHT", 4, 0)
  cg.head = W.Label(f, "", "GameFontNormalSmall"); cg.head:SetPoint("TOPLEFT", 14, -36); cg.head:SetWidth(640)
  if cg.head.SetJustifyH then cg.head:SetJustifyH("LEFT") end
  cg.rows, cg.grows = {}, {}
  for i = 1, ROWS do cg.rows[i] = makeRow(f, i); cg.grows[i] = makeGrantRow(f, i) end
  cg.grant = W.Button(f, L.CAT_GRANT, 140, 22, function(self) UI.CatalogGrantFlow(self) end)
  cg.grant:SetPoint("TOPLEFT", 12, -64 - ROWS * 26)
  cg.empty = W.Label(f, ""); cg.empty:SetPoint("TOPLEFT", 16, -70); cg.empty:SetTextColor(0.6, 0.6, 0.6)
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta) cg.off = math.max(0, (cg.off or 0) - delta); UI.CatalogRefresh() end)
end

local function fillRow(r, row)
  r.row = row
  r.check:SetChecked(row.on)
  local legacy = (not row.on) and row.r and #(row.r.entries or {}) > 0
  r.name:SetText((row.on and "" or "|cff888888") .. row.title .. (row.on and "" or "|r") ..
                 (legacy and (" |cff888888(" .. L.LEGACY_TAG .. ")|r") or ""))
  r.state:SetText(stateOf(row))
  local closed = row.r and row.r.state == "closed"
  r.size:SetShown(row.race)
  if row.race then
    r.size:SetText("Top " .. tostring(row.r and row.r.size or Cat.sizeMax(row.id, Cat.def(row.id))))
    if r.size.SetEnabled then pcall(r.size.SetEnabled, r.size, not closed) end
    W.Tooltip(r.size, L.CAT_SIZE_T, closed and L.CAT_CLOSED_TIP or L.CAT_SIZE_TIP:format(Cat.sizeMax(row.id, Cat.def(row.id))))
  end
  W.Tooltip(r.check, row.title, row.on and L.CAT_ON_TIP or L.CAT_OFF_TIP)
  r:Show()
end
local function grantLine(rec)
  local d = rec.d
  local who = (ns.state.squads and ns.state.squads[d.who] and ns.state.squads[d.who].d.name) or ns.shortName(d.who)
  local line = UI.CatalogTitle(d.ach) .. " · " .. who .. " · " .. (d.reason or "") .. " · " ..
               (ns.Progress and ns.Progress.formatDate(rec.ts) or tostring(rec.ts))
  if d.on == false then line = "|cff888888" .. line .. " (" .. L.CAT_WITHDRAWN .. ")|r" end
  return line
end

function UI.CatalogRefresh()
  if not cg.frame then return end
  local gm = isGM()
  for _, b in ipairs({ cg.groupBtn, cg.allOn, cg.allOff, cg.global, cg.new, cg.grantBtn, cg.grant }) do
    if b.SetEnabled then pcall(b.SetEnabled, b, gm) end
  end
  cg.groupBtn:SetText(L.CAT_GROUP .. ": " .. (L["CG_" .. cg.group] or cg.group))
  W.SetSelected(cg.grantBtn, cg.view == "grants")
  local n, custom, grants, off = Cat.stats()
  cg.head:SetText(L.CAT_HEAD:format(n, custom, Cat.MAX_CUSTOM, grants, off))
  if cg.view == "grants" then
    local list = Cat.grantHistory()
    cg.off = math.min(cg.off or 0, math.max(0, #list - ROWS))
    for i, r in ipairs(cg.rows) do r:Hide() end
    for i, r in ipairs(cg.grows) do
      local rec = list[cg.off + i]
      r.rec = rec
      if rec then r.text:SetText(grantLine(rec)); r.undo:SetShown(rec.d.on ~= false and gm); r:Show() else r:Hide() end
    end
    cg.grant:Show()
    cg.empty:SetText(#list == 0 and L.CAT_GRANTS_EMPTY or ""); cg.empty:SetShown(#list == 0)
    return
  end
  cg.grant:Hide()
  for _, r in ipairs(cg.grows) do r:Hide() end
  local rows = UI.CatalogRows(cg.group)
  cg.off = math.min(cg.off or 0, math.max(0, #rows - ROWS))
  for i, r in ipairs(cg.rows) do
    local row = rows[cg.off + i]
    if row then fillRow(r, row) else r.row = nil; r:Hide() end
  end
  cg.empty:SetText(#rows == 0 and L.CAT_EMPTY or ""); cg.empty:SetShown(#rows == 0)
end
