-- Guild Squads (MIT) - Core/Races.lua
-- Pure Lua (no WoW API). "Salón de la fama": races (Top 100 / 10 / 3) computed locally from replicated
-- observations, witness rules, squad-alliance crediting (docs/en/ACHIEVEMENTS.md §3), GM annulments with history,
-- frozen (immutable) closed races, compaction, paginated sync helpers, achievements and guild adoption.
--
-- RaceObs (whitelisted fields only, see R.SCHEMA). `by` = the reporting client (must equal the sender).
--   lv:   { t="lv", who, by, ts, src="self"|"roster", lv, cls?, race? }   milestone level reached (10..60)
--   kill: { t="kill", who=by, by, ts, inst, iid?, it, enc?, boss?, gs?, pres={names}, sqm={"name>sid"} }
--   bg:   { t="bg", who=by, by, ts, inst (map), win=1|0, pres, sqm }
--   cnt:  { t="cnt", who=by, by, ts, k="hk"|"caps"|"prof"|"rep"|"legacy"|"pvprank", key?, n, cls?, sea? }
-- RaceEntry (computed / frozen): { key, pos, ts, mark, chars={}, squads={}, sup={}, wit, mixed?, ex? }
-- No economy fields anywhere (see the schema test).
local _, ns = ...
ns = ns or {}

local R = {}
ns.Races = R
local Content = ns.Content
local floor, min, max = math.floor, math.min, math.max

R.LEVELS = { 10, 20, 30, 40, 50, 60 }
R.LEVEL_WINDOW = 600        -- 10 min between level witnesses
R.KILL_WINDOW = 180         -- boss / BG witnesses
R.PENDING_TTL = 86400       -- a kill with a single report stays "pending" 24 h
R.MIN_WITNESSES = 2
R.MIN_SQUAD = 3             -- members of one squad present to credit that squad
R.ALLIANCE_SHARE = 0.7      -- share of the required kills a squad must attend (alliance crediting)
R.BG_TOGETHER = 2           -- squad members in a BG to count it as "together"
R.RUN_WINDOW = 7 * 86400    -- a raid "run" = kills of that raid in the 7 days before the final boss
R.HK_STEPS = { 100, 1000, 5000 }
R.BG_STEPS = { 10, 50, 100 }
R.CAPS_STEPS = { 10, 100 }
R.PROF_STEPS = { 150, 225, 300 }
R.LEGACY_STEPS = { 100, 500, 1000 }
R.PVP_RANKS = { 5, 10, 12, 14 }
R.EXALTED = 8
R.ADOPT_DAYS = 14
R.ADOPT_GOAL = 0.8
R.CNT_KINDS = { hk = true, caps = true, prof = true, rep = true, legacy = true, pvprank = true }
R.CATS = { "level", "class", "race", "dungeon", "raid", "pvp", "other" }
R.LIVE_PAST, R.LIVE_FUTURE = 600, 300   -- a live level report must be dated inside [now-600, now+300] (receiver clock)
R.QUIET = 600               -- a race is not frozen until 10 min after the last observation received
R.MAX_DYN = 300             -- races created on the fly (keys taken from the data) per compute
R.MIN_REPORTERS = 2         -- a non-whitelisted key needs >= 2 distinct reporters to create a race
R.MAX_OBS_PER_AUTHOR = 2000 -- store.obs cap per reporter (SavedVariables + replication)
local function set(list) local t = {} for _, v in ipairs(list) do t[v] = true end return t end
R.CLASS_OK = set({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
                   "DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER" })
R.RACE_OK = set({ "HUMAN", "DWARF", "NIGHTELF", "GNOME", "ORC", "SCOURGE", "UNDEAD", "TAUREN", "TROLL", "BLOODELF",
                  "DRAENEI", "GOBLIN", "WORGEN", "PANDAREN", "HIGHELF", "VOIDELF", "NIGHTBORNE" })
-- professions / reputations whitelisted by slug (enUS + esES); anything else needs >= 2 reporters
R.PROF_OK = set({ "alchemy", "blacksmithing", "enchanting", "engineering", "herbalism", "leatherworking", "mining",
  "skinning", "tailoring", "jewelcrafting", "inscription", "cooking", "first_aid", "fishing",
  "alquimia", "herrería", "encantamiento", "ingeniería", "herboristería", "peletería", "minería", "desuello",
  "sastrería", "joyería", "inscripción", "cocina", "primeros_auxilios", "pesca" })
R.REP_OK = set({ "stormwind", "ironforge", "darnassus", "gnomeregan_exiles", "gnomeregan", "orgrimmar", "thunder_bluff",
  "undercity", "darkspear_trolls", "argent_dawn", "timbermaw_hold", "cenarion_circle", "hydraxian_waterlords",
  "brood_of_nozdormu", "zandalar_tribe", "thorium_brotherhood", "bloodsail_buccaneers", "booty_bay", "gadgetzan",
  "everlook", "ratchet", "silverwing_sentinels", "warsong_outriders", "stormpike_guard", "frostwolf_clan",
  "the_league_of_arathor", "league_of_arathor", "the_defilers", "wintersaber_trainers", "ravenholdt",
  "darkmoon_faire", "shen'dralar", "steamwheedle_cartel",
  "ventormenta", "forjaz", "exiliados_de_gnomeregan", "cima_del_trueno", "entrañas", "trols_lanzanegra",
  "alba_argenta", "bastión_fauces_de_madera", "círculo_cenarion", "prole_de_nozdormu", "tribu_zandalar",
  "hermandad_del_torio", "bucaneros_velasangre", "bahía_del_botín", "vista_eterna", "trinquete",
  "centinelas_ala_de_plata", "escoltas_grito_de_guerra", "guardia_pico_tormenta", "clan_lobo_gélido",
  "liga_de_arathor", "los_rapiñadores", "feria_de_la_luna_negra", "cártel_bonvapor" })

-------------------------------------------------------------------------------
-- schema
R.SCHEMA = {
  t = { "s", 5 }, who = { "s", 48 }, by = { "s", 48 }, ts = { "n" }, src = { "s", 6 },
  lv = { "n" }, cls = { "s", 16 }, race = { "s", 24 },
  inst = { "s", 64 }, iid = { "n" }, it = { "s", 8 }, enc = { "n" }, boss = { "s", 64 }, gs = { "n" },
  win = { "n" }, pres = { "L", 40, 48 }, sqm = { "L", 40, 100 },
  k = { "s", 8 }, key = { "s", 48 }, n = { "n" }, sea = { "s", 16 },
}
local KEEP = {
  lv = { src = 1, lv = 1, cls = 1, race = 1 },
  kill = { inst = 1, iid = 1, it = 1, enc = 1, boss = 1, gs = 1, pres = 1, sqm = 1 },
  bg = { inst = 1, win = 1, pres = 1, sqm = 1 },
  cnt = { k = 1, key = 1, n = 1, cls = 1, sea = 1 },
}
local BASE = { t = 1, who = 1, by = 1, ts = 1 }

local function norm(s) return type(s) == "string" and s:lower():gsub("^%s+", ""):gsub("%s+$", "") or "" end
-- id-safe slug: letters / digits only (keeps UTF-8 bytes of localized names), spaces -> "_"
local function slug(s)
  s = norm(s):gsub("%s+", "_"):gsub("[%.|~;,>@:%+]", "")
  return s ~= "" and s or "?"
end
R.slug = slug
local function isInt(v) return type(v) == "number" and v == floor(v) end

