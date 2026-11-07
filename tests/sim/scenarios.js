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
  check('mean msgs/s per client (busiest) <= 1.05 (client throttle 1/s; Comm drains at 1/s)', mean <= 1.05, mean.toFixed(3));
  check('peak in any 1 s window <= 10 (throttle burst)', peak1 <= 10, peak1);
  check('sends refused by the throttle = 0', thr === 0, thr);
  check('send queue never above X = 500', maxQ <= 500, maxQ);
  check('model converged', sim.settle(900, 15));
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { clients: cs.length, seconds: Math.round(dur), meanAll: +avgAll.toFixed(3), meanBusiest: +mean.toFixed(3), peak1s: peak1, peak10s: +peak10.toFixed(2), maxQueue: maxQ, throttled: thr, records: n } };
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
  const refused = news.filter((c) => c !== forger).map((c) => Number(c.val('NS.Sync.stats.relayRefused')[0]));
  check('the GM-impersonating copy was refused as a relay', refused.every((n) => n >= 1), refused.slice(0, 5).join(','));
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
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { arrived, total, verified, sqArrived, sqTotal, sqVerified, after2, after3, sq2, sq3, sessions, t: Math.round(sim.t), ...sim.stats } };
}
function S11(seed) { return s11core(seed, false); }
function S15(seed) { return s11core(seed, true); }

// S12 (AC2 + AC4): a forged profile of an offline author. One malicious relayer -> unverified on every client and never
// verified; a second colluder -> verified by quorum. The author logs in: its version wins, its client repudiates the
// fake, the fake disappears from every client and both relayers are listed in /gsq diag.
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
  check('a second colluder: verified by quorum', v2.every((x) => x.startsWith('falso/')), v2.join(','));
  au.login();
  sim.run(300);
  const all = [au, y, z, c1, c2];
  const v3 = all.map(view);
  check('the author logs in: the real version on every client, the fake gone (stored and pending)', v3.every((x) => x === 'real/nil'), v3.join(','));
  const rep = c1.val('NS.DiagGlue.Report()')[0];
  const line = (rep.match(/p2p pend=[^\n|]*/) || [''])[0];
  check('/gsq diag lists both relayers with a repudiation', line.includes('Mb2-Realm:1') && line.includes('Mb3-Realm:1'), line);
  const nRep = all.map((c) => c.val('(function() local n = 0 for _ in pairs(NS.state.repudiates or {}) do n = n + 1 end return n end)()')[0]);
  check('the repudiate reached every client', nRep.every((n) => Number(n) >= 1), nRep.join(','));
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { diag: line, t: Math.round(sim.t), ...sim.stats } };
}

