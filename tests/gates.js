// Static gates over the addon (no WoW client needed):
//   1. SYNTAX  every .lua file parses as Lua 5.1 (luaparse).
//   2. API     every called global function / namespaced function (X(), C_Foo.Bar(), string.x()) must be in the
//              vendored 16001 API list (tests/tools/api-16001.txt) or be guarded (ns.apiFn("X"), `if X then`,
//              `X and X(`, `if not X then return end`). Non-called globals (constants, frames, tables) must be in
//              the API list, defined by the addon, or in REF_ALLOW below.
//   3. TOC     Interface 16001, SavedVariables declared, every listed file exists (case-exact, backslash paths),
//              every addon .lua outside tests/ is listed.
//   4. LOCALE  key parity: every L.KEY assigned in Locales/enUS.lua is assigned in Locales/esES.lua and vice versa.
// Usage: NODE_PATH=/tmp/gsq-node/node_modules node tests/gates.js [path/to/Probe.lua]
// The optional probe file only adds names (e.g. checked in game by GuildSquadsProbe) to the known list.
const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');
// GSQ_GATES_ROOT lets tests/tools/gates-selftest.js run the gate over a temporary fixture tree.
const root = process.env.GSQ_GATES_ROOT ? path.resolve(process.env.GSQ_GATES_ROOT) : path.resolve(__dirname, '..');
const rel = (f) => path.relative(root, f).split(path.sep).join('/');
let failures = 0;
const fail = (msg) => { failures++; console.log('FAIL ' + msg); };

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === 'node_modules' || e.name.startsWith('.')) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out); else if (p.endsWith('.lua')) out.push(p);
  }
  return out;
}
const isAddonFile = (f) => !rel(f).startsWith('tests/') && !rel(f).startsWith('docs/');

// ---------- known API names (vendored list + optional probe) ----------
const API = new Set(fs.readFileSync(path.join(__dirname, 'tools', 'api-16001.txt'), 'utf8')
  .split('\n').map((s) => s.trim()).filter((s) => s && !s.startsWith('#')));