function R.sanitize(ev)
  if type(ev) ~= "table" then return nil, "shape" end
  local keep = KEEP[ev.t]
  if not keep then return nil, "type" end
  local out = {}
  for field, spec in pairs(R.SCHEMA) do
    local v, ty = ev[field], spec[1]
    if v ~= nil and (BASE[field] or keep[field]) then
      if ty == "s" and type(v) == "string" then out[field] = v:sub(1, spec[2])
      elseif ty == "n" and type(v) == "number" and v == v and v < 1e15 and v > -1e15 then out[field] = v
      elseif ty == "L" and type(v) == "table" then
        local l = {}
        for i = 1, min(#v, spec[2]) do if type(v[i]) == "string" then l[#l + 1] = v[i]:sub(1, spec[3]) end end
        out[field] = l
      end
    end
  end
  if type(out.who) ~= "string" or out.who == "" or type(out.by) ~= "string" or out.by == ""
     or type(out.ts) ~= "number" then return nil, "shape" end
  out.ts = floor(out.ts)
  if out.t == "lv" then
    if not isInt(out.lv) or out.lv < 2 or out.lv > 60 then return nil, "level" end
    if out.src == "self" then
      if out.by ~= out.who then return nil, "denied" end
    else out.src = "roster" end
  else
    if out.who ~= out.by then return nil, "denied" end -- kills, BGs and counters are reported by their author
    if out.t == "kill" then
      if out.it ~= "party" and out.it ~= "raid" then return nil, "instanceType" end
      if not ((out.enc and out.enc > 0) or (out.inst and out.boss)) then return nil, "shape" end
    elseif out.t == "bg" then
      if out.win ~= 0 and out.win ~= 1 then return nil, "win" end
      out.inst = out.inst or "?"
    elseif out.t == "cnt" then
      if not R.CNT_KINDS[out.k] then return nil, "kind" end
      if not isInt(out.n) or out.n < 0 or out.n > 1000000 then return nil, "count" end
      if (out.k == "prof" or out.k == "rep") and (type(out.key) ~= "string" or out.key == "") then return nil, "shape" end
    end
    out.pres = (out.t == "kill" or out.t == "bg") and (out.pres or {}) or nil
    out.sqm = (out.t == "kill" or out.t == "bg") and (out.sqm or {}) or nil
  end
  return out
end

local function killKey(ev)
  if ev.t == "bg" then return "b" .. norm(ev.inst) .. "#" .. tostring(ev.win) end
  if ev.enc and ev.enc > 0 then return "e" .. ev.enc end
  return "n" .. norm(ev.inst) .. "|" .. norm(ev.boss)
end
R.killKey = killKey

function R.obsId(ev)
  local tail
  if ev.t == "lv" then tail = ev.who .. "#" .. ev.lv
  elseif ev.t == "cnt" then tail = ev.k .. "#" .. (ev.key or "") .. "#" .. ev.n .. "#" .. (ev.sea or "")
  else tail = killKey(ev) end
  return ev.by .. "|" .. ev.t .. "|" .. ev.ts .. "|" .. tail
end

function R.newStore() return { obs = {}, closed = {} } end

-- rxNow (optional) = receiver clock when the observation arrived: races are not frozen for R.QUIET seconds after it
-- trusted (optional) = relayed by a GM/officer: confirms an observation we hold as "unverified".
-- a kill, BG or counter received (rxNow given, not trusted) dated
-- outside [rxNow - R.MAX_DELAY - R.SENT_SKEW, rxNow + R.SENT_SKEW] is kept but marked `uv` ("no verificado"): it is
-- replicated by nobody's officer pages, never scored, and confirmed only when a GM/officer relays it.
local UV_KINDS = { kill = true, bg = true, cnt = true }
function R.add(store, ev, rxNow, trusted)
  local clean, why = R.sanitize(ev)
  if not clean then return false, why end
  local id = R.obsId(clean)
  local had = store.obs[id]
  if had then
    if trusted and had.uv then had.uv = nil; return true, id end
    return false, "dup"
  end
  if rxNow == nil and type(ev) == "table" and ev.uv == 1 then clean.uv = 1 end   -- SavedVariables keep the mark
  if type(rxNow) == "number" and not trusted and UV_KINDS[clean.t]
     and (clean.ts < rxNow - R.MAX_DELAY - R.SENT_SKEW or clean.ts > rxNow + R.SENT_SKEW) then clean.uv = 1 end
  -- counters must be monotonic with plausible jumps (also for our own readings)
  -- (network and own readings only: rxNow given; loading SavedVariables keeps what was already accepted)
  if type(rxNow) == "number" then
    local okC, whyC = R.counterOk(store, clean)
    if not okC then return false, whyC end
  end
  -- one level report per reporter + character + level, the earliest one wins (order independent)
  local lvKey
  if clean.t == "lv" then
    if not store.lvIdx then
      store.lvIdx = {}
      for oid, o in pairs(store.obs) do
        if o.t == "lv" then
          local k = o.by .. "|" .. o.who .. "#" .. o.lv
          local cur = store.lvIdx[k] and store.obs[store.lvIdx[k]]
          if not cur or o.ts < cur.ts then store.lvIdx[k] = oid end
        end
      end
    end
    lvKey = clean.by .. "|" .. clean.who .. "#" .. clean.lv
    local oldId = store.lvIdx[lvKey]
    local old = oldId and store.obs[oldId]
    if old then
      if old.ts <= clean.ts then return false, "dup" end
      store.obs[oldId] = nil                     -- an earlier report of the same level replaces the later one
      if store.nBy and store.nBy[old.by] then store.nBy[old.by] = store.nBy[old.by] - 1 end
    end
  end
  -- per-reporter cap (counted lazily, reset by compaction)
  if not store.nBy then
    store.nBy = {}
    for _, o in pairs(store.obs) do store.nBy[o.by] = (store.nBy[o.by] or 0) + 1 end
  end
  if (store.nBy[clean.by] or 0) >= R.MAX_OBS_PER_AUTHOR then return false, "cap" end
  store.nBy[clean.by] = (store.nBy[clean.by] or 0) + 1
  store.obs[id] = clean
  if lvKey then store.lvIdx[lvKey] = id end
  if clean.t == "cnt" and R.CNT_GUARDED[clean.k] and store.cntIdx and store.cntIdxOf == store.obs then
    local k = R.cntKey(clean)
    store.cntIdx[k] = store.cntIdx[k] or {}
    store.cntIdx[k][id] = true
  end
  if type(rxNow) == "number" then store.lastRx = math.max(store.lastRx or 0, rxNow) end
  return true, id
end

-- a LIVE level observation is only taken when dated inside [now-600, now+300] by the receiver's
-- clock, and never before the moment this receiver last saw the character at a lower level (roster cache).
-- seen = { lv = level, ts = when first seen at that level } or nil.
-- the window is measured from the SEND, not from the event. sentAt = the
-- sender's server time when the message left its queue (Comm stamps it); it must be within R.SENT_SKEW of our clock,
-- the event cannot be later than it, and it may have waited in the sender's queue up to R.MAX_DELAY (a long BG or
-- encounter). Older clients send no stamp: sentAt = now (receiver clock), so the delay bound still applies.
R.MAX_DELAY = 3 * 3600
R.SENT_SKEW = 300
function R.liveOk(ev, now, sentAt)
  if type(ev) ~= "table" or type(ev.ts) ~= "number" or type(now) ~= "number" then return false end
  local s = type(sentAt) == "number" and sentAt or now
  if s < now - R.SENT_SKEW or s > now + R.SENT_SKEW then return false end
  if type(sentAt) == "number" then
    if ev.ts > s then return false end
  elseif ev.ts > now + R.SENT_SKEW then return false end
  return s - ev.ts <= R.MAX_DELAY
end
function R.liveLevelOk(ev, now, seen, sentAt)
  if type(ev) ~= "table" or ev.t ~= "lv" or type(ev.ts) ~= "number" or type(now) ~= "number" then return false end
  if not R.liveOk(ev, now, sentAt) then return false end
  if type(seen) == "table" and type(seen.lv) == "number" and type(seen.ts) == "number"
     and seen.lv < (ev.lv or 0) and ev.ts < seen.ts then return false end
  return true
end

-- counters (HK, Overlord captures, professions, reputation) are guarded like levels.
--   * live only when dated inside [now-600, now+300] by the receiver's clock (relayed: GM/officer only, in Hall);
--   * monotonic per character + counter (+ key): a value lower than an earlier one (or higher than a later one)
--     is refused;
--   * plausible jumps: at most R.CNT_RATE[k] per 10 min between two readings (same timestamp = one reading, e.g. the
--     first sample after installing reports every step already crossed).
R.CNT_GUARDED = { hk = true, caps = true, prof = true, rep = true }
R.CNT_RATE = { hk = 200, prof = 60, rep = 1 }   -- prof 25 -> 60 per 10 min   -- caps: monotonic only (no rate limit)
R.RATE_WINDOW = 600
function R.liveCounterOk(ev, now, sentAt)
  if type(ev) ~= "table" or ev.t ~= "cnt" then return false end
  return R.liveOk(ev, now, sentAt)
end
local function jumpOk(k, lo, hi)   -- lo/hi = earlier/later reading { ts, n }
  local rate = R.CNT_RATE[k]
  if not rate or hi.ts == lo.ts then return true end
  local periods = max(1, (hi.ts - lo.ts) / R.RATE_WINDOW)
  return hi.n - lo.n <= rate * periods
end
R.jumpOk = jumpOk
-- returns true, or false + "decrease" | "sameTs" (checked against every stored reading of the same counter)
-- a jump is not refused here; R.compute leaves it "unverified" (not scored) until the
-- pace is plausible again. Two different values with the same ts (100/1000/5000 "first reading") are refused.
-- reporter|counter|key -> set of obs ids of guarded counter readings. Built lazily, kept up
-- to date by R.add, dropped by R.compact and rebuilt when store.obs is replaced. Stale ids are skipped by readers.
function R.cntKey(o) return o.by .. "|" .. o.k .. "|" .. (o.key or "") end
function R.cntIndex(store)
  if store.cntIdx and store.cntIdxOf == store.obs then return store.cntIdx end
  local idx = {}
  for oid, o in pairs(store.obs) do
    if o.t == "cnt" and R.CNT_GUARDED[o.k] then
      local k = R.cntKey(o)
      idx[k] = idx[k] or {}
      idx[k][oid] = true
    end
  end
  store.cntIdx, store.cntIdxOf = idx, store.obs
  return idx
