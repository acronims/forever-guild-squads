-- Guild Squads (MIT) - Comm.lua
-- Addon-channel transport: serialize -> escape -> chunk -> throttled queue -> SendAddonMessage.
-- Nothing is sent while an encounter / PvP match / M+ is running or chat is locked down.
local _, ns = ...
ns = ns or {}

local Comm = {}
ns.Comm = Comm
local S, C, Q = ns.Serialize, ns.Chunk, ns.Queue

Comm.PREFIX = "GSquads"
Comm.PROTO = 2   -- v1.2 (BRO 7-nov 21:20): 1.0.x / 1.1 speak 1 and drop every v ~= 1, so they get nothing from a 1.2
-- distinct senders seen on an older protocol (members who still have to update); local count only, never sent
Comm.oldPeers = {}
Comm.OLD_PEERS_MAX = 1000
function Comm.OldPeerCount()
  local n = 0
  for _ in pairs(Comm.oldPeers) do n = n + 1 end
  return n
end
Comm.stats = { sent = 0, recv = 0, failed = 0, badProto = 0, tooBig = 0 }
Comm.MAX_PARTS = 64   -- Chunk.feed drops n > 64 on receive: never queue such a message (sec F7)

-- 1.2.2 whispers (BRO in the game, 9-nov 03:03-03:11). With the 1.2.1 a guildmate's chat filled with «No hay ningún
-- jugador con el nombre Kas CAMWOWEU4Realm6PvP.» (the 1.2.1 whispered «Kas-CAMWOWEU4Realm6PvP»); BRO's test: WoW
-- Forever only delivers a whisper to the full name WITH the surname («Kas Pitas»). The callers keep passing the
-- character key ("Kas-Realm"); the target comes from the roster (ns.whisperTarget). When the server answers
-- ERR_CHAT_PLAYER_NOT_FOUND_S for a name we whispered in the last WHISPER_WINDOW s, the line is hidden
-- (Comm.SystemFilter), the message goes again once with the other variant (with / without the realm suffix) and, if
-- that fails too, the character is marked for UNREACHABLE_FOR s: meanwhile whatever went to him by whisper goes over
-- GUILD in a "W" envelope with the recipient key (only he processes it; 1.2.0 / 1.2.1 drop the unknown tag). After
-- the mark a single probe whisper goes; the rest waits over GUILD until it is known (no error in WHISPER_WINDOW s).
-- A character missing from the roster is never whispered (GUILD envelope); one offline in the roster that we did not
-- hear from lately gets nothing.
Comm.ROUTED = "W"
Comm.WHISPER_WINDOW = 5
Comm.UNREACHABLE_FOR = 600
Comm.HEARD_FRESH = 120
Comm.wsent = {}     -- whisper target -> { k = character key, t = GetTime of our last part to it, alt, probe }
Comm.wstate = {}    -- character key -> { alt = true (the other variant), fail = t (marked), probe = t, n = failures }
Comm.recent = {}    -- whisper messages whose first part left in the last WHISPER_WINDOW s (sent again if they failed)
Comm.stats.notFound, Comm.stats.routed, Comm.stats.wdropped, Comm.stats.notForMe = 0, 0, 0, 0

local function now() return (GetTime and GetTime()) or 0 end

local function chatLocked()
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
    local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
    if ok and locked then return true end
  end
  local encFn = ((ns.encounterFn and ns.encounterFn()) or IsEncounterInProgress)
  if encFn then
    local ok, inProgress = pcall(encFn)
    if ok and inProgress then return true end
  end
  return false
end

-- Enum.SendAddonMessageResult. 11 = AddOnMessageLockdown -> pause the queue and keep the item;
-- permanent errors are dropped at once; only throttling / generic failures are retried.
Comm.LOCKDOWN = 11
local PERMANENT = { [1] = true, [2] = true, [4] = true, [6] = true, [7] = true, [10] = true, [12] = true }
Comm.lockUntil = nil
local function sentOk(item)
  if item.onSent then pcall(item.onSent) end
  return true
