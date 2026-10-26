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
