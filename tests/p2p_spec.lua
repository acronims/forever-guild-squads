-- v1.1: P2P relay of authorial records with a quorum of 2, captains as nodes of their squad, the author always
-- wins and may repudiate, the real installed counter (presence). Spec: docs/SPEC-v1.1-sync-p2p.md.
local M, R = NS.Model, NS.Roster
local X = NS.P2P
local T0 = 1795000000
local NOW = T0 + 5000
local DAY = 86400

local RANKS = { ["Gm-R"] = 0, ["Of-R"] = 1, ["Au-R"] = 5, ["Y-R"] = 5, ["Z-R"] = 5, ["W-R"] = 5, ["V-R"] = 5,
                ["Cap-R"] = 5, ["CapB-R"] = 5 }
local roster = makeRoster(RANKS)
local function copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = copy(v) end return o end
-- apply as received from `sender` (nil = local) on the client of `me`
local function ap(s, r, sender, me) return M.apply(s, copy(r), { roster = roster, sender = sender, me = me, now = NOW }) end
local function prof(a, ts, d, sq) return { k = "profile", id = a, a = a, ts = ts, sq = sq or 1, d = d or { note = "hola" } } end
local function newState()
  local s = M.newState()
  ok(ap(s, { k = "settings", id = "settings", a = "Gm-R", ts = T0, sq = 1,
             d = { squadsEnabled = true, officerRanks = { 1 }, rlList = { "Cap-R", "CapB-R" } } }))
  return s
end

test("p2p: the closed list of authorial kinds (annex A of the spec)", function()
  ok(X ~= nil, "Core/P2P.lua loaded (NS.P2P)")
  for _, k in ipairs({ "profile", "rsvp", "witness", "presence", "reject", "repudiate" }) do ok(M.P2P_KINDS[k], k) end
  for _, k in ipairs({ "settings", "squad", "annul", "boss", "roster", "attendance", "vconfirm", "achdef", "achgrant" }) do
    ok(not M.P2P_KINDS[k], k .. " is an authority kind")
  end
  ok(M.isP2P(prof("Au-R", T0)), "plain profile")
  ok(not M.isP2P(prof("Au-R", T0, { xferTo = "A>Y-R" })), "a profile carrying xferTo signs a transfer: authority")
  ok(M.isP2P({ k = "reject", id = "A|Au-R|inv", a = "Au-R", ts = T0, sq = 1, d = { sid = "A", name = "Au-R", kind = "inv" } }), "reject inv")
  ok(not M.isP2P({ k = "reject", id = "A|Au-R|req", a = "Cap-R", ts = T0, sq = 1, d = { sid = "A", name = "Au-R", kind = "req" } }), "reject req")
end)

-- AC2: a forged authorial record (author X, invented by Y) stays "unverified" and does not count
test("AC2: a forged profile relayed by one member stays unverified and never counts", function()
  local s = newState()
  ok(ap(s, { k = "squad", id = "A", a = "Cap-R", ts = T0 + 1, sq = 1, d = { name = "Alfa", captain = "Cap-R", members = { "Cap-R", "Au-R" } } }))
  local forged = prof("Au-R", T0 + 10, { squad = "A", note = "falso" })
  for _ = 1, 3 do
    local okA, why = ap(s, forged, "Y-R")
    eq(okA, false, "not applied"); eq(why, "pending")
  end
  eq(s.profiles["Au-R"], nil, "not stored as a real profile")
  local u = X.unverified(s, "profile", "Au-R")
  ok(u and u.r.d.note == "falso", "kept as unverified (shown grey)")
  eq(u.from, "Y-R", "the relayer is known (tooltip)")
  eq(M.isMember(s, "A", "Au-R"), false, "an unverified profile never makes a member (rankings, Tops)")
  eq(X.stats(s).pend, 1)
end)

