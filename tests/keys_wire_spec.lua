-- v1.2 annex F, step (3) wiring: our pk goes in the hello (learned strong by whoever hears it from us), relayed
-- records carry the strong keys of their authors (`ks`, learned weak with a quorum of 2), only for authors of the
-- records in that message and only for roster members; /gsq trust reset forgets a key.
local M, S, T, E = NS.Model, NS.Serialize, NS.Trust, NS.Ed25519
local ranks = { ["Gm-R"] = 0, ["Ali-R"] = 5, ["Bob-R"] = 5, ["Cid-R"] = 5, ["Eve-R"] = 7 }
local roster = makeRoster(ranks)
local T0 = 1795000000
local function key(tag) local sk = E.sha512("wire-key " .. tag):sub(1, 32) return sk, E.publicKey(sk) end
local _, pkA = key("A")
local _, pkB = key("B")
local _, pkF = key("F")

local function wireNs(me, myPk, p2p)
  local sent = {}
  local ns = { Model = M, Permissions = NS.Permissions, Serialize = S, Trust = T, state = M.newState(), roster = roster,
               rosterReady = true, onlineCount = function() return 1 end, me = function() return me end,
               fullName = function(n) return n end, After = function(_, fn) fn() end, serverTime = function() return T0 end,
               trustDB = T.st({}), myPk = function() return myPk end, Cert = NS.Cert, certDB = NS.Cert.st({}),
               Comm = { Send = function(tag, p, ch, to) sent[#sent + 1] = { tag, p, ch, to } end } }
  if p2p then ns.P2P = NS.P2P end
  loadmod("Sync.lua", ns)
  return ns, sent
end
local function prof(name, ts) return { k = "profile", id = name, a = name, ts = ts, sq = 1, d = { squad = "", role = "DAMAGER" } } end

test("keys: the hello carries our pk; a hello's pk is pinned strong for its sender", function()
  local ns, sent = wireNs("Ali-R", pkA)
  ns.Sync.Hello()
  local h
  for _, m in ipairs(sent) do if m[1] == "H" then h = m[2] end end
  ok(h and h.pk == T.hex(pkA), "own pk in the hello")
  local ns2 = wireNs("Bob-R", pkB)
  ns2.Sync.OnMessage("H", h, "Ali-R")
  local k, s = T.keyOf(ns2.trustDB, "Ali-R")
  ok(k == pkA and s == "strong", "learned strong from its owner")
  -- a hello without a key (no key yet) is fine; a malformed pk changes nothing
  ns2.Sync.OnMessage("H", { h = h.h, pk = "zz" }, "Cid-R")
  ok(T.keyOf(ns2.trustDB, "Cid-R") == nil)
  local ns3, sent3 = wireNs("Cid-R", nil)
  ns3.Sync.Hello()
  for _, m in ipairs(sent3) do if m[1] == "H" then ok(m[2].pk == nil, "no pk before we have a key") end end
end)

test("keys: records carry their authors' strong keys (ks); 2 relayers make only a candidate, 2 in-person certificates a cert key (annex G), the owner a strong one", function()
  NS.Cert.resetQueue()
  -- Bob holds Ali's key strong and replies with Ali's profile: ks has Ali's key
  local nsB, sentB = wireNs("Bob-R", pkB)
  T.hearOwner(nsB.trustDB, "Ali-R", pkA, T0)
  ok(nsB.Sync.Apply(prof("Ali-R", T0), "Ali-R"))
  nsB.Sync.SendRecords({ M.stored(nsB.state, prof("Ali-R", T0)) })
  local d
  for _, m in ipairs(sentB) do if m[1] == "D" then d = m[2] end end
  ok(d and d.ks and d.ks["Ali-R"] == T.hex(pkA), "author's key attached")
  -- the newcomer hears it from Bob, then from Cid: weak
  local nsN = wireNs("Eve-R", nil)
  nsN.Sync.OnMessage("D", d, "Bob-R")
  ok(T.keyOf(nsN.trustDB, "Ali-R") == nil, "one relayer: candidate")
  nsN.Sync.OnMessage("D", d, "Cid-R")
  ok(T.keyOf(nsN.trustDB, "Ali-R") == nil, "two relayers: still only a candidate (annex G: no quorum of relayers)")
  -- a candidate is never relayed onward (each relayer vouches only for keys heard in person or certified)
  local sentN = {}
  nsN.Comm.Send = function(tag, p) sentN[#sentN + 1] = { tag, p } end
  nsN.Sync.SendRecords({ M.stored(nsN.state, prof("Ali-R", T0)) or prof("Ali-R", T0) })
  for _, m in ipairs(sentN) do if m[1] == "D" then ok(not (m[2].ks and m[2].ks["Ali-R"]), "candidate key relayed") end end
  -- Eve heard Bob and Cid in person; their certificates list Ali's key: cert
  local C = NS.Cert
  local skB2 = key("B")
  local skC, pkC = key("C")
  T.hearOwner(nsN.trustDB, "Bob-R", pkB, T0); T.hearOwner(nsN.trustDB, "Cid-R", pkC, T0)
  local cB, cC = C.build("Bob-R", 1, { ["Ali-R"] = pkA }, skB2, pkB), C.build("Cid-R", 1, { ["Ali-R"] = pkA }, skC, pkC)
  nsN.Sync.OnMessage("D", { r = {}, c = cC }, "Bob-R")
  ok(C.pending() == 0, "a certificate relayed by someone else than its issuer is ignored")
  nsN.Sync.OnMessage("D", { r = {}, c = cB }, "Bob-R")
  nsN.Sync.OnMessage("D", { r = {}, c = cC }, "Cid-R")
  ok(C.pending() == 2, "both queued for a verify")
  for _ = 1, 3 do nsN.Sync.SigStep() end
  local k, s = T.keyOf(nsN.trustDB, "Ali-R")
  ok(k == pkA and s == "cert", "two in-person certificates: cert")
  -- keys for names without a record in the message, or outside the roster, are ignored
  nsN.Sync.OnMessage("D", { r = d.r, ks = { ["Gm-R"] = T.hex(pkF), ["Zed-R"] = T.hex(pkF) } }, "Bob-R")
  nsN.Sync.OnMessage("D", { r = d.r, ks = { ["Gm-R"] = T.hex(pkF), ["Zed-R"] = T.hex(pkF) } }, "Cid-R")
  ok(T.keyOf(nsN.trustDB, "Gm-R") == nil and T.keyOf(nsN.trustDB, "Zed-R") == nil, "unrelated keys ignored")
  -- the owner's own records carry his key: heard in person = strong
  local nsA, sentA = wireNs("Ali-R", pkA)
  ok(nsA.Sync.Apply(prof("Ali-R", T0 + 1), "Ali-R"))
  nsA.Sync.SendRecords({ M.stored(nsA.state, prof("Ali-R", T0 + 1)) })
  for _, m in ipairs(sentA) do if m[1] == "D" then d = m[2] end end
  ok(d.ks and d.ks["Ali-R"] == T.hex(pkA), "own key on own records")
  local nsZ = wireNs("Cid-R", nil)
  nsZ.Sync.OnMessage("D", d, "Ali-R")
  local kz, sz = T.keyOf(nsZ.trustDB, "Ali-R")
  ok(kz == pkA and sz == "strong", "own record from its author: strong")
end)

test("keys: the same author's key goes once per 10 min per destination", function()
  local nsB, sentB = wireNs("Bob-R", pkB)
  T.hearOwner(nsB.trustDB, "Ali-R", pkA, T0)
  nsB.Sync.Apply(prof("Ali-R", T0), "Ali-R")
  local r = M.stored(nsB.state, prof("Ali-R", T0))
  nsB.Sync.SendRecords({ r }); nsB.Sync.SendRecords({ r })
  local n = 0
  for _, m in ipairs(sentB) do if m[1] == "D" and m[2].ks then n = n + 1 end end
  eq(n, 1, "second message without the key")
  nsB.Sync.SendRecords({ r }, "Eve-R")
  local last = sentB[#sentB]
  ok(last[2].ks and last[2].ks["Ali-R"], "a whisper to someone else carries it")
end)

test("keys: the owner in person with a new key replaces the pinned one; /gsq trust reset still forgets", function()
  local db = T.st({})
  T.hearOwner(db, "Ali-R", pkA, T0)
  eq(T.hearOwner(db, "Ali-R", pkF, T0 + 1), "replaced")
  T.reset(db, "Ali-R")
  eq(T.hearOwner(db, "Ali-R", pkF, T0 + 2), "new")
  -- own key holder is separate from the guild's trust db (per character, not per guild)
  local holder = {}
  local pool = T.entropy()
  for i = 1, T.MIN_SAMPLES do pool.add(i, "x") end
  local sk, pk = T.ensureOwn(holder, pool)
  ok(sk and pk and holder.me and holder.keys == nil, "ensureOwn only writes `me`")
end)

test("keys: a 1.2 replier re-sends its certificate by WHISPER to the requester (S16b: offline when it changed), once per requester per CERT_REHELLO, capped", function()
  NS.Cert.resetQueue()
  local skB = key("B")
  local now = T0
  local nsB, sentB = wireNs("Bob-R", pkB, true)
  nsB.serverTime = function() return now end
  nsB.mySk = function() return skB end
  local function certsSent()
    local out = {}
    for _, m in ipairs(sentB) do if m[1] == "D" and m[2].c then out[#out + 1] = { c = m[2].c, ch = m[3], to = m[4] } end end
    return out
  end
  local function hello(from, pk) nsB.Sync.OnMessage("H", { h = {}, p2 = 2, pk = pk }, from) end
  -- nobody heard in person yet: an empty certificate is not re-sent
  hello("Cid-R")
  eq(#certsSent(), 0, "empty: not re-sent")
  -- Bob meets Ali in person; Eve (offline when it changed) says hello: Bob whispers it to Eve
  T.hearOwner(nsB.trustDB, "Ali-R", pkA, now)
  nsB.Sync.DropOwnCertCache()        -- what Sync.OnOwnerKey does when the key is heard through a hello (sec F5 cache)
  now = now + 5
  hello("Eve-R")
  local cs = certsSent()
  eq(#cs, 1, "re-sent on a 1.2 hello")
  ok(cs[1].c.i == "Bob-R" and #cs[1].c.e == 1 and cs[1].c.e[1] == NS.Cert.hash("Ali-R", pkA), "lists Ali")
  ok(cs[1].ch == "WHISPER" and cs[1].to == "Eve-R", "by WHISPER to the requester, not by GUILD")
  -- Eve again inside the window: nothing; Gm (another requester): his own whisper
  now = now + 10; hello("Eve-R")
  eq(#certsSent(), 1, "same requester inside the window: not again")
  now = now + 10; hello("Gm-R")
  cs = certsSent()
  ok(#cs == 2 and cs[2].to == "Gm-R", "another requester gets his own")
  -- a flood of hellos from many names inside one window: at most CERT_REHELLO_MAX whispers
  for i = 1, 3 * nsB.Sync.CERT_REHELLO_MAX do hello("F" .. i .. "-R") end
  eq(#certsSent(), nsB.Sync.CERT_REHELLO_MAX, "capped per window")
  -- the next window: Eve can get it again
  now = now + 2 * nsB.Sync.CERT_REHELLO
  hello("Eve-R")
  eq(#certsSent(), nsB.Sync.CERT_REHELLO_MAX + 1, "next window: re-sent")
  -- a 1.0 / 1.1 hello (no p2) does not trigger it
  now = now + 2 * nsB.Sync.CERT_REHELLO
  nsB.Sync.OnMessage("H", { h = {} }, "Cid-R")
  eq(#certsSent(), nsB.Sync.CERT_REHELLO_MAX + 1, "1.0/1.1 hello: nothing")
end)

test("keys: no certificate whisper while our own GUILD broadcast is pending (s8t9: the login burst changes it on every hello); after it, whispers resume", function()
  NS.Cert.resetQueue()
  local skB = key("B")
  local _, pkE = key("E")
  local now = T0
  local nsB, sentB = wireNs("Bob-R", pkB, true)
  local pending = {}
  nsB.After = function(_, fn) pending[#pending + 1] = fn end
  nsB.serverTime = function() return now end
  nsB.mySk = function() return skB end
  local function certsSent()
    local out = {}
    for _, m in ipairs(sentB) do if m[1] == "D" and m[2].c then out[#out + 1] = { ch = m[3], to = m[4] } end end
    return out
  end
  T.hearOwner(nsB.trustDB, "Ali-R", pkA, now)
  -- Eve logs in: her hello is the first time Bob hears her in person, so Bob's certificate changes and its GUILD
  -- broadcast is queued; Eve is online now and gets that one: no whisper on top
  now = now + 5
  nsB.Sync.OnMessage("H", { h = {}, p2 = 2, pk = T.hex(pkE) }, "Eve-R")
  eq(#certsSent(), 0, "broadcast pending: no whisper")
  now = now + nsB.Sync.CERT_DEBOUNCE
  local fns = pending; pending = {}
  for _, fn in ipairs(fns) do fn() end
  local cs = certsSent()
  ok(#cs == 1 and cs[1].ch == nil, "the queued broadcast goes by GUILD")
  -- later, someone who was offline when it changed says hello (nothing changes for Bob): whispered as before
  now = now + 5
  nsB.Sync.OnMessage("H", { h = {}, p2 = 2 }, "Gm-R")
  cs = certsSent()
  ok(#cs == 2 and cs[2].ch == "WHISPER" and cs[2].to == "Gm-R", "no broadcast pending: whispered")
end)

test("keys: the 1.2 hello lists the certificates we hold (cn); a replier re-sends its own only if the requester lacks it or holds an older n", function()
  NS.Cert.resetQueue()
  local skB = key("B")
  local now = T0
  local nsB, sentB = wireNs("Bob-R", pkB, true)
  nsB.After = function(_, fn) fn() end
  nsB.serverTime = function() return now end
  nsB.mySk = function() return skB end
  local function certsSent()
    local n = 0
    for _, m in ipairs(sentB) do if m[1] == "D" and m[2].c then n = n + 1 end end
    return n
  end
  T.hearOwner(nsB.trustDB, "Ali-R", pkA, now)
  local own = nsB.Sync.OwnCert()
  ok(own and own.n, "Bob has a certificate")
  local tok = nsB.Sync.CertTok
  ok(type(tok) == "function", "Sync.CertTok exists")
  -- the requester already holds Bob's certificate with this n: nothing re-sent
  nsB.Sync.OnMessage("H", { h = {}, p2 = 2, cn = tok("Cid-R", 5) .. tok("Bob-R", own.n) }, "Eve-R")
  eq(certsSent(), 0, "requester has it: not re-sent")
  -- an older n: re-sent
  now = now + 2 * nsB.Sync.CERT_REHELLO
  nsB.Sync.OnMessage("H", { h = {}, p2 = 2, cn = tok("Bob-R", own.n - 1) }, "Eve-R")
  eq(certsSent(), 1, "older n: re-sent")
  -- no cn at all: re-sent
  now = now + 2 * nsB.Sync.CERT_REHELLO
  nsB.Sync.OnMessage("H", { h = {}, p2 = 2 }, "Gm-R")
  eq(certsSent(), 2, "no cn: re-sent")
  -- a malformed / oversized cn is ignored (treated as empty)
  now = now + 2 * nsB.Sync.CERT_REHELLO
  nsB.Sync.OnMessage("H", { h = {}, p2 = 2, cn = { 1, 2 } }, "Cid-R")
  eq(certsSent(), 3, "bad cn: re-sent")
  -- our own hello carries the tokens of the certificates we hold (one per issuer, capped)
  local db = nsB.certDB
  db.crt = db.crt or {}
  for i = 1, nsB.Sync.CN_MAX + 5 do db.crt["X" .. i .. "-R"] = { n = 1000 + i, e = {}, s = "" } end
  sentB = {}
  local sent2 = {}
  nsB.Comm.Send = function(tag, p) sent2[#sent2 + 1] = { tag, p } end
  nsB.Sync.Hello()
  local h
  for _, m in ipairs(sent2) do if m[1] == "H" then h = m[2] end end
  ok(h and type(h.cn) == "string", "hello has cn")
  eq(#h.cn, nsB.Sync.CN_MAX * #tok("A", 1), "capped at CN_MAX tokens")
  ok(h.cn:find(tok("X" .. (nsB.Sync.CN_MAX + 5) .. "-R", 1000 + nsB.Sync.CN_MAX + 5), 1, true), "newest first")
end)

test("keys AF5 end to end: a relayed new key without the old key's signature is refused and noted; with it (kr) it is accepted and relayed on; in person it wins and is noted", function()
  NS.Cert.resetQueue()
  local skA = key("A")
  local nsC, sentC = wireNs("Cid-R", nil, true)
  T.hearOwner(nsC.trustDB, "Ali-R", pkA, T0)
  local function has(db, s) for _, a in ipairs(db.alerts) do if a == s then return true end end return false end
  -- Bob relays Ali's profile with another key and no rotation signature: refused, in diag (alerts)
  local rej0 = nsC.trustDB.n.rejected
  nsC.Sync.OnMessage("D", { r = { prof("Ali-R", T0 + 1) }, ks = { ["Ali-R"] = T.hex(pkF) } }, "Bob-R")
  local k, s = T.keyOf(nsC.trustDB, "Ali-R")
  ok(k == pkA and s == "strong", "unsigned change refused")
  ok(has(nsC.trustDB, "unsigned-keychange Ali-R"), "noted in alerts (diag)")
  eq(nsC.trustDB.n.rejected, rej0 + 1, "counted as rejected")
  -- a bad rotation signature (signed by the new key): refused too
  nsC.Sync.OnMessage("D", { r = { prof("Ali-R", T0 + 2) }, ks = { ["Ali-R"] = T.hex(pkF) },
                            kr = { ["Ali-R"] = T.hex(T.signRotation(key("F"), pkF, "Ali-R", pkF)) } }, "Bob-R")
  while nsC.Sync.RotPending() > 0 do nsC.Sync.SigStep() end   -- QA r2 N3: rotations verify in the frame step
  ok(T.keyOf(nsC.trustDB, "Ali-R") == pkA, "bad rotation refused")
  ok(has(nsC.trustDB, "badrotation Ali-R"), "bad rotation noted")
  -- signed by the old key: accepted, keeps its strength
  local rs = T.hex(T.signRotation(skA, pkA, "Ali-R", pkF))
  nsC.Sync.OnMessage("D", { r = { prof("Ali-R", T0 + 3) }, ks = { ["Ali-R"] = T.hex(pkF) }, kr = { ["Ali-R"] = rs } }, "Bob-R")
  while nsC.Sync.RotPending() > 0 do nsC.Sync.SigStep() end
  k, s = T.keyOf(nsC.trustDB, "Ali-R")
  ok(k == pkF and s == "strong", "signed rotation accepted")
  ok(has(nsC.trustDB, "rotated Ali-R"), "rotation noted")
  -- Cid relays Ali's records with the new key and its rotation signature
  local ks, kr = nsC.Sync.KeysFor({ prof("Ali-R", T0 + 3) }, "Eve-R")
  ok(ks and ks["Ali-R"] == T.hex(pkF), "relays the new key")
  ok(kr and kr["Ali-R"] == rs, "and its rotation signature")
  -- in person always wins, noted (BRO 8-nov 03:09)
  local _, pkG = key("G")
  nsC.Sync.OnMessage("H", { h = {}, pk = T.hex(pkG) }, "Ali-R")
  ok(T.keyOf(nsC.trustDB, "Ali-R") == pkG, "in person wins")
  ok(has(nsC.trustDB, "keychange Ali-R"), "in person change noted")
end)

test("keys AF5: /gsq trust newkey signs the new key with the old one; our relayed records carry it (kr)", function()
  NS.Cert.resetQueue()
  local skA = key("A")
  local nsA = wireNs("Ali-R", pkA, true)
  nsA.mySk = function() return skA end
  ok(type(nsA.Sync.OwnRotation) == "function", "Sync.OwnRotation exists")
  nsA.Sync.OwnRotation(skA, pkA, pkF)
  nsA.myPk = function() return pkF end
  local ks, kr = nsA.Sync.KeysFor({ prof("Ali-R", T0) }, "Bob-R")
  ok(ks and ks["Ali-R"] == T.hex(pkF), "own new key")
  ok(kr and T.rotate(T.st({ keys = { ["Ali-R"] = { pk = T.hex(pkA), s = "strong", t = T0 } } }), "Ali-R", pkF, T.unhex(kr["Ali-R"]), T0),
     "own rotation verifies with the old key")
end)

test("keys: F5: a flood of hellos from one name gets at most one reply per HELLO_MIN; our certificate is not recomputed on every hello", function()
  NS.Cert.resetQueue()
  local skB = key("B")
  local now = T0
  local nsB = wireNs("Bob-R", pkB, true)
  nsB.serverTime = function() return now end
  nsB.mySk = function() return skB end
  local owns = 0
  local C2 = {}
  for k, v in pairs(NS.Cert) do C2[k] = v end
  C2.own = function(...) owns = owns + 1; return NS.Cert.own(...) end
  nsB.Cert = C2
  T.hearOwner(nsB.trustDB, "Ali-R", pkA, now)
  ok(type(nsB.Sync.HELLO_MIN) == "number", "Sync.HELLO_MIN exists")
  local r0 = nsB.Sync.stats.replied
  for _ = 1, 30 do nsB.Sync.OnMessage("H", { h = {}, p2 = 2, cu = 1, cn = "" }, "Eve-R") end
  eq(nsB.Sync.stats.replied - r0, 1, "30 hellos from Eve in a burst: one reply")
  now = now + (nsB.Sync.HELLO_MIN or 0) + 1
  nsB.Sync.OnMessage("H", { h = {}, p2 = 2, cn = "" }, "Eve-R")
  eq(nsB.Sync.stats.replied - r0, 2, "after HELLO_MIN Eve is answered again")
  -- 30 hellos from 30 names at the same moment: the certificate is computed a few times, not 30
  owns = 0
  for i = 1, 30 do nsB.Sync.OnMessage("H", { h = {}, p2 = 2, cn = "" }, "X" .. i .. "-R") end
  ok(owns <= 2, "C.own ran " .. owns .. " times for 30 hellos")
end)

test("keys: F4: a name flipping its key in person every few seconds triggers at most one certificate broadcast per FLIP_MIN", function()
  NS.Cert.resetQueue()
  local skB = key("B")
  local now = T0
  local nsB, sentB = wireNs("Bob-R", pkB, true)
  nsB.serverTime = function() return now end
  nsB.mySk = function() return skB end
  local function guildCerts()
    local n = 0
    for _, m in ipairs(sentB) do if m[1] == "D" and m[2].c and m[3] == nil then n = n + 1 end end
    return n
  end
  for i = 1, 30 do
    local _, pk = key("flip" .. i)
    nsB.Sync.OnMessage("H", { h = {}, pk = T.hex(pk) }, "Eve-R")
    now = now + 5
  end
  local kpk = T.keyOf(nsB.trustDB, "Eve-R")
  local _, last = key("flip30")
  ok(kpk == last, "in person still wins: Eve's last key is the one we hold")
  ok(guildCerts() <= 2, "GUILD certificate broadcasts: " .. guildCerts())
  -- after FLIP_MIN a flip is broadcast again
  now = now + (nsB.Sync.FLIP_MIN or 0) + 1
  local before = guildCerts()
  local _, pk = key("flip31")
  nsB.Sync.OnMessage("H", { h = {}, pk = T.hex(pk) }, "Eve-R")
  eq(guildCerts(), before + 1, "after FLIP_MIN: broadcast")
end)

test("keys: QA D4 / sec F8: rotations (kr) are verified one per frame, never inside the message handler; a bad one is not verified twice", function()
  local nsB = wireNs("Bob-R", pkB, true)
  local pending = {}
  nsB.After = function(_, fn) pending[#pending + 1] = fn end
  local rot = 0
  local T2 = {}
  for k, v in pairs(T) do T2[k] = v end
  T2.rotate = function(...) rot = rot + 1; return T.rotate(...) end
  nsB.Trust = T2
  local names = { "Ali-R", "Cid-R", "Gm-R", "Eve-R" }
  for _, n in ipairs(names) do local _, pk = key("old" .. n); T.hearOwner(nsB.trustDB, n, pk, T0) end
  local r, ks, kr = {}, {}, {}
  for _, n in ipairs(names) do
    r[#r + 1] = prof(n, T0 + 1)
    local _, pk = key("new" .. n)
    ks[n] = T.hex(pk); kr[n] = ("ab"):rep(64)
  end
  local msg = { r = r, ks = ks, kr = kr }
  nsB.Sync.OnMessage("D", msg, "Fox-R")
  eq(rot, 0, "no rotation verified inside the handler")
  local steps = 0
  for _, fn in ipairs(pending) do fn() end
  while nsB.Sync.RotPending() > 0 and steps < 50 do
    local before = rot
    nsB.Sync.SigStep()
    ok(rot - before <= 1, "at most one rotation verify per frame")
    steps = steps + 1
  end
  eq(rot, #names, "each rotation verified once")
  nsB.Sync.OnMessage("D", msg, "Fox-R")
  while nsB.Sync.RotPending() > 0 and steps < 100 do nsB.Sync.SigStep(); steps = steps + 1 end
  eq(rot, #names, "the same bad rotation is not verified again")
end)

test("keys: QA r2 N3: rotations go through Sync.SigStep (the one-per-frame step paused in combat/encounters), no timer of their own", function()
  local nsB = wireNs("Bob-R", pkB, true)
  local pending = {}
  nsB.After = function(_, fn) pending[#pending + 1] = fn end
  local rot = 0
  local T2 = {}
  for k, v in pairs(T) do T2[k] = v end
  T2.rotate = function(...) rot = rot + 1; return T.rotate(...) end
  nsB.Trust = T2
  local names = { "Ali-R", "Cid-R", "Gm-R" }
  for _, n in ipairs(names) do local _, pk = key("n3old" .. n); T.hearOwner(nsB.trustDB, n, pk, T0) end
  local r, ks, kr = {}, {}, {}
  for _, n in ipairs(names) do
    r[#r + 1] = prof(n, T0 + 1)
    local _, pk = key("n3new" .. n)
    ks[n] = T.hex(pk); kr[n] = ("cd"):rep(64)
  end
  nsB.Sync.OnMessage("D", { r = r, ks = ks, kr = kr }, "Fox-R")
  for _, fn in ipairs(pending) do fn() end
  eq(rot, 0, "no rotation verified by a timer")
  eq(nsB.Sync.RotPending and nsB.Sync.RotPending(), #names, "the rotations wait for the frame step")
  for i = 1, #names do
    local before = rot
    nsB.Sync.SigStep()
    eq(rot - before, 1, "one rotation verify per SigStep")
  end
  eq(nsB.Sync.RotPending(), 0)
end)

test("keys: sec r2 R4: one sender cannot fill the rotation queue (ROT_PER_SENDER)", function()
  local nsB = wireNs("Bob-R", pkB, true)
  local per = nsB.Sync.ROT_PER_SENDER
  ok(type(per) == "number" and per < nsB.Sync.ROT_Q_MAX, "a per-sender cap below the queue size")
  for i = 1, nsB.Sync.ROT_Q_MAX do nsB.Sync.QueueRotation("N" .. i .. "-R", ("ab"):rep(32), ("cd"):rep(64), "Fox-R") end
  eq(nsB.Sync.RotPending(), per, "Fox fills only his share")
  nsB.Sync.QueueRotation("Ali-R", ("ab"):rep(32), ("ef"):rep(64), "Eve-R")
  eq(nsB.Sync.RotPending(), per + 1, "another sender still gets in")
  while nsB.Sync.RotPending() > 0 do nsB.Sync.SigStep() end
  nsB.Sync.QueueRotation("M1-R", ("ab"):rep(32), ("11"):rep(64), "Fox-R")
  eq(nsB.Sync.RotPending(), 1, "the share is freed once his rotations are verified")
end)

-- fix/perf (runtime review A3): the hello carried our whole certificate (~25 B per key heard in person): 400 keys =
-- 64 parts and Comm.Send dropped the hello (no sync, no pk); 100 keys = 33 parts per hello. Now the hello carries a
-- reference (cr = { n, h = 12 chars of the signature }); who lacks it asks (whispered D with ca) and the issuer sends
-- it once by GUILD for a burst of asks. Cert.OWN_MAX caps the certificate (the most recently heard keys) so the D
-- that carries it always fits the 64 parts.
local function commParts(tag, p)
  local cns = { Serialize = NS.Serialize, Chunk = NS.Chunk, Queue = NS.Queue }
  loadmod("Comm.lua", cns)
  return cns.Comm.Parts(tag, p)
end
local function helloOf(nsX)
  local sent = {}
  nsX.Comm.Send = function(tag, p, ch, to) sent[#sent + 1] = { tag, p, ch, to } end
  nsX.After = function() end
  nsX.Sync.Hello()
  for _, m in ipairs(sent) do if m[1] == "H" then return m[2] end end
end

test("keys perf A3: the hello carries a reference to our certificate, not the certificate (400 keys heard in person)", function()
  NS.Cert.resetQueue()
  local skB = key("B")
  local ns0 = wireNs("Bob-R", pkB, true)
  ns0.mySk = function() return skB end
  T.hearOwner(ns0.trustDB, "K0-R", E.sha512("a3 pk 0"):sub(1, 32), T0)
  local p0 = commParts("H", helloOf(ns0))
  local nsB = wireNs("Bob-R", pkB, true)
  nsB.mySk = function() return skB end
  for i = 1, 400 do T.hearOwner(nsB.trustDB, ("K%d-R"):format(i), E.sha512("a3 pk " .. i):sub(1, 32), T0) end
  local h = helloOf(nsB)
  ok(h ~= nil, "hello sent")
  eq(h.c, nil, "no certificate in the hello")
  local own = nsB.Sync.OwnCert()
  ok(own and #own.e == 400, "the certificate lists the 400 keys")
  ok(type(h.cr) == "table" and h.cr.n == own.n and h.cr.h == own.s:sub(1, 12), "the hello carries n and a hash of it")
  local p400 = commParts("H", h)
  local old = {}
  for k, v in pairs(h) do old[k] = v end
  old.cr, old.c = nil, { i = own.i, n = own.n, e = own.e, s = own.s }
  print(("  A3 measure: hello parts with 1 key %d; with 400 keys %d (the 1.2 hello with c would be %d)"):format(p0, p400, commParts("H", old)))
  ok(p400 <= p0 + 1, ("hello with 400 keys: %d parts, with 1 key: %d (it was ~+41)"):format(p400, p0))
end)

test("keys perf A3: the certificate is capped at Cert.OWN_MAX (most recent keys) and its D fits 64 parts", function()
  NS.Cert.resetQueue()
  local C = NS.Cert
  ok(type(C.OWN_MAX) == "number" and C.OWN_MAX <= C.MAX_ENTRIES, "Cert.OWN_MAX <= what a receiver takes")
  local skB = key("B")
  local nsB = wireNs("Bob-R", pkB, true)
  nsB.mySk = function() return skB end
  local N = C.OWN_MAX + 20
  for i = 1, N do T.hearOwner(nsB.trustDB, ("Q%d-R"):format(i), E.sha512("a3 cap " .. i):sub(1, 32), T0 - N + i) end
  local own = nsB.Sync.OwnCert()
  eq(#own.e, C.OWN_MAX, "capped")
  local set = {}
  for _, x in ipairs(own.e) do set[x] = true end
  ok(set[C.hash("Q" .. N .. "-R", E.sha512("a3 cap " .. N):sub(1, 32))], "the newest key is listed")
  ok(not set[C.hash("Q1-R", E.sha512("a3 cap 1"):sub(1, 32))], "the oldest is not")
  local parts = commParts("D", { r = {}, c = { i = own.i, n = own.n, e = own.e, s = own.s } })
  ok(parts <= 64, "the D with the capped certificate: " .. parts .. " parts")
end)

test("keys perf A3: who lacks the certificate of a hello's sender asks for it; the sender answers a burst once by GUILD", function()
  NS.Cert.resetQueue()
  local skA, skB = key("A"), key("B")
  local nsA, sentA = wireNs("Ali-R", pkA, true)
  nsA.mySk = function() return skA end
  T.hearOwner(nsA.trustDB, "Cid-R", E.sha512("a3 cid"):sub(1, 32), T0)
  local nsB, sentB = wireNs("Bob-R", pkB, true)
  nsB.mySk = function() return skB end
  local own = nsA.Sync.OwnCert()
  local hello = { h = {}, p2 = 2, pk = T.hex(pkA), cr = { n = own.n, h = own.s:sub(1, 12) } }
  nsB.Sync.OnMessage("H", hello, "Ali-R")
  local ask
  for _, m in ipairs(sentB) do if m[1] == "D" and m[2].ca and m[3] == "WHISPER" and m[4] == "Ali-R" then ask = m[2] end end
  ok(ask ~= nil, "Bob lacks Ali's certificate: he asks her by whisper")
  nsA.Sync.OnMessage("D", ask, "Bob-R", "WHISPER")
  nsA.Sync.OnMessage("D", ask, "Eve-R", "WHISPER")
  local guild
  local n = 0
  for _, m in ipairs(sentA) do if m[1] == "D" and m[2].c and m[3] == nil then n = n + 1; guild = m[2] end end
  eq(n, 1, "one GUILD send of the certificate for the burst of asks")
  nsB.Sync.OnMessage("D", guild, "Ali-R", "GUILD")
  for _ = 1, 5 do if NS.Cert.pending() > 0 then nsB.Sync.SigStep() end end
  ok(NS.Cert.holds(nsB.certDB, "Ali-R"), "Bob holds Ali's certificate")
  for k in pairs(sentB) do sentB[k] = nil end
  nsB.Sync.OnMessage("H", hello, "Ali-R")
  for _, m in ipairs(sentB) do ok(not (m[1] == "D" and m[2].ca), "the next hello with the same reference: no ask") end
end)

-- fix/perf (runtime review M2): the timers that sign (QueueOwnCert 30 s, QueueOwnManifest 5 s, the answer to a
-- certificate ask) fired in combat and encounters; only the verifies were paused. Now they wait (Sync.SIGN_RETRY s)
-- until combat / the encounter is over. Counted with a wrapper on Ed25519.sign.
test("keys perf M2: no signature in combat or an encounter; it is signed and sent once they are over", function()
  NS.Cert.resetQueue()
  local skB = key("B")
  local nsB, sentB = wireNs("Bob-R", pkB, true)
  nsB.mySk = function() return skB end
  local timers = {}
  nsB.After = function(_, fn) timers[#timers + 1] = fn end
  local function run() local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end end
  local realSign, signs = E.sign, 0
  E.sign = function(...) signs = signs + 1; return realSign(...) end
  local realCombat, enc = rawget(_G, "InCombatLockdown"), false
  local okR, err = pcall(function()
    InCombatLockdown = function() return true end
    T.hearOwner(nsB.trustDB, "Ali-R", pkA, T0)
    nsB.Sync.QueueOwnCert()
    run()
    eq(signs, 0, "in combat: not signed")
    ok(#timers == 1, "re-scheduled")
    InCombatLockdown = function() return false end
    nsB.encounterFn = function() return function() return enc end end   -- like ns.encounterFn: gives the API function
    enc = true
    run()
    eq(signs, 0, "in an encounter: not signed")
    enc = false
    run()
    eq(signs, 1, "after: signed once")
    local n = 0
    for _, m in ipairs(sentB) do if m[1] == "D" and m[2].c then n = n + 1 end end
    eq(n, 1, "and sent")
  end)
  E.sign, InCombatLockdown = realSign, realCombat
  if not okR then error(err, 0) end
end)
