#!/usr/bin/env node
// Local Runner Backend - lightweight HTTP bridge for the Co-Optimization
// Studio dashboard. Binds to 127.0.0.1 only (not 0.0.0.0) - never exposes
// child-process execution to the network.
'use strict';
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const express = require('express');
const { spawn } = require('child_process');
const { runClaude } = require('../scripts/lib/claudeAgent');
const { runHermes } = require('../scripts/lib/hermesAgent');
const { runGemini } = require('../scripts/lib/geminiAgent');

const REPO_ROOT = path.join(__dirname, '..');
const RUNS_LOG = path.join(REPO_ROOT, 'runs.log');
const PORT = parseInt(process.env.RUNNER_PORT || '4004', 10);
const HOST = process.env.RUNNER_HOST || '127.0.0.1';

fs.mkdirSync(path.dirname(RUNS_LOG), { recursive: true });
if (!fs.existsSync(RUNS_LOG)) fs.writeFileSync(RUNS_LOG, '');

const app = express();
app.use(express.json({ limit: '5mb' }));
app.use(express.static(path.join(REPO_ROOT, 'dashboard')));
app.use('/memory', express.static(path.join(REPO_ROOT, 'memory')));

// --- Active run tracking -----------------------------------------------
const activeRuns = new Map(); // pid -> { mode, args, startedAtMs, status }

function appendLog(line) {
  fs.appendFileSync(RUNS_LOG, `[${new Date().toISOString()}] ${line}\n`);
}

function launchCoOptimizer(mode, opts) {
  const args = ['scripts/co_optimizer.js', '--mode', mode];
  if (opts.prompt) args.push('--prompt', opts.prompt);
  if (opts.target) args.push('--target', opts.target);
  if (opts.trace) args.push('--trace', opts.trace);
  if (opts.apply) args.push('--apply');
  if (opts.dryRun) args.push('--dry-run');

  const child = spawn(process.execPath, args, { cwd: REPO_ROOT, shell: false });
  const record = { mode, args, startedAtMs: Date.now(), status: 'running', pid: child.pid };
  activeRuns.set(child.pid, record);
  appendLog(`RUNNER: launched pid=${child.pid} mode=${mode}`);

  child.stdout.on('data', () => {}); // co_optimizer.js writes its own runs.log lines
  child.stderr.on('data', (d) => appendLog(`RUNNER pid=${child.pid} STDERR: ${d.toString().trim()}`));
  child.on('close', (code) => {
    record.status = code === 0 ? 'completed' : 'failed';
    record.exitCode = code;
    appendLog(`RUNNER: pid=${child.pid} exited code=${code}`);
  });
  child.on('error', (err) => {
    record.status = 'failed';
    record.error = err.message;
    appendLog(`RUNNER: pid=${child.pid} spawn error: ${err.message}`);
  });

  return record;
}

// --- Endpoints -----------------------------------------------------------
app.post('/api/run/dual-code', (req, res) => {
  const { prompt, target, apply, dryRun } = req.body || {};
  if (!prompt) return res.status(400).json({ ok: false, error: 'prompt is required' });
  const record = launchCoOptimizer('dual-code', { prompt, target, apply, dryRun });
  res.json({ ok: true, pid: record.pid, mode: record.mode });
});

app.post('/api/run/dual-refactor', (req, res) => {
  const { target, apply, dryRun } = req.body || {};
  if (!target) return res.status(400).json({ ok: false, error: 'target is required' });
  const record = launchCoOptimizer('dual-refactor', { target, apply, dryRun });
  res.json({ ok: true, pid: record.pid, mode: record.mode });
});

app.post('/api/run/dual-debug', (req, res) => {
  const { trace, target, apply, dryRun } = req.body || {};
  if (!trace) return res.status(400).json({ ok: false, error: 'trace is required' });
  const record = launchCoOptimizer('dual-debug', { trace, target, apply, dryRun });
  res.json({ ok: true, pid: record.pid, mode: record.mode });
});