-- AC3: two distinct relayers, same version -> verified. Two different versions -> none until the author
test("AC3: quorum of 2 distinct relayers applies; two versions apply nothing until the author", function()
  local s = newState()
  local v1 = prof("Au-R", T0 + 10, { note = "uno" })
  local okA, why = ap(s, v1, "Y-R"); eq(okA, false); eq(why, "pending")
  okA, why = ap(s, v1, "Y-R"); eq(okA, false, "the same relayer twice is still one")
  okA, why = ap(s, v1, "Z-R"); eq(okA, true, "second relayer"); eq(why, "verified")
  eq(s.profiles["Au-R"].d.note, "uno")
  eq(X.unverified(s, "profile", "Au-R"), nil, "no longer pending")
  eq(X.stats(s).verified, 1)
  -- the author's relay of the author's own record does not count as a relayer: it is live
  local s2 = newState()
  local a = prof("V-R", T0 + 10, { note = "a" })
  local b = prof("V-R", T0 + 10, { note = "b" })        -- same ts.sq.author, other content
  eq(select(2, ap(s2, a, "Y-R")), "pending")
  eq(select(2, ap(s2, b, "Z-R")), "conflict")
  eq(select(2, ap(s2, a, "W-R")), "conflict", "two relayers of A, but B exists: no version applies")
  eq(s2.profiles["V-R"], nil)
  okA = ap(s2, b, "V-R"); ok(okA, "the author live decides")
  eq(s2.profiles["V-R"].d.note, "b")
  eq(X.unverified(s2, "profile", "V-R"), nil, "the pending versions of that record are gone")
end)

-- AC4 (unit): the author's live version wins over any relay; the author's own client repudiates a fake
test("AC4: the author's live version wins, a repudiate removes the fake and counts the relayers", function()
  local s = newState()
  local fake = prof("Au-R", T0 + 50, { note = "falso" })
  ap(s, fake, "Y-R"); ok(ap(s, fake, "Z-R"), "two colluding relayers get it verified")
  local real = prof("Au-R", T0 + 10, { note = "real" })  -- older ts than the fake
  ok(ap(s, real, "Au-R"), "author live replaces a relayed version whatever the ts")
  eq(s.profiles["Au-R"].d.note, "real")
  -- the author's own client: a relayed record with my name that is not the one I hold -> "mine" (repudiate it)
  local me = newState()
  ok(ap(me, real))
  local okA, why = ap(me, fake, "Y-R", "Au-R")
  eq(okA, false); eq(why, "mine")
  eq(me.profiles["Au-R"].d.note, "real", "my own record untouched")
  -- the repudiate signed by the author removes that version everywhere and counts both relayers
  local s3 = newState()
  ap(s3, fake, "Y-R"); ap(s3, fake, "Z-R")
  eq(s3.profiles["Au-R"].d.note, "falso")
  local rp = X.repudiation(fake, "Au-R", T0 + 60, 2)
  ok(ap(s3, rp, "Au-R"), "repudiate applied live")
  eq(s3.profiles["Au-R"], nil, "the fake version is gone")
  eq(X.relayerScore(s3, "Y-R"), 1); eq(X.relayerScore(s3, "Z-R"), 1)
  local okB, whyB = ap(s3, fake, "W-R")
  eq(okB, false); eq(whyB, "repudiated", "a repudiated version is never taken again")
  eq(X.stats(s3).repudiated, 1)
  -- a repudiate relayed by a single member is pending (quorum like any authorial record)
  local s4 = newState()
  eq(select(2, ap(s4, rp, "Y-R")), "pending")
  -- nobody else can repudiate the author's record
  local bad = X.repudiation(fake, "Au-R", T0 + 60, 2); bad.a = "Y-R"
  eq(ap(s4, bad, "Y-R"), false)
end)

test("AC4: a relayer with 3 repudiations is blocked for the quorum for 7 days", function()
  local s = newState()
  for i = 1, 3 do
    local fake = prof("Au-R", T0 + 100 + i, { note = "f" .. i })
    ap(s, fake, "Y-R"); ap(s, fake, "Z-R")
    ok(ap(s, X.repudiation(fake, "Au-R", T0 + 200 + i, 10 + i), "Au-R"))
  end
  eq(X.relayerScore(s, "Y-R"), 3)
  ok(X.blocked(s, "Y-R", NOW), "blocked")
  ok(not X.blocked(s, "Y-R", NOW + 8 * DAY), "for 7 days only")
  local v = prof("V-R", T0 + 300, { note = "x" })
  eq(select(2, ap(s, v, "Y-R")), "pending")
  eq(select(2, ap(s, v, "Z-R")), "pending", "Y does not count: one vote only")
  eq(X.stats(s, NOW).blocked, 2, "Y and Z were both in the three fakes")
  ok(X.diagLine(s, NOW):find("^p2p pend=%d+ verified=%d+ repudiated=%d+ blocked=%d+"), X.diagLine(s, NOW))
end)

