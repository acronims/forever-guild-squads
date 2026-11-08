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

test("keys: a 1.2 replier re-sends its certificate by GUILD (S16b: who was offline when it changed), once per CERT_REHELLO, coalesced", function()
  NS.Cert.resetQueue()
  local skB = key("B")
  local now = T0
  local nsB, sentB = wireNs("Bob-R", pkB, true)
  local later = {}
  nsB.After = function(d, fn) later[#later + 1] = { d, fn } end
  nsB.serverTime = function() return now end
  nsB.mySk = function() return skB end
  local function certsSent()
    local out = {}
    for _, m in ipairs(sentB) do if m[1] == "D" and m[2].c then out[#out + 1] = { c = m[2].c, ch = m[3], to = m[4] } end end
    return out
  end
  local H = { h = {}, p2 = 2 }
  local function hello(from, pk) local h = { h = H.h, p2 = 2, pk = pk }; nsB.Sync.OnMessage("H", h, from) end
  -- nobody heard in person yet: an empty certificate is not re-sent
  hello("Cid-R")
  eq(#certsSent(), 0, "empty: not re-sent")
  -- Bob meets Ali in person; Eve (offline when it changed) says hello: Bob re-sends it by GUILD
  T.hearOwner(nsB.trustDB, "Ali-R", pkA, now)
  now = now + 5
  hello("Eve-R")
  local cs = certsSent()
  eq(#cs, 1, "re-sent on a 1.2 hello")
  ok(cs[1].c.i == "Bob-R" and #cs[1].c.e == 1 and cs[1].c.e[1] == NS.Cert.hash("Ali-R", pkA), "lists Ali")
  ok(cs[1].ch == nil and cs[1].to == nil, "by GUILD")
  -- two more hellos inside the window: one coalesced send at its end, not two
  now = now + 10; hello("Gm-R")
  now = now + 10; hello("Cid-R")
  eq(#certsSent(), 1, "not right away")
  local n = 0
  for _, l in ipairs(later) do if l[1] == nsB.Sync.CERT_REHELLO - 10 then n = n + 1; now = now + 40; l[2]() end end
  eq(n, 1, "one coalesced send scheduled")
  eq(#certsSent(), 2, "sent at the end of the window")
  -- a 1.0 / 1.1 hello (no p2) does not trigger it
  now = now + 2 * nsB.Sync.CERT_REHELLO
  nsB.Sync.OnMessage("H", { h = {} }, "Cid-R")
  eq(#certsSent(), 2, "1.0/1.1 hello: nothing")
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
