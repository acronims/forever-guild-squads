-- 2.0 (docs/SPEC-v2.0-identidad.md §5, AC5): the SavedVariables of the 1.2.2 move to the WoW Forever identity
-- «Name Surname» (Model.migrateIdentity, which replaces Model.sweepSurnames). The input is tests/fixtures/sv-1.2.2.lua:
-- ONE account played with the tag v1.2.2 in the simulator (tests/tools/make-sv-122.js): the main «Kas Pitas», his alt
-- «Alt Apalt», a second «Kas» on the realm («Kas Mora», another account), Gm / Mb / Nc on 1.2.2, plus the 1.2.0
-- leftovers «Name Surname-Realm». D1 (BRO): signed records of others from the 1.x are dropped.
local M, S, G, E = NS.Model, NS.Serialize, NS.Sig, NS.Ed25519
local NOW = 1795100000
local GK = "Forever-Realm"
-- the guild roster as the 2.0 sees it (forever mode): one identity per member, everyone on «Realm»
local ROSTER = { { "Kas", "Pitas" }, { "Kas", "Mora" }, { "Alt", "Apalt" }, { "Gm", "Apgm" }, { "Mb", "Apmb" }, { "Nc", "Apnc" } }

-- ns.id of the contract (§2.3, «Datos guardados de la 1.x»): Core/Identity.lua when it is loaded, else the same rules
-- written out for these names («Kas Pitas-R» -> «Kas Pitas»; «Kas-R» -> by (first name, realm) when it is unique)
local idOf, idSource
do
  local I = NS.Identity
  if I and type(I.id) == "function" and type(I.newIndex) == "function" and type(I.indexAdd) == "function" then
    local ix = I.newIndex()
    for _, m in ipairs(ROSTER) do I.indexAdd(ix, m[1] .. " " .. m[2], m[1], m[2], "Realm") end
    local ctx = { mode = "forever", myRealm = "Realm", index = ix }
    idOf, idSource = function(n) return I.id(n, nil, ctx) end, "Core/Identity.lua"
  else
    local byFR = {}
    for _, m in ipairs(ROSTER) do
      local k = m[1]:lower() .. "-Realm"
      byFR[k] = byFR[k] or {}
      byFR[k][#byFR[k] + 1] = m[1] .. " " .. m[2]
    end
    idOf, idSource = function(n)
      if type(n) ~= "string" or n == "" then return nil end
      local sp, dash = n:find(" ", 1, true), n:find("-", 1, true)
      if sp and dash and dash > sp then return n:sub(1, dash - 1) end
      if not dash then return sp and n or nil end
      local l = byFR[n:sub(1, dash - 1):lower() .. "-" .. n:sub(dash + 1)]
      return (l and #l == 1) and l[1] or nil
    end, "stub"
  end
end
local function fixture()
  local src = SOURCES["tests/fixtures/sv-1.2.2.lua"]
  ok(type(src) == "string", "tests/fixtures/sv-1.2.2.lua is loaded by tests/run.js")
  return load(src, "@tests/fixtures/sv-1.2.2.lua")()
end
local function ctxFor(me, oldMe, extra)
  local c = { mode = "forever", id = idOf, me = me, oldMe = oldMe, now = NOW, eventId = NS.Progress.eventId,
              obsId = NS.Races.obsId, rsvpId = NS.Roster.rsvpId, grantId = NS.Catalog.grantId }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end
local function main(root) return M.migrateIdentity(root, root.guilds[GK], ctxFor("Kas Pitas", "Kas-Realm")) end
local function alt(root) return M.migrateIdentity(root, root.guilds[GK], ctxFor("Alt Apalt", "Alt-Realm")) end
local function old(n) return type(n) == "string" and n:find("-", 1, true) ~= nil end
local function oldKeys(t) local n = 0; for k in pairs(type(t) == "table" and t or {}) do if old(k) then n = n + 1 end end return n end
local function recOf(list, k, id) for _, r in ipairs(list or {}) do if r.k == k and r.id == id then return r end end end
local function has(list, x) for _, v in ipairs(list or {}) do if v == x then return true end end return false end

test("migration: the fixture is a 1.2.2 account (main + alt, foreign records, 1.2.0 leftovers, two «Kas»)", function()
  local root = fixture()
  local g = root.guilds and root.guilds[GK]
  ok(g, "partition " .. GK)
  ok(root.ownKeys["Kas-Realm"] and root.ownKeys["Alt-Realm"], "own keys of the main and the alt")
  local authors = {}
  for _, r in ipairs(g.records) do authors[r.a] = (authors[r.a] or 0) + 1 end
  ok(authors["Kas-Realm"] and authors["Alt-Realm"] and authors["Mb-Realm"] and authors["Gm-Realm"], "own and foreign records")
  ok(g.trust.keys["Mb Apmb-Realm"] and g.sig.man["Mb Apmb-Realm"] and g.cert.crt["Mb Apmb-Realm"], "1.2.0 leftovers")
  ok(g.sig.own["Kas-Realm"] and g.sig.own["Alt-Realm"], "the two own manifests of the 1.2.2")
  eq(idOf("Kas-Realm"), nil, "two «Kas» on the realm: «Kas-Realm» is ambiguous (" .. idSource .. ")")
  eq(idOf("Nc-Realm"), "Nc Apnc", "an unambiguous old name")
  eq(idOf("Mb Apmb-Realm"), "Mb Apmb", "a 1.2.0 leftover")
end)

test("migration AC5 (a) (e): no old name left in trust, manifests or certificates; others' 1.x records dropped (D1)", function()
  local root = fixture()
  local g = root.guilds[GK]
  local foreign = 0
  for _, r in ipairs(g.records) do if r.a ~= "Kas-Realm" and r.a ~= "Alt-Realm" then foreign = foreign + 1 end end
  ok(foreign >= 5, "the fixture has foreign records (" .. foreign .. ")")
  local res = main(root)
  ok(res.guild and res.char, "both steps ran")
  for name, t in pairs({ keys = g.trust.keys, pend = g.trust.pend, contested = g.trust.contested, suspects = g.trust.suspects,
                         man = g.sig.man, own = g.sig.own, crt = g.cert.crt, cown = g.cert.own, prev = root.prevOwnKeys }) do
    eq(oldKeys(t), 0, name .. ": keys with «-»")
  end
  for _, a in ipairs(g.trust.alerts or {}) do ok(not old(a:match(" (.*)$")), "alert " .. a) end
  for _, r in ipairs(g.records) do
    ok(not old(r.a), "no record by an old name: " .. tostring(r.a))
    eq(r.a, "Kas Pitas", "only my records stay in g.records (" .. tostring(r.k) .. ":" .. tostring(r.id) .. ")")
  end
  ok(res.dropped >= foreign, "the foreign records were dropped: " .. res.dropped)
  for _, byV in pairs(type(g.p2p) == "table" and g.p2p.pend or {}) do for _, e in pairs(byV) do ok(not old(e.r.a), "p2p pend") end end
end)

test("migration AC5 (b): my records become «Kas Pitas», re-keyed and remapped inside, and a new key signs them", function()
  local root = fixture()
  local g = root.guilds[GK]
  local before = {}
  for _, r in ipairs(g.records) do if r.a == "Kas-Realm" then before[r.k .. ":" .. r.id] = r.sq end end
  main(root)
  local prof, pres = recOf(g.records, "profile", "Kas Pitas"), recOf(g.records, "presence", "Kas Pitas")
  ok(prof and prof.a == "Kas Pitas" and not prof.resign, "profile re-keyed by my identity")
  ok(pres and pres.a == "Kas Pitas", "presence re-keyed by my identity")
  ok(recOf(g.records, "profile", "Kas-Realm") == nil, "no profile left under the old name")
  eq(prof.ts, NOW, "ts = now"); eq(prof.sq, before["profile:Kas-Realm"] + 1, "sq + 1")
  local sq
  for _, r in ipairs(g.records) do if r.k == "squad" then sq = r end end
  ok(sq, "my squad")
  eq(sq.id, "Kas-Realm:1795001009", "the squad id stays (opaque)")
  eq(sq.d.captain, "Kas Pitas", "captain")
  ok(has(sq.d.members, "Kas Pitas") and has(sq.d.members, "Gm Apgm") and #sq.d.members == 2, "members remapped: " .. table.concat(sq.d.members, ","))
  local rj = recOf(g.records, "reject", "Kas-Realm:1795001009|Nc Apnc|req")
  ok(rj and rj.d.name == "Nc Apnc", "the reject names «Nc Apnc» and its id is rebuilt")
  ok(root.ownKeys["Kas-Realm"] == nil, "the 1.x key of the main is gone")
  ok(root.ownKeys["Alt-Realm"] ~= nil, "the alt keeps his until he logs in")
  eq(root.idv["Kas Pitas"], 2, "idv mark"); eq(g.idv, 2, "partition mark"); eq(g.idMigratedAt, NOW)
  eq(root.idOld["Kas-Realm"], "Kas Pitas", "idOld")
  eq(g.sig.fresh, "Kas Pitas", "Sync.OwnManifest signs n = 1 next")
  -- a new client verifies a manifest n = 1 signed with the new key over these records (2.0 tags)
  local sk = E.sha512("migration new key"):sub(1, 32)
  local pk = E.publicKey(sk)
  local m = G.build("Kas Pitas", 1, g.records, sk, pk)
  G.resetQueue()
  local db = G.st({})
  G.offer(db, m, function(n) if n == "Kas Pitas" then return pk, "strong" end end)
  eq(G.step(db), "Kas Pitas", "verified by a new client")
  for _, r in ipairs(g.records) do eq(G.status(db, r), "strong", "signed: " .. r.k .. ":" .. r.id) end
end)

test("migration AC5 (c): the alt's records wait in resign until the alt logs in, then they are his again", function()
  local root = fixture()
  local g = root.guilds[GK]
  main(root)
  local waiting = 0
  for _, r in ipairs(g.resign or {}) do
    eq(r.a, "Alt Apalt", "only the alt waits"); eq(r.resign, true, "marked resign"); waiting = waiting + 1
  end
  ok(waiting >= 2, "profile and presence of the alt wait (" .. waiting .. ")")
  for _, r in ipairs(g.records) do ok(r.a ~= "Alt Apalt", "nothing of the alt is loaded (never sent nor relayed)") end
  local res = alt(root)
  ok(not res.guild and res.char, "the partition was done; the alt's step ran")
  eq(g.resign, nil, "nothing waits any more")
  local prof = recOf(g.records, "profile", "Alt Apalt")
  ok(prof and prof.a == "Alt Apalt" and prof.resign == nil and prof.ts == NOW, "the alt's profile, re-signed")
  eq(prof.d.squad, "Mb-Realm:1795000050", "his request still points at Mb's squad (an opaque id)")
  ok(root.ownKeys["Alt-Realm"] == nil, "the alt's 1.x key is gone")
  eq(root.idv["Alt Apalt"], 2)
  ok(recOf(g.records, "profile", "Kas Pitas"), "the main's records are still there")
end)

test("migration AC5 (d): with two «Kas» on the realm «Kas-Realm» goes from shared data, an unambiguous name is remapped", function()
  local root = fixture()
  local g = root.guilds[GK]
  ok(g.races.obs["Mb-Realm|lv|1795001170|Kas-Realm#30"], "the fixture has an observation of the ambiguous Kas")
  main(root)
  for id, o in pairs(g.races.obs) do
    ok(not old(id) and not old(o.who) and not old(o.by), "observation " .. id)
    for _, n in ipairs(o.pres or {}) do ok(not old(n), "pres " .. n) end
  end
  ok(g.races.obs["Mb Apmb|lv|1795001170|Kas-Realm#30"] == nil, "the ambiguous Kas observation is gone")
  local kill = g.races.obs["Nc Apnc|kill|1795001120|e1443"]
  ok(kill and kill.by == "Nc Apnc" and kill.who == "Nc Apnc", "the kill re-keyed by its remapped reporter")
  ok(#kill.pres == 2 and has(kill.pres, "Nc Apnc") and has(kill.pres, "Mb Apmb"), "pres remapped: " .. table.concat(kill.pres, ","))
  local ev = g.progress.events["Nc Apnc|boss|1795001120|1443"]
  ok(ev and ev.who == "Nc Apnc", "the progress event re-keyed")
  ok(#ev.pres == 2 and not has(ev.pres, "Kas-Realm") and has(ev.pres, "Mb Apmb"), "the ambiguous Kas left the list: " .. table.concat(ev.pres, ","))
  for id in pairs(g.progress.events) do ok(not old(id), "event " .. id) end
  -- the per-character state of this account is mine by construction
  ok(g.races.hkBase["Kas Pitas"] ~= nil and g.races.hkBase["Kas-Realm"] == nil, "hkBase of the main re-keyed")
  ok(g.races.hkBase["Alt Apalt"] ~= nil, "hkBase of the alt re-keyed")
  eq(g.progress.hkState.who, "Kas Pitas:lifetime", "the counter state")
  for id in pairs(g.races.pend or {}) do ok(not old(id:match("^([^|]*)")), "pend " .. id) end
end)

test("migration AC5 (f): twice in a row gives the same bytes, also without the marks and after the alt", function()
  local a, b = fixture(), fixture()
  main(a)
  main(b); main(b)
  eq(S.encode(b), S.encode(a), "two runs = one run")
  b.guilds[GK].idv, b.guilds[GK].idMigratedAt, b.idv = nil, nil, nil
  main(b)
  eq(S.encode(b), S.encode(a), "without the marks: the same bytes")
  alt(a); alt(b); alt(b); main(b)
  eq(S.encode(b), S.encode(a), "main, alt, alt again, main again")
end)

test("migration AC5 (g): never raises; realm mode, no identity and broken shapes do nothing wrong", function()
  local root = fixture()
  local bytes = S.encode(root)
  local r = M.migrateIdentity(root, root.guilds[GK], ctxFor("Kas Pitas", "Kas-Realm", { mode = "realm" }))
  eq(S.encode(root), bytes, "realm mode: nothing changes"); eq(r.swept + r.dropped, 0)
  M.migrateIdentity(root, root.guilds[GK], ctxFor(nil, "Kas-Realm"))
  eq(S.encode(root), bytes, "no identity yet: nothing written")
  local junk = { ownKeys = 5, guilds = { x = { records = { 1, "x", { a = 5 }, { a = "Q-R" } }, trust = { keys = "k", alerts = { 7 } },
                 progress = { events = { e = "y", f = { who = 3 } }, hkState = { who = 9 } }, races = { obs = 1, pend = { 1 } },
                 sig = "s", cert = { crt = 2 }, p2p = { pend = { k = 1, j = { v = 2 } } }, resign = { 3 } } } }
  local okJ, errJ = pcall(M.migrateIdentity, junk, junk.guilds.x, ctxFor("Kas Pitas", "Kas-Realm"))
  ok(okJ, "broken shapes: " .. tostring(errJ))
  local okN = pcall(M.migrateIdentity, nil, nil, nil)
  ok(okN, "nil arguments")
  local throwing = ctxFor("Kas Pitas", "Kas-Realm", { id = function() error("boom") end })
  local okT = pcall(M.migrateIdentity, fixture(), fixture().guilds[GK], throwing)
  ok(okT, "an id function that raises")
end)

test("migration: dry mode counts what it would do and writes nothing (/gsq diag)", function()
  local root = fixture()
  local bytes = S.encode(root)
  local dry = M.migrateIdentity(root, root.guilds[GK], ctxFor("Kas Pitas", "Kas-Realm", { dry = true }))
  eq(S.encode(root), bytes, "nothing written")
  local real = main(root)
  for _, k in ipairs({ "swept", "dropped", "resign", "remapped", "removed", "resigned" }) do eq(dry[k], real[k], "dry " .. k) end
  ok(real.swept > 0 and real.dropped > 0 and real.resigned > 0, "the run did something")
end)

-- the first manifest after the migration is n = 1 (§5 step 2, AC5 b); later ones keep n = max(n + 1, server time)
SMOKE_CHECKS = SMOKE_CHECKS or {}
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "2.0: the first own manifest of a migrated identity is n = 1, the next ones grow", function(c)
  local ns = c.ns
  local Sy, db, me = ns.Sync, ns.sigDB, ns.me()
  ok(Sy and db and me and ns.myPk(), "a client with its key and a sig db")
  local keepOwn, keepFresh = db.own and db.own[me], db.fresh
  db.own = type(db.own) == "table" and db.own or {}
  db.own[me], db.fresh = nil, me
  Sy.ResignOwn()
  local m = Sy.OwnManifest()
  ok(m, "signed")
  eq(m.n, 1, "n = 1 right after the migration")
  ok(db.fresh == nil, "the mark is used once")
  Sy.ResignOwn()
  local m2 = Sy.OwnManifest()
  ok(m2 and m2.n > 1, "the next one grows (" .. tostring(m2 and m2.n) .. ")")
  db.own[me] = keepOwn or m2
  db.fresh = keepFresh
end }
