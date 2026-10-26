// Guild Squads multi-client simulator (Node + fengari).
// Every client is a FULL addon instance (every file of GuildSquads.toc) in its own fengari state, with its own
// fake WoW API (tests/sim/fakewow.lua), SavedVariables, clock (skew) and timers. A shared bus carries GUILD /
// WHISPER addon messages as CHAT_MSG_ADDON with a "Name-Realm" sender: 50-800 ms latency (in order per
// sender->recipient pair, like the client), per-prefix throttle (burst 10, 1 msg/s; over it the send returns 3),
// optional loss, comms lockdown during encounters / BGs, login / logout / reload with persisted SavedVariables.
// Deterministic: one seeded PRNG drives latency, loss and the scenarios; each state's math.random is seeded too.
'use strict';
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

const ROOT = process.env.GSQ_ROOT || path.join(__dirname, '..', '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p));
const FAKE = fs.readFileSync(path.join(__dirname, 'fakewow.lua'));
const GLUE = fs.readFileSync(path.join(__dirname, 'client.lua'));
const TOC = read('GuildSquads.toc').toString('utf8').split(/\r?\n/).filter((l) => /\.lua$/.test(l.trim())).map((l) => l.trim().replace(/\\/g, '/'));
const SOURCES = {};
for (const f of TOC) SOURCES[f] = read(f);

// S10: the addon at another git ref (an older build) for mixed-version clients.
// Needs the git history (CI: actions/checkout with fetch-depth: 0).
function sourcesAt(ref) {
  const { execFileSync } = require('child_process');
  const git = (args) => execFileSync('git', args, { cwd: ROOT, maxBuffer: 64 << 20 });
  const toc = git(['show', ref + ':GuildSquads.toc']).toString('utf8').split(/\r?\n/).filter((l) => /\.lua$/.test(l.trim())).map((l) => l.trim().replace(/\\/g, '/'));
  const sources = {};
  for (const f of toc) sources[f] = git(['show', ref + ':' + f]);
  return { toc, sources, ref };
}

function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// ---- small fengari helpers -------------------------------------------------------------------------------
function pushVal(L, v) {
  if (v === null || v === undefined) lua.lua_pushnil(L);
  else if (typeof v === 'number') { if (Number.isInteger(v)) lua.lua_pushinteger(L, v); else lua.lua_pushnumber(L, v); }
  else if (typeof v === 'boolean') lua.lua_pushboolean(L, v);
  else if (v instanceof Uint8Array) lua.lua_pushstring(L, v);
  else lua.lua_pushstring(L, to_luastring(String(v)));
}
function getVal(L, i) {
  const t = lua.lua_type(L, i);
  if (t === lua.LUA_TNIL || t === lua.LUA_TNONE) return null;
  if (t === lua.LUA_TNUMBER) return lua.lua_tonumber(L, i);
  if (t === lua.LUA_TBOOLEAN) return lua.lua_toboolean(L, i);
  if (t === lua.LUA_TSTRING) return lua.lua_tolstring(L, i);   // raw bytes (Uint8Array)
  return lua.lua_typename(L, t);
}
const str = (u8) => (u8 instanceof Uint8Array ? Buffer.from(u8).toString('utf8') : u8);
function results(L, base) {
  const n = lua.lua_gettop(L) - base;
  const out = [];
  for (let i = 1; i <= n; i++) out.push(getVal(L, base + i));
  lua.lua_settop(L, base);
  return out;
}
function loadRun(L, src, name, args) {
  const base = lua.lua_gettop(L);
  if (lauxlib.luaL_loadbuffer(L, src instanceof Uint8Array ? src : to_luastring(src), null, to_luastring('@' + name)) !== lua.LUA_OK) {
    const e = lua.lua_tojsstring(L, -1); lua.lua_settop(L, base); throw new Error('load ' + name + ': ' + e);
  }
  for (const a of args || []) pushVal(L, a);
  if (lua.lua_pcall(L, (args || []).length, lua.LUA_MULTRET, 0) !== lua.LUA_OK) {
    const e = lua.lua_tojsstring(L, -1); lua.lua_settop(L, base); throw new Error(name + ': ' + e);
  }
  return results(L, base);
}
function callG(L, fname, ...args) {
  const base = lua.lua_gettop(L);
  lua.lua_getglobal(L, to_luastring(fname));
  for (const a of args) pushVal(L, a);
  if (lua.lua_pcall(L, args.length, lua.LUA_MULTRET, 0) !== lua.LUA_OK) {
    const e = lua.lua_tojsstring(L, -1); lua.lua_settop(L, base); throw new Error(fname + ': ' + e);
  }
  return results(L, base);
}
const luaStr = (s) => JSON.stringify(String(s)); // JSON string literal is a valid Lua string for ASCII/UTF-8 text

// ---- client ------------------------------------------------------------------------------------------------
class Client {
  constructor(sim, name, opts) {
    this.sim = sim; this.name = name; this.full = name + '-' + sim.realm;
    this.skew = opts.skew || 0; this.saved = opts.saved || null; this.online = false;
    this.guild = opts.guild === undefined ? sim.guild : opts.guild;
    this.next = null; this.bucket = {}; this.errorsBefore = 0;
    this.sent = 0; this.sentAt = []; this.throttled = 0; this.maxQueue = 0;
    this.code = opts.code || null;                // { toc, sources } of another version (sourcesAt)
  }
  login() {
    const sim = this.sim;
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    this.L = L;
    const seed = Math.floor(sim.rand() * 2147483647);
    loadRun(L, `math.randomseed(${seed}); SIM_T = ${sim.t}; SIM_CFG = { name = ${luaStr(this.name)}, realm = ${luaStr(sim.realm)}, ` +
      `guild = ${this.guild ? luaStr(this.guild) : 'nil'}, skew = ${this.skew}, epoch = ${sim.epoch}, uptime0 = ${1000 + Math.floor(sim.rand() * 5000)} }`, 'cfg');
    lua.lua_pushjsfunction(L, (Ls) => {   // SIM_canSend(prefix) -> 0 | 3 (per-prefix throttle like the client)
      const prefix = str(lua.lua_tolstring(Ls, 1));
      lua.lua_pushinteger(Ls, this.takeToken(prefix));
      return 1;
    });
    lua.lua_setglobal(L, to_luastring('SIM_canSend'));
    loadRun(L, FAKE, 'tests/sim/fakewow.lua');
    this.setRoster();
    if (this.saved) loadRun(L, Buffer.concat([Buffer.from('GuildSquadsDB = (function() '), Buffer.from(this.saved), Buffer.from(' end)()')]), 'SavedVariables');
    loadRun(L, 'SIM_ns = {}', 'ns');
    lua.lua_getglobal(L, to_luastring('SIM_ns'));
    const nsRef = lauxlib.luaL_ref(L, lua.LUA_REGISTRYINDEX);
    const toc = this.code ? this.code.toc : TOC, srcs = this.code ? this.code.sources : SOURCES;
    for (const f of toc) {
      const base = lua.lua_gettop(L);
      if (lauxlib.luaL_loadbuffer(L, srcs[f], null, to_luastring('@' + f)) !== lua.LUA_OK) throw new Error(lua.lua_tojsstring(L, -1));
      lua.lua_pushstring(L, to_luastring('GuildSquads'));
      lua.lua_rawgeti(L, lua.LUA_REGISTRYINDEX, nsRef);
      if (lua.lua_pcall(L, 2, 0, 0) !== lua.LUA_OK) throw new Error(f + ': ' + lua.lua_tojsstring(L, -1));
      lua.lua_settop(L, base);
    }
    loadRun(L, GLUE, 'tests/sim/client.lua');
    this.online = true;
    this.bucket = {};
    sim.markRoster();
    this.fire('ADDON_LOADED', 'GuildSquads');
    this.fire('PLAYER_LOGIN');
    this.fire('PLAYER_ENTERING_WORLD', true, false);
    this.fire('GUILD_ROSTER_UPDATE');
  }
  logout() {
    if (!this.online) return;
    this.fire('PLAYER_LOGOUT');
    this.saved = str(callG(this.L, 'SIM_saveVars')[0]);
    this.errorsBefore += this.errors();
    this.online = false; this.L = null; this.next = null;
    this.sim.markRoster();
  }
  reload() { this.logout(); this.login(); }
  takeToken(prefix) {
    const t = this.sim.t;
    const b = this.bucket[prefix] || (this.bucket[prefix] = { tokens: this.sim.throttle.burst, at: t });
    b.tokens = Math.min(this.sim.throttle.burst, b.tokens + (t - b.at) * this.sim.throttle.rate);
    b.at = t;
    if (b.tokens < 1) { this.throttled++; return 3; }
    b.tokens -= 1;
    return 0;
  }
  setRoster() {
    if (!this.L) return;
    const rows = this.sim.roster.map((r) => `{${luaStr(r.name + '-' + this.sim.realm)},${r.rank},${r.level || 60},"WARRIOR",${this.sim.isOnline(r.name) ? 'true' : 'false'}}`);
    loadRun(this.L, 'SIM_ROSTER = {' + rows.join(',') + '}', 'roster');
  }
  // run Lua code inside this client (has A, NS, SIM_* globals)
  run(code) { const r = loadRun(this.L, code, 'sim:' + this.name).map(str); this.after(); return r; }
  fire(ev, ...args) { callG(this.L, 'SIM_step', this.sim.t); callG(this.L, 'SIM_fire', ev, ...args); this.after(); }
  step() { callG(this.L, 'SIM_step', this.sim.t); this.after(); }
  after() {
    if (!this.L) return;
    const L = this.L;
    for (;;) {
      const [prefix, msg, channel, target] = callG(L, 'SIM_pop');
      if (prefix === null) break;
      this.sent++; this.sentAt.push(this.sim.t);
      this.sim.post(this, prefix, msg, str(channel), str(target));
    }
    for (;;) {
      const [text, channel] = callG(L, 'SIM_popChat');
      if (text === null) break;
      this.sim.chat.push({ from: this.full, text: str(text), channel: str(channel), t: this.sim.t });
    }
    const q = callG(L, 'SIM_queue')[0];
    if (q > this.maxQueue) this.maxQueue = q;
    this.next = callG(L, 'SIM_next')[0];
  }
  hash() { return str(callG(this.L, 'SIM_modelHash')[0]); }
  model() { return str(callG(this.L, 'SIM_modelText')[0]); }
  errors() { return this.L ? callG(this.L, 'SIM_errorCount')[0] : 0; }
  errorText() { return this.L ? str(callG(this.L, 'SIM_errorText')[0]) : ''; }
  totalErrors() { return this.errorsBefore + this.errors(); }
  val(expr) { return this.run('return ' + expr); }
}

// ---- simulation --------------------------------------------------------------------------------------------
class Sim {
  constructor(opts) {
    opts = opts || {};
    this.seed = opts.seed || 1;
    this.rand = mulberry32(this.seed);
    this.realm = opts.realm || 'Realm';
    this.guild = opts.guild || 'Forever';
    this.epoch = opts.epoch || 1795000000;      // run second 0 in server time
    this.t = 0;
    this.loss = opts.loss || 0;
    this.latency = opts.latency || [0.05, 0.8];
    this.throttle = opts.throttle || { burst: 10, rate: 1 };
    this.roster = [];                             // { name, rank, level }
    this.clients = {};
    this.queue = [];                              // pending deliveries, sorted by t then seq
    this.seq = 0;
    this.lastAt = {};                             // sender>recipient -> last delivery time (order per pair)
    this.chat = [];
    this.stats = { posted: 0, delivered: 0, lost: 0 };
    this.rosterDirty = false;
  }
  addMember(name, rank, level) { this.roster.push({ name, rank, level: level || 60 }); this.markRoster(); }
  setRank(name, rank) { for (const r of this.roster) if (r.name === name) r.rank = rank; this.markRoster(); }
  removeMember(name) { this.roster = this.roster.filter((r) => r.name !== name); this.markRoster(); }
  isOnline(name) { const c = this.clients[name]; return !!(c && c.online); }
  markRoster() { this.rosterDirty = true; }
  client(name, opts) {
    const c = new Client(this, name, opts || {});
    this.clients[name] = c;
    return c;
  }
  online() { return Object.values(this.clients).filter((c) => c.online); }
  post(from, prefix, msg, channel, target) {
    this.stats.posted++;
    const targets = [];
    if (channel === 'GUILD') { for (const c of this.online()) if (c !== from && c.guild && c.guild === from.guild) targets.push(c); }
    else if (channel === 'WHISPER') {
      const short = target.replace(/-.*$/, '');
      const c = this.clients[short];
      if (c && c.online) targets.push(c);
    }
    for (const to of targets) {
      if (this.loss > 0 && this.rand() < this.loss) { this.stats.lost++; continue; }
      const key = from.name + '>' + to.name;
      let at = this.t + this.latency[0] + this.rand() * (this.latency[1] - this.latency[0]);
      if (this.lastAt[key] && at < this.lastAt[key]) at = this.lastAt[key];
      this.lastAt[key] = at;
      this.queue.push({ t: at, seq: ++this.seq, to, toGen: to.L, prefix, msg, channel, sender: from.full });
    }
    this.queue.sort((a, b) => a.t - b.t || a.seq - b.seq);
  }
  pushRoster() {
    if (!this.rosterDirty) return;
    this.rosterDirty = false;
    for (const c of this.online()) { c.setRoster(); c.fire('GUILD_ROSTER_UPDATE'); }
  }
  // advance simulated time to `until` (seconds), processing deliveries and timers in order
  runUntil(until) {
    for (let guard = 0; guard < 5e6; guard++) {
      this.pushRoster();
      let next = until, who = null;
      if (this.queue.length && this.queue[0].t < next) next = this.queue[0].t;
      for (const c of this.online()) if (c.next !== null && c.next < next) { next = c.next; who = c; }
      if (next >= until && !(this.queue.length && this.queue[0].t <= until)) { this.t = Math.max(this.t, until); break; }
      this.t = Math.max(this.t, next);
      if (this.queue.length && this.queue[0].t <= this.t) {
        const d = this.queue.shift();
        if (d.to.online && d.to.L === d.toGen) { this.stats.delivered++; d.to.fire('CHAT_MSG_ADDON', d.prefix, d.msg, d.channel, d.sender); }
      } else if (who) who.step();
      else for (const c of this.online()) if (c.next !== null && c.next <= this.t) c.step();
    }
  }
  run(seconds) { this.runUntil(this.t + seconds); }
  // run until every online client has the same model hash (checked every `every` s), max `max` s
  settle(max, every) {
    every = every || 10;
    const end = this.t + (max || 600);
    while (this.t < end) {
      this.run(every);
      if (this.converged()) return true;
    }
    return this.converged();
  }
  hashes() { const o = {}; for (const c of this.online()) o[c.name] = c.hash(); return o; }
  converged() { const h = Object.values(this.hashes()); return h.length > 0 && h.every((x) => x === h[0]); }
  errors() { let n = 0; for (const c of Object.values(this.clients)) n += c.totalErrors(); return n; }
  errorText() { return Object.values(this.clients).map((c) => c.errorText()).filter(Boolean).join('\n'); }
}

module.exports = { Sim, luaStr, mulberry32, sourcesAt };
