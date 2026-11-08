-- v1.2 annex G (BRO 8-nov 03:15 GO, 04:13 «ok 1»): cross certification of keys. Each client signs ONE list of
-- hash12(name|key) of the keys it heard in person; a stranger Z is "cert" when >= 2 certificates from issuers that are
-- strong for me (heard in person by me) list hash12(Z|K) and no strong issuer lists another key for Z ("disputed"
-- otherwise). Z in person always wins. Relayer quorum is gone. Spec: docs/SPEC-v1.2-p2p.md, annex G (AF7, S16b).
local C, T, E = NS.Cert, NS.Trust, NS.Ed25519
local NOW = 1795000000

local function key(tag) local sk = E.sha512("cert-key " .. tag):sub(1, 32) return sk, E.publicKey(sk) end
local skH1, pkH1 = key("H1")
local skH2, pkH2 = key("H2")
local skH3, pkH3 = key("H3")
local skA1, pkA1 = key("A1")
local skA2, pkA2 = key("A2")
local _, pkZ = key("Z")
local _, pkFake = key("fake")

-- me: heard H1, H2, H3, A1, A2 in person; Z never
local function world()
  C.resetQueue()
  local tdb = T.st({})
  for name, pk in pairs({ ["H1-R"] = pkH1, ["H2-R"] = pkH2, ["H3-R"] = pkH3, ["A1-R"] = pkA1, ["A2-R"] = pkA2 }) do
    T.hearOwner(tdb, name, pk, NOW)
  end
  return tdb, C.st({})
end
local function give(cdb, tdb, c) local r = C.offer(cdb, c); while C.pending() > 0 do C.step(cdb, tdb, NOW) end; return r end

