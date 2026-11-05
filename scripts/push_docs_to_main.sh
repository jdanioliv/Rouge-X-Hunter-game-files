#!/usr/bin/env bash
# Sends HANDOFF.md and pending-vault-notes/ straight to main, from any branch, without touching
# the working tree. These are the only files allowed on main without the owner's permission, so
# the next session always reads the latest handoff. See HANDOFF.md.
#
#   bash scripts/push_docs_to_main.sh "commit message"
#   bash scripts/push_docs_to_main.sh --clear-pending "commit message"   notes are now in the vault

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CLEAR=0
if [ "${1:-}" = "--clear-pending" ]; then
  CLEAR=1
  shift
fi
if [ $# -lt 1 ] || [ -z "$1" ]; then
  echo 'usage: bash scripts/push_docs_to_main.sh [--clear-pending] "commit message"' >&2
  exit 2
fi
MESSAGE="$1"

TMP="$(mktemp -d)"
WORK="$TMP/main"
cleanup() {
  git -C "$ROOT" worktree remove --force "$WORK" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

git fetch -q origin main
git worktree add -q --detach "$WORK" origin/main

cp HANDOFF.md "$WORK/HANDOFF.md"
# Notes are only ever added here, unless asked to clear them. A branch that lacks a note must not
# delete one that another session left on main.
if [ "$CLEAR" = 1 ]; then
  rm -rf "$WORK/pending-vault-notes"
elif [ -d pending-vault-notes ]; then
  mkdir -p "$WORK/pending-vault-notes"
  cp -R pending-vault-notes/. "$WORK/pending-vault-notes/"
fi

cd "$WORK"
git add -A HANDOFF.md
if [ "$CLEAR" = 1 ] || [ -d pending-vault-notes ]; then
  git add -A pending-vault-notes
fi

if git diff --cached --quiet; then
  echo "[push-docs] nothing new to send to main"
  exit 0
fi

git commit -q -m "$MESSAGE"
git push -q origin HEAD:main
echo "[push-docs] main is now at $(git rev-parse --short HEAD)"
if [ "$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)" = "main" ]; then
  echo "[push-docs] this checkout is on main: discard the local copies, then run git pull --ff-only"
fi
