-- Guild Squads (MIT) - Core/Call.lua
-- Pure Lua. "Llamar al squad": payload format and cooldown / anti-spam rules.
local _, ns = ...
ns = ns or {}

local Call = {}
ns.Call = Call

Call.COOLDOWN = 300 -- seconds, sender side and receiver side (per sender)

-- sender: may I call now? returns ok, secondsLeft
function Call.canSend(lastSent, now)
  if not lastSent then return true, 0 end
  local left = Call.COOLDOWN - (now - lastSent)
  if left <= 0 then return true, 0 end
  return false, math.ceil(left)
end

-- receiver: accept one call per sender per COOLDOWN. seen = { [sender] = time }. Records the accepted call.
function Call.accept(seen, sender, now)
  if type(sender) ~= "string" then return false end
  local last = seen[sender]
  if last and now - last < Call.COOLDOWN then return false end
  seen[sender] = now
  return true
end

function Call.fmtLeft(sec)
  sec = math.max(0, math.floor(sec or 0))
  return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function clean(s) return (tostring(s or "")):gsub("[|\n\r]", ""):sub(1, 48) end

-- payload table that travels through Comm (serialized + escaped there)
function Call.payload(zone, subzone, x, y)
  local p = { z = clean(zone), s = clean(subzone) }
  if type(x) == "number" and type(y) == "number" then
    p.x = math.floor(x * 1000 + 0.5) / 10; p.y = math.floor(y * 1000 + 0.5) / 10
  end
  return p
end

-- human text for the receiver: "Los Baldíos (Cruce) 52.1, 30.4"
function Call.text(p)
  if type(p) ~= "table" or type(p.z) ~= "string" then return nil end
  local t = clean(p.z)
  if type(p.s) == "string" and p.s ~= "" and p.s ~= p.z then t = t .. " (" .. clean(p.s) .. ")" end
  if type(p.x) == "number" and type(p.y) == "number" then t = t .. (" %.1f, %.1f"):format(p.x, p.y) end
  return t
end

return Call
