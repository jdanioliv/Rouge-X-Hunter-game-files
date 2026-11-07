#!/usr/bin/env node
// Weekly Maintenance Routine: Claude (Opus 5) ingests unresolved nightly
// defect reports and proposes fixes, and prunes stale router references.
// SAFETY DEFAULT: proposes only (writes to output/reviews/weekly/) unless
// run with --apply, since unattended writes to live game code are risky.
'use strict';
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { runClaude } = require('../lib/claudeAgent');
const { loadRubric } = require('../lib/rubric');
const { syncRouters } = require('../lib/routerSync');

const REPO_ROOT = path.join(__dirname, '..', '..');
const NIGHTLY_DIR = path.join(REPO_ROOT, 'output', 'reviews', 'nightly');
const WEEKLY_DIR = path.join(REPO_ROOT, 'output', 'reviews', 'weekly');

function loadRecentNightlyReports(days = 7) {
  if (!fs.existsSync(NIGHTLY_DIR)) return [];
  const cutoff = Date.now() - days * 24 * 60 * 60 * 1000;
  return fs.readdirSync(NIGHTLY_DIR)
    .filter((f) => f.endsWith('.md'))
    .map((f) => ({ file: f, full: path.join(NIGHTLY_DIR, f) }))
    .filter((r) => fs.statSync(r.full).mtimeMs >= cutoff)
    .map((r) => `\n--- ${r.file} ---\n${fs.readFileSync(r.full, 'utf8')}`);
}

function findStaleRouterReferences() {
  // Very cheap heuristic: any inline-code-span path (`...`) in a router that
  // doesn't exist on disk. Not exhaustive - flags candidates for a human/Claude look.
  const routerFiles = ['CLAUDE.md', 'memory/routers/SYSTEMS.md', 'memory/routers/NETWORKING.md', 'memory/routers/ASSETS.md'];
  const stale = [];
  for (const rel of routerFiles) {
    const full = path.join(REPO_ROOT, rel);
    if (!fs.existsSync(full)) continue;
    const content = fs.readFileSync(full, 'utf8');
    const matches = content.match(/`([\w./-]+\.(luau|json|md|toml))`/g) || [];
    for (const m of matches) {
      const p = m.slice(1, -1);
      if (!fs.existsSync(path.join(REPO_ROOT, p))) stale.push({ router: rel, reference: p });
    }
  }
  return stale;
}

async function main(opts = {}) {
  const apply = opts.apply || process.argv.includes('--apply');
  const dryRun = opts.dryRun || process.argv.includes('--dry-run');
  fs.mkdirSync(WEEKLY_DIR, { recursive: true });

  const nightlyBlocks = loadRecentNightlyReports();
  const stale = findStaleRouterReferences();
  const rubric = loadRubric();

  if (!nightlyBlocks.length && !stale.length) {
    console.log('No unresolved nightly defects and no stale router references. Nothing to do.');
    return { ok: true, nothingToDo: true };
  }

  const prompt = [
    `You are Claude Opus 5 running the weekly architect cleanup.`,
    `Below are this week's nightly defect reports (the nightly audit was removed, so usually none), and`,
    `a list of router references pointing at files that no longer exist.`,
    `For each real defect: propose a concrete fix (diff-style). For each`,
    `stale reference: propose the router edit that removes/updates it.`,
    apply
      ? `You may assume these will be applied directly - be conservative and precise.`
      : `This is a PROPOSAL ONLY - it will be written to output/reviews/weekly/ for human review, not applied automatically.`,
    `\n--- REVIEW RUBRIC ---\n${rubric}`,
    `\n--- NIGHTLY DEFECT REPORTS ---${nightlyBlocks.join('\n') || ' (none)'}`,
    `\n--- STALE ROUTER REFERENCES ---\n${JSON.stringify(stale, null, 2)}`,
  ].join('\n');

  const result = await runClaude(prompt, { dryRun });
  const stamp = new Date().toISOString().slice(0, 10);
  const reportPath = path.join(WEEKLY_DIR, `${stamp}${apply ? '_applied' : '_proposal'}.md`);
  fs.writeFileSync(reportPath, `# Weekly Architect Cleanup — ${stamp}${apply ? ' (apply mode)' : ' (proposal only)'}\n\n${result.text}\n`, 'utf8');

  await syncRouters(
    { runId: `weekly-${stamp}`, action: apply ? 'cleaned up' : 'proposed cleanup for', file: `${nightlyBlocks.length} nightly report(s), ${stale.length} stale ref(s)`, note: `see output/reviews/weekly/${path.basename(reportPath)}` },
    ['CLAUDE.md']
  );

  console.log(`Weekly cleanup ${apply ? 'applied' : 'proposed'} -> ${reportPath}`);
  return { ok: result.ok, reportPath, apply, staleCount: stale.length };
}

if (require.main === module) {
  main().catch((err) => { console.error('Weekly cleanup failed:', err); process.exit(1); });
}

module.exports = { main };
