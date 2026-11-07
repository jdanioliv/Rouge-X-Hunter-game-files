#!/usr/bin/env node
// Long-running PM2-managed process: fires the weekly cleanup on a cron schedule. Node-cron works identically on Windows/macOS/
// Linux, unlike shell cron/Task Scheduler, so this is the single source of
// truth for scheduling - the .sh/.ps1 wrappers are for manual/OS-cron use.
'use strict';
require('dotenv').config();
const cron = require('node-cron');
const path = require('path');
const weekly = require('./weekly_architect_cleanup');

const WEEKLY_CRON = process.env.WEEKLY_CLEANUP_CRON || '0 3 * * 0';

function log(msg) {
  console.log(`[scheduler ${new Date().toISOString()}] ${msg}`);
}

if (!cron.validate(WEEKLY_CRON)) throw new Error(`Invalid WEEKLY_CLEANUP_CRON: ${WEEKLY_CRON}`);

cron.schedule(WEEKLY_CRON, () => {
  log('Firing weekly_architect_cleanup (proposal mode, no --apply)...');
  weekly.main({ apply: false }).then((r) => log('weekly_architect_cleanup done: ' + JSON.stringify(r))).catch((e) => log('weekly_architect_cleanup ERROR: ' + e.message));
});

log(`Scheduler started. Weekly cleanup: "${WEEKLY_CRON}" (proposal-only by default).`);
log(`Repo root: ${path.join(__dirname, '..', '..')}`);
