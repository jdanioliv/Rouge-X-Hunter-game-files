-- NenAwakeningService
-- The illegal Forced Aura Node Awakening NPC (GDD section 3, "Gehaku / Aura
-- Shock Catalyst"). Any Instance tagged "AwakeningNPC" (CollectionService)
-- gets a ProximityPrompt. Triggering it charges money, rolls the 5-tier
-- outcome wheel server-side, lets the client play the cinematic, then applies
-- the outcome - including the 3-second fast-twitch QTE on Lethal Exhaustion.
--
-- Trust model: the wheel roll, payment, deadlines, and all consequences are
-- server-side. The client only reports QTE success/failure, and the server
-- enforces the deadline and accepts a single response.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local AwakeningOutcomes = require(Shared.AwakeningOutcomes)
local Remotes = require(Shared.Remotes)

local PlayerStateService = require(script.Parent.PlayerStateService)
local NenAffinityService = require(script.Parent.NenAffinityService)

local NenAwakeningService = {}

local NPC_TAG = "AwakeningNPC"

local resultRemote = Remotes.Get("AwakeningResult")
local qteRemote = Remotes.Get("AwakeningQTE")

local rng = Random.new()

-- Players currently mid-ceremony (wheel cinematic or QTE).
local inProgress: { [Player]: boolean } = {}
-- Pending QTE deadlines awaiting a client response.
local pendingQTE: { [Player]: { deadline: number } } = {}

--------------------------------------------------------------------------------
-- Outcome application
--------------------------------------------------------------------------------

local function awaken(player: Player)
	PlayerStateService.SetNenAwakened(player, true)
	-- Water Divination Ceremony: assigns the innate affinity.
	NenAffinityService.AssignAffinity(player)
end

local function startExhaustionQTE(player: Player)
	pendingQTE[player] = {
		deadline = os.clock() + Constants.AWAKENING_QTE_SECONDS + Constants.NETWORK_TOLERANCE,
	}
	qteRemote:FireClient(player, {
		duration = Constants.AWAKENING_QTE_SECONDS,
		requiredHits = Constants.AWAKENING_QTE_REQUIRED_HITS,
	})

	-- Server-enforced collapse timer: no response in time = failure.
	task.delay(Constants.AWAKENING_QTE_SECONDS + Constants.NETWORK_TOLERANCE * 2, function()
		if pendingQTE[player] then
			pendingQTE[player] = nil
			inProgress[player] = nil
			if player.Parent then
				PlayerStateService.LoseSoulNode(player, "awakening_collapse")
			end
		end
	end)
end

local function applyOutcome(player: Player, outcome: string)
	if not player.Parent then
		inProgress[player] = nil
		return
	end

	if outcome == "Clean" then
		awaken(player)
		inProgress[player] = nil
	elseif outcome == "Exhaustion" then
		startExhaustionQTE(player) -- resolution clears inProgress
	elseif outcome == "Mutilation" then
		-- Permanent scarring, no awakening; the payment is consumed.
		PlayerStateService.ApplyMutilation(player)
		inProgress[player] = nil
	elseif outcome == "Bypassed" then
		-- Set the penalty BEFORE assigning affinity so the client's
		-- AffinityAssigned payload already carries the bypassed flag.
		PlayerStateService.SetBypassedPenalty(player)
		awaken(player)
		inProgress[player] = nil
	elseif outcome == "Fatal" then
		PlayerStateService.LoseSoulNode(player, "awakening_overload")
		inProgress[player] = nil
	end
end

--------------------------------------------------------------------------------
-- Ceremony entry
--------------------------------------------------------------------------------

local function beginAwakening(player: Player)
	local state = PlayerStateService.GetState(player)
	if not state or state.isDowned or inProgress[player] then
		return
	end
	if state.nenAwakened then
		resultRemote:FireClient(player, { outcome = "Rejected", reason = "AlreadyAwakened" })
		return
	end
	if not PlayerStateService.TrySpendMoney(player, Constants.AWAKENING_COST) then
		resultRemote:FireClient(player, { outcome = "Rejected", reason = "InsufficientFunds" })
		return
	end

	inProgress[player] = true
	local outcome = AwakeningOutcomes.Roll(rng)

	-- Client plays the wheel cinematic; the server applies consequences when
	-- the wheel lands so deaths don't happen mid-spin.
	resultRemote:FireClient(player, { outcome = outcome })
	task.delay(Constants.AWAKENING_WHEEL_SECONDS, applyOutcome, player, outcome)
end

--------------------------------------------------------------------------------
-- NPC prompt wiring (tag any NPC/part "AwakeningNPC" via CollectionService)
--------------------------------------------------------------------------------

local function attachPrompt(instance: Instance)
	local promptParent: Instance? = nil
	if instance:IsA("BasePart") then
		promptParent = instance
	elseif instance:IsA("Model") then
		promptParent = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
	end
	if not promptParent or promptParent:FindFirstChild("AwakeningPrompt") then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "AwakeningPrompt"
	prompt.ActionText = `Forced Aura Awakening ({Constants.AWAKENING_COST})`
	prompt.ObjectText = "Gehaku - Aura Shock Catalyst"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptParent

	prompt.Triggered:Connect(beginAwakening)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function NenAwakeningService.Init()
	for _, instance in CollectionService:GetTagged(NPC_TAG) do
		attachPrompt(instance)
	end
	CollectionService:GetInstanceAddedSignal(NPC_TAG):Connect(attachPrompt)

	-- Client QTE result. One response max, deadline enforced server-side.
	qteRemote.OnServerEvent:Connect(function(player, payload)
		local pending = pendingQTE[player]
		if not pending then
			return
		end
		pendingQTE[player] = nil
		inProgress[player] = nil

		local inTime = os.clock() <= pending.deadline
		local succeeded = type(payload) == "table" and payload.success == true

		if inTime and succeeded then
			awaken(player)
		else
			-- Failing to stabilize Ten within 3s: collapse and death (GDD).
			PlayerStateService.LoseSoulNode(player, "awakening_collapse")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		inProgress[player] = nil
		pendingQTE[player] = nil
	end)
end

return NenAwakeningService
