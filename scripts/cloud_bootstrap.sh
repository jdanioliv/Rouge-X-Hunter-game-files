#!/usr/bin/env bash
# Prepares a Claude Code cloud session for this project. Safe to re-run. Pushes nothing.
#
#   bash scripts/cloud_bootstrap.sh            put the vault in GameNotes/, install dependencies
#   bash scripts/cloud_bootstrap.sh --graph    also install graphify, for npm run vault:graph
#
# The vault tools expect the vault at GameNotes/, which this repo ignores. A cloud session only
# has it when the owner attaches the vault repo, and the docs do not say where a second repo gets
# cloned, so this looks for it, then tries GitHub. A failed lookup is reported, never fatal.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

VAULT_NAME="Rouge-X-Hunter-obsidian-vault"
WEB_NAME="Rouge-X-Hunter-WebApp"
VAULT_URL="https://github.com/jdanioliv/$VAULT_NAME.git"
VENV="$HOME/.venvs/graphify"
WITH_GRAPH=0
[ "${1:-}" = "--graph" ] && WITH_GRAPH=1

say() { printf '[bootstrap] %s\n' "$*"; }

# Finds a checkout by folder name or by its origin URL, since a proxied URL still names the repo.
find_repo() {
  local name="$1" dir url
  for dir in "$ROOT"/../*/ "$ROOT"/../../*/ "$HOME"/*/ "$HOME"/*/*/; do
    [ -d "${dir}.git" ] || continue
    url="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
    case "$(basename "$dir") $url" in
      *"$name"*) (cd "$dir" && pwd); return 0 ;;
    esac
  done
  return 1
}

copy_identity() {
  local key value
  for key in user.name user.email; do
    if ! git -C GameNotes config "$key" >/dev/null 2>&1; then
      value="$(git config "$key" 2>/dev/null || true)"
      [ -n "$value" ] && git -C GameNotes config "$key" "$value"
    fi
  done
}

vault_state="MISSING"
vault_reason="not attached to this session, and not found nearby"
if [ -f GameNotes/00-Home.md ]; then
  vault_state="OK (already in GameNotes/)"
else
  if [ -e GameNotes ]; then
    # Something is there, but it is not the vault. Never delete what this script did not create.
    rescue="GameNotes.rescued.$(date +%s)"
    mv GameNotes "$rescue"
    say "moved an existing GameNotes/ with no vault in it to $rescue"
  fi

  attached="$(find_repo "$VAULT_NAME" || true)"
  if [ -n "$attached" ]; then
    # A real clone, not a symlink, so paths stay inside this repo for the lint and graph tools.
    origin="$(git -C "$attached" remote get-url origin)"
    if err="$(git clone -q "$attached" GameNotes 2>&1)"; then
      git -C GameNotes remote set-url origin "$origin"
      if git -C GameNotes fetch -q origin main 2>/dev/null && git -C GameNotes checkout -q -B main origin/main 2>/dev/null; then
        vault_state="OK (from the repo attached at $attached)"
      else
        vault_state="OK, BUT NOT UPDATED (could not fetch GitHub from $attached, so publishing may fail)"
      fi
    else
      vault_reason="found at $attached but could not copy it: $err"
    fi
  fi

  if [ ! -f GameNotes/00-Home.md ]; then
    if err="$(GIT_TERMINAL_PROMPT=0 timeout 60 git clone -q "$VAULT_URL" GameNotes 2>&1)"; then
      vault_state="OK (cloned from GitHub)"
    else
      rm -rf GameNotes
      [ -z "$attached" ] && vault_reason="not attached to this session, and GitHub refused the clone: $(printf '%s' "$err" | tail -1)"
    fi
  fi
fi
[ -f GameNotes/00-Home.md ] && copy_identity

if [ ! -d node_modules ]; then
  if npm ci --silent >/dev/null 2>&1; then say "npm dependencies installed"; else say "npm install failed. The vault tools do not need it"; fi
fi

if [ "$WITH_GRAPH" = 1 ]; then
  if [ -x "$VENV/bin/python" ] || [ -x "$VENV/Scripts/python.exe" ]; then
    say "graphify already installed"
  # graphifyy, with two y's, is the package's real name on PyPI.
  elif python3 -m venv "$VENV" && "$VENV/bin/python" -m pip install --quiet --disable-pip-version-check graphifyy; then
    say "graphify installed at $VENV"
  else
    say "graphify install failed. Publish anyway, and say the graph was not rebuilt"
  fi
fi

git fetch -q origin 2>/dev/null || say "could not fetch the game repo from GitHub"
branch="$(git rev-parse --abbrev-ref HEAD)"

echo
say "game repo: $branch at $(git rev-parse --short HEAD)"
[ "$branch" = "main" ] && say "you are on main: create a branch before changing code, see HANDOFF.md"

unmerged="$(git branch -r --no-merged origin/main 2>/dev/null | grep -v 'HEAD' | sed 's/^ *//' | tr '\n' ' ')"
[ -n "$unmerged" ] && say "branches not merged into main: $unmerged"

pending="$(ls pending-vault-notes/*.md 2>/dev/null | wc -l | tr -d ' ')"
[ "$pending" != "0" ] && say "$pending session note(s) waiting in pending-vault-notes/: move them into the vault, see HANDOFF.md"

web="$(find_repo "$WEB_NAME" || true)"
say "web repo:  ${web:-not attached}"

say "vault:     $vault_state"
if [ -f GameNotes/00-Home.md ]; then
  say "vault at:  $(git -C GameNotes rev-parse --abbrev-ref HEAD) $(git -C GameNotes rev-parse --short HEAD)"
  node scripts/vault_lint.js --warn | head -5
else
  say "reason:    $vault_reason"
  say "Search for it, then ask the owner to attach $VAULT_NAME to a new session."
  say "Until then, write session notes to pending-vault-notes/. See HANDOFF.md."
fi
