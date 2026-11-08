-- v1.2 annex F (BRO 8-nov 00:46 + 01:02): the record rules with signed manifests. A relayed record (authorial or
-- authority) is applied only if the last verified manifest of its author lists it; there is no quorum for records
-- any more (only for keys), officers relaying do not skip the signature, a weak key never replaces nor deletes what
-- was heard / signed strong, a repudiate or an authority record needs a strong key. Spec: docs/SPEC-v1.2-p2p.md (AF2).
local M, X, G, E = NS.Model, NS.P2P, NS.Sig, NS.Ed25519
local T0 = 1795000000
local NOW = T0 + 5000
local RANKS = { ["Gm-R"] = 0, ["Of-R"] = 1, ["Au-R"] = 5, ["Y-R"] = 5, ["Z-R"] = 5, ["W-R"] = 5, ["Cap-R"] = 5 }
local roster = makeRoster(RANKS)
local function copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = copy(v) end return o end
local function ap(s, r, sender) return M.apply(s, copy(r), { roster = roster, sender = sender, now = NOW }) end
local function prof(a, ts, d) return { k = "profile", id = a, a = a, ts = ts, sq = 1, d = d or { note = "hola" } } end
local function key(tag) local sk = E.sha512("sigrules " .. tag):sub(1, 32) return sk, E.publicKey(sk) end
local KEYS = {}
for _, n in ipairs({ "Au-R", "Cap-R", "Gm-R", "Y-R" }) do local sk, pk = key(n); KEYS[n] = { sk = sk, pk = pk } end
local function newState()
  G.resetQueue()
  local s = M.newState()
  s.sigdb = G.st({})
  ok(ap(s, { k = "settings", id = "settings", a = "Gm-R", ts = T0, sq = 1,
             d = { squadsEnabled = true, officerRanks = { 1 }, rlList = { "Cap-R" } } }))
  return s
end
-- the author signs a manifest over `recs`; the receiver knows his key as `strength` (and signer = whose sk signs)
local function sign(s, author, n, recs, strength, signer)
  local k = KEYS[signer or author]
  local m = G.build(author, n, recs, k.sk, k.pk)
  G.offer(s.sigdb, m, function(name) if name == author then return k.pk, strength or "strong" end end)
  return G.step(s.sigdb)
end

test("sig rules: a relayed record without its author's signature is never applied (no quorum, not even officers)", function()
  ok(X.SIGNED == true, "P2P runs with signatures (X.SIGNED)")
  local s = newState()
  local p = prof("Au-R", T0 + 10, { note = "falso" })
  for _, by in ipairs({ "Y-R", "Z-R", "W-R", "Of-R", "Gm-R" }) do
    local okA, why = ap(s, p, by)
    eq(okA, false, "relayed by " .. by .. ": not applied"); eq(why, "pending")
  end
  eq(s.profiles["Au-R"], nil, "five relayers (two officers among them) do not make a quorum any more")
  local sq = { k = "squad", id = "A", a = "Cap-R", ts = T0 + 1, sq = 1, d = { name = "Alfa", captain = "Cap-R", members = { "Cap-R", "Y-R" } } }
  for _, by in ipairs({ "Y-R", "Z-R", "W-R", "Of-R" }) do eq(select(2, ap(s, sq, by)), "pending") end
  eq(s.squads["A"], nil, "an authority record relayed by anyone needs the owner's signature")
end)

test("sig rules: one relayer is enough with a strong manifest; a pending copy applies once the manifest verifies", function()
  local s = newState()
  local p = prof("Au-R", T0 + 10, { note = "real" })
  eq(select(2, ap(s, p, "Y-R")), "pending")
  eq(sign(s, "Au-R", 1, { p }), "Au-R", "manifest verified")
  eq(X.retry(s, "Au-R", { roster = roster, now = NOW }), 1, "the pending copy is re-offered and applied")
  eq(s.profiles["Au-R"] and s.profiles["Au-R"].d.note, "real")
  local p2 = prof("Au-R", T0 + 20, { note = "cambiado por Y" })
  eq(select(2, ap(s, p2, "Y-R")), "pending", "a version not in the manifest waits")
  eq(s.profiles["Au-R"].d.note, "real")
  local sq = { k = "squad", id = "A", a = "Cap-R", ts = T0 + 1, sq = 1, d = { name = "Alfa", captain = "Cap-R", members = { "Cap-R" } } }
  sign(s, "Cap-R", 1, { sq })
  local okA, why = ap(s, sq, "Z-R")
  ok(okA, "the captain's signed squad applies from one relayer: " .. tostring(why))
end)

