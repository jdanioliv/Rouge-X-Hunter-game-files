#!/usr/bin/env bash
# POSIX wrapper for OS-level cron (Linux/macOS). On Windows, prefer PM2's
# scheduler.js (recommended) or nightly_code_audit.ps1 with Task Scheduler.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
node scripts/routines/nightly_code_audit.js "$@"
