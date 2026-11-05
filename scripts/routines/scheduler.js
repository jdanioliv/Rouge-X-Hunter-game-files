#!/usr/bin/env node
// Long-running PM2-managed process: fires the nightly audit and weekly
// cleanup on cron schedules. Node-cron works identically on Windows/macOS/
// Linux, unlike shell cron/Task Scheduler, so this is the single source of
// truth for scheduling - the .sh/.ps1 wrappers are for manual/OS-cron use.
'use strict';
require('dotenv').config();
const cron = require('node-cron');
const path = require('path');
const nightly = require('./nightly_code_audit');
const weekly = require('./weekly_architect_cleanup');

const NIGHTLY_CRON = process.env.NIGHTLY_AUDIT_CRON || '0 2 * * *';
const WEEKLY_CRON = process.env.WEEKLY_CLEANUP_CRON || '0 3 * * 0';

function log(msg) {
  console.log(`[scheduler ${new Date().toISOString()}] ${msg}`);
}

if (!cron.validate(NIGHTLY_CRON)) throw new Error(`Invalid NIGHTLY_AUDIT_CRON: ${NIGHTLY_CRON}`);
if (!cron.validate(WEEKLY_CRON)) throw new Error(`Invalid WEEKLY_CLEANUP_CRON: ${WEEKLY_CRON}`);

cron.schedule(NIGHTLY_CRON, () => {
  log('Firing nightly_code_audit...');
  nightly.main().then((r) => log('nightly_code_audit done: ' + JSON.stringify(r))).catch((e) => log('nightly_code_audit ERROR: ' + e.message));
});

cron.schedule(WEEKLY_CRON, () => {
  log('Firing weekly_architect_cleanup (proposal mode, no --apply)...');
  weekly.main({ apply: false }).then((r) => log('weekly_architect_cleanup done: ' + JSON.stringify(r))).catch((e) => log('weekly_architect_cleanup ERROR: ' + e.message));
});

log(`Scheduler started. Nightly audit: "${NIGHTLY_CRON}". Weekly cleanup: "${WEEKLY_CRON}" (proposal-only by default).`);
log(`Repo root: ${path.join(__dirname, '..', '..')}`);
