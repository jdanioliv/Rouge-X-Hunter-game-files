# RougeXHunter — Architecture & Development Rules

## 1. Project Overview & Role
- **Game**: RougeXHunter (Roblox Action-RPG inspired by Hunter x Hunter & Deepwoken mechanics).
- **Core Systems**: Frame-accurate parry/feint combat, 6-affinity Nen Hexagon mathematics, Seiyaku contracts/budget engine, Water Divination & Meditation progression, DataStore v2 + MemoryStore atomic session persistence.
- **Your Role**: Principal Roblox Engineer. Write modular, server-authoritative, highly performant Luau code synced via Rojo/VS Code.

---

## 2. Technical Stack & Luau Standards
- **Luau Strict Typing**: Always start files with `--!strict`. All state, payloads, and configs must strictly consume schemas defined in `src/ReplicatedStorage/Shared/Types.luau`.
- **Server Authority**: 
  - The client is NEVER trusted for damage calculation, cooldown timers, memory slots, or Nen roll outcomes.
  - Clients send *Intents* (e.g., `AttackIntent`, `ParryIntent`, `HatsuIntent`, `FocusTick`); the server validates and calculates outcomes.
- **Zero Circular Dependencies**:
  - Keep `Shared/` purely functional (e.g., `NenHexagon.luau`, `SeiyakuBudget.luau`, `AwakeningOutcomes.luau`).
  - If two server services need data from each other, use lazy requires inside functions or event-driven signals rather than top-level requires.
- **No Deprecated Roblox APIs**: Use `task.wait`, `task.delay`, `task.spawn` (never `wait()` or `spawn()`). Use `ContextActionService` and `UserInputService` for input.

---

## 3. Architecture Blueprint
- `src/ReplicatedStorage/Shared/`:
  - `Types.luau`: Shared custom types (`PlayerState`, `PersistedData`, `SeiyakuBuild`, `MeditationState`).
  - `Constants.luau`: Global tuning values, frame timings, combat multipliers, session lock TTLs.
  - `Remotes.luau`: Authoritative central registry for RemoteEvents and RemoteFunctions.
  - Pure calculation modules (`NenHexagon`, `SeiyakuBudget`, `AwakeningOutcomes`).
- `src/ServerScriptService/Services/`:
  - `DataPersistenceService.luau`: `MemoryStoreService` locks + `UpdateAsync` atomic writes + Character wipe handling.
  - `PlayerStateService.luau`: Authoritative character state machine, aura snapshots, mutilation/bypassed penalty multipliers.
  - `CombatService.luau`: Hitboxes, 10-frame parry windows, posture breaks, downed handling, combat logging NPC clones.
  - `NenAffinityService.luau`: Hexagon efficiency math, memory slot verification (`TryLearnSkillNode`), Water Divination roll.
  - `SeiyakuService.luau` & `HatsuService.luau`: Contract validation and ability execution with dynamic condition checks.
  - `MeditationService.luau` & `WaterDivinationService.luau`: Safe aura opening minigame and ritual triggers.
- `src/StarterPlayer/StarterPlayerScripts/Client/`:
  - UI Controllers (`HUDController`, `SkillTreeController`, `SeiyakuController`, `AwakeningQTEController`, `MeditationController`).
  - Render Controllers (`AnimationController` with client prediction, `AuraVFXController` reading character attributes).

---

## 4. Communication & Coding Behavior Preferences
- **Direct & Modular**: Output production-ready Luau scripts directly without unnecessary conversational filler or placeholders.
- **Maintain Consistency**: When adding new systems, always update `Types.luau`, `Constants.luau`, `Remotes.luau`, and `Main.server.luau` init order in tandem.
- **Studio Debug Support**: Keep the `Constants.AUTO_AWAKEN_DEBUG` and `RunService:IsStudio()` overrides intact so Studio playtesting is never blocked by dormant Nen gates.
- **Defensive Persistence**: Any state change affecting inventory, cards, or character life must route through atomic saves with session-lock validation.

---

