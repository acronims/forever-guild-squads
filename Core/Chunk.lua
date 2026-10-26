-- Guild Squads (MIT) - Core/Chunk.lua
-- Pure Lua. Splits an (already escaped) payload into <=255 byte messages and reassembles.
local _, ns = ...
ns = ns or {}

local C = {}
ns.Chunk = C

C.MAX = 255
C.TIMEOUT = 120 -- seconds before an incomplete message is dropped

-- header: "<msgId>:<index>/<total>:"
function C.split(payload, msgId, maxLen)
  maxLen = maxLen or C.MAX
  local parts = {}
  local headerMax = #tostring(msgId) + 2 + 2 * 5 + 1
  local body = maxLen - headerMax
  if body < 16 then error("maxLen too small") end
  local total = math.max(1, math.floor((#payload + body - 1) / body))
  for i = 1, total do
    local piece = payload:sub((i - 1) * body + 1, i * body)
    parts[i] = msgId .. ":" .. i .. "/" .. total .. ":" .. piece
  end
  return parts
end

function C.newAssembler()
  return { buf = {} }
end

-- Feed one message. Returns the full payload when complete, else nil.
function C.feed(asm, sender, msg, now)
  local id, i, n, data = msg:match("^(%w+):(%d+)/(%d+):(.*)$")
  if not id then return nil, "bad header" end
  i, n = tonumber(i), tonumber(n)
  if n < 1 or n > 64 or i < 1 or i > n then return nil, "bad index" end
  if n == 1 then return data end
  local key = sender .. "\1" .. id
  local e = asm.buf[key]
  if not e then
    e = { n = n, got = 0, parts = {}, t = now or 0 }
    asm.buf[key] = e
  end
  if e.n ~= n then asm.buf[key] = nil; return nil, "inconsistent" end
  if not e.parts[i] then e.parts[i] = data; e.got = e.got + 1 end
  e.t = now or e.t
  if e.got == e.n then
    asm.buf[key] = nil
    return table.concat(e.parts)
  end
  return nil
end

function C.gc(asm, now)
  for k, e in pairs(asm.buf) do
    if now - e.t > C.TIMEOUT then asm.buf[k] = nil end
  end
end

return C
