// Guild Squads simulator scenarios S1-S10 (results: docs/en/SIMULATOR-RESULTS.md). Each returns
// { pass, checks: [ [label, ok, detail] ], metrics }. Positive assertions only: every check names the value it expects.
'use strict';
const { Sim, luaStr, sourcesAt } = require('./sim.js');

const SETTINGS = 'squadsEnabled = true, bench = 2, minCreateRank = 9, officerRanks = { 1 }, banned = {}, compEnabled = true';
function checker() {
  const checks = [];
  const check = (label, ok, detail) => { checks.push([label, !!ok, detail === undefined ? '' : String(detail)]); return !!ok; };
  return { checks, check, pass: () => checks.every((c) => c[1]) };
}
// guild: Gm (rank 0), officers Of1.. (rank 1), members Mb1.. (rank 5)
function makeGuild(sim, nOff, nMem, level) {
  sim.addMember('Gm', 0, level);
  for (let i = 1; i <= nOff; i++) sim.addMember('Of' + i, 1, level);
  for (let i = 1; i <= nMem; i++) sim.addMember('Mb' + i, 5, level);
}
function gmSettings(gm, extra) {
  const r = gm.run(`return A.SaveSettings({ ${SETTINGS}${extra ? ', ' + extra : ''} })`);
  return r[0] === true;
}
const full = (sim, n) => n + '-' + sim.realm;
function errorsCheck(sim, check) {
  const n = sim.errors();
  check('caught Lua errors = 0', n === 0, n === 0 ? 0 : n + ': ' + sim.errorText().slice(0, 400));
}

// S1: 10 clients create squads, request, accept and kick in random order -> same model hash everywhere
function S1(seed) {
  const sim = new Sim({ seed });
  const { check, checks, pass } = checker();
  makeGuild(sim, 0, 9);
  const cs = sim.roster.map((r) => sim.client(r.name));
  for (const c of cs) { c.login(); sim.run(1 + sim.rand() * 3); }
  sim.run(15);
  check('GM settings written', gmSettings(cs[0]));
  sim.run(20);
  for (const i of [1, 2, 3]) cs[i].run(`return A.CreateSquad({ name = "Squad ${i}", icon = 1, color = 1, border = 1, tags = {}, open = true })`);
  sim.run(10);
  let actions = 0;
  for (let k = 0; k < 120; k++) {
    const c = cs[1 + Math.floor(sim.rand() * 9)];
    const lab = c.run(`return SIM_squadAction(${sim.rand()}, ${sim.rand()})`)[0];
    if (lab && !/idle|none|waiting/.test(String(lab))) actions++;
    sim.run(sim.rand() * 5);
  }
  const conv = sim.settle(900, 10);
  const h = sim.hashes();
  check('every client has the same model hash after the calm', conv, JSON.stringify(Object.values(h).slice(0, 2)));
  check('the run changed squads (actions applied)', actions > 30, actions);
  const sizes = cs[0].val('(function() local t = {} for id, r in pairs(NS.state.squads) do if not r.d.disbanded then t[#t+1] = #r.d.members end end table.sort(t) return table.concat(t, ",") end)()')[0];
  check('live squads with members', String(sizes).length > 0, sizes);
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { actions, t: Math.round(sim.t), ...sim.stats } };
}

// S2: GM changes settings with 30 clients online -> all apply them in <= 60 s; a forged settings record does nothing
function S2(seed) {
  const sim = new Sim({ seed });
  const { check, checks, pass } = checker();
  makeGuild(sim, 2, 27);
  const cs = sim.roster.map((r) => sim.client(r.name));
  for (const c of cs) { c.login(); sim.run(0.5 + sim.rand()); }
  const gm = cs[0];
  check('GM settings written', gmSettings(gm));
  sim.settle(300, 10);
  check('baseline converged', sim.converged());
  gm.run('return A.SaveSettings({ squadsEnabled = true, bench = 1, minCreateRank = 3, officerRanks = { 1 }, banned = { "noob" }, compEnabled = true })');
  const t0 = sim.t;
  let tAll = null;
  while (sim.t - t0 < 120) {
    sim.run(1);
    if (cs.every((c) => String(c.val('NS.Model.settingsOf(NS.state).bench')[0]) === '1')) { tAll = sim.t - t0; break; }
  }
  check('all 30 clients apply the new settings in <= 60 s', tAll !== null && tAll <= 60, tAll === null ? 'not after 120 s' : tAll.toFixed(1) + ' s');
  // forgery: a member signs settings with his own name, and another one impersonates the GM (a = Gm-Realm)
  const forger = cs[10];
  forger.run(`NS.Comm.Send("D", { r = { { k = "settings", id = "settings", a = NS.me(), ts = GetServerTime(), sq = 9999, d = { squadsEnabled = false, bench = 0 } } } })`);
  forger.run(`NS.Comm.Send("D", { r = { { k = "settings", id = "settings", a = ${luaStr(full(sim, 'Gm'))}, ts = GetServerTime(), sq = 9998, d = { squadsEnabled = false, bench = 0 } } } })`);
  sim.run(60);
  const bad = cs.filter((c) => c !== forger && (String(c.val('NS.Model.settingsOf(NS.state).bench')[0]) !== '1' || c.val('tostring(NS.Model.settingsOf(NS.state).squadsEnabled)')[0] !== 'true'));
  check('forged settings applied by 0 clients', bad.length === 0, bad.map((c) => c.name).join(','));
  check('still converged after the forgery', sim.settle(120, 10));
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { applyAllSeconds: tAll, ...sim.stats } };
}

// S3: a new client logs in with 200 records in the guild. (a) an officer online -> converges in <= N rounds.
// (b) no GM / officer online -> v1.1: it gets every profile by P2P quorum (1.0: only what the connected authors own).
function S3(seed) {
  const { check, checks, pass } = checker();
  const metrics = {};
  {
    const sim = new Sim({ seed });
    makeGuild(sim, 1, 200);
    const off = sim.client('Of1');
    off.login(); sim.run(5);
    const names = sim.roster.filter((r) => /^Mb/.test(r.name)).map((r) => full(sim, r.name));
    const n = off.run(`return SIM_genRecords({ ${names.map(luaStr).join(',')} }, 0, ${sim.epoch - 86400 * 3})`)[0];
    check('officer holds 200 profile records', n === 200, n);
    sim.run(30);
    const nc = sim.client('Mb200');
    nc.login();
    const t0 = sim.t;
    let tConv = null;
    while (sim.t - t0 < 900) { sim.run(5); if (nc.hash() === off.hash()) { tConv = sim.t - t0; break; } }
    check('newcomer converges with the officer in <= 6 hello rounds (<= 450 s)', tConv !== null && tConv <= 450, tConv === null ? 'no' : tConv.toFixed(0) + ' s');
    metrics.convergeSeconds = tConv; metrics.records = n;
    errorsCheck(sim, check);
  }
  {
    const sim = new Sim({ seed: seed + 1 });
    makeGuild(sim, 1, 200);
    const authors = ['Mb1', 'Mb2', 'Mb3'].map((n) => sim.client(n));
    const names = sim.roster.filter((r) => /^Mb/.test(r.name)).map((r) => full(sim, r.name));
    for (const a of authors) { a.login(); sim.run(2); a.run(`return SIM_genRecords({ ${names.map(luaStr).join(',')} }, 0, ${sim.epoch - 86400 * 3})`); }
    sim.run(30);
    const nc = sim.client('Mb150');
    nc.login();
    sim.run(600);
    const got = nc.val('(function() local t = {} for id in pairs(NS.state.profiles) do t[#t+1] = id end table.sort(t) return table.concat(t, ",") end)()')[0];
    const want = ['Mb1', 'Mb150', 'Mb2', 'Mb3'].map((n) => full(sim, n)).sort().join(',');
    // v1.1: the 3 connected members hold the same 200 profiles; their replies give 2 distinct relayers per version
    // (quorum) -> the newcomer converges on all of them without an officer (it used to get only the 3 authors' own)
    const all = names.slice().sort().join(',');
    check('without officers the newcomer gets every profile (P2P quorum of 2 relayers)', got === all, got.split(',').length + ' profiles');
    metrics.noOfficerProfiles = got.split(',').length;
    errorsCheck(sim, check);
  }
  return { pass: pass(), checks, metrics };
}

// build two squads of 5 in a raid of 10 (captains create, members request, captains accept)
function twoSquads(sim, cs, a, b) {
  const mk = (cap, name) => cap.run(`return A.CreateSquad({ name = ${luaStr(name)}, icon = 1, color = 1, border = 1, tags = {}, open = true })`);
  mk(cs[a[0]], 'Alfa'); mk(cs[b[0]], 'Beta');
  sim.run(20);
  const sidA = cs[a[0]].val('A.MySquadId()')[0], sidB = cs[b[0]].val('A.MySquadId()')[0];
  for (const [sid, list] of [[sidA, a], [sidB, b]]) {
    for (const i of list.slice(1)) { cs[i].run(`return A.RequestJoin(${luaStr(sid)})`); sim.run(1); }
  }
  sim.run(20);
  for (const [sid, list] of [[sidA, a], [sidB, b]]) {
    for (const i of list.slice(1)) { cs[list[0]].run(`return A.AddMember(${luaStr(sid)}, ${luaStr(cs[i].full)})`); sim.run(2); }
  }
  sim.settle(300, 10);
  return [sidA, sidB];
}

// S4: raid of 10 with 2 squads; boss kill while comms are locked during the encounter -> same score and Top
function S4(seed) {
  const sim = new Sim({ seed });
  const { check, checks, pass } = checker();
  makeGuild(sim, 0, 9);
  const cs = sim.roster.map((r) => sim.client(r.name));
  for (const c of cs) { c.login(); sim.run(1); }
  sim.run(10); gmSettings(cs[0]); sim.run(20);
  const [sidA, sidB] = twoSquads(sim, cs, [1, 2, 3, 4, 5], [6, 7, 8, 9, 0]);
  const memA = cs[1].val(`#NS.Model.members(NS.state, ${luaStr(sidA)})`)[0], memB = cs[6].val(`#NS.Model.members(NS.state, ${luaStr(sidB)})`)[0];
  check('two squads of 5', memA === 5 && memB === 5, memA + '/' + memB);
  const group = '{ raid = true, ' + cs.map((c) => luaStr(c.full)).join(',') + ' }';
  for (const c of cs) c.run(`SIM_GROUP = ${group}; SIM_INST = { "Molten Core", "raid", 9, 409 }`);
  for (const c of cs) { c.run('SIM_ENCOUNTER = true'); c.fire('ENCOUNTER_START', 663, 'Lucifron', 9, 10); }
  // traffic generated during the encounter stays queued
  cs[2].run('return A.SaveProfile({ note = "pull" })');
  const sentBefore = cs.reduce((n, c) => n + c.sent, 0);
  sim.run(90);
  const sentDuring = cs.reduce((n, c) => n + c.sent, 0) - sentBefore;
  check('no addon message leaves a client during the encounter', sentDuring === 0, sentDuring);
  for (const c of cs) { c.run('SIM_ENCOUNTER = false'); c.fire('ENCOUNTER_END', 663, 'Lucifron', 9, 10, 1); sim.run(sim.rand() * 0.5); }
  sim.settle(600, 10);
  const wipe = cs[0].val('NS.ProgressGlue.Wipe()')[0];
  const texts = cs.map((c) => c.val(`SIM_scoreText(${luaStr(wipe)})`)[0]);
  check('every client has the same score and Top', texts.every((t) => t === texts[0]), texts[0]);
  check('both squads scored the boss', /=\d/.test(texts[0]) && !/=0\.0000;.*=0\.0000/.test(texts[0]) && texts[0].includes(sidA) && texts[0].includes(sidB), texts[0]);
  check('model converged', sim.converged());
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { score: texts[0], ...sim.stats } };
}