-- AC5 (1.1) -> v1.2 AC1/AC4 (D1 = 2, BRO 7-nov 19:04): authority records relayed by a non-officer wait pending until
-- QUORUM_AUTH = 2 distinct relayers
test("v1.2: authority kinds relayed by a non-officer stay pending, never stored, until 2 distinct relayers", function()
  local s = newState()
  local recs = {
    { k = "settings", id = "settings", a = "Gm-R", ts = T0 + 5, sq = 2, d = { squadsEnabled = false } },
    { k = "squad", id = "A", a = "Cap-R", ts = T0 + 5, sq = 1, d = { name = "Alfa", captain = "Cap-R", members = { "Cap-R" } } },
    { k = "reject", id = "A|Au-R|req", a = "Cap-R", ts = T0 + 5, sq = 1, d = { sid = "A", name = "Au-R", kind = "req", on = true } },
    { k = "annul", id = "r|k", a = "Gm-R", ts = T0 + 5, sq = 1, d = { race = "r", key = "k", reason = "x", on = true } },
    { k = "roster", id = "Cap-R:1", a = "Cap-R", ts = T0 + 5, sq = 1, d = { raid = "custom", size = 10, name = "R", at = T0 + 9000, st = "draft" } },
    { k = "attendance", id = "Cap-R:1", a = "Cap-R", ts = T0 + 5, sq = 1, d = { rid = "Cap-R:1", names = { "Cap-R" } } },
    prof("Cap-R", T0 + 5, { squad = "A", xferTo = "A>Y-R" }),
  }
  for _, r in ipairs(recs) do
    local okA, why = ap(s, r, "Y-R")
    eq(okA, false, r.k); eq(why, "pending", r.k)
    okA, why = ap(s, r, "Y-R"); eq(why, "pending", r.k .. " twice (same relayer)")
  end
  -- one relayer (even twice) never verifies; the second distinct one does
  eq(X.QUORUM_AUTH, 2)
  eq(s.settings.d.squadsEnabled, true, "settings not replaced with 1 relayer")
  eq(s.squads["A"], nil, "squad not stored")
  eq(select(2, ap(s, recs[1], "Z-R")), "verified", "second distinct relayer")
  eq(s.settings.d.squadsEnabled, false)
  -- an officer relay of an unverified forward (u = 1) is not trusted
  local u = prof("V-R", T0 + 5); u.u = 1
  eq(select(2, ap(s, u, "Of-R")), "pending")
  eq(s.profiles["V-R"], nil)
  -- and an officer relay still is (unchanged)
  ok(ap(s, prof("W-R", T0 + 5), "Of-R"))
end)

-- AC5b: captains are authority nodes of their own squad only
test("AC5b: the captain of A verifies A's records at once, not B's; an ex-captain stops being a node", function()
  local s = newState()
  ok(ap(s, { k = "squad", id = "A", a = "Cap-R", ts = T0 + 1, sq = 1, d = { name = "Alfa", captain = "Cap-R", members = { "Cap-R", "Au-R", "Z-R" } } }))
  ok(ap(s, { k = "squad", id = "B", a = "CapB-R", ts = T0 + 1, sq = 1, d = { name = "Beta", captain = "CapB-R", members = { "CapB-R", "W-R" } } }))
  ok(ap(s, prof("Cap-R", T0 + 2, { squad = "A" })))
  ok(ap(s, prof("CapB-R", T0 + 2, { squad = "B" })))
  local okA, why = ap(s, prof("Au-R", T0 + 3, { squad = "A" }), "Cap-R")
  eq(okA, true, "member of A relayed by A's captain"); eq(why, "verified")
  eq(select(2, ap(s, prof("W-R", T0 + 3, { squad = "B" }), "Cap-R")), "pending", "B's profile: one relayer")
  -- RSVPs: the event's squad is the squad of the roster owner
  local function ros(owner) return { k = "roster", id = owner .. ":1", a = owner, ts = T0 + 4, sq = 1,
    d = { raid = "custom", size = 10, name = "Raid", at = T0 + 90000, st = "published", main = {}, bench = {} } } end
  ok(ap(s, ros("Cap-R"))); ok(ap(s, ros("CapB-R")))
  local function rsvp(name, rid) return { k = "rsvp", id = R.rsvpId(rid, name), a = name, ts = T0 + 6, sq = 1, d = { rid = rid, name = name, v = "yes" } } end
  eq(select(2, ap(s, rsvp("Au-R", "Cap-R:1"), "Cap-R")), "verified", "RSVP to A's event")
  eq(select(2, ap(s, rsvp("W-R", "CapB-R:1"), "Cap-R")), "pending", "RSVP to B's event")
  -- the captain of A gains nothing over guild authority records
  eq(select(2, ap(s, { k = "settings", id = "settings", a = "Gm-R", ts = T0 + 7, sq = 3, d = { squadsEnabled = false } }, "Cap-R")), "pending")
  -- transfer: Cap signs xferTo A>Au-R in his own profile (live) -> he is no longer A's node
  ok(ap(s, prof("Cap-R", T0 + 8, { squad = "A", xferTo = "A>Au-R" }), "Cap-R"))
  eq(select(2, ap(s, prof("Z-R", T0 + 9, { squad = "A" }), "Cap-R")), "pending", "ex-captain = one relayer")
  -- a receiver that does not know the squad yet counts the captain as one ordinary relayer
  local s2 = newState()
  eq(select(2, ap(s2, prof("Au-R", T0 + 3, { squad = "A" }), "Cap-R")), "pending")
end)