app.post('/api/run/claude', async (req, res) => {
  const { prompt, dryRun } = req.body || {};
  if (!prompt) return res.status(400).json({ ok: false, error: 'prompt is required' });
  appendLog(`RUNNER: direct claude call (${prompt.length} chars)`);
  const result = await runClaude(prompt, { dryRun: !!dryRun });
  appendLog(`RUNNER: direct claude call finished ok=${result.ok}`);
  res.json(result);
});

app.post('/api/run/hermes', async (req, res) => {
  const { prompt, dryRun } = req.body || {};
  if (!prompt) return res.status(400).json({ ok: false, error: 'prompt is required' });
  appendLog(`RUNNER: direct hermes call (${prompt.length} chars)`);
  const result = await runHermes(prompt, { dryRun: !!dryRun });
  appendLog(`RUNNER: direct hermes call finished ok=${result.ok}`);
  res.json(result);
});

app.post('/api/run/gemini', async (req, res) => {
  const { prompt, dryRun } = req.body || {};
  if (!prompt) return res.status(400).json({ ok: false, error: 'prompt is required' });
  appendLog(`RUNNER: direct gemini call (${prompt.length} chars)`);
  const result = await runGemini(prompt, { dryRun: !!dryRun });
  appendLog(`RUNNER: direct gemini call finished ok=${result.ok}`);
  res.json(result);
});

app.get('/api/status', (req, res) => {
  const lines = fs.readFileSync(RUNS_LOG, 'utf8').split('\n').filter(Boolean);
  res.json({
    ok: true,
    activeRuns: Array.from(activeRuns.values()),
    recentLog: lines.slice(-200),
  });
});

app.get('/api/artifacts', (req, res) => {
  const dir = path.join(REPO_ROOT, 'output', 'artifacts');
  if (!fs.existsSync(dir)) return res.json({ ok: true, files: [] });
  const files = fs.readdirSync(dir)
    .filter((f) => f !== '.gitkeep')
    .map((f) => {
      const stat = fs.statSync(path.join(dir, f));
      return { name: f, sizeBytes: stat.size, mtimeMs: stat.mtimeMs };
    })
    .sort((a, b) => b.mtimeMs - a.mtimeMs);
  res.json({ ok: true, files });
});

app.get('/api/reviews', (req, res) => {
  const dir = path.join(REPO_ROOT, 'output', 'reviews');
  if (!fs.existsSync(dir)) return res.json({ ok: true, runs: [] });
  const runs = fs.readdirSync(dir)
    .map((runId) => {
      const summaryPath = path.join(dir, runId, 'summary.json');
      if (!fs.existsSync(summaryPath)) return null;
      try { return JSON.parse(fs.readFileSync(summaryPath, 'utf8')); } catch { return null; }
    })
    .filter(Boolean)
    .sort((a, b) => (b.startedAtMs || 0) - (a.startedAtMs || 0));
  res.json({ ok: true, runs });
});

// --- Live log stream (SSE) ------------------------------------------------
const sseClients = new Set();
let lastLogSize = fs.statSync(RUNS_LOG).size;

app.get('/api/stream', (req, res) => {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
  });
  res.write('retry: 2000\n\n');
  sseClients.add(res);
  req.on('close', () => sseClients.delete(res));
});

fs.watchFile(RUNS_LOG, { interval: 500 }, () => {
  const stat = fs.statSync(RUNS_LOG);
  if (stat.size < lastLogSize) lastLogSize = 0; // log rotated/truncated
  if (stat.size === lastLogSize) return;
  const stream = fs.createReadStream(RUNS_LOG, { start: lastLogSize, end: stat.size });
  let chunk = '';
  stream.on('data', (d) => { chunk += d.toString(); });
  stream.on('end', () => {
    lastLogSize = stat.size;
    chunk.split('\n').filter(Boolean).forEach((line) => {
      const payload = `data: ${line.replace(/\n/g, ' ')}\n\n`;
      for (const client of sseClients) client.write(payload);
    });
  });
});

app.listen(PORT, HOST, () => {
  appendLog(`RUNNER: listening on http://${HOST}:${PORT}`);
  console.log(`Agentic OS Runner listening on http://${HOST}:${PORT}`);
});
