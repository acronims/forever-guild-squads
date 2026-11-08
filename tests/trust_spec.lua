-- v1.2 annex F (no dev key, BRO 8-nov 01:02): keys per character, TOFU strong from the owner in person, relayed keys
-- are only candidates (annex G certificates: tests/cert_spec.lua), owner in person wins, rotation signed by the old
-- key, reset by hand, entropy seed. Spec: docs/SPEC-v1.2-p2p.md, annex F.
local T, E = NS.Trust, NS.Ed25519
local NOW = 1795000000

local function key(tag) local sk = E.sha512("test-key " .. tag):sub(1, 32) return sk, E.publicKey(sk) end
local skA, pkA = key("A")
local _, pkFake = key("fake")
local _, pkFake2 = key("fake2")

test("trust: owner in person = strong, pinned; a different key from the owner in person always wins (BRO 8-nov 03:09)", function()
  ok(T ~= nil, "Core/Trust.lua loaded (NS.Trust)")
  local db = T.st({})
  ok(T.hearOwner(db, "A-R", pkA, NOW) == "new", "first key from the owner")
  local k, s = T.keyOf(db, "A-R")
  ok(k == pkA and s == "strong", "pinned strong")
  ok(T.hearOwner(db, "A-R", pkA, NOW + 1) == "same", "same key again")
  local r, old = T.hearOwner(db, "A-R", pkFake, NOW + 2)
  ok(r == "replaced" and old == pkA, "a new key heard from the owner in person replaces the strong one (old pk back)")
  local k2, s2 = T.keyOf(db, "A-R")
  ok(k2 == pkFake and s2 == "strong", "the new key is pinned strong")
  ok(db.alerts[#db.alerts] == "keychange A-R", "noted for diag")
  ok(db.n.replaced == 1, "counted as replaced")
  ok(T.hearRelayed(db, "A-R", pkA, "X-R", NOW + 3) == "strong" and T.hearRelayed(db, "A-R", pkA, "Y-R", NOW + 4) == "strong"
    and T.keyOf(db, "A-R") == pkFake, "a relayed key (even with quorum) never replaces a strong one")
  ok(T.hearOwner(db, "A-R", "short", NOW) == "bad", "malformed key")
end)

test("trust: rotation only signed by the old key; reset by hand", function()
  local db = T.st({})
  T.hearOwner(db, "A-R", pkA, NOW)
  local skB, pkB = key("B")
  ok(not T.rotate(db, "A-R", pkB, T.signRotation(skB, pkB, "A-R", pkB), NOW), "signed by the new key: refused")
  ok(T.keyOf(db, "A-R") == pkA and db.alerts[#db.alerts] == "badrotation A-R", "kept and noted")
  ok(not T.rotate(db, "A-R", pkB, T.signRotation(skA, pkA, "Other-R", pkB), NOW), "statement for another name refused")
  ok(T.rotate(db, "A-R", pkB, T.signRotation(skA, pkA, "A-R", pkB), NOW), "signed by the old key: accepted")
  local k, s = T.keyOf(db, "A-R")
  ok(k == pkB and s == "strong", "new key, same strength")
  T.reset(db, "A-R")
  ok(T.keyOf(db, "A-R") == nil, "reset forgets it")
  ok(T.hearOwner(db, "A-R", pkA, NOW) == "new", "and the next key heard in person is pinned")
end)

test("trust: caps on pending relayed keys (one relayer cannot fill the table)", function()
  local db = T.st({})
  for i = 1, T.MAX_PEND_RELAYER do T.hearRelayed(db, "N" .. i .. "-R", pkFake, "Flood-R", NOW) end
  ok(T.hearRelayed(db, "Extra-R", pkFake, "Flood-R", NOW) == "full", "relayer cap")
  ok(T.hearRelayed(db, "Extra-R", pkA, "Honest-R", NOW) == "pending", "others still fit")
  T.expire(db, NOW + T.PEND_TTL + 1)
  local _, _, pend = T.counts(db)
  ok(pend == 0, "pending keys expire")
end)

test("trust: own key from the entropy pool; seeds do not repeat across 1000 simulated starts", function()
  local db = T.st({})
  local pool = T.entropy()
  ok(T.ensureOwn(db, pool) == nil, "no key with an empty pool")
  for i = 1, T.MIN_SAMPLES do pool.add(1234.5 + i * 16.7, i) end
  local sk, pk = T.ensureOwn(db, pool)
  ok(sk and #sk == 32 and pk == E.publicKey(sk), "key created")
  ok(select(2, T.ensureOwn(db, T.entropy())) == pk, "kept in SavedVariables, never regenerated")
  local seen, dup = {}, 0
  for start = 1, 1000 do
    local p = T.entropy()
    -- same GUID, same server time second, clocks that differ only slightly between starts
    for i = 1, 8 do p.add(start * 0.001 + i * 16.6, 1795000000, "Player-1-0000ABCD", (start * 7 + i) % 100) end
    local s = p.seed()
    if seen[s] then dup = dup + 1 end
    seen[s] = true
  end
  ok(dup == 0, "1000 distinct seeds")
end)