-- AC6: the installed counter (presence records, adoptDays = 30)
test("AC6: the counter counts presence in the last 30 days, lists who has it, flags a GM without it", function()
  local s = newState()
  local function pres(a, ts, ver) return { k = "presence", id = a, a = a, ts = ts, sq = 1, d = { ver = ver or "1.1.0", day = math.floor(ts / DAY) } } end
  ok(ap(s, pres("Au-R", NOW - 3 * DAY, "1.1.0")), "presence of 3 days ago")
  ok(ap(s, pres("Y-R", NOW - 31 * DAY, "1.1.0")), "presence of 31 days ago")
  ok(ap(s, pres("Z-R", NOW - 1 * DAY, "1.1.1")))
  eq(ap(s, pres("W-R", NOW, "1.1.0"), "Y-R"), false, "a relayed presence follows the quorum")
  eq(ap(s, { k = "presence", id = "Au-R", a = "Y-R", ts = NOW, sq = 2, d = { ver = "x", day = 1 } }), false, "only about oneself")
  local members = {}
  for n, rk in pairs(RANKS) do members[n] = { rank = rk, online = false, seen = 1 } end
  local a = X.adoption(s, members, NOW)
  eq(a.n, 2, "Au (3 days, offline) and Z count; Y (31 days) does not")
  eq(a.days, 30)
  eq(a.total, 9)
  eq(#a.list, 2); eq(a.list[1].name, "Au-R"); eq(a.list[1].ver, "1.1.0"); eq(a.list[2].name, "Z-R")
  eq(a.gmMissing, true, "rank 0 has no presence")
  ok(ap(s, pres("Gm-R", NOW - DAY)))
  eq(X.adoption(s, members, NOW).gmMissing, false)
  -- adoptDays from the GM settings
  ok(ap(s, { k = "settings", id = "settings", a = "Gm-R", ts = T0 + 9, sq = 5, d = { squadsEnabled = true, adoptDays = 60 } }))
  eq(X.adoption(s, members, NOW).n, 4, "Y counts with 60 days")
  -- the visible text
  ok(type(X.counterText) == "function")
  -- pruning: a presence of someone who left the guild or older than 60 days goes away
  members["Au-R"] = nil
  local gone = X.prunePresence(s, members, NOW + 40 * DAY)
  eq(gone, 2, "Au (left) and Y (71 days) pruned")
  eq(s.presence["Au-R"], nil); eq(s.presence["Y-R"], nil); ok(s.presence["Z-R"])
end)

test("p2p: pending store is bounded (2000) and expires after 7 days", function()
  local s = newState()
  for i = 1, 2010 do
    local n = "N" .. i .. "-R"
    RANKS[n] = 5
    ap(s, { k = "presence", id = n, a = n, ts = T0 + i, sq = 1, d = { ver = "1", day = 1 } }, "Y-R")
  end
  ok(X.stats(s).pend <= 2000, "at most 2000: " .. X.stats(s).pend)
  X.expire(s, NOW + 8 * DAY)
  eq(X.stats(s).pend, 0, "expired after 7 days")
  for i = 1, 2010 do RANKS["N" .. i .. "-R"] = nil end
end)

-- full client (zload fake WoW): /gsq diag carries the p2p line, our presence is published, the counter text is real
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "v1.1: /gsq diag p2p line, own presence published, counter 'Guild Squads: X/Y (30 days)'", function(c)
  local ns = c.ns
  local rep = ns.DiagGlue.Report()
  ok(type(rep) == "string" and rep:find("p2p pend=%d+ verified=%d+ repudiated=%d+ blocked=%d+"), "diag p2p line")
  local p = ns.state.presence and ns.state.presence[ns.me()]
  ok(p and p.d.day == math.floor(GetServerTime() / 86400), "own presence of today")
  local text = ns.HallGlue.AdoptionText()
  ok(text:find("%d+/%d+") and text:find("30"), text)
  ok(ns.Actions.PublishPresence() == false, "at most once a day")
end }