end
local restamp
-- 1.2.2: a whisper part left: remember the target (the server's not found refers to it) and its message
local function whispered(item)
  local m, t = item.wm, now()
  if not m.started then
    m.started, m.at = true, t
    local w = Comm.wstate[m.key]
    if w and w.fail and t - w.fail >= Comm.UNREACHABLE_FOR and not (w.probe and w.probe > w.fail) then w.probe, m.probe = t, true end
    local keep = {}
    for _, r in ipairs(Comm.recent) do if t - r.at <= Comm.WHISPER_WINDOW and not r.resent then keep[#keep + 1] = r end end
    keep[#keep + 1] = m
    Comm.recent = keep
  end
  Comm.wsent[item.target] = { k = m.key, t = t, alt = m.alt, probe = m.probe }
end
local function rawSend(item)
  if item.stamp then restamp(item) end
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return sentOk(item) end
  local ok, res = pcall(C_ChatInfo.SendAddonMessage, Comm.PREFIX, item.msg, item.channel, item.target)
  -- Retail returns an Enum.SendAddonMessageResult (0 = success); older builds return a boolean.
  if ok and (res == nil or res == true or res == 0) then
    Comm.stats.sent = Comm.stats.sent + 1
    if item.wm then whispered(item) end
    return sentOk(item)
  end
  if ok and res == 12 and item.wm then   -- Enum.SendAddonMessageResult.TargetOffline: the same as a not found
    whispered(item)
    if Comm.Failed then Comm.Failed(item.target, now()) end
  end
  if ok and res == Comm.LOCKDOWN then
    Comm.queue:setBlocked("lockdown", true)
    Comm.lockUntil = now() + 30
    Comm.stats.lockdowns = (Comm.stats.lockdowns or 0) + 1
    return false
  end
  if ok and PERMANENT[res] then
    Comm.stats.failed = Comm.stats.failed + 1
    if ns.debug then ns.debug("send failed (permanent " .. tostring(res) .. "), dropped") end
    return true
  end
  item.tries = (item.tries or 0) + 1
  if item.tries >= 5 then
    Comm.stats.failed = Comm.stats.failed + 1
    if ns.debug then ns.debug("send failed, dropped: " .. tostring(res)) end
    return true -- give up on this one so the queue does not stall
  end
  return false
end

Comm.queue = Q.new({ rate = 1, burst = 4, send = rawSend, isLocked = chatLocked })
Comm.assembler = C.newAssembler()

-- seeded per session so a /reload does not reuse the ids of half-received messages
local counter = math.floor(((GetTime and GetTime()) or 0) * 1000) % 1296
local function nextId()
  counter = (counter + 1) % 1296
  local digits = "0123456789abcdefghijklmnopqrstuvwxyz"
  local a, b = math.floor(counter / 36) + 1, (counter % 36) + 1
  return digits:sub(a, a) .. digits:sub(b, b)
end

-- every message carries `s` = sentAt, the server time when it really
-- leaves the queue (fixed 10-digit string, restamped on the first part right before SendAddonMessage). The body is
-- deterministic (keys sorted: p < s < t < v), so it is rebuilt around the stamp without re-encoding the payload.
local function serverNow()
  if type(GetServerTime) == "function" then
    local okT, v = pcall(GetServerTime)
    if okT and type(v) == "number" then return v end
  end
  return time and time() or 0
end
Comm.ServerNow = serverNow
local function stampOf(t) return string.format("%010d", math.max(0, math.floor(t or 0)) % 10000000000) end
function Comm.Body(tag, payload, at)
  local pre = S.encode({ p = payload })
  return pre:sub(1, -2) .. "s1:s" .. S.encode(stampOf(at)) .. "s1:t" .. S.encode(tag) .. "s1:v" .. S.encode(Comm.PROTO) .. "e"
end

-- number of <=255-byte parts a message takes (the queue sends 1 part per second): the GM's bulk estimate
function Comm.Parts(tag, payload) return #C.split(S.escape(Comm.Body(tag, payload, 0)), "zz") end

-- the first part of a message is restamped right before it leaves (same length: the other parts keep their split)
restamp = function(item)
  local m = item.stamp
  local okB, fresh = pcall(m.build, serverNow())
  if okB and #fresh == #m.items then for i, p in ipairs(fresh) do m.items[i].msg = p end end
end

-- Send a message table. channel "GUILD" (default) or "WHISPER" with target. onSent (optional) runs when the last
-- part has really left (claims are timed from that moment). skip (optional, AF4) is asked when the message reaches
-- the head of the queue, before its first part leaves: true drops the whole message (onSent does not run).
-- 1.2.2 -------------------------------------------------------------------------------------------------------
local function keyOf(name) return (ns.fullName and ns.fullName(name)) or name end
-- true while a character is marked (both variants failed, UNREACHABLE_FOR s) or a probe whisper waits for its answer
function Comm.Unreachable(key, t)
  local w = Comm.wstate[key]
  if not (w and w.fail) then return false end
  t = t or now()
  if t - w.fail < Comm.UNREACHABLE_FOR then return true end
  if w.probe and w.probe > w.fail then
    if t - w.probe <= Comm.WHISPER_WINDOW then return true end
    Comm.wstate[key] = nil                                   -- the probe got through: reachable again
  end
  return false
end
local function variant(key)
  if Comm.Unreachable(key) then return "gone" end
  local w = Comm.wstate[key]
  return (w and w.alt) and "alt" or "main"
end
-- offline in the roster and silent lately: nobody to deliver to (the roster may lag a login: a fresh sender counts)
local function offline(key)
  local r = ns.roster and ns.roster(key)
  if not (r and r.online == false) then return false end
  local ago = ns.Sync and ns.Sync.HeardAgo and ns.Sync.HeardAgo(key)
  return not (ago and ago <= Comm.HEARD_FRESH)
end
-- the message over GUILD in a "W" envelope with the recipient key (only he processes it, as a whisper)
local function routeGuild(tag, payload, key, onSent, urgent, skip)
  if tag == Comm.ROUTED then return false end
  -- Sync.WHISPER_GUILD_FALLBACK = false: a marked member (or one missing from the roster) gets nothing more
  if ns.Sync and ns.Sync.WHISPER_GUILD_FALLBACK == false then Comm.stats.wdropped = Comm.stats.wdropped + 1; return false end
  Comm.stats.routed = Comm.stats.routed + 1
  return Comm.Send(Comm.ROUTED, { to = key, t = tag, p = payload }, "GUILD", nil, onSent, urgent, skip)
end
-- the failed whisper messages of a character go again (the other variant, or the GUILD envelope)
local function resendRecent(key, t)
  local keep = {}
  for _, m in ipairs(Comm.recent) do
    if t - m.at <= Comm.WHISPER_WINDOW and not m.resent then
      if m.key == key then m.resent = true; pcall(m.resend) else keep[#keep + 1] = m end
    end
  end
  Comm.recent = keep
end
-- the server did not find `target` (one of our whisper targets): first failure -> the other variant once; the other
-- variant (or the probe after a mark) failing -> marked for UNREACHABLE_FOR s. Stale errors only get hidden.
function Comm.Failed(target, t)
  local e = Comm.wsent[target]
  if not (e and e.k) then return end
  t = t or now()
  local key = e.k
  local w = Comm.wstate[key]
  if not w then w = {}; Comm.wstate[key] = w end
  if e.probe and w.probe and not (w.fail and w.fail > w.probe) then
    w.fail, w.n, w.alt, w.probe = t, (w.n or 0) + 1, nil, nil
  elseif w.fail and t - w.fail < Comm.UNREACHABLE_FOR then
    return
  elseif not e.alt and not w.alt then
    w.alt = true
  elseif e.alt and w.alt then
    w.fail, w.n, w.alt, w.probe = t, (w.n or 0) + 1, nil, nil
  else
    return
  end
  resendRecent(key, t)
end
local function bareLower(n)
  local i = string.find(n, "[ %-]")
  return string.lower(i and string.sub(n, 1, i - 1) or n)
end
-- our whisper targets of the last WHISPER_WINDOW s that a "not found" name refers to. The server shows the name its
-- own way (the 1.2.1 whispered «Kas-CAMWOWEU4Realm6PvP» and got «Kas CAMWOWEU4Realm6PvP»): exact first, then the
-- same first name with our realm in the text, then the same first name.
function Comm.MatchNotFound(name, t)
  local exact, strong, loose = {}, {}, {}
  if type(name) ~= "string" or name == "" then return exact end
  t = t or now()
  local lname, bare = string.lower(name), bareLower(name)
  for target, e in pairs(Comm.wsent) do
    if t - e.t <= Comm.WHISPER_WINDOW then
      if string.lower(target) == lname then exact[#exact + 1] = target
      elseif bareLower(target) == bare then
        local realm = string.match(target, "%-(.+)$") or (type(e.k) == "string" and string.match(e.k, "%-(.+)$"))
        if realm and string.find(lname, string.lower(realm), 1, true) then strong[#strong + 1] = target
        else loose[#loose + 1] = target end
      end
    end
  end
  if #exact > 0 then return exact end
  if #strong > 0 then return strong end
  return loose
end
-- ERR_CHAT_PLAYER_NOT_FOUND_S as a pattern (the client's own string, any locale): "(.+)" where %s goes
local patFor, pat
local function notFoundName(msg)
  local f = ERR_CHAT_PLAYER_NOT_FOUND_S
  if type(f) ~= "string" then return nil end
  if f ~= patFor then
    patFor = f
    local p = f:gsub("%%%d%$s", "%%s")
    p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    local n
    p, n = p:gsub("%%%%s", "(.+)", 1)
    pat = (n == 1) and ("^" .. p .. "$") or false
  end
  return pat and string.match(msg, pat) or nil
end
-- CHAT_MSG_SYSTEM: true = the line is ours (a not found for a name we just whispered) and is hidden
local lastSys, lastSysAt
function Comm.OnSystemMessage(msg)
  if type(msg) ~= "string" then return false end
  if issecretvalue and issecretvalue(msg) then return false end
  local name = notFoundName(msg)
  if not name then return false end
  local t = now()
  local hits = Comm.MatchNotFound(name, t)
  if #hits == 0 then return false end
  if msg == lastSys and lastSysAt == t then return true end    -- the same line in another chat frame
  lastSys, lastSysAt = msg, t
  Comm.stats.notFound = Comm.stats.notFound + 1
  for _, target in ipairs(hits) do Comm.Failed(target, t) end
  return true
end
function Comm.SystemFilter(_, _, msg)
  local okF, hide = pcall(Comm.OnSystemMessage, msg)
  if okF and hide then return true end
  return false
end
-- a "W" envelope is mine: my key, or my first name on a realm under which nobody is in my roster (the sender read a
-- bare sender and guessed the realm)
function Comm.ForMe(to)
  if type(to) ~= "string" or not ns.me then return false end
  local me, key = ns.me(), keyOf(to)
  if not (me and key) then return false end
  if key == me then return true end
  if string.match(key, "^([^-]+)") ~= string.match(me, "^([^-]+)") then return false end
  return not (ns.roster and ns.roster(key))
end
function Comm.WhisperDiag()
  local marked, alt = 0, 0
  for key, w in pairs(Comm.wstate) do
    if Comm.Unreachable(key) then marked = marked + 1 elseif w.alt then alt = alt + 1 end
  end
  return ("whisper notFound=%d alt=%d marked=%d routed=%d dropped=%d notForMe=%d"):format(Comm.stats.notFound, alt,
    marked, Comm.stats.routed, Comm.stats.wdropped, Comm.stats.notForMe)
end

function Comm.Send(tag, payload, channel, target, onSent, urgent, skip)
  -- an identical message still waiting in the queue (same payload, channel and target, e.g.
  -- the same record version published twice while comms are locked) is not queued again (the stamp is not part of
  -- the key)
  local ch = channel or "GUILD"
  -- 1.2.2: callers pass the character key; the whisper leaves to the roster name with the surname (ns.whisperTarget)
  local wm
  if ch == "WHISPER" then
    local key = keyOf(target)
    if type(key) ~= "string" then return false end
    if offline(key) or (ns.isAmbiguous and ns.isAmbiguous(key)) then Comm.stats.wdropped = Comm.stats.wdropped + 1; return false end
    local v = variant(key)
    if v == "gone" then return routeGuild(tag, payload, key, onSent, urgent, skip) end
    local wt = target
    if ns.whisperTarget then
      wt = ns.whisperTarget(key, v == "alt")
      if not wt then return routeGuild(tag, payload, key, onSent, urgent, skip) end
    end
    target = wt
    wm = { key = key, variant = v, alt = (v == "alt") }
    -- never urgent: a re-send can run inside Q:pump (a drop check, TargetOffline), where pushing in front of the head
    -- being processed would lose the first part
    function wm.resend() return Comm.Send(tag, payload, "WHISPER", key, (not wm.done) and onSent or nil, nil, skip) end
  end
  local key = ch .. "|" .. tostring(target or "") .. "|" .. S.escape(S.encode({ v = Comm.PROTO, t = tag, p = payload }))
  if Comm.queue.pending and Comm.queue:pending(key) then
    Comm.queue.deduped = (Comm.queue.deduped or 0) + 1
    return false
  end
  local id = nextId()
  local pre = S.encode({ p = payload }):sub(1, -2)          -- snapshot: later changes to `payload` do not leak
  local tail = "s1:t" .. S.encode(tag) .. "s1:v" .. S.encode(Comm.PROTO) .. "e"
  local m = { items = {} }
  function m.build(at) return C.split(S.escape(pre .. "s1:s" .. S.encode(stampOf(at)) .. tail), id) end
  local parts = {}
  for i, part in ipairs(m.build(serverNow())) do
    local it = { msg = part, channel = ch, target = target }
    if i == 1 then it.stamp = m end
    m.items[i] = it
    parts[#parts + 1] = it
  end
  if #parts > Comm.MAX_PARTS then
    Comm.stats.tooBig = (Comm.stats.tooBig or 0) + 1
    if ns.debug then ns.debug("comm: " .. tostring(tag) .. " of " .. #parts .. " parts not sent (max " .. Comm.MAX_PARTS .. ")") end
    return false
  end
  if onSent and #parts > 0 then parts[#parts].onSent = onSent end
  if skip and #parts > 0 then
    local st = {}
    for i, it in ipairs(parts) do
      if i == 1 then
        it.first = true
        it.drop = function() if st.d == nil then local okS, r = pcall(skip); st.d = okS and r == true end return st.d end
      else it.drop = function() return st.d == true end end
    end
  end
  -- 1.2.2: a whisper not started yet whose character changed variant (or got marked) meanwhile goes again whole
  -- (other variant / GUILD envelope); one sent again after a failure drops its remaining parts
  if wm and #parts > 0 then
    parts[#parts].onSent = function() wm.done = true; if onSent then return onSent() end end
    for _, it in ipairs(parts) do
      local prev = it.drop
      it.wm = wm
      it.drop = function()
        if prev and prev() then return true end
        if wm.resent then return true end
        if wm.started then return false end
        if variant(wm.key) ~= wm.variant then wm.resent = true; pcall(wm.resend); return true end
        return false
      end
    end
  end
  local okP = true
  if urgent and Comm.queue.pushMessageFront then okP = Comm.queue:pushMessageFront(parts, key)
  elseif Comm.queue.pushMessage then okP = Comm.queue:pushMessage(parts, key)
  else for _, item in ipairs(parts) do Comm.queue:push(item) end end
  if Comm.Wake then Comm.Wake() end
  return okP
end

function Comm.Pending() return Comm.queue:size() end

local BLOCK_ON = { ENCOUNTER_START = "encounter", PVP_MATCH_ACTIVE = "pvp", CHALLENGE_MODE_START = "mplus" }
local BLOCK_OFF = { ENCOUNTER_END = "encounter", PVP_MATCH_COMPLETE = "pvp", PVP_MATCH_INACTIVE = "pvp",
                    CHALLENGE_MODE_COMPLETED = "mplus", CHALLENGE_MODE_RESET = "mplus" }

-- accepted addon channels. GUILD (the server only delivers it to members), or WHISPER
-- from someone in our guild roster. PARTY/RAID/INSTANCE/CHANNEL and strangers' whispers are ignored.
function Comm.ChannelOk(channel, sender)
  if channel == "GUILD" then return true end
  if channel == "WHISPER" and type(sender) == "string" and ns.roster then
    local okR, r = pcall(ns.roster, sender)
    return okR and r ~= nil
  end
  return false
end

local lastGc = 0
function Comm.OnEvent(event, ...)
  if event == "CHAT_MSG_ADDON" then   -- drop stale half-received messages every 30 s of traffic
    local t = now()
    if t - lastGc > 30 then lastGc = t; C.gc(Comm.assembler, t) end
  end
  if BLOCK_ON[event] then
    Comm.queue:setBlocked(BLOCK_ON[event], true)
  elseif BLOCK_OFF[event] then
    Comm.queue:setBlocked(BLOCK_OFF[event], false)
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- zone change / reload: recompute the blocks from the client state instead of clearing them
    Comm.RecomputeBlocks()
  elseif event == "CHAT_MSG_ADDON" then
    local prefix, msg, channel, sender = ...
    if prefix ~= Comm.PREFIX or type(msg) ~= "string" or type(sender) ~= "string" then return end
    -- never index tables with Midnight secret values
    if issecretvalue and (issecretvalue(sender) or issecretvalue(msg)) then return end
    if ns.isSelf and ns.isSelf(sender) then return end
    -- 1.2.2: two members share this sender's key (same realm and first name): nobody can tell them apart, ignore both
    if ns.isAmbiguous and ns.isAmbiguous(sender) then Comm.stats.ambiguous = (Comm.stats.ambiguous or 0) + 1; return end
    -- only the GUILD channel, or a WHISPER from a member of the guild roster
    if not Comm.ChannelOk(channel, sender) then Comm.stats.badChannel = (Comm.stats.badChannel or 0) + 1; return end
    local full = C.feed(Comm.assembler, sender, msg, now())
    if not full then return end
    local ok, data = S.decode(S.unescape(full))
    if not ok or type(data) ~= "table" then return end
    if data.v ~= Comm.PROTO then
      Comm.stats.badProto = Comm.stats.badProto + 1
      local v = tonumber(data.v)
      if v and v < Comm.PROTO and not Comm.oldPeers[sender] and Comm.OldPeerCount() < Comm.OLD_PEERS_MAX then
        Comm.oldPeers[sender] = true
        if ns.Sync and ns.Sync.OnOldPeer then pcall(ns.Sync.OnOldPeer) end
      end
      -- 1.2.2 (BRO 9-nov 03:49): a newer protocol (PROTO 3 = the 2.0) heard in the guild: a local notice, once per
      -- session (never sent anywhere)
      if v and v > Comm.PROTO and not Comm.newerSeen then
        Comm.newerSeen = true
        local text = ns.L and ns.L.NEWER_VERSION
        if text and ns.print then pcall(ns.print, text) end
      end
      return
    end
    Comm.stats.recv = Comm.stats.recv + 1
    local tag, payload = data.t, data.p
    -- 1.2.2: a whisper that went over GUILD in a "W" envelope: only its recipient handles it, as a whisper
    if tag == Comm.ROUTED then
      if channel ~= "GUILD" or type(payload) ~= "table" or type(payload.t) ~= "string" or payload.t == Comm.ROUTED
          or not Comm.ForMe(payload.to) then
        Comm.stats.notForMe = Comm.stats.notForMe + 1
        return
      end
      tag, payload, channel = payload.t, payload.p, "WHISPER"
    end
    -- a broken payload never raises inside CHAT_MSG_ADDON
    if Comm.handler then
      local sentAt = type(data.s) == "string" and tonumber(data.s) or nil   -- absent from older clients
      local okH = pcall(Comm.handler, tag, payload, sender, channel, sentAt)
      if not okH then Comm.stats.handlerErrors = (Comm.stats.handlerErrors or 0) + 1 end
    end
  end
end

local function apiTrue(fn)
  if type(fn) ~= "function" then return false end
  local ok, v = pcall(fn)
  return ok and v and true or false
end
function Comm.RecomputeBlocks()
  Comm.queue:setBlocked("encounter", apiTrue(((ns.encounterFn and ns.encounterFn()) or IsEncounterInProgress)))
  Comm.queue:setBlocked("pvp", apiTrue(C_PvP and C_PvP.IsMatchActive))
  Comm.queue:setBlocked("mplus", apiTrue(C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive))
end

local EVENTS = { "CHAT_MSG_ADDON", "ENCOUNTER_START", "ENCOUNTER_END", "PVP_MATCH_ACTIVE", "PVP_MATCH_COMPLETE",
                 "PVP_MATCH_INACTIVE", "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET",
                 "PLAYER_ENTERING_WORLD" }

function Comm.Init(handler)
  Comm.handler = handler
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, Comm.PREFIX)
  end
  -- 1.2.2: the server's "not found" for our own whispers never reaches the chat (Comm.SystemFilter)
  local addFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
  if type(addFilter) == "function" then pcall(addFilter, "CHAT_MSG_SYSTEM", Comm.SystemFilter) end
  local f = CreateFrame("Frame")
  for _, ev in ipairs(EVENTS) do pcall(f.RegisterEvent, f, ev) end -- unknown events are skipped
  f:SetScript("OnEvent", function(_, ev, ...) Comm.OnEvent(ev, ...) end)
  -- with C_Timer the queue runs on a 0.2 s ticker that only exists while something is pending
  -- (Comm.Wake on every Send) and is cancelled when the queue is empty; without C_Timer the old OnUpdate stays.
  -- Half-received chunks are collected on incoming traffic (Comm.OnEvent) instead of on a timer.
  local function step()
    if Comm.lockUntil and now() >= Comm.lockUntil then Comm.lockUntil = nil; Comm.queue:setBlocked("lockdown", false) end
    Comm.queue:pump(now())
  end
  local ticker
  if C_Timer and type(C_Timer.NewTicker) == "function" then
    function Comm.Wake()
      if ticker then return end
      local okT, t = pcall(C_Timer.NewTicker, 0.2, function()
        step()
        if Comm.queue:size() == 0 and not Comm.lockUntil and ticker then ticker:Cancel(); ticker = nil end
      end)
      if okT then ticker = t end
    end
    function Comm.Ticking() return ticker ~= nil end
  else
    local acc = 0
    f:SetScript("OnUpdate", function(_, elapsed)
      acc = acc + (elapsed or 0)
      if acc < 0.2 then return end
      acc = 0
      step()
    end)
    function Comm.Wake() end
    function Comm.Ticking() return true end
  end
  Comm.frame = f
end

return Comm
