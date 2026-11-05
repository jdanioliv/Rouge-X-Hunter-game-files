#!/usr/bin/env node
'use strict';
// Lints the Obsidian vault (GameNotes/): dangling [[wikilinks]], unclosed frontmatter,
// leftover lock files, and `path/File.ext:LINE` code citations that point past the end of a file.
//
//   node scripts/vault_lint.js          exit 1 if anything is wrong
//   node scripts/vault_lint.js --warn   report only, exit 0
//
// Link resolution mirrors Obsidian: [[Name]] matches any note named Name, [[Folder/Name]]
// matches a path suffix, ../ prefixes are relative. Links inside code fences and inline code
// are ignored (they are examples), and Templates/ is skipped (placeholders are not links).

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.join(__dirname, '..');
const VAULT = path.join(REPO_ROOT, process.env.OBSIDIAN_NOTES_DIR || 'GameNotes');
const SKIP_DIRS = new Set(['.git', '.obsidian', '.trash', 'node_modules']);
const CODE_ROOTS = ['src', 'scripts', 'server', 'dashboard', 'templates', 'memory', '.claude', 'GameNotes'];

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (!SKIP_DIRS.has(entry.name)) walk(full, out);
    } else {
      out.push(full);
    }
  }
  return out;
}

const toRel = (p, base = VAULT) => path.relative(base, p).split(path.sep).join('/');

const files = walk(VAULT);
const fileRels = files.map((f) => toRel(f));
const notes = files.filter((f) => f.endsWith('.md'));
const noteKeys = new Set(notes.map((f) => toRel(f).slice(0, -3)));
const baseNames = new Set([...noteKeys].map((k) => k.split('/').pop()));

// Every code file a note may cite, as repo-relative paths with their line counts.
const codeFiles = [];
for (const root of CODE_ROOTS) {
  const full = path.join(REPO_ROOT, root);
  if (fs.existsSync(full)) for (const f of walk(full)) codeFiles.push(toRel(f, REPO_ROOT));
}
for (const f of fs.readdirSync(REPO_ROOT)) {
  if (fs.statSync(path.join(REPO_ROOT, f)).isFile()) codeFiles.push(f);
}
const lineCounts = new Map();
function linesOf(rel) {
  if (!lineCounts.has(rel)) lineCounts.set(rel, fs.readFileSync(path.join(REPO_ROOT, rel), 'utf8').split('\n').length);
  return lineCounts.get(rel);
}

function resolves(rawTarget) {
  let t = rawTarget.trim().replace(/\\$/, '').replace(/\\/g, '/').replace(/^(\.\.?\/)+/, '');
  if (!t) return true; // [[#heading]] links to the same note
  if (/\.[a-z0-9]{2,5}$/i.test(t) && !/\.md$/i.test(t)) {
    return fileRels.some((f) => f === t || f.endsWith('/' + t)); // attachment embed
  }
  t = t.replace(/\.md$/i, '');
  if (noteKeys.has(t)) return true;
  for (const k of noteKeys) if (k.endsWith('/' + t)) return true;
  return !t.includes('/') && baseNames.has(t);
}

const stripCode = (s) => s.replace(/```[\s\S]*?```/g, '').replace(/`[^`\n]*`/g, '');
const LINK_RE = /\[\[([^\]|#]*)(?:#[^\]|]*)?(?:\|[^\]]*)?\]\]/g;
const CITE_RE = /`([\w./-]+\.(?:luau|js|json|html|md|ps1|sh|toml)):(\d+)(?:[-–](\d+))?`/g;
const problems = [];
let citations = 0;

for (const f of notes) {
  const raw = fs.readFileSync(f, 'utf8');
  const relf = toRel(f);
  if (relf.startsWith('Templates/')) continue;
  if (raw.startsWith('---') && raw.indexOf('\n---', 3) === -1) {
    problems.push(`${relf}: frontmatter opened with --- but never closed`);
  }
  const body = stripCode(raw);
  let m;
  while ((m = LINK_RE.exec(body)) !== null) {
    if (!resolves(m[1])) problems.push(`${relf}: dangling link [[${m[1]}]]`);
  }
  while ((m = CITE_RE.exec(raw)) !== null) {
    citations++;
    const cited = m[1];
    const line = parseInt(m[3] || m[2], 10);
    const hits = codeFiles.filter((c) => c === cited || c.endsWith('/' + cited));
    if (hits.length === 0) problems.push(`${relf}: cites missing file ${m[0]}`);
    else if (hits.every((h) => line > linesOf(h))) problems.push(`${relf}: ${m[0]} is past the end of the file`);
  }
}

for (const f of files) {
  if (f.endsWith('.md.lock')) problems.push(`${toRel(f)}: leftover lock file (a routerSync write crashed?) - delete it`);
}

if (problems.length) {
  console.log(`[vault-lint] ${notes.length} notes, ${citations} code citations, ${problems.length} problem(s):`);
  for (const p of problems) console.log('  - ' + p);
  process.exit(process.argv.includes('--warn') ? 0 : 1);
} else {
  console.log(`[vault-lint] ${notes.length} notes, ${citations} code citations: no dangling links, frontmatter OK, no lock files`);
}