test("cert: shape and size, base64 hash12 entries, signed statement", function()
  ok(C ~= nil, "Core/Cert.lua loaded (NS.Cert)")
  local h = C.hash("Z-R", pkZ)
  ok(type(h) == "string" and #h == 16 and not h:find("[^A-Za-z0-9+/]"), "hash12 in base64 = 16 chars")
  ok(C.hash("Z-R", pkZ) ~= C.hash("Z-R", pkFake) and C.hash("Z-R", pkZ) ~= C.hash("Y-R", pkZ), "name and key both count")
  local c = C.build("H1-R", 5, { ["Z-R"] = pkZ, ["Y-R"] = pkFake }, skH1, pkH1)
  ok(C.validShape(c) and c.i == "H1-R" and c.n == 5 and #c.e == 2, "two entries")
  ok(c.e[1] < c.e[2], "entries sorted (canonical)")
  ok(not C.validShape({ i = "H1-R", n = 1, e = { "short" }, s = c.s }), "a bad entry is refused")
end)

test("cert: verified only from an issuer strong for me; tampered and replayed certificates do nothing", function()
  local tdb, cdb = world()
  local good = C.build("H1-R", 2, { ["Z-R"] = pkZ }, skH1, pkH1)
  give(cdb, tdb, good)
  ok(C.holds(cdb, "H1-R"), "H1's certificate verified")
  local bad = C.build("H2-R", 2, { ["Z-R"] = pkZ }, skA1, pkA1)
  give(cdb, tdb, bad)
  ok(not C.holds(cdb, "H2-R") and cdb.cnt.rejected == 1, "signed by another key: rejected")
  local _, pkW = key("W")
  local skW = key("W")
  give(cdb, tdb, C.build("W-R", 1, { ["Z-R"] = pkZ }, skW, pkW))
  ok(not C.holds(cdb, "W-R"), "an issuer I never heard in person is not used")
  local t = C.build("H3-R", 3, { ["Z-R"] = pkZ }, skH3, pkH3)
  t.e = { C.hash("Z-R", pkFake) }
  give(cdb, tdb, t)
  ok(not C.holds(cdb, "H3-R"), "an entry swapped under a valid signature: rejected")
  ok(C.offer(cdb, C.build("H1-R", 1, {}, skH1, pkH1)) == "old", "an older n is a replay")
end)

test("cert: two strong issuers certify Z; one is not enough; Z itself and a certified issuer do not count", function()
  local tdb, cdb = world()
  ok(T.hearRelayed(tdb, "Z-R", pkZ, "H1-R", NOW) == "pending" and T.hearRelayed(tdb, "Z-R", pkZ, "H2-R", NOW) == "pending",
    "two relayers alone do not make a key any more (no quorum of relayers)")
  ok(T.keyOf(tdb, "Z-R") == nil, "Z unknown")
  give(cdb, tdb, C.build("H1-R", 1, { ["Z-R"] = pkZ }, skH1, pkH1))
  ok(C.eval(cdb, tdb, "Z-R", NOW) == nil and T.keyOf(tdb, "Z-R") == nil, "one certificate: not yet")
  give(cdb, tdb, C.build("H2-R", 1, { ["Z-R"] = pkZ }, skH2, pkH2))
  ok(C.eval(cdb, tdb, "Z-R", NOW) == "cert", "two certificates: certified")
  local k, s = T.keyOf(tdb, "Z-R")
  ok(k == pkZ and s == "cert", "Z's key is 'cert' (counts as strong to apply data)")
  ok(not T.inPerson(tdb, "Z-R"), "but not in person: Z cannot issue for me")
  local skZ = key("Z")
  local _, pkY = key("Y")
  T.hearRelayed(tdb, "Y-R", pkY, "H1-R", NOW)
  give(cdb, tdb, C.build("Z-R", 1, { ["Y-R"] = pkY }, skZ, pkZ))
  give(cdb, tdb, C.build("H3-R", 1, { ["Y-R"] = pkY }, skH3, pkH3))
  ok(C.eval(cdb, tdb, "Y-R", NOW) == nil, "a certified (not in person) issuer does not count: 1 of 2 (no second hop)")
end)

test("cert S16b: 2 known alts certify a fake key; 1 honest against = disputed; Z in person wins", function()
  local tdb, cdb = world()
  T.hearRelayed(tdb, "Z-R", pkFake, "A1-R", NOW)
  T.hearRelayed(tdb, "Z-R", pkZ, "H1-R", NOW)
  give(cdb, tdb, C.build("A1-R", 1, { ["Z-R"] = pkFake }, skA1, pkA1))
  give(cdb, tdb, C.build("A2-R", 1, { ["Z-R"] = pkFake }, skA2, pkA2))
  give(cdb, tdb, C.build("H1-R", 1, { ["Z-R"] = pkZ }, skH1, pkH1))
  ok(C.eval(cdb, tdb, "Z-R", NOW) == "disputed", "disputed")
  ok(T.keyOf(tdb, "Z-R") == nil, "no key used for Z while disputed")
  ok(C.counts(cdb, tdb).disputed == 1, "counted for diag")
  -- the fake was certified first, then the honest certificate arrives: the fake is dropped
  local tdb2, cdb2 = world()
  T.hearRelayed(tdb2, "Z-R", pkFake, "A1-R", NOW)
  give(cdb2, tdb2, C.build("A1-R", 1, { ["Z-R"] = pkFake }, skA1, pkA1))
  give(cdb2, tdb2, C.build("A2-R", 1, { ["Z-R"] = pkFake }, skA2, pkA2))
  ok(C.eval(cdb2, tdb2, "Z-R", NOW) == "cert", "2 alts alone: certified (the documented limit)")
  local dropped
  T.hearRelayed(tdb2, "Z-R", pkZ, "H1-R", NOW)
  give(cdb2, tdb2, C.build("H1-R", 1, { ["Z-R"] = pkZ }, skH1, pkH1))
  ok(C.eval(cdb2, tdb2, "Z-R", NOW, function(name, old) dropped = old end) == "disputed", "honest certificate against: disputed")
  ok(dropped == pkFake and T.keyOf(tdb2, "Z-R") == nil, "the fake key is dropped (what it signed is forgotten)")
  -- Z in person
  local r, old = T.hearOwner(tdb, "Z-R", pkZ, NOW + 5)
  local k, s = T.keyOf(tdb, "Z-R")
  ok(k == pkZ and s == "strong", "Z in person: his key, strong")
  ok(C.eval(cdb, tdb, "Z-R", NOW + 5) == "strong", "in person beats any certificate")
  ok(r ~= "bad" and old == nil, "nothing to drop: no key was in use")
end)

test("cert: our own certificate lists the keys heard in person in the last 30 days, re-signed only when it changes", function()
  local tdb = world()
  tdb.keys["H3-R"].seen = NOW - 31 * 86400
  tdb.keys["H3-R"].t = NOW - 31 * 86400
  T.hearRelayed(tdb, "Z-R", pkZ, "H1-R", NOW)
  local own = {}
  local skMe, pkMe = key("me")
  local c1 = C.own(own, tdb, "Me-R", skMe, pkMe, NOW)
  ok(c1 and #c1.e == 4, "H1, H2, A1, A2 (H3 too old, Z not in person)")
  local c2 = C.own(own, tdb, "Me-R", skMe, pkMe, NOW + 10)
  ok(c2.n == c1.n and c2.s == c1.s, "unchanged: same n, not re-signed")
  T.hearOwner(tdb, "H3-R", pkH3, NOW + 20)
  local c3 = C.own(own, tdb, "Me-R", skMe, pkMe, NOW + 20)
  ok(c3.n > c1.n and #c3.e == 5, "H3 heard again: re-signed with a higher n")
end)

-- fix/perf (runtime review A1 / M1): C.hash is pure and memoized (name|pk -> hash12). Before, C.evalAll did one
-- sha512 per candidate name after EVERY accepted certificate (100 names = 0.2-0.35 s in one frame), and C.own
-- hashed every key heard in person twice on each recompute (inside the hello handler too). Counted with a wrapper
-- on E.sha512 (E.sign / E.verify hash through their own local, so only the external calls are counted).
local function countSha(fn)
  local real, calls = E.sha512, 0
  E.sha512 = function(s) calls = calls + 1; return real(s) end
  local okR, err = pcall(fn)
  E.sha512 = real
  if not okR then error(err, 2) end
  return calls
end

test("cert perf A1: evalAll after an accepted certificate does no sha512 for names already evaluated", function()
  local tdb, cdb = world()
  local heard = {}
  for i = 1, 100 do
    local nm, pk = ("PerfA%d-R"):format(i), E.sha512("perf A1 pk " .. i):sub(1, 32)
    heard[nm] = pk
    T.hearRelayed(tdb, nm, pk, "H1-R", NOW)
  end
  -- the relayed keys arrive first: Sync.CertEval(name) runs C.eval once per (name, key), in the D handler
  local first = countSha(function() for nm in pairs(heard) do C.eval(cdb, tdb, nm, NOW) end end)
  ok(first <= 100, "one sha512 per new (name, key) at most: " .. first)
  give(cdb, tdb, C.build("H1-R", NOW, heard, skH1, pkH1))
  local n1 = countSha(function() C.evalAll(cdb, tdb, NOW) end)
  eq(n1, 0, "evalAll after the first certificate: no sha512 (all memoized)")
  give(cdb, tdb, C.build("H2-R", NOW, heard, skH2, pkH2))
  local certified = {}
  local n2 = countSha(function() C.evalAll(cdb, tdb, NOW, nil, function(nm) certified[#certified + 1] = nm end) end)
  eq(n2, 0, "evalAll after the second certificate: no sha512")
  eq(#certified, 100, "and the 100 names are certified by H1 + H2")
  local _, s = T.keyOf(tdb, "PerfA7-R")
  eq(s, "cert")
end)

test("cert perf A1: the memo is exact and bounded (flushed whole past HASH_MEMO entries)", function()
  ok(type(C.HASH_MEMO) == "number" and C.HASH_MEMO >= 1000, "C.HASH_MEMO cap")
  local a = C.hash("PerfMemo-R", pkZ)
  local cap = C.HASH_MEMO
  C.HASH_MEMO = 3
  for i = 1, 10 do C.hash("PerfMemo" .. i .. "-R", pkZ) end
  local b = C.hash("PerfMemo-R", pkZ)
  C.HASH_MEMO = cap
  eq(a, b, "same hash after a flush")
  ok(C.hash("PerfMemo-R", pkFake) ~= a, "the key is part of the memo key")
end)

test("cert perf M1: C.own re-hashes only the keys that are new, not every key heard in person", function()
  local tdb = world()
  for i = 1, 100 do T.hearOwner(tdb, ("PerfM%d-R"):format(i), E.sha512("perf M1 pk " .. i):sub(1, 32), NOW) end
  local skMe, pkMe = key("Me-perf")
  local own = {}
  C.own(own, tdb, "Me-R", skMe, pkMe, NOW)
  T.hearOwner(tdb, "PerfM101-R", E.sha512("perf M1 pk 101"):sub(1, 32), NOW + 5)
  local c
  local n = countSha(function() c = C.own(own, tdb, "Me-R", skMe, pkMe, NOW + 5) end)
  ok(n <= 1, "one new key heard in person = at most one sha512 (was 2 x 106): " .. n)
  eq(#c.e, 106, "5 issuers + 101 keys listed")
end)
