# RougeXHunter — Agentic OS Quick Start

Multi-Agent Peer-Review & Code Optimization Engine. Claude Opus 5 (`claude -p`,
author), Hermes (OpenRouter, model configurable, independent verifier), and
Gemini (Google Generative Language API, planner + second reviewer) draft,
plan, cross-examine, and verify RougeXHunter code before it lands. Full
architecture: `CLAUDE.md` / `HERMES.md` / `GEMINI.md` /
`templates/REVIEW_RUBRIC.md`.

## Prerequisites
- Node.js 18+ (you have Node 24 — fine).
- [Claude Code CLI](https://docs.claude.com) installed and on PATH: `claude --version`
  should print a version. If it's elsewhere, set `CLAUDE_BIN` in `.env`.
- An [OpenRouter](https://openrouter.ai/keys) API key. The model Hermes uses
  is configurable (`OX_ALPHA_MODEL` in `.env`) — see `.env.example` for the
  current recommendation and why it's changed before.
- A Gemini API key from [Google AI Studio](https://aistudio.google.com/apikey)
  — free tier, no card required. **Not** the same as a Gemini Advanced/Google
  AI Pro subscription, which does not include API access at all.
- Optional but recommended: `selene` or `luau-analyze` on PATH (installable
  via Aftman/Rokit, which you already have). Without one, review still runs,
  just without real linter evidence grounding it — see "Design notes" below.

## One-time setup
```bash
npm install
cp .env.example .env
# then edit .env: paste your real OPENROUTER_API_KEY
```

## Launch everything
```bash
# Option A - PM2 (recommended, survives terminal close / reboot):
npm install -g pm2
pm2 start ecosystem.config.js
pm2 save

# To also survive a full reboot on Windows: `pm2 startup` needs systemd/launchd
# and doesn't apply here. Instead, drop a tiny .vbs into your Startup folder
# (Win+R -> shell:startup) that silently runs `pm2 resurrect` at login - no
# admin rights needed. Ask your agent for the exact script if you skipped this.

# Option B - no PM2, just the server, foreground:
npm run start
```
Then open **http://127.0.0.1:4004** — that's the Command Centre dashboard.

## Run a co-optimization pass from the CLI
```bash
npm run co-optimize -- --mode dual-code --prompt "Add a Hatsu cooldown-reset item" --target src/ServerScriptService/Services/HatsuService.luau
npm run co-optimize -- --mode dual-refactor --target src/ServerScriptService/Services/CombatService.luau
npm run co-optimize -- --mode dual-debug --trace "attempt to index nil with 'Character'" --target src/ServerScriptService/Services/PlayerStateService.luau
```
Add `--apply` to write the verified result directly to the target file.
Without it, results land in `output/artifacts/` for you to review and copy in
yourself — this is the default on purpose.

## Skills (in Claude Code / compatible agents)
`/dual-code`, `/dual-refactor`, `/dual-debug` — see `.claude/skills/*/SKILL.md`
(mirrored in `.agent/skills/`) for exact triggers and guardrails.

## Rebuild the Second Brain
```bash
npm run update-memory
```
Then open `memory/second_brain.html` directly (works standalone, no server
needed) or view it embedded in the dashboard's Section 4.

## Game notes (Obsidian)
`GameNotes/` at the repo root is an Obsidian vault — open that folder
directly in Obsidian. Start at `GameNotes/00-Home.md`. Every
`dual-code`/`dual-refactor`/`dual-debug` run, nightly audit, and weekly
cleanup automatically appends a line to that day's note under
`GameNotes/Daily/<date>.md` (via `scripts/lib/routerSync.js`) — no manual
step. The top `## Summary` section of each daily note is yours to fill in
by hand. Change the vault's location with `OBSIDIAN_NOTES_DIR` in `.env` if
you ever move it.

The vault is its own git repo (github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault),
ignored by this one. Every working session documents itself there with
`/session-log`: `npm run vault:new`, `npm run vault:lint`, `npm run vault:publish`.
See `GameNotes/Process/Session-Documentation.md`.

## Scheduled routines
Handled by the `agentic-os-scheduler` PM2 process (`scripts/routines/scheduler.js`,
node-cron — cross-platform, no OS Task Scheduler needed):
- Nightly (`NIGHTLY_AUDIT_CRON`, default 02:00): Hermes scans the day's Git
  commits against the rubric → `output/reviews/nightly/<date>.md`.
- Weekly (`WEEKLY_CLEANUP_CRON`, default Sun 03:00): Claude reads unresolved
  nightly reports + stale router references → **proposal only** at
  `output/reviews/weekly/<date>_proposal.md`. Run manually with `--apply` if
  you want it to write fixes directly — this is never automatic.

`.ps1`/`.sh` equivalents exist under `scripts/routines/` if you'd rather use
Windows Task Scheduler or cron instead of the PM2 scheduler.

## Safety defaults (read before turning off)
- Nothing is ever written to a live game file without `--apply`.
- The weekly cleanup never applies fixes automatically, even with the
  scheduler running — `--apply` must be passed by a human.
- A run that can't produce a machine-readable `REMAINING_CRITICAL_ISSUES: 0`
  fails closed (nothing written) rather than guessing.

## Design notes
Two architecture fixes worth knowing about, both grounded in published
multi-agent research (cited in full in `templates/REVIEW_RUBRIC.md`):

1. **Hermes verifies independently, not Claude.** Earlier versions gated the
   final write on Claude's own `REMAINING_CRITICAL_ISSUES` self-report — the
   same model checking its own work. Research on LLM self-correction
   (Huang et al., ICLR 2024) shows this is unreliable: without new
   information, self-review changes correct answers to wrong ones about as
   often as the reverse. Now Hermes re-reviews every refined file from
   scratch after Stage 3, and Hermes's count is what gates Stage 4 — Claude's
   self-report is kept in the log for transparency only.
2. **Real lint evidence, not just re-reading code as text.** When `selene` or
   `luau-analyze` is on PATH, its actual output is injected into every
   critique and verification prompt (`scripts/lib/luauLint.js`). A reviewer
   can't argue away a real lint failure in prose — this is the same
   "new-information" principle that makes the CRITIC (ICLR 2024) approach
   work: tool output the author didn't have at generation time, not another
   pass of the same text.
3. **Router writes are now lock-safe.** Two overlapping runs (say, a manual
   trigger during the nightly audit) used to be a lost-update race on
   `CLAUDE.md`/`HERMES.md` — last write wins, one run's history silently
   disappears. `scripts/lib/routerSync.js` now takes a per-file lockfile
   around each read-modify-write, so concurrent runs queue instead of
   clobbering each other.
4. **Daily notes are a view, not a dependency.** `syncRouters()` also
   appends to `GameNotes/Daily/<date>.md` using the same lockfile mechanism,
   but that write is wrapped in try/catch and only logs a warning on
   failure — a full disk or a locked Obsidian file should never fail a
   co-optimizer run that would otherwise have succeeded.
5. **Gemini plans and reviews, but doesn't get a second vote.** Gemini gives
   an independent first read before code exists (a plan for `dual-code`, a
   priority profile for `dual-refactor`, a third hypothesis for `dual-debug`)
   and a second independent critique alongside Hermes after Claude drafts or
   refines. Its findings must be addressed in the next revision — but the
   write-gate stays single-owner: Hermes's count, not a two-verifier
   consensus. See `templates/REVIEW_RUBRIC.md` § External Evidence and
   Independent Verification, rule 3, for why that's a deliberate choice and
   not an oversight. Calls degrade gracefully: if `GEMINI_API_KEY` isn't set
   or a call fails, the pipeline logs it and continues with Claude/Hermes
   alone rather than blocking a run on a third engineer being unavailable.

Cost tradeoff: each refinement round now makes one extra Hermes call (the
independent verification) plus, in most stages, a parallel Gemini call. Both
exist to make the write-gate harder to game with a confident-sounding
self-report or a single reviewer's blind spot — worth it for anything
landing with `--apply`, and Gemini's calls have a free tier so the added
cost in practice is mostly latency, not money.
