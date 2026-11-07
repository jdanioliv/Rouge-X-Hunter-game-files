# RougeXHunter — Dual-Agent Review Rubric

Shared, non-negotiable standard for all three peer engineers — Claude Opus 5
(author), Reviewer (independent verifier), and Gemini (planner and
second reviewer). Every critique and every refinement is graded against this
file. A finding tagged `CRITICAL` blocks the final write until resolved.

## 1. Game State & Determinism
- Every service/controller has explicit init (`.new()` / `Init()`) and explicit
  teardown — no implicit global state that outlives a round or a player.
- Every `:Connect()` has a matching `:Disconnect()` path (player leaving,
  round ending, object destroyed). Use `Shared/Util/Signal.luau` for custom
  events so listeners are trackable, not raw `BindableEvent` sprawl.
- No `--!strict` violations. Every payload crossing the client/server boundary
  must match a type in `Types.luau`.

## 2. Memory & GC
- Zero per-frame table/closure allocations inside `RunService.Heartbeat` /
  `Stepped` / hot combat loops. Reuse buffers; pool Instances that spawn
  repeatedly (hitboxes, VFX parts, projectile clones).
- No unbounded growth: caches, cooldown maps, and combat-log tables must evict
  entries on player-leaving or TTL expiry.
- Prefer `task.spawn`/`task.delay`/`task.wait` over legacy `spawn()`/`wait()`.

## 3. Client/Server Boundaries
- Server is authoritative for damage, cooldowns, Nen rolls, memory slots, and
  all DataStore-bound state. Clients send *Intents* only, never outcomes.
- Every `RemoteEvent`/`RemoteFunction` handler validates argument types,
  ranges, and rate-limits the firing player before acting — assume a hostile
  client on every remote.
- No remote fires outcome data the client could use to predict/cheat future
  rolls (e.g. never leak the RNG seed or pre-roll results).

## 4. Concurrency & Persistence
- `DataPersistenceService` writes use `MemoryStoreService` locks or
  equivalent session-locking around every `UpdateAsync` — no lost-update races
  across duplicate sessions.
- No two services mutate the same player's persisted state without going
  through the same lock path.

## 5. Modular Architecture
- No circular top-level `require()`. Cross-service dependencies use
  function-scoped lazy requires or `Signal`-based events.
- New shared types/constants/remotes go in `Types.luau` / `Constants.luau` /
  `Remotes.luau` — never inlined ad hoc in a service.
- File lands in the folder the Rojo tree (`default.project.json`) already
  maps — no new top-level DataModel paths without updating that file too.

## 6. Performance
- Flag any O(n²)+ loop over players/entities per frame.
- Flag any `Instance:FindFirstChild` / `WaitForChild` inside a hot loop instead
  of cached at init.
- Flag any risk of frame-rate drop from unbatched `Instance.new` / VFX bursts.

## Severity Tags
`CRITICAL` (blocks write) · `MAJOR` (must fix before merge) · `MINOR`
(note, non-blocking) · `NIT` (style only).

## External Evidence & Independent Verification
Two rules the orchestrator enforces in code, not just policy:

1. **The proposer never certifies its own "done."** Claude may self-report a
   `REMAINING_CRITICAL_ISSUES` count after refining code, but that number is
   informational only. Reviewer — the reviewer, not the author — independently
   re-counts against the same code, and *that* count is what gates whether
   anything gets written. An LLM re-reviewing its own recent output tends to
   rubber-stamp it; a second, independent pass catches what self-review
   misses.[^self-correct]
2. **Deterministic evidence outranks prose.** When a Luau linter (`selene` or
   `luau-analyze`) is available on PATH, its real output is injected into
   every critique and verification prompt as ground truth. A reviewer may not
   argue away a lint failure in text — a compiler/linter says something the
   code's own author couldn't have known at generation time, which is exactly
   what makes review valuable instead of redundant.[^critic]

Both rules exist because text-only self-review is measurably weak: models
asked to check their own reasoning without new information change *correct*
answers to *incorrect* ones about as often as the reverse.

3. **A second opinion is not a second gate.** Gemini plans before code exists
   and reviews alongside Reviewer after it does — every CRITICAL/MAJOR finding
   Gemini raises must be addressed in the next revision, same as Reviewer's.
   But the write-gate itself stays single-owner: Reviewer's independent count,
   not a Reviewer+Gemini consensus or vote. Splitting the gate across two
   verifiers trades a clear, testable authority for deadlock risk and doubled
   cost, without a demonstrated correctness win over one dedicated,
   evidence-grounded verifier.

[^self-correct]: Huang et al., "Large Language Models Cannot Self-Correct Reasoning Yet," ICLR 2024.
[^critic]: Gou et al., "CRITIC: Large Language Models Can Self-Correct with Tool-Interactive Critiquing," ICLR 2024.

## Anti-Reward-Hacking Guardrails
- A reviewer that finds nothing must still address the lint evidence
  explicitly ("no linter available" or "lint clean, N/A") — silence is not
  a pass.
- Declaring victory with unsupported claims ("looks secure," "should be fine
  now") without pointing at a specific rubric section or piece of evidence
  does not count as resolving a finding.
- A CRITICAL finding is a veto: it blocks the write regardless of how well
  everything else scores, exactly like the hallucination-veto pattern in
  rubric-based LLM-judge design generally.

## Golden Rule
Whenever a file is created, modified, or moved during a co-optimization run,
the agent that touched it updates the relevant router (`CLAUDE.md`,
`GEMINI.md`, or the matching `memory/routers/*.md`) **in the
same turn**.
Router writes go through a per-file lockfile (`scripts/lib/routerSync.js`) so
two overlapping runs (e.g. a manual trigger during the nightly audit) can't
silently overwrite each other's history — a known multi-agent failure mode
(concurrent writers to a shared file, last write wins).
