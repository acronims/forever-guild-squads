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

local function wireNs(me, myPk)
  local sent = {}
  local ns = { Model = M, Permissions = NS.Permissions, Serialize = S, Trust = T, state = M.newState(), roster = roster,
               rosterReady = true, onlineCount = function() return 1 end, me = function() return me end,
               fullName = function(n) return n end, After = function(_, fn) fn() end, serverTime = function() return T0 end,
               trustDB = T.st({}), myPk = function() return myPk end,
               Comm = { Send = function(tag, p, ch, to) sent[#sent + 1] = { tag, p, ch, to } end } }
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

test("keys: records carry their authors' strong keys (ks); 2 relayers make a weak key, the owner a strong one", function()
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
  ok(T.keyOf(nsN.trustDB, "Ali-R") == nil, "one relayer: pending")
  nsN.Sync.OnMessage("D", d, "Cid-R")
  local k, s = T.keyOf(nsN.trustDB, "Ali-R")
  ok(k == pkA and s == "weak", "two relayers: weak")
  -- keys for names without a record in the message, or outside the roster, are ignored
  nsN.Sync.OnMessage("D", { r = d.r, ks = { ["Gm-R"] = T.hex(pkF), ["Zed-R"] = T.hex(pkF) } }, "Bob-R")
  nsN.Sync.OnMessage("D", { r = d.r, ks = { ["Gm-R"] = T.hex(pkF), ["Zed-R"] = T.hex(pkF) } }, "Cid-R")
  ok(T.keyOf(nsN.trustDB, "Gm-R") == nil and T.keyOf(nsN.trustDB, "Zed-R") == nil, "unrelated keys ignored")
  -- weak keys are never relayed onward (each relayer vouches only for keys heard in person)
  local _, sentN = nsN, {}
  nsN.Comm.Send = function(tag, p) sentN[#sentN + 1] = { tag, p } end
  nsN.Sync.SendRecords({ M.stored(nsN.state, prof("Ali-R", T0)) or prof("Ali-R", T0) })
  for _, m in ipairs(sentN) do if m[1] == "D" then ok(not (m[2].ks and m[2].ks["Ali-R"]), "weak key relayed") end end
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

test("keys: /gsq trust reset forgets a pinned key so the owner can be learned again", function()
  local db = T.st({})
  T.hearOwner(db, "Ali-R", pkA, T0)
  eq(T.hearOwner(db, "Ali-R", pkF, T0 + 1), "changed")
  T.reset(db, "Ali-R")
  eq(T.hearOwner(db, "Ali-R", pkF, T0 + 2), "new")
  -- own key holder is separate from the guild's trust db (per character, not per guild)
  local holder = {}
  local pool = T.entropy()
  for i = 1, T.MIN_SAMPLES do pool.add(i, "x") end
  local sk, pk = T.ensureOwn(holder, pool)
  ok(sk and pk and holder.me and holder.keys == nil, "ensureOwn only writes `me`")
end)
