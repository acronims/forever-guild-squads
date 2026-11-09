-- 1.2.2 (BRO in the game, 9-nov 03:03-03:11). With the 1.2.1 a guildmate's chat filled with «No hay ningún jugador
-- con el nombre Kas CAMWOWEU4Realm6PvP.», over and over (1.2.0: «... Magic Essency-CAMWOWEU4Realm6PvP»). BRO's test:
-- WoW Forever only delivers a whisper to the full name WITH the surname («Kas Pitas»); «Kas» alone does not work.
-- The identity of a character stays "Name-Realm" (author, signatures, certificates, indexes: ns.charKey / fullName);
-- the WHISPER target is built apart from the roster name (ns.whisperTarget): "Name Surname" on my realm,
-- "Name Surname-Realm" on another one. A server "not found" for a name we just whispered is hidden, the other variant
-- is tried once, then the character is marked for 10 min and whatever went to him by whisper goes over GUILD inside a
-- "W" envelope with the recipient.

-------------------------------------------------------------------------------
-- part 1: Comm.lua alone (own instance, mocked client)
local G = { CreateFrame = CreateFrame, GetTime = GetTime, C_ChatInfo = C_ChatInfo, C_Timer = C_Timer,
            ERR = ERR_CHAT_PLAYER_NOT_FOUND_S, AF = ChatFrame_AddMessageEventFilter }