for (const n of [...API]) if (n.includes('.')) API.add(n.split('.')[0]); // namespaces: C_Timer, string, bit, ...
const probePath = process.argv[2];
if (probePath && fs.existsSync(probePath)) {
  for (const m of fs.readFileSync(probePath, 'utf8').matchAll(/[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?/g)) API.add(m[0]);
}

// Calls allowed although they are not in the API list. Each entry needs a reason.
// (math.randomseed is not in the list; it is guarded with `if math.randomseed then`.)
const CALL_ALLOW = new Map([]);
// Non-called globals (constants, frames, tables, Lua 5.1 builtins) not in the API list. Each entry needs a reason.
const REF_ALLOW = new Map([
  ['_G', 'Lua global table'],
  ['RAID_CLASS_COLORS', 'FrameXML constant table (Constants.lua)'],
  ['UIParent', 'FrameXML root frame'],
  ['GameTooltip', 'FrameXML tooltip frame'],
  ['DEFAULT_CHAT_FRAME', 'FrameXML chat frame'],
  ['Minimap', 'FrameXML minimap frame'],
  ['SlashCmdList', 'FrameXML slash command table'],
  ['UISpecialFrames', 'FrameXML table of ESC-closable frames'],
  ['StaticPopupDialogs', 'FrameXML popup definitions table'],
  ['STANDARD_TEXT_FONT', 'FrameXML font constant'],
  ['GameFontNormal', 'FrameXML font object'],
  ['GameFontHighlight', 'FrameXML font object'],
  ['GameFontHighlightSmall', 'FrameXML font object'],
  ['GameFontNormalSmall', 'FrameXML font object'],
  ['GameFontNormalLarge', 'FrameXML font object'],
  ['GameFontDisable', 'FrameXML font object'],
  ['GameFontDisableSmall', 'FrameXML font object'],
  ['ChatFontNormal', 'FrameXML font object'],
  ['NORMAL_FONT_COLOR', 'FrameXML color constant'],
  ['HIGHLIGHT_FONT_COLOR', 'FrameXML color constant'],
  ['GRAY_FONT_COLOR', 'FrameXML color constant'],
  ['RED_FONT_COLOR', 'FrameXML color constant'],
  ['GREEN_FONT_COLOR', 'FrameXML color constant'],
  ['YES', 'FrameXML GlobalStrings'],
  ['NO', 'FrameXML GlobalStrings'],
  ['OKAY', 'FrameXML GlobalStrings'],
  ['CANCEL', 'FrameXML GlobalStrings'],
  ['ACCEPT', 'FrameXML GlobalStrings'],
  ['CLOSE', 'FrameXML GlobalStrings'],
  ['BINDING_HEADER_GUILDSQUADS', 'addon binding label (Bindings.xml)'],
  ['BINDING_NAME_GUILDSQUADS_TOGGLE', 'addon binding label (Bindings.xml)'],
]);

// ---------- AST helpers ----------
function dotted(n) { // Identifier / a.b.c (non-local root) -> "a.b.c", else null
  if (!n) return null;
  if (n.type === 'Identifier') return n.isLocal ? null : n.name;
  if (n.type === 'MemberExpression' && n.indexer === '.') { const b = dotted(n.base); return b && b + '.' + n.identifier.name; }
  return null;
}
function mentions(n, name) { // does expression n reference global `name` (or a prefix of it, e.g. C_Timer for C_Timer.After)?
  let hit = false;
  const v = (x) => {
    if (hit || !x || typeof x !== 'object') return;
    if (Array.isArray(x)) { x.forEach(v); return; }
    const d = dotted(x);
    if (d && (d === name || name.startsWith(d + '.'))) { hit = true; return; }
    if (x.type === 'StringLiteral') { const s = x.raw.slice(1, -1); if (s === name) { hit = true; return; } }
    for (const k of Object.keys(x)) if (k !== 'loc' && k !== 'range') v(x[k]);
  };
  v(n);
  return hit;
}
const returnsEarly = (body) => body.some((s) => s.type === 'ReturnStatement' || s.type === 'BreakStatement');

// ---------- 1+2: syntax and API gates ----------
const files = walk(root);
let bad = 0;
const ownGlobals = new Set(['ns', 'GuildSquadsDB']);
const parsed = [];
for (const f of files) {
  let ast;
  try { ast = luaparse.parse(fs.readFileSync(f, 'utf8'), { luaVersion: '5.1', scope: true, locations: true }); } catch (e) { bad++; fail('SYNTAX ' + rel(f) + ' ' + e.message); continue; }
  if (!isAddonFile(f)) continue;
  parsed.push([f, ast]);
  // globals the addon defines itself: `X = ...` and `function X()` at any depth
  const v = (n) => {
    if (!n || typeof n !== 'object') return;
    if (Array.isArray(n)) { n.forEach(v); return; }
    if (n.type === 'AssignmentStatement') n.variables.forEach((t) => {
      if (t.type === 'Identifier' && !t.isLocal) ownGlobals.add(t.name);
      else { const d = dotted(t); if (d) ownGlobals.add(d); } // e.g. SlashCmdList.GUILDSQUADS = ...
    });
    if (n.type === 'FunctionDeclaration' && n.identifier && n.identifier.type === 'Identifier' && !n.identifier.isLocal) ownGlobals.add(n.identifier.name);
    for (const k of Object.keys(n)) if (k !== 'loc' && k !== 'range') v(n[k]);
  };
  v(ast.body);
}
console.log(`SYNTAX: ${files.length - bad}/${files.length} files parse as Lua 5.1`);

const covered = new Map(), guarded = new Map(), allowedCalls = new Map(), missing = new Map(), badRefs = new Map();
const add = (m, k, where) => m.set(k, (m.get(k) || new Set()).add(where));
for (const [f, ast] of parsed) {
  // stack of {node, key} so guards can be found among ancestors and earlier sibling statements
  const visit = (n, stack) => {
    if (!n || typeof n !== 'object') return;
    if (Array.isArray(n)) { n.forEach((c) => visit(c, stack)); return; }
    const isCall = n.type === 'CallExpression' || n.type === 'StringCallExpression' || n.type === 'TableCallExpression';
    if (isCall) {
      const name = dotted(n.base);
      if (name && !ownGlobals.has(name.split('.')[0]) && !ownGlobals.has(name)) {
        const where = `${rel(f)}:${n.loc.start.line}`;
        if (API.has(name)) add(covered, name, where);
        else if (CALL_ALLOW.has(name)) add(allowedCalls, name, where);
        else if (isGuarded(name, n, stack)) add(guarded, name, where);
        else add(missing, name, where);
      }
      // still walk the arguments (and the base only for nested calls)
      visit(n.arguments || n.argument, stack.concat(n));
      if (!name) visit(n.base, stack.concat(n));
      return;
    }
    const d = dotted(n);
    if (d && (n.type === 'Identifier' || n.type === 'MemberExpression')) {
      const rootName = d.split('.')[0];
      const parent = stack[stack.length - 1];
      const isKey = parent && ((parent.type === 'TableKeyString' && parent.key === n));
      if (!isKey && !ownGlobals.has(rootName) && !API.has(rootName) && !API.has(d) && !REF_ALLOW.has(rootName)
        && !isGuarded(d, n, stack)) add(badRefs, rootName, `${rel(f)}:${n.loc.start.line}`);
      return;
    }
    for (const k of Object.keys(n)) {
      if (k === 'loc' || k === 'range') continue;
      if (n.type === 'MemberExpression' && k === 'identifier') continue; // field name, not a global
      if (n.type === 'TableKeyString' && k === 'key') continue;
      visit(n[k], stack.concat(n));
    }
  };
  visit(ast.body, []);
}
function isGuarded(name, node, stack) {
  const chain = stack.concat(node);
  const isCallNode = (x) => x.type === 'CallExpression' || x.type === 'StringCallExpression' || x.type === 'TableCallExpression';
  for (let i = chain.length - 2; i >= 0; i--) {
    const a = chain[i], child = chain[i + 1];
    // Only a bare reference (`X`, `C_Foo.X`) is an existence test; a call result (`X()`) used as a condition /
    // operand is NOT a guard: the call itself already raised "attempt to call a nil value".
    // A bare reference stays a bare reference through `and` / `or` / `not` (e.g. `if A and B then`), never through a call.
    const isRef = !isCallNode(node) && chain.slice(i + 1, -1).every((x) => x.type === 'LogicalExpression'
      || (x.type === 'UnaryExpression' && x.operator === 'not'));
    // X and X(...)  /  X and X.y
    if (a.type === 'LogicalExpression' && a.operator === 'and' && a.right === child && mentions(a.left, name)) return true;
    // X or fallback (the reference itself is the existence test)
    // `X and ...` (existence test) / `A or X` / `X or B` (nil-tolerant value; the consumer checks it)
    if (a.type === 'LogicalExpression' && a.left === child && isRef) return true;
    if (a.type === 'LogicalExpression' && a.operator === 'or' && a.right === child && node.type !== 'CallExpression') return true;
    // passed by value to pcall/xpcall or to a local wrapper (e.g. `call(UnitPVPRank, "player")`): the wrapper handles nil
    if (a.type === 'CallExpression' && a.arguments.includes(child) && node === child
      && (a.base.type === 'Identifier' && (a.base.isLocal || a.base.name === 'pcall' || a.base.name === 'xpcall'))) return true;
    // if X then ... X() ... end   (also elseif)
    if ((a.type === 'IfClause' || a.type === 'ElseifClause') && a.body.includes(child) && mentions(a.condition, name)) return true;
    if ((a.type === 'IfClause' || a.type === 'ElseifClause' || a.type === 'WhileStatement') && a.condition === child && isRef) return true; // `if X then`
    if (a.type === 'UnaryExpression' && a.operator === 'not' && a.argument === child && isRef) return true; // `not X`
    if (a.type === 'CallExpression' && a.base.type === 'Identifier' && a.base.name === 'type' && a.arguments.includes(child) && isRef) return true; // type(X)
    // if not X then return end ... X()   (earlier sibling statement in an enclosing block)
    const body = Array.isArray(a.body) ? a.body : null;
    if (body) {
      const idx = body.indexOf(child);
      for (let j = 0; j < idx; j++) {
        const s = body[j];
        if (s.type === 'IfStatement' && s.clauses.length && mentions(s.clauses[0].condition, name) && returnsEarly(s.clauses[0].body)) return true;
      }
    }
    // ns.apiFn("X") / ns.apiFn("C_Foo.X")
    if (a.type === 'CallExpression' && dotted(a.base) === null && a.base.type === 'MemberExpression' && a.base.identifier.name === 'apiFn'
      && a.arguments.some((x) => x.type === 'StringLiteral' && x.raw.slice(1, -1) === name)) return true;
  }
  return false;
}
const fmt = (m) => [...m.keys()].sort().map((k) => `${k} (${[...m.get(k)].slice(0, 3).join(', ')}${m.get(k).size > 3 ? ', ...' : ''})`);
console.log(`APIS COVERED BY PROBE: ${covered.size} called names found in api-16001.txt: ${[...covered.keys()].sort().join(', ')}`);
console.log(`APIS GUARDED (not in list, existence-checked before use): ${guarded.size}: ${[...guarded.keys()].sort().join(', ')}`);
if (allowedCalls.size) console.log(`APIS ALLOWLISTED: ${allowedCalls.size}: ${[...allowedCalls.keys()].sort().join(', ')}`);
for (const line of fmt(missing)) fail('API unguarded call not in 16001 list: ' + line);
for (const line of fmt(badRefs)) fail('API global reference not in 16001 list nor REF_ALLOW: ' + line);

// ---------- 3: TOC ----------
const tocPath = path.join(root, 'GuildSquads.toc');
const toc = fs.readFileSync(tocPath, 'utf8').split(/\r?\n/);
const meta = {};
for (const l of toc) { const m = /^## ([^:]+):\s*(.*)$/.exec(l); if (m) meta[m[1].trim()] = m[2].trim(); }
if (meta.Interface !== '16001') fail(`TOC Interface is "${meta.Interface}", expected 16001`);
if (!/\bGuildSquadsDB\b/.test(meta.SavedVariables || '')) fail('TOC SavedVariables does not declare GuildSquadsDB');
const listed = toc.filter((l) => l.trim() && !l.startsWith('#')).map((l) => l.trim());
const existsExact = (parts) => {
  let dir = root;
  for (const p of parts) { if (!fs.existsSync(dir) || !fs.readdirSync(dir).includes(p)) return false; dir = path.join(dir, p); }
  return true;
};
for (const l of listed) {
  if (l.includes('/')) fail(`TOC entry uses "/" instead of "\\": ${l}`);
  if (!existsExact(l.split(/[\\/]/))) fail(`TOC entry missing on disk (case-exact): ${l}`);
}
const listedSet = new Set(listed.map((l) => l.replace(/\\/g, '/')));
for (const [f] of parsed) if (!listedSet.has(rel(f))) fail(`addon file not listed in TOC: ${rel(f)}`);
console.log(`TOC: Interface ${meta.Interface}, SavedVariables ${meta.SavedVariables}, ${listed.length} files listed`);

// ---------- 4: locale key parity ----------
function localeKeys(file) {
  const ast = luaparse.parse(fs.readFileSync(path.join(root, file), 'utf8'), { luaVersion: '5.1', scope: true });
  const keys = new Set();
  const v = (n) => {
    if (!n || typeof n !== 'object') return;
    if (Array.isArray(n)) { n.forEach(v); return; }
    if (n.type === 'AssignmentStatement') for (const t of n.variables) {
      if (t.type === 'MemberExpression' && t.base.type === 'Identifier' && t.base.name === 'L') keys.add(t.identifier.name);
      if (t.type === 'IndexExpression' && t.base.type === 'Identifier' && t.base.name === 'L' && t.index.type === 'StringLiteral') keys.add(t.index.raw.slice(1, -1));
    }
    for (const k of Object.keys(n)) if (k !== 'loc' && k !== 'range') v(n[k]);
  };
  v(ast.body);
  return keys;
}
const en = localeKeys('Locales/enUS.lua'), es = localeKeys('Locales/esES.lua');
const onlyEn = [...en].filter((k) => !es.has(k)).sort(), onlyEs = [...es].filter((k) => !en.has(k)).sort();
if (onlyEn.length) fail(`LOCALE keys in enUS missing in esES (${onlyEn.length}): ${onlyEn.join(', ')}`);
if (onlyEs.length) fail(`LOCALE keys in esES missing in enUS (${onlyEs.length}): ${onlyEs.join(', ')}`);
console.log(`LOCALE: enUS ${en.size} keys, esES ${es.size} keys`);

console.log(failures === 0 ? 'GATES: OK' : `GATES: ${failures} failure(s)`);
process.exit(failures === 0 ? 0 : 1);