// S5: celebrations on, 20 clients -> exactly 1 guild chat message per event, over `seeds` seeds
function S5one(seed) {
  const sim = new Sim({ seed });
  makeGuild(sim, 1, 18, 59);
  const cs = sim.roster.map((r) => sim.client(r.name));
  for (const c of cs) { c.login(); sim.run(0.2 + sim.rand()); }
  sim.run(10);
  gmSettings(cs[0], 'celOn = true, celScope = "any", celSquad = true');
  sim.settle(300, 10);
  sim.run(90);   // the Hall's first pass (60 s after login) marks what was there before as already seen
  sim.chat.length = 0;
  // one member reaches level 60: their own client fires PLAYER_LEVEL_UP, everybody sees it in the guild roster
  const who = cs[2 + Math.floor(sim.rand() * 18)];
  for (const r of sim.roster) if (r.name === who.name) r.level = 60;
  who.run('SIM_LEVEL = 60'); who.fire('PLAYER_LEVEL_UP', 60);
  sim.markRoster();
  sim.run(180);
  const guildMsgs = sim.chat.filter((m) => m.channel === 'GUILD');
  // one level-up opens several races (overall, class, race): each EVENT must be announced exactly once
  const per = {};
  for (const m of guildMsgs) per[m.text] = (per[m.text] || 0) + 1;
  const events = Object.keys(per).length;
  const dup = Object.values(per).filter((v) => v !== 1).length;
  return { n: events > 0 && dup === 0 ? 1 : (events === 0 ? 0 : 2), events, msgs: guildMsgs.length, who: who.name, texts: guildMsgs.map((m) => m.from + ': ' + m.text), errors: sim.errors(), errText: sim.errorText() };
}
function S5(seed, seeds) {
  const { check, checks, pass } = checker();
  const counts = {};
  const bad = [];
  let errors = 0, evs = 0, msgs = 0;
  for (let s = 0; s < seeds; s++) {
    const r = S5one(seed + s);
    counts[r.n] = (counts[r.n] || 0) + 1;
    evs += r.events; msgs += r.msgs;
    errors += r.errors;
    if (r.n !== 1) bad.push(`seed ${seed + s}: ${r.n} (${r.texts.join(' | ').slice(0, 160)})`);
  }
  check(`exactly 1 guild message per event in ${seeds}/${seeds} seeds (${evs} events, ${msgs} messages)`, bad.length === 0, bad.slice(0, 3).join('; ') || JSON.stringify(counts));
  check('caught Lua errors = 0', errors === 0, errors);
  return { pass: pass(), checks, metrics: { seeds, events: evs, messages: msgs } };
}

// S6: wipe change (Wednesday 09:00) with clients skewed +-200 s -> same wipe results everywhere
function S6(seed) {
  const { check, checks, pass } = checker();
  // find the next reset from a probe client, then start the run 10 minutes before it
  const probe = new Sim({ seed });
  makeGuild(probe, 0, 1);
  const pc = probe.client('Gm'); pc.login();
  const reset = Number(pc.val('NS.Progress.wipeEndTs(NS.ProgressGlue.Wipe())')[0]);
  const sim = new Sim({ seed, epoch: reset - 900 });
  makeGuild(sim, 0, 9);
  const cs = sim.roster.map((r) => sim.client(r.name, { skew: Math.round((sim.rand() * 2 - 1) * 200) }));
  for (const c of cs) { c.login(); sim.run(1); }
  sim.run(10); gmSettings(cs[0]); sim.run(20);
  const [sidA, sidB] = twoSquads(sim, cs, [1, 2, 3, 4, 5], [6, 7, 8, 9, 0]);
  const groups = [[1, 2, 3, 4, 5], [6, 7, 8, 9, 0]];
  groups.forEach((g, gi) => {
    const lua = '{ ' + g.map((i) => luaStr(cs[i].full)).join(',') + ' }';
    for (const i of g) cs[i].run(`SIM_GROUP = ${lua}; SIM_INST = { "Ragefire Chasm", "party", 1, 389 }`);
  });
  // kills from 5 min before to 5 min after the reset (true time); each client stamps them with its own clock
  let enc = 100;
  while (sim.t < 900 + 300) {
    const g = groups[Math.floor(sim.rand() * 2)];
    enc++;
    for (const i of g) { cs[i].fire('ENCOUNTER_START', enc, 'Boss ' + enc, 1, 5); cs[i].fire('ENCOUNTER_END', enc, 'Boss ' + enc, 1, 5, 1); }
    sim.run(20 + sim.rand() * 40);
  }
  sim.settle(600, 10);
  const prev = cs[0].val('NS.Progress.prevWipe(NS.Progress.wipeOf(GetServerTime() - 3600), 0)')[0];
  const cur = cs[0].val('NS.Progress.wipeOf(GetServerTime() + 3600)')[0];
  const liveSame = {};
  for (const w of [prev, cur]) {
    const texts = cs.map((c) => c.val(`SIM_scoreText(${luaStr(w)})`)[0]);
    // the live score of a CLOSED wipe uses the canonical rule of the summary -> same on all
    liveSame[w] = new Set(texts).size;
    if (w === prev) check(`same live score for closed wipe ${w} on every client`, liveSame[w] === 1, String(liveSame[w]));
    const sums = cs.map((c) => c.val(`NS.Progress.summaryHash((NS.Progress.wipeSummary(NS.ProgressGlue.Events(), ${luaStr(w)}, (function() local o = NS.ProgressGlue.Opts(); o.profiles = NS.state.profiles; o.squads = NS.state.squads; return o end)())))`)[0]);
    check(`same wipe summary for ${w} on every client`, sums.every((t) => t === sums[0]), sums[0]);
  }
  if (process.env.SIM_DEBUG) { const a = cs[0].model().split('\n'), b = cs[6].model().split('\n'); console.log('DIFF', a.filter((x) => !b.includes(x)).join('\n'), '\n---\n', b.filter((x) => !a.includes(x)).join('\n')); }
  const skews = cs.map((c) => c.skew);
  check('clients are skewed', Math.max(...skews) - Math.min(...skews) > 100, skews.join(','));
  check('model converged', sim.converged(), process.env.SIM_DEBUG ? JSON.stringify(sim.hashes()) + cs.map((c) => c.val('#NS.Model.allRecords(NS.state) .. " ev" .. (function() local n=0 for _ in pairs(NS.ProgressGlue.Events()) do n=n+1 end return n end)()')[0]).join(',') : '');
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { prev, cur, kills: enc - 100, skews, liveScoreVariants: liveSame } };
}

// S7: raid roster: publish, 15 RSVPs, invite, close without the RL -> "pending", later signature -> same attendance
function S7(seed) {
  const sim = new Sim({ seed });
  const { check, checks, pass } = checker();
  makeGuild(sim, 1, 15);
  const cs = sim.roster.map((r) => sim.client(r.name));
  for (const c of cs) { c.login(); sim.run(0.5); }
  const gm = cs[0], rl = cs[1], mem = cs.slice(2);
  sim.run(10); gmSettings(gm); sim.settle(200, 10);
  const at = Number(rl.val('NS.RaidGlue.WallNow()')[0]) + 3600 * 2;
  const rid = rl.run(`local id = NS.RaidGlue.Create({ raid = "custom", size = 20, name = "MC jueves", at = ${at} }); return id`)[0];
  const ridS = String(rid);
  check('RL created the roster', !!rid, ridS);
  rl.run(`local r = NS.RaidGlue.Get(${luaStr(ridS)}); local d = NS.Roster.copy(r.d); ` +
    mem.map((c) => `NS.Roster.addPlayer(d, ${luaStr(c.full)})`).join('; ') + `; return NS.RaidGlue.Publish(${luaStr(ridS)}, d)`);
  sim.settle(200, 10);
  for (const c of mem) { c.run(`return NS.RaidGlue.Answer(${luaStr(ridS)}, "yes", "")`); sim.run(1 + sim.rand() * 3); }
  sim.settle(300, 10);
  const conf = rl.val(`#NS.Roster.confirmed(NS.state, ${luaStr(ridS)})`)[0];
  check('15 RSVPs confirmed on the RL', conf === 15, conf);
  // raid time: the RL invites, then leaves; the 15 raid in the window and log out before the close
  sim.run(2 * 3600 - (sim.t % 60) - 60);
  const group = '{ raid = true, ' + [rl, ...mem].map((c) => luaStr(c.full)).join(',') + ' }';
  rl.run('SIM_GROUP = nil');   // solo: first click invites the party cap, the rest on the next clicks
  const inv = rl.run(`local r = NS.RaidGlue.Invite(${luaStr(ridS)}); return r and r.invited or -1`)[0];
  check('RL invite batch sent', inv > 0, inv);
  rl.run(`SIM_GROUP = nil`); rl.logout();
  for (const c of mem) c.run(`SIM_GROUP = ${group}`);
  sim.run(1800);
  for (const c of mem) { c.run('SIM_GROUP = nil'); c.logout(); }
  sim.run(3 * 3600);  // past at + 3 h: the GM (online, not in the raid) closes it with nothing seen
  const st1 = gm.val(`NS.Roster.attendanceState(NS.state, ${luaStr(ridS)})`)[0];
  check('closed without the RL -> attendance pending', st1 === 'pending', st1);
  // the RL comes back and signs the attendance from the confirmed list; members come back later
  rl.login(); sim.settle(300, 10);
  const signed = rl.run(`return NS.RaidGlue.SignAttendance(${luaStr(ridS)}, NS.Roster.confirmed(NS.state, ${luaStr(ridS)}))`)[0];
  check('RL signs the attendance later', signed === true, signed);
  for (const c of mem) { c.login(); sim.run(1); }
  sim.settle(900, 15);
  const lists = sim.online().map((c) => c.val(`NS.Roster.attendanceState(NS.state, ${luaStr(ridS)}) .. ":" .. table.concat(NS.Roster.attendanceList(NS.state, ${luaStr(ridS)}), ",")`)[0]);
  check('everyone sees the same signed attendance', lists.every((l) => l === lists[0]) && /^signed:/.test(lists[0]), lists[0].slice(0, 80) + ' n=' + (lists[0].split(',').length));
  check('attendance has the 15 raiders', lists[0].split(',').length >= 15, lists[0].split(',').length);
  check('model converged', sim.converged());
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { invited: inv, ...sim.stats } };
}

