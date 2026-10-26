// Checks every relative link in the repository's Markdown files and docs HTML indexes:
// the target file must exist and, for "#anchor" links into Markdown, the heading must exist
// (GitHub slug rules). Also checks that docs/en and docs/es hold the same set of files.
// Usage: node tests/tools/check-links.js   (exit 1 on any broken link or language mismatch)
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..', '..');
const SKIP_DIRS = new Set(['.git', 'node_modules', '.node', '.release']);

function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SKIP_DIRS.has(e.name)) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out); else out.push(p);
  }
  return out;
}

function slug(text) {
  return text.trim().toLowerCase()
    .replace(/<[^>]+>/g, '')
    .replace(/[^\p{L}\p{N}\- _]/gu, '')
    .replace(/ /g, '-');
}

const anchorCache = new Map();
function anchorsOf(file) {
  if (anchorCache.has(file)) return anchorCache.get(file);
  const set = new Set();
  const seen = new Map();
  let fence = false;
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    if (/^\s*```/.test(line)) { fence = !fence; continue; }
    if (fence) continue;
    const m = /^#{1,6}\s+(.*?)\s*#*\s*$/.exec(line);
    if (!m) continue;
    let s = slug(m[1]);
    const n = seen.get(s) || 0;
    seen.set(s, n + 1);
    if (n > 0) s = `${s}-${n}`;
    set.add(s);
  }
  anchorCache.set(file, set);
  return set;
}

function linksOf(file) {
  const text = fs.readFileSync(file, 'utf8');
  const out = [];
  if (file.endsWith('.md')) {
    let fence = false;
    text.split('\n').forEach((line, i) => {
      if (/^\s*```/.test(line)) { fence = !fence; return; }
      if (fence) return;
      const noCode = line.replace(/`[^`]*`/g, '');
      for (const m of noCode.matchAll(/!?\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g)) out.push({ target: m[1], line: i + 1 });
    });
  } else {
    text.split('\n').forEach((line, i) => {
      for (const m of line.matchAll(/(?:href|src)="([^"]+)"/g)) out.push({ target: m[1], line: i + 1 });
    });
  }
  return out;
}

const files = walk(root, []);
const md = files.filter((f) => f.endsWith('.md'));
const html = files.filter((f) => /docs[\\/](en|es)[\\/]diagrams[\\/]index\.html$/.test(f));
let checked = 0;
const broken = [];
for (const file of [...md, ...html]) {
  for (const { target, line } of linksOf(file)) {
    if (/^(https?:|mailto:|data:)/.test(target)) continue;
    checked++;
    const [rawPath, anchor] = target.split('#');
    const dest = rawPath === '' ? file : path.resolve(path.dirname(file), decodeURI(rawPath));
    const where = `${path.relative(root, file)}:${line} -> ${target}`;
    if (!fs.existsSync(dest)) { broken.push(`${where} (missing file)`); continue; }
    if (anchor !== undefined && dest.endsWith('.md') && !anchorsOf(dest).has(decodeURIComponent(anchor))) {
      broken.push(`${where} (missing anchor)`);
    }
  }
}

function listDocs(lang) {
  const base = path.join(root, 'docs', lang);
  return walk(base, []).map((f) => path.relative(base, f).split(path.sep).join('/')).sort();
}
const en = listDocs('en');
const es = listDocs('es');
const onlyEn = en.filter((f) => !es.includes(f));
const onlyEs = es.filter((f) => !en.includes(f));

console.log(`links checked: ${checked} in ${md.length} .md + ${html.length} .html; broken: ${broken.length}`);
broken.forEach((b) => console.log('  BROKEN ' + b));
console.log(`docs/en: ${en.length} files · docs/es: ${es.length} files · only in en: ${onlyEn.length} · only in es: ${onlyEs.length}`);
onlyEn.forEach((f) => console.log('  ONLY EN ' + f));
onlyEs.forEach((f) => console.log('  ONLY ES ' + f));
process.exit(broken.length || onlyEn.length || onlyEs.length ? 1 : 0);
