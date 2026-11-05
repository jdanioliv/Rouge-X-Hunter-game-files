---
name: dual-debug
description: Both models independently diagnose an error trace, cross-evaluate each other's hypothesis, then output one verified fix. Use for a real bug/error trace, not a hypothetical.
---

# /dual-debug

Triggers `scripts/co_optimizer.js --mode dual-debug` on an error trace.

## Trigger
User pastes (or points to) an actual error/stack trace/repro and wants a
verified root-cause fix — not a design review (use `/dual-code`/`/dual-refactor`).

## Handoff (must happen in this order)
1. **Independent hypotheses (parallel)** — Claude and Hermes each generate
   their OWN root-cause hypothesis + confidence %, blind to the other's answer.
2. **Cross-evaluation (parallel)** — each model reviews the OTHER's hypothesis
   against its own and states what's right/wrong and why.
3. **Claude synthesizes** the single verified fix: states the confirmed root
   cause (explicitly rejecting whichever hypothesis cross-eval disproved),
   then the patch. Emits `REMAINING_CRITICAL_ISSUES:` and, if `--target` was
   given, a `FINAL_FILE:` block.
4. Fix is only written to `output/artifacts/` (and the live file, with
   `--apply`) once critical issues = 0.

## Input / Output paths
- In: `--trace "<error text>"` (or a relative path to a log file) `[--target <file>]`
- Out: `output/reviews/<timestamp>_dual-debug/` with both hypotheses, both
  cross-evals, and the synthesized fix; `output/artifacts/`; `runs.log`;
  router auto-update.

## Command
```
node scripts/co_optimizer.js --mode dual-debug --trace "attempt to index nil with 'Character'" --target src/ServerScriptService/Services/PlayerStateService.luau
```

## NEVER DO
- NEVER let one model see the other's hypothesis before Stage 1 completes —
  independence is the point; a hint-primed second opinion isn't a real
  cross-check.
- NEVER synthesize a fix that ignores a cross-evaluation's disproof of a
  hypothesis — state explicitly which hypothesis was rejected and why.
- NEVER apply a fix to the live file without `--apply`.
- NEVER guess at a root cause with no trace/repro text — ask for one instead.
