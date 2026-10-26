-- part 2: every error code that Model / Permissions / Actions / Sync can return has text in EN and ES,
-- and both locales define the same keys.
local function keys(src)
  local out = {}
  for k in src:gmatch("\nL%.([%w_]+)%s*=") do out[k] = true end
  return out
end
test("every error code returned by the model has ERR_ text in enUS and esES", function()
  local en, es = keys(SOURCES["Locales/enUS.lua"]), keys(SOURCES["Locales/esES.lua"])
  local codes, n = {}, 0
  for _, f in ipairs({ "Core/Model.lua", "Core/Permissions.lua", "GuildSquads.lua", "Sync.lua" }) do
    for code in SOURCES[f]:gmatch('return false, "([%w_]+)"') do if not codes[code] then codes[code] = true; n = n + 1 end end
  end
  for _, extra in ipairs({ "nameTaken", "stale", "future", "relay", "xfer", "ts", "error", "maxSquads" }) do
    if not codes[extra] then codes[extra] = true; n = n + 1 end
  end
  ok(n >= 25, "codes found: " .. n)
  local missing = {}
  for code in pairs(codes) do
    if not en["ERR_" .. code] then missing[#missing + 1] = "en:" .. code end
    if not es["ERR_" .. code] then missing[#missing + 1] = "es:" .. code end
  end
  table.sort(missing)
  eq(#missing, 0, "missing " .. table.concat(missing, ","))
end)

test("locale key diff: enUS and esES define the same keys", function()
  local en, es = keys(SOURCES["Locales/enUS.lua"]), keys(SOURCES["Locales/esES.lua"])
  local miss = {}
  for k in pairs(en) do if not es[k] then miss[#miss + 1] = "es:" .. k end end
  for k in pairs(es) do if not en[k] then miss[#miss + 1] = "en:" .. k end end
  table.sort(miss)
  eq(#miss, 0, table.concat(miss, ","))
end)

test("ErrText never returns a raw ERR_ key", function()
  local ns = {}
  loadmod("Locales/enUS.lua", ns)
  eq(ns.ErrText("xfer"), ns.L.ERR_xfer)
  ok(ns.ErrText("weird"):find("weird", 1, true) and not ns.ErrText("weird"):find("ERR_", 1, true))
end)

-- part 3 (runs inside the fake client of tests/zload_spec.lua): every default achievement and race, every family
-- expanded (lvl.class.<CLASS>.<H>, lvl.race.<RACE>.<H>, dng.<key>, pvp.rank.*, ...), every race state and every
-- category / group / metric label has a real display name in esES and in enUS (never nil, empty or a raw key).
SMOKE_CHECKS = SMOKE_CHECKS or {}
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "default achievements, races, states and categories have names in enUS and esES", function(c)
  local ns = c.ns
  local UI, R, Cat, Content, L = ns.UI, ns.Races, ns.Catalog, ns.Content, ns.L
  local function sorted(set) local o = {}; for k in pairs(set) do o[#o + 1] = k end; table.sort(o); return o end
  local ids = {}
  local function add(id) ids[#ids + 1] = id end
  for _, h in ipairs(R.LEVELS) do
    add("lvl.all." .. h)
    for _, cl in ipairs(sorted(R.CLASS_OK)) do add("lvl.class." .. cl .. "." .. h) end
    for _, rc in ipairs(sorted(R.RACE_OK)) do add("lvl.race." .. rc .. "." .. h) end
  end
  for _, e in ipairs(Content.DUNGEONS) do add("dng." .. e.key); add("dng." .. e.key .. ".boss") end
  for _, e in ipairs(Content.RAIDS) do add("raid." .. e.key); add("raid." .. e.key .. ".boss") end
  for _, id in ipairs({ "dng.all", "raid.all", "full.10", "full.20", "squad.full60", "prof.*", "rep.*",
                        "pvp.bgmap.warsong_gulch", "rep.stormwind.exalted" }) do add(id) end
  for _, r in ipairs(R.PVP_RANKS) do add("pvp.rank." .. r .. ".s1") end
  for _, cl in ipairs(sorted(R.CLASS_OK)) do add("pvp.rank.class." .. cl .. ".14.s1") end
  for _, n in ipairs(R.HK_STEPS) do add("pvp.hk." .. n) end
  for _, n in ipairs(R.BG_STEPS) do add("pvp.bg." .. n) end
  for _, n in ipairs(R.CAPS_STEPS) do add("wpvp.caps." .. n) end
  for _, n in ipairs(R.PROF_STEPS) do add("prof.alchemy." .. n) end
  for _, n in ipairs(R.LEGACY_STEPS) do add("legacy." .. n) end
  for _, id in ipairs(Cat.knownIds(ns.HallGlue.Races())) do if Cat.isRaceId(id) and not Cat.isCustom(id) then add(id) end end
  local badges = Cat.badges()
  ok(#ids > 300 and #badges >= 30, "families expanded: " .. #ids .. " races, " .. #badges .. " badges")

  local function bad(s, raw)
    return type(s) ~= "string" or s == "" or s == raw or s:find("%u%u+_[%w_]+") ~= nil or s:find("%%[sd]") ~= nil
  end
  local function check(lang)
    local miss = {}
    for _, id in ipairs(ids) do
      local t = UI.RaceTitle(id)
      if bad(t, id) then miss[#miss + 1] = id .. "=" .. tostring(t) end
      local rc = id:match("^lvl%.race%.([^.]+)%.")
      if rc and not rawget(L, "RACE_" .. rc) then miss[#miss + 1] = "RACE_" .. rc end
    end
    for _, b in ipairs(badges) do
      local t, d = UI.AchTitleDefault(b.key)
      if bad(t, b.key) then miss[#miss + 1] = "ach " .. b.key .. "=" .. tostring(t) end
      if bad(d, b.key) then miss[#miss + 1] = "achd " .. b.key .. "=" .. tostring(d) end
    end
    for _, st in ipairs({ { state = "open", entries = {}, size = 10 }, { state = "closed", entries = {}, size = 10 },
                          { state = "nodata", entries = {}, size = 10 } }) do
      local t = UI.RaceStateText(st):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
      if bad(t, "HALL_" .. st.state:upper()) then miss[#miss + 1] = "state " .. st.state end
    end
    local labels = {}
    for _, k in ipairs(R.CATS) do labels[#labels + 1] = "HF_" .. k end
    for _, k in ipairs(Cat.GROUPS) do labels[#labels + 1] = "CG_" .. k end
    for _, k in ipairs(Cat.METRICS) do labels[#labels + 1] = "CAT_M_" .. k end
    for _, k in ipairs({ "level", "dungeon", "raid", "pvp", "wpvp", "general" }) do labels[#labels + 1] = "CAT_" .. k; labels[#labels + 1] = "CATD_" .. k end
    for _, k in ipairs({ "exact", "approx", "wit", "self" }) do labels[#labels + 1] = "MARK_" .. k end
    for _, k in ipairs({ "CEL_RACE", "CEL_ACH", "HALL_NODATA", "HALL_NODATA_LONG", "HALL_OPEN", "HALL_CLOSED", "TOP_N", "MINUTES" }) do labels[#labels + 1] = k end
    for _, k in ipairs(labels) do if bad(rawget(L, k) and rawget(L, k):gsub("%%[sd]", "x"), k) then miss[#miss + 1] = k end end
    table.sort(miss)
    eq(#miss, 0, lang .. ": " .. table.concat(miss, ", "))
  end

  -- esES (the fake client's locale)
  eq(rawget(L, "TAB_FINDER"), "Buscador", "esES active")
  check("esES")
  local esNight = UI.RaceTitle("lvl.race.NIGHTELF.60")
  -- enUS: load the base locale on its own and swap its values into the live table, then restore
  local en = {}
  loadmod("Locales/enUS.lua", en)
  local saved = {}
  for k, v in pairs(en.L) do saved[k] = rawget(L, k); rawset(L, k, v) end
  local okAll, err = pcall(function()
    eq(rawget(L, "TAB_FINDER"), "Finder", "enUS swapped in")
    check("enUS")
    local enNight = UI.RaceTitle("lvl.race.NIGHTELF.60")
    ok(enNight:find("Night Elf", 1, true) and esNight:find("Elfo de la noche", 1, true), enNight .. " / " .. esNight)
    eq(UI.AchTitleDefault("forever"), "Forever route", "default achievement name in English")
  end)
  for k in pairs(en.L) do rawset(L, k, saved[k]) end
  ok(rawget(L, "TAB_FINDER") == "Buscador", "esES restored")
  if not okAll then error(err, 0) end
end }
