// Persists every stage of a co-optimization run to output/reviews/<run-id>/
// and appends condensed lines to runs.log for the dashboard's live tail.
'use strict';
const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.join(__dirname, '..', '..');
const REVIEWS_DIR = path.join(REPO_ROOT, 'output', 'reviews');
const RUNS_LOG = path.join(REPO_ROOT, 'runs.log');

function pad(n) { return String(n).padStart(2, '0'); }

function makeRunId(mode, seedMs) {
  const d = new Date(seedMs);
  const stamp = `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}-` +
                `${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}`;
  return `${stamp}_${mode}`;
}

class ReviewLogger {
  constructor(mode, seedMs) {
    this.mode = mode;
    this.runId = makeRunId(mode, seedMs);
    this.dir = path.join(REVIEWS_DIR, this.runId);
    fs.mkdirSync(this.dir, { recursive: true });
    this.summary = { runId: this.runId, mode, startedAtMs: seedMs, stages: [], criticalIssuesRemaining: null };
    this.appendRunsLog(`=== RUN START ${this.runId} (mode=${mode}) ===`);
  }

  appendRunsLog(line) {
    const stamped = `[${new Date().toISOString()}] ${line}\n`;
    fs.appendFileSync(RUNS_LOG, stamped);
  }

  writeStage(stageName, filename, content) {
    fs.writeFileSync(path.join(this.dir, filename), content, 'utf8');
    this.summary.stages.push({ stage: stageName, file: filename, bytes: Buffer.byteLength(content) });
    this.appendRunsLog(`[${this.runId}] ${stageName} -> ${filename} (${Buffer.byteLength(content)} bytes)`);
  }

  writeFinalArtifact(targetRelPath, content) {
    const artifactsDir = path.join(REPO_ROOT, 'output', 'artifacts');
    fs.mkdirSync(artifactsDir, { recursive: true });
    const outPath = path.join(artifactsDir, `${this.runId}__${path.basename(targetRelPath)}`);
    fs.writeFileSync(outPath, content, 'utf8');
    this.appendRunsLog(`[${this.runId}] FINAL ARTIFACT -> output/artifacts/${path.basename(outPath)}`);
    return outPath;
  }

  finish(criticalIssuesRemaining) {
    this.summary.criticalIssuesRemaining = criticalIssuesRemaining;
    this.summary.finishedAtMs = Date.now();
    fs.writeFileSync(path.join(this.dir, 'summary.json'), JSON.stringify(this.summary, null, 2), 'utf8');
    this.appendRunsLog(`=== RUN END ${this.runId} (critical remaining: ${criticalIssuesRemaining}) ===`);
  }
}

module.exports = { ReviewLogger, REVIEWS_DIR, RUNS_LOG };