// S8: load: 500 members and 100 squads, 20 clients -> msgs/s per client (mean, peak) under the throttle, bounded queue
function S8(seed, minutes) {
  const sim = new Sim({ seed });
  const { check, checks, pass } = checker();
  makeGuild(sim, 2, 497);
  const names = sim.roster.filter((r) => /^Mb/.test(r.name)).map((r) => full(sim, r.name));
  names.unshift(full(sim, 'Of2'), full(sim, 'Of1'), full(sim, 'Gm'));
  const gen = sim.client('Gm');
  gen.login(); sim.run(3);
  gmSettings(gen); sim.run(1);
  const n = gen.run(`return SIM_genRecords({ ${names.map(luaStr).join(',')} }, 100, ${sim.epoch - 86400 * 5})`)[0];
  check('500 profiles + 100 squads generated', n >= 600, n);
  gen.logout();
  const saved = gen.saved;
  const online = ['Gm', 'Of1', 'Of2', ...Array.from({ length: 17 }, (_, i) => 'Mb' + (i * 25 + 3))];
  const cs = online.map((nm) => sim.client(nm, { saved }));
  for (const c of cs) { c.login(); sim.run(1 + sim.rand() * 4); }
  const t0 = sim.t;
  for (const c of cs) { c.sent = 0; c.sentAt = []; c.maxQueue = 0; c.throttled = 0; }
  const end = t0 + (minutes || 15) * 60;
  while (sim.t < end) {
    const c = cs[Math.floor(sim.rand() * cs.length)];
    c.run(`return A.SaveProfile({ note = "n${Math.floor(sim.rand() * 1000)}" })`);
    sim.run(5 + sim.rand() * 20);
  }
  const dur = sim.t - t0;
  let mean = 0, peak1 = 0, peak10 = 0, maxQ = 0, thr = 0;
  for (const c of cs) {
    mean = Math.max(mean, c.sent / dur);
    const at = c.sentAt.filter((x) => x >= t0).sort((a, b) => a - b);
    let j = 0, k = 0;
    for (let i = 0; i < at.length; i++) {
      while (at[i] - at[j] >= 1) j++;
      while (at[i] - at[k] >= 10) k++;
      peak1 = Math.max(peak1, i - j + 1); peak10 = Math.max(peak10, (i - k + 1) / 10);
    }
    maxQ = Math.max(maxQ, c.maxQueue); thr += c.throttled;
  }
  const avgAll = cs.reduce((s, c) => s + c.sent, 0) / cs.length / dur;
  const partsEdits = cs.reduce((s, c) => s + c.sent, 0);
  // v1.2 AC3 (BRO 7-nov 19:07: measured in S8 instead of S8g): right after the edits a newcomer with empty
  // SavedVariables logs in; t95 / t100 of the profiles + squads it holds (stored = verified), the curve
  // [s, held, pending ids] every 30 s, and the local "synced" chat line (once). GSQ_S8_NEWCOMER=0: no newcomer (the
  // traffic run for AC5, same conditions as the 1.1 S8).
  let nc = null, t95 = null, t100 = null, t95v = null, t100v = null, target = null, curve = [], chat = [];
  if (process.env.GSQ_S8_NEWCOMER !== '0') {
    const cnt = `(function() local n = 0 for _ in pairs(NS.state.profiles) do n = n + 1 end for _ in pairs(NS.state.squads) do n = n + 1 end return n end)()`;
    const pendCnt = `(function() local n = 0 for _ in pairs((NS.state.p2p and NS.state.p2p.pend) or {}) do n = n + 1 end return n end)()`;
    // annex G (BRO 8-nov 04:13: what cannot be verified is shown «sin verificar»): `vis` = stored (verified) plus held
    // pending (shown grey) ids. S8's 600 records are generated unsigned (1.1-era data, authors never online with 1.2
    // keys), so most of them cannot be verified by design; AC3 is checked on vis, the verified-only times are metrics.
    const visCnt = `(function() local s = {} for id in pairs(NS.state.profiles) do s["profile:" .. id] = true end for id in pairs(NS.state.squads) do s["squad:" .. id] = true end for kid, byId in pairs((NS.state.p2p and NS.state.p2p.pend) or {}) do if next(byId) and (kid:match("^profile:") or kid:match("^squad:")) then s[kid] = true end end local n = 0 for _ in pairs(s) do n = n + 1 end return n end)()`;
    target = Number(cs[0].val(cnt)[0]);
    nc = sim.client('Mb2');
    const tn = sim.t;
    nc.login();
    for (let k = 0; k < 60 && t100 === null; k++) {
      sim.run(10);
      const h = Number(nc.val(cnt)[0]);
      const v = Number(nc.val(visCnt)[0]);
      if (k % 3 === 2) { curve.push([Math.round(sim.t - tn), h, Number(nc.val(pendCnt)[0]), v]); console.error('S8 newcomer', JSON.stringify(curve[curve.length - 1]), 'of', target); }
      if (t95 === null && h >= 0.95 * target) t95 = Math.round(sim.t - tn);
      if (h >= target) t100 = Math.round(sim.t - tn);
      if (t95v === null && v >= 0.95 * target) t95v = Math.round(sim.t - tn);
      if (t100v === null && v >= target) t100v = Math.round(sim.t - tn);
    }
    sim.run(120);  // room for the "synced" line (60 s of quiet after the last round)
    const raw = nc.val('(function() local o = {} for _, e in ipairs(SIM_LOCAL or {}) do o[#o + 1] = e.s end return table.concat(o, "\\n") end)()')[0];
    chat = String(raw || '').split('\n').filter((x) => x);
  }
  check('mean msgs/s per client (busiest) <= 1.05 (client throttle 1/s; Comm drains at 1/s)', mean <= 1.05, mean.toFixed(3));
  check('peak in any 1 s window <= 10 (throttle burst)', peak1 <= 10, peak1);
  check('sends refused by the throttle = 0', thr === 0, thr);
  check('send queue never above X = 500', maxQ <= 500, maxQ);
  check('model converged', sim.settle(900, 15));
  if (nc) {
    const syncedLines = chat.filter((x) => /^Guild Squads: (synced|sincronizado) \(\d+ /.test(x));
    check('AC3 newcomer 95 % (verified + «sin verificar») in <= 240 s', t95v !== null && t95v <= 240, t95v + ' s (verified only: ' + t95 + ' s)');
    check('AC3 newcomer 100 % (verified + «sin verificar») in <= 600 s', t100v !== null && t100v <= 600, t100v + ' s (verified only: ' + t100 + ' s)');
    check('AC3 the newcomer writes the local "synced" chat line exactly once', syncedLines.length === 1, JSON.stringify(chat).slice(0, 200));
  }
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { clients: cs.length, seconds: Math.round(dur), meanAll: +avgAll.toFixed(3), meanBusiest: +mean.toFixed(3), peak1s: peak1, peak10s: +peak10.toFixed(2), maxQueue: maxQ, throttled: thr, records: n,
    partsEdits, newcomerTarget: target, newcomerT95: t95, newcomerT100: t100, newcomerT95vis: t95v, newcomerT100vis: t100v, newcomerCurve: curve, newcomerChat: chat } };
}

// S9: chaos: 1 simulated hour of random actions with 5 % loss and random /reloads -> convergence, no Lua errors
function S9(seed, minutes) {
  const sim = new Sim({ seed, loss: 0.05 });
  const { check, checks, pass } = checker();
  makeGuild(sim, 1, 10);
  const cs = sim.roster.map((r) => sim.client(r.name));
  for (const c of cs) { c.login(); sim.run(1); }
  sim.run(10); gmSettings(cs[0]); sim.run(30);
  for (const i of [2, 3, 4]) cs[i].run(`return A.CreateSquad({ name = "Caos ${i}", icon = 1, color = 1, border = 1, tags = {}, open = true })`);
  const end = sim.t + (minutes || 60) * 60;
  const counts = { act: 0, reload: 0, logout: 0, login: 0, profile: 0, settings: 0 };
  while (sim.t < end) {
    const c = cs[Math.floor(sim.rand() * cs.length)];
    const r = sim.rand();
    if (!c.online) { c.login(); counts.login++; }
    else if (r < 0.04) { c.reload(); counts.reload++; }
    else if (r < 0.07 && c !== cs[0]) { c.logout(); counts.logout++; }
    else if (r < 0.15) { c.run(`return A.SaveProfile({ note = "c${Math.floor(sim.rand() * 99)}" })`); counts.profile++; }
    else if (r < 0.17 && c === cs[0]) { gmSettings(c, `inactiveDays = ${7 + Math.floor(sim.rand() * 20)}`); counts.settings++; }
    else { c.run(`return SIM_squadAction(${sim.rand()}, ${sim.rand()})`); counts.act++; }
    sim.run(2 + sim.rand() * 18);
  }
  for (const c of cs) if (!c.online) c.login();
  sim.loss = 0;
  const conv = sim.settle(1200, 15);
  let diff = '';
  if (!conv) {
    const hs = sim.hashes(), names = Object.keys(hs);
    const other = names.find((n) => hs[n] !== hs[names[0]]);
    const a = cs[0].model().split('\n'), b = sim.clients[other].model().split('\n');
    const line = a.find((x) => !b.includes(x));
    if (line && /^squad\|/.test(line)) diff = ' why=' + sim.clients[other].run(`local r = NS.state.squads[${luaStr(line.split('|')[1])}]; local mine = r and r.ts; return tostring(mine)`)[0];
    diff += ' | ' + names[0] + ' only: ' + a.filter((x) => !b.includes(x)).join(' ; ') + ' | ' + other + ' only: ' + b.filter((x) => !a.includes(x)).join(' ; ');
  }
  check('final convergence (same model hash on all 11 clients)', conv, JSON.stringify(Object.values(sim.hashes()).slice(0, 3)) + diff);
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { counts, lost: sim.stats.lost, t: Math.round(sim.t) } };
}

