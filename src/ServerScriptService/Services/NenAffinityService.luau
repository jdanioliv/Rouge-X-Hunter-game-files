-- NenAffinityService
-- Owns each player's innate Nen category and all skill node purchases through
-- the Kastro Penalty Engine. With the awakening gate, affinity is NO LONGER
-- assigned on join: NenAwakeningService calls AssignAffinity (the Water
-- Divination roll) when a player successfully awakens. In Studio,
-- PlayerStateService's AUTO_AWAKEN_DEBUG path calls it directly.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local NenHexagon = require(Shared.NenHexagon)
local Remotes = require(Shared.Remotes)

local PlayerStateService = require(script.Parent.PlayerStateService)

local NenAffinityService = {}

local affinities = {} -- [Player] = Types.Affinity
local learnedNodes = {} -- [Player] = { [NenCategory] = nodeCount }

local affinityRemote = Remotes.Get("AffinityAssigned")
local purchaseFunction = Remotes.GetFunction("PurchaseSkillNode")

-- Roll weights for the primary affinity. Specialization is intentionally rare.
local AFFINITY_WEIGHTS = {
	{ category = "Enhancement", weight = 22 },
	{ category = "Transmutation", weight = 20 },
	{ category = "Conjuration", weight = 18 },
	{ category = "Emission", weight = 18 },
	{ category = "Manipulation", weight = 17 },
	{ category = "Specialization", weight = 5 },
}

local rng = Random.new()

local function rollPrimary(): string
	local total = 0
	for _, entry in AFFINITY_WEIGHTS do
		total += entry.weight
	end
	local pick = rng:NextNumber(0, total)
	local accumulated = 0
	for _, entry in AFFINITY_WEIGHTS do
		accumulated += entry.weight
		if pick <= accumulated then
			return entry.category
		end
	end
	return "Enhancement"
end

