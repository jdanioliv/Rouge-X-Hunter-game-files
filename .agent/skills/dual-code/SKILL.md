---
name: dual-code
description: End-to-end co-optimization loop for a NEW feature or system - Gemini plans, Claude implements, Reviewer+Gemini review, Reviewer verifies. Use when the user wants a new Luau service, controller, or state machine built and adversarially reviewed before it lands.
---

# /dual-code

Triggers `scripts/co_optimizer.js --mode dual-code` for a brand-new feature.

## Trigger
User asks to build a new system/service/controller and wants it peer-reviewed
before landing (not a quick throwaway snippet).

## Handoff (must happen in this order)
0. **Gemini (Stage 0)** — plans before any code exists: approach, files/state/
   API touched, edge cases. Claude drafts against this plan, not from a blank page.
1. **Claude (Stage 1)** — implement from the prompt + Gemini's plan +
   `templates/REVIEW_RUBRIC.md`. State state machines and Remote/API contracts.
2. **Reviewer + Gemini (Stage 2, parallel)** — both audit independently:
   race conditions, listener leaks, state sync, GC/perf, edge cases. Diff-style
   patches, severity-tagged.
3. **Claude (Stage 3)** — resolve every CRITICAL/MAJOR from BOTH reviewers,
   merge valid perf fixes, verify compatibility with `Types.luau`/`Constants.luau`/
   `Remotes.luau`. Emit `REMAINING_CRITICAL_ISSUES: <n>` (informational) and `FINAL_FILE:`.
3b. **Reviewer independently re-verifies** the refined code against real lint
   evidence — Reviewer's count, not Claude's or Gemini's, is authoritative.
4. **Stage 4 (automatic)** — loop 2→3b (max 3 rounds) until Reviewer confirms 0
   critical issues, then write to `output/artifacts/`. Only writes into the
   live target path with `--apply`.

## Input / Output paths
- In: `--prompt "<feature request>"` `[--target <relative/path.luau>]`
- Out: `output/reviews/<timestamp>_dual-code/` (full transcript + summary.json),
  `output/artifacts/<run-id>__<file>` (final code), `runs.log` (tail).
- Router update: `CLAUDE.md`, `GEMINI.md` and today's
  `GameNotes/Daily/<date>.md` all get an entry automatically
  (`scripts/lib/routerSync.js`) — same run, no manual step.

## Command
```
node scripts/co_optimizer.js --mode dual-code --prompt "..." [--target src/...] [--apply]
```

## NEVER DO
- NEVER skip Stage 2 (Reviewer) — code that never faced adversarial review does
  not count as co-optimized. Gemini's review is additional, not a substitute.
- NEVER write to the live target file without `--apply` explicitly passed.
- NEVER trust Claude's or Gemini's critical count as the stop condition —
  only Reviewer's independent re-verification gates the write. If Reviewer
  doesn't comply with the machine-readable line, the run fails closed.
- NEVER invent a new top-level DataModel path — new files must land inside
  the tree `default.project.json` already maps.
