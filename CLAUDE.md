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