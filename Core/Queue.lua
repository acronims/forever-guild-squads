-- Guild Squads (MIT) - Core/Queue.lua
-- Pure Lua. Token-bucket send queue that holds everything while comms are locked
-- (encounter / PvP match / M+ / chat lockdown). The caller injects send() and the clock.
local _, ns = ...
ns = ns or {}

local Q = {}
Q.__index = Q
ns.Queue = Q

function Q.new(opts)
  opts = opts or {}
  local q = setmetatable({}, Q)
  q.rate = opts.rate or 1        -- messages per second sustained
  q.burst = opts.burst or 4      -- bucket size
  q.max = opts.max or 2000       -- hard cap on queued messages
  q.tokens = q.burst
  q.last = opts.now or 0
  q.items = {}
  q.head = 1
  q.tail = 0
  q.blocks = {}                  -- reason -> true
  q.send = opts.send             -- function -> boolean sent
  q.isLocked = opts.isLocked     -- optional function() -> boolean (e.g. InChatMessagingLockdown)
  q.sent = 0
  q.dropped = 0
  q.deduped = 0
  q.keys = {}                    -- dedupe key -> parts still pending
  return q
end

function Q:size() return self.tail - self.head + 1 end

-- item.key (optional) identifies a message (same record and version, same channel and
-- target). While a message with that key is still pending, an identical one is not queued again.
function Q:pending(key) return key ~= nil and (self.keys[key] or 0) > 0 end

function Q:push(item)
  if self:size() >= self.max then self.dropped = self.dropped + 1; return false end
  self.tail = self.tail + 1
  self.items[self.tail] = item
  if type(item) == "table" and item.key ~= nil then self.keys[item.key] = (self.keys[item.key] or 0) + 1 end
  return true
end

-- push every part of one message (dedupe on the message key); returns false when deduped or full
function Q:pushMessage(parts, key)
  if key ~= nil and self:pending(key) then self.deduped = self.deduped + 1; return false end
  if self:size() + #parts > self.max then self.dropped = self.dropped + #parts; return false end
  for _, item in ipairs(parts) do item.key = key; self:push(item) end
  return true
end

-- a fresh own record goes BEFORE the backlog of sync replies (parts kept in order;
-- the assembler keys parts by message id, so interleaving with a half-sent message is safe)
function Q:pushMessageFront(parts, key)
  if key ~= nil and self:pending(key) then self.deduped = self.deduped + 1; return false end
  if self:size() + #parts > self.max then self.dropped = self.dropped + #parts; return false end
  for i = #parts, 1, -1 do
    local item = parts[i]
    item.key = key
    self.head = self.head - 1
    self.items[self.head] = item
    if key ~= nil then self.keys[key] = (self.keys[key] or 0) + 1 end
  end
  return true
end

function Q:setBlocked(reason, on)
  self.blocks[reason] = on and true or nil
end

function Q:blocked()
  if next(self.blocks) then return true end
  if self.isLocked and self.isLocked() then return true end
  return false
end

-- Call periodically. Returns number of messages sent.
function Q:pump(now)
  local dt = now - self.last
  if dt > 0 then
    self.tokens = math.min(self.burst, self.tokens + dt * self.rate)
    self.last = now
  end
  if self:blocked() then return 0 end
  local n = 0
  while self.tokens >= 1 and self.head <= self.tail do
    local item = self.items[self.head]
    if self.send and self.send(item) == false then break end
    self.items[self.head] = nil
    if type(item) == "table" and item.key ~= nil and self.keys[item.key] then
      self.keys[item.key] = self.keys[item.key] - 1
      if self.keys[item.key] <= 0 then self.keys[item.key] = nil end
    end
    self.head = self.head + 1
    self.tokens = self.tokens - 1
    self.sent = self.sent + 1
    n = n + 1
  end
  if self.head > self.tail then self.items = {}; self.head = 1; self.tail = 0 end
  return n
end

return Q
