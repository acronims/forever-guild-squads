-- context menu timer, disabled buttons explain why
local function smoke(name, fn) SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { name, fn } end

smoke("context menu closes on a ticker that only lives while shown", function(e)
  local W = e.ns.W
  local m = { idle = 0, hidden = false, Hide = function(self) self.hidden = true end,
              IsMouseOver = function(self) return self.over end }
  m.over = true
  for _ = 1, 10 do ok(not W.MenuIdleTick(m, W.MENU_TICK), "cursor over: stays open") end
  m.over = false
  local n = 0
  while not m.hidden and n < 20 do W.MenuIdleTick(m, W.MENU_TICK); n = n + 1 end
  ok(m.hidden, "closes once the cursor is away")
  eq(n, 7, "closes after > 1.5 s away (7 ticks of 0.25 s)")
  W.Menu(UIParent, { { text = "a", func = function() end }, { text = "b", func = function() end } })
  W.CloseMenu()
end)

smoke("Mi perfil save button disabled without changes says why", function(e)
  local ns, L = e.ns, e.ns.L
  ns.UI.Open("profile"); ns.UI.Select("profile")
  local prof = ns.UI.ProfileState()
  eq(prof.save.tip, L.WHY_DISABLED, "tooltip title")
  eq(prof.save.tipText, L.WHY_NO_CHANGES, "tooltip reason")
  ok(type(L.WHY_NO_ONE_ONLINE) == "string" and L.WHY_NO_ONE_ONLINE ~= "", "invite reason string")
end)

-- the other two buttons that explain why and the hook that makes tooltips fire on disabled buttons
smoke("disabled Siguiente / Invitar al grupo explain why; W.Primary enables motion while disabled", function(e)
  local ns, L, W = e.ns, e.ns.L, e.ns.W
  -- W.Primary -> makeButton calls SetMotionScriptsWhileDisabled(true), otherwise OnEnter never fires while disabled
  local origCreate, seen = W.Create, nil
  W.Create = function(...)
    local b = origCreate(...)
    b.SetMotionScriptsWhileDisabled = function(_, v) seen = v end
    return b
  end
  local okP, errP = pcall(W.Primary, UIParent, "x", function() end)
  W.Create = origCreate
  ok(okP, tostring(errP))
  eq(seen, true, "W.Primary called SetMotionScriptsWhileDisabled(true)")
  -- Crear squad step 1 with an empty name: "Siguiente" disabled, tooltip = why
  ns.UI.OpenCreate("new")
  local cr = ns.UI.CreateState()
  cr.name:SetText("")
  ns.UI.OpenCreate("new")
  eq(cr.step, 1, "step 1")
  eq(cr.primary.tip, L.WHY_DISABLED, "Siguiente tooltip title")
  ok(type(cr.primary.tipText) == "string" and cr.primary.tipText ~= "", "Siguiente tooltip reason: " .. tostring(cr.primary.tipText))
  -- Mi squad with nobody else online: "Invitar al grupo" disabled, tooltip = no one online
  if not ns.Actions.MySquadId() then
    ok(ns.Actions.SaveProfile({ role = "TANK", avail = "11000000", goals = { "dungeons" } }))
    ok(ns.Actions.CreateSquad({ name = "Solo Lobos", icon = 1, color = 1, border = 1, tags = { "dungeons" }, open = true }))
  end
  -- everyone else in the squad offline for the check, restored afterwards
  local id = ns.Actions.MySquadId()
  local restore = {}
  for _, n in ipairs(ns.state.squads[id].d.members or {}) do
    local r = ns.roster(n)
    if r and n ~= ns.me() then restore[#restore + 1] = { r, r.online }; r.online = false end
  end
  ns.UI.Open("mysquad"); ns.UI.Select("mysquad")
  local sq = ns.UI.MySquadState()
  local tip, tipText = sq.primary.tip, sq.primary.tipText
  for _, x in ipairs(restore) do x[1].online = x[2] end
  ns.UI.Select("mysquad")
  eq(tip, L.WHY_DISABLED, "Invitar tooltip title")
  eq(tipText, L.WHY_NO_ONE_ONLINE, "Invitar tooltip reason")
  ok(sq.primary.tip == nil, "with someone online again the tooltip is cleared")
end)
