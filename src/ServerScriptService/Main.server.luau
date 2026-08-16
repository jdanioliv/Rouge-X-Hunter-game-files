-- Server bootstrap. Initializes services in dependency order.
-- DataPersistenceService MUST init first: its PlayerAdded/PlayerRemoving
-- connections need to fire before PlayerStateService's so profiles are
-- claimed before gameplay starts and saved before state is cleared.

local ServerScriptService = game:GetService("ServerScriptService")
local servicesFolder = ServerScriptService:WaitForChild("Services")

local DataPersistenceService = require(servicesFolder.DataPersistenceService)
local PlayerStateService = require(servicesFolder.PlayerStateService)
local NenAffinityService = require(servicesFolder.NenAffinityService)
local CombatService = require(servicesFolder.CombatService)
local NenAwakeningService = require(servicesFolder.NenAwakeningService)
local SeiyakuService = require(servicesFolder.SeiyakuService)
local HatsuService = require(servicesFolder.HatsuService)

DataPersistenceService.Init()
PlayerStateService.Init()
NenAffinityService.Init()
CombatService.Init()
NenAwakeningService.Init()
SeiyakuService.Init()
HatsuService.Init()

print("[RougeXHunter] Server initialized (Persistence, PlayerState, NenAffinity, Combat, Awakening, Seiyaku, Hatsu)")