test("sig rules: a weak key never replaces nor deletes what is strong; repudiate and authority need strong", function()
  local s = newState()
  ok(ap(s, prof("Au-R", T0 + 10, { note = "en persona" }), "Au-R"), "heard from the author in person")
  local fake = prof("Au-R", T0 + 50, { note = "de la debil" })
  sign(s, "Au-R", 1, { fake }, "weak", "Y-R")     -- a weak key brought by 2 alts, really Y's key
  local okA, why = ap(s, fake, "Z-R")
  eq(okA, false, "not applied over the strong copy"); eq(why, "weak")
  eq(s.profiles["Au-R"].d.note, "en persona")
  local rep = X.repudiation(s.profiles["Au-R"], "Au-R", T0 + 60, 2)
  sign(s, "Au-R", 2, { fake, rep }, "weak", "Y-R")
  eq(select(2, ap(s, rep, "Z-R")), "weak", "a weak repudiate deletes nothing")
  ok(s.profiles["Au-R"], "the real profile is still there")
  local sq = { k = "squad", id = "B", a = "Cap-R", ts = T0 + 1, sq = 1, d = { name = "Beta", captain = "Cap-R", members = { "Cap-R" } } }
  sign(s, "Cap-R", 1, { sq }, "weak")
  eq(select(2, ap(s, sq, "Z-R")), "weak", "a squad signed by a weak key is not applied")
  eq(s.squads["B"], nil)
  -- a weak signature on a profile nobody holds is shown as unverified (applied, marked weak) and later yields
  local s2 = newState()
  local w = prof("W-R", T0 + 10, { note = "w" })
  local skW, pkW = key("W-R")
  G.offer(s2.sigdb, G.build("W-R", 1, { w }, skW, pkW), function() return pkW, "weak" end); G.step(s2.sigdb)
  ok(ap(s2, w, "Z-R"), "a weak-signed authorial record with nothing strong under it is applied")
  eq(X.strengthOf(s2, s2.profiles["W-R"]), "weak", "marked weak (shown unverified)")
  ok(ap(s2, prof("W-R", T0 + 5, { note = "real, en persona" }), "W-R"), "the owner in person replaces a weak copy even if older")
  eq(s2.profiles["W-R"].d.note, "real, en persona")
  eq(X.strengthOf(s2, s2.profiles["W-R"]), "strong")
end)

test("sig rules H2: a profile with d.squad=A only counts if A's roster, signed by its captain, lists the author", function()
  local s = newState()
  local sq1 = { k = "squad", id = "A", a = "Cap-R", ts = T0 + 1, sq = 1, d = { name = "Alfa", captain = "Cap-R", members = { "Cap-R" } } }
  local p = prof("Au-R", T0 + 10, { squad = "A" })
  eq(sign(s, "Cap-R", 1, { sq1 }), "Cap-R"); eq(sign(s, "Au-R", 1, { p }), "Au-R")
  ok(ap(s, sq1, "Z-R")); ok(ap(s, p, "Z-R"))
  eq(s.profiles["Au-R"].d.squad, "A", "the profile itself is applied (it is the author's own record)")
  ok(not M.isMember(s, "A", "Au-R"), "but it does not make Au-R a member: the captain's roster does not list him")
  ok(not NS.Permissions.contains(M.members(s, "A"), "Au-R"), "nor is he counted among the members")
  eq(M.squadOf(s, "Au-R"), nil)
  -- Y forges a roster of A that lists Au-R: as himself (not the captain) or as the captain with his own key
  local fake = { k = "squad", id = "A", a = "Y-R", ts = T0 + 20, sq = 2, d = { name = "Alfa", captain = "Cap-R", members = { "Cap-R", "Au-R" } } }
  eq(sign(s, "Y-R", 1, { fake }), "Y-R")
  local okY = ap(s, fake, "Y-R")
  ok(not okY, "a roster of A written by someone other than its captain is denied")
  local fake2 = { k = "squad", id = "A", a = "Cap-R", ts = T0 + 21, sq = 2, d = { name = "Alfa", captain = "Cap-R", members = { "Cap-R", "Au-R" } } }
  local m = G.build("Cap-R", 2, { fake2 }, KEYS["Y-R"].sk, KEYS["Y-R"].pk)
  G.offer(s.sigdb, m, function(name) if name == "Cap-R" then return KEYS["Cap-R"].pk, "strong" end end)
  G.step(s.sigdb)
  eq(select(2, ap(s, fake2, "Y-R")), "pending", "a roster claiming the captain but signed with another key never applies")
  ok(not M.isMember(s, "A", "Au-R"), "after both forgeries Au-R is still not a member")
  -- the real captain lists him: now he counts
  local sq2 = { k = "squad", id = "A", a = "Cap-R", ts = T0 + 30, sq = 3, d = { name = "Alfa", captain = "Cap-R", members = { "Cap-R", "Au-R" } } }
  eq(sign(s, "Cap-R", 3, { sq2 }), "Cap-R")
  ok(ap(s, sq2, "Z-R"))
  ok(M.isMember(s, "A", "Au-R"), "listed by the captain's signed roster + own profile: member")
  eq(M.squadOf(s, "Au-R"), "A")
end)

