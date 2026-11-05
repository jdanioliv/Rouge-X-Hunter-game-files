# Router: Assets & Build

## Rojo mapping (`default.project.json`)
- `src/ReplicatedStorage/Shared` → `ReplicatedStorage.Shared`
- `src/ServerScriptService` → `ServerScriptService`
- `src/StarterPlayer/StarterPlayerScripts/Client` → `StarterPlayer.StarterPlayerScripts.Client`

New files MUST land under one of these three source roots. A new top-level
DataModel path needs `default.project.json` updated in the same commit —
the co-optimizer's router-sync will flag this if `--target` falls outside
the existing tree.

## Package management
`wally.toml` — realm `shared`, registry `UpliftGames/wally-index`. Add
third-party Luau deps here, not via manual `Packages/` edits.

## Ignored build artifacts (`.gitignore`)
`/Packages`, `/ServerPackages`, `/DevPackages`, `sourcemap.json`, `*.rbxl*`,
`*.rbxm*` — none of these should ever appear in a co-optimizer diff/artifact.

## Agentic OS build outputs (new, also gitignored)
`node_modules/`, `.env`, `output/`, `runs.log`, `memory/index.json` — all
regenerable; never treat them as source of truth, only `templates/`,
`scripts/`, `server/`, `dashboard/`, and the routers themselves are source.

## Obsidian vault (`GameNotes/`, separate repo, gitignored here)
Own git repo, remote github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault. Tools:
`scripts/vault_session.js` (new/index/status/publish), `scripts/vault_lint.js`.
Process: `GameNotes/Process/Session-Documentation.md`.

## Picking up the work
`HANDOFF.md` holds current state for a new session. `scripts/cloud_bootstrap.sh` prepares a cloud session, and
`scripts/push_docs_to_main.sh` sends the handoff to `main`. `tools/blender-pipeline/` backs up the asset pipeline.

<!-- AGENTIC-OS:RECENT-CHANGES:START -->
<!-- AGENTIC-OS:RECENT-CHANGES:END -->
