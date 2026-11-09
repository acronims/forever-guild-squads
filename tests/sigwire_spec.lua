-- v1.2 annex F, step (4) wiring: the author signs his own manifest (n grows when one of his records changes, kept
-- in the per-guild sig db under his name), D messages carry `m` = the manifests of the authors of their records
-- (once per author and destination every Sync.MAN_EVERY s, or when n changes), the receiver queues them (Sig.offer)
-- before applying the records and Sync.SigStep (1 verify per frame) re-applies the author's pending copies.
local M, S, T, E, G = NS.Model, NS.Serialize, NS.Trust, NS.Ed25519, NS.Sig
local ranks = { ["Gm-R"] = 0, ["Ali-R"] = 5, ["Bob-R"] = 5, ["Cid-R"] = 5, ["Eve-R"] = 7 }
local roster = makeRoster(ranks)
local T0 = 1795000000
local function key(tag) local sk = E.sha512("sigwire-key " .. tag):sub(1, 32) return sk, E.publicKey(sk) end
local skA, pkA = key("A")
local skB, pkB = key("B")

local function wireNs(me, sk, pk)
  local sent = {}
  local sigdb = G.st({})
  local state = M.newState()
  state.sigdb = sigdb
  local ns = { Model = M, Permissions = NS.Permissions, Serialize = S, Trust = T, Sig = G, P2P = NS.P2P, state = state,
               roster = roster, rosterReady = true, onlineCount = function() return 1 end, me = function() return me end,
               After = function(_, fn) fn() end, serverTime = function() return T0 end,
               trustDB = T.st({}), sigDB = sigdb, myPk = function() return pk end, mySk = function() return sk end,
               Comm = { Send = function(tag, p, ch, to, onSent, urgent, skip) sent[#sent + 1] = { tag, p, ch, to, onSent, urgent, skip } end } }
  loadmod("Sync.lua", ns)
  return ns, sent
end
local function prof(name, ts, note) return { k = "profile", id = name, a = name, ts = ts, sq = 1, d = { squad = "", role = "DAMAGER", note = note } } end
local function lastD(sent) for i = #sent, 1, -1 do if sent[i][1] == "D" then return sent[i][2] end end end

test("sigwire: own records go out with our signed manifest; n grows when one of them changes", function()
  G.resetQueue()
  local nsA, sentA = wireNs("Ali-R", skA, pkA)
  ok(nsA.Sync.Publish(prof("Ali-R", T0 + 1, "a")))
  local d = lastD(sentA)
  ok(d and type(d.m) == "table" and #d.m == 1, "one manifest in the message")
  local m = d.m[1]
  eq(m.a, "Ali-R")
  ok(G.validShape(m), "well formed")
  ok(E.verify(pkA, G.statement(m), T.unhex(m.s)), "signed with our key")
  ok(m.h["profile:Ali-R"] == G.recHash(M.stored(nsA.state, prof("Ali-R", T0 + 1))), "lists the record")
  ok(nsA.sigDB.own and nsA.sigDB.own["Ali-R"] and nsA.sigDB.own["Ali-R"].n == m.n, "kept in the sig db under our name")
  local n1 = m.n
  ok(nsA.Sync.Publish(prof("Ali-R", T0 + 2, "b")))
  local m2 = lastD(sentA).m
  ok(m2 and m2[1].n > n1, "a new version, a new n")
  -- the same records again (a reply to a hello) do not re-sign
  nsA.Sync.SendRecords({ M.stored(nsA.state, prof("Ali-R", T0 + 2)) }, "Bob-R")
  local m3 = lastD(sentA).m
  ok(m3 and m3[1].n == m2[1].n and m3[1].s == m2[1].s, "unchanged records: same manifest")
end)

test("sigwire: a relayed record waits for its author's manifest and is applied once Sync.SigStep verifies it", function()
  G.resetQueue()
  local nsA, sentA = wireNs("Ali-R", skA, pkA)
  ok(nsA.Sync.Publish(prof("Ali-R", T0 + 1, "a")))
  -- Bob heard it from Ali in person (the record, then her manifest): he holds Ali's key strong and her manifest
  local nsB, sentB = wireNs("Bob-R", skB, pkB)
  T.hearOwner(nsB.trustDB, "Ali-R", pkA, T0)
  local nD = 0
  for _, x in ipairs(sentA) do if x[1] == "D" then nsB.Sync.OnMessage("D", x[2], "Ali-R"); nD = nD + 1 end end
  eq(nD, 2, "the record, then the manifest alone")
  for _ = 1, 3 do nsB.Sync.SigStep() end
  ok(nsB.sigDB.man["Ali-R"], "Bob verified Ali's manifest")
  -- Bob relays Ali's profile to Eve, who knows Ali's key (hello) but not her manifest
  nsB.Sync.SendRecords({ M.stored(nsB.state, prof("Ali-R", T0 + 1)) }, "Eve-R")
  local dB = lastD(sentB)
  ok(dB.m and dB.m[1] and dB.m[1].a == "Ali-R", "Bob relays Ali's manifest next to her record")
  local nsE = wireNs("Eve-R", nil, nil)
  T.hearOwner(nsE.trustDB, "Ali-R", pkA, T0)
  nsE.Sync.OnMessage("D", dB, "Bob-R")
  eq(nsE.state.profiles["Ali-R"], nil, "not applied before the verify")
  nsE.Sync.SigStep()
  ok(nsE.state.profiles["Ali-R"], "applied after the verify")
  eq(nsE.state.profiles["Ali-R"].d.note, "a")
  -- a forged copy with Ali's manifest does not pass
  local nsE2 = wireNs("Eve-R", nil, nil)
  T.hearOwner(nsE2.trustDB, "Ali-R", pkA, T0)
  local fake = { r = { prof("Ali-R", T0 + 1, "falso") }, m = dB.m }
  nsE2.Sync.OnMessage("D", fake, "Bob-R")
  nsE2.Sync.SigStep()
  eq(nsE2.state.profiles["Ali-R"], nil, "a changed record is not in the manifest")
  -- manifests of authors that have no record in the message are ignored
  local nsE3 = wireNs("Eve-R", nil, nil)
  T.hearOwner(nsE3.trustDB, "Ali-R", pkA, T0)
  nsE3.Sync.OnMessage("D", { r = { prof("Cid-R", T0 + 1, "c") }, m = dB.m }, "Bob-R")
  eq(G.pending(), 0, "unrelated manifest not queued")
end)

-- S8 (CI 42505121559, 4 / 16 members): a member who logs in late gets an author's records and manifest relayed in a
-- hello reply whose `ks` copy of that key went out earlier (KEY_EVERY per destination): no key yet, so Sig.step
-- parks the manifest. The author's key then arrives in person (his hello / his own D), but only a certified key
-- (annex G) used to unpark: the manifest stayed parked and his records pending until another copy came (>= MAN_EVERY)
test("sigwire: a manifest parked for lack of its author's key is verified once the author is heard in person", function()
  G.resetQueue()
  local nsA, sentA = wireNs("Ali-R", skA, pkA)
  ok(nsA.Sync.Publish(prof("Ali-R", T0 + 1, "a")))
  local nsB, sentB = wireNs("Bob-R", skB, pkB)
  T.hearOwner(nsB.trustDB, "Ali-R", pkA, T0)
  for _, x in ipairs(sentA) do if x[1] == "D" then nsB.Sync.OnMessage("D", x[2], "Ali-R") end end
  for _ = 1, 3 do nsB.Sync.SigStep() end
  ok(nsB.sigDB.man["Ali-R"], "Bob verified Ali's manifest")
  G.resetQueue()
  nsB.Sync.SendRecords({ M.stored(nsB.state, prof("Ali-R", T0 + 1)) }, "Eve-R")
  local dB = lastD(sentB)
  ok(dB.m and dB.m[1] and dB.m[1].a == "Ali-R", "Bob relays Ali's manifest next to her record")
  local nsE = wireNs("Eve-R", nil, nil)
  nsE.Sync.OnMessage("D", { r = dB.r, m = dB.m }, "Bob-R")      -- without `ks`: Bob's copy of Ali's key went earlier
  for _ = 1, 3 do nsE.Sync.SigStep() end
  eq(nsE.sigDB.man["Ali-R"], nil, "no key yet: the manifest waits parked")
  eq(nsE.state.profiles["Ali-R"], nil, "and her record waits pending")
  nsE.Sync.OnOwnerKey("Ali-R", T.hearOwner(nsE.trustDB, "Ali-R", pkA, T0 + 5))   -- Ali's hello: her key in person
  for _ = 1, 3 do nsE.Sync.SigStep() end
  ok(nsE.sigDB.man["Ali-R"], "the parked manifest is verified with the key heard in person")
  ok(nsE.state.profiles["Ali-R"] and nsE.state.profiles["Ali-R"].d.note == "a", "and Ali's record is applied")
end)

test("sigwire: an author's manifest goes once per MAN_EVERY per destination unless n changes", function()
  G.resetQueue()
  local nsA, sentA = wireNs("Ali-R", skA, pkA)
  ok(nsA.Sync.Publish(prof("Ali-R", T0 + 1, "a")))
  local r = M.stored(nsA.state, prof("Ali-R", T0 + 1))
  nsA.Sync.SendRecords({ r }, "Bob-R")
  ok(lastD(sentA).m, "first whisper to Bob carries it")
  nsA.Sync.SendRecords({ r }, "Bob-R")
  ok(not lastD(sentA).m, "second one does not")
  ok(nsA.Sync.Publish(prof("Ali-R", T0 + 2, "b")))
  nsA.Sync.SendRecords({ M.stored(nsA.state, prof("Ali-R", T0 + 2)) }, "Bob-R")
  ok(lastD(sentA).m, "a new n goes again")
end)

test("sigwire: a new own key (/gsq trust newkey) re-signs the same records with it, n keeps growing", function()
  G.resetQueue()
  local nsA, sentA = wireNs("Ali-R", skA, pkA)
  ok(nsA.Sync.Publish(prof("Ali-R", T0 + 1, "a")))
  local m1 = lastD(sentA).m[1]
  local skN, pkN = key("A-new")
  nsA.mySk, nsA.myPk = function() return skN end, function() return pkN end
  ok(nsA.Sync.ResignOwn ~= nil, "Sync.ResignOwn exists")
  nsA.Sync.ResignOwn()
  nsA.Sync.SendRecords({ M.stored(nsA.state, prof("Ali-R", T0 + 1)) }, "Bob-R")
  local m2 = lastD(sentA).m
  ok(m2 and m2[1].n > m1.n, "a new n")
  ok(E.verify(pkN, G.statement(m2[1]), T.unhex(m2[1].s)), "signed with the new key")
  ok(not E.verify(pkA, G.statement(m2[1]), T.unhex(m2[1].s)), "not with the old one")
end)

-- AF4 (s8t2: 9642 parts, the `m` of hello replies ~4600): a GUILD hello reply carries no `m`; each manifest goes as
-- its own message {r = {}, m = {one}} with a skip check run when it reaches the head of the send queue: dropped if
-- that same manifest (author, n, signature) was heard on GUILD after the requester's hello (he got it already)
test("sigwire AF4: GUILD hello replies send manifests apart and drop them once heard on GUILD after the hello", function()
  G.resetQueue()
  local savedGT, clk = GetTime, 100
  GetTime = function() return clk end
  local nsA, sentA = wireNs("Ali-R", skA, pkA)
  ok(nsA.Sync.Publish(prof("Ali-R", T0 + 1, "a")))
  local mA = nsA.sigDB.own["Ali-R"]
  local r = M.stored(nsA.state, prof("Ali-R", T0 + 1))
  local nsB, sentB = wireNs("Bob-R", skB, pkB)
  T.hearOwner(nsB.trustDB, "Ali-R", pkA, T0)
  for _, x in ipairs(sentA) do if x[1] == "D" then nsB.Sync.OnMessage("D", x[2], "Ali-R", "GUILD") end end
  for _ = 1, 3 do nsB.Sync.SigStep() end
  ok(nsB.sigDB.man["Ali-R"], "Bob holds Ali's manifest")
  -- Eve says hello; Bob answers by GUILD with Ali's record
  ok(nsB.Sync.HelloHeard ~= nil, "Sync.HelloHeard exists")
  clk = 101
  nsB.Sync.HelloHeard("Eve-R")
  clk = 102
  local before = #sentB
  nsB.Sync.SendRecords({ r }, nil, nil, "Eve-R")
  local recMsg, manMsg
  for i = before + 1, #sentB do
    local x = sentB[i]
    if x[1] == "D" and #x[2].r > 0 then recMsg = x elseif x[1] == "D" and x[2].m then manMsg = x end
  end
  ok(recMsg and recMsg[3] == nil, "the records go by GUILD")
  ok(recMsg and recMsg[2].m == nil, "without `m`")
  ok(manMsg and manMsg[3] == nil and #manMsg[2].r == 0 and manMsg[2].m[1].a == "Ali-R", "the manifest goes apart by GUILD")
  ok(type(manMsg[7]) == "function", "with a skip check")
  eq(manMsg[7](), false, "not heard yet: it goes")
  -- a forged copy (other signature) heard on GUILD does not stop it
  local forged = { a = "Ali-R", n = mA.n, h = mA.h, s = string.rep("ab", 64) }
  nsB.Sync.OnMessage("D", { r = { r }, m = { forged } }, "Cid-R", "GUILD")
  eq(manMsg[7](), false, "a forged copy does not count")
  -- the same manifest heard by WHISPER does not count (only Bob got it)
  nsB.Sync.OnMessage("D", { r = { r }, m = { { a = mA.a, n = mA.n, h = mA.h, s = mA.s } } }, "Cid-R", "WHISPER")
  eq(manMsg[7](), false, "a whisper does not count")
  -- another replier sent it by GUILD after Eve's hello: Eve has it, ours is dropped
  nsB.Sync.OnMessage("D", { r = { r }, m = { { a = mA.a, n = mA.n, h = mA.h, s = mA.s } } }, "Cid-R", "GUILD")
  eq(manMsg[7](), true, "heard on GUILD after the hello: dropped")
  -- a later hello from Eve (she may have lost it): heard before that hello does not count
  nsB.Sync.HelloHeard("Eve-R", 1e9)
  eq(manMsg[7](), false, "heard before the requester's hello: it goes")
  -- receiver: a manifest-only message of a roster author is queued
  G.resetQueue()
  local nsE = wireNs("Eve-R", nil, nil)
  T.hearOwner(nsE.trustDB, "Ali-R", pkA, T0)
  nsE.Sync.OnMessage("D", manMsg[2], "Bob-R", "GUILD")
  eq(G.pending(), 1, "manifest-only message queued")
  GetTime = savedGT
end)

test("queue AF4: a message whose skip check says yes leaves the queue without spending tokens", function()
  local Q = NS.Queue
  local sent = {}
  local q = Q.new({ rate = 1, burst = 2, max = 50, send = function(it) sent[#sent + 1] = it.msg; return true end })
  local dropped = false
  local m = {}
  local p1 = { msg = "a1", first = true, drop = function() if not m.d then m.d = dropped and true or false end return m.d end }
  local p2 = { msg = "a2", drop = function() return m.d end }
  q:pushMessage({ p1, p2 }, "k1")
  q:pushMessage({ { msg = "b1" } }, "k2")
  dropped = true
  q:pump(0)
  eq(table.concat(sent, ","), "b1", "both parts of the skipped message dropped, the next one sent")
  eq(q:size(), 0)
  eq(q.skipped, 1, "counted")
end)

SMOKE_CHECKS = SMOKE_CHECKS or {}
-- full client (zload fake WoW): /gsq diag carries the signatures line of point 8 (annex F)
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "v1.2: /gsq diag sig line (verified/pending/rejected, keys strong/weak, replaced)", function(c)
  local rep = c.ns.DiagGlue.Report()
  ok(type(rep) == "string" and rep:find("sig verified=%d+ pending=%d+ rejected=%d+ keys%(strong/weak%)=%d+/%d+ replaced=%d+") and rep:find("cert held=%d+ cert=%d+ disputed=%d+ pending=%d+ rejected=%d+"),
    "diag sig line")
end }

-- full client: /gsq diag carries the line of point 8 of the scope (p2 proto= sample= suppressed= auth-pend= seals=)
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "v1.2: /gsq diag p2 line (proto, sample, suppressed, auth-pend, seals)", function(c)
  local rep = c.ns.DiagGlue.Report()
  ok(type(rep) == "string" and rep:find("p2 proto=2 sample=%d+ suppressed=%d+ auth%-pend=%d+ seals=%d+"), "diag p2 line")
  local y = c.ns.Sync.stats
  ok(type(y.sampled) == "number" and type(y.suppressed) == "number", "sample / suppressed counters in Sync.stats")
end }

-- full client: /gsq trust newkey in the same session makes a DIFFERENT key (fresh entropy, the pool starts over) and
-- announces it in a hello as soon as it exists (before: the pool had stopped sampling, so the same seed = same key)
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "v1.2 AF5: /gsq trust newkey in-session makes a different key from fresh entropy and says hello with it", function(c)
  local ns = c.ns
  for _ = 1, 100 do if ns.myPk() then break end; c.tick(1) end
  local pk1 = ns.myPk()
  ok(pk1, "own key made")
  local hellos, saved = {}, ns.Comm.Send
  ns.Comm.Send = function(kind, msg, ...) if kind == "H" then hellos[#hellos + 1] = msg end; return saved(kind, msg, ...) end
  ok(ns.NewOwnKey(), "newkey")
  local pk2
  for _ = 1, 200 do pk2 = ns.myPk(); if pk2 then break end; c.tick(1) end
  for _ = 1, 5 do c.tick(1) end
  ns.Comm.Send = saved
  ok(pk2 and pk2 ~= pk1, "a different key")
  local said
  for _, h in ipairs(hellos) do if h.pk == ns.Trust.hex(pk2) then said = true end end
  ok(said, "a hello carries the new key")
end }

-- full client: our records were published before our key existed (the entropy pool needs T.MIN_SAMPLES samples
-- first, so the login profile/presence go out unsigned). When the key is made, our manifest is signed and sent
-- by GUILD (MAN_DEBOUNCE s later) without waiting for a record change. Before: nobody held our manifest, and a
-- client who logged in later never verified our records relayed by others (S2 never converged, 68e70d3..261f62a).
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "v1.2 AF1: a key made after our records were published signs and sends our manifest", function(c)
  local ns = c.ns
  for _ = 1, 100 do if ns.myPk() then break end; c.tick(1) end
  local me = ns.me()
  local mine = 0
  for _, r in ipairs(ns.Model.allRecords(ns.state)) do if r.a == me then mine = mine + 1 end end
  ok(mine > 0, "we have own records (" .. mine .. ")")
  -- back to the login state: records, no key, no manifest (no old key either, so this is not a rotation)
  GuildSquadsDB.ownKeys[me] = nil
  if type(GuildSquadsDB.prevOwnKeys) == "table" then GuildSquadsDB.prevOwnKeys[me] = nil end
  ok(ns.NewOwnKey(), "key dropped, fresh pool")
  ns.sigDB.own[me] = nil
  ns.Sync.MarkOwnDirty()
  local mans, saved = {}, ns.Comm.Send
  ns.Comm.Send = function(kind, msg, ...)
    if kind == "D" and type(msg) == "table" and type(msg.m) == "table" then
      for _, m in ipairs(msg.m) do if m.a == me then mans[#mans + 1] = m end end
    end
    return saved(kind, msg, ...)
  end
  local pk
  for _ = 1, 200 do pk = ns.myPk(); if pk then break end; c.tick(1) end
  ok(pk, "a new key made")
  for _ = 1, ns.Sync.MAN_DEBOUNCE + 3 do c.tick(1) end
  ns.Comm.Send = saved
  local own = ns.sigDB.own[me]
  ok(own and own.s, "our manifest signed after the key was made")
  ok(#mans >= 1, "our manifest sent in a D (got " .. #mans .. ")")
  ok(own and ns.Ed25519.verify(pk, ns.Sig.statement(own), ns.Trust.unhex(own.s)), "signed with the new key")
end }

SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "v1.2 QA D1: ns.OnKeyReplaced is defined and drops what the replaced key signed", function(c)
  local ns = c.ns
  ok(type(ns.OnKeyReplaced) == "function", "ns.OnKeyReplaced is defined (Sync calls it on every key replacement)")
  local X = ns.P2P
  local st = X.st(ns.state)
  local pk = string.rep("\7", 32)
  local h = (pk:gsub(".", function(ch) return string.format("%02x", ch:byte()) end))
  local rec = { k = "profile", id = "Zz-Realm", a = "Zz-Realm", ts = 1795000000, sq = 1, d = { note = "falso" } }
  ns.state.profiles["Zz-Realm"] = rec
  st.via["profile:Zz-Realm"] = { v = X.vkey(rec), by = { "Y-Realm" }, t = 1795000000, sig = "cert", pk = h }
  ns.OnKeyReplaced("Zz-Realm", pk)
  eq(ns.state.profiles["Zz-Realm"], nil, "the profile the replaced key signed is dropped")
  eq(st.via["profile:Zz-Realm"], nil)
end }

SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "v1.2 sec r3 S1: a forged record of mine with '=' in its id does not break my manifest for others", function(c)
  local ns = c.ns
  local me = ns.me()
  local t = GetServerTime()
  ns.OnMine({ k = "profile", id = "x=1", a = me, ts = t, sq = 1, d = { note = "falso" } })
  local found = false
  for vk, _ in pairs(ns.state.repudiates or {}) do if vk:find("x=1", 1, true) then found = true end end
  ok(found, "the forged 'x=1' is repudiated")
  local m = ns.Sync.OwnManifest()
  ok(m and ns.Sig.validShape(m), "my next manifest still has a valid shape for any other client")
  local any = false
  for kid in pairs(m and m.h or {}) do if kid:find("x=1", 1, true) then any = true end end
  ok(any, "and it lists the repudiate")
  local pk = ns.myPk and ns.myPk()
  if pk then ok(ns.Ed25519.verify(pk, ns.Sig.statement(m), ns.Trust.unhex(m.s)), "signed over the new statement") end
end }

SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "v1.2 sec F1: forged records with my name make me sign at most a few repudiates per hour", function(c)
  local ns = c.ns
  local me = ns.me()
  local function nrep() local n = 0 for _ in pairs(ns.state.repudiates or {}) do n = n + 1 end return n end
  local before = nrep()
  local t = GetServerTime()
  for i = 1, 30 do
    ns.OnMine({ k = "profile", id = me, a = me, ts = t + i, sq = 50000 + i, d = { note = "falso " .. i } })
  end
  local made = nrep() - before
  ok(made >= 1, "the first forged versions are still repudiated (" .. made .. ")")
  ok(made <= 5, "30 forged versions make at most 5 repudiates (" .. made .. ")")
  -- sec r3 I4: the window is saved per guild (a /reload does not give 5 more)
  local saved = ns.gdb and ns.gdb.mineAt
  ok(type(saved) == "table" and #saved >= 1 and #saved <= 5, "the repudiate times are in the saved guild db (" .. tostring(saved and #saved) .. ")")
end }

SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "v1.2 sec F6: a GUILD copy with the real (a, n, s) and another body does not skip our manifest", function(c)
  local ns = c.ns
  local Sync = ns.Sync
  local real = { a = "Zz-Realm", n = 7, s = string.rep("ab", 64), h = { ["profile:Zz-Realm"] = string.rep("cd", 16) } }
  local fake = { a = real.a, n = real.n, s = real.s, h = {} }
  Sync.HelloHeard("Req-Realm", GetTime() - 10)
  Sync.NoteManHeard(fake)
  ok(not Sync.ManHeardSince(real, "Req-Realm"), "a fake body does not count as our manifest heard")
  Sync.NoteManHeard(real)
  ok(Sync.ManHeardSince(real, "Req-Realm"), "the same manifest heard does")
end }

-- QA r3 Q3-1: in 16001 IsEncounterInProgress lives only in C_InstanceEncounter; the one-per-frame signature step
-- must pause during a boss encounter through ns.encounterFn(), not through the (absent) global
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "QA r3 Q3-1: the signature step pauses in an encounter seen only through C_InstanceEncounter", function(c)
  local S = c.ns.Sync
  local gEnc, cEnc, rot, step = IsEncounterInProgress, C_InstanceEncounter, S.RotPending, S.SigStep
  local steps = 0
  IsEncounterInProgress = nil
  C_InstanceEncounter = { IsEncounterInProgress = function() return true end }
  S.RotPending = function() return 1 end
  S.SigStep = function() steps = steps + 1 end
  c.tick(5)
  local during = steps
  C_InstanceEncounter = { IsEncounterInProgress = function() return false end }
  c.tick(3)
  local after = steps
  IsEncounterInProgress, C_InstanceEncounter, S.RotPending, S.SigStep = gEnc, cEnc, rot, step
  eq(during, 0, "no signature step during the encounter")
  ok(after >= 1, "the step resumes after the encounter: " .. after)
end }

-- QA r3 Q3-3: the rotation queue does not outlive the guild (unloadGuild empties it) and a step without trust db
-- (guild unloaded) is no Lua error in the frame
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "QA r3 Q3-3: rotations queued when the guild unloads are dropped, no error without trust db", function(c)
  local ns = c.ns
  local Sync = ns.Sync
  local saved = ns.trustDB
  Sync.QueueRotation("Zq-Realm", string.rep("ab", 32), string.rep("cd", 64), "Y-Realm")
  ok(Sync.RotPending() >= 1, "a rotation queued")
  ns.trustDB = nil
  local okS, err = pcall(Sync.SigStep)
  ns.trustDB = saved
  ok(okS, "a step with the guild unloaded raises no error (" .. tostring(err) .. ")")
  Sync.QueueRotation("Zq-Realm", string.rep("ef", 32), string.rep("cd", 64), "Y-Realm")
  ok(type(Sync.ResetRotations) == "function", "Sync.ResetRotations")
  if Sync.ResetRotations then Sync.ResetRotations() end
  eq(Sync.RotPending(), 0, "the queue is empty after the reset")
  local hooked = false
  for _, fn in ipairs(ns.guildUnloadHooks or {}) do if fn == Sync.ResetRotations then hooked = true end end
  ok(hooked, "unloading the guild resets the rotation queue")
end }

-- fix/perf (runtime review A2): Sync.OwnManifest hashed every own record twice (once for the "same?" check, once in
-- G.build) on EVERY edit, plus the sign: 180 records = 360 sha512 = 0.7-2.5 s with the frame frozen. Now the hash of
-- each own record is cached by its version and passed to G.build: an edit costs one sha512. Counted with a wrapper
-- on Ed25519.sha512 (sign / verify hash through a local, so they are not counted).
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "fix/perf A2: an edit re-hashes only the changed own record, not all of them twice", function(c)
  local ns = c.ns
  local me = ns.me()
  local M, E, db = ns.Model, ns.Ed25519, ns.sigDB
  db.own = type(db.own) == "table" and db.own or {}
  local saved = db.own[me]
  local realAll, realSha = M.allRecords, E.sha512
  local recs, t = {}, GetServerTime()
  for i = 1, 150 do recs[i] = { k = "perf", id = me .. "#a2-" .. i, a = me, ts = t - i, sq = 1, d = { x = i } } end
  M.allRecords = function() return recs end
  local calls = 0
  E.sha512 = function(s) calls = calls + 1; return realSha(s) end
  local okR, err = pcall(function()
    ns.Sync.MarkOwnDirty()
    local m1 = ns.Sync.OwnManifest()
    ok(m1 and m1.h["perf:" .. recs[1].id], "built over the 150 records")
    ok(calls <= 150, "the first build hashes each record once (was twice): " .. calls)
    calls = 0
    recs[3] = { k = "perf", id = recs[3].id, a = me, ts = t + 10, sq = 2, d = { x = "edited" } }
    ns.Sync.MarkOwnDirty()
    local m2 = ns.Sync.OwnManifest()
    ok(m2 and m2.n > m1.n, "re-signed after the edit")
    ok(calls <= 1, "one edit = one sha512 (was 2 x 150): " .. calls)
    calls = 0
    ns.Sync.MarkOwnDirty()
    local m3 = ns.Sync.OwnManifest()
    eq(m3.n, m2.n, "dirty with no change: not re-signed")
    eq(calls, 0, "and no sha512 at all")
    E.sha512 = realSha
    eq(m2.h["perf:" .. recs[3].id], ns.Sig.recHash(recs[3]), "the edited record carries its fresh hash")
    local pk = ns.myPk and ns.myPk()
    if pk then ok(ns.Ed25519.verify(pk, ns.Sig.statement(m2), ns.Trust.unhex(m2.s)), "and the manifest verifies") end
  end)
  E.sha512, M.allRecords = realSha, realAll
  db.own[me] = saved
  ns.Sync.MarkOwnDirty()
  if not okR then error(err, 0) end
end }
