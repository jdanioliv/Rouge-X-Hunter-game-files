# Router: Systems

Gameplay services, one line each. Full detail lives in the file itself —
this is a pointer index, not a copy.

## `src/ServerScriptService/Services/`
- `CombatService.luau` — hitboxes, 10-frame parry windows, posture breaks, downed handling.
- `PlayerStateService.luau` — authoritative character state machine, aura snapshots, penalty multipliers.
- `DataPersistenceService.luau` — DataStore v2 + MemoryStore atomic locks, character wipe handling.
- `MeditationService.luau` — focus progression, server-side tick verification.
- `WaterDivinationService.luau` — cup interactions, authoritative Nen affinity roll.
- `NenAffinityService.luau` — Hexagon efficiency math, memory slot verification (`TryLearnSkillNode`).
- `NenAwakeningService.luau` — awakening gate logic; judges the QTE press by press and settles pending results when a player leaves.
- `SeiyakuService.luau` — contract validation, dynamic condition checks.
- `HatsuService.luau` — ability execution.

## `src/ReplicatedStorage/Shared/`
- `Types.luau` — every type crossing the client/server boundary.
- `Constants.luau` — tuning values, tick rates, TTLs.
- `Remotes.luau` — authoritative RemoteEvent/RemoteFunction registry.
- `NenHexagon.luau`, `SeiyakuBudget.luau`, `AwakeningOutcomes.luau`, `SeiyakuConfig.luau` — pure calc modules.
- `Util/Signal.luau` — custom event pattern (use instead of raw BindableEvents so listeners are trackable/disconnectable).

## `src/StarterPlayer/StarterPlayerScripts/Client/`
- `HUDController`, `SkillTreeController`, `SeiyakuController`, `AwakeningQTEController`,
  `MeditationController` — UI/input controllers, intents only, never outcomes.
- `AnimationController`, `AuraVFXController`, `DivinationVFXController`, `CombatController`,
  `HatsuController` — render/feedback controllers.

<!-- AGENTIC-OS:RECENT-CHANGES:START -->
<!-- AGENTIC-OS:RECENT-CHANGES:END -->
