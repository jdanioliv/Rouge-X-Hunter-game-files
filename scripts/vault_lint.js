#!/usr/bin/env node
'use strict';
// Lints the Obsidian vault (GameNotes/). Fails on:
//   - broken relative markdown links, including heading anchors
//   - [[wikilinks]] left in body text (run `npm run vault:links`), or dangling ones in frontmatter
//   - orphan notes that no other note links to
//   - unclosed frontmatter and leftover .md.lock files
//   - `path/File.ext:LINE` code citations pointing at a missing file or past its end
//
//   node scripts/vault_lint.js          exit 1 if anything is wrong
//   node scripts/vault_lint.js --warn   report only, exit 0
//
// Links inside code fences and inline code are ignored, since they are examples. Templates/ holds
// placeholders and is skipped. Graph/ is generated, so only its links are checked.

const fs = require('fs');
const path = require('path');
const { headingSlug, splitFrontmatter } = require('./vault_links');

const REPO_ROOT = path.join(__dirname, '..');
const VAULT = path.join(REPO_ROOT, process.env.OBSIDIAN_NOTES_DIR || 'GameNotes');
const SKIP_DIRS = new Set(['.git', '.obsidian', '.trash', 'node_modules']);
const CODE_ROOTS = ['src', 'scripts', 'server', 'dashboard', 'templates', 'memory', '.claude', 'GameNotes'];
const NOT_ORPHANS = new Set(['00-Home.md', 'README.md']);

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
const stripCode = (s) => s.replace(/```[\s\S]*?```/g, '').replace(/`[^`\n]*`/g, '');

const files = walk(VAULT);
const notes = files.filter((f) => f.endsWith('.md'));
const noteRels = new Set(notes.map((f) => toRel(f)));
const noteKeys = new Set([...noteRels].map((r) => r.slice(0, -3)));
const exactPaths = new Set(['.']);
for (const f of files) {
  const parts = toRel(f).split('/');
  for (let i = 1; i <= parts.length; i++) exactPaths.add(parts.slice(0, i).join('/'));
}

// Every file a note may cite, as repo-relative paths with their line counts.
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

const anchorCache = new Map();
function anchorsOf(relNote) {
  if (!anchorCache.has(relNote)) {
    const raw = fs.readFileSync(path.join(VAULT, relNote), 'utf8').replace(/```[\s\S]*?```/g, '');
    const slugs = new Set();
    for (const line of raw.split('\n')) {
      const m = line.match(/^#{1,6}\s+(.*?)\s*#*\s*$/);
      if (m) slugs.add(headingSlug(m[1].replace(/`/g, '')));
    }
    anchorCache.set(relNote, slugs);
  }
  return anchorCache.get(relNote);
}

function frontmatterLinkResolves(rawTarget) {
  const t = rawTarget.trim().replace(/\\$/, '').replace(/\\/g, '/').replace(/^(\.\.?\/)+/, '').replace(/\.md$/i, '');
  if (!t) return true;
  if (noteKeys.has(t)) return true;
  for (const k of noteKeys) if (k.endsWith('/' + t)) return true;
  return false;
}

const WIKI_RE = /\[\[([^\]|#]*)(?:#[^\]|]*)?(?:\\?\|[^\]]*)?\]\]/g;
const MD_LINK_RE = /(?<!!)\[[^\]\n]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g;
const CITE_RE = /`([\w./-]+\.(?:luau|js|json|html|md|ps1|sh|toml|py)):(\d+)(?:[-–](\d+))?`/g;
const problems = [];
const inbound = new Map();
let citations = 0;
let links = 0;

for (const f of notes) {
  const raw = fs.readFileSync(f, 'utf8');
  const relf = toRel(f);
  if (relf.startsWith('Templates/')) continue;
  const generated = relf.startsWith('Graph/');

  if (raw.startsWith('---') && raw.indexOf('\n---', 3) === -1) {
    problems.push(`${relf}: frontmatter opened with --- but never closed`);
  }
  const [front, bodyRaw] = splitFrontmatter(raw);
  const body = stripCode(bodyRaw);
  let m;

  while ((m = WIKI_RE.exec(front)) !== null) {
    if (!frontmatterLinkResolves(m[1])) problems.push(`${relf}: frontmatter link [[${m[1]}]] points at nothing`);
  }
  while ((m = WIKI_RE.exec(body)) !== null) {
    problems.push(`${relf}: body wikilink [[${m[1]}]] does not work on GitHub - run npm run vault:links`);
  }

  while ((m = MD_LINK_RE.exec(body)) !== null) {
    const href = m[1];
    if (/^[a-z][a-z0-9+.-]*:/i.test(href)) continue;
    links++;
    const hash = href.indexOf('#');
    let target = hash === -1 ? href : href.slice(0, hash);
    const anchor = hash === -1 ? '' : href.slice(hash + 1);
    try { target = decodeURI(target); } catch { /* keep as written */ }
    const resolved = target ? path.posix.normalize(path.posix.join(path.posix.dirname(relf), target)) : relf;
    // Exact-case lookup, not fs.existsSync: Windows ignores case but GitHub does not, so a link
    // with the wrong case would pass here and break on the repo.
    if (resolved.startsWith('..') || !exactPaths.has(resolved.replace(/\/$/, ''))) {
      problems.push(`${relf}: broken link ${href}`);
      continue;
    }
    if (resolved !== relf && noteRels.has(resolved) && !generated) {
      if (!inbound.has(resolved)) inbound.set(resolved, new Set());
      inbound.get(resolved).add(relf);
    }
    if (anchor && resolved.endsWith('.md') && !anchorsOf(resolved).has(anchor.toLowerCase())) {
      problems.push(`${relf}: link ${href} points at a heading that does not exist`);
    }
  }

  if (!generated) {
    while ((m = CITE_RE.exec(raw)) !== null) {
      citations++;
      const cited = m[1];
      const line = parseInt(m[3] || m[2], 10);
      const hits = codeFiles.filter((c) => c === cited || c.endsWith('/' + cited));
      if (hits.length === 0) problems.push(`${relf}: cites missing file ${m[0]}`);
      else if (hits.every((h) => line > linesOf(h))) problems.push(`${relf}: ${m[0]} is past the end of the file`);
    }
  }
}

for (const rel of noteRels) {
  if (NOT_ORPHANS.has(rel) || rel.startsWith('Templates/')) continue;
  if (rel.startsWith('Graph/') && rel !== 'Graph/GRAPH_REPORT.md' && rel !== 'Graph/wiki/index.md') continue;
  if (!inbound.has(rel)) problems.push(`${rel}: orphan note - nothing links to it`);
}

for (const f of files) {
  if (f.endsWith('.md.lock')) problems.push(`${toRel(f)}: leftover lock file (a routerSync write crashed?) - delete it`);
}

const summary = `${notes.length} notes, ${links} links, ${citations} code citations`;
if (problems.length) {
  console.log(`[vault-lint] ${summary}, ${problems.length} problem(s):`);
  for (const p of problems) console.log('  - ' + p);
  process.exit(process.argv.includes('--warn') ? 0 : 1);
} else {
  console.log(`[vault-lint] ${summary}: all links resolve, no orphans, frontmatter OK, no lock files`);
}