end

function R.counterOk(store, ev)
  if type(ev) ~= "table" or ev.t ~= "cnt" or not R.CNT_GUARDED[ev.k] then return true end
  local key = ev.key or ""
  -- only the readings of this reporter + counter (+ key), via an index, not all of obs
  local bucket = R.cntIndex(store)[ev.by .. "|" .. ev.k .. "|" .. key]
  for oid in pairs(bucket or {}) do
    local o = store.obs[oid]
    if o and o.t == "cnt" and o.by == ev.by and o.k == ev.k and (o.key or "") == key then
      if o.ts == ev.ts then
        if o.n ~= ev.n then return false, "sameTs" end
      else
        local lo, hi = o, ev
        if o.ts > ev.ts then lo, hi = ev, o end
        if hi.n < lo.n then return false, "decrease" end
      end
    end
  end
  return true
end

-- readings that score. Per character + counter (+ key) the earliest reading is the
-- baseline (the value it had when it started reporting: never scored); a later reading scores only when it is not
-- `uv` and its jump from the last scoring reading (or the baseline) is plausible; otherwise it stays "unverified".
-- Returns set obs -> true, and the count of unverified readings.
function R.scoredCounters(list)
  local groups = {}
  for _, ev in ipairs(list) do
    if R.CNT_GUARDED[ev.k] then
      local g = ev.by .. "|" .. ev.k .. "|" .. (ev.key or "")
      groups[g] = groups[g] or {}
      table.insert(groups[g], ev)
    end
  end
  local scored, unv = {}, 0
  for _, l in pairs(groups) do
    table.sort(l, function(a, b) if a.ts ~= b.ts then return a.ts < b.ts end return a.n < b.n end)
    local ref = l[1]
    for i = 2, #l do
      local ev = l[i]
      if ev.ts > l[1].ts then
        if not ev.uv and ev.n >= ref.n and jumpOk(ev.k, ref, ev) then scored[ev] = true; ref = ev
        else unv = unv + 1 end
      end
    end
  end
  return scored, unv
end

-- SavedVariables have no `races` table: create it, keep everything else untouched (idempotent)
function R.migrate(db)
  if type(db) ~= "table" then return nil end
  local r = type(db.races) == "table" and db.races or {}
  r.obs = type(r.obs) == "table" and r.obs or {}
  r.closed = type(r.closed) == "table" and r.closed or {}
  r.hello = type(r.hello) == "table" and r.hello or {}
  r.seen = type(r.seen) == "table" and r.seen or {}       -- announced / toasted entries
  r.rcache = type(r.rcache) == "table" and r.rcache or {}   -- roster level cache (non-addon level races)
  r.rseen = type(r.rseen) == "table" and r.rseen or {}      -- name -> { lv, ts } when this client saw it
  r.ach = type(r.ach) == "table" and r.ach or { squad = {}, char = {}, guild = {} }
  r.ver = 6
  db.races = r
  return r
end

-- `sent` (steps already reported) and `hkBase` (lifetime HK at install) live
-- per character inside the guild: rdb.sent[name] = { "k|key|step|sea" = true }, rdb.hkBase[name] = number. An older
-- flat table is migrated: each step goes to the character that holds the matching observation in `obs`; a step
-- with no matching observation is dropped (that character reports it again: harmless). The flat hkBase goes to the
-- character with the earliest HK observation, or is dropped (counting starts again from now). Idempotent.
function R.migrateCharState(rdb)
  if type(rdb) ~= "table" then return nil end
  if rdb.charState == 2 then return rdb end
  local obs = type(rdb.obs) == "table" and rdb.obs or {}
  local flat = type(rdb.sent) == "table" and rdb.sent or {}
  local sent = {}
  for sk, v in pairs(flat) do
    if type(v) == "table" then sent[sk] = v                       -- already per character
    elseif v == true and type(sk) == "string" then
      local k, key, step, sea = sk:match("^([^|]*)|([^|]*)|([^|]*)|(.*)$")
      step = tonumber(step)
      local owner
      for _, o in pairs(obs) do
        if o.t == "cnt" and o.k == k and (o.key or "") == key and o.n == step and (o.sea or "") == sea
           and (not owner or o.by < owner) then owner = o.by end
      end
      if owner then sent[owner] = sent[owner] or {}; sent[owner][sk] = true end
    end
  end
  local base = {}
  if type(rdb.hkBase) == "table" then base = rdb.hkBase
  elseif type(rdb.hkBase) == "number" then
    local first
    for _, o in pairs(obs) do
      if o.t == "cnt" and o.k == "hk" and (not first or o.ts < first.ts or (o.ts == first.ts and o.by < first.by)) then first = o end
    end
    if first then base[first.by] = rdb.hkBase end
  end
  rdb.sent, rdb.hkBase, rdb.charState = sent, base, 2
  return rdb
end

