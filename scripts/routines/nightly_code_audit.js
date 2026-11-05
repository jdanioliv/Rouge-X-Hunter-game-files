#!/usr/bin/env node
// Nightly Maintenance Routine: Hermes (Ox Alpha) scans recent Git commits
// against templates/REVIEW_RUBRIC.md and writes a defect report.
// Read-only against the game source - never modifies live files.
'use strict';
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { runHermes } = require('../lib/hermesAgent');
const { loadRubric } = require('../lib/rubric');
const { syncRouters } = require('../lib/routerSync');

const REPO_ROOT = path.join(__dirname, '..', '..');
const OUT_DIR = path.join(REPO_ROOT, 'output', 'reviews', 'nightly');

function getChangedLuauFiles() {
  try {
    const out = execFileSync('git', ['log', '--since=1.day', '--name-only', '--pretty=format:'], { cwd: REPO_ROOT })
      .toString();
    return Array.from(new Set(out.split('\n').map((l) => l.trim()).filter((l) => l.endsWith('.luau'))));
  } catch (err) {
    console.error('git log failed (is this a git repo with history?):', err.message);
    return [];
  }
}

async function main(opts = {}) {
  const dryRun = opts.dryRun || process.argv.includes('--dry-run');
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const rubric = loadRubric();
  const changedFiles = getChangedLuauFiles();

  if (!changedFiles.length) {
    console.log('No .luau files changed in the last 24h - nothing to audit.');
    return { ok: true, filesAudited: 0 };
  }

  const fileBlocks = changedFiles
    .filter((f) => fs.existsSync(path.join(REPO_ROOT, f)))
    .map((f) => `\n--- ${f} ---\n${fs.readFileSync(path.join(REPO_ROOT, f), 'utf8')}`)
    .join('\n');

  const prompt = [
    `You are Hermes (Ox Alpha) performing the nightly automated audit.`,
    `Scan the following files (all changed in Git in the last 24h) against`,
    `the rubric. List every finding with file, line (best estimate), severity,`,
    `and a one-sentence fix suggestion. This is READ-ONLY - do not propose`,
    `full file rewrites, just the defect list.`,
    `\n--- REVIEW RUBRIC ---\n${rubric}`,
    `\n--- CHANGED FILES ---${fileBlocks}`,
  ].join('\n');

  const result = await runHermes(prompt, { dryRun });
  const stamp = new Date().toISOString().slice(0, 10);
  const reportPath = path.join(OUT_DIR, `${stamp}.md`);
  fs.writeFileSync(reportPath, `# Nightly Audit — ${stamp}\n\nFiles audited: ${changedFiles.length}\n\n${result.text}\n`, 'utf8');

  await syncRouters(
    { runId: `nightly-${stamp}`, action: 'audited', file: changedFiles.join(', '), note: `defect report at output/reviews/nightly/${stamp}.md` },
    ['HERMES.md']
  );

  console.log(`Nightly audit complete: ${changedFiles.length} file(s) -> ${reportPath}`);
  return { ok: result.ok, filesAudited: changedFiles.length, reportPath };
}

if (require.main === module) {
  main().catch((err) => { console.error('Nightly audit failed:', err); process.exit(1); });
}

module.exports = { main };
