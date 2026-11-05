# Router: Networking

All client/server boundary crossings, by contract.

## Authoritative registry
Every Remote lives in `src/ReplicatedStorage/Shared/Remotes.luau` — no ad hoc
`Instance.new("RemoteEvent")` elsewhere. If you can't find a Remote you need
there, it doesn't exist yet; add it there first, then reference it.

## Contract rule
Clients fire **Intents** (`AttackIntent`, `ParryIntent`, `HatsuIntent`,
`FocusTick`) — never outcomes. The server validates type/range/rate-limit on
every handler and computes the outcome. See `templates/REVIEW_RUBRIC.md` §3.

## Payload shapes
Every payload that crosses a Remote must have a matching type in
`src/ReplicatedStorage/Shared/Types.luau`. A Remote with an untyped payload
is a rubric violation (CRITICAL under §1).

## Known boundary-sensitive services
`CombatService`, `PlayerStateService`, `NenAffinityService`,
`WaterDivinationService` compute outcomes the client must never predict —
particularly RNG-derived results (Nen rolls). Never leak seeds or pre-roll
results over a Remote.

<!-- AGENTIC-OS:RECENT-CHANGES:START -->
<!-- AGENTIC-OS:RECENT-CHANGES:END -->
