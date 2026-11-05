---
name: dual-debug
description: Three models independently diagnose an error trace, cross-evaluate each other's hypotheses, then output one verified fix. Use for a real bug/error trace, not a hypothetical.
---

# /dual-debug

Triggers `scripts/co_optimizer.js --mode dual-debug` on an error trace.

## Trigger
User pastes (or points to) an actual error/stack trace/repro and wants a
verified root-cause fix — not a design review (use `/dual-code`/`/dual-refactor`).

## Handoff (must happen in this order)
1. **Independent hypotheses (parallel)** — Claude, Hermes, and Gemini each
   generate their OWN root-cause hypothesis + confidence %, blind to the
   other two's answers.
2. **Cross-evaluation (parallel)** — each of the three reviews the OTHER
   two's hypotheses against its own and states what's right/wrong and why.
3. **Claude synthesizes** the single verified fix from all three hypotheses
   and cross-evals: states the confirmed root cause (explicitly rejecting
   whichever hypothesis/es were disproved), then the patch. Emits
   `REMAINING_CRITICAL_ISSUES:` (informational) and, if `--target` was
   given, a `FINAL_FILE:` block.
3b. If a fix file was produced, **Hermes independently re-verifies it**
   against real lint evidence — Hermes's count is authoritative, not
   Claude's or Gemini's.
4. Fix is only written to `output/artifacts/` (and the live file, with
   `--apply`) once Hermes confirms critical issues = 0.

## Input / Output paths
- In: `--trace "<error text>"` (or a relative path to a log file) `[--target <file>]`
- Out: `output/reviews/<timestamp>_dual-debug/` with all three hypotheses,
  all three cross-evals, and the synthesized fix; `output/artifacts/`;
  `runs.log`; router auto-update.

## Command
```
node scripts/co_optimizer.js --mode dual-debug --trace "attempt to index nil with 'Character'" --target src/ServerScriptService/Services/PlayerStateService.luau
```

## NEVER DO
- NEVER let one model see another's hypothesis before Stage 1 completes —
  independence is the point; a hint-primed second opinion isn't a real
  cross-check.
- NEVER synthesize a fix that ignores a cross-evaluation's disproof of a
  hypothesis — state explicitly which hypothesis was rejected and why.
- NEVER apply a fix to the live file without `--apply`.
- NEVER guess at a root cause with no trace/repro text — ask for one instead.
