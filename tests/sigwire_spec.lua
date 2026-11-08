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
               fullName = function(n) return n end, After = function(_, fn) fn() end, serverTime = function() return T0 end,
               trustDB = T.st({}), sigDB = sigdb, myPk = function() return pk end, mySk = function() return sk end,
               Comm = { Send = function(tag, p, ch, to) sent[#sent + 1] = { tag, p, ch, to } end } }
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

SMOKE_CHECKS = SMOKE_CHECKS or {}
-- full client (zload fake WoW): /gsq diag carries the signatures line of point 8 (annex F)
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "v1.2: /gsq diag sig line (verified/pending/rejected, keys strong/weak, replaced)", function(c)
  local rep = c.ns.DiagGlue.Report()
  ok(type(rep) == "string" and rep:find("sig verified=%d+ pending=%d+ rejected=%d+ keys%(strong/weak%)=%d+/%d+ replaced=%d+") and rep:find("cert held=%d+ cert=%d+ disputed=%d+ pending=%d+ rejected=%d+"),
    "diag sig line")
end }