## 5. Agentic OS — Multi-Agent Co-Optimization

You (Claude Opus 5) are the author, one of three peer engineers. **Hermes
(Ox Alpha)** independently verifies your work — see `HERMES.md`. **Gemini**
plans before you write code and reviews alongside Hermes after — see
`GEMINI.md`. Every non-trivial feature, refactor, or bug fix should go
through the co-optimization pipeline rather than landing unreviewed.

- **Standard**: `templates/REVIEW_RUBRIC.md` — shared, non-negotiable, both
  agents graded against it identically.
- **Skills**: `.claude/skills/dual-code|dual-refactor|dual-debug/SKILL.md` —
  exact handoff steps, input/output paths, NEVER-DO guardrails.
- **Orchestrator**: `node scripts/co_optimizer.js --mode <mode> ...` —
  see the Command block in each skill file.
- **Memory**: `memory/routers/SYSTEMS.md`, `NETWORKING.md`, `ASSETS.md` —
  sub-area indexes; `memory/second_brain.html` — searchable visual map.
- **Dashboard**: `dashboard/index.html`, served by `server/runner.js` at
  `http://127.0.0.1:4004` — Co-Optimization Studio, Artifacts/Review feed,
  live output stream, Second Brain embed.
- **Game Notes**: `GameNotes/` — Obsidian vault, `00-Home.md` is the entry
  point. `scripts/lib/routerSync.js` appends every co-optimization run to
  that day's note under `GameNotes/Daily/` automatically — no manual step.

**Golden Rule**: when a file is created, modified, or moved during a
co-optimization run, the active agent updates the relevant router in the
same turn. `scripts/lib/routerSync.js` does this automatically for
co-optimizer runs — don't bypass it in manual sessions.

**You cannot approve your own "done."** After Stage 3, Hermes independently
re-verifies your refined code against real lint evidence, and Hermes's count
— not your self-report — decides whether anything gets written. See
`templates/REVIEW_RUBRIC.md` § External Evidence & Independent Verification.

<!-- AGENTIC-OS:RECENT-CHANGES:START -->
- `2026-09-20T01:00:00.360Z` **weekly-2026-09-20** proposed cleanup for: `0 nightly report(s), 41 stale ref(s)` — see output/reviews/weekly/2026-09-20_proposal.md
- `2026-09-13T01:00:00.791Z` **weekly-2026-09-13** proposed cleanup for: `0 nightly report(s), 41 stale ref(s)` — see output/reviews/weekly/2026-09-13_proposal.md
- `2026-08-30T01:00:00.593Z` **weekly-2026-08-30** proposed cleanup for: `0 nightly report(s), 41 stale ref(s)` — see output/reviews/weekly/2026-08-30_proposal.md
<!-- AGENTIC-OS:RECENT-CHANGES:END -->

## 6. Session Documentation (Obsidian vault -> GitHub) — every session, no exceptions
- `GameNotes/` is the Obsidian vault AND its own git repo (remote `origin` =
  https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault, branch `main`). The
  game repo's `.gitignore` excludes it on purpose. Start at `GameNotes/00-Home.md`.
- Before ending ANY working session, run the `/session-log` routine
  (`.claude/skills/session-log/SKILL.md`):
  1. `node scripts/vault_session.js new --title "..." --summary "..."` (creates
     `GameNotes/Sessions/<date>-<slug>.md`, logs it to the daily note, rebuilds the index).
  2. Fill the session note: goal, files changed, decisions, verification, open threads.
  3. Write the day's `## Summary` in `GameNotes/Daily/<date>.md` (never inside the markers).
  4. Update every `Systems/`, `Reference/` or `Web-Hub/` note whose subject changed.
  5. `npm run vault:lint` (zero dangling wikilinks), then
     `npm run vault:publish -- --message "Session <date>: <title>"`.
- Vault notes cite code as `path/File.luau:LINE`. If a note and the code disagree, the
  code is right: fix the note in the same turn.
- Never put `.env` values or keys in the vault. Never force-push or rewrite its history.
