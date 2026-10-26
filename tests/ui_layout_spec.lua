-- UI layout checks: pure checks run here; UI checks are registered in
-- SMOKE_CHECKS and run at the end of tests/zload_spec.lua with the fake client loaded.
local Pr = NS.Progress
SMOKE_CHECKS = SMOKE_CHECKS or {}
local function smoke(name, fn) SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { name, fn } end

test("ranking lists only squads with points (positions 1..n, 0-point squads unranked)", function()
  local res = { squads = { S1 = { raid = 5 }, S2 = { raid = 0 }, S3 = { raid = 2 } } }
  local l = Pr.scored(res, "raid", { S1 = true, S2 = true, S3 = true, S9 = true })
  eq(#l, 2); eq(l[1].sid, "S1"); eq(l[1].pos, 1); eq(l[2].sid, "S3"); eq(l[2].pos, 2)
  eq(#Pr.scored({ squads = {} }, "raid", { S1 = true }), 0, "nobody scored: empty list")
  eq(#Pr.ranking(res, "raid", { S1 = true, S2 = true, S3 = true, S9 = true }), 4, "P.ranking unchanged (all squads)")
end)

smoke("smoke: Bandas without points shows only the notice; Este wipe shows – for 0 points", function(e)
  local ns = e.ns
  ns.UI.Open("ranking")
  local rk = ns.UI.RankingState()
  rk.cat = "raid"; rk.mode = "wipe"; rk.back = 0
  ns.UI.Select("ranking")
  local shown = 0
  for _, c in ipairs(rk.grid.cells) do if e.vis(c) then shown = shown + 1 end end
  eq(shown, 0, "no 0-point rows under the notice")
  eq(e.vis(rk.notice), true, "notice over the empty list")
  rk.cat = "general"; ns.UI.Select("ranking")
  local id = ns.Actions.MySquadId()
  ok(id, "has squad")
  ns.UI.Select("mysquad")
  local sq = ns.UI.MySquadState()
  sq.wipe:SetSquad(id)
  local raidCell
  for _, c in ipairs(sq.wipe.cells) do if c.cat == "raid" then raidCell = c end end
  eq(rawget(raidCell.pos, "_text"), "–", "0 points: no position")
end)

smoke("geometry: request reason chip clear of the accept button; finder goal chips clear of the fit badge", function(e)
  local ns = e.ns
  ns.UI.Select("mysquad")
  local sq = ns.UI.MySquadState()
  local r = sq.req[1]
  r.reason:SetReason({ "goal", "dungeons" })
  rawset(r, "_w", 330)
  local cl, _, cw = e.geo(r.reason, r)
  local yl = e.geo(r.yes, r)
  ok(cl and yl, "anchored")
  ok(r.reason.maxW and cl + r.reason.maxW <= yl, ("chip max right %s <= accept left %s"):format(tostring(cl + (r.reason.maxW or 999)), tostring(yl)))
  ok(cw <= r.reason.maxW, "chip width capped")
  -- force a long reason: width is capped
  local orig = r.reason.text.GetStringWidth
  r.reason.text.GetStringWidth = function() return 400 end
  r.reason:SetReason({ "goal", "dungeons" })
  r.reason.text.GetStringWidth = orig
  eq(rawget(r.reason, "_w"), r.reason.maxW, "long text truncated to the max width")
  -- finder: 3 chips right-aligned before the fit badge
  ns.UI.Select("finder")
  local fd = ns.UI.FinderState()
  local c = fd.grid.cells[1]
  rawset(c, "_w", 674)
  c.chips:SetKeys({ "leveling", "dungeons", "raid" })
  local fl = e.geo(c.fit, c)
  local maxR, minL = -1e9, 1e9
  for i = 1, 3 do
    local l, _, w = e.geo(c.chips.chips[i], c)
    ok(l, "chip anchored"); maxR = math.max(maxR, l + w); minL = math.min(minL, l)
  end
  ok(maxR <= fl, ("chips right %d <= fit left %d"):format(maxR, fl))
  local l1 = e.geo(c.chips.chips[1], c); local l3 = e.geo(c.chips.chips[3], c)
  ok(l1 < l3, "key order kept left to right")
  local nl = e.geo(c.role2, c) or 0
  ok(minL > 250, "chips start right of the role icons: " .. minL)
end)

smoke("squads: inactive cards dim even when full (alphas combine)", function(e)
  local UI = e.ns.UI
  eq(UI.SquadCardAlpha(true, "open"), 0.5); eq(UI.SquadCardAlpha(false, "full"), 0.6)
  eq(UI.SquadCardAlpha(true, "full"), 0.5, "inactive + full: the lowest"); eq(UI.SquadCardAlpha(false, "open"), 1)
end)

smoke("Mi perfil and member tooltip: localized class name; squad name on one line", function(e)
  local ns, W = e.ns, e.ns.W
  LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Guerrero", PRIEST = "Sacerdote" }
  eq(W.ClassName("WARRIOR"), "Guerrero")
  LOCALIZED_CLASS_NAMES_MALE = nil
  GetClassInfo = function(id) if id == 5 then return "Sacerdote", "PRIEST", 5 end return "X", "OTHER", id end
  eq(W.ClassName("PRIEST"), "Sacerdote", "GetClassInfo fallback")
  GetClassInfo = nil
  eq(W.ClassName("WARLOCK"), "Warlock", "token fallback"); eq(W.ClassName(nil), "")
  LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Guerrero" }
  ns.UI.Select("profile")
  local prof = ns.UI.ProfileState()
  local sub = rawget(prof.sub, "_text") or ""
  ok(sub:find("Guerrero", 1, true) and not sub:find("WARRIOR", 1, true), "profile shows the localized class: " .. sub)
  eq(rawget(prof.squad, "_h"), 14, "squad label: one line high")
  local _, top = e.geo(prof.squad, ns.UI.panels.profile.frame)
  local _, ltop = e.geo(prof.squadLink, ns.UI.panels.profile.frame)
  ok(top and ltop and top - 14 >= ltop, "squad name ends above the Mi squad link")
  LOCALIZED_CLASS_NAMES_MALE = nil
end)

smoke("Ajustes: options aligned in a fixed column, buttons fit their text ([sin límite], Restablecer)", function(e)
  local ns = e.ns
  ns.UI.Open("settings")
  local st = ns.UI.SettingsState()
  local byParent = {}
  for _, s in ipairs(st.seg) do
    local b1 = s.buttons[1]
    local parent = rawget(b1, "_parent")
    local x = e.geo(b1, parent)
    ok(x, "seg anchored: " .. s.field)
    byParent[parent] = byParent[parent] or {}
    table.insert(byParent[parent], { x = x, f = s.field })
    for i, v in ipairs(s.values) do
      local need = 7 * (#(("[" .. s.show(v) .. "]"):gsub("[\128-\191]", ""))) + 12
      ok(rawget(s.buttons[i], "_w") >= math.min(need, 46) and rawget(s.buttons[i], "_w") >= need - 1,
         s.field .. " button fits " .. s.show(v) .. ": " .. tostring(rawget(s.buttons[i], "_w")))
      local l, _, w = e.geo(s.buttons[i], parent)
      ok(l + w <= 696, s.field .. " row stays inside the panel: " .. (l + w))
    end
  end
  for _, rows in pairs(byParent) do
    for _, r in ipairs(rows) do eq(r.x, rows[1].x, "options of " .. r.f .. " start in the same column as " .. rows[1].f) end
  end
  local lim
  for _, s in ipairs(st.seg) do if s.field == "maxSquads" then lim = s end end
  ok(lim.width >= 7 * 12 + 12, "[sin límite] fits: " .. lim.width)
  local reset = st.modRows[1].reset
  ok(rawget(reset, "_w") >= 7 * #ns.L.S_RESET_LOGO - 10, "Restablecer nombre/logo fits: " .. rawget(reset, "_w"))
  local dl = e.geo(st.modRows[1].disband, st.modRows[1]); local rl = e.geo(reset, st.modRows[1])
  ok(dl + 120 <= rl, "disband does not overlap reset")
end)

smoke("wording: the guild goal counts this wipe, not 'this week'", function(e)
  local L = e.ns.L
  ok(L.GOAL:find("wipe", 1, true) and not L.GOAL:find("semana", 1, true), L.GOAL)
  ok(L.GOAL_TIP:find("wipe", 1, true) and L.S_GOAL:find("wipe", 1, true))
  e.ns.UI.Open("ranking")
  ok(L.GOAL:format(3, 30):find("3 / 30", 1, true))
end)
