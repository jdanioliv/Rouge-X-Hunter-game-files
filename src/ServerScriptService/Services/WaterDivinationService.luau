--!strict
-- WaterDivinationService
-- The Water Divination Ceremony (GDD section 3): a glass of water with a leaf
-- floating on it, and the tell that reveals the practitioner's innate category.
--
-- This is the payoff for the safe path. Where NenAwakeningService's Gehaku
-- catalyst rolls the outcome wheel (and can cost a Soul Node), reaching the cup
-- with a full meditation focus bar awakens Nen with zero risk. The roll being
-- performed is the SAME one - NenAffinityService.AssignAffinity - so both paths
-- converge on one authoritative affinity source.
--
-- Any Instance tagged "DivinationCup" (CollectionService) gets a ProximityPrompt,
-- matching how NenAwakeningService attaches to "AwakeningNPC".
--
-- Trust model: the client can only trigger the prompt. Focus requirement, the
-- roll, the awakening flag, and the atomic save are all server-side, and the
-- ritual is single-flighted per player so prompt spam cannot double-roll.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Types = require(Shared.Types)
local Remotes = require(Shared.Remotes)

local PlayerStateService = require(script.Parent.PlayerStateService)
local NenAffinityService = require(script.Parent.NenAffinityService)

local WaterDivinationService = {}

local DIVINATION = Constants.DIVINATION

local outcomeRemote = Remotes.Get("DivinationOutcome")

-- Players mid-ritual. Cleared once the roll is applied.
local inProgress: { [Player]: boolean } = {}

-- Studio playtests spawn awakened via AUTO_AWAKEN_DEBUG; without this the cup
-- would always answer "AlreadyAwakened" and the six reveal animations could
-- never be exercised. Re-rolling the affinity is the point in that mode.
local function isStudioDebug(): boolean
	return RunService:IsStudio() and Constants.AUTO_AWAKEN_DEBUG
end

--------------------------------------------------------------------------------
-- Lazy cross-service accessors
--
-- Required inside the functions that use them rather than at the top of the
-- file: DataPersistenceService already requires PlayerStateService and
-- NenAffinityService at load time, and keeping these lazy means this service can
-- be initialized in any order without a load-time cycle appearing later.
--------------------------------------------------------------------------------

local function getMeditationService()
	return require(script.Parent.MeditationService)
end

local function getDataPersistenceService()
	return require(script.Parent.DataPersistenceService)
end

--------------------------------------------------------------------------------
-- Result construction
--------------------------------------------------------------------------------

-- NenAffinityService is a non-strict module, so its rolled affinity arrives as
-- loose data; this is the shape it guarantees.
type RolledAffinity = { primary: string, secondary: string? }

local function buildMessage(affinity: RolledAffinity): string
	local primary = affinity.primary
	local tell = DIVINATION.CATEGORY_TELLS[primary] or "The water reacts."
	local title = DIVINATION.CATEGORY_TITLES[primary] or primary

	if affinity.secondary then
		local secondTitle = DIVINATION.CATEGORY_TITLES[affinity.secondary] or affinity.secondary
		-- Rare in-between roll: the water gives two tells at once.
		return `{tell} You sit between {title} and {secondTitle}.`
	end
	return `{tell} You are a {title}.`
end

local function reject(player: Player, reason: string, message: string?)
	outcomeRemote:FireClient(player, {
		success = false,
		reason = reason,
		message = message,
	})
end

--------------------------------------------------------------------------------
-- Ceremony
--------------------------------------------------------------------------------

local function performDivination(player: Player, cup: Instance?)
	if inProgress[player] then
		return
	end

	local state = PlayerStateService.GetState(player)
	if not state or state.isDowned then
		return
	end
	if state.nenAwakened and not isStudioDebug() then
		reject(player, "AlreadyAwakened", "Your aura nodes are already open.")
		return
	end

	local MeditationService = getMeditationService()

	-- Read through MeditationService so an in-flight session's uncommitted focus
	-- counts too, rather than making the player stop first.
	local progress = MeditationService.GetProgress(player)
	if progress < DIVINATION.REQUIRED_PROGRESS then
		reject(
			player,
			"InsufficientFocus",
			`Your focus is not deep enough ({math.floor(progress)}/{DIVINATION.REQUIRED_PROGRESS}). Meditate first.`
		)
		return
	end

	inProgress[player] = true

	-- Awaken BEFORE rolling so the AffinityAssigned payload NenAffinityService
	-- pushes is already consistent with an awakened player.
	PlayerStateService.SetNenAwakened(player, true)
	local affinity: RolledAffinity = NenAffinityService.AssignAffinity(player)

	-- Focus is spent only now that the ritual has actually succeeded.
	MeditationService.ResetProgress(player)

	-- The cast is safe: AssignAffinity only ever returns categories drawn from
	-- NenHexagon.Categories, which is exactly the NenCategory union.
	local result: Types.DivinationResult = {
		category = affinity.primary :: Types.NenCategory,
		success = true,
		message = buildMessage(affinity),
	}

	outcomeRemote:FireClient(player, {
		success = true,
		result = result,
		category = affinity.primary,
		secondary = affinity.secondary,
		cup = cup,
		revealSeconds = DIVINATION.REVEAL_SECONDS,
	})

	inProgress[player] = nil

	-- Irreversible progression: force an atomic write immediately so a server
	-- crash in the next second cannot roll the awakening back. Spawned because
	-- SaveNow yields on the DataStore call.
	task.spawn(function()
		local DataPersistenceService = getDataPersistenceService()
		if not DataPersistenceService.SaveNow(player) then
			warn(`[WaterDivination] Immediate save failed for {player.Name}; autosave will retry`)
		end
	end)
end

--------------------------------------------------------------------------------
-- Cup prompt wiring (tag any part/model "DivinationCup" via CollectionService)
--------------------------------------------------------------------------------

local function attachPrompt(instance: Instance)
	local promptParent: Instance? = nil
	if instance:IsA("BasePart") then
		promptParent = instance
	elseif instance:IsA("Model") then
		promptParent = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
	end
	if not promptParent or promptParent:FindFirstChild("DivinationPrompt") then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DivinationPrompt"
	prompt.ActionText = "Perform Water Divination"
	prompt.ObjectText = "Glass of Water"
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = DIVINATION.PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptParent

	prompt.Triggered:Connect(function(player)
		performDivination(player, instance)
	end)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

-- Exposed so a tutorial NPC or test command can run the ceremony without a prop.
function WaterDivinationService.Perform(player: Player, cup: Instance?)
	performDivination(player, cup)
end

function WaterDivinationService.Init()
	for _, instance in CollectionService:GetTagged(DIVINATION.CUP_TAG) do
		attachPrompt(instance)
	end
	CollectionService:GetInstanceAddedSignal(DIVINATION.CUP_TAG):Connect(attachPrompt)

	Players.PlayerRemoving:Connect(function(player)
		inProgress[player] = nil
	end)
end

return WaterDivinationService