local function rollAffinity()
	-- Rare in-between node: the character sits between two adjacent types
	-- (e.g. Killua/Machi between Transmutation and Enhancement) and treats
	-- both as innate.
	if rng:NextNumber() < Constants.IN_BETWEEN_AFFINITY_CHANCE then
		local pair = NenHexagon.AdjacentPairs[rng:NextInteger(1, #NenHexagon.AdjacentPairs)]
		return { primary = pair[1], secondary = pair[2] }
	end
	return { primary = rollPrimary(), secondary = nil }
end

local function isInnate(affinity, category: string): boolean
	return category == affinity.primary or category == affinity.secondary
end

-- Sends the client everything it needs to render the skill tree locally.
local function pushAffinityToClient(player: Player)
	local affinity = affinities[player]
	local state = PlayerStateService.GetState(player)
	affinityRemote:FireClient(player, {
		primary = affinity and affinity.primary or nil,
		secondary = affinity and affinity.secondary or nil,
		bypassed = state ~= nil and state.awakeningPenalties.bypassed or false,
		learnedNodes = learnedNodes[player] and table.clone(learnedNodes[player]) or {},
	})
end

--------------------------------------------------------------------------------
-- Affinity assignment (Water Divination)
--------------------------------------------------------------------------------

function NenAffinityService.AssignAffinity(player: Player)
	local affinity = rollAffinity()
	affinities[player] = affinity
	learnedNodes[player] = learnedNodes[player] or {}
	pushAffinityToClient(player)
	return affinity
end

--------------------------------------------------------------------------------
-- Read API
--------------------------------------------------------------------------------

function NenAffinityService.GetAffinity(player: Player)
	return affinities[player]
end

-- Efficiency including the Bypassed Fundamentals penalty: -15% across all
-- non-innate categories (GDD section 3).
function NenAffinityService.GetEfficiency(player: Player, category: string): number
	local affinity = affinities[player]
	if not affinity then
		return 0
	end
	local efficiency = NenHexagon.GetEfficiency(affinity, category)

	local state = PlayerStateService.GetState(player)
	if state and state.awakeningPenalties.bypassed and not isInnate(affinity, category) and efficiency > 0 then
		efficiency = math.max(0, efficiency - Constants.BYPASSED_EFFICIENCY_PENALTY)
	end
	return efficiency
end

-- Damage/effect multiplier for the player using an ability of this category.
function NenAffinityService.GetEffectMultiplier(player: Player, category: string): number
	return NenAffinityService.GetEfficiency(player, category) / 100
end

function NenAffinityService.GetLearnedNodes(player: Player, category: string): number
	local nodes = learnedNodes[player]
	return nodes and nodes[category] or 0
end

-- Memory slot cost for the player's next node in this category,
-- or nil if the category is locked for their affinity.
function NenAffinityService.GetSkillNodeCost(player: Player, category: string): number?
	if not affinities[player] then
		return nil
	end
	return NenHexagon.GetMemorySlotCost(NenAffinityService.GetEfficiency(player, category))
end

--------------------------------------------------------------------------------
-- Progression API (the "Kastro Trap" lives here: off-affinity nodes eat the
-- shared memory pool at inflated rates and can permanently cap progression)
--------------------------------------------------------------------------------

function NenAffinityService.TryLearnSkillNode(player: Player, category: string): (boolean, string?)
	local cost = NenAffinityService.GetSkillNodeCost(player, category)
	if not cost then
		return false, "CategoryLocked"
	end
	if not PlayerStateService.SpendMemorySlots(player, cost) then
		return false, "MemorySaturated"
	end

	local nodes = learnedNodes[player]
	if nodes then
		nodes[category] = (nodes[category] or 0) + 1
	end
	return true, nil
end

--------------------------------------------------------------------------------
-- Persistence API (called by DataPersistenceService)
--------------------------------------------------------------------------------

function NenAffinityService.BuildPersistedData(player: Player)
	return {
		affinity = affinities[player],
		learnedNodes = learnedNodes[player] and table.clone(learnedNodes[player]) or {},
	}
end

function NenAffinityService.ApplyPersistedData(player: Player, data)
	if type(data) ~= "table" then
		return
	end

	if type(data.learnedNodes) == "table" then
		local restored = {}
		for category, count in data.learnedNodes do
			if table.find(NenHexagon.Categories, category) and type(count) == "number" then
				restored[category] = math.max(0, math.floor(count))
			end
		end
		learnedNodes[player] = restored
	end

	local savedAffinity = data.affinity
	if type(savedAffinity) == "table" and table.find(NenHexagon.Categories, savedAffinity.primary) then
		affinities[player] = {
			primary = savedAffinity.primary,
			secondary = table.find(NenHexagon.Categories, savedAffinity.secondary) and savedAffinity.secondary or nil,
		}
	end

	if affinities[player] then
		pushAffinityToClient(player)
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function NenAffinityService.Init()
	local function onPlayerAdded(player: Player)
		-- No affinity on join anymore (awakening gate); just prep bookkeeping.
		learnedNodes[player] = {}
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		affinities[player] = nil
		learnedNodes[player] = nil
	end)

	-- A full character wipe erases Nen progression entirely (GDD section 2):
	-- back to dormant. In Studio debug mode, immediately re-awaken for testing.
	PlayerStateService.CharacterWiped:Connect(function(player)
		if not player.Parent then
			return
		end
		affinities[player] = nil
		learnedNodes[player] = {}
		if RunService:IsStudio() and Constants.AUTO_AWAKEN_DEBUG then
			PlayerStateService.SetNenAwakened(player, true)
			NenAffinityService.AssignAffinity(player)
		else
			pushAffinityToClient(player) -- tells the client it is dormant again
		end
	end)

	-- Server-verified skill node purchases from the skill tree UI.
	purchaseFunction.OnServerInvoke = function(player, category)
		if type(category) ~= "string" or not table.find(NenHexagon.Categories, category) then
			return { success = false, reason = "InvalidCategory" }
		end
		local state = PlayerStateService.GetState(player)
		if not state or not state.nenAwakened or not affinities[player] then
			return { success = false, reason = "NenDormant" }
		end

		local success, reason = NenAffinityService.TryLearnSkillNode(player, category)
		return {
			success = success,
			reason = reason,
			learnedNodes = learnedNodes[player] and table.clone(learnedNodes[player]) or {},
			memorySlotsUsed = state.memorySlotsUsed,
		}
	end
end

return NenAffinityService