-- full client: an unverified profile shows in the finder, grey with "unverified", and never as a verified member
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "v1.1: an unverified profile is listed grey in the finder with its relayer", function(c)
  local ns = c.ns
  local cache = ns.rosterList()
  cache["Uv-Realm"] = { rank = 5, online = false, level = 30, class = "MAGE" }
  cache["Rl-Realm"] = { rank = 5, online = true, level = 30, class = "MAGE" }
  local okA, why = ns.Sync.Apply({ k = "profile", id = "Uv-Realm", a = "Uv-Realm", ts = GetServerTime() - 10, sq = 1,
    d = { role = "HEALER", level = 30, note = "uv" } }, "Rl-Realm")
  eq(okA, false); eq(why, "pending")
  eq(ns.state.profiles["Uv-Realm"], nil)
  ns.UI.Select("finder")
  local found
  for _, o in ipairs(c.allObjs) do
    local t = rawget(o, "_text")
    if type(t) == "string" and t:find("Uv", 1, true) and t:find(ns.L.UNVERIFIED, 1, true) then found = o end
  end
  ok(found, "grey unverified card in the finder")
  cache["Uv-Realm"], cache["Rl-Realm"] = nil, nil
end }

-- v1.2 AC4: the GM repudiates a forged settings verified by quorum; a flooding relayer is capped at 200 pending
test("v1.2: repudiate works on authority kinds (settings verified by 2 relayers is removed, relayers counted)", function()
  local s = newState()
  local fake = { k = "settings", id = "settings", a = "Gm-R", ts = T0 + 50, sq = 7, d = { squadsEnabled = false } }
  for _, n in ipairs({ "Y-R", "Z-R" }) do ap(s, fake, n) end
  eq(s.settings.d.squadsEnabled, false, "verified by quorum 2")
  ok(ap(s, X.repudiation(fake, "Gm-R", T0 + 60, 8), "Gm-R"))
  eq(s.settings, nil, "the forged settings is gone")
  eq(X.relayerScore(s, "Y-R"), 1); eq(X.relayerScore(s, "Z-R"), 1)
  -- someone else cannot repudiate the GM's version
  local s2 = newState()
  ap(s2, fake, "Y-R")
  local bad = X.repudiation(fake, "Gm-R", T0 + 60, 8); bad.a = "Z-R"
  eq(select(2, ap(s2, bad, "Z-R")), "denied")
end)