// S10: 30 clients, 5 of them running an older build without the GM catalog (git ref GSQ_COMPAT_REF of a build without the catalog). The GM disables 60 races
// (one bulk = 60 achdef records) and creates 5 custom achievements. Every current client converges on the same catalog
// in the time the throttle allows (measured); a member's forged achdef (own name / impersonating the GM) is taken by
// nobody; the older clients refuse the unknown kinds without a Lua error and keep syncing the rest.
const V091 = process.env.GSQ_COMPAT_REF;
function S10(seed) {
  if (!V091) throw new Error('S10 needs GSQ_COMPAT_REF: a git ref (reachable from GIT_DIR) of a build without the GM catalog');
  const sim = new Sim({ seed });
  const { check, checks, pass } = checker();
  makeGuild(sim, 2, 27);
  const old = sourcesAt(V091);
  const oldNames = new Set(['Mb4', 'Mb9', 'Mb14', 'Mb19', 'Mb24']);
  const cs = sim.roster.map((r) => sim.client(r.name, oldNames.has(r.name) ? { code: old } : {}));
  const olds = cs.filter((c) => oldNames.has(c.name)), news = cs.filter((c) => !oldNames.has(c.name));
  for (const c of cs) { c.login(); sim.run(0.5 + sim.rand()); }
  const gm = cs[0];
  check('GM settings written', gmSettings(gm));
  sim.settle(300, 10);
  check('baseline converged (30 clients, 5 on the older build)', sim.converged());
  sim.run(90);   // every client computed the Hall once
  // the bulk: 60 races off
  const bulk = gm.run(`local items = {}
    for _, id in ipairs(NS.HallGlue.CatalogIds()) do
      if NS.Catalog.isRaceId(id) and #items < 60 then items[#items + 1] = { id = id, d = { on = false } } end
    end
    -- the sim guild is all warriors: the class races of the other classes (real ids, still empty) fill up to 60
    for _, cls in ipairs({ "MAGE", "PRIEST", "ROGUE", "DRUID", "HUNTER" }) do
      for _, h in ipairs(NS.Races.LEVELS) do
        if #items < 60 then items[#items + 1] = { id = "lvl.class." .. cls .. "." .. h, d = { on = false } } end
      end
    end
    local a, r = A.WriteMany("achdef", items)
    return a, r, #items, NS.Sync.EstimateParts((select(3, A.WriteMany("achdef", items, true))))`);
  check('bulk: 60 achdef records applied by the GM', bulk[0] === 60 && bulk[1] === 0, bulk.join('/'));
  const customs = gm.run(`local H, n = NS.HallGlue, 0
    local specs = { { metric = "level", thr = 20, size = 5, name = "Primeros al 20" },
                    { metric = "level", param = "class:WARRIOR", thr = 40, size = 3, name = "Guerreros al 40" },
                    { metric = "bg", thr = 5, size = 3, name = "5 BG juntos" },
                    { metric = "manual", scope = "squad", name = "Squad del mes" },
                    { metric = "manual", scope = "char", name = "Héroe de la guild" } }
    for _, sp in ipairs(specs) do if H.CreateCustom(sp) then n = n + 1 end end
    return n`)[0];
  check('5 custom achievements created', customs === 5, customs);
  const want = gm.val('SIM_catalogText()')[0];
  const t0 = sim.t;
  let tAll = null;
  while (sim.t - t0 < 900) {
    sim.run(5);
    if (news.every((c) => c.val('SIM_catalogText()')[0] === want)) { tAll = sim.t - t0; break; }
  }
  const counts = news.map((c) => c.val('SIM_catalogCount()')[0]);
  check('all 25 current clients hold the same catalog (65 records, 60 off)', tAll !== null && counts.every((x) => x === '65/60'), tAll === null ? 'not after 900 s: ' + counts.join(',') : counts[0]);
  check(`convergence within the throttle estimate (${bulk[3]} parts at 1 msg/s + 5 customs, <= 300 s)`, tAll !== null && tAll <= 300, tAll === null ? 'no' : tAll.toFixed(0) + ' s');
  // forgery: a member signs an achdef with his own name, another impersonates the GM
  const forger = news[news.length - 1];
  forger.run(`NS.Comm.Send("D", { r = { { k = "achdef", id = "lvl.all.60", a = NS.me(), ts = GetServerTime(), sq = 9999, d = { on = true, name = "hack1" } } } })`);
  forger.run(`NS.Comm.Send("D", { r = { { k = "achdef", id = "lvl.all.10", a = ${luaStr(full(sim, 'Gm'))}, ts = GetServerTime(), sq = 9998, d = { on = true, name = "hack2" } } } })`);
  forger.run(`NS.Comm.Send("D", { r = { { k = "achgrant", id = "first60|" .. NS.me(), a = NS.me(), ts = GetServerTime(), sq = 9997, d = { ach = "first60", who = NS.me(), reason = "yo", on = true } } } })`);
  sim.run(60);
  const took = news.filter((c) => c !== forger && c.val('SIM_catalogText()')[0] !== want);
  check('forged achdef / achgrant accepted by 0 clients (catalog unchanged on the other 24)', took.length === 0, took.map((c) => c.name).join(','));
  // 1.1: refused as a relay. 1.2 (AC4): a member relaying authority leaves it pending, never verified without quorum.
  // Per honest client: "A" = the fake is applied (fail), "P" = held pending unverified, "R" = refused as relay, "-" = neither
  const fake = news.filter((c) => c !== forger && c !== gm).map((c) => c.val(`(function()
    local X, s = NS.P2P, NS.state
    local r = X and X.getStored and X.getStored(s, "achdef", "lvl.all.10") or (NS.Model.kindTable and NS.Model.kindTable(s, "achdef")["lvl.all.10"])
    if r and r.d and r.d.name == "hack2" then return "A" end
    local u = X and X.unverified and X.unverified(s, "achdef", "lvl.all.10")
    if u and u.r and u.r.d and u.r.d.name == "hack2" then return "P" end
    if (NS.Sync.stats.relayRefused or 0) >= 1 then return "R" end
    local st = s.p2p
    if (NS.Sync.stats.pending or 0) >= 1 and st and (st.repudiated or 0) >= 1 then return "D" end
    return "-" end)()`)[0]).join('');
  // raw counters of the first honest client: relayRefused / pending / repudiated / bad
  const raw = news.find((c) => c !== forger && c !== gm).val('NS.Sync.stats.relayRefused, NS.Sync.stats.pending, NS.state.p2p and NS.state.p2p.repudiated or -1, NS.Sync.stats.bad').join('/');
  check('the GM-impersonating copy was refused as a relay, held pending or denied by the GM, never applied', /^[RPD]+$/.test(fake), fake + ' (refused/pending/repudiated/bad ' + raw + ')');
  // the GM is the impersonated author: it never holds the fake and denies it (1.2: repudiated; 1.1: refused as relay)
  const gmSays = gm.val(`(function() local r = NS.Model.kindTable(NS.state, "achdef")["lvl.all.10"]
    if r and r.d and r.d.name == "hack2" then return "A" end
    local st = NS.state.p2p
    if (st and (st.repudiated or 0) >= 1) or (NS.Sync.stats.mine or 0) >= 1 then return "D" end
    if (NS.Sync.stats.relayRefused or 0) >= 1 then return "R" end
    return "-" end)()`)[0];
  check('the impersonated GM never holds the fake and denies or refuses it', gmSays === 'D' || gmSays === 'R', gmSays);
  // the older clients: unknown kinds refused (counted as bad), no Lua error, everything else still syncs
  const bad = olds.map((c) => Number(c.val('NS.Sync.stats.bad')[0]));
  check('older clients received and refused the new kinds (Sync.stats.bad > 0 on each)', bad.every((b) => b > 0), bad.join(','));
  const oldCat = olds.map((c) => c.val('SIM_catalogText()')[0]);
  check('older clients store no achdef / achgrant', oldCat.every((x) => x === ''), oldCat.map((x) => x.length).join(','));
  olds[0].run('return A.SaveProfile({ note = "091 sigue" })');
  news[3].run('return A.SaveProfile({ note = "010 sigue" })');
  gm.run('return A.SaveSettings({ squadsEnabled = true, bench = 1, minCreateRank = 9, officerRanks = { 1 }, banned = {}, compEnabled = true })');
  let tCore = null;
  const t1 = sim.t;
  while (sim.t - t1 < 600) {
    sim.run(5);
    const h = cs.map((c) => c.val('SIM_coreHash()')[0]);
    if (h.every((x) => x === h[0])) { tCore = sim.t - t1; break; }
  }
  check('after the catalog: profiles / settings still converge on all 30 (older build included)', tCore !== null, tCore === null ? 'no' : tCore.toFixed(0) + ' s');
  const n091 = olds.map((c) => c.val('NS.Model.settingsOf(NS.state).bench')[0]);
  check('older clients applied the new GM settings', n091.every((b) => String(b) === '1'), n091.join(','));
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { catalogConvergeSeconds: tAll, bulkParts: bulk[3], coreConvergeSeconds: tCore, oldBad: bad, ref091: V091, ...sim.stats } };
}

// ---- v1.1: P2P sync (docs/SPEC-v1.1-sync-p2p.md) ------------------------------------------------------------
// what client `c` holds of the authorial records written by `authors` (profile note "soy <name>" + presence):
// "v" = verified (stored), "u" = unverified (pending), "-" = missing. Returns one char per author and kind.
function holdings(sim, c, authors) {
  const list = authors.map((n) => `{ ${luaStr(full(sim, n))}, ${luaStr('soy ' + n)} }`).join(',');
  return c.val(`(function() local X, out = NS.P2P, {}
    for _, e in ipairs({ ${list} }) do
      local p = NS.state.profiles[e[1]]
      local u = X and X.unverified(NS.state, "profile", e[1])
      out[#out + 1] = (p and p.d.note == e[2]) and "v" or ((u and u.r.d.note == e[2]) and "u" or "-")
      local q = NS.state.presence and NS.state.presence[e[1]]
      local uq = X and X.unverified(NS.state, "presence", e[1])
      out[#out + 1] = q and "v" or (uq and "u" or "-")
    end
    return table.concat(out) end)()`)[0];
}

// squads held by client c: "v" = in NS.state.squads, "u" = pending / unverified (v1.2), "-" = missing
function squadHoldings(c, ids) {
  const list = ids.map((id) => luaStr(id)).join(',');
  return c.val(`(function() local X, out = NS.P2P, {}
    for _, id in ipairs({ ${list} }) do
      local r = NS.state.squads[id]
      local u = X and X.unverified and X.unverified(NS.state, "squad", id)
      out[#out + 1] = r and "v" or (u and "u" or "-")
    end
    return table.concat(out) end)()`)[0];
}

// annex F/G key audit: each client's own key, counts, and every key it holds for another member compared with that
// member's real key ("fakes" = name:author:strength of every wrong key held, uncontested)
function keyAudit(cs, names) {
  const keys = {};
  for (const c of cs) {
    c.login();
    const v = c.run(`local pk = NS.myPk and NS.myPk(); local db = NS.trustDB or {}; local s, w, p = NS.Trust.counts(db)
      local held = {}
      for n, k in pairs(db.keys or {}) do if not (db.contested and db.contested[n]) then held[#held + 1] = n .. "=" .. k.pk .. "=" .. k.s end end
      table.sort(held)
      return pk and NS.Trust.hex(pk) or "", s, w, p, table.concat(held, ";")`);
    keys[c.name] = { pk: String(v[0]).slice(0, 8), full: String(v[0]), strong: v[1], weak: v[2], pend: v[3], held: String(v[4] || '') };
    c.logout();
  }
  const realPk = {}; for (const n of names) realPk[n] = keys[n].full;
  const fakes = [];
  for (const n of names) for (const e of keys[n].held.split(';').filter(Boolean)) {
    const [who, pk, st] = e.split('=');
    const short = who.split('-')[0];
    const real = realPk[who] !== undefined ? realPk[who] : realPk[short];
    if (real !== undefined && real !== pk) fakes.push(`${n}:${who}:${st}`);
  }
  const certHeld = Object.fromEntries(names.map((n) => [n, keys[n].held.split(';').filter((e) => e.endsWith('=cert')).length]));
  for (const k of Object.values(keys)) { delete k.full; delete k.held; }
  return { keys, fakes, certHeld };
}

// S11 (AC1): no GM / officer with the addon. 5 clients log in staggered, never more than 2 online at once
// (forward chain, backward chain, forward chain: <= 3 sessions per client, each one overlapping the next for 25 min).
// Every authorial record (profiles + presence) of every author reaches every client, and so do the squads (v1.2 AC1)
// that Mb1 and Mb4 create in their first session (authority records: in v1.1 only the author or an officer may
// hand them over, so Mb3/Mb5 never get Mb1's squad -> red expected on v1.1).
// S15 (AC1) = S11 with the GM online all along (it is not counted in "online at once").
function s11core(seed, withGm) {
  const sim = new Sim({ seed });
  const { check, checks, pass } = checker();
  makeGuild(sim, 1, 5);                         // Gm and Of1 exist in the roster; in S11 they never run the addon
  const names = ['Mb1', 'Mb2', 'Mb3', 'Mb4', 'Mb5'];
  const cs = names.map((n) => sim.client(n));
  let gm = null;
  if (withGm) { gm = sim.client('Gm'); gm.login(); sim.run(20); }
  const members = () => sim.online().filter((c) => c !== gm).length;
  const sessions = {}; let maxOnline = 0;
  const squadIds = [];
  const OVER = 25 * 60;
  const on = (c) => {
    if (c.online) return;
    c.login(); sessions[c.name] = (sessions[c.name] || 0) + 1;
    maxOnline = Math.max(maxOnline, members());
    sim.run(20);
    c.run(`return A.SaveProfile({ note = ${luaStr('soy ' + c.name)} })`);
    if (sessions[c.name] === 1 && (c.name === 'Mb1' || c.name === 'Mb4')) {
      sim.run(5);
      c.run(`return A.CreateSquad({ name = ${luaStr('Squad ' + c.name)}, icon = 1, color = 1, border = 1, tags = {}, open = true })`);
      const id = c.val('A.MySquadId()')[0];
      if (id) squadIds.push(String(id));
    }
  };
  const chain = (order) => {
    on(cs[order[0]]);
    for (let i = 1; i < order.length; i++) { on(cs[order[i]]); sim.run(OVER); cs[order[i - 1]].logout(); }
  };
  chain([0, 1, 2, 3, 4]);
  chain([4, 3, 2, 1, 0]);
  const after2 = {}, sq2 = {};
  cs[0].logout();
  for (const c of cs) { c.login(); after2[c.name] = holdings(sim, c, names); sq2[c.name] = squadHoldings(c, squadIds); c.logout(); }
  chain([0, 1, 2, 3, 4]);
  cs[4].logout();
  const after3 = {}, sq3 = {};
  for (const c of cs) { c.login(); after3[c.name] = holdings(sim, c, names); sq3[c.name] = squadHoldings(c, squadIds); c.logout(); }
  const cells = Object.values(after3).join('');
  const arrived = cells.split('').filter((x) => x !== '-').length, total = cells.length;
  const verified = cells.split('').filter((x) => x === 'v').length;
  const sqCells = Object.values(sq3).join('');
  const sqArrived = sqCells.split('').filter((x) => x !== '-').length, sqTotal = sqCells.length;
  const sqVerified = sqCells.split('').filter((x) => x === 'v').length;
  check('never more than 2 member clients online at once', maxOnline <= 2, maxOnline);
  check('<= 3 sessions per client', Object.values(sessions).every((n) => n <= 3), JSON.stringify(sessions));
  check('100 % of the authorial records reached every client (verified or unverified) after 3 passes', arrived === total, `${arrived}/${total} ${JSON.stringify(after3)}`);
  check('2 squads created (Mb1, Mb4)', squadIds.length === 2, JSON.stringify(squadIds));
  check('100 % of the squads reached every client (verified or pending) after 3 passes', sqTotal > 0 && sqArrived === sqTotal, `${sqArrived}/${sqTotal} ${JSON.stringify(sq3)}`);
  if (withGm) check('GM online all along, no officer', !!gm.online && !sim.clients.Of1, '');
  else check('no GM / officer ever online', !sim.clients.Gm && !sim.clients.Of1, '');
  // annex F wiring: every client made its own key, keys are distinct, and they travel (strong in person, cert by annex G)
  const { keys, fakes, certHeld } = keyAudit(cs, names);
  check('AF7: 0 fake keys accepted', fakes.length === 0, JSON.stringify(fakes));
  const maxGraph = withGm ? 38 : 26;   // annex G graph maximum, docs/DESIGN-certificados.md
  check(`AF7: verified authorial records >= graph maximum (${maxGraph}/50)`, verified >= maxGraph, `${verified}/${total} certHeld=${JSON.stringify(certHeld)}`);
  const pks = Object.values(keys).map((k) => k.pk);
  check('annex F: every client has its own key, all distinct', pks.every((x) => x.length === 8) && new Set(pks).size === pks.length, JSON.stringify(keys));
  check('annex F: every client learned >= 1 key in person', Object.values(keys).every((k) => k.strong >= 1), JSON.stringify(keys));
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { keys, fakes, certHeld, arrived, total, verified, sqArrived, sqTotal, sqVerified, after2, after3, sq2, sq3, sessions, t: Math.round(sim.t), ...sim.stats } };
}
function S11(seed) { return s11core(seed, false); }
function S15(seed) { return s11core(seed, true); }