// S16 (v1.2 AC4): poisoning of authority records. Mb2, then Mb3 too, forge a GM `settings` (bench 0, squads off) and
// Mb1's squad (renamed) while the GM and Mb1 are offline. 1 relayer and QUORUM_AUTH - 1 = 2 relayers: never verified
// on any honest client. A flood of 5,000 fake pending records from one relayer stays capped at 200 and does not evict
// a legitimate pending version. The GM logs in -> repudiates the settings, Mb1 logs in -> repudiates the squad: both
// fakes gone from every client and both relayers listed in /gsq diag.
function S16(seed) {
  const sim = new Sim({ seed });
  const { check, checks, pass } = checker();
  makeGuild(sim, 1, 8);
  const [gm, cap] = [sim.client('Gm'), sim.client('Mb1')];
  const [y, z] = [sim.client('Mb2'), sim.client('Mb3')];
  const honest = ['Mb4', 'Mb5', 'Mb6'].map((n) => sim.client(n));
  const pub = sim.client('Mb7');
  for (const c of [gm, cap, ...honest]) { c.login(); sim.run(5); }
  check('GM settings written', gmSettings(gm));
  sim.run(20);
  cap.run('return A.CreateSquad({ name = "Lobos", icon = 1, color = 1, border = 1, tags = {}, open = true })');
  const SID = String(cap.val('A.MySquadId()')[0]);
  sim.run(60);
  gm.logout(); cap.logout();
  const GM = full(sim, 'Gm'), CAP = full(sim, 'Mb1');
  const FTS = sim.epoch + Math.round(sim.t) + 200;
  const fakeSet = `{ k = "settings", id = "settings", a = ${luaStr(GM)}, ts = ${FTS}, sq = 9001, d = { squadsEnabled = false, bench = 0, minCreateRank = 9, officerRanks = { 1 }, banned = {}, compEnabled = true } }`;
  const fakeSq = `{ k = "squad", id = ${luaStr(SID)}, a = ${luaStr(CAP)}, ts = ${FTS}, sq = 9002, d = { name = "Hackeado", captain = ${luaStr(CAP)}, members = { ${luaStr(CAP)} }, bench = {}, icon = 1, color = 1, border = 1, tags = {}, open = true, approved = true } }`;
  const forge = `NS.Comm.Send("D", { r = { ${fakeSet}, ${fakeSq} } })`;
  for (const c of [y, z]) { c.login(); sim.run(5); }
  sim.run(30);
  const view = (c) => c.val(`(function() local s = NS.Model.settingsOf(NS.state); local q = NS.state.squads[${luaStr(SID)}]
    local us = NS.P2P.unverified(NS.state, "settings", "settings"); local uq = NS.P2P.unverified(NS.state, "squad", ${luaStr(SID)})
    return tostring(s.bench) .. "/" .. (q and q.d.name or "nil") .. "|" .. (us and tostring(us.r.d.bench) or "nil") .. "/" .. (uq and uq.r.d.name or "nil") end)()`)[0];
  y.run(forge); sim.run(1); y.run(forge);
  sim.run(120);
  const v1 = honest.map(view);
  check('one malicious relayer: the fakes are pending on every honest client, the real ones stay', v1.every((x) => x === '2/Lobos|0/Hackeado'), v1.join(','));
  sim.run(1200);
  const v1b = honest.map(view);
  check('20 min later, still never verified (1 relayer)', v1b.every((x) => x.startsWith('2/Lobos|')), v1b.join(','));
  z.run(forge);
  sim.run(600);
  const v2 = honest.map(view);
  check('QUORUM_AUTH - 1 = 2 colluders: still never verified', v2.every((x) => x.startsWith('2/Lobos|')), v2.join(','));
  // a legitimate pending version (Mb7's profile relayed by one honest member), then 5,000 fakes from Mb2 alone
  pub.login(); sim.run(10); pub.run('return A.SaveProfile({ note = "legit" })'); sim.run(30); pub.logout();
  const PUB = full(sim, 'Mb7'), Y = full(sim, 'Mb2');
  const h0 = honest[0];
  const legitIn = h0.val(`(function() local p = NS.state.profiles[${luaStr(PUB)}]; return p and p.d.note or "nil" end)()`)[0];
  const t0 = sim.epoch + Math.round(sim.t);
  const flood = h0.val(`(function()
    local X = NS.P2P
    -- the honest client drops what it got live from Mb7 and gets it again relayed by Mb4's neighbour Mb5 only
    local real = NS.state.profiles[${luaStr(PUB)}]
    NS.state.profiles[${luaStr(PUB)}] = nil
    local legit = { k = real.k, id = real.id, a = real.a, ts = real.ts, sq = real.sq, d = real.d }
    NS.Sync.Apply(legit, ${luaStr(full(sim, 'Mb5'))})
    for i = 1, 5000 do
      NS.Sync.Apply({ k = "squad", id = ${luaStr(CAP)} .. ":" .. (1000 + i), a = ${luaStr(CAP)}, ts = ${t0} - i, sq = 100 + i,
        d = { name = "F" .. i, captain = ${luaStr(CAP)}, members = { ${luaStr(CAP)} }, bench = {}, icon = 1, color = 1, border = 1, tags = {}, open = true, approved = true } }, ${luaStr(Y)})
    end
    local byY = 0
    for _, byId in pairs(NS.state.p2p.pend) do for _, e in pairs(byId) do if e.by[${luaStr(Y)}] then byY = byY + 1 end end end
    local u = X.unverified(NS.state, "profile", ${luaStr(PUB)})
    return byY .. "|" .. (u and u.r.d.note or "nil") .. "|" .. X.stats(NS.state, 0).pend
  end)()`)[0];
  const [byY, legitAfter] = String(flood).split('|');
  check('Mb7 profile arrived live before the flood', legitIn === 'legit', legitIn);
  check('5,000 fakes from one relayer: at most 200 pending by him', Number(byY) <= 200, flood);
  check('the legitimate pending version survives the flood', legitAfter === 'legit', flood);
  gm.login(); sim.run(300);
  cap.login(); sim.run(300);
  const all = [gm, cap, y, z, ...honest];
  const v3 = all.map(view);
  check('GM and Mb1 log in: real versions everywhere, both fakes gone (stored and pending)', v3.every((x) => x === '2/Lobos|nil/nil'), v3.join(','));
  const rep = honest[1].val('NS.DiagGlue.Report()')[0];
  const line = (rep.match(/p2p pend=[^\n|]*/) || [''])[0];
  check('/gsq diag lists both relayers', line.includes('Mb2-Realm:') && line.includes('Mb3-Realm:'), line);
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { sid: SID, flood, diag: line, t: Math.round(sim.t), ...sim.stats } };
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

