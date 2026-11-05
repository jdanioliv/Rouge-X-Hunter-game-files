#!/usr/bin/env node
// Rebuilds memory/index.json (project files + review logs + artifacts) and
// re-embeds it into memory/second_brain.html so the Second Brain works even
// opened directly as a local file (no server, no CORS/fetch issues).
'use strict';
const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.join(__dirname, '..');
const OUT_JSON = path.join(REPO_ROOT, 'memory', 'index.json');
const BRAIN_HTML = path.join(REPO_ROOT, 'memory', 'second_brain.html');
const EMBED_START = '<!-- MEMORY-DATA:START -->';
const EMBED_END = '<!-- MEMORY-DATA:END -->';

const EXCLUDE_DIRS = new Set(['.git', 'node_modules', 'Packages', 'ServerPackages', 'DevPackages']);

function categorize(relPath) {
  if (relPath.startsWith('src/ReplicatedStorage/Shared')) return 'Shared';
  if (relPath.startsWith('src/ServerScriptService')) return 'Services';
  if (relPath.startsWith('src/StarterPlayer')) return 'Client';
  if (relPath.startsWith('output/reviews')) return 'Review Log';
  if (relPath.startsWith('output/artifacts')) return 'Artifact';
  if (relPath.startsWith('.claude/skills') || relPath.startsWith('.agent/skills')) return 'Skill';
  if (relPath.startsWith('templates')) return 'Rubric/Template';
  if (relPath.startsWith('memory/routers')) return 'Memory Router';
  if (relPath === 'CLAUDE.md' || relPath === 'HERMES.md') return 'Root Router';
  if (relPath.startsWith('scripts') || relPath.startsWith('server') || relPath.startsWith('dashboard')) return 'Agentic OS';
  if (relPath.endsWith('.md')) return 'Docs';
  return 'Other';
}

function walk(dir, out) {
  for (const name of fs.readdirSync(dir)) {
    if (EXCLUDE_DIRS.has(name)) continue;
    const full = path.join(dir, name);
    const rel = path.relative(REPO_ROOT, full).split(path.sep).join('/');
    const stat = fs.statSync(full);
    if (stat.isDirectory()) {
      walk(full, out);
    } else {
      out.push({
        path: rel,
        name,
        category: categorize(rel),
        sizeBytes: stat.size,
        mtimeMs: stat.mtimeMs,
      });
    }
  }
}

function loadReviewSummaries() {
  const reviewsDir = path.join(REPO_ROOT, 'output', 'reviews');
  if (!fs.existsSync(reviewsDir)) return [];
  const summaries = [];
  for (const runDir of fs.readdirSync(reviewsDir)) {
    const summaryPath = path.join(reviewsDir, runDir, 'summary.json');
    if (fs.existsSync(summaryPath)) {
      try {
        summaries.push(JSON.parse(fs.readFileSync(summaryPath, 'utf8')));
      } catch { /* skip malformed */ }
    }
  }
  return summaries.sort((a, b) => (b.startedAtMs || 0) - (a.startedAtMs || 0));
}

function build() {
  const files = [];
  walk(REPO_ROOT, files);
  const index = {
    generatedAtMs: Date.now(),
    fileCount: files.length,
    files,
    reviews: loadReviewSummaries(),
  };
  fs.mkdirSync(path.dirname(OUT_JSON), { recursive: true });
  fs.writeFileSync(OUT_JSON, JSON.stringify(index, null, 2), 'utf8');

  if (fs.existsSync(BRAIN_HTML)) {
    let html = fs.readFileSync(BRAIN_HTML, 'utf8');
    const startIdx = html.indexOf(EMBED_START);
    const endIdx = html.indexOf(EMBED_END);
    if (startIdx !== -1 && endIdx !== -1) {
      const before = html.slice(0, startIdx + EMBED_START.length);
      const after = html.slice(endIdx);
      const embed = `\n<script id="memory-data" type="application/json">${JSON.stringify(index)}</script>\n`;
      html = before + embed + after;
      fs.writeFileSync(BRAIN_HTML, html, 'utf8');
    }
  }
  return index;
}

if (require.main === module) {
  const index = build();
  console.log(`Indexed ${index.fileCount} files, ${index.reviews.length} review run(s) -> memory/index.json + memory/second_brain.html`);
}

module.exports = { build };
