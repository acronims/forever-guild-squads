-- tiny assert harness (runs inside fengari)
local print = print
NS = {}
function loadmod(name, ns)
  local f, err = load(SOURCES[name], "@" .. name)
  if not f then error(err) end
  return f("GuildSquads", ns or NS)
end
for _, n in ipairs(CORE) do loadmod(n) end

local passed, failed = 0, 0
function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
function eq(a, b, msg)
  if a ~= b then error((msg or "eq") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
function ok(v, msg) if not v then error(msg or "expected truthy", 2) end end

-- deep compare
function deq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deq(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- fake guild roster: name -> rank
function makeRoster(ranks)
  return function(name)
    local r = ranks[name]
    if r == nil then return nil end
    return { rank = r, online = true }
  end
end

for _, s in ipairs(SPECS) do
  print("-- " .. s)
  loadmod(s)
end
print(string.format("RESULT: %d passed, %d failed", passed, failed))
FAILED = failed
