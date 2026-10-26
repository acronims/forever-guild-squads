-- observations: sentAt window, backdated kills, ACK + retry, per-character migration, announcer claims
local R, Cel, S = NS.Races, NS.Celebrate, NS.Serialize
local T0 = 1795000000
local function cnt(k, n, ts, key, by)
  return { t = "cnt", who = by or "Ali-R", by = by or "Ali-R", ts = ts, k = k, key = key, n = n }
end

test("sentAt: queue blocked 40 min accepted, 30 days back refused, clock skew +-200 s accepted", function()
  local now = T0
  -- HK step crossed 40 min before the queue unblocked; the message left (sentAt) 2 s before it arrived
  ok(R.liveOk(cnt("hk", 100, now - 2400), now, now - 2), "40 min in a blocked queue")
  ok(R.liveLevelOk({ t = "lv", who = "Ali-R", by = "Ali-R", ts = now - 2400, src = "self", lv = 60 }, now, nil, now - 2), "level too")
  ok(R.liveOk({ t = "kill", ts = now - 2400 }, now, now - 1), "kill too")
  ok(not R.liveOk(cnt("hk", 100, now - 30 * 86400), now, now), "30 days back refused")
  ok(not R.liveOk(cnt("hk", 100, now - 3 * 3600 - 1), now, now), "more than 3 h queued refused")
  -- sender clock 200 s ahead / behind: ts and sentAt both in the sender clock
  ok(R.liveOk(cnt("hk", 100, now + 200 - 60), now, now + 200), "+200 s skew")
  ok(R.liveOk(cnt("hk", 100, now - 200 - 60), now, now - 200), "-200 s skew")
  ok(not R.liveOk(cnt("hk", 100, now - 60), now, now - 301), "stamp more than 300 s off refused")
  ok(not R.liveOk(cnt("hk", 100, now + 10), now, now), "event after its own send refused")
end)

test("Comm body: the stamped body is the deterministic encoding of { p, s, t, v }", function()
  local ns2 = { Serialize = S, Chunk = NS.Chunk, Queue = NS.Queue }
  local Comm = loadmod("Comm.lua", ns2)
  local p = { o = { { t = "cnt", n = 5 } }, k = "x" }
  eq(Comm.Body("RO", p, 1795000000), S.encode({ p = p, s = "1795000000", t = "RO", v = Comm.PROTO }))
end)

test("backdated kills: kept unverified, never scored; an officer relay confirms", function()
  local s = R.newStore()
  local ev = { t = "kill", who = "Eve-R", by = "Eve-R", ts = T0 - 30 * 86400, inst = "Foo Keep", it = "raid", enc = 1, pres = {}, sqm = {} }
  ok(R.add(s, ev, T0)); local id = R.obsId(R.sanitize(ev))
  eq(s.obs[id].uv, 1, "unverified")
  ok(R.add(s, ev, T0, true)); eq(s.obs[id].uv, nil, "officer relay confirms")
  -- SavedVariables keep the mark
  local s2 = R.newStore(); local saved = {}
  for k, v in pairs(ev) do saved[k] = v end
  saved.uv = 1
  R.add(s2, saved); eq(s2.obs[id].uv, 1)
end)

