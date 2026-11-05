---
name: dual-code
description: End-to-end 3-stage Claude/Hermes co-optimization loop for a NEW feature or system. Use when the user wants a new Luau service, controller, or state machine built and adversarially reviewed before it lands.
---

# /dual-code

Triggers `scripts/co_optimizer.js --mode dual-code` for a brand-new feature.

## Trigger
User asks to build a new system/service/controller and wants it peer-reviewed
before landing (not a quick throwaway snippet).

## Handoff (must happen in this order)
1. **Claude (Stage 1)** — implement from the prompt + `templates/REVIEW_RUBRIC.md`.
   State state machines and Remote/API contracts explicitly.
2. **Hermes/Ox Alpha (Stage 2)** — adversarial audit: race conditions, listener
   leaks, state sync, GC/perf, edge cases. Diff-style patches, severity-tagged.
3. **Claude (Stage 3)** — resolve every CRITICAL/MAJOR, merge valid perf fixes,
   verify compatibility with `Types.luau`/`Constants.luau`/`Remotes.luau`.
   Emit `REMAINING_CRITICAL_ISSUES: <n>` and a `FINAL_FILE:` fenced block.
4. **Stage 4 (automatic)** — loop 2→3 (max 3 rounds) until 0 critical issues,
   then write to `output/artifacts/`. Only writes into the live target path
   with `--apply`.

## Input / Output paths
- In: `--prompt "<feature request>"` `[--target <relative/path.luau>]`
- Out: `output/reviews/<timestamp>_dual-code/` (full transcript + summary.json),
  `output/artifacts/<run-id>__<file>` (final code), `runs.log` (tail).
- Router update: `CLAUDE.md` and `HERMES.md` get a "Recent Automated Changes"
  entry automatically (`scripts/lib/routerSync.js`) — same run, no manual step.

## Command
```
node scripts/co_optimizer.js --mode dual-code --prompt "..." [--target src/...] [--apply]
```

## NEVER DO
- NEVER skip Stage 2 (Hermes) — code that never faced adversarial review does
  not count as co-optimized.
- NEVER write to the live target file without `--apply` explicitly passed.
- NEVER declare 0 critical issues without the machine-readable
  `REMAINING_CRITICAL_ISSUES:` line — if either agent doesn't comply, the run
  fails closed (nothing gets written) rather than guessing.
- NEVER invent a new top-level DataModel path — new files must land inside
  the tree `default.project.json` already maps.
