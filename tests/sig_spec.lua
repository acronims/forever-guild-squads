-- v1.2 annex F: signed manifests per author (Core/Sig.lua). One verify per manifest, records checked by hash, replay
-- by manifest seq, a weak key never replaces what a strong key signed, a replaced weak key loses what it signed,
-- verifications queued at most 1 per step. Spec: docs/SPEC-v1.2-p2p.md, annex F (AF2, AF4, AF5).
local G, E = NS.Sig, NS.Ed25519

local function key(tag) local sk = E.sha512("sig-key " .. tag):sub(1, 32) return sk, E.publicKey(sk) end
local skA, pkA = key("A")
local skM, pkM = key("mallory")
local function rec(id, d, ts) return { k = "profile", id = id, ts = ts or 100, sq = 1, a = "A-R", d = d or { cls = "MAGE" } } end
local function keys(map) return function(name) local e = map[name]; if e then return e[1], e[2] end end end

test("sig: a manifest signed by the author makes its records strong; a changed byte is not signed", function()
  ok(G ~= nil, "Core/Sig.lua loaded (NS.Sig)")
  G.resetQueue()
  local db = G.st({})
  local r1, r2 = rec("A-R"), { k = "rsvp", id = "e1:A-R", ts = 100, sq = 2, a = "A-R", d = { s = "yes" } }
  local m = G.build("A-R", 1, { r1, r2 }, skA, pkA)
  ok(G.status(db, r1) == nil, "nothing verified yet")
  ok(G.offer(db, m, keys({ ["A-R"] = { pkA, "strong" } })) == "queued", "queued")
  ok(G.pending() == 1, "one in the queue")
  ok(G.status(db, r1) == nil, "not applied before the verify step")
  ok(G.step(db) == "A-R", "one step verifies it")
  ok(G.pending() == 0, "queue empty")
  ok(G.status(db, r1) == "strong" and G.status(db, r2) == "strong", "both records strong")
  local forged = rec("A-R", { cls = "WARRIOR" })
  ok(G.status(db, forged) == nil, "a relayer's changed copy has no signature")
end)

test("sig: a manifest signed by another key, or tampered, is rejected", function()
  G.resetQueue()
  local db = G.st({})
  local m = G.build("A-R", 1, { rec("A-R", { cls = "WARRIOR" }) }, skM, pkM)
  G.offer(db, m, keys({ ["A-R"] = { pkA, "strong" } }))
  ok(G.step(db) == nil and db.cnt.rejected == 1, "mallory's signature for A is rejected")
  local good = G.build("A-R", 2, { rec("A-R") }, skA, pkA)
  local bad = { a = good.a, n = good.n, s = good.s, h = { ["profile:A-R"] = G.recHash(rec("A-R", { cls = "ROGUE" })) } }
  G.offer(db, bad, keys({ ["A-R"] = { pkA, "strong" } }))
  ok(G.step(db) == nil and db.cnt.rejected == 2, "a hash swapped under a valid signature is rejected")
  ok(G.offer(db, { a = "A-R", n = 1, h = {}, s = "zz" }, keys({})) == "bad", "malformed")
end)

test("sig: replay of an older manifest does nothing; a newer one replaces it", function()
  G.resetQueue()
  local db = G.st({})
  local k = keys({ ["A-R"] = { pkA, "strong" } })
  local old, new = rec("A-R", { cls = "MAGE" }, 100), rec("A-R", { cls = "PRIEST" }, 200)
  local m1, m2 = G.build("A-R", 1, { old }, skA, pkA), G.build("A-R", 2, { new }, skA, pkA)
  G.offer(db, m2, k); G.step(db)
  ok(G.status(db, new) == "strong", "the new record is signed")
  ok(G.offer(db, m1, k) == "old", "the old manifest is ignored (replay)")
  ok(G.status(db, old) == nil, "the old record does not come back")
end)

