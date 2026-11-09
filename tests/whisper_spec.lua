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
ns.fullName = function(n)
  if type(n) ~= "string" or n == "" then return nil end
  return (M.charName(n, "Realm"))
end
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

test("1.2.2 names: the whisper target is the full name with the surname (realm suffix only for another realm)", function()
  ok(type(M.whisperTarget) == "function", "Model.whisperTarget exists")
  eq(M.whisperTarget("Kas-Realm", "Pitas", "Realm"), "Kas Pitas", "same realm: «Kas Pitas» (BRO's test)")
  eq(M.whisperTarget("Kas-Realm", "Pitas", "Realm", true), "Kas Pitas-Realm", "the other variant adds the suffix")
  eq(M.whisperTarget("Ñoño-Otro", "Pérez", "Realm"), "Ñoño Pérez-Otro", "another realm: «Name Surname-Realm»")
  eq(M.whisperTarget("Ñoño-Otro", "Pérez", "Realm", true), "Ñoño Pérez", "the other variant drops the suffix")
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
    eq(lastTo(), "Ñoño Pérez-Otro", "another realm keeps the suffix")
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

test("1.2.2 SavedVariables: the 1.2.0 keys with a surname are dropped at load (trust, manifests, certificates)", function()
  ok(type(M.sweepSurnames) == "function", "Model.sweepSurnames exists")
  local g = { trust = { keys = { ["Kas Pitas-Realm"] = { pk = "a", s = "strong" }, ["Kas-Realm"] = { pk = "b", s = "strong" } },
                        pend = { ["Kas Pitas-Realm"] = {} }, contested = { ["Kas Pitas-Realm"] = 1 }, suspects = { ["Kas Pitas-Realm"] = 2, ["Bob-Realm"] = 1 } },
              sig = { man = { ["Kas Pitas-Realm"] = { n = 1 }, ["Kas-Realm"] = { n = 2 } } },
              cert = { crt = { ["Kas Pitas-Realm"] = { n = 1 }, ["Kas-Realm"] = { n = 3 } } } }
  eq(M.sweepSurnames(g), 6, "six entries dropped")
  ok(g.trust.keys["Kas-Realm"] and not g.trust.keys["Kas Pitas-Realm"], "trust keys")
  ok(next(g.trust.pend) == nil and next(g.trust.contested) == nil and g.trust.suspects["Bob-Realm"] == 1, "pend / contested / suspects")
  ok(g.sig.man["Kas-Realm"] and not g.sig.man["Kas Pitas-Realm"], "manifests")
  ok(g.cert.crt["Kas-Realm"] and not g.cert.crt["Kas Pitas-Realm"], "certificates")
  eq(M.sweepSurnames(g), 0, "idempotent"); eq(M.sweepSurnames({}), 0, "empty partition")
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
    eq(ns.whisperTarget("Cid-Otro"), "Cid Ñúñez-Otro", "another realm: with the suffix")
    ok(ns.whisperTarget("Zed-Realm") == nil, "not in the roster: no target")
    Comm.Send("X", { s = 1 }, "WHISPER", "Bob-Realm", nil, true)   -- urgent: ahead of any backlog
    c.tick(3)
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
