-- Server bootstrap. Initializes services in dependency order.
-- DataPersistenceService inits first so profiles are claimed as early as possible.
-- Leaving does not rely on handler order: its PlayerRemoving handler saves, then fires
-- PlayerGone, and only that signal clears player data.

local ServerScriptService = game:GetService("ServerScriptService")
local servicesFolder = ServerScriptService:WaitForChild("Services")

local DataPersistenceService = require(servicesFolder.DataPersistenceService)
local PlayerStateService = require(servicesFolder.PlayerStateService)
local NenAffinityService = require(servicesFolder.NenAffinityService)
local CombatService = require(servicesFolder.CombatService)
local NenAwakeningService = require(servicesFolder.NenAwakeningService)
local MeditationService = require(servicesFolder.MeditationService)
local WaterDivinationService = require(servicesFolder.WaterDivinationService)
local SeiyakuService = require(servicesFolder.SeiyakuService)
local HatsuService = require(servicesFolder.HatsuService)

DataPersistenceService.Init()
PlayerStateService.Init()
NenAffinityService.Init()
CombatService.Init()
NenAwakeningService.Init()
-- MeditationService before WaterDivinationService: the cup reads live focus
-- through it, and its interrupt hooks should be listening before any prop
-- prompt can be triggered.
MeditationService.Init()
WaterDivinationService.Init()
SeiyakuService.Init()
HatsuService.Init()

print(
	"[RougeXHunter] Server initialized (Persistence, PlayerState, NenAffinity, Combat, Awakening, Meditation, WaterDivination, Seiyaku, Hatsu)"
)
