#!/usr/bin/env bash
# POSIX wrapper for OS-level cron (Linux/macOS). Defaults to proposal-only
# (no --apply) - pass --apply explicitly if you want it to write live fixes.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
node scripts/routines/weekly_architect_cleanup.js "$@"