-- v1.2 AC4 (S16): the stored copy of a verified fake has another content hash (defaults filled in on store), so the
-- GM denies that hash. The same signed version (same kind:id@ts.sq.author) with the wire content, still pending on
-- other clients, goes too, and never comes back by relay; the author's live record is not blocked.
test("v1.2: a repudiate removes pending copies of the same signed version with another content hash", function()
  local s = newState()
  local wire = { k = "settings", id = "settings", a = "Gm-R", ts = T0 + 50, sq = 7, d = { squadsEnabled = false } }
  eq(select(2, ap(s, wire, "Y-R")), "pending")
  local filled = copy(wire); filled.d.bench = 0; filled.d.minCreateRank = 9
  ok(X.vkey(filled) ~= X.vkey(wire), "two content hashes of one signed version")
  ok(ap(s, X.repudiation(filled, "Gm-R", T0 + 60, 8), "Gm-R"))
  eq(X.unverified(s, "settings", "settings"), nil, "the wire copy is no longer pending")
  eq(X.relayerScore(s, "Y-R"), 1, "its relayer is counted")
  local _, why = ap(s, wire, "Z-R")
  eq(why, "repudiated", "the wire copy never comes back by relay")
  -- the same for a squad that nobody stored (only pending)
  local sq = { k = "squad", id = "Cap-R:1", a = "Cap-R", ts = T0 + 70, sq = 3, d = { name = "Hack", captain = "Cap-R", members = { "Cap-R" } } }
  eq(select(2, ap(s, sq, "Y-R")), "pending")
  local sq2 = copy(sq); sq2.d.ct = T0 + 70
  ok(ap(s, X.repudiation(sq2, "Cap-R", T0 + 80, 4), "Cap-R"))
  eq(X.unverified(s, "squad", "Cap-R:1"), nil, "the pending squad is gone")
  -- a newer live version of the author is untouched
  ok(ap(s, { k = "settings", id = "settings", a = "Gm-R", ts = T0 + 90, sq = 9, d = { squadsEnabled = true } }, "Gm-R"))
  eq(s.settings.d.squadsEnabled, true)
end)

test("v1.2: one relayer holds at most MAX_PEND_RELAYER pending versions; others are not evicted", function()
  local s = newState()
  eq(select(2, ap(s, prof("V-R", T0 + 5, { note = "legit" }), "Z-R")), "pending")
  local capped = 0
  for i = 1, 1000 do
    local _, why = ap(s, { k = "squad", id = "Cap-R:" .. i, a = "Cap-R", ts = T0 + 10, sq = i,
      d = { name = "F" .. i, captain = "Cap-R", members = { "Cap-R" } } }, "Y-R")
    if why == "cap" then capped = capped + 1 end
  end
  eq(X.pendBy(s, "Y-R"), X.MAX_PEND_RELAYER)
  eq(capped, 1000 - X.MAX_PEND_RELAYER)
  eq(X.unverified(s, "profile", "V-R").r.d.note, "legit", "the legit pending version survives")
end)

-- v1.2 AC3 (BRO 7-nov 19:04): when the client is synced (a hello round with no differences, or 60 s without new
-- records after the last round) one local chat line, once per session: "Guild Squads: synced (N records, M pending)"
SMOKE_CHECKS[#SMOKE_CHECKS + 1] = { "v1.2 AC3: the 'synced' chat line fires once per session with N records and M pending", function(c)
  local ns = c.ns
  local Sync = ns.Sync
  ok(type(Sync.NoteRound) == "function" and type(Sync.CheckSynced) == "function", "Sync.NoteRound / CheckSynced")
  local got = {}
  Sync.chatSink = function(line) got[#got + 1] = line end
  Sync.ResetSynced()
  local t = 1000
  Sync.NoteRecord(t)
  Sync.NoteRound(5, t + 30, true)            -- still learning, more rounds to come: nothing
  eq(#got, 0, "not while rounds go on")
  Sync.NoteRound(3, t + 60, false)           -- last round taught 3 records: wait 60 s of silence
  Sync.NoteRecord(t + 80)
  Sync.CheckSynced(t + 125)                  -- only 45 s since the last record
  eq(#got, 0, "not before 60 s of silence")
  Sync.CheckSynced(t + 141)
  eq(#got, 1, "fires after 60 s without new records")
  local n, m = Sync.SyncedCounts()
  eq(got[1], ns.L.SYNCED:format(n, m))
  ok(got[1]:find("^Guild Squads: ") and got[1]:find(tostring(n), 1, true) and got[1]:find(tostring(m), 1, true), got[1])
  Sync.NoteRound(0, t + 200, true)           -- a round with no differences later: once per session
  Sync.CheckSynced(t + 400)
  eq(#got, 1, "once per session")
  -- a round with no differences fires at once (new session)
  Sync.ResetSynced(); got = {}
  Sync.NoteRound(0, t + 500, true)
  eq(#got, 1, "a hello round with no differences = synced")
  -- the default sink is the local chat frame (never the network)
  Sync.chatSink = nil
  local seen
  local old = DEFAULT_CHAT_FRAME
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, s) seen = s end }
  Sync.ResetSynced(); Sync.NoteRound(0, t + 600, true)
  DEFAULT_CHAT_FRAME = old
  ok(seen and seen:find("^Guild Squads: "), "DEFAULT_CHAT_FRAME:AddMessage")
end }