// S12 (AC2 + AC4, annex F model, QA D2): a forged profile of an offline author. One malicious relayer -> unverified on
// every client and never verified; a second colluder changes nothing (no quorum: no author signature, never applied).
// The author logs in: its version on every client, the fake gone (stored and pending). No repudiate is needed: the
// fake was never applied anywhere (a repudiate is only signed for a record that carries a valid signature).
function S12(seed) {
  const sim = new Sim({ seed });
  const { check, checks, pass } = checker();
  makeGuild(sim, 1, 6);
  const [au, y, z, c1, c2] = ['Mb1', 'Mb2', 'Mb3', 'Mb4', 'Mb5'].map((n) => sim.client(n));
  const honest = [c1, c2];
  for (const c of [au, c1, c2]) { c.login(); sim.run(5); }
  au.run('return A.SaveProfile({ note = "real" })');
  sim.run(60);
  au.logout();
  for (const c of [y, z]) { c.login(); sim.run(5); }
  sim.run(30);
  const AU = full(sim, 'Mb1');
  const FTS = sim.epoch + Math.round(sim.t) + 250;   // the same forged version from both colluders
  const forge = `NS.Comm.Send("D", { r = { { k = "profile", id = ${luaStr(AU)}, a = ${luaStr(AU)}, ts = ${FTS}, sq = 777, d = { note = "falso", level = 60 } } } })`;
  y.run(forge); sim.run(1); y.run(forge);
  sim.run(120);
  const view = (c) => c.val(`(function() local p = NS.state.profiles[${luaStr(AU)}]; local u = NS.P2P.unverified(NS.state, "profile", ${luaStr(AU)})
    return (p and p.d.note or "nil") .. "/" .. (u and u.r.d.note or "nil") end)()`)[0];
  const v1 = honest.map(view);
  check('one malicious relayer: the fake is unverified on every honest client, the real one stays', v1.every((x) => x === 'real/falso'), v1.join(','));
  sim.run(1200);     // hellos and anti-entropy: nobody turns it into verified
  const v1b = honest.map(view);
  check('20 min later, still never verified (single relayer)', v1b.every((x) => x === 'real/falso'), v1b.join(','));
  z.run(forge);
  sim.run(60);
  const v2 = honest.map(view);
  check('a second colluder: still unverified (no quorum with signatures)', v2.every((x) => x === 'real/falso'), v2.join(','));
  au.login();
  sim.run(300);
  const all = [au, y, z, c1, c2];
  const v3 = all.map(view);
  check('the author logs in: the real version on every client, the fake gone (stored and pending)', v3.every((x) => x === 'real/nil'), v3.join(','));
  const rep = c1.val('NS.DiagGlue.Report()')[0];
  const line = (rep.match(/p2p pend=[^\n|]*/) || [''])[0];
  const nRep = all.map((c) => c.val('(function() local n = 0 for _ in pairs(NS.state.repudiates or {}) do n = n + 1 end return n end)()')[0]);
  check('no repudiate needed (the unsigned fake was never applied)', nRep.every((n) => Number(n) === 0), nRep.join(','));
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { diag: line, t: Math.round(sim.t), ...sim.stats } };
}

// S16 (v1.2 annex F, AF2): poisoning with signatures. k = 2, 3 and 5 accomplices (alts the honest clients know in
// person) forge, while the GM, the captain Mb1 and the victim Mb7 are offline: a GM `settings`, Mb1's squad, Mb7's
// profile and a `repudiate` of Mb7's real profile. Three ways each: bare records, the same with a fake key for the
// author (`ks`) plus a manifest signed with it, and a manifest for the victim signed with the alt's own key. No fake
// is applied on any honest client (settings, squad, profile and repudiate as they were). The legitimate relayed
// version arrives (Mb7 edits with Mb8 online; Mb9, offline then, gets it from Mb8 verified). A flood of 600 fake
// pending records from one relayer stays capped at 200 and does not evict the legitimate one. Metric (not a check,
// annex G pending): a fake key + profile for Mb11, whom no honest client ever heard in person.
function s16run(seed, k) {
  const sim = new Sim({ seed });
  const { check, checks, pass } = checker();
  makeGuild(sim, 1, 12);
  const [gm, cap, vic] = [sim.client('Gm'), sim.client('Mb1'), sim.client('Mb7')];
  const alts = Array.from({ length: k }, (_, i) => sim.client('Mb' + (i + 2)));
  const honest = ['Mb8', 'Mb9', 'Mb10'].map((n) => sim.client(n));
  for (const c of [gm, cap, vic, ...honest]) { c.login(); sim.run(5); }
  check('GM settings written', gmSettings(gm));
  sim.run(20);
  cap.run('return A.CreateSquad({ name = "Lobos", icon = 1, color = 1, border = 1, tags = {}, open = true })');
  const SID = String(cap.val('A.MySquadId()')[0]);
  vic.run('return A.SaveProfile({ note = "real" })');
  sim.run(60);
  gm.logout(); cap.logout(); vic.logout();
  const GM = full(sim, 'Gm'), CAP = full(sim, 'Mb1'), VIC = full(sim, 'Mb7'), ZED = full(sim, 'Mb11');
  for (const c of alts) { c.login(); sim.run(5); }
  sim.run(30);
  const view = (c) => c.val(`(function() local s = NS.Model.settingsOf(NS.state); local q = NS.state.squads[${luaStr(SID)}]
    local p = NS.state.profiles[${luaStr(VIC)}]; local z = NS.state.profiles[${luaStr(ZED)}]
    local nr = 0 for _ in pairs(NS.state.repudiates or {}) do nr = nr + 1 end
    return tostring(s.bench) .. "/" .. (q and q.d.name or "nil") .. "/" .. (p and p.d.note or "nil") .. "/rep" .. nr .. "|" .. (z and (z.d.note .. ":" .. tostring(NS.P2P.strengthOf(NS.state, z))) or "nil") end)()`)[0];
  const T0 = Date.now(); const tr = (m) => { if (process.env.GSQ_TRACE) console.error(`S16 k=${k} ${m} ${((Date.now() - T0) / 1000).toFixed(1)}s`); };
  const before = honest.map(view);
  check('setup: honest clients hold the real settings, squad and profile', before.every((x) => x.startsWith('2/Lobos/real/rep0|')), before.join(','));
  const realVic = honest[0].val(`(function() local p = NS.state.profiles[${luaStr(VIC)}]; return NS.P2P.vkey(p) end)()`)[0];
  const FTS = sim.epoch + Math.round(sim.t) + 200;
  // every alt: 3 attacks, each one twice (a retry does not help)
  const forge = (i) => `(function()
    local E, G, X = NS.Ed25519, NS.Sig, NS.P2P
    local fsk = string.rep(string.char(${11 + i}), 32); local fpk = E.publicKey(fsk); local fhex = NS.Trust.hex(fpk)
    local recs = {
      { k = "settings", id = "settings", a = ${luaStr(GM)}, ts = ${FTS}, sq = 9001, d = { squadsEnabled = false, bench = 0, minCreateRank = 9, officerRanks = { 1 }, banned = {}, compEnabled = true } },
      { k = "squad", id = ${luaStr(SID)}, a = ${luaStr(CAP)}, ts = ${FTS}, sq = 9002, d = { name = "Hackeado", captain = ${luaStr(CAP)}, members = { ${luaStr(CAP)} }, bench = {}, icon = 1, color = 1, border = 1, tags = {}, open = true, approved = true } },
      { k = "profile", id = ${luaStr(VIC)}, a = ${luaStr(VIC)}, ts = ${FTS}, sq = 9003, d = { note = "falso", level = 60 } },
      { k = "repudiate", id = ${luaStr(realVic)}, a = ${luaStr(VIC)}, ts = ${FTS}, sq = 9004, d = { t = "profile:" .. ${luaStr(VIC)}, v = ${luaStr(realVic)} } },
      { k = "profile", id = ${luaStr(ZED)}, a = ${luaStr(ZED)}, ts = ${FTS}, sq = 9005, d = { note = "fantasma", level = 60 } },
    }
    NS.Comm.Send("D", { r = recs })
    local ks, ms = {}, {}
    for _, a in ipairs({ ${luaStr(GM)}, ${luaStr(CAP)}, ${luaStr(VIC)}, ${luaStr(ZED)} }) do
      ks[a] = fhex; ms[#ms + 1] = G.build(a, 2000000000 + ${i}, recs, fsk, fpk)
    end
    NS.Comm.Send("D", { r = recs, ks = ks, m = ms })
    local osk, opk = NS.Trust.own(GuildSquadsDB.ownKeys[NS.me()])
    if osk then NS.Comm.Send("D", { r = recs, m = { G.build(${luaStr(VIC)}, 2010000000 + ${i}, recs, osk, opk) } }) end
    return true end)()`;
  for (let i = 0; i < alts.length; i++) { alts[i].val(forge(i)); sim.run(1); alts[i].val(forge(i)); sim.run(1); }
  tr('forged'); sim.run(120); tr('run120');
  for (let n = 0; n < 200; n++) for (const c of honest) c.step();
  tr('drained');   // drain the verify queue
  sim.run(600);
  tr('run600'); const after = honest.map(view);
  const core = (x) => x.split('|')[0];
  check(`${k} alts: no fake settings / squad / profile / repudiate applied on any honest client`, after.every((x) => core(x) === '2/Lobos/real/rep0'), after.join(','));
  // the legitimate relayed version: Mb7 edits with Mb8 online, Mb9 (offline then) gets it from Mb8 only
  honest[1].logout();
  vic.login(); sim.run(10); vic.run('return A.SaveProfile({ note = "legit" })'); sim.run(40); vic.logout();
  sim.run(10);
  honest[1].login();
  if (process.env.GSQ_TRACE) honest[1].val(`(function() SIMDBG = {} local o = NS.debug; NS.debug = function(m) if tostring(m):find(${luaStr(VIC)}, 1, true) then SIMDBG[#SIMDBG + 1] = tostring(m) end if o then return o(m) end end
    local of = NS.Sig.offer; NS.Sig.offer = function(db, m, k) local r = of(db, m, k); if m.a == ${luaStr(VIC)} then SIMDBG[#SIMDBG + 1] = "offer n=" .. tostring(m.n) .. " " .. tostring(r) end return r end return true end)()`);
  sim.run(120);
  sim.run(60);
  // the sim only runs OnUpdate (1 verify per frame) when a client steps: drain Mb9's verify queue before reading
  for (let n = 0; n < 200; n++) honest[1].step();
  const legit = honest[1].val(`(function() local p = NS.state.profiles[${luaStr(VIC)}]; return (p and p.d.note or "nil") .. ":" .. tostring(p and NS.P2P.strengthOf(NS.state, p)) end)()`)[0];
  if (process.env.GSQ_TRACE) console.error('S16dbg Mb9 log', honest[1].val('table.concat(SIMDBG, " ## ")')[0]);
  if (process.env.GSQ_TRACE) for (const c of honest) console.error('S16dbg', c.name || '?', c.val(`(function() local G = NS.Sig; local db = NS.sigDB
    local m = db and db.man and db.man[${luaStr(VIC)}]; local own = db and db.own and db.own[${luaStr(VIC)}]
    local p = NS.state.profiles[${luaStr(VIC)}]; local c = G.counts(db)
    local np = 0 for _, byId in pairs(NS.state.p2p and NS.state.p2p.pend or {}) do for _ in pairs(byId) do np = np + 1 end end
    return "man.n=" .. tostring(m and m.n) .. " own.n=" .. tostring(own and own.n) .. " p=" .. tostring(p and p.d.note) .. " st=" .. tostring(p and G.status(db, p)) .. " q=" .. G.pending() .. " pend=" .. np .. " ver=" .. tostring(c.verified) .. " rej=" .. tostring(c.rejected) .. " pk=" .. table.concat((function() local o = {} for kid, byId in pairs(NS.state.p2p and NS.state.p2p.pend or {}) do for _, e in pairs(byId) do o[#o + 1] = kid .. "@" .. tostring(e.r.a) .. "=" .. tostring(e.r.d and e.r.d.note) end end return o end)(), ",") end)()`)[0]);
  check('the legitimate relayed version arrives verified (Mb9 from Mb8)', legit.startsWith('legit:') && !/weak/.test(legit), legit);
  // flood: 600 fake pending squads from one alt do not pass 200 by him nor evict a legitimate pending copy
  tr('legit'); const Y = full(sim, 'Mb2'), PUB = VIC;
  const h0 = honest[0];
  const t0 = sim.epoch + Math.round(sim.t);
  const flood = h0.val(`(function()
    local X = NS.P2P
    for i = 1, 600 do
      NS.Sync.Apply({ k = "squad", id = ${luaStr(CAP)} .. ":" .. (1000 + i), a = ${luaStr(CAP)}, ts = ${t0} - i, sq = 100 + i,
        d = { name = "F" .. i, captain = ${luaStr(CAP)}, members = { ${luaStr(CAP)} }, bench = {}, icon = 1, color = 1, border = 1, tags = {}, open = true, approved = true } }, ${luaStr(Y)})
    end
    local byY = 0
    for _, byId in pairs(NS.state.p2p.pend) do for _, e in pairs(byId) do if e.by[${luaStr(Y)}] then byY = byY + 1 end end end
    local p = NS.state.profiles[${luaStr(PUB)}]
    return byY .. "|" .. (p and p.d.note or "nil") .. "|" .. X.stats(NS.state, 0).pend
  end)()`)[0];
  const [byY, keep] = String(flood).split('|');
  check('600 fakes from one relayer (3x the cap): at most 200 pending by him', Number(byY) <= 200, flood);
  check('the legitimate version survives the flood', keep === 'legit', flood);
  tr('flood'); gm.login(); sim.run(120); cap.login(); sim.run(120);
  const fin = [gm, cap, ...honest].map(view);
  check('GM and Mb1 back: real settings and squad everywhere', fin.every((x) => x.startsWith('2/Lobos/')), fin.join(','));
  const zed = after.map((x) => x.split('|')[1]);
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { k, zedNeverSeen: zed, flood, t: Math.round(sim.t), ...sim.stats } };
}
function S16(seed) {
  const out = { pass: true, checks: [], metrics: {} };
  for (const k of (process.env.GSQ_S16K ? process.env.GSQ_S16K.split(',').map(Number) : [2, 3, 5])) {
    const r = s16run(seed, k);
    out.pass = out.pass && r.pass;
    for (const c of r.checks) out.checks.push([`[k=${k}] ` + c[0], c[1], c[2]]);
    out.metrics['k' + k] = r.metrics;
  }
  return out;
}

