# RougeXHunter

_RougeXHunter_ is a high-skill, lore-accurate _Hunter x Hunter_ Action-RPG for Roblox built with a modular, Rojo-syncable Luau codebase. Designed to reject generic "bandit-beater" grinding tropes in favor of deep tactical depth, high-stakes combat, and permadeath mechanics, the project centers around an authentic Nen system, server-authoritative combat, and punishing risk-reward progression.

## Core Design Philosophy & Overview

- **Lore-Accurate Nen System**: Full implementation of the Nen Hexagon, category efficiency multipliers, memory slot caps (the "Kastro Penalty"), and a Seiyaku (Nen vow) engine that scales power based on strict conditional restrictions.
    
- **Tactical Combat**: Heavy focus on frame-precise defense, posture management, directional/Ryu aura distribution, and brutal grip execution mechanics similar to _Deepwoken_.
    
- **Permadeath & Risk**: Players navigate a finite Soul Node pool, brutal forced awakening risks, and severe consequences for reckless combat choices.
    

## Implemented Systems

### 1. Foundation & State Architecture

- **Server-Authoritative State Engine (`PlayerStateService`)**: Manages core attributes, including HP, Posture, Aura Pool, Soul Nodes (permadeath life counters), Memory Slots (100-slot cap), and active Combat Tags.
    
- **Advanced Defensive & Offensive States**:
    
    - **Basic Principles**: Toggleable `Ten` (containment), `Ren` (output), `Zetsu` (concealment/regen), and `Ken` (advanced defense).
        
    - **Ryu Distribution**: Dynamic, real-time offensive/defensive ratio shifting (e.g., 80/20 offensive vs. defensive aura focus).
        
    - **Downed & Execution Flow**: Downed state triggered upon depletion of health, bleed-out timers, and server-validated **Grip** finishers.
        
    - **Guard & Posture**: Posture accumulation on blocked attacks leading to Guard Break punishes and frame-trap vulnerability.
        

### 2. Nen Hexagon & Skill Memory Engine

- **Affinity Distribution (`NenHexagon` + `NenAffinityService`)**:
    
    - Implements canonical efficiency multipliers based on proximity to the player's natural affinity vertex.
        
    - Supports rare "in-between" hybrid node rolls.
        
- **Memory Slot Cap ("Kastro Penalty Engine")**:
    
    - Out-of-category skill learning imposes exponential memory costs against the 100-slot cap.
        
    - Prevents jack-of-all-trades builds and punishes inefficient Nen distribution.
        

### 3. Tactical Melee Combat System

- **Hitbox & Frame Validation (`CombatService` + `CombatController`)**:
    
    - Server-side spatial hitbox sweeps with strict latency and timing validation.
        
    - **10-Frame Parry Window**: Precise timing negates posture damage and opens counter-attack opportunities.
        
    - **Block & Guard Break**: Holding block consumes posture; breaking posture results in severe stun windows.
        

### 4. Data Persistence & Duplication Protection

- **Pipeline Architecture (`DataPersistenceService`)**:
    
    - Robust DataStore pipeline backed by `MemoryStore` session locks to completely prevent item/stat duplication on server hopping.
        
    - Features atomic `UpdateAsync` writes, automatic background saves, `BindToClose` cleanup flushes, and instant force-saves on character wipe (Soul Node depletion).
        
    - Gracefully degrades to Studio warnings when "Studio Access to API Services" is disabled.
        

### 5. Nen Awakening Gate

- **Dormant Spawning**: Players begin as normal humans devoid of active Nen.
    
- **Forced Awakening NPC (`AwakeningNPC`)**:
    
    - Interacting with an awakened entity triggers a high-risk 5-tier probability wheel:
        
        1. **Clean Awakening (35%)**: Safe aura node opening.
            
        2. **Lethal Exhaustion (25%)**: Triggers a 3-second timing QTE (`Space`). Failure results in the immediate loss of a Soul Node.
            
        3. **Mutilation (20%)**: Permanent -10% Max HP and -15% Max Aura penalty on the current character.
            
        4. **Bypassed Fundamentals (15%)**: Permanent -15% efficiency penalty to all non-innate Nen categories.
            
        5. **Fatal Overload (5%)**: Instant aura overload and Soul Node wipe.
            
    - Debug feature: Set `AUTO_AWAKEN_DEBUG = true` in `Constants.luau` for instant awakening during testing.
        

### 6. Seiyaku (Nen vow) Engine & Custom Hatsu

- **Contract Budgeting (`SeiyakuConfig`, `SeiyakuBudget`, `SeiyakuService`)**:
    
    - Allows players to restrict their Hatsu abilities with self-imposed rules to massively boost damage, area of effect, or status effects.
        
    - Server verifies that conditions match the overall condition budget before allowing build submission.
        
- **Visual Editor (`SeiyakuController`, Toggle `K`)**:
    
    - Interactive interface allowing selection of up to 4 conditions (e.g., HP thresholds, time limits, target restrictions) and 3 modifiers (e.g., Guard Break, Blindness, Stun Extension, AoE expansion).
        
- **Runtime Hatsu Execution (`HatsuService`, Keybind `Q`)**:
    
    - At cast time, the server verifies all conditions against live `PlayerStateService` parameters.
        
    - Applies execution penalties (+25% aura cost for Bypassed builds) and post-cast consequences (such as temporary `Ten` seals, backfire damage, or extended cooldowns).
        

### 7. Interface, Animation, and Visual FX

- **Hexagonal Skill Tree (`SkillTreeController`, Toggle `N`)**:
    
    - Real-time visualization of the 6 Nen categories arranged at hexagon vertices. Live readouts of affinity percentage, memory slot consumption, and unlocked skills.
        