test("ACK + retry: own observations are sent again until a peer holds them or 3 h pass", function()
  local s = R.newStore()
  local a, b = cnt("hk", 0, T0), cnt("hk", 100, T0 + 3600)
  local _, ida = R.add(s, a, T0); local _, idb = R.add(s, b, T0 + 3600)
  local pend = { [ida] = T0, [idb] = T0 + 3600 }
  -- a peer with nothing: both are sent again
  local empty = R.bucketHashes(R.newStore())
  eq(#R.ackScan(pend, s, empty, T0 + 3700), 2)
  -- a peer that holds `a` only: a acknowledged, b sent again
  local peer = R.newStore(); R.add(peer, a)
  local again = R.ackScan(pend, s, R.bucketHashes(peer), T0 + 3700)
  if R.bucketOf("o:" .. ida) ~= R.bucketOf("o:" .. idb) then
    eq(#again, 1); eq(pend[ida], nil, "acknowledged"); ok(pend[idb], "still pending")
  end
  -- 3 h later: forgotten
  R.ackScan(pend, s, empty, T0 + 3600 + 3 * 3600 + 1)
  eq(next(pend), nil, "expired")
end)

test("migration: sent / hkBase per character (legacy flat tables), idempotent", function()
  local rdb = { obs = {}, sent = { ["prof|Mining|150|"] = true, ["hk||100|"] = true, ["caps||10|"] = true }, hkBase = 4000 }
  for _, e in ipairs({ cnt("prof", 150, T0, "Mining", "Main-R"), cnt("hk", 100, T0 + 5, nil, "Alt-R"), cnt("hk", 100, T0 + 9, nil, "Main-R") }) do
    rdb.obs[R.obsId(R.sanitize(e))] = R.sanitize(e)
  end
  R.migrateCharState(rdb)
  ok(rdb.sent["Main-R"]["prof|Mining|150|"], "prof step goes to the character that reported it")
  ok(rdb.sent["Alt-R"]["hk||100|"], "hk step: lowest name holding it")
  eq(rdb.sent["caps||10|"], nil, "flat keys removed"); eq(rdb.sent["Main-R"]["caps||10|"], nil, "unmatched step dropped")
  eq(rdb.hkBase["Alt-R"], 4000, "hkBase to the earliest HK reporter"); eq(rdb.hkBase["Main-R"], nil, "the other character starts fresh")
  R.migrateCharState(rdb); ok(rdb.sent["Main-R"]["prof|Mining|150|"], "idempotent")
  -- a per-character table stays as it is
  local fresh = { obs = {}, sent = { ["Ali-R"] = { x = true } }, hkBase = { ["Ali-R"] = 7 } }
  R.migrateCharState(fresh); ok(fresh.sent["Ali-R"].x); eq(fresh.hkBase["Ali-R"], 7)
end)

test("with candidates: a claim that left the queue late still yields one announcer", function()
  local cands = { "Zed-R", "Abe-R" }          -- Zed preferred (protagonist), Abe backup
  local function run(arriveA)
    local a, b = Cel.newClaims(), Cel.newClaims()
    Cel.setCandidates(a, "k", cands); Cel.setCandidates(b, "k", cands)
    Cel.noteClaim(b, "k", "Abe-R", 8)          -- B claims at 8 (sent at once)
    Cel.noteClaim(a, "k", "Abe-R", 8.5)        -- A hears B
    Cel.noteClaim(a, "k", "Zed-R", arriveA - 0.3) -- A's own claim noted when it really left the queue
    Cel.noteClaim(b, "k", "Zed-R", arriveA)    -- B hears A
    return Cel.claimWinner(a, "k"), Cel.claimWinner(b, "k")
  end
  local wa, wb = run(9); eq(wa, wb, "both books agree (inside the hold)"); eq(wa, "Zed-R")
  -- (residual: a claim landing within one network latency of the hold edge can still split the books)
  wa, wb = run(11); eq(wa, wb, "both books agree (A claim too late)"); eq(wa, "Abe-R")
  -- non-candidates are ignored; a busy candidate is skipped
  local book = Cel.newClaims(); Cel.setCandidates(book, "k", cands)
  Cel.noteClaim(book, "k", "Eve-R", 1); ok(not Cel.claimed(book, "k"), "non-candidate claim ignored")
  local ctx = { online = function() return true end, hasAddon = function() return true end,
                rank = function(n) return ({ ["Gm-R"] = 0, ["Off-R"] = 1 })[n] or 5 end, users = { "Off-R", "Gm-R", "Bob-R", "Cid-R" } }
  local c = Cel.candidates({ "Zed-R" }, ctx, function(n) return n == "Zed-R" end)
  eq(table.concat(c, ","), "Gm-R,Off-R,Bob-R", "busy protagonist skipped, then rank order, max 3")
end)

test("SQ flood: one per 30 s per sender, never the same summary twice to the same requester", function()
  local Pr, g = NS.Progress, {}
  ok(Pr.sqGate(g, "Eve-R", "W1", "h1", 100), "first request served")
  ok(not Pr.sqGate(g, "Eve-R", "W2", "h2", 110), "second within 30 s dropped")
  ok(not Pr.sqGate(g, "Eve-R", "W1", "h1", 200), "same summary again: already served")
  ok(Pr.sqGate(g, "Eve-R", "W2", "h2", 240), "another wipe after 30 s")
  ok(Pr.sqGate(g, "Bob-R", "W1", "h1", 110), "other senders independent")
end)