test("sig rules D1: what a replaced key signed is dropped (X.dropSignedBy); what the author said in person stays", function()
  local s = newState()
  local skF, pkF = key("fake Au-R")
  local p = prof("Au-R", T0 + 10, { note = "falso" })
  local m = G.build("Au-R", 1, { p }, skF, pkF)
  G.offer(s.sigdb, m, function(name) if name == "Au-R" then return pkF, "cert" end end); G.step(s.sigdb)
  ok(ap(s, p, "Z-R"), "a cert-signed profile is applied")
  eq(s.profiles["Au-R"].d.note, "falso")
  ok(G.dropKey(s.sigdb, "Au-R", pkF), "the manifest of the replaced key is forgotten")
  eq(X.dropSignedBy(s, "Au-R", pkF), 1, "one record signed by the replaced key")
  eq(s.profiles["Au-R"], nil, "the record it signed is dropped")
  eq(s.p2p.via["profile:Au-R"], nil, "and its relay trail")
  -- a record heard from its author in person is not touched
  local s2 = newState()
  ok(ap(s2, prof("Au-R", T0 + 10, { note = "en persona" }), "Au-R"))
  eq(X.dropSignedBy(s2, "Au-R", pkF), 0)
  eq(s2.profiles["Au-R"].d.note, "en persona", "a record heard in person stays")
end)

test("sig rules D3: a cert key applies profiles and squads, never a repudiate nor an authority record", function()
  local s = newState()
  local k = KEYS["Au-R"]
  local p = prof("Au-R", T0 + 10, { note = "x" })
  ok(ap(s, p, "Au-R"), "the author's profile, in person")
  local rep = { k = "repudiate", id = X.vkey(p), a = "Au-R", ts = T0 + 20, sq = 2, d = { t = X.kid(p), v = X.vkey(p) } }
  G.offer(s.sigdb, G.build("Au-R", 1, { rep }, k.sk, k.pk), function() return k.pk, "cert" end); G.step(s.sigdb)
  local okR = ap(s, rep, "Z-R")
  ok(not okR, "a repudiate signed by a cert key is not applied")
  eq(s.profiles["Au-R"].d.note, "x", "the profile stays")
  local set = { k = "settings", id = "settings", a = "Gm-R", ts = T0 + 30, sq = 2, d = { squadsEnabled = false, officerRanks = { 1 } } }
  local kg = KEYS["Gm-R"]
  G.offer(s.sigdb, G.build("Gm-R", 1, { set }, kg.sk, kg.pk), function() return kg.pk, "cert" end); G.step(s.sigdb)
  ok(not ap(s, set, "Z-R"), "settings signed by a cert key are not applied")
  eq(s.settings.d.squadsEnabled, true)
end)

