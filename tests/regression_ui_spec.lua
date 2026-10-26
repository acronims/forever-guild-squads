-- UI regression checks.
-- They run inside tests/zload_spec.lua (fake client; Ann-Realm is the GM) via SMOKE_CHECKS.

-- locale keys (static): every L.X used in UI/*.lua exists in enUS and esES, and both define the same keys.
test("locale keys: UI keys exist in both locales; same key set; same format specifiers", function()
  local function keys(src)
    local t = {}
    for line in src:gmatch("[^\n]+") do
      local k, v = line:match("^%s*L%.([%w_]+)%s*=%s*(.*)$")
      if k then t[k] = v end
    end
    return t
  end
  local en, es = keys(SOURCES["Locales/enUS.lua"]), keys(SOURCES["Locales/esES.lua"])
  for k in pairs(en) do ok(es[k], "falta en esES: " .. k) end
  for k in pairs(es) do ok(en[k], "falta en enUS: " .. k) end
  for _, f in ipairs({ "UI/Panels.lua", "UI/Widgets.lua", "UI/Ranking.lua", "UI/Main.lua", "UI/Hall.lua", "UI/Raids.lua", "UI/Minimap.lua" }) do
    for k in SOURCES[f]:gmatch("[^%w_]L%.([%w_]+)") do ok(en[k] and es[k], f .. " usa L." .. k .. " sin traducir") end
  end
end)

SMOKE_CHECKS = SMOKE_CHECKS or {}

-- raid editor: changing only the name (or "Cada semana") marks the draft dirty, enables "Guardar" and shows
-- the "sin guardar" label.
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "Raids: renaming a roster enables Save", function(c)
  local ns, UI, G = c.ns, c.ns.UI, c.ns.RaidGlue
  local wall = G.WallNow()
  local rid = G.Create({ raid = "custom", size = 10, name = "Raid P3", at = wall + 2 * 86400 })
  ok(rid, "roster creado")
  UI.OpenRoster(rid)
  local rb = UI.RaidsState()
  ok(rb.editable, "el GM puede editar")
  eq(rawget(rb.save, "_enabled"), false, "Guardar deshabilitado sin cambios")
  rawset(rb.name, "_text", "Raid P3 renombrada")
  local fn = rawget(rb.name, "_OnTextChanged"); ok(fn, "OnTextChanged")
  fn(rb.name, true)
  ok(rb.dirty, "el borrador queda sucio")
  eq(rawget(rb.save, "_enabled"), true, "Guardar debería habilitarse tras teclear el nombre")
end }

-- "Firmar asistencia" with nobody marked tells the raid leader why nothing was signed.
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "Raids: signing an empty attendance warns the RL", function(c)
  local ns, UI, G, Rr = c.ns, c.ns.UI, c.ns.RaidGlue, c.ns.Roster
  local origTime = GetServerTime
  GetServerTime = function() return 1796000000 end
  local wall = G.WallNow()
  local rid = G.Create({ raid = "custom", size = 10, name = "Raid vacía", at = wall - Rr.CLOSE_AFTER - 600 })
  local d = Rr.copy(G.Get(rid).d); Rr.addPlayer(d, "Bob-Realm"); d.st = "published"
  ok(G.Save(rid, d)); G.Tick()
  eq(Rr.attendanceState(ns.state, rid), "pending")
  UI.OpenRoster(rid)
  local rb = UI.RaidsState()
  ok(rb.attMode, "modo corrección")
  rb.att = {}                                   -- nadie marcado
  local said = {}
  local origPrint, origFlash = print, UI.Flash
  print = function(m) said[#said + 1] = tostring(m) end
  UI.Flash = function(t) said[#said + 1] = tostring(t); return origFlash(t) end
  local okc, e = pcall(c.click, rb.primary)
  print, UI.Flash = origPrint, origFlash
  GetServerTime = origTime
  ok(okc, tostring(e))
  local found = false
  for _, m in ipairs(said) do if m:find(ns.L.RB_ATT_EMPTY, 1, true) then found = true end end
  ok(found, "se esperaba el aviso RB_ATT_EMPTY; salió: " .. table.concat(said, " | "))
end }

-- a failed action from a panel prints its error once (scenario: a banned word in the squad name, the
-- captain toggles open/closed and the edit is refused with nameBanned).
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "My squad: an action error is shown once in chat", function(c)
  local ns, UI, M = c.ns, c.ns.UI, c.ns.Model
  local my = ns.Actions.MySquadId()
  ok(my and ns.state.squads[my].d.captain == ns.me(), "Ann es capitana")
  local name = ns.state.squads[my].d.name
  local word = name:match("(%a%a%a%a+)") or name
  local s0 = M.settingsOf(ns.state)
  local s = {}; for k, v in pairs(s0) do s[k] = v end
  s.banned = { word }
  ok(ns.Actions.SaveSettings(s), "ajustes con palabra prohibida")
  UI.Select("mysquad")
  local sq = UI.MySquadState()
  local said = {}
  local origPrint = print
  print = function(m) said[#said + 1] = tostring(m) end
  local okc, e = pcall(rawget(sq.state, "_OnClick"), sq.state, "LeftButton")
  print = origPrint
  local s2 = {}; for k, v in pairs(s0) do s2[k] = v end
  s2.banned = {}; ns.Actions.SaveSettings(s2)
  ok(okc, tostring(e))
  local errs = 0
  local prefix = ns.L.ERR:match("^(.-)%%s")
  for _, m in ipairs(said) do if m:find(prefix, 1, true) then errs = errs + 1 end end
  ok(errs >= 1, "la edición debía fallar: " .. table.concat(said, " | "))
  eq(errs, 1, "mensajes de error: " .. table.concat(said, " | "))
end }

-- Salón: a failed annulment shows the translated error text, not the internal code.
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "Hall of Fame: a failed annulment shows translated text, not the error code", function(c)
  local ns, UI = c.ns, c.ns.UI
  local Hg = ns.HallGlue
  local said = {}
  local origPrint, origAnnul = print, Hg.Annul
  Hg.Annul = function() return false, "denied" end
  print = function(m) said[#said + 1] = tostring(m) end
  local origPrompt, origConfirm = ns.W.Prompt, ns.W.Confirm
  ns.W.Prompt = function(_, fn) fn("motivo") end
  ns.W.Confirm = function(_, fn) fn() end
  local okc, e = pcall(UI.HallAnnul, "lvl.all.20", { key = "Cid-Realm", chars = { "Cid-Realm" } })
  ns.W.Prompt, ns.W.Confirm, Hg.Annul, print = origPrompt, origConfirm, origAnnul, origPrint
  ok(okc, tostring(e))
  local joined = table.concat(said, " | ")
  ok(not joined:find(": denied", 1, true), "código crudo en el chat: " .. joined)
end }