local clock, sent, handled, filters = 1000, {}, {}, {}
local frame = { scripts = {} }
function frame:RegisterEvent() end
function frame:SetScript(k, fn) self.scripts[k] = fn end
local function install()
  CreateFrame = function() return frame end
  GetTime = function() return clock end
  C_Timer = nil
  ERR_CHAT_PLAYER_NOT_FOUND_S = "No hay ningún jugador con el nombre %s."
  ChatFrame_AddMessageEventFilter = function(ev, fn) filters[ev] = fn end
  C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end,
                 SendAddonMessage = function(_, msg, ch, to) sent[#sent + 1] = { msg = msg, ch = ch, to = to }; return 0 end }
end
local function restore()
  CreateFrame, GetTime, C_ChatInfo, C_Timer = G.CreateFrame, G.GetTime, G.C_ChatInfo, G.C_Timer
  ERR_CHAT_PLAYER_NOT_FOUND_S, ChatFrame_AddMessageEventFilter = G.ERR, G.AF
end
install()
local M = NS.Model
local ns = { Serialize = NS.Serialize, Chunk = NS.Chunk, Queue = NS.Queue, Model = M }
-- roster of the fake: key -> entry (the surname comes from "Name Surname-Realm", like readRoster)
local roster = { ["Kas-Realm"] = { online = true, surname = "Pitas" }, ["Ñoño-Otro"] = { online = true, surname = "Pérez" },
                 ["Off-Realm"] = { online = false, surname = "Zz" }, ["Ann-Realm"] = { online = true, surname = "Essency" } }
-- 2.0: these part-1 checks are the realm mode (ns.ID_MODE = "realm": the identity is the 1.2.2 key "Name-Realm" and the
-- 1.2.2 whisper rules stay whole, SPEC-v2.0 §6); part 1b below is the forever mode
ns.ID_MODE = "realm"
ns.fullName = function(n)
  if type(n) ~= "string" or n == "" then return nil end
  return (M.charName(n, "Realm"))
end
ns.id = ns.fullName
ns.roster = function(n) return roster[ns.fullName(n) or ""] end
ns.me = function() return "Ann-Realm" end
ns.isSelf = function(s) return ns.fullName(s) == "Ann-Realm" end
ns.whisperTarget = function(n, alt)
  local key = ns.fullName(n); local r = key and roster[key]
  if not r then return nil end
  return M.whisperTarget and M.whisperTarget(key, r.surname, "Realm", alt)
end
local okLoad, errLoad = pcall(loadmod, "Comm.lua", ns)
local Comm = ns.Comm
if okLoad and Comm then Comm.Init(function(tag, payload, sender, channel) handled[#handled + 1] = { tag, payload, sender, channel } end) end
restore()

local function within(fn)
  install()
  local okF, err = pcall(fn)
  restore()
  if not okF then error(err, 0) end
end
local function pump(sec) for _ = 1, (sec or 1) * 5 do clock = clock + 0.2; Comm.queue:pump(clock) end end
local function lastTo() return sent[#sent] and sent[#sent].to end
local function whispersTo(to) local n = 0; for _, s in ipairs(sent) do if s.ch == "WHISPER" and s.to == to then n = n + 1 end end return n end
local function sys(name) return filters.CHAT_MSG_SYSTEM and filters.CHAT_MSG_SYSTEM({}, "CHAT_MSG_SYSTEM", ERR_CHAT_PLAYER_NOT_FOUND_S:format(name)) end
local function decode(s)
  local okD, data
  local full = NS.Chunk.feed(NS.Chunk.newAssembler(), "x", s.msg, 0)
  if full then okD, data = NS.Serialize.decode(NS.Serialize.unescape(full)) end
  return okD and data or nil
end

test("1.2.2 names: the character key never carries the surname, in every plausible form", function()
  local cases = {
    { "Kas", "Kas-Realm", nil }, { "Kas-Realm", "Kas-Realm", nil }, { "Kas Pitas", "Kas-Realm", "Pitas" },
    { "Kas Pitas-Realm", "Kas-Realm", "Pitas" }, { "Kas-Realm Pitas", "Kas-Realm", "Pitas" },
    { "Kas Pitas-CAMWOWEU4Realm6PvP", "Kas-CAMWOWEU4Realm6PvP", "Pitas" },
    -- «Kas CAMWOWEU4Realm6PvP» (the text of the server error): read as name + surname, never as a whisper target
    { "Kas CAMWOWEU4Realm6PvP", "Kas-Realm", "CAMWOWEU4Realm6PvP" },
    { "Ñoño Pérez-Otro", "Ñoño-Otro", "Pérez" }, { "Ástrid Muñoz", "Ástrid-Realm", "Muñoz" }, { "Élan-Otro", "Élan-Otro", nil },
  }
  for _, c in ipairs(cases) do
    local key, surname = M.charName(c[1], "Realm")
    eq(key, c[2], "key of «" .. c[1] .. "»"); eq(surname, c[3], "surname of «" .. c[1] .. "»")
  end
end)

test("1.2.2 names: the whisper target is the full name with the surname, without the realm (the suffix only as the other variant)", function()
  ok(type(M.whisperTarget) == "function", "Model.whisperTarget exists")
  eq(M.whisperTarget("Kas-Realm", "Pitas", "Realm"), "Kas Pitas", "same realm: «Kas Pitas» (BRO's test)")
  eq(M.whisperTarget("Kas-Realm", "Pitas", "Realm", true), "Kas Pitas-Realm", "the other variant adds the suffix")
  eq(M.whisperTarget("Ñoño-Otro", "Pérez", "Realm"), "Ñoño Pérez", "another realm: «Name Surname» too (unique in the region)")
  eq(M.whisperTarget("Ñoño-Otro", "Pérez", "Realm", true), "Ñoño Pérez-Otro", "the other variant adds the suffix")
  eq(M.whisperTarget("Kas-Realm", nil, "Realm"), "Kas", "no surname in the roster: the bare name")
  ok(M.whisperTarget(nil, "Pitas", "Realm") == nil, "no key, no target")
end)

test("1.2.2 Comm: a whisper leaves to «Name Surname» (the roster name), never to the character key", function()
  ok(okLoad and Comm, "Comm.lua loads: " .. tostring(errLoad))
  within(function()
    sent = {}
    Comm.Send("X", { a = 1 }, "WHISPER", "Kas-Realm"); pump(2)
    eq(lastTo(), "Kas Pitas", "SendAddonMessage target"); eq(sent[#sent].ch, "WHISPER")
    Comm.Send("X", { a = 2 }, "WHISPER", "Kas Pitas-Realm"); pump(2)
    eq(lastTo(), "Kas Pitas", "a key with the surname gives the same target")
    Comm.Send("X", { a = 3 }, "WHISPER", "Ñoño-Otro"); pump(2)
    eq(lastTo(), "Ñoño Pérez", "another realm: no suffix either")
  end)
end)

test("1.2.2 Comm: the server's not found for our whisper is hidden; the other variant once; then GUILD with the recipient", function()
  within(function()
    sent = {}; clock = clock + 2000
    ok(type(filters.CHAT_MSG_SYSTEM) == "function", "a CHAT_MSG_SYSTEM filter is registered")
    Comm.Send("X", { b = 1 }, "WHISPER", "Kas-Realm"); pump(1)
    eq(lastTo(), "Kas Pitas")
    -- not ours: a name we never whispered stays in the chat
    ok(not sys("Zed Nadie"), "a not found for a name we did not whisper is shown")
    -- ours (the server may show it as it likes: «Kas Pitas», «Kas Pitas-Realm», «Kas Realm»)
    ok(sys("Kas Pitas") == true, "our whisper's not found is hidden")
    ok(sys("Kas Pitas") == true, "the same line in a second chat frame is hidden too")
    pump(2)
    eq(lastTo(), "Kas Pitas-Realm", "the failed message is sent again with the other variant")
    ok(sys("Kas Pitas-Realm") == true, "the other variant's not found is hidden")
    pump(2)
    local w = sent[#sent]
    eq(w.ch, "GUILD", "after both variants failed the message goes over GUILD")
    local d = decode(w)
    ok(d and d.t == "W" and type(d.p) == "table" and d.p.to == "Kas-Realm" and d.p.t == "X" and d.p.p.b == 1,
      "a W envelope with the recipient key and the original message")
    -- (c) no whisper to him while marked (10 min): new messages go over GUILD at once
    local before = whispersTo("Kas Pitas") + whispersTo("Kas Pitas-Realm")
    for i = 1, 5 do Comm.Send("X", { c = i }, "WHISPER", "Kas-Realm"); pump(1) end
    eq(whispersTo("Kas Pitas") + whispersTo("Kas Pitas-Realm"), before, "no whisper while marked")
    eq(sent[#sent].ch, "GUILD")
    -- after the mark: one probe whisper; the rest waits over GUILD until it is known whether it got through
    clock = clock + Comm.UNREACHABLE_FOR + 1
    Comm.Send("X", { d = 1 }, "WHISPER", "Kas-Realm"); Comm.Send("X", { d = 2 }, "WHISPER", "Kas-Realm"); pump(2)
    eq(whispersTo("Kas Pitas") + whispersTo("Kas Pitas-Realm"), before + 1, "a single probe whisper after the mark")
    ok(sys("Kas Pitas") == true, "the probe's not found is hidden")
    pump(2)
    for i = 1, 3 do Comm.Send("X", { e = i }, "WHISPER", "Kas-Realm"); pump(1) end
    eq(whispersTo("Kas Pitas") + whispersTo("Kas Pitas-Realm"), before + 1, "marked again: no more whispers")
    ok(Comm.stats.notFound >= 3, "not found counted: " .. tostring(Comm.stats.notFound))
  end)
end)

-- a failure seen while the queue pumps (SendAddonMessage -> 12 TargetOffline) re-sends from inside Q:pump: an urgent
-- message must not be pushed in front of the head being processed (its first part would be lost)
test("1.2.2 Comm: TargetOffline (12) on an urgent whisper: the other variant goes whole", function()
  within(function()
    sent = {}; clock = clock + 5000; Comm.wstate = {}
    local origSend = C_ChatInfo.SendAddonMessage
    C_ChatInfo.SendAddonMessage = function(p, msg, ch, to)
      if to == "Ñoño Pérez" then return 12 end
      return origSend(p, msg, ch, to)
    end
    Comm.Send("X", { u = string.rep("z", 400) }, "WHISPER", "Ñoño-Otro", nil, true); pump(6)
    local alt = {}
    for _, x in ipairs(sent) do if x.ch == "WHISPER" and x.to == "Ñoño Pérez-Otro" then alt[#alt + 1] = x end end
    ok(#alt >= 2, "the other variant left with every part: " .. #alt)
    local asm, full = NS.Chunk.newAssembler(), nil
    for _, x in ipairs(alt) do full = NS.Chunk.feed(asm, "x", x.msg, 0) or full end
    local okD, d = false, nil
    if full then okD, d = NS.Serialize.decode(NS.Serialize.unescape(full)) end
    ok(okD and d and d.t == "X" and d.p and d.p.u == string.rep("z", 400), "and it reassembles")
    Comm.wstate = {}
  end)
end)

test("1.2.2 Comm: no roster entry = no whisper (GUILD envelope); offline in the roster = nothing sent", function()
  within(function()
    sent = {}
    Comm.Send("X", { f = 1 }, "WHISPER", "Zed-Realm"); pump(2)
    eq(#sent, 1); eq(sent[1].ch, "GUILD", "a character missing from the roster goes over GUILD")
    local d = decode(sent[1]); ok(d and d.t == "W" and d.p.to == "Zed-Realm", "with the recipient")
    sent = {}
    Comm.Send("X", { f = 2 }, "WHISPER", "Off-Realm"); pump(2)
    eq(#sent, 0, "offline in the roster: nothing sent")
  end)
end)

-- BRO 9-nov 03:35 («por el canal de la guild no envíes nada sin permiso»): Sync.WHISPER_GUILD_FALLBACK = false
test("1.2.2 Comm: WHISPER_GUILD_FALLBACK = false: a marked member (or one missing from the roster) gets nothing over GUILD", function()
  within(function()
    sent = {}; clock = clock + 9000; Comm.wstate = {}
    ns.Sync = { WHISPER_GUILD_FALLBACK = false }
    local okF, errF = pcall(function()
      Comm.Send("X", { g = 1 }, "WHISPER", "Kas-Realm"); pump(1)
      ok(sys("Kas Pitas") == true, "hidden"); pump(2)
      ok(sys("Kas Pitas-Realm") == true, "hidden"); pump(2)
      for i = 1, 3 do Comm.Send("X", { h = i }, "WHISPER", "Kas-Realm"); pump(1) end
      Comm.Send("X", { h = 9 }, "WHISPER", "Zed-Realm"); pump(2)
      local guild = 0
      for _, x in ipairs(sent) do if x.ch == "GUILD" then guild = guild + 1 end end
      eq(guild, 0, "nothing over GUILD")
      eq(#sent, 2, "only the two whispers (main and the other variant): " .. #sent)
    end)
    ns.Sync = nil; Comm.wstate = {}
    if not okF then error(errF, 0) end
  end)
end)

-- BRO 9-nov 03:49: a local notice, once per session, the first time a newer protocol is heard (in the 1.2.2: PROTO 3;
-- in the 2.0: anything above PROTO 3)
test("Comm: hearing a newer PROTO prints «there is a newer version» once per session", function()
  within(function()
    local printed = {}
    ns.print = function(m) printed[#printed + 1] = tostring(m) end
    ns.L = { NEWER_VERSION = "Hay una versión más nueva de Guild Squads en tu hermandad: actualiza." }
    local function hear(v, id, who)
      local body = NS.Serialize.encode({ v = v, t = "H", p = {} })
      frame.scripts.OnEvent(frame, "CHAT_MSG_ADDON", Comm.PREFIX, id .. ":1/1:" .. body, "GUILD", who)
    end
    local P = Comm.PROTO
    hear(P + 1, "n1", "Neo-Realm"); hear(P + 1, "n2", "Neo2-Realm"); hear(1, "o1", "Old-Realm"); hear(P + 2, "n3", "Neo3-Realm")
    ns.print, ns.L = nil, nil
    eq(#printed, 1, "printed once: " .. table.concat(printed, " | "))
    ok(printed[1]:find("más nueva", 1, true), "the notice says there is a newer version")
  end)
end)

test("1.2.2 Comm: a W envelope is processed only by its recipient, as a whisper", function()
  within(function()
    local function receive(to, sender)
      local body = NS.Serialize.escape(NS.Serialize.encode({ v = Comm.PROTO, t = "W", p = { to = to, t = "Q", p = { z = to } } }))
      for _, part in ipairs(NS.Chunk.split(body, "w" .. tostring(#handled % 9))) do
        frame.scripts.OnEvent(frame, "CHAT_MSG_ADDON", Comm.PREFIX, part, "GUILD", sender or "Bob-Realm")
      end
    end
    local n = #handled
    receive("Ann-Realm"); eq(#handled, n + 1, "for me: handled")
    eq(handled[#handled][1], "Q"); eq(handled[#handled][2].z, "Ann-Realm"); eq(handled[#handled][4], "WHISPER", "as a whisper")
    receive("Kas-Realm"); eq(#handled, n + 1, "for someone else: ignored")
    -- the sender guessed my realm wrong (bare sender + his realm) and nobody in my roster has that key: mine
    receive("Ann-Otro"); eq(#handled, n + 2, "my name on a realm nobody in my roster has: mine")
  end)
end)

test("1.2.2 Comm: the error text of the 1.2.1 («Kas CAMWOWEU4Realm6PvP» for a whisper to «Kas-CAMWOWEU4Realm6PvP») matches", function()
  within(function()
    ok(type(Comm.MatchNotFound) == "function", "Comm.MatchNotFound exists")
    local t = clock
    Comm.wsent["Kas-CAMWOWEU4Realm6PvP"] = { k = "Kas-CAMWOWEU4Realm6PvP", t = t }
    Comm.wsent["Kasandra Pitas"] = { k = "Kasandra-Realm", t = t }
    local hits = Comm.MatchNotFound("Kas CAMWOWEU4Realm6PvP", t + 1)
    eq(#hits, 1, "one target"); eq(hits[1], "Kas-CAMWOWEU4Realm6PvP")
    eq(#Comm.MatchNotFound("Kas CAMWOWEU4Realm6PvP", t + Comm.WHISPER_WINDOW + 1), 0, "too late: not ours")
    Comm.wsent["Kas-CAMWOWEU4Realm6PvP"], Comm.wsent["Kasandra Pitas"] = nil, nil
  end)
end)

-- 2.0: M.migrateIdentity replaces M.sweepSurnames (tests/migration_spec.lua runs it on the 1.2.2 fixture). In forever
-- mode every saved key in the old form goes: the 1.2.0 «Name Surname-Realm» ones and the 1.2.2 «Name-Realm» ones.
test("2.0 SavedVariables: the 1.x keys (1.2.0 with a surname, 1.2.2 «Name-Realm») go at load in forever mode", function()
  ok(M.sweepSurnames == nil and type(M.migrateIdentity) == "function", "Model.migrateIdentity replaces sweepSurnames")
  local g = { trust = { keys = { ["Kas Pitas-Realm"] = { pk = "a", s = "strong" }, ["Kas-Realm"] = { pk = "b", s = "strong" },
                                 ["Bob Pitas"] = { pk = "c", s = "strong" } },
                        pend = { ["Kas Pitas-Realm"] = {} }, contested = { ["Kas Pitas-Realm"] = 1 }, suspects = { ["Kas Pitas-Realm"] = 2, ["Bob Pitas"] = 1 } },
              sig = { man = { ["Kas Pitas-Realm"] = { n = 1 }, ["Kas-Realm"] = { n = 2 } } },
              cert = { crt = { ["Kas Pitas-Realm"] = { n = 1 }, ["Kas-Realm"] = { n = 3 } } } }
  local root = { guilds = { G = g } }
  local ctx = { mode = "forever", me = "Ann Essency", oldMe = "Ann-Realm", now = 1, id = function() return nil end }
  local r = M.migrateIdentity(root, g, ctx)
  eq(r.swept, 9, "nine entries dropped")
  ok(g.trust.keys["Bob Pitas"] and next(g.trust.keys, next(g.trust.keys)) == nil, "only the 2.0 key stays")
  ok(next(g.trust.pend) == nil and next(g.trust.contested) == nil and g.trust.suspects["Bob Pitas"] == 1, "pend / contested / suspects")
  ok(next(g.sig.man) == nil and next(g.cert.crt) == nil, "manifests and certificates")
  local again = M.migrateIdentity(root, g, ctx)
  eq(again.swept, 0, "idempotent")
  eq(M.migrateIdentity({}, {}, { mode = "realm", me = "Ann-Realm" }).swept, 0, "realm mode: nothing")
end)

-------------------------------------------------------------------------------
-- part 1b: the 2.0 in WoW Forever (ns.ID_MODE = "forever", SPEC-v2.0 §6). The identity is «Name Surname» and it IS the
-- whisper target: never a «-Realm», no other variant (the first "not found" marks the character), MatchNotFound exact
-- or the identity with a «-...» the server added (never by the first name: two «Kas» exist), ForMe exact.
local fsent, fhandled, ffilters = {}, {}, {}
local fframe = { scripts = {} }
function fframe:RegisterEvent() end
function fframe:SetScript(k, fn) self.scripts[k] = fn end
local function finstall()
  CreateFrame = function() return fframe end
  GetTime = function() return clock end
  C_Timer = nil
  ERR_CHAT_PLAYER_NOT_FOUND_S = "No hay ningún jugador con el nombre %s."
  ChatFrame_AddMessageEventFilter = function(ev, fn) ffilters[ev] = fn end
  C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end,
                 SendAddonMessage = function(_, msg, ch, to) fsent[#fsent + 1] = { msg = msg, ch = ch, to = to }; return 0 end }
end
local froster = { ["Kas Pitas"] = { online = true }, ["Kas Mora"] = { online = true }, ["Ann Essency"] = { online = true },
                  ["Off Line"] = { online = false } }
local fns = { Serialize = NS.Serialize, Chunk = NS.Chunk, Queue = NS.Queue, Model = M, ID_MODE = "forever" }
-- ns.id of the contract for these names: «N A» and «N A-Realm» -> «N A»; a bare first name only when it is unique
fns.id = function(n)
  if type(n) ~= "string" or n == "" then return nil end
  local sp, dash = n:find(" ", 1, true), n:find("-", 1, true)
  if sp then return (dash and dash > sp) and n:sub(1, dash - 1) or n end
  local first, hit = dash and n:sub(1, dash - 1) or n, nil
  for id in pairs(froster) do if id:sub(1, #first + 1) == first .. " " then if hit then return nil end hit = id end end
  return hit
end
fns.roster = function(n) local id = fns.id(n); return id and froster[id] or nil end
fns.me = function() return "Ann Essency" end
fns.isSelf = function(s) return fns.id(s) == "Ann Essency" end
fns.whisperTarget = function(n, alt) local id = fns.id(n); if alt or not (id and froster[id]) then return nil end return id end
finstall()
local okF, errF = pcall(loadmod, "Comm.lua", fns)
local FComm = fns.Comm
if okF and FComm then FComm.Init(function(tag, payload, sender, channel) fhandled[#fhandled + 1] = { tag, payload, sender, channel } end) end
restore()
local function fwithin(fn)
  finstall()
  local okW, err = pcall(fn)
  restore()
  if not okW then error(err, 0) end
end
local function fpump(sec) for _ = 1, (sec or 1) * 5 do clock = clock + 0.2; FComm.queue:pump(clock) end end
local function fsys(name) return ffilters.CHAT_MSG_SYSTEM and ffilters.CHAT_MSG_SYSTEM({}, "CHAT_MSG_SYSTEM", ERR_CHAT_PLAYER_NOT_FOUND_S:format(name)) end
local function dashed() local n = 0; for _, s in ipairs(fsent) do if s.ch == "WHISPER" and tostring(s.to):find("-", 1, true) then n = n + 1 end end return n end

test("2.0 forever Comm: the whisper target is the identity «Kas Pitas» from any form of it, never with «-»", function()
  ok(okF and FComm, "Comm.lua loads in forever mode: " .. tostring(errF))
  fwithin(function()
    fsent = {}
    FComm.Send("X", { a = 1 }, "WHISPER", "Kas Pitas"); fpump(2)
    eq(fsent[#fsent].to, "Kas Pitas"); eq(fsent[#fsent].ch, "WHISPER")
    FComm.Send("X", { a = 2 }, "WHISPER", "Kas Pitas-CAMWOWEU4Realm6PvP"); fpump(2)
    eq(fsent[#fsent].to, "Kas Pitas", "the roster form gives the same target")
    FComm.Send("X", { a = 3 }, "WHISPER", "Kas Mora"); fpump(2)
    eq(fsent[#fsent].to, "Kas Mora", "the other Kas is another target")
    local n = #fsent
    FComm.Send("X", { a = 4 }, "WHISPER", "Kas"); fpump(2)
    ok(#fsent == n or fsent[#fsent].ch == "GUILD", "a bare «Kas» (two in the roster) is never whispered")
    eq(dashed(), 0, "no whisper target with «-»")
  end)
end)

test("2.0 forever Comm: the first not found marks (no other variant); the message goes over GUILD «W» to the identity", function()
  fwithin(function()
    fsent = {}; clock = clock + 20000; FComm.wstate = {}
    FComm.Send("X", { b = 1 }, "WHISPER", "Kas Pitas"); fpump(1)
    eq(fsent[#fsent].to, "Kas Pitas")
    ok(fsys("Kas Pitas") == true, "the not found is hidden")
    fpump(2)
    local w = fsent[#fsent]
    eq(w.ch, "GUILD", "no other variant: straight to GUILD")
    local d = decode(w)
    ok(d and d.t == "W" and d.p.to == "Kas Pitas" and d.p.t == "X" and d.p.p.b == 1, "a W envelope to «Kas Pitas»")
    ok(FComm.Unreachable("Kas Pitas"), "marked after one failure")
    local whispers = 0
    for _, s in ipairs(fsent) do if s.ch == "WHISPER" then whispers = whispers + 1 end end
    eq(whispers, 1, "one whisper only (no «Kas Pitas-Realm» retry)")
    ok(FComm.WhisperDiag():find("alt=0 marked=1", 1, true), FComm.WhisperDiag())
    -- the other Kas is not marked: his whispers still go
    FComm.Send("X", { b = 2 }, "WHISPER", "Kas Mora"); fpump(2)
    eq(fsent[#fsent].to, "Kas Mora"); eq(fsent[#fsent].ch, "WHISPER")
    eq(dashed(), 0, "no whisper target with «-»")
    FComm.wstate = {}
  end)
end)

test("2.0 forever Comm: MatchNotFound is exact (any case) or the identity with «-...»; never by the first name", function()
  fwithin(function()
    local t = clock
    FComm.wsent = { ["Kas Pitas"] = { k = "Kas Pitas", t = t } }
    eq(#FComm.MatchNotFound("Kas Pitas", t), 1, "exact")
    eq(#FComm.MatchNotFound("kas pitas", t), 1, "any case")
    eq(#FComm.MatchNotFound("Kas Pitas-CAMWOWEU4Realm6PvP", t), 1, "the server added the realm")
    eq(#FComm.MatchNotFound("Kas Mora", t), 0, "the other Kas: not ours")
    eq(#FComm.MatchNotFound("Kas", t), 0, "the first name alone: not ours")
    eq(#FComm.MatchNotFound("Kas CAMWOWEU4Realm6PvP", t), 0, "the 1.2.1 text: not ours")
    eq(#FComm.MatchNotFound("Kas Pitas", t + FComm.WHISPER_WINDOW + 1), 0, "too late")
    FComm.wsent = {}
  end)
end)

test("2.0 forever Comm: a «W» envelope is mine only for my exact identity", function()
  fwithin(function()
    local function receive(to)
      local body = NS.Serialize.escape(NS.Serialize.encode({ v = FComm.PROTO, t = "W", p = { to = to, t = "Q", p = { z = to } } }))
      for _, part in ipairs(NS.Chunk.split(body, "f" .. tostring(#fhandled % 9))) do
        fframe.scripts.OnEvent(fframe, "CHAT_MSG_ADDON", FComm.PREFIX, part, "GUILD", "Kas Pitas")
      end
    end
    local n = #fhandled
    receive("Ann Essency"); eq(#fhandled, n + 1, "mine"); eq(fhandled[#fhandled][4], "WHISPER", "as a whisper")
    receive("Ann Mora"); eq(#fhandled, n + 1, "another Ann: not mine")
    receive("Kas Pitas"); eq(#fhandled, n + 1, "someone else: not mine")
    receive("Ann Otro-Realm"); eq(#fhandled, n + 1, "no realm guess in forever mode")
  end)
end)

-------------------------------------------------------------------------------
-- part 2: the whole addon on the fake client of zload_spec.lua (roster «Name Surname-Realm», UnitName «Name»,
-- senders «Name-Realm»)
SMOKE_CHECKS = SMOKE_CHECKS or {}
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "1.2.2: roster «Name Surname-Realm»: SendAddonMessage gets «Bob Pitas», keys stay «Bob-Realm»", function(c)
  local ns = c.ns
  local Comm = ns.Comm
  local orig = { c.roster[1][1], c.roster[2][1], c.roster[3][1] }
  c.roster[1][1], c.roster[2][1], c.roster[3][1] = "Ann Essency-Realm", "Bob Pitas-Realm", "Cid Ñúñez-Otro"
  c.fire("GUILD_ROSTER_UPDATE"); c.tick(2)
  local origSend, got = C_ChatInfo.SendAddonMessage, {}
  C_ChatInfo.SendAddonMessage = function(_, msg, ch, to) got[#got + 1] = { ch = ch, to = to, msg = msg }; return 0 end
  local okAll, err = pcall(function()
    eq(ns.me(), "Ann-Realm", "UnitName «Ann» = Ann-Realm")
    ok(ns.roster("Bob-Realm") and ns.roster("Bob-Realm").surname == "Pitas", "roster keyed without the surname")
    ok(ns.roster("Cid-Otro"), "the member on another realm keyed Cid-Otro")
    ok(type(ns.whisperTarget) == "function", "ns.whisperTarget exists")
    eq(ns.whisperTarget("Bob-Realm"), "Bob Pitas", "same realm: «Bob Pitas»")
    eq(ns.whisperTarget("Bob"), "Bob Pitas", "a bare sender too")
    eq(ns.whisperTarget("Cid-Otro"), "Cid Ñúñez", "another realm: «Name Surname» too")
    eq(ns.whisperTarget("Cid-Otro", true), "Cid Ñúñez-Otro", "the other variant: with the suffix")
    -- a sender «Name Surname» without the realm (WoW Forever, research-surnames.md): the roster gives his realm
    eq(ns.fullName("Cid Ñúñez"), "Cid-Otro", "sender «Cid Ñúñez» = Cid-Otro (roster)")
    eq(ns.fullName("Bob Pitas"), "Bob-Realm", "sender «Bob Pitas» = Bob-Realm")
    eq(ns.fullName("Zed Nadie"), "Zed-Realm", "not in the roster: my realm, as before")
    ok(ns.isSelf("Ann Essency"), "our own echo «Ann Essency» is ours")
    ok(Comm.ChannelOk("WHISPER", "Cid Ñúñez"), "a whisper from «Cid Ñúñez» (another realm) is accepted")
    ok(ns.whisperTarget("Zed-Realm") == nil, "not in the roster: no target")
    -- with regional unique names (WoW Forever) a roster entry without its surname has no target that works
    c.roster[2][1] = "Bob-Realm"; c.fire("GUILD_ROSTER_UPDATE"); c.tick(2)
    eq(ns.whisperTarget("Bob-Realm"), "Bob", "classic client: the bare name")
    RegionalUniqueNamesEnabled = function() return true end
    local tNo = ns.whisperTarget("Bob-Realm")
    RegionalUniqueNamesEnabled = nil
    ok(tNo == nil, "Forever, no surname cached: no whisper target (GUILD envelope)")
    c.roster[2][1] = "Bob Pitas-Realm"; c.fire("GUILD_ROSTER_UPDATE"); c.tick(2)
    -- urgent: ahead of any backlog; the queue is pumped here (Comm may run on a C_Timer ticker the fake clock does
    -- not drive) with the blocks of earlier checks set aside
    local q, blocks, locked = Comm.queue, Comm.queue.blocks, Comm.queue.isLocked
    q.blocks, q.isLocked = {}, nil
    Comm.Send("X", { s = 1 }, "WHISPER", "Bob-Realm", nil, true)
    local t0 = math.max(GetTime(), q.last or 0)
    for k = 1, 6 do q:pump(t0 + k) end
    q.blocks, q.isLocked = blocks, locked
    local toBob, bad = 0, {}
    for _, s in ipairs(got) do
      if s.ch == "WHISPER" then
        if s.to == "Bob Pitas" then toBob = toBob + 1 end
        if not s.to:find(" ", 1, true) then bad[#bad + 1] = s.to end   -- every member has a surname here
      end
    end
    ok(toBob >= 1, "SendAddonMessage got «Bob Pitas»"); eq(#bad, 0, "whispers without the surname: " .. table.concat(bad, ","))
    -- the sender of CHAT_MSG_ADDON is «Bob-Realm» (no surname): his messages and his key stay under Bob-Realm
    eq(ns.fullName("Bob-Realm"), "Bob-Realm"); ok(Comm.ChannelOk("WHISPER", "Bob-Realm"), "a whisper from Bob is accepted")
  end)
  C_ChatInfo.SendAddonMessage = origSend
  c.roster[1][1], c.roster[2][1], c.roster[3][1] = orig[1], orig[2], orig[3]
  c.fire("GUILD_ROSTER_UPDATE"); c.tick(2)
  if Comm.wstate then Comm.wstate = {} end
  if not okAll then error(err, 0) end
end }

-- Anton's condition for 1.2.2 (9-nov 03:32): two members of the same realm with the same first name and different
-- surnames («Cid Pitas-Realm», «Cid Mora-Realm») share the key Cid-Realm until the 1.3 changes the identity. No crash,
-- and never the data of one on the other: the key is detected as ambiguous and both are ignored (diag line).
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "1.2.2: two «Cid» of the same realm with different surnames: ambiguous, both ignored, diag", function(c)
  local ns = c.ns
  local Comm = ns.Comm
  local origN, origCid = GetNumGuildMembers, c.roster[3][1]
  c.roster[3][1] = "Cid Pitas-Realm"
  c.roster[4] = { "Cid Mora-Realm", "Member", 4, 25, "Mage", "Durotar", "", "", true, 0, "MAGE" }
  GetNumGuildMembers = function() return 4 end
  c.fire("GUILD_ROSTER_UPDATE"); c.tick(2)
  local origH, got = Comm.handler, {}
  local okAll, err = pcall(function()
    ok(type(ns.isAmbiguous) == "function", "ns.isAmbiguous exists")
    ok(ns.isAmbiguous("Cid Pitas") and ns.isAmbiguous("Cid Mora") and ns.isAmbiguous("Cid-Realm"), "Cid-Realm is ambiguous")
    ok(not ns.isAmbiguous("Bob-Realm"), "Bob is not")
    ok(ns.roster("Cid-Realm") == nil, "the ambiguous key is not in the roster (records refused as notInGuild)")
    -- messages from either Cid never reach the handler
    Comm.handler = function(tag, p, sender) got[#got + 1] = sender end
    local body = NS.Serialize.escape(NS.Serialize.encode({ v = Comm.PROTO, t = "X", p = { a = 1 } }))
    for i, who in ipairs({ "Cid Pitas", "Cid Mora", "Cid-Realm", "Bob-Realm" }) do
      for _, part in ipairs(NS.Chunk.split(body, "a" .. i)) do Comm.OnEvent("CHAT_MSG_ADDON", Comm.PREFIX, part, "GUILD", who) end
    end
    eq(#got, 1, "only Bob's message was handled"); eq(got[1], "Bob-Realm")
    ok((Comm.stats.ambiguous or 0) >= 3, "counted: " .. tostring(Comm.stats.ambiguous))
    -- nothing is whispered to the ambiguous key, not even in an envelope
    local q, pushed = Comm.queue, 0
    local origPush = q.pushMessage
    q.pushMessage = function() pushed = pushed + 1; return true end
    Comm.Send("X", { b = 1 }, "WHISPER", "Cid-Realm")
    q.pushMessage = origPush
    eq(pushed, 0, "no whisper and no envelope to an ambiguous key")
    local diag = ns.RosterDiag()
    ok(diag:find("ambiguous=1", 1, true) and diag:find("Cid Pitas", 1, true) and diag:find("Cid Mora", 1, true), "diag: " .. diag)
  end)
  Comm.handler = origH
  GetNumGuildMembers = origN
  c.roster[4] = nil; c.roster[3][1] = origCid
  c.fire("GUILD_ROSTER_UPDATE"); c.tick(2)
  if not okAll then error(err, 0) end
end }

-- BRO 9-nov 03:35: nothing goes to the visible guild chat but the GM's celebrations (settings celOn, off by default)
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "1.2.2: the visible GUILD chat only gets the GM's celebrations (celOn, off by default)", function(c)
  local ns = c.ns
  local hits = {}
  for line in SOURCES["GuildSquads.toc"]:gmatch("[^\r\n]+") do
    if line:match("%.lua$") then
      local f = line:gsub("\\", "/")
      for l in (SOURCES[f] or ""):gmatch("[^\n]+") do
        local code = l:gsub("%-%-.*$", ""):gsub('"[^"]*"', '""')   -- code only (API names in strings are no call)
        if code:find("SendChatMessage", 1, true) then hits[#hits + 1] = f end   -- (SendTell only opens the edit box)
      end
    end
  end
  ok(#hits >= 1, "the celebrations send is found")
  for _, f in ipairs(hits) do eq(f, "Hall.lua", "a chat send outside the celebrations") end
  local src = SOURCES["Hall.lua"]
  local fn = src:match("function H%.PumpCelebrations%(%)(.-)\nend")
  ok(fn and fn:find("s.celOn ~= true", 1, true) and fn:find('"GUILD"', 1, true), "PumpCelebrations is gated by celOn")
  local outside = src:gsub("function H%.PumpCelebrations%(%).-\nend", "")
  for l in outside:gmatch("[^\n]+") do
    local code = l:gsub("%-%-.*$", ""):gsub('"[^"]*"', '""')
    ok(not code:find("SendChatMessage", 1, true), "SendChatMessage outside PumpCelebrations: " .. l)
  end
  eq(ns.Model.settingsOf(ns.Model.newState()).celOn, false, "celebrations off by default")
  -- dynamic: with celOn off, a pump never writes to the chat
  local spy, origG = {}, SendChatMessage
  local origC = C_ChatInfo.SendChatMessage
  SendChatMessage = function(_, ch) spy[#spy + 1] = tostring(ch) end
  C_ChatInfo.SendChatMessage = SendChatMessage
  local okAll, err = pcall(function()
    if ns.Model.settingsOf(ns.state).celOn ~= true then
      for _ = 1, 5 do ns.HallGlue.PumpCelebrations(); c.tick(1) end
      eq(#spy, 0, "nothing written to the chat with celebrations off")
    end
  end)
  SendChatMessage, C_ChatInfo.SendChatMessage = origG, origC
  if not okAll then error(err, 0) end
end }