// S14 (AC7): 2 clients on v1.0.1 (GSQ_REF) among 6 on v1.1, no officers online. The old clients get relays, presence
// and repudiate records they do not know: no Lua error, and their own records still reach everybody.
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
  // a forged record and its repudiation travel the guild too
  const M1 = full(sim, 'Mb1');
  cs[2].run(`NS.Comm.Send("D", { r = { { k = "profile", id = ${luaStr(M1)}, a = ${luaStr(M1)}, ts = GetServerTime() + 200, sq = 555, d = { note = "falso" } } } })`);
  sim.run(60);
  cs[0].logout(); sim.run(5); cs[0].login();
  sim.run(600);
  const olds = cs.filter((c) => oldNames.has(c.name)), news = cs.filter((c) => !oldNames.has(c.name));
  const bad = olds.map((c) => Number(c.val('NS.Sync.stats.bad')[0]));
  check('old clients received and dropped the unknown kinds (presence / repudiate)', bad.every((b) => b > 0), bad.join(','));
  const oldNotes = news.map((c) => olds.map((o) => c.val(`(function() local p = NS.state.profiles[${luaStr(o.full)}]; return p and p.d.note or "nil" end)()`)[0]).join('+'));
  check('every v1.1 client holds the old clients\' own profiles', oldNotes.every((x) => x === 'soy Mb2+soy Mb5'), oldNotes.join(','));
  const newOnOld = olds.map((o) => news.map((c) => o.val(`(function() local p = NS.state.profiles[${luaStr(c.full)}]; return p and p.d.note or "nil" end)()`)[0]).filter((x) => x.startsWith('soy ')).length);
  check('the old clients hold the v1.1 authors\' own profiles (live)', newOnOld.every((n) => n === news.length), newOnOld.join(','));
  const fake = olds.map((o) => o.val(`(function() local p = NS.state.profiles[${luaStr(M1)}]; return p and p.d.note or "nil" end)()`)[0]);
  check('the forged relay was refused by the old clients too', fake.every((x) => x === 'soy Mb1'), fake.join(','));
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { oldBad: bad, ref: REF, ...sim.stats } };
}