// S16b (annex G, AF7): 2 alts known in person by the honest clients certify the SAME fake key for Z (Mb11). Mb10
// met Z in person and certifies his real key: with that honest certificate against, Z's key is "disputed" and
// nothing new of Z is applied. When Z comes online (in person), his own records apply and the fake ones are dropped.
// S16c (QA D12): the same without Mb10 (no honest certificate against). The 2 alts' certificates make the fake key
// "cert" on the honest clients and the fake profile IS applied (the documented limit of annex G); when Z logs in
// in person his key wins, what the fake key signed is dropped (ns.OnKeyReplaced) and his own profile applies.
function S16b(seed) { return s16bRun(seed, true); }
function S16c(seed) { return s16bRun(seed, false); }
function s16bRun(seed, withWit) {
  const sim = new Sim({ seed });
  const { check, checks, pass } = checker();
  makeGuild(sim, 1, 12);
  const gm = sim.client('Gm');
  const alts = ['Mb2', 'Mb3'].map((n) => sim.client(n));
  const [h1, h2, wit] = ['Mb8', 'Mb9', 'Mb10'].map((n) => sim.client(n));
  const z = sim.client('Mb11');
  const ZED = full(sim, 'Mb11');
  for (const c of [gm, h1, h2, ...(withWit ? [wit] : []), ...alts]) { c.login(); sim.run(5); }
  check('GM settings written', gmSettings(gm));
  sim.run(60);
  for (const c of [gm, h1, h2, ...alts]) c.logout();
  // Z meets only Mb10 in person, saves his profile, leaves
  // the sim only runs frames when a client steps: give Z the frames of a real login (entropy for his key)
  z.login(); for (let n = 0; n < 80; n++) { sim.run(0.2); z.step(); } sim.run(5);
  const zpk0 = z.val('NS.myPk() ~= nil')[0];
  z.run('return A.SaveProfile({ note = "realz" })'); sim.run(60);
  const zpk1 = z.val('NS.myPk() ~= nil')[0];
  z.logout();
  sim.run(30);
  for (const c of [h1, h2, ...alts]) { c.login(); sim.run(5); }
  sim.run(120);
  const keyView = (c) => c.val(`(function() local T, db = NS.Trust, NS.trustDB
    local pk, s = T.keyOf(db, ${luaStr(ZED)}); local nc = #T.candidates(db, ${luaStr(ZED)})
    local p = NS.state.profiles[${luaStr(ZED)}]
    local cw = NS.certDB.crt and NS.certDB.crt[${luaStr(full(sim,'Mb10'))}]
    local dbg = " w=" .. (cw and (#cw.e .. "@" .. cw.n) or "none")
    return tostring(s) .. "/" .. (db.contested[${luaStr(ZED)}] and "contested" or "-") .. "/c" .. nc .. "/" .. (p and (tostring(p.d.note) .. ":" .. tostring(NS.P2P.strengthOf(NS.state, p))) or "nil") .. dbg end)()`)[0];
  const pendZ = (c) => c.val(`(function() local n = 0 for kid, byId in pairs(NS.state.p2p and NS.state.p2p.pend or {}) do for _, e in pairs(byId) do if e.r.a == ${luaStr(ZED)} then n = n + 1 end end end return n end)()`)[0];
  const before = [h1, h2].map(keyView).concat([withWit ? 'wit:' + keyView(wit) : 'wit:-', 'pendZ:' + [h1, h2].map(pendZ).join('/')]);
  const FTS = sim.epoch + Math.round(sim.t) + 200;
  // both alts: the same fake key for Z, a fake profile of Z signed with it, and a certificate (signed with the alt's
  // own key, known in person) that lists hash12(Z | fake key) next to the keys the alt heard in person
  const forge = (i) => `(function()
    local E, G, C, T = NS.Ed25519, NS.Sig, NS.Cert, NS.Trust
    local fsk = string.rep(string.char(77), 32); local fpk = E.publicKey(fsk)
    local recs = { { k = "profile", id = ${luaStr(ZED)}, a = ${luaStr(ZED)}, ts = ${FTS}, sq = 9005, d = { note = "fantasma", level = 60 } } }
    local heard = {}
    for name, k in pairs(NS.trustDB.keys) do if k.s == "strong" then heard[name] = T.unhex(k.pk) end end
    heard[${luaStr(ZED)}] = fpk
    local osk, opk = T.own(GuildSquadsDB.ownKeys[NS.me()])
    local c = C.build(NS.me(), ${FTS} + ${i}, heard, osk, opk)
    NS.Comm.Send("D", { r = recs, ks = { [${luaStr(ZED)}] = T.hex(fpk) }, m = { G.build(${luaStr(ZED)}, 2000000000, recs, fsk, fpk) },
      c = { i = c.i, n = c.n, e = c.e, s = c.s } })
    return true end)()`;
  for (let i = 0; i < alts.length; i++) { alts[i].val(forge(i)); sim.run(2); }
  sim.run(120);
  for (let n = 0; n < 200; n++) for (const c of [h1, h2]) c.step();
  sim.run(60);
  for (let n = 0; n < 50; n++) for (const c of [h1, h2]) c.step();
  const after = [h1, h2].map(keyView);
  if (withWit) {
    check('2 alts + 1 honest certificate against: Z disputed on the honest clients', after.every((x) => /contested/.test(x) || /^disputed/.test(x)), after.join(','));
    check('nothing fake of Z applied (no "fantasma")', after.every((x) => !/fantasma/.test(x)), after.join(','));
  } else {
    check('2 alts, nobody against: the fake key is certified and the fake profile applied (annex G limit)', after.every((x) => /^cert\//.test(x) && /fantasma/.test(x)), after.join(','));
  }
  // Z online with Mb8 and Mb9: in person wins
  z.login(); sim.run(90);
  for (let n = 0; n < 200; n++) for (const c of [h1, h2]) c.step();
  // QA D12: before Z writes anything new, his key heard in person alone must drop what the fake key signed
  const mid = [h1, h2].map(keyView);
  check('Z in person, before any new record: the fake profile is dropped', mid.every((x) => x.startsWith('strong/') && !/fantasma/.test(x)), mid.join(','));
  z.run('return A.SaveProfile({ note = "realz2" })'); sim.run(90);
  for (let n = 0; n < 200; n++) for (const c of [h1, h2]) c.step();
  const fin = [h1, h2].map(keyView);
  check('Z in person: his key strong and his own profile applied, the fake dropped', fin.every((x) => x.startsWith('strong/') && /realz2:strong/.test(x) && !/fantasma/.test(x)), fin.join(','));
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { zpk0, zpk1, before, after, mid, fin, t: Math.round(sim.t), ...sim.stats } };
}

// S13 (AC8): channel load. 40 clients (GM, 2 officers, 37 members) with 200 profiles + 20 squads on disk, 15 min
// of profile edits: messages per minute per client of v1.1 vs the reference build (GSQ_REF, default v1.0.1 = 406029a)
// with the same seed, the same MAX_REPLY and the same queue. Second run without GM / officers online. During an
// encounter no client sends anything.
const REF = process.env.GSQ_REF || '406029a';
function loadRun(seed, code, minutes, withOfficers) {
  const sim = new Sim({ seed });
  makeGuild(sim, 2, 197);
  const names = sim.roster.filter((r) => /^Mb/.test(r.name)).map((r) => full(sim, r.name));
  const gen = sim.client('Gm', code ? { code } : {});
  gen.login(); sim.run(3); gmSettings(gen); sim.run(1);
  gen.run(`return SIM_genRecords({ ${names.map(luaStr).join(',')} }, 20, ${sim.epoch - 86400 * 5})`);
  gen.logout();
  const saved = gen.saved;
  delete sim.clients.Gm;
  const online = (withOfficers ? ['Gm', 'Of1', 'Of2'] : []).concat(Array.from({ length: withOfficers ? 37 : 40 }, (_, i) => 'Mb' + (i * 4 + 1)));
  const cs = online.map((nm) => sim.client(nm, code ? { saved, code } : { saved }));
  for (const c of cs) { c.login(); sim.run(1 + sim.rand() * 4); }
  const t0 = sim.t;
  for (const c of cs) { c.sent = 0; c.sentAt = []; }
  const end = t0 + minutes * 60;
  while (sim.t < end) {
    const c = cs[Math.floor(sim.rand() * cs.length)];
    c.run(`return A.SaveProfile({ note = "n${Math.floor(sim.rand() * 1000)}" })`);
    sim.run(5 + sim.rand() * 20);
  }
  const dur = (sim.t - t0) / 60;
  const per = cs.map((c) => c.sent / dur);
  // encounter: every client locked for 2 min while edits continue -> 0 messages sent
  for (const c of cs) { c.run('SIM_ENCOUNTER = true'); c.fire('ENCOUNTER_START', 663, 'Lucifron', 9, 40); }
  const before = cs.map((c) => c.sent);
  for (let k = 0; k < 8; k++) { cs[k].run(`return A.SaveProfile({ note = "enc${k}" })`); sim.run(15); }
  const inEnc = cs.reduce((a, c, i) => a + c.sent - before[i], 0);
  for (const c of cs) { c.run('SIM_ENCOUNTER = false'); c.fire('ENCOUNTER_END', 663, 'Lucifron', 9, 40, 1); }
  const conv = sim.settle(900, 15);
  return { mean: per.reduce((a, b) => a + b, 0) / per.length, busiest: Math.max(...per), inEnc, conv, errors: sim.errors(), errText: sim.errorText() };
}
function S13(seed, minutes) {
  const { check, checks, pass } = checker();
  minutes = minutes || 15;
  const old = sourcesAt(REF);
  const metrics = { ref: REF };
  for (const off of [true, false]) {
    const tag = off ? 'officers' : 'noOfficers';
    const a = loadRun(seed, old, minutes, off), b = loadRun(seed, null, minutes, off);
    metrics[tag] = { refMean: +a.mean.toFixed(3), newMean: +b.mean.toFixed(3), refBusiest: +a.busiest.toFixed(3), newBusiest: +b.busiest.toFixed(3) };
    check(`${tag}: mean msgs/min per client v1.1 <= 1.3 x ${REF}`, b.mean <= a.mean * 1.3, `${b.mean.toFixed(2)} vs ${a.mean.toFixed(2)}`);
    check(`${tag}: busiest client v1.1 <= 1.3 x ${REF}`, b.busiest <= a.busiest * 1.3, `${b.busiest.toFixed(2)} vs ${a.busiest.toFixed(2)}`);
    check(`${tag}: messages sent during the encounter = 0`, b.inEnc === 0, b.inEnc);
    check(`${tag}: v1.1 converged after the run`, b.conv, '');
    check(`${tag}: caught Lua errors = 0`, b.errors === 0, b.errors ? b.errText.slice(0, 300) : 0);
  }
  return { pass: pass(), checks, metrics };
}

// S14 (v1.2, adaptada a PROTO 2; la de la 1.1 probaba la interoperabilidad 1.0.1 <-> 1.1, que BRO corta el 7-nov
// 21:20): 2 clients on v1.0.1 (GSQ_REF) among 6 on v1.2, no officers online. Everyone saves a profile, a 1.2 client
// forges Mb1's profile, Mb1 reloads. Criteria: no old client holds anything from a 1.2 client (nor the forgery) and no
// 1.2 client holds anything from an old one; the 1.2 clients sync among themselves and refuse the forgery; the old
// clients still sync between them (author's own records); every 1.2 client online through the logins counts the 2 old
// members; 0 Lua errors. S17 covers the same cut with 1.1 clients and officers.
function S14(seed) {
  const sim = new Sim({ seed });
  const { check, checks, pass } = checker();
  makeGuild(sim, 1, 8);
  const old = sourcesAt(REF);
  const oldNames = new Set(['Mb2', 'Mb5']);
  const names = ['Mb1', 'Mb2', 'Mb3', 'Mb4', 'Mb5', 'Mb6', 'Mb7', 'Mb8'];
  const cs = names.map((n) => sim.client(n, oldNames.has(n) ? { code: old } : {}));
  for (const c of cs) { c.login(); sim.run(2 + sim.rand() * 3); }
  sim.run(30);
  for (const c of cs) { c.run(`return A.SaveProfile({ note = ${luaStr('soy ' + c.name)} })`); sim.run(2); }
  sim.run(120);
  const M1 = full(sim, 'Mb1');
  cs[2].run(`NS.Comm.Send("D", { r = { { k = "profile", id = ${luaStr(M1)}, a = ${luaStr(M1)}, ts = GetServerTime() + 200, sq = 555, d = { note = "falso" } } } })`);
  sim.run(60);
  cs[0].logout(); sim.run(5); cs[0].login();
  sim.run(600);
  const olds = cs.filter((c) => oldNames.has(c.name)), news = cs.filter((c) => !oldNames.has(c.name));
  const own = (c, o) => c.val(`(function() local p = NS.state.profiles[${luaStr(o.full)}]; return p and p.d.note or "nil" end)()`)[0];
  const leakOld = [];
  for (const o of olds) for (const n of news) if (own(o, n) !== 'nil') leakOld.push(`${o.name}<-${n.name}:${own(o, n)}`);
  check('no old client holds anything from a 1.2 client (nor the forgery)', leakOld.length === 0, leakOld.join(','));
  const leakNew = [];
  for (const n of news) for (const o of olds) if (own(n, o) !== 'nil') leakNew.push(`${n.name}<-${o.name}:${own(n, o)}`);
  check('no 1.2 client holds anything from an old client', leakNew.length === 0, leakNew.join(','));
  const missNew = [];
  for (const n of news) for (const o of news) if (n !== o && own(n, o) !== 'soy ' + o.name) missNew.push(`${n.name}<-${o.name}:${own(n, o)}`);
  check('the 1.2 clients sync among themselves and refuse the forgery', missNew.length === 0, missNew.join(','));
  const oldOld = [];
  for (const o of olds) for (const p of olds) if (o !== p && own(o, p) !== 'soy ' + p.name) oldOld.push(`${o.name}<-${p.name}:${own(o, p)}`);
  check('the old clients still sync between them', oldOld.length === 0, oldOld.join(','));
  const cnt = news.map((c) => `${c.name}:${c.val('NS.Comm.OldPeerCount()')[0]}`);
  check('every 1.2 client online through the logins counts the 2 old members', news.filter((c) => c.name !== 'Mb1').every((c) => Number(c.val('NS.Comm.OldPeerCount()')[0]) === 2), cnt.join(','));
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { ref: REF, oldPeers: cnt, ...sim.stats } };
}

