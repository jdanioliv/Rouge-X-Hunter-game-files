#!/usr/bin/env node
'use strict';
// Converts [[wikilinks]] in the vault body text to standard relative markdown links.
//
//   node scripts/vault_links.js           rewrite notes in place
//   node scripts/vault_links.js --check   report only, exit 1 if anything would change
//
// Standard links are the one format that works everywhere the vault is read: Obsidian follows
// them and draws them in the graph view, and GitHub makes them clickable. Wikilinks only work in
// Obsidian. It is still fine to type [[...]] while writing: `vault:publish` runs this first.
//
// Frontmatter is left alone on purpose. Obsidian only treats [[...]] as links inside properties.
// Code fences and inline code are left alone too, since links there are examples.
// Idempotent: a converted note contains nothing left to convert.

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.join(__dirname, '..');
const VAULT = path.join(REPO_ROOT, process.env.OBSIDIAN_NOTES_DIR || 'GameNotes');
const SKIP_DIRS = new Set(['.git', '.obsidian', '.trash', 'node_modules']);
const SKIP_PREFIXES = ['Templates/', 'Graph/']; // placeholders and generated output

const posix = (p) => p.split(path.sep).join('/');

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (!SKIP_DIRS.has(entry.name)) walk(full, out);
    } else if (entry.name.endsWith('.md')) {
      out.push(posix(path.relative(VAULT, full)));
    }
  }
  return out;
}

// GitHub's heading anchor rule. Obsidian still opens the note for this form.
function headingSlug(heading) {
  return heading.trim().toLowerCase().replace(/[^\w\- ]+/g, '').replace(/ /g, '-');
}

function displayName(target) {
  const base = target.split('/').pop();
  if (base === '00-Home') return 'Home';
  if (/^\d{4}-\d{2}-\d{2}/.test(base)) return base;
  return base.replace(/^_/, '').replace(/-/g, ' ');
}

function resolveTarget(rawTarget, srcRel, keys) {
  const t = rawTarget.trim().replace(/\\/g, '/').replace(/\.md$/i, '');
  if (!t) return srcRel.replace(/\.md$/, '');
  if (t.startsWith('.')) {
    const rel = path.posix.normalize(path.posix.join(path.posix.dirname(srcRel), t));
    if (keys.has(rel)) return rel;
  }
  const stripped = t.replace(/^(\.\.?\/)+/, '');
  if (keys.has(stripped)) return stripped;
  const sibling = path.posix.join(path.posix.dirname(srcRel), stripped);
  if (keys.has(sibling)) return sibling;
  const matches = [...keys].filter((k) => k.endsWith('/' + stripped) || k === stripped);
  return matches.length ? matches.sort((a, b) => a.length - b.length)[0] : null;
}

function splitFrontmatter(raw) {
  if (!raw.startsWith('---')) return ['', raw];
  const end = raw.indexOf('\n---', 3);
  if (end === -1) return ['', raw];
  const cut = end + 4;
  return [raw.slice(0, cut), raw.slice(cut)];
}

// Matches code first, so wikilinks inside code are consumed as code and left untouched.
const TOKEN_RE = /(```[\s\S]*?```|`[^`\n]*`)|(?<!!)\[\[([^\]\n]+?)\]\]/g;

function convertBody(body, srcRel, keys, unresolved) {
  return body.replace(TOKEN_RE, (whole, code, inner) => {
    if (code) return whole;
    const pipe = inner.search(/\\?\|/);
    const linkPart = pipe === -1 ? inner : inner.slice(0, pipe);
    const alias = pipe === -1 ? null : inner.slice(pipe).replace(/^\\?\|/, '').trim();
    const hash = linkPart.indexOf('#');
    const rawTarget = hash === -1 ? linkPart : linkPart.slice(0, hash);
    const anchor = hash === -1 ? '' : linkPart.slice(hash + 1);

    const resolved = resolveTarget(rawTarget, srcRel, keys);
    if (!resolved) {
      unresolved.push({ file: srcRel, link: inner });
      return whole;
    }
    const text = alias || (rawTarget.trim() ? displayName(resolved) : anchor);
    const samePage = !rawTarget.trim();
    const rel = samePage ? '' : encodeURI(path.posix.relative(path.posix.dirname(srcRel), `${resolved}.md`));
    const frag = anchor ? `#${headingSlug(anchor)}` : '';
    return `[${text}](${rel}${frag})`;
  });
}

function convertVault({ write = true } = {}) {
  const notes = walk(VAULT);
  const keys = new Set(notes.map((n) => n.replace(/\.md$/, '')));
  const changed = [];
  const unresolved = [];
  for (const rel of notes) {
    if (SKIP_PREFIXES.some((p) => rel.startsWith(p))) continue;
    const full = path.join(VAULT, rel);
    const raw = fs.readFileSync(full, 'utf8');
    const [front, body] = splitFrontmatter(raw);
    const next = front + convertBody(body, rel, keys, unresolved);
    if (next !== raw) {
      changed.push(rel);
      if (write) fs.writeFileSync(full, next, 'utf8');
    }
  }
  return { checked: notes.length, changed, unresolved };
}

module.exports = { convertVault, headingSlug, splitFrontmatter };

if (require.main === module) {
  const check = process.argv.includes('--check');
  const { checked, changed, unresolved } = convertVault({ write: !check });
  console.log(`[vault-links] ${checked} notes, ${changed.length} ${check ? 'need converting' : 'converted'}`);
  for (const c of changed) console.log('  ' + c);
  for (const u of unresolved) console.log(`  unresolved in ${u.file}: [[${u.link}]]`);
  process.exit(unresolved.length || (check && changed.length) ? 1 : 0);
}