// S17 (v1.2 AC6): S14 widened. 12 clients: 8 on v1.2 (GM, Of1, Mb1, Mb3, Mb7-Mb10); Mb4, Mb6 on v1.1 (GSQ_REF11, default
// 636e545); Mb2, Mb5 on v1.0.1 (GSQ_REF, default 406029a). Everyone writes a profile. Then, with Mb2, Mb4 and Mb7 offline,
// the GM changes the settings (bench 1) and the GM and the officer log out. Mb2, Mb4 and Mb7 come back while only
// members are online: the v1.2 members relay the new settings to Mb7 (quorum), and an authority record relayed by a
// member must never reach a client with p2 < 2 (it would count it as `relay` refused). Last, Of1 logs in: the old
// clients get the settings from the officer. 0 Lua errors.
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
  for (const c of all) { c.login(); sim.run(2 + sim.rand() * 3); }
  sim.run(20);
  check('GM settings written', gmSettings(cs.Gm));
  sim.run(30);
  for (const c of all) { c.run(`return A.SaveProfile({ note = ${luaStr('soy ' + c.name)} })`); sim.run(2); }
  sim.run(120);
  const olds = ['Mb2', 'Mb5', 'Mb4', 'Mb6'];
  // relay refusals counted from here on (a re-login starts a fresh Lua state, the counter with it); the spy keeps kind<sender
  const spy = `NS.SIM_REF = {} local ap = NS.Sync.Apply NS.Sync.Apply = function(rec, sender, ...) local ok, why = ap(rec, sender, ...)
    if not ok and why == "relay" then NS.SIM_REF[#NS.SIM_REF + 1] = tostring(rec.k) .. "<" .. tostring(sender) end return ok, why end`;
  const base = {};
  const arm = (n) => { cs[n].run(spy); base[n] = Number(cs[n].val('NS.Sync.stats.relayRefused')[0]); };
  for (const n of ['Mb2', 'Mb4', 'Mb7']) cs[n].logout();
  arm('Mb5'); arm('Mb6');
  sim.run(10);
  check('GM changes the settings (bench 1)', cs.Gm.run(`return A.SaveSettings({ ${SETTINGS.replace('bench = 2', 'bench = 1')} })`)[0] === true);
  sim.run(60);
  const bench = (c) => c.val('(function() local s = NS.state.settings; return s and s.d and tostring(s.d.bench) or "nil" end)()')[0];
  const benchAfter = names.filter((n) => !['Mb2', 'Mb4', 'Mb7'].includes(n)).map((n) => `${n}:${bench(cs[n])}`).join(',');
  check('the clients online at the change hold bench 1 (live from the GM)', !/:[^1,]/.test(benchAfter), benchAfter);
  cs.Gm.logout(); cs.Of1.logout();
  sim.run(10);
  for (const n of ['Mb2', 'Mb4', 'Mb7']) { cs[n].login(); if (ver[n]) arm(n); sim.run(3); }
  sim.run(300);
  // authorial kinds relayed by members (v1.1, M.P2P_KINDS) are refused by a 1.0.1 client as before (S14); authority kinds
  // relayed by a member must reach no old client at all
  const AUTHORIAL = new Set(['profile', 'rsvp', 'witness', 'presence', 'reject', 'repudiate']);
  const refused = olds.map((n) => Number(cs[n].val('NS.Sync.stats.relayRefused')[0]) - base[n]);
  const refusedBy = olds.map((n) => n + '=' + cs[n].val('table.concat(NS.SIM_REF, " ")')[0]);
  const authRef = olds.map((n) => cs[n].val('table.concat(NS.SIM_REF, " ")')[0].split(' ').filter((x) => x && !AUTHORIAL.has(x.split('<')[0])));
  check('no authority record relayed by a member reached a client with p2 < 2 (members only online)',
    authRef.every((l) => l.length === 0), olds.map((n, i) => `${n}=${authRef[i].join(' ') || '-'}`).join(' | '));
  check('the v1.1 clients refused no relay at all', [2, 3].every((i) => refused[i] === 0), refusedBy.join(' | '));
  const mb7 = bench(cs.Mb7);   // measured, not a criterion: the quorum of 3 needs 3 distinct relayers of the cube
  cs.Of1.login();
  sim.run(30);
  // the old clients ask again (their next session): the officer serves them the settings
  for (const n of ['Mb2', 'Mb4']) { cs[n].reload(); sim.run(3); }
  sim.run(300);
  const ob = olds.map((n) => `${n}:${bench(cs[n])}`);
  check('the old clients got the new settings from the officer', olds.every((n) => bench(cs[n]) === '1'), ob.join(','));
  const online = all.filter((c) => c.name !== 'Gm');
  const own = (c, o) => c.val(`(function() local p = NS.state.profiles[${luaStr(o.full)}]; return p and p.d.note or "nil" end)()`)[0];
  const miss = [];
  for (const o of olds.map((n) => cs[n])) for (const c of online) if (own(o, c) !== 'soy ' + c.name) miss.push(`${o.name}<-${c.name}:${own(o, c)}`);
  check('every old client holds the profile of every client online (theirs live, the rest relayed)', miss.length === 0, miss.slice(0, 8).join(','));
  const missNew = [];
  for (const n of ['Mb1', 'Mb3', 'Mb7']) for (const o of olds) if (own(cs[n], cs[o]) !== 'soy ' + o) missNew.push(`${n}<-${o}:${own(cs[n], cs[o])}`);
  check('every v1.2 member holds the old clients\' profiles', missNew.length === 0, missNew.slice(0, 8).join(','));
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { ref: REF, ref11: REF11, refused, refusedBy, mb7BenchMembersOnly: mb7, ...sim.stats } };
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
  for (let k = 0; k < 60 && t100 === null; k++) {
    sim.run(10);
    const h = Number(nc.val(cnt)[0]);
    if (t95 === null && h >= 0.95 * target) t95 = Math.round(sim.t - tn);
    if (h >= target) t100 = Math.round(sim.t - tn);
  }
  const tc = sim.t;
  const conv = sim.settle(900, 15);
  const tConv = Math.round(sim.t - tc);
  // v1.2 hello counters (nil on 1.0.1 / 1.1 builds): hellos heard and answered by each officer / the GM
  const hs = cs.slice(0, 3).map((c) => c.val('Sync.stats.hellos or -1, Sync.stats.replied or -1').map(Number));
  const ofShare = Math.max(...hs.map(([h, r]) => (h > 0 ? r / h : 1)));
  const share = top[0][1] / Math.max(1, total);
  check('caught Lua errors = 0', sim.errors() === 0, sim.errors() ? sim.errorText().slice(0, 300) : 0);
  check('model converged', conv, tConv + ' s');
  if (process.env.GSQ_S8G_AC !== '0') {   // GSQ_S8G_AC=0: reference runs (AC0) only measure
    check('AC2 no client sends > 15 % of the parts', share <= 0.15, top[0].join(':') + ' = ' + (100 * share).toFixed(1) + ' %');
    check('AC2 an officer answers <= 30 % of the hellos', ofShare <= 0.30, JSON.stringify(hs));
    check('AC3 newcomer 95 % in <= 180 s', t95 !== null && t95 <= 180, t95 + ' s');
    check('AC3 newcomer 100 % in <= 600 s', t100 !== null && t100 <= 600, t100 + ' s');
    check('AC5 parts total <= 1.1 + 20 % (6914)', total <= 6914, total);
    check('AC5 max queue <= 500', maxQ <= 500, maxQ);
    check('AC5 never throttled', thr === 0, thr);
  }
  return { pass: pass(), checks, metrics: { clients: cs.length, officerHellos: hs, seconds: Math.round(dur), records: n, partsTotal: total,
    partsTopClient: top.slice(0, 5).map((e) => e.join(':')).join(','), topShare: +(top[0][1] / Math.max(1, total)).toFixed(3),
    maxQueue: maxQ, throttled: thr, meanAll: +(total / cs.length / dur).toFixed(3), newcomerTarget: target,
    newcomerT95: t95, newcomerT100: t100, convergeAfterNewcomer: tConv, ...sim.stats } };
}

module.exports = { S8g, S15, S16, S17, S1, S2, S3, S4, S5, S5one, S6, S7, S8, S9, S10, S11, S12, S13, S14 };
