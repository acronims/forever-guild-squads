-- v1.2 annex F (no dev key, BRO 8-nov 01:02): keys per character, TOFU strong from the owner in person, weak with a
-- quorum of 2 relayers, contested weak keys, owner beats weak, pinned key change refused, rotation signed by the old
-- key, reset by hand, entropy seed. Spec: docs/SPEC-v1.2-p2p.md, annex F.
local T, E = NS.Trust, NS.Ed25519
local NOW = 1795000000

local function key(tag) local sk = E.sha512("test-key " .. tag):sub(1, 32) return sk, E.publicKey(sk) end
local skA, pkA = key("A")
local _, pkFake = key("fake")
local _, pkFake2 = key("fake2")

test("trust: owner in person = strong, pinned; a different key later is refused and noted", function()
  ok(T ~= nil, "Core/Trust.lua loaded (NS.Trust)")
  local db = T.st({})
  ok(T.hearOwner(db, "A-R", pkA, NOW) == "new", "first key from the owner")
  local k, s = T.keyOf(db, "A-R")
  ok(k == pkA and s == "strong", "pinned strong")
  ok(T.hearOwner(db, "A-R", pkA, NOW + 1) == "same", "same key again")
  ok(T.hearOwner(db, "A-R", pkFake, NOW + 2) == "changed", "different key from the owner without rotation")
  ok(T.keyOf(db, "A-R") == pkA, "the pinned key stays")
  ok(db.alerts[#db.alerts] == "keychange A-R", "noted for diag")
  ok(T.hearOwner(db, "A-R", "short", NOW) == "bad", "malformed key")
end)

test("trust: relayed keys need 2 distinct relayers (not the owner) and stay weak", function()
  local db = T.st({})
  ok(T.hearRelayed(db, "A-R", pkA, "X-R", NOW) == "pending", "one relayer: pending")
  ok(T.keyOf(db, "A-R") == nil, "no key yet")
  ok(T.hearRelayed(db, "A-R", pkA, "X-R", NOW + 1) == "pending", "the same relayer twice does not count")
  ok(T.hearRelayed(db, "A-R", pkA, "Y-R", NOW + 2) == "weak", "second relayer: weak")
  local k, s = T.keyOf(db, "A-R")
  ok(k == pkA and s == "weak" and not T.isStrong(db, "A-R"), "weak, not strong")
  ok(T.hearOwner(db, "A-R", pkA, NOW + 3) == "same" and T.isStrong(db, "A-R", pkA), "the owner confirms it: strong")
  -- the owner's own relay counts as in person
  local db2 = T.st({})
  ok(T.hearRelayed(db2, "A-R", pkA, "A-R", NOW) == "new" and T.isStrong(db2, "A-R"), "relayer == owner: strong")
end)

test("trust: a weak key from alts never beats the owner; the alts become suspects", function()
  local db = T.st({})
  T.hearRelayed(db, "A-R", pkFake, "Alt1-R", NOW)
  ok(T.hearRelayed(db, "A-R", pkFake, "Alt2-R", NOW) == "weak", "two alts plant a weak key for a stranger")
  local r, old = T.hearOwner(db, "A-R", pkA, NOW + 10)
  ok(r == "replaced" and old == pkFake, "the owner in person replaces it (the caller drops what it signed)")
  ok(T.isStrong(db, "A-R", pkA), "real key strong")
  ok(db.suspects["Alt1-R"] == 1 and db.suspects["Alt2-R"] == 1, "both relayers counted as suspects")
  ok(T.hearRelayed(db, "A-R", pkFake, "Alt3-R", NOW + 11) == "strong", "relaying a fake key against a strong one")
  ok(T.keyOf(db, "A-R") == pkA and db.suspects["Alt3-R"] == 1, "ignored and counted")
end)

test("trust: two weak keys with quorum = contested, neither used until the owner", function()
  local db = T.st({})
  T.hearRelayed(db, "A-R", pkA, "X-R", NOW); T.hearRelayed(db, "A-R", pkA, "Y-R", NOW)
  T.hearRelayed(db, "A-R", pkFake, "Alt1-R", NOW)
  ok(T.hearRelayed(db, "A-R", pkFake, "Alt2-R", NOW) == "contested", "second key with quorum")
  ok(T.keyOf(db, "A-R") == nil, "no key while contested")
  ok(T.hearRelayed(db, "A-R", pkFake2, "Alt3-R", NOW) ~= "weak", "still no weak key")
  ok(T.hearOwner(db, "A-R", pkA, NOW + 5) == "same" and T.isStrong(db, "A-R", pkA), "the owner settles it")
  ok((db.suspects["Alt1-R"] or 0) >= 1 and (db.suspects["Alt2-R"] or 0) >= 1 and not db.suspects["X-R"], "only the liars are suspects")
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