test("sig: a weak key never replaces a strong signature; a replaced weak key loses what it signed", function()
  G.resetQueue()
  local db = G.st({})
  local r = rec("A-R")
  G.offer(db, G.build("A-R", 1, { r }, skA, pkA), keys({ ["A-R"] = { pkA, "strong" } })); G.step(db)
  local fake = rec("A-R", { cls = "WARRIOR" })
  G.offer(db, G.build("A-R", 9, { fake }, skM, pkM), keys({ ["A-R"] = { pkM, "weak" } })); G.step(db)
  ok(G.status(db, r) == "strong" and G.status(db, fake) == nil, "the strong one stays")
  local db2 = G.st({})
  G.offer(db2, G.build("A-R", 9, { fake }, skM, pkM), keys({ ["A-R"] = { pkM, "weak" } })); G.step(db2)
  ok(G.status(db2, fake) == "weak", "weak-signed = weak (shown unverified)")
  ok(G.dropKey(db2, "A-R", pkM) == true and G.status(db2, fake) == nil, "the replaced weak key loses it")
  G.offer(db2, G.build("A-R", 1, { r }, skA, pkA), keys({ ["A-R"] = { pkA, "strong" } })); G.step(db2)
  ok(G.status(db2, r) == "strong", "then the owner's manifest applies, even with a lower seq")
end)

test("sig: at most one verify per step, no key = retry later, queue capped", function()
  G.resetQueue()
  local db = G.st({})
  local k = keys({ ["A-R"] = { pkA, "strong" } })
  for n = 1, 3 do G.offer(db, G.build("A-R", n, { rec("A-R", nil, 100 + n) }, skA, pkA), k) end
  local verifies, real = 0, E.verify
  E.verify = function(...) verifies = verifies + 1; return real(...) end
  G.step(db)
  ok(verifies == 1, "one verify per step")
  E.verify = real
  G.resetQueue()
  G.offer(db, G.build("B-R", 1, {}, skA, pkA), keys({}))
  ok(G.step(db) == nil and db.man["B-R"] == nil, "no key: not accepted")
  ok(G.offer(db, G.build("B-R", 1, {}, skA, pkA), keys({ ["B-R"] = { pkA, "strong" } })) == "queued", "it can be offered again")
end)

test("sig: a parked fake manifest with a huge n does not displace the real one (one parked per sender, AF6)", function()
  G.resetQueue()
  local db = G.st({})
  local map = {}
  local k = keys(map)
  local real = rec("A-R", { cls = "MAGE" }, 300)
  local fake = rec("A-R", { cls = "WARRIOR" }, 900)
  G.offer(db, G.build("A-R", 5, { real }, skA, pkA), k, "Honest-R"); G.step(db)
  G.offer(db, G.build("A-R", 2000000000, { fake }, skM, pkM), k, "Mallory-R"); G.step(db)
  ok(db.man["A-R"] == nil, "nothing accepted without a key")
  ok(G.unpark("A-R") == true, "the author's key arrives: his parked manifests go to the queue")
  map["A-R"] = { pkA, "strong" }  -- certified now (annex G)
  for _ = 1, 4 do G.step(db) end
  ok(G.status(db, real) == "strong", "the real manifest is verified after the key arrives")
  ok(G.status(db, fake) == nil, "the fake one is rejected")
  -- the same sender only keeps his newest; a sender cannot fill the author's slots
  G.resetQueue()
  local db2 = G.st({})
  map["A-R"] = nil
  G.offer(db2, G.build("A-R", 5, { real }, skA, pkA), k, "Honest-R"); G.step(db2)
  for i = 1, 20 do G.offer(db2, G.build("A-R", 100 + i, { fake }, skM, pkM), k, "Mallory-R"); G.step(db2) end
  map["A-R"] = { pkA, "strong" }
  G.unpark("A-R")
  for _ = 1, 4 do G.step(db2) end
  ok(G.status(db2, real) == "strong", "20 fakes from one sender still leave the real one parked")
end)
