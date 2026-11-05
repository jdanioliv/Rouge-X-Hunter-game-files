# RougeXHunter — Game Files

A high-skill Action-RPG for Roblox inspired by Hunter x Hunter and Deepwoken, written in Luau and synced to Studio with Rojo. This is an unofficial fan project.

**Status: pre-alpha.** The core systems exist in code, but there is no world, zone or progression loop yet, and known bugs are still open. See the roadmap in the vault.

## The three repos
| Repo | Holds |
|---|---|
| [Rouge-X-Hunter-game-files](https://github.com/jdanioliv/Rouge-X-Hunter-game-files) | This repo: the game code and the Agentic OS tooling |
| [Rouge-X-Hunter-obsidian-vault](https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault) | All documentation. Checked out locally at `GameNotes/`, which this repo ignores |
| [Rouge-X-Hunter-WebApp](https://github.com/jdanioliv/Rouge-X-Hunter-WebApp) | The community website. On hold for now |

Start with the vault's [home page](https://github.com/jdanioliv/Rouge-X-Hunter-obsidian-vault/blob/main/00-Home.md). It documents every system below with code citations.

## What is in here
| Path | Contents |
|---|---|
| `src/ReplicatedStorage/Shared/` | Types, constants, the Remote registry, and pure math (hexagon, Seiyaku budget, awakening wheel) |
| `src/ServerScriptService/Services/` | Server-authoritative systems: combat, player state, persistence, Nen, meditation, Seiyaku, Hatsu |
| `src/StarterPlayer/StarterPlayerScripts/Client/` | HUD, input, animation and VFX controllers. Clients send intents, never outcomes |
| `scripts/`, `server/`, `dashboard/`, `templates/`, `memory/` | The Agentic OS: multi-model review pipeline, dashboard, routines. See `README_AGENTIC_OS.md` |
| `CLAUDE.md`, `HERMES.md`, `GEMINI.md` | Working rules for the AI engineers on this project |
| `Game_concept.md`, `IDEA.md` | The original game concept |

## Running the game
1. Install [Rojo](https://rojo.space), through Aftman or the editor extension.
2. Start the sync server:
   ```bash
   rojo serve
   ```
3. Open a place file in Roblox Studio and press **Connect** in the Rojo plugin.

`Constants.AUTO_AWAKEN_DEBUG` makes Studio players spawn awakened for testing.

## Running the tooling
```bash
npm install
cp .env.example .env
```
Fill in `.env`, which is gitignored. Setup details are in `README_AGENTIC_OS.md`.

## Working rules
- Every session ends by documenting itself in the vault with `/session-log`. See `CLAUDE.md` section 6.
- Never commit `.env` or any key.