-- ACK: own observations wait in `pend` (id -> ts) until a peer's hello shows it holds them (its
-- bucket hash equals ours for that observation's bucket) or until R.MAX_DELAY has passed. Returns the observations
-- to send again now (live, freshly stamped) and drops the acknowledged / expired ones.
function R.ackScan(pend, store, rh, now, cache)
  local resend = {}
  if type(pend) ~= "table" then return resend end
  local mine = type(rh) == "table" and R.bucketHashes(store, nil, cache) or nil
  local ids = {}
  for id in pairs(pend) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local ev, ts = store.obs[id], pend[id]
    if not ev or type(ts) ~= "number" or now - ts > R.MAX_DELAY then pend[id] = nil
    elseif mine and rh[R.bucketOf("o:" .. id)] == mine[R.bucketOf("o:" .. id)] then pend[id] = nil
    else resend[#resend + 1] = ev end
  end
  return resend
end

-------------------------------------------------------------------------------
-- race registry
function R.def(id, defs)
  local size, cat, season = 10, "other", nil
  if id:find("^lvl%.all%.") then size, cat = 100, "level"
  elseif id:find("^lvl%.class%.") then cat = "class"
  elseif id:find("^lvl%.race%.") then cat = "race"
  elseif id:find("^dng%.") then cat = "dungeon"
  elseif id:find("^raid%.") then cat = "raid"
  elseif id:find("^full%.") then size, cat = 3, "raid"
  elseif id:find("^pvp%.") or id:find("^wpvp%.") then cat = "pvp" end
  season = id:match("%.s([%w_]+)$")
  if not id:find("^pvp%.rank%.") then season = nil end
  local scope = "char"
  if id:find("^dng%.") or id:find("^raid%.") or id:find("^full%.") then scope = "group"
  elseif id:find("^pvp%.bg") or id:find("^squad%.") then scope = "squad" end
  if id == "dng.all" then scope = "squad" end
  local r = { id = id, size = size, cat = cat, season = season, scope = scope }
  -- the GM's catalog (achdef) gives the effective size, the visible label and the `off` mark;
  -- r.base = the family size, r.sizeTs = when the GM set the size (see R.place)
  local Cat = ns.Catalog
  if Cat and Cat.decorate then Cat.decorate(r, defs) end
  return r
end

local function sortedKeys(t) local o = {} for k in pairs(t) do o[#o + 1] = k end table.sort(o) return o end
local function setList(t) return sortedKeys(t) end

-- squads present in a kill/bg: sid -> { names set, n }
local function squadsIn(sqm)
  local out = {}
  for _, s in ipairs(sqm or {}) do
    local name, sid = s:match("^(.-)>(.+)$")
    if name and name ~= "" then
      local e = out[sid] or { names = {}, n = 0 }
      out[sid] = e
      if not e.names[name] then e.names[name] = true; e.n = e.n + 1 end
    end
  end
  return out
end

-- strong quorum = >= 2 reporters of DIFFERENT squads or groups (a reporter's
-- group = its own squad mark, or itself when it has none), or >= R.MIN_REPORTERS_ANY reporters. It confirms a boss
-- learned by a non-officer (catalog). Race entries keep the 2-reporter rule (two
-- members of one squad are an honest kill); backdating is stopped by the live window (`uv`).
R.MIN_REPORTERS_ANY = 3
function R.witnessesOk(evs)
  local groups, ng = {}, 0
  for _, ev in ipairs(evs) do
    local own = "solo:" .. ev.by
    for _, sm in ipairs(ev.sqm or {}) do
      local nm, sid = sm:match("^(.-)>(.+)$")
      if nm == ev.by then own = "sq:" .. sid end
    end
    if not groups[own] then groups[own] = true; ng = ng + 1 end
  end
  return #evs >= R.MIN_REPORTERS_ANY or (#evs >= R.MIN_WITNESSES and ng >= 2)
end

-- witnessed groups: list of { key, ts, first, names = set, sq = sid -> {names,n}, wit } ; pending: single reports
local function witnessed(list, now)
  local groups = {}
  for _, ev in ipairs(list) do
    local g = killKey(ev)
    groups[g] = groups[g] or {}
    table.insert(groups[g], ev)
  end
  local valid, pending = {}, {}
  for _, l in pairs(groups) do
    table.sort(l, function(a, b) if a.ts ~= b.ts then return a.ts < b.ts end return a.by < b.by end)
    local i = 1
    while i <= #l do
      local first = l[i]
      local rep, n, names, sqm, seenBy = {}, 0, {}, {}, {}
      local j = i
      local evs = {}
      while j <= #l and l[j].ts - first.ts <= R.KILL_WINDOW do
        local ev = l[j]
        if not rep[ev.by] then rep[ev.by] = true; n = n + 1; evs[#evs + 1] = ev end
        j = j + 1
      end
      -- a name counts when it is a reporter or listed in `pres` by >= 2 distinct reporters; a
      -- reporter only vouches for its OWN squad (the sid of its own "name>sid" mark), never for another squad.
      for _, ev in ipairs(evs) do
        local once = {}
        for _, p in ipairs(ev.pres or {}) do
          if not once[p] then once[p] = true; seenBy[p] = (seenBy[p] or 0) + 1 end
        end
      end
      for nm in pairs(rep) do names[nm] = true end
      for nm, c in pairs(seenBy) do if c >= 2 then names[nm] = true end end
      for _, ev in ipairs(evs) do
        local own
        for _, sm in ipairs(ev.sqm or {}) do
          local nm, sid = sm:match("^(.-)>(.+)$")
          if nm == ev.by then own = sid end
        end
        if own then
          for _, sm in ipairs(ev.sqm or {}) do
            local nm, sid = sm:match("^(.-)>(.+)$")
            if sid == own and names[nm] then sqm[#sqm + 1] = sm end
          end
        end
      end
      local k = { key = killKey(first), ts = first.ts, ev = first, names = names, sq = squadsIn(sqm), wit = n, rep = rep }
      k.strong = R.witnessesOk(evs)
      if n >= R.MIN_WITNESSES then valid[#valid + 1] = k
      elseif not now or now - first.ts < R.PENDING_TTL then pending[#pending + 1] = k end
      i = j
    end
  end
  table.sort(valid, function(a, b) if a.ts ~= b.ts then return a.ts < b.ts end return a.key < b.key end)
  return valid, pending
end
R.witnessed = witnessed

-- crediting -----------------------------------------------------------------
-- dungeon: the single squad with >= 3 members (most members, then sid) or a "mixed group"
local function dungeonCredit(k)
  local best, bn
  for sid, e in pairs(k.sq) do
    if e.n >= R.MIN_SQUAD and (not best or e.n > bn or (e.n == bn and sid < best)) then best, bn = sid, e.n end
  end
  local chars = setList(k.names)
  if best then return { key = "sq:" .. best, squads = { best }, chars = chars, sup = {} } end
  return { key = "mix:" .. table.concat(chars, ","), squads = {}, chars = chars, sup = {}, mixed = true }
end
-- raid boss: every squad with >= 3 members shares the entry; players outside those squads are "support"
local function allianceOf(sids, names, sqTable)
  table.sort(sids)
  local inSq = {}
  for _, sid in ipairs(sids) do for n in pairs((sqTable[sid] or { names = {} }).names) do inSq[n] = true end end
  local chars, sup = {}, {}
  for _, n in ipairs(setList(names)) do if inSq[n] then chars[#chars + 1] = n else sup[#sup + 1] = n end end
  if #sids == 0 then return { key = "mix:" .. table.concat(sup, ","), squads = {}, chars = sup, sup = {}, mixed = true } end
  return { key = "al:" .. table.concat(sids, "+"), squads = sids, chars = chars, sup = sup }
end
local function raidCredit(k)
  local sids = {}
  for sid, e in pairs(k.sq) do if e.n >= R.MIN_SQUAD then sids[#sids + 1] = sid end end
  return allianceOf(sids, k.names, k.sq)
end
R.dungeonCredit, R.raidCredit = dungeonCredit, raidCredit

-- §9.1: squads present (>= 3) in >= 70 % of the required kills of a run
function R.allianceCredit(run, required)
  local need = {}
  for _, b in ipairs(required) do need[b] = true end
  local att, names, sqAll = {}, {}, {}
  for _, k in ipairs(run) do
    if need[k.boss] then
      for sid, e in pairs(k.sq) do
        if e.n >= R.MIN_SQUAD then
          att[sid] = att[sid] or {}
          att[sid][k.boss] = true
          sqAll[sid] = sqAll[sid] or { names = {} }
          for n in pairs(e.names) do sqAll[sid].names[n] = true end
        end
      end
      for n in pairs(k.names) do names[n] = true end
    end
  end
  local sids = {}
  for sid, bosses in pairs(att) do
    local c = 0
    for _ in pairs(bosses) do c = c + 1 end
    if #required > 0 and c / #required >= R.ALLIANCE_SHARE then sids[#sids + 1] = sid end
  end
  return allianceOf(sids, names, sqAll)
end

-------------------------------------------------------------------------------
-- compute
-- ctx = { now, isFinal(instKey, bossSlug, bossName) -> bool, bossesOf(instKey) -> {slugs}, trusted(name) -> bool,
--         inGuild(name) -> bool, squads() -> { sid = {titulares} }, annul = { [race] = { [key] = {reason,by,ts} } },
--         nodata = { prof = true, rep = true, legacy = true }, season = "1", classes = {CLASS...} }
local function instOf(ev)
  local e = Content and Content.match(ev.inst, ev.it, ev.iid)
  local kind = (ev.it == "raid" or (e and e.kind == "raid")) and "raid" or "dungeon"
  local key = e and e.key or ("classic:" .. norm(ev.inst))
  return kind, slug(key:gsub("^classic:", "")), e
end
function R.instKey(ev) local kind, ik = instOf(ev); return ik, kind end
local function bossSlug(ev) return (ev.enc and ev.enc > 0) and tostring(ev.enc) or slug(ev.boss) end
R.bossSlug = bossSlug

local function copyCand(c)
  local o = {}
  for k, v in pairs(c) do o[k] = v end
  return o
end

function R.compute(store, ctx)
  ctx = ctx or {}
  local now = ctx.now or 0
  -- the GM's catalog (sizes, labels, off marks) and his custom races ("gm.*"), fed by the same observations
  local Cat = ns.Catalog
  local defs = ctx.achdefs or (Cat and Cat.defs()) or {}
  local cus = (Cat and Cat.customRaces(defs)) or { level = {}, boss = {}, bg = {}, prof = {}, rep = {}, all = {} }
  local races, info = {}, { lvTs = {}, lvSelf = {}, dngDone = {}, raidDone = {}, charDng = {}, charRaid = {}, rank = {},
                           killed = {} }
  local function race(id)
    local r = races[id]
    if not r then
      r = R.def(id, defs); r.cands = {}; r.pending = {}; r.history = {}; r.entries = {}
      races[id] = r
    end
    return r
  end
  local function cand(id, c) table.insert(race(id).cands, c) end
  local function nodata(id) race(id).nodata = true end
  -- races whose id comes from the data. Created only when the key is whitelisted or backed by
  -- >= 2 distinct reporters; at most R.MAX_DYN of them (sorted by id: deterministic).
  local dynC, dynBy, dynWhite = {}, {}, {}
  local function dyn(id, c, reporters, white)
    dynC[id] = dynC[id] or {}
    table.insert(dynC[id], c)
    dynBy[id] = dynBy[id] or {}
    for nm in pairs(reporters) do dynBy[id][nm] = true end
    if white then dynWhite[id] = true end
  end
  local function one(nm) return { [nm] = true } end

  local byType = { lv = {}, kill = {}, bg = {}, cnt = {} }
  for _, ev in pairs(store.obs) do
    if ev.uv and ev.t ~= "cnt" then info.unverified = (info.unverified or 0) + 1   -- never scored
    else table.insert(byType[ev.t], ev) end
  end
  local cntScored, cntUnv = R.scoredCounters(byType.cnt)
  info.unverified = (info.unverified or 0) + cntUnv

  -- levels: self + roster confirmation (exact) or >= 2 roster observers within 10 min (approx.)
  local lg = {}
  for _, ev in ipairs(byType.lv) do
    local g = ev.who .. "#" .. ev.lv
    lg[g] = lg[g] or {}
    table.insert(lg[g], ev)
  end
  for _, l in pairs(lg) do
    table.sort(l, function(a, b) if a.ts ~= b.ts then return a.ts < b.ts end return a.by < b.by end)
    local self, rost, cls, rc = nil, {}, nil, nil
    for _, ev in ipairs(l) do
      if ev.src == "self" then self = self or ev else rost[#rost + 1] = ev end
      cls = cls or ev.cls; rc = rc or ev.race
    end
    if self then cls, rc = self.cls or cls, self.race or rc end
    local ts, mark
    if self then
      -- the roster witness must confirm the same level INSIDE the window, on both sides
      for _, r in ipairs(rost) do
        if r.by ~= self.who and math.abs(r.ts - self.ts) <= R.LEVEL_WINDOW then ts, mark = self.ts, "exact"; break end
      end
    end
    if not ts then
      for i = 1, #rost do
        for j = i + 1, #rost do
          if rost[j].by ~= rost[i].by and rost[j].ts - rost[i].ts <= R.LEVEL_WINDOW then ts, mark = rost[i].ts, "approx"; break end
        end
        if ts then break end
      end
    end
    if not ts and ctx.trusted then
      for _, r in ipairs(rost) do if ctx.trusted(r.by) then ts, mark = r.ts, "approx"; break end end
    end
    local who, lv = l[1].who, l[1].lv
    if self then info.lvSelf[who] = info.lvSelf[who] or {}; info.lvSelf[who][lv] = self.ts end
    if ts then
      info.lvTs[who] = info.lvTs[who] or {}
      info.lvTs[who][lv] = ts
      local c = function() return { key = who, ts = ts, mark = mark, chars = { who }, squads = {}, sup = {}, name = who } end
      local milestone = false
      for _, h in ipairs(R.LEVELS) do if h == lv then milestone = true end end
      if milestone then
        cand("lvl.all." .. lv, c())
        local reps = {}   -- reporters that actually sent this race key
        for _, ev in ipairs(l) do if ev.race and rc and slug(ev.race):upper() == slug(rc):upper() then reps[ev.by] = true end end
        local cu, ru = cls and slug(cls):upper(), rc and slug(rc):upper()
        if cu and R.CLASS_OK[cu] then cand("lvl.class." .. cu .. "." .. lv, c()) end
        if ru then dyn("lvl.race." .. ru .. "." .. lv, c(), reps, R.RACE_OK[ru]) end
      end
      for _, cu in ipairs(cus.level[lv] or {}) do   -- custom level races (same witness rule)
        if Cat.levelMatch(cu, cls, rc) then cand(cu.id, c()) end
      end
    end
  end
  for _, h in ipairs(R.LEVELS) do race("lvl.all." .. h) end
  for _, cls in ipairs(ctx.classes or {}) do for _, h in ipairs(R.LEVELS) do race("lvl.class." .. cls .. "." .. h) end end

  -- PvE kills
  local valid, pending = witnessed(byType.kill, now)
  local runs = {} -- raid instKey -> list of kills (with .boss slug)
  for _, k in ipairs(valid) do
    local kind, ik = instOf(k.ev)
    k.boss, k.ik, k.kind = bossSlug(k.ev), ik, kind
    local final = ctx.isFinal and ctx.isFinal(ik, k.boss, k.ev.boss) or false
    local c = kind == "raid" and raidCredit(k) or dungeonCredit(k)
    c.ts, c.mark, c.wit, c.name = k.ts, "wit", k.wit, c.key
    local pre = kind == "raid" and "raid." or "dng."
    dyn(pre .. ik .. "." .. k.boss, c, k.rep, false)
    for _, cu in ipairs(cus.boss[ik .. "." .. k.boss] or {}) do cand(cu.id, copyCand(c)) end   -- >= 2 witnesses
    if k.strong then info.killed[ik .. "." .. k.boss] = true end   -- catalog quorum
    for n in pairs(k.names) do
      local t = kind == "raid" and info.charRaid or info.charDng
      t[n] = t[n] or {}
      if kind == "raid" then t[n][ik] = t[n][ik] or k.ts end
    end
    if kind == "raid" then runs[ik] = runs[ik] or {}; table.insert(runs[ik], k) end
    if final then
      if kind == "dungeon" then
        local d = dungeonCredit(k)
        d.ts, d.mark, d.wit, d.name = k.ts, "wit", k.wit, d.key
        cand("dng." .. ik, d)
        for _, sid in ipairs(d.squads) do
          info.dngDone[sid] = info.dngDone[sid] or {}
          info.dngDone[sid][ik] = info.dngDone[sid][ik] or k.ts
        end
        for n in pairs(k.names) do info.charDng[n][ik] = info.charDng[n][ik] or k.ts end
      else
        local run = {}
        for _, rk in ipairs(runs[ik]) do if rk.ts >= k.ts - R.RUN_WINDOW then run[#run + 1] = rk end end
        local req = ctx.bossesOf and ctx.bossesOf(ik) or {}
        if #req == 0 then
          local seen = {}
          for _, rk in ipairs(run) do if not seen[rk.boss] then seen[rk.boss] = true; req[#req + 1] = rk.boss end end
        end
        local a = R.allianceCredit(run, req)
        a.ts, a.mark, a.wit, a.name = k.ts, "wit", k.wit, a.key
        cand("raid." .. ik, a)
        for _, sid in ipairs(a.squads) do
          info.raidDone[sid] = info.raidDone[sid] or {}
          info.raidDone[sid][ik] = info.raidDone[sid][ik] or k.ts
        end
      end
    end
  end
  -- single reports never create a race: they are only listed under a race that already exists
  local pendingBy = {}
  for _, k in ipairs(pending) do
    local kind, ik = instOf(k.ev)
    local id = (kind == "raid" and "raid." or "dng.") .. ik .. "." .. bossSlug(k.ev)
    pendingBy[#pendingBy + 1] = { id = id, p = { ts = k.ts, by = k.ev.by, chars = setList(k.names) } }
  end
  -- completion races of the catalog (pending data while the final boss is unknown)
  local hasFinal = ctx.hasFinal or function() return false end
  local dKeys, rDefs = {}, {}
  if Content then
    for _, e in ipairs(Content.DUNGEONS) do dKeys[#dKeys + 1] = e.key end
    for _, e in ipairs(Content.RAIDS) do rDefs[#rDefs + 1] = e end
  end
  for _, k in ipairs(dKeys) do local r = race("dng." .. k); if not hasFinal(k) then r.nodata = true end end
  for _, e in ipairs(rDefs) do local r = race("raid." .. e.key); if not hasFinal(e.key) then r.nodata = true end end
  -- aggregates: per squad completion time = latest of the required contents; equal times share a position
  local function aggregate(id, keysD, keysR)
    local r = race(id)
    for _, k in ipairs(keysD) do if not hasFinal(k) then r.nodata = true end end
    for _, k in ipairs(keysR) do if not hasFinal(k) then r.nodata = true end end
    if r.nodata then return end
    local done = {}
    local sids = {}
    for sid in pairs(info.dngDone) do sids[sid] = true end
    for sid in pairs(info.raidDone) do sids[sid] = true end
    for sid in pairs(sids) do
      local last, okAll = 0, true
      for _, k in ipairs(keysD) do local t = (info.dngDone[sid] or {})[k]; if not t then okAll = false else last = max(last, t) end end
      for _, k in ipairs(keysR) do local t = (info.raidDone[sid] or {})[k]; if not t then okAll = false else last = max(last, t) end end
      if okAll then done[last] = done[last] or {}; table.insert(done[last], sid) end
    end
    for ts, list in pairs(done) do
      table.sort(list)
      cand(id, { key = (#list > 1 and "al:" or "sq:") .. table.concat(list, "+"), ts = ts, mark = "wit", squads = list,
                 chars = {}, sup = {}, name = table.concat(list, "+") })
    end
  end
  local r10, r20, rAll = {}, {}, {}
  for _, e in ipairs(rDefs) do
    rAll[#rAll + 1] = e.key
    if e.size == 10 then r10[#r10 + 1] = e.key elseif e.size == 20 then r20[#r20 + 1] = e.key end
  end
  aggregate("dng.all", dKeys, {})
  aggregate("raid.all", {}, rAll)
  aggregate("full.10", dKeys, r10)
  aggregate("full.20", dKeys, r20)

  -- battlegrounds: witnessed wins, squads with >= 2 members present
  local bgs = witnessed(byType.bg, now)
  local wins, cwins = {}, {}
  for _, k in ipairs(bgs) do
    if k.ev.win == 1 then
      for sid, e in pairs(k.sq) do
        if e.n >= R.BG_TOGETHER then
          wins[sid] = (wins[sid] or 0) + 1
          local c = function() return { key = "sq:" .. sid, ts = k.ts, mark = "wit", squads = { sid }, chars = setList(e.names), sup = {}, wit = k.wit, name = sid } end
          for _, n in ipairs(R.BG_STEPS) do if wins[sid] == n then cand("pvp.bg." .. n, c()) end end
          dyn("pvp.bgmap." .. slug(k.ev.inst), c(), k.rep, false)
          for _, cu in ipairs(cus.bg) do   -- N squad wins, overall or on one map
            if cu.param == "" or cu.param == slug(k.ev.inst) then
              cwins[cu.id] = cwins[cu.id] or {}
              cwins[cu.id][sid] = (cwins[cu.id][sid] or 0) + 1
              if cwins[cu.id][sid] == cu.thr then cand(cu.id, c()) end
            end
          end
        end
      end
    end
  end
  for _, n in ipairs(R.BG_STEPS) do race("pvp.bg." .. n) end

  -- counters (self-reported)
  for _, ev in ipairs(byType.cnt) do
    if R.CNT_GUARDED[ev.k] and not cntScored[ev] then ev = nil end
    if ev then
    local function c() return { key = ev.who, ts = ev.ts, mark = "self", chars = { ev.who }, squads = {}, sup = {}, name = ev.who } end
    if ev.k == "hk" then for _, n in ipairs(R.HK_STEPS) do if ev.n >= n then cand("pvp.hk." .. n, c()) end end
    elseif ev.k == "caps" then for _, n in ipairs(R.CAPS_STEPS) do if ev.n >= n then cand("wpvp.caps." .. n, c()) end end
    elseif ev.k == "legacy" then for _, n in ipairs(R.LEGACY_STEPS) do if ev.n >= n then cand("legacy." .. n, c()) end end
    elseif ev.k == "prof" then
      local sk = slug(ev.key)
      for _, n in ipairs(R.PROF_STEPS) do if ev.n >= n then dyn("prof." .. sk .. "." .. n, c(), one(ev.by), R.PROF_OK[sk]) end end
      for _, cu in ipairs(cus.prof[sk] or {}) do if ev.n >= cu.thr then cand(cu.id, c()) end end
    elseif ev.k == "rep" then
      local sk = slug(ev.key)
      if ev.n >= R.EXALTED then dyn("rep." .. sk .. ".exalted", c(), one(ev.by), R.REP_OK[sk]) end
      for _, cu in ipairs(cus.rep[sk] or {}) do if ev.n >= cu.thr then cand(cu.id, c()) end end
    elseif ev.k == "pvprank" then
      local sea = slug(ev.sea or "1")
      info.rank[ev.who] = info.rank[ev.who] or {}
      if (info.rank[ev.who][sea] or 0) < ev.n then info.rank[ev.who][sea] = ev.n end
      for _, n in ipairs(R.PVP_RANKS) do
        if ev.n >= n then
          cand("pvp.rank." .. n .. ".s" .. sea, c())
          local cu = ev.cls and slug(ev.cls):upper()
          if n == 14 and cu and R.CLASS_OK[cu] then cand("pvp.rank.class." .. cu .. ".14.s" .. sea, c()) end
        end
      end
    end
    end
  end
  for _, n in ipairs(R.HK_STEPS) do race("pvp.hk." .. n) end
  for _, n in ipairs(R.CAPS_STEPS) do race("wpvp.caps." .. n) end
  for _, n in ipairs(R.PVP_RANKS) do race("pvp.rank." .. n .. ".s" .. slug(ctx.season or "1")) end
  local nd = ctx.nodata or {}
  if nd.legacy then for _, n in ipairs(R.LEGACY_STEPS) do nodata("legacy." .. n) end end
  if nd.prof then nodata("prof.*") end
  if nd.rep then nodata("rep.*") end
  -- every custom race exists (open n/N) from its definition; without the API it is "pending data"
  for _, cu in ipairs(cus.all) do
    race(cu.id)
    if (cu.metric == "prof" and nd.prof) or (cu.metric == "rep" and nd.rep) then nodata(cu.id) end
  end

  -- squad.full60: the 5 titulares at 60 (time = the last of them)
  if ctx.squads then
    for sid, mem in pairs(ctx.squads() or {}) do
      if #mem >= 5 then
        local last, all = 0, true
        for i = 1, 5 do local t = (info.lvTs[mem[i]] or {})[60]; if not t then all = false else last = max(last, t) end end
        if all then cand("squad.full60", { key = "sq:" .. sid, ts = last, mark = "approx", squads = { sid }, chars = {}, sup = {}, name = sid }) end
      end
    end
  end
  race("squad.full60")

  -- races created on the fly: whitelisted or >= 2 reporters, at most R.MAX_DYN (sorted ids)
  local made = 0
  for _, id in ipairs(sortedKeys(dynC)) do
    local nrep = 0
    for _ in pairs(dynBy[id]) do nrep = nrep + 1 end
    if (dynWhite[id] or nrep >= R.MIN_REPORTERS) and (races[id] or made < R.MAX_DYN) then
      if not races[id] then made = made + 1 end
      for _, c in ipairs(dynC[id]) do cand(id, c) end
    end
  end
  for _, p in ipairs(pendingBy) do if races[p.id] then table.insert(races[p.id].pending, p.p) end end

  -- order, unique competitors, annulments, closed races
  for id, r in pairs(races) do R.place(store, r, ctx) end
  return races, info
end

local function candLess(a, b)
  if a.ts ~= b.ts then return a.ts < b.ts end
  -- always by key (BG / full60 candidates used name = sid, frozen rows name = key)
  return tostring(a.key) < tostring(b.key)
end

-- one entry per competitor; for shared entries, squads already placed are removed (all placed = skipped)
local function admit(r, c, usedKey, usedSq)
  if usedKey[c.key] then return nil end
  if #(c.squads or {}) > 0 then
    local left = {}
    for _, sid in ipairs(c.squads) do if not usedSq[sid] then left[#left + 1] = sid end end
    if #left == 0 then return nil end
    if #left ~= #c.squads then
      c = { key = (#left > 1 and "al:" or "sq:") .. table.concat(left, "+"), ts = c.ts, mark = c.mark, squads = left,
            chars = c.chars, sup = c.sup, wit = c.wit, name = c.name }
      if usedKey[c.key] then return nil end
    end
  end
  return c
end

-- the placement loop: one entry per competitor up to `size`, annulled candidates go to the history
local function runPlace(r, size, annul)
  local usedKey, usedSq, out, hist = {}, {}, {}, {}
  local function use(c)
    usedKey[c.key] = true
    for _, sid in ipairs(c.squads or {}) do usedSq[sid] = true end
  end
  for _, c in ipairs(r.cands) do
    if #out >= size then break end
    if annul[c.key] and not usedKey[c.key] then
      use(c)
      hist[#hist + 1] = { key = c.key, ts = c.ts, chars = c.chars, squads = c.squads, reason = annul[c.key].reason,
                          by = annul[c.key].by, at = annul[c.key].ts }
    else
      local a = admit(r, c, usedKey, usedSq)
      if a then use(a); out[#out + 1] = a end
    end
  end
  return out, hist
end

-- size set by the GM (achdef). Deterministic from the data, on every client:
--   * a frozen (closed) Top keeps its size: #rows (closed = immutable);
--   * a race that was already full with its family size when the GM set the new size (sizeTs) keeps the old size;
--   * otherwise the new size, but never below the entries it already had at sizeTs.
function R.effectiveSize(r, frozen, annul)
  if frozen then return #frozen.rows end
  if not r.sizeTs then return r.size end
  local base = r.base or r.size
  if not r.custom then
    if r.size == base then return base end
    local out0 = runPlace(r, base, annul)
    if #out0 >= base and out0[#out0].ts <= r.sizeTs then return base end
  end
  local probe = runPlace(r, math.max(base, r.size), annul)
  local n0 = 0
  for _, e in ipairs(probe) do if e.ts <= r.sizeTs then n0 = n0 + 1 end end
  return math.min(math.max(r.size, n0), math.max(base, r.size))
end

function R.place(store, r, ctx)
  local annul = (ctx and ctx.annul and ctx.annul[r.id]) or {}
  table.sort(r.cands, candLess)
  -- the stored closed Top is not authoritative over the observations we hold. Its rows are merged
  -- with the candidates and the Top is recomputed deterministically (same data -> same Top, whatever the order
  -- it arrived in); the rows only matter for observations already compacted away.
  local frozen = store and store.closed and store.closed[r.id]
  if frozen then
    for _, row in ipairs(frozen.rows) do
      r.cands[#r.cands + 1] = { key = row.key, ts = row.ts, mark = row.mark, chars = row.chars, squads = row.squads,
                                sup = row.sup, wit = row.wit, name = row.key }
    end
    table.sort(r.cands, candLess)
  end
  r.size = R.effectiveSize(r, frozen, annul)
  local out, hist = runPlace(r, r.size, annul)
  for _, h in ipairs(hist) do r.history[#r.history + 1] = h end
  for i, e in ipairs(out) do
    e.pos = i
    if ctx and ctx.inGuild and #(e.squads or {}) == 0 and e.chars and #e.chars == 1 and not ctx.inGuild(e.chars[1]) then e.ex = true end
  end
  r.entries = out
  r.cands = nil
  if r.nodata and #out == 0 then r.state = "nodata"
  elseif #out >= r.size then r.state = "closed" else r.state = "open" end
  -- freeze (snapshot for compaction / peers) only when the data is quiet: not during the initial sync and not
  -- before R.QUIET seconds after the last observation received
  local quiet = not (ctx and ctx.syncing) and not (store and store.lastRx and ctx and ctx.now and ctx.now - store.lastRx < R.QUIET)
  if r.state == "closed" and quiet and store and store.closed then
    local rows = {}
    for i, e in ipairs(out) do rows[i] = { key = e.key, ts = e.ts, mark = e.mark, chars = e.chars, squads = e.squads, sup = e.sup, wit = e.wit } end
    store.closed[r.id] = { rows = rows, at = (ctx and ctx.now) or 0 }
  end
  return r
end

-- races of a filter category, sorted by id
-- races disabled by the GM are hidden here (they keep counting); R.legacyList gives the
-- disabled ones that already have entries ("Legado")
function R.list(races, cat)
  local out = {}
  for id, r in pairs(races) do if (not cat or r.cat == cat) and not r.off then out[#out + 1] = r end end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end
function R.legacyList(races, cat)
  local out = {}
  for id, r in pairs(races) do
    if (not cat or r.cat == cat) and r.off and #(r.entries or {}) > 0 then out[#out + 1] = r end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

-------------------------------------------------------------------------------
-- annulment (GM only, mandatory reason): validated record -> ctx.annul map
-- rec = { race, key, reason } authored by `by`. Returns ok, why.
function R.validAnnul(d, by, isGM)
  if type(d) ~= "table" or type(d.race) ~= "string" or type(d.key) ~= "string" then return false, "shape" end
  if type(d.reason) ~= "string" or d.reason:gsub("%s", "") == "" then return false, "reason" end
  if not isGM(by) then return false, "denied" end
  return true
end
function R.annulMap(records)
  local out = {}
  for _, rec in pairs(records or {}) do
    local d = rec.d
    if d and d.on ~= false then
      out[d.race] = out[d.race] or {}
      out[d.race][d.key] = { reason = d.reason, by = rec.a, ts = rec.ts }
    end
  end
  return out
end

-- achievements derived from race entries (an annulment, or reverting one, changes them). After merging,
-- a derived achievement that the current races no longer give is retracted. Returns the removed { scope, owner, key }.
function R.raceDerivedAch(key)
  return key == "hallOfFame" or key == "top10class" or key == "top10race" or key == "first1"
         or (type(key) == "string" and key:find("^top100%.") ~= nil)
end
function R.retractAchievements(known, fresh)
  local removed = {}
  for _, scope in ipairs({ "squad", "char" }) do
    for owner, keys in pairs(known and known[scope] or {}) do
      for key in pairs(keys) do
        if R.raceDerivedAch(key) and not (fresh and fresh[scope] and fresh[scope][owner] and fresh[scope][owner][key]) then
          removed[#removed + 1] = { scope = scope, owner = owner, key = key }
        end
      end
    end
  end
  for _, r in ipairs(removed) do known[r.scope][r.owner][r.key] = nil end
  return removed
end

-------------------------------------------------------------------------------
-- compaction: observations that only feed closed races are dropped (the frozen row keeps the result)
local function feeds(ev)
  local out = {}
  if ev.t == "lv" then
    out[#out + 1] = "lvl.all." .. ev.lv
    if ev.cls then out[#out + 1] = "lvl.class." .. slug(ev.cls):upper() .. "." .. ev.lv end
    if ev.race then out[#out + 1] = "lvl.race." .. slug(ev.race):upper() .. "." .. ev.lv end
    if ev.lv == 60 then return nil end -- also feeds squad.full60 / achievements: keep
  elseif ev.t == "cnt" and (ev.k == "hk" or ev.k == "caps") then
    local steps = ev.k == "hk" and R.HK_STEPS or R.CAPS_STEPS
    for _, n in ipairs(steps) do if ev.n >= n then out[#out + 1] = (ev.k == "hk" and "pvp.hk." or "wpvp.caps.") .. n end end
    if #out < #steps then return nil end -- still below a threshold: may feed an open race later
  else return nil end
  return out
end
function R.compact(store, defs)
  local dropped = 0
  -- a level that feeds a custom race of the GM is kept (its race may still be open)
  local Cat = ns.Catalog
  local cl = Cat and Cat.customRaces(defs or Cat.defs()).level or {}
  for id, ev in pairs(store.obs) do
    local list = feeds(ev)
    if list and ev.t == "lv" and cl[ev.lv] then list = nil end
    if list and #list > 0 then
      local all = true
      for _, rid in ipairs(list) do if not store.closed[rid] then all = false; break end end
      if all then store.obs[id] = nil; dropped = dropped + 1 end
    end
  end
  store.nBy = nil
  store.lvIdx = nil
  store.cntIdx = nil
  return dropped
end

-- closed race as one compact row: "key~ts~mark~chars~squads~sup~wit;..." (names never contain ~ ; , +)
function R.packClosed(c)
  local parts = {}
  for _, row in ipairs(c.rows) do
    parts[#parts + 1] = table.concat({ row.key, tostring(row.ts), row.mark or "", table.concat(row.chars or {}, ","),
      table.concat(row.squads or {}, "+"), table.concat(row.sup or {}, ","), tostring(row.wit or 0) }, "~")
  end
  return table.concat(parts, ";")
end
local function split(s, sep)
  local out = {}
  if s == "" then return out end
  for p in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = p end
  return out
end
function R.unpackClosed(text)
  if type(text) ~= "string" or #text > 20000 then return nil end
  local rows = {}
  for _, part in ipairs(split(text, ";")) do
    local f = split(part, "~")
    if #f < 7 or not tonumber(f[2]) then return nil end
    rows[#rows + 1] = { key = f[1], ts = tonumber(f[2]), mark = f[3] ~= "" and f[3] or nil, chars = split(f[4], ","),
                        squads = split(f[5], "+"), sup = split(f[6], ","), wit = tonumber(f[7]) }
    if #rows > 100 then return nil end
  end
  return { rows = rows }
end
-- a closed race received from a peer is only taken when we have none (closed = immutable)
-- `size` is the effective one (the GM's achdef when valid, R.def); defs optional (default: the catalog in use)
function R.importClosed(store, id, text, at, defs)
  if type(id) ~= "string" or store.closed[id] then return false end
  local c = R.unpackClosed(text)
  -- a closed Top must be complete (exactly `size` rows) with non-decreasing dates
  if not c or #c.rows ~= R.def(id, defs).size then return false end
  for i = 2, #c.rows do if c.rows[i].ts < c.rows[i - 1].ts then return false end end
  c.at = at or 0
  store.closed[id] = c
  return true
end

-------------------------------------------------------------------------------
-- paginated sync: bucket hashes of observations + closed races; a peer replies with the items of the
-- differing buckets, `size` items per page (the caller sends one page per message / timer tick)
R.NBUCKETS = 16
local function bucketOf(id, nb)
  local h = 0
  for i = 1, #id do h = (h * 31 + id:byte(i)) % 65521 end
  return (h % nb) + 1
end
local function items(store)
  local out = {}
  for id, ev in pairs(store.obs) do out[#out + 1] = { id = "o:" .. id, o = ev } end
  for id, c in pairs(store.closed) do
    local text = R.packClosed(c)
    out[#out + 1] = { id = "c:" .. id .. "@" .. (ns.Serialize and ns.Serialize.hash(text):sub(1, 6) or tostring(#text)), c = id, text = text }
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end
R.itemsOf = items
function R.bucketOf(id, nb) return bucketOf(id, nb or R.NBUCKETS) end   -- build once per hello and pass it to bucketHashes / diffPage
function R.bucketHashes(store, nb, cache)
  nb = nb or R.NBUCKETS
  local lists = {}
  for i = 1, nb do lists[i] = {} end
  for _, it in ipairs(cache or items(store)) do table.insert(lists[bucketOf(it.id, nb)], it.id) end
  local out = {}
  for i = 1, nb do
    out[i] = #lists[i] == 0 and "0" or (ns.Serialize and ns.Serialize.hash(table.concat(lists[i], ",")):sub(1, 6) or tostring(#lists[i]))
  end
  return out
end
-- returns page items ({o=obs} or {c=id, text}), more = true when another page follows
-- filter(it) -> bool (optional: e.g. only my own observations); cache = R.itemsOf(store) (optional)
function R.diffPage(store, remote, page, size, nb, filter, cache)
  nb, size, page = nb or R.NBUCKETS, size or 20, page or 1
  cache = cache or items(store)
  local mine = R.bucketHashes(store, nb, cache)
  local list = {}
  for _, it in ipairs(cache) do
    local b = bucketOf(it.id, nb)
    if (type(remote) ~= "table" or remote[b] ~= mine[b]) and (not filter or filter(it)) then list[#list + 1] = it end
  end
  local out = {}
  for i = (page - 1) * size + 1, min(#list, page * size) do out[#out + 1] = list[i] end
  return out, #list > page * size, #list
end

-------------------------------------------------------------------------------
-- adoption: "Guild Squads instalado: X/Y miembros activos" (hellos of the last 14 days)
-- members = { { name, days = days offline (0 = online / unknown) } }, hello = { name -> last hello ts }
function R.adoption(members, hello, now, days)
  days = days or R.ADOPT_DAYS
  local x, y = 0, 0
  for _, m in ipairs(members or {}) do
    if (m.days or 0) <= days then
      y = y + 1
      local h = hello and hello[m.name]
      if m.self or (type(h) == "number" and now - h <= days * 86400) then x = x + 1 end
    end
  end
  return x, y
end

-------------------------------------------------------------------------------
-- achievements (dated) + progress. ctx = { now, squads() -> {sid = titulares}, classOf(name), roleOf(name),
-- wipeStats = { [sid] = { allCapped = ts|nil, streak = n, streakTs = ts } }, adoption = {x, y} }
R.SQUAD_ACH = { "allRoles", "allClasses", "wipeTopAll", "wipes4", "hallOfFame" }
R.CHAR_ACH = { "top10class", "top10race", "first1", "dungeonsAll", "raider" }
local function setAch(t, owner, key, ts)
  t[owner] = t[owner] or {}
  if not t[owner][key] or ts < t[owner][key] then t[owner][key] = ts end
end
function R.achievements(races, info, ctx)
  ctx = ctx or {}
  local now = ctx.now or 0
  local out = { squad = {}, char = {}, guild = {} }
  local prog = { squad = {}, char = {}, guild = {} }
  local function put(scope, owner, key, cur, need, unit)
    prog[scope][owner] = prog[scope][owner] or {}
    prog[scope][owner][key] = { cur = min(cur, need), need = need, unit = unit }
  end
  -- squad composition
  for sid, mem in pairs(ctx.squads and ctx.squads() or {}) do
    local roles, classes, nc = { TANK = 0, HEALER = 0, DAMAGER = 0 }, {}, 0
    for i = 1, min(#mem, 5) do
      local r = ctx.roleOf and ctx.roleOf(mem[i])
      if r and roles[r] then roles[r] = roles[r] + 1 end
      local c = ctx.classOf and ctx.classOf(mem[i])
      if c and not classes[c] then classes[c] = true; nc = nc + 1 end
    end
    if #mem >= 5 and roles.TANK == 1 and roles.HEALER == 1 and roles.DAMAGER == 3 then setAch(out.squad, sid, "allRoles", now) end
    if nc >= 5 then setAch(out.squad, sid, "allClasses", now) end
    put("squad", sid, "allClasses", nc, 5, "class")
    local ws = ctx.wipeStats and ctx.wipeStats[sid]
    if ws then
      if ws.allCapped then setAch(out.squad, sid, "wipeTopAll", ws.allCapped) end
      put("squad", sid, "wipeTopAll", ws.capped or (ws.allCapped and 5 or 0), 5, "cat")
      if (ws.streak or 0) >= 4 then setAch(out.squad, sid, "wipes4", ws.streakTs or now) end
      put("squad", sid, "wipes4", ws.streak or 0, 4, "wipe")
    end
  end
  -- hall of fame / char positions
  for id, r in pairs(races or {}) do
    for _, e in ipairs(r.entries or {}) do
      if r.size <= 10 then for _, sid in ipairs(e.squads or {}) do setAch(out.squad, sid, "hallOfFame", e.ts) end end
      if r.scope == "char" and #(e.chars or {}) == 1 then
        local who = e.chars[1]
        local h = id:match("^lvl%.all%.(%d+)$")
        if h then setAch(out.char, who, "top100." .. h, e.ts) end
        if id:find("^lvl%.class%.") then setAch(out.char, who, "top10class", e.ts) end
        if id:find("^lvl%.race%.") then setAch(out.char, who, "top10race", e.ts) end
        if e.pos == 1 then setAch(out.char, who, "first1", e.ts) end
      elseif e.pos == 1 then
        for _, who in ipairs(e.chars or {}) do setAch(out.char, who, "first1", e.ts) end
      end
    end
  end
  info = info or {}
  -- levels reached with the addon (self reports)
  for who, lvs in pairs(info.lvSelf or {}) do
    for lv, ts in pairs(lvs) do setAch(out.char, who, "lvl" .. lv, ts) end
  end
  -- Explorador de Forever (9 dungeons completed, any group) and Raider (a boss of every open raid)
  local nd = Content and #Content.DUNGEONS or 9
  for who, d in pairs(info.charDng or {}) do
    local c, last = 0, 0
    for _, ts in pairs(d) do c = c + 1; last = max(last, ts) end
    if c >= nd then setAch(out.char, who, "dungeonsAll", last) end
    put("char", who, "dungeonsAll", c, nd, "dungeon")
  end
  local nr = Content and #Content.RAIDS or 3
  for who, d in pairs(info.charRaid or {}) do
    local c, last = 0, 0
    for _, ts in pairs(d) do c = c + 1; last = max(last, ts) end
    if c >= nr then setAch(out.char, who, "raider", last) end
    put("char", who, "raider", c, nr, "raid")
  end
  for who, seas in pairs(info.rank or {}) do
    for _, rank in pairs(seas) do
      for _, n in ipairs(R.PVP_RANKS) do if rank >= n then setAch(out.char, who, "pvpRank" .. n, now) end end
    end
  end
  -- guild: "Toda la guild a bordo" (80 % of the active members with the addon)
  local ad = ctx.adoption
  if ad and ad.y and ad.y > 0 then
    if ad.x / ad.y >= R.ADOPT_GOAL then setAch(out.guild, "guild", "allAboard", now) end
    put("guild", "guild", "allAboard", ad.x, math.max(1, math.ceil(ad.y * R.ADOPT_GOAL)), "member")
  end
  return out, prog
end

-- wipe stats for wipeTopAll / wipes4 from the wipe scoring (closed wipes oldest first)
-- results = { { wipe = id, ends = ts, res = Pr.compute(...) } }, ranking = Pr.ranking
function R.wipeStats(results, ranking, cats, cap)
  local out = {}
  for _, w in ipairs(results) do
    for sid, r in pairs(w.res.squads or {}) do
      local s = out[sid] or { streak = 0, best = 0, capped = 0 }
      out[sid] = s
      local n = 0
      for _, c in ipairs(cats) do if (r[c] or 0) >= cap then n = n + 1 end end
      s.capped = max(s.capped, n)
      if n >= #cats and not s.allCapped then s.allCapped = w.ends end
    end
    local top = {}
    for _, e in ipairs(ranking(w.res, "general")) do if e.pos <= 3 and (e.points or 0) > 0 then top[e.sid] = true end end
    for sid, s in pairs(out) do
      if top[sid] then s.streak = s.streak + 1; if s.streak >= 4 and not s.streakTs then s.streakTs = w.ends end
      elseif not s.streakTs then s.streak = 0 end
    end
    for sid in pairs(top) do if not out[sid] then out[sid] = { streak = 1, capped = 0 } end end
  end
  return out
end

-- plain-text Top for Discord (no links, no colour codes)
function R.exportText(r, title, label)
  local lines = { "**" .. (title or r.id) .. "**" }
  for _, e in ipairs(r.entries or {}) do
    lines[#lines + 1] = ("%d. %s"):format(e.pos, label and label(e) or (e.name or e.key))
  end
  return (table.concat(lines, "\n"):gsub("|", ""))
end

-------------------------------------------------------------------------------
-- explicit confirmation of an "unverified" observation by the GM or an officer. A signed Model
-- record `vconfirm` (id = observation id, d = { oid }) that only GM / officers may write; every client holding it
-- clears the `uv` mark of that observation (same effect as a GM/officer relay, but explicit and replicated).
R.VCONFIRM_SCHEMA = { oid = { "s", 200 } }
function R.applyConfirm(state, rec, roster, settings)
  local d = rec.d
  if type(d.oid) ~= "string" or d.oid == "" or rec.id ~= d.oid then return false, "shape" end
  local P = ns.Permissions
  if not (P and P.isOfficer(roster, rec.a, settings)) then return false, "denied" end
  state.vconfirm = state.vconfirm or {}
  local cur = state.vconfirm[rec.id]
  -- one confirmation is enough. Concurrent confirmations converge on the earliest
  -- (ts, author, sq) record, so the vconfirm bucket hashes match on every peer
  if cur then
    local M = ns.Model
    if (cur.ts == rec.ts and cur.a == rec.a and cur.sq == rec.sq) or not (M and M.earlier(rec, cur)) then return false, "dup" end
  end
  state.vconfirm[rec.id] = rec
  return true, "applied"
end
do
  local M = ns.Model
  if M and M.registerKind then M.registerKind("vconfirm", R.VCONFIRM_SCHEMA, "vconfirm", 11, R.applyConfirm) end
end
-- clear the mark of every confirmed observation held in `store`. confirms = state.vconfirm. -> number cleared
function R.applyConfirms(store, confirms)
  local n = 0
  for oid in pairs(confirms or {}) do
    local o = store.obs[oid]
    if o and o.uv then o.uv = nil; n = n + 1 end
  end
  return n
end
-- unverified observations, newest first: { { id, ev } }
function R.unverifiedList(store)
  local out = {}
  for id, ev in pairs(store.obs or {}) do if ev.uv then out[#out + 1] = { id = id, ev = ev } end end
  table.sort(out, function(a, b) if a.ev.ts ~= b.ev.ts then return a.ev.ts > b.ev.ts end return a.id < b.id end)
  return out
end

return R