// S17 (v1.2, AC de corte que sustituye a AC6; BRO 7-nov 21:20): Comm.PROTO = 2 cuts 1.0.x / 1.1 off. 12 clients:
// 8 on v1.2 (GM, Of1, Mb1, Mb3, Mb7-Mb10); Mb4, Mb6 on v1.1 (GSQ_REF11, default 636e545); Mb2, Mb5 on v1.0.1 (REF).
// Everyone logs in, the GM writes the settings, everyone saves a profile, the GM changes the settings, Mb2 and Mb1
// reload. Criteria: no old client holds anything written by a 1.2 client (profiles, settings) and no 1.2 client holds
// anything from an old one; every 1.2 client counts the 4 old members (Comm.OldPeerCount) and, once synced, writes
// the local old-version line; 0 Lua errors. Measured only: the old clients still sync among themselves.
const REF11 = process.env.GSQ_REF11 || '636e545';
function S17(seed) {
  const sim = new Sim({ seed });
  const { check, checks, pass } = checker();
  makeGuild(sim, 1, 10);
  const v101 = sourcesAt(REF), v11 = sourcesAt(REF11);
  const ver = { Mb2: '1.0.1', Mb5: '1.0.1', Mb4: '1.1', Mb6: '1.1' };
  const names = ['Gm', 'Of1', 'Mb1', 'Mb2', 'Mb3', 'Mb4', 'Mb5', 'Mb6', 'Mb7', 'Mb8', 'Mb9', 'Mb10'];
  const cs = {};
  for (const n of names) cs[n] = sim.client(n, ver[n] === '1.0.1' ? { code: v101 } : ver[n] === '1.1' ? { code: v11 } : {});
  const all = names.map((n) => cs[n]);
  const olds = ['Mb2', 'Mb5', 'Mb4', 'Mb6'];
  const news = names.filter((n) => !ver[n]);
  for (const c of all) { c.login(); sim.run(2 + sim.rand() * 3); }
  sim.run(20);
  check('GM settings written', gmSettings(cs.Gm));
  sim.run(30);
  for (const c of all) { c.run(`return A.SaveProfile({ note = ${luaStr('soy ' + c.name)} })`); sim.run(2); }
  sim.run(120);
  check('GM changes the settings (bench 1)', cs.Gm.run(`return A.SaveSettings({ ${SETTINGS.replace('bench = 2', 'bench = 1')} })`)[0] === true);
  sim.run(60);
  cs.Mb2.reload(); sim.run(3); cs.Mb1.reload();
  sim.run(300);
  const bench = (c) => c.val('(function() local s = NS.state.settings; return s and s.d and tostring(s.d.bench) or "nil" end)()')[0];
  const own = (c, o) => c.val(`(function() local p = NS.state.profiles[${luaStr(o.full)}]; return p and p.d.note or "nil" end)()`)[0];
  const newBench = news.map((n) => `${n}:${bench(cs[n])}`);
  check('the 1.2 clients hold the new settings (bench 1)', news.every((n) => bench(cs[n]) === '1'), newBench.join(','));
  const missNew = [];
  for (const n of news) for (const o of news) if (n !== o && own(cs[n], cs[o]) !== 'soy ' + o) missNew.push(`${n}<-${o}:${own(cs[n], cs[o])}`);
  check('the 1.2 clients sync among themselves (every 1.2 profile)', missNew.length === 0, missNew.slice(0, 8).join(','));
  const leakOld = [];
  for (const o of olds) {
    if (bench(cs[o]) !== 'nil') leakOld.push(`${o}:settings=${bench(cs[o])}`);
    for (const n of news) if (own(cs[o], cs[n]) !== 'nil') leakOld.push(`${o}<-${n}:${own(cs[o], cs[n])}`);
  }
  check('no old client holds anything from a 1.2 client (profiles, settings)', leakOld.length === 0, leakOld.slice(0, 8).join(','));
  const leakNew = [];
  for (const n of news) for (const o of olds) if (own(cs[n], cs[o]) !== 'nil') leakNew.push(`${n}<-${o}:${own(cs[n], cs[o])}`);
  check('no 1.2 client holds anything from an old client', leakNew.length === 0, leakNew.slice(0, 8).join(','));
  const cnt = news.map((n) => `${n}:${cs[n].val('NS.Comm.OldPeerCount()')[0]}`);
  // a session only counts the old members it hears: Mb1 reloaded after them, so it hears only those who speak again (Mb2)
  check('every 1.2 client online through the logins counts the 4 old members (Comm.OldPeerCount)', news.filter((n) => n !== 'Mb1').every((n) => Number(cs[n].val('NS.Comm.OldPeerCount()')[0]) === 4), cnt.join(','));
  const chat = (c) => c.val('(function() local o = {} for _, e in ipairs(SIM_LOCAL or {}) do if type(e) == "table" and e.s then o[#o + 1] = e.s end end return table.concat(o, "\\n") end)()')[0];
  const mb1 = chat(cs.Mb1);
  const lines = news.map((n) => [n, (chat(cs[n]).match(/old version|versión antigua/g) || []).length]);
  check('every 1.2 client writes the local old-version line exactly once', lines.every((x) => x[1] === 1), lines.map((x) => x.join(':')).join(','));
  check('the reloaded 1.2 client (Mb1) also writes it, with the old members it heard', /\b[1-4]\b[^\n]*(old version|versión antigua)/.test(mb1), mb1.replace(/\n/g, ' / '));
  const oldOld = [];
  for (const o of olds) for (const p of olds) if (o !== p && own(cs[o], cs[p]) !== 'soy ' + p) oldOld.push(`${o}<-${p}`);
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { ref: REF, ref11: REF11, oldAmongThemselvesMissing: oldOld, oldPeers: cnt, ...sim.stats } };
}