- **Attribute-Driven Aura FX (`AuraVFXController`)**:
    
    - Client-predicted, server-synchronized particle emitters that dynamic scale and tint based on active aura state (`Ten`, `Ren`, `Ken`) and individual RGB aura colors.
        
- **Animation Pipeline (`AnimationController`)**:
    
    - Weighted swing pools and client-side stance blending for responsive combat feel.
        

## Project Directory Layout

```
SRC/

├── ReplicatedStorage/

│ └── Shared/ -- Shared modules, configurations, and network definitions

│ ├── Util/

│ │ └── Signal.luau -- Custom signal utility class

│ ├── AwakeningOutcomes.luau -- Forced awakening table weights and outcomes

│ ├── Constants.luau -- Global balance values & debug flags

│ ├── NenHexagon.luau -- Affinity efficiency & memory math calculations

│ ├── Remotes.luau -- Client-server remote event & function definitions

│ ├── SeiyakuBudget.luau -- Contract point allocation validator

│ ├── SeiyakuConfig.luau -- Conditions & modifiers definitions

│ └── Types.luau -- Type assertions & Luau interface definitions

│

├── ServerScriptService/

│ ├── Services/ -- Server-authoritative systems

│ │ ├── CombatService.luau -- Hitboxes, parry validation, posture, and grips

│ │ ├── DataPersistenceService.luau -- MemoryStore locks & DataStore pipeline

│ │ ├── HatsuService.luau -- Real-time Hatsu execution & condition checking

│ │ ├── NenAffinityService.luau -- Natural affinity rolls & skill slot tracking

│ │ ├── NenAwakeningService.luau-- Awakening wheel logic & QTE processing

│ │ ├── PlayerStateService.luau -- Core character stats, aura modes, and state machine

│ │ └── SeiyakuService.luau -- Contract validation & build saving

│ └── Main.server.luau -- Core server entry point & service bootstrapper

│

└── StarterPlayer/

└── StarterPlayerScripts/

└── Client/ -- Client-side controllers & user interface handlers

├── AnimationController.client.luau -- Combat animation state & blending

├── AuraVFXController.client.luau -- Client aura rendering & particle FX

├── AwakeningQTEController.client.luau-- Forced awakening timing bar UI

├── CombatController.client.luau -- Player combat input & prediction

├── HatsuController.client.luau -- Custom ability activation listener

├── HUDController.client.luau -- Main player HUD (HP, Posture, Aura bars)

├── SeiyakuController.client.luau -- Contract editor UI manager (Keybind K)

└── SkillTreeController.client.luau -- Nen Hexagon skill tree UI manager (Keybind N)
```

_Note: Server services dynamically discover dependencies within `ServerScriptService.Services`. Shared utility modules reside in `ReplicatedStorage.Shared`._

## Tooling & Syncing with Rojo

This project relies on **Rojo** for external code editing in modern code editors (VS Code / Cursor / Claude Code) and synchronization with Roblox Studio.

1. **Install Tooling**:
    
    Bash
    
    ```
    aftman add rojo-rbx/rojo
    ```
    
    _(Or install the official Rojo extension in your code editor)._
    
2. **Start Sync Server**:
    
    Bash
    
    ```
    rojo serve
    ```
    
3. **Connect Studio**:
    
    - Open your local `.rbxl` place file in Roblox Studio.
        
    - Open the Rojo Plugin tab and click **Connect**.
        

## Control Scheme & Keybinds

| Input Category        | Keybind               | Action / System Triggered                       |
| --------------------- | --------------------- | ----------------------------------------------- |
| **Melee Combat**      | `Left Mouse Button`   | Light Attack Combo                              |
| **Defensive**         | `F` (Tap)             | Timed Parry (10-frame activation window)        |
| **Defensive**         | `F` (Hold)            | Block / Guard Stance                            |
| **Aura Principles**   | `T`                   | Toggle **Ten** (Aura Enclosure)                 |
| **Aura Principles**   | `G`                   | Toggle **Ren** (Aura Output)                    |
| **Aura Principles**   | `Z`                   | Toggle **Zetsu** (Aura Suppression)             |
| **Aura Principles**   | `C`                   | Toggle **Ken** (Advanced Defense)               |
| **Aura Principles**   | `X`                   | Deactivate All Aura Principles                  |
| **Ryu Adjustment**    | `Ctrl + Scroll Wheel` | Shift Aura Ratio (Offense vs. Defense focus)    |
| **Abilities & Hatsu** | `Q`                   | Cast Stored Custom Hatsu Ability                |
| **User Interface**    | `N`                   | Toggle Nen Hexagon Skill Tree UI                |
| **User Interface**    | `K`                   | Toggle Seiyaku Contract / Hatsu Creation Editor |
| **Interactive QTE**   | `Space`               | Forced Awakening Survival Timing Zone Hits      |

## Deferred & Future Expansion Roadmap

- **Character Creation & Legacy Systems**: Full character creation suite, custom RGB aura color picker UI, and Surname Lineage passives (monetization architecture).
    
- **Server Enforcement**: Expanded combat logging disconnect punishments and severe combat logging consequences.
    
- **Faction & Licensing Systems**: Hunter Exam progression, Hunter License perks, and active target-restriction integration for Seiyaku conditions.
    
- **World Modes & Content**:
    
    - **Heavens Arena**: Ranked PvP ladder system alongside a dedicated **PvE Floor-Climbing Mode** featuring wave survival and boss encounters.
        
    - **Yorknew City**: Open-world exploration, black market trading, and auction house mechanics.