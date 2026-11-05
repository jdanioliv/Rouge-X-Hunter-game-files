// Enforces the Golden Rule from REVIEW_RUBRIC.md: any file the co-optimizer
// creates/modifies/moves gets logged into the relevant router's "Recent
// Automated Changes" section, in the same run - not left to human memory.
//
// Concurrency note: two co_optimizer runs (e.g. a manual dashboard trigger
// overlapping the nightly scheduler) can both read-modify-write the same
// router file. Without a lock this is a classic lost-update race - see
// "Failure Mode One: Concurrency Conflicts in Shared File Systems" in the
// multi-agent literature. A per-file lockfile (atomic O_EXCL create, retry
// with backoff, steal if stale) is the simplest correct fix for a
// single-machine tool like this - a full optimistic-lock/version-number
// scheme is overkill for local file contention this low-frequency.
'use strict';
const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.join(__dirname, '..', '..');
const MARKER_START = '<!-- AGENTIC-OS:RECENT-CHANGES:START -->';
const MARKER_END = '<!-- AGENTIC-OS:RECENT-CHANGES:END -->';
const MAX_ENTRIES = 25;
const LOCK_STALE_MS = 30 * 1000;
const LOCK_RETRY_MS = 100;
const LOCK_TIMEOUT_MS = 10 * 1000;

// Obsidian vault lives at the repo root (per project setup) under GameNotes/.
// Every syncRouters() call - dual-code, dual-refactor, dual-debug, nightly
// audit, weekly cleanup - also appends to today's daily note, so "what
// happened to the game today" always has one place to look regardless of
// which router(s) a given run touches.
const OBSIDIAN_DIR_REL = process.env.OBSIDIAN_NOTES_DIR || 'GameNotes';
const OBSIDIAN_DAILY_REL = path.join(OBSIDIAN_DIR_REL, 'Daily');

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function acquireLock(lockPath) {
  const deadline = Date.now() + LOCK_TIMEOUT_MS;
  for (;;) {
    try {
      const fd = fs.openSync(lockPath, 'wx'); // atomic create-if-not-exists
      fs.writeSync(fd, String(process.pid));
      fs.closeSync(fd);
      return;
    } catch (err) {
      if (err.code !== 'EEXIST') throw err;
      try {
        const stat = fs.statSync(lockPath);
        if (Date.now() - stat.mtimeMs > LOCK_STALE_MS) {
          fs.unlinkSync(lockPath); // previous holder crashed without cleanup - steal it
          continue;
        }
      } catch { /* lock disappeared between check and stat - fine, retry */ }
      if (Date.now() > deadline) {
        throw new Error(`Timed out waiting for router lock: ${lockPath}`);
      }
      await sleep(LOCK_RETRY_MS);
    }
  }
}

function releaseLock(lockPath) {
  try { fs.unlinkSync(lockPath); } catch { /* already gone - fine */ }
}

function ensureSection(content) {
  if (content.includes(MARKER_START)) return content;
  return content.trimEnd() + `\n\n## Recent Automated Changes (Co-Optimizer)\n${MARKER_START}\n${MARKER_END}\n`;
}

async function logChange(routerRelPath, entry) {
  const fullPath = path.join(REPO_ROOT, routerRelPath);
  const lockPath = fullPath + '.lock';

  await acquireLock(lockPath);
  try {
    // Re-read AFTER acquiring the lock, not before - the whole point is that
    // no other process can be mid-write between our read and our write.
    let content = fs.existsSync(fullPath) ? fs.readFileSync(fullPath, 'utf8') : `# ${path.basename(routerRelPath)}\n`;
    content = ensureSection(content);

    const startIdx = content.indexOf(MARKER_START) + MARKER_START.length;
    const endIdx = content.indexOf(MARKER_END);
    const existingBlock = content.slice(startIdx, endIdx).trim();
    const existingLines = existingBlock ? existingBlock.split('\n').filter(Boolean) : [];

    const stamp = new Date().toISOString();
    const newLine = `- \`${stamp}\` **${entry.runId}** ${entry.action}: \`${entry.file}\`${entry.note ? ' — ' + entry.note : ''}`;
    const updatedLines = [newLine, ...existingLines].slice(0, MAX_ENTRIES);

    const newBlock = `\n${updatedLines.join('\n')}\n`;
    content = content.slice(0, startIdx) + newBlock + content.slice(endIdx);

    fs.writeFileSync(fullPath, content, 'utf8');
  } finally {
    releaseLock(lockPath);
  }
}

function dailyNoteScaffold(dateStr) {
  return `# ${dateStr}\n\n## Summary\n*(add your own notes here — what you worked on, decisions made, anything the automated log below won't capture)*\n\n## Automated changes\n${MARKER_START}\n${MARKER_END}\n\n## Links\n- [[00-Home]]\n`;
}

async function logToObsidianDaily(entry) {
  const dateStr = new Date().toISOString().slice(0, 10); // YYYY-MM-DD, local run's UTC date
  const dailyDir = path.join(REPO_ROOT, OBSIDIAN_DAILY_REL);
  const fullPath = path.join(dailyDir, `${dateStr}.md`);
  const lockPath = fullPath + '.lock';

  fs.mkdirSync(dailyDir, { recursive: true });

  await acquireLock(lockPath);
  try {
    let content = fs.existsSync(fullPath) ? fs.readFileSync(fullPath, 'utf8') : dailyNoteScaffold(dateStr);
    if (!content.includes(MARKER_START)) {
      // Existing note (e.g. hand-written before the vault existed) with no
      // automated section yet - append one rather than overwriting notes.
      content = content.trimEnd() + `\n\n## Automated changes\n${MARKER_START}\n${MARKER_END}\n`;
    }

    const startIdx = content.indexOf(MARKER_START) + MARKER_START.length;
    const endIdx = content.indexOf(MARKER_END);
    const existingBlock = content.slice(startIdx, endIdx).trim();
    const existingLines = existingBlock ? existingBlock.split('\n').filter(Boolean) : [];

    const time = new Date().toISOString().slice(11, 16); // HH:MM UTC
    const newLine = `- \`${time}\` **${entry.runId}** ${entry.action} \`${entry.file}\`${entry.note ? ' — ' + entry.note : ''}`;
    const updatedLines = [...existingLines, newLine]; // chronological within the day, unlike the router's newest-first log

    const newBlock = `\n${updatedLines.join('\n')}\n`;
    content = content.slice(0, startIdx) + newBlock + content.slice(endIdx);

    fs.writeFileSync(fullPath, content, 'utf8');
  } finally {
    releaseLock(lockPath);
  }
}

/**
 * @param {{runId:string, action:string, file:string, note?:string}} entry
 * @param {string[]} routerRelPaths - e.g. ['CLAUDE.md', 'HERMES.md', 'memory/routers/SYSTEMS.md']
 */
async function syncRouters(entry, routerRelPaths) {
  // Sequential, not Promise.all: two routers sharing no lock could still race
  // each other's console/log ordering, and there's no throughput need here.
  for (const rel of routerRelPaths) {
    await logChange(rel, entry);
  }

  // Best-effort: the Obsidian daily log is a convenience layer on top of the
  // routers, not the source of truth - never let it fail a real run.
  try {
    await logToObsidianDaily(entry);
  } catch (err) {
    console.warn(`[routerSync] Obsidian daily note sync failed (non-fatal): ${err.message}`);
  }
}

module.exports = { syncRouters, logToObsidianDaily };