// S8g (v1.2 AC0/AC2/AC3/AC5): the S13 guild (200 members: GM, 2 officers, 197 members; 200 profiles + 20 squads on
// disk), 40 clients online (GM + 2 officers + 37 members) for `minutes` of profile edits, then a newcomer with an
// empty SavedVariables logs in. Measures the totals the v1.2 criteria compare against the reference builds
// (run it with GSQ_ROOT = a checkout of 1.1 / 1.0.1): parts sent in total and per client, max queue, mean msgs/s,
// newcomer time to 95 % / 100 % of what it lacked, time to converge.
function S8g(seed, minutes) {
  const sim = new Sim({ seed });
  const { check, checks, pass } = checker();
  minutes = minutes || 15;
  makeGuild(sim, 2, 197);
  const names = sim.roster.filter((r) => /^Mb/.test(r.name)).map((r) => full(sim, r.name));
  names.unshift(full(sim, 'Of2'), full(sim, 'Of1'), full(sim, 'Gm'));
  const gen = sim.client('Gm');
  gen.login(); sim.run(3); gmSettings(gen); sim.run(1);
  const n = gen.run(`return SIM_genRecords({ ${names.map(luaStr).join(',')} }, 20, ${sim.epoch - 86400 * 5})`)[0];
  gen.logout();
  const saved = gen.saved;
  delete sim.clients.Gm;
  const online = ['Gm', 'Of1', 'Of2', ...Array.from({ length: 37 }, (_, i) => 'Mb' + (i * 4 + 1))];
  const cs = online.map((nm) => sim.client(nm, { saved }));
  for (const c of cs) { c.login(); sim.run(1 + sim.rand() * 4); }
  const t0 = sim.t;
  for (const c of cs) { c.sent = 0; c.sentAt = []; c.maxQueue = 0; c.throttled = 0; }
  const end = t0 + minutes * 60;
  while (sim.t < end) {
    const c = cs[Math.floor(sim.rand() * cs.length)];
    c.run(`return A.SaveProfile({ note = "n${Math.floor(sim.rand() * 1000)}" })`);
    sim.run(5 + sim.rand() * 20);
  }
  const dur = sim.t - t0;
  const parts = cs.map((c) => c.sent);
  const total = parts.reduce((a, b) => a + b, 0);
  const maxQ = Math.max(...cs.map((c) => c.maxQueue));
  const thr = cs.reduce((a, c) => a + c.throttled, 0);
  const top = cs.map((c, i) => [c.name, parts[i]]).sort((a, b) => b[1] - a[1]);
  // newcomer: empty SavedVariables, counts profiles + squads it holds (stored = verified) every 10 s for 10 min
  const cnt = `(function() local n = 0 for _ in pairs(NS.state.profiles) do n = n + 1 end for _ in pairs(NS.state.squads) do n = n + 1 end return n end)()`;
  const target = Number(cs[0].val(cnt)[0]);
  const nc = sim.client('Mb2');
  const tn = sim.t;
  nc.login();
  let t95 = null, t100 = null;
  const pendCnt = `(function() local n = 0 for _ in pairs((NS.state.p2p and NS.state.p2p.pend) or {}) do n = n + 1 end return n end)()`;
  const curve = [];   // measured: [s, held, pending ids] every 30 s, to see where the newcomer stalls
  for (let k = 0; k < 60 && t100 === null; k++) {
    sim.run(10);
    const h = Number(nc.val(cnt)[0]);
    if (k % 3 === 2) curve.push([Math.round(sim.t - tn), h, Number(nc.val(pendCnt)[0])]);
    if (t95 === null && h >= 0.95 * target) t95 = Math.round(sim.t - tn);
    if (h >= target) t100 = Math.round(sim.t - tn);
  }
  const tc = sim.t;
  const conv = sim.settle(900, 15);
  const tConv = Math.round(sim.t - tc);
  // v1.2 hello counters (nil on 1.0.1 / 1.1 builds): hellos heard and answered by each officer / the GM
  const hs = cs.slice(0, 3).map((c) => c.val('(NS.Sync and NS.Sync.stats and NS.Sync.stats.hellos) or -1, (NS.Sync and NS.Sync.stats and NS.Sync.stats.replied) or -1').map(Number));
  const ofShare = Math.max(...hs.map(([h, r]) => (h > 0 ? r / h : 1)));
  const share = top[0][1] / Math.max(1, total);
  check('caught Lua errors = 0', sim.errors() === 0, sim.errors() ? sim.errorText().slice(0, 300) : 0);
  check('model converged', conv, tConv + ' s');
  if (process.env.GSQ_S8G_AC !== '0') {   // GSQ_S8G_AC=0: reference runs (AC0) only measure
    check('AC2 no client sends > 15 % of the parts', share <= 0.15, top[0].join(':') + ' = ' + (100 * share).toFixed(1) + ' %');
    check('AC2 an officer answers <= 30 % of the hellos', ofShare <= 0.30, JSON.stringify(hs));
    check('AC3 newcomer 95 % in <= 240 s (no worse than 1.1)', t95 !== null && t95 <= 240, t95 + ' s');
    check('AC3 newcomer 100 % in <= 600 s', t100 !== null && t100 <= 600, t100 + ' s');
    check('AC5 parts total <= 1.1 + 20 % (6914)', total <= 6914, total);
    check('AC5 max queue <= 500', maxQ <= 500, maxQ);
    check('AC5 never throttled', thr === 0, thr);
  }
  return { pass: pass(), checks, metrics: { clients: cs.length, officerHellos: hs, seconds: Math.round(dur), records: n, partsTotal: total,
    partsTopClient: top.slice(0, 5).map((e) => e.join(':')).join(','), topShare: +(top[0][1] / Math.max(1, total)).toFixed(3),
    maxQueue: maxQ, throttled: thr, meanAll: +(total / cs.length / dur).toFixed(3), newcomerTarget: target,
    newcomerT95: t95, newcomerT100: t100, newcomerCurve: curve, convergeAfterNewcomer: tConv, ...sim.stats } };
}

// S18 (AF7, annex G dense case, BRO 8-nov 04:13): 10 member clients, >= 3 online at once (sliding window of 4), 3
// sessions each in three passes (in order, stride 3, in order). With >= 2 in-person certificates every key is reachable
// in this meeting graph (tests/sim: 100/100 pairs), so every authorial record (profile + presence of the 10 authors on
// the 10 clients = 200) and both squads (Mb1, Mb4 -> 20) must end VERIFIED, with 0 fake keys.
function S18(seed) {
  const sim = new Sim({ seed });
  const { check, checks, pass } = checker();
  makeGuild(sim, 1, 10);
  const names = []; for (let i = 1; i <= 10; i++) names.push('Mb' + i);
  const cs = names.map((n) => sim.client(n));
  const sessions = {}; let maxOnline = 0, minOverlap = 99;
  const squadIds = [];
  const OVER = 25 * 60, W = 4;
  const on = (c) => {
    c.login(); sessions[c.name] = (sessions[c.name] || 0) + 1;
    maxOnline = Math.max(maxOnline, sim.online().length);
    sim.run(20);
    c.run(`return A.SaveProfile({ note = ${luaStr('soy ' + c.name)} })`);
    if (sessions[c.name] === 1 && (c.name === 'Mb1' || c.name === 'Mb4')) {
      sim.run(5);
      c.run(`return A.CreateSquad({ name = ${luaStr('Squad ' + c.name)}, icon = 1, color = 1, border = 1, tags = {}, open = true })`);
      const id = c.val('A.MySquadId()')[0];
      if (id) squadIds.push(String(id));
    }
  };
  const pass1 = (order) => {
    for (let i = 0; i < order.length; i++) {
      on(cs[order[i]]);
      if (i >= W - 2) minOverlap = Math.min(minOverlap, sim.online().length);
      sim.run(OVER);
      if (i - (W - 1) >= 0) cs[order[i - (W - 1)]].logout();
    }
    for (const c of cs) if (c.online) c.logout();
  };
  pass1([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
  pass1([0, 3, 6, 9, 2, 5, 8, 1, 4, 7]);
  pass1([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
  const after = {}, sq = {};
  for (const c of cs) { c.login(); after[c.name] = holdings(sim, c, names); sq[c.name] = squadHoldings(c, squadIds); c.logout(); }
  const cells = Object.values(after).join('');
  const verified = cells.split('').filter((x) => x === 'v').length, total = cells.length;
  const sqCells = Object.values(sq).join('');
  const sqVerified = sqCells.split('').filter((x) => x === 'v').length, sqTotal = sqCells.length;
  check('>= 3 member clients online at once while they overlap', minOverlap >= 3, minOverlap);
  check('<= 3 sessions per client', Object.values(sessions).every((n) => n <= 3), JSON.stringify(sessions));
  check('2 squads created (Mb1, Mb4)', squadIds.length === 2, JSON.stringify(squadIds));
  const { keys, fakes, certHeld } = keyAudit(cs, names);
  check('AF7: 0 fake keys accepted', fakes.length === 0, JSON.stringify(fakes));
  check('AF7: 100 % of the authorial records VERIFIED on every client', total === 200 && verified === total, `${verified}/${total} ${JSON.stringify(after)}`);
  check('AF7: 100 % of the squads VERIFIED on every client', sqTotal === 20 && sqVerified === sqTotal, `${sqVerified}/${sqTotal} ${JSON.stringify(sq)}`);
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { keys, certHeld, verified, total, sqVerified, sqTotal, maxOnline, sessions, t: Math.round(sim.t), ...sim.stats } };
}

module.exports = { S18, S8g, S15, S16, S16b, S16c, S17, S1, S2, S3, S4, S5, S5one, S6, S7, S8, S9, S10, S11, S12, S13, S14 };
