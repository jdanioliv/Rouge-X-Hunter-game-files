---
name: dual-refactor
description: Reviewer and Gemini both profile/benchmark an existing file for perf and bugs; Claude synthesizes the production refactor. Use when the user wants an existing Luau file optimized without changing its behavior/API.
---

# /dual-refactor

Triggers `scripts/co_optimizer.js --mode dual-refactor` on an existing file.

## Trigger
User names an existing file and wants it optimized, cleaned up, or checked
for perf/bugs — not a from-scratch feature (use `/dual-code` for that).

## Handoff (must happen in this order)
1. **Reviewer + Gemini (Stage 1, parallel)** — both profile the file
   independently: perf bottlenecks, GC pressure, race conditions, bugs,
   ranked by rubric severity.
2. **Claude (Stage 2)** — synthesize the refactor resolving both sets of
   findings. Preserve the public API/Remote contract unless a finding
   requires changing it (call that out explicitly if so). Emit
   `REMAINING_CRITICAL_ISSUES:` (informational only) and `FINAL_FILE:`.
3. **Re-check loop (automatic)** — Reviewer independently re-reviews the
   refactor against real lint evidence; Reviewer's count, not Claude's or
   Gemini's, gates the loop. Repeat Stage 2 up to 3 rounds until Reviewer
   confirms 0 critical issues.
4. Write to `output/artifacts/`; only overwrite the live file with `--apply`.

## Input / Output paths
- In: `--target <relative/path.luau>` (required, must already exist)
- Out: same layout as `/dual-code` — `output/reviews/<timestamp>_dual-refactor/`,
  `output/artifacts/`, `runs.log`, router auto-update.

## Command
```
node scripts/co_optimizer.js --mode dual-refactor --target src/ServerScriptService/Services/CombatService.luau [--apply]
```

## NEVER DO
- NEVER change the file's public Remote/API contract silently — a contract
  change must be called out in the Stage 2 output in plain text.
- NEVER apply to the live file without `--apply`.
- NEVER treat a MINOR/NIT finding as blocking — only CRITICAL/MAJOR gate the
  write, per Reviewer's independent recheck, never Claude's or Gemini's claim.
- NEVER refactor a file that doesn't exist yet — that's `/dual-code`.