test("sig rules QA r2 N1: a squad relayed under a cert key is applied (annex G: cert = strong for profiles and squads)", function()
  local s = newState()
  local sq = { k = "squad", id = "A", a = "Cap-R", ts = T0 + 40, sq = 1, d = { name = "Alfa", captain = "Cap-R", members = { "Cap-R" } } }
  local pc = prof("Cap-R", T0 + 41, { note = "cap" })
  sign(s, "Cap-R", 1, { sq, pc }, "cert")
  local okS, why = ap(s, sq, "Z-R")
  ok(okS, "the squad signed by a cert key is applied (" .. tostring(why) .. ")")
  ok(s.squads["A"] ~= nil, "the squad is in the state")
  ok(ap(s, pc, "Z-R"), "and the profile too")
end)

test("sig sec r3 M1: a cert key of the GM cannot disband, edit or evict a squad he does not captain", function()
  local s = newState()
  local sq = { k = "squad", id = "A", a = "Cap-R", ts = T0 + 40, sq = 1, d = { name = "Alfa", captain = "Cap-R", members = { "Cap-R" } } }
  ok(ap(s, sq, "Cap-R"), "the captain's squad, heard in person")
  local dis = copy(sq); dis.a = "Gm-R"; dis.ts = T0 + 50; dis.sq = 2; dis.d.disbanded = true
  local ren = copy(sq); ren.a = "Gm-R"; ren.ts = T0 + 51; ren.sq = 3; ren.d.name = "Pwned"
  sign(s, "Gm-R", 1, { dis }, "cert")
  local okD, whyD = ap(s, dis, "Z-R")
  ok(not okD, "a disband by a cert key of the GM is not applied (" .. tostring(whyD) .. ")")
  sign(s, "Gm-R", 2, { ren }, "cert")
  local okE, whyE = ap(s, ren, "Z-R")
  ok(not okE, "an edit by a cert key of the GM is not applied (" .. tostring(whyE) .. ")")
  eq(s.squads["A"].d.name, "Alfa", "the squad stays as its captain wrote it")
  ok(not s.squads["A"].d.disbanded, "and alive")
  -- eviction by the name race: an older creation with the same name under a cert key would push the real squad out
  local old = { k = "squad", id = "B", a = "Gm-R", ts = T0 + 1, sq = 4, d = { name = "Alfa", captain = "Gm-R", members = { "Gm-R" }, ct = T0 + 1 } }
  sign(s, "Gm-R", 3, { old }, "cert")
  local okV, whyV = ap(s, old, "Z-R")
  ok(not okV, "a cert-key squad that would evict another is not applied (" .. tostring(whyV) .. ")")
  ok(s.squads["A"] ~= nil, "the real squad is not evicted")
  -- his own squad, as its captain, under a cert key still goes through (annex G, QA r2 N1)
  local own = { k = "squad", id = "C", a = "Y-R", ts = T0 + 70, sq = 1, d = { name = "Gamma", captain = "Y-R", members = { "Y-R" } } }
  ok(ap(s, { k = "settings", id = "settings", a = "Gm-R", ts = T0 + 61, sq = 10,
             d = { squadsEnabled = true, officerRanks = { 1 }, rlList = { "Cap-R", "Y-R" } } }, "Gm-R"))
  sign(s, "Y-R", 1, { own }, "cert")
  local okO, whyO = ap(s, own, "Z-R")
  ok(okO, "a captain's own squad under a cert key is applied (" .. tostring(whyO) .. ")")
end)

test("sig sec r2 R1: a repudiate of a forged copy with the real (ts, sq, a) does not hide the author's signed version", function()
  local s = newState()
  local real = prof("Au-R", T0 + 10, { note = "real" })
  local forged = prof("Au-R", T0 + 10, { note = "falso" })
  ok(X.vbase(X.vkey(real)) == X.vbase(X.vkey(forged)), "precondition: same signed base, other content")
  local rep = X.repudiation(forged, "Au-R", T0 + 60, 2)
  eq(sign(s, "Au-R", 2, { real, rep }), "Au-R", "the victim's manifest lists the real record and the repudiate")
  ok(ap(s, rep, "Y-R"), "the strong repudiate is applied")
  eq(select(2, ap(s, forged, "Z-R")), "repudiated", "the forged copy stays out")
  local okA, why = ap(s, real, "Z-R")
  ok(okA, "the real signed version is applied although its base was repudiated: " .. tostring(why))
  eq(s.profiles["Au-R"] and s.profiles["Au-R"].d.note, "real")
end)
