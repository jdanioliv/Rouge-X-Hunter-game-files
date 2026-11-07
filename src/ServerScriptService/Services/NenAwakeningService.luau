-- NenAwakeningService
-- The illegal Forced Aura Node Awakening NPC (GDD section 3, "Gehaku / Aura
-- Shock Catalyst"). Any Instance tagged "AwakeningNPC" (CollectionService)
-- gets a ProximityPrompt. Triggering it charges money, rolls the 5-tier
-- outcome wheel server-side, lets the client play the cinematic, then applies
-- the outcome - including the 3-second fast-twitch QTE on Lethal Exhaustion.
--
-- Trust model: the wheel roll, payment, deadlines, the QTE verdict and all
-- consequences are server-side. The client reports each press with its QTE time;
-- the server recomputes the marker at that time, checks that time against its own
-- clock, and counts the hit itself. This stops a client simply claiming success.
-- It cannot stop a script that presses at the right moments.
--
-- Leaving does not escape the result: a roll or QTE still pending when the player
-- leaves is settled before their final save.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
-- Rolled outcomes whose wheel is still spinning.
local pendingOutcome: { [Player]: string } = {}
-- Running QTEs, judged press by press.
local pendingQTE: { [Player]: { startedAt: number, hits: number, lastElapsed: number } } = {}

--------------------------------------------------------------------------------
-- Outcome application
--------------------------------------------------------------------------------

local function awaken(player: Player)
	PlayerStateService.SetNenAwakened(player, true)
	-- Water Divination Ceremony: assigns the innate affinity.
	NenAffinityService.AssignAffinity(player)
end

-- Irreversible progression: same immediate write Water Divination does. A Soul
-- Node loss saves itself through DataPersistenceService. Required lazily, matching
-- WaterDivinationService, so init order cannot create a load-time cycle.
local function saveNow(player: Player)
	task.spawn(function()
		local DataPersistenceService = require(script.Parent.DataPersistenceService)
		if not DataPersistenceService.SaveNow(player) then
			warn(`[NenAwakening] Immediate save failed for {player.Name}; autosave will retry`)
		end
	end)
end

local function resolveQTE(player: Player, stabilized: boolean)
	pendingQTE[player] = nil
	inProgress[player] = nil
	qteRemote:FireClient(player, { verdict = if stabilized then "Stabilized" else "Collapsed" })

	if stabilized then
		awaken(player)
		saveNow(player)
	else
		-- Failing to stabilize Ten within 3s: collapse and death (GDD).
		PlayerStateService.LoseSoulNode(player, "awakening_collapse")
	end
end

local function startExhaustionQTE(player: Player)
	local qte = { startedAt = os.clock(), hits = 0, lastElapsed = -math.huge }
	pendingQTE[player] = qte
	qteRemote:FireClient(player, {
		duration = Constants.AWAKENING_QTE_SECONDS,
		requiredHits = Constants.AWAKENING_QTE_REQUIRED_HITS,
	})

	-- Server-enforced collapse timer: not enough hits in time = failure.
	task.delay(Constants.AWAKENING_QTE_SECONDS + Constants.AWAKENING_QTE_MAX_LAG, function()
		if pendingQTE[player] == qte then
			resolveQTE(player, false)
		end
	end)
end

local function onQTEPress(player: Player, payload)
	local qte = pendingQTE[player]
	if not qte or type(payload) ~= "table" then
		return
	end
	local elapsed = payload.elapsed
	if type(elapsed) ~= "number" or elapsed ~= elapsed then
		return
	end

	-- The client's QTE clock starts after the server's and its press arrives later
	-- still, so a real press always reads a little behind the server clock.
	local serverElapsed = os.clock() - qte.startedAt
	if elapsed < 0 or elapsed > Constants.AWAKENING_QTE_SECONDS or elapsed > serverElapsed then
		return
	end
	if serverElapsed - elapsed > Constants.AWAKENING_QTE_MAX_LAG then
		return
	end
	if elapsed - qte.lastElapsed < Constants.AWAKENING_QTE_MIN_PRESS_SPACING then
		return
	end
	if not AwakeningOutcomes.IsQTEHit(elapsed, Constants.AWAKENING_QTE_ZONE_HALF_WIDTH) then
		return
	end

	qte.lastElapsed = elapsed
	qte.hits += 1
	if qte.hits >= Constants.AWAKENING_QTE_REQUIRED_HITS then
		resolveQTE(player, true)
	end
end

-- The consequences of every outcome except Exhaustion, which has its own QTE.
local function settleOutcome(player: Player, outcome: string)
	if outcome == "Clean" then
		awaken(player)
	elseif outcome == "Mutilation" then
		-- Permanent scarring, no awakening; the payment is consumed.
		PlayerStateService.ApplyMutilation(player)
	elseif outcome == "Bypassed" then
		-- Set the penalty BEFORE assigning affinity so the client's
		-- AffinityAssigned payload already carries the bypassed flag.
		PlayerStateService.SetBypassedPenalty(player)
		awaken(player)
	elseif outcome == "Fatal" then
		PlayerStateService.LoseSoulNode(player, "awakening_overload")
	end
end

local function applyOutcome(player: Player, outcome: string)
	if pendingOutcome[player] ~= outcome then
		return -- already settled when the player left
	end
	pendingOutcome[player] = nil

	if outcome == "Exhaustion" then
		startExhaustionQTE(player) -- resolution clears inProgress
		return
	end

	settleOutcome(player, outcome)
	inProgress[player] = nil
	if outcome ~= "Fatal" then
		saveNow(player)
	end
end

-- Runs before the leaving player's final save, so quitting cannot escape a bad
-- result. An unfinished QTE counts as failed.
local function settleOnLeave(player: Player)
	local outcome = pendingOutcome[player]
	if outcome then
		pendingOutcome[player] = nil
		if outcome == "Exhaustion" then
			PlayerStateService.LoseSoulNode(player, "awakening_collapse")
		else
			settleOutcome(player, outcome)
		end
	elseif pendingQTE[player] then
		pendingQTE[player] = nil
		PlayerStateService.LoseSoulNode(player, "awakening_collapse")
	end
	inProgress[player] = nil
end

--------------------------------------------------------------------------------
-- Ceremony entry
--------------------------------------------------------------------------------

local function beginAwakening(player: Player)
	local state = PlayerStateService.GetState(player)
	if not state or state.isDowned or state.isGripping or inProgress[player] or not PlayerStateService.IsCharacterAlive(player) then
		return
	end
	-- Until the saved profile loads, this state is only defaults: a spin now would be paid
	-- for by money about to be overwritten, and could reroll a saved affinity. Studio can
	-- run without saves, so it is exempt.
	local DataPersistenceService = require(script.Parent.DataPersistenceService)
	if not RunService:IsStudio() and not DataPersistenceService.IsLoaded(player) then
		resultRemote:FireClient(player, { outcome = "Rejected", reason = "Loading" })
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
	pendingOutcome[player] = outcome

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
	prompt.HoldDuration = Constants.AWAKENING_PROMPT_HOLD_SECONDS
	prompt.MaxActivationDistance = Constants.AWAKENING_PROMPT_DISTANCE
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

	qteRemote.OnServerEvent:Connect(onQTEPress)

	PlayerStateService.PlayerLeaving:Connect(settleOnLeave)

	-- Dying to something else, like a Grip, ends the ceremony. Otherwise the pending
	-- result would take a second node, or land on the fresh character after a wipe.
	-- The ceremony's own node losses clear these entries first, so they never reach here.
	PlayerStateService.SoulNodeLost:Connect(function(player)
		local hadQTE = pendingQTE[player] ~= nil
		if not hadQTE and not pendingOutcome[player] then
			return
		end
		pendingOutcome[player] = nil
		pendingQTE[player] = nil
		inProgress[player] = nil
		if hadQTE then
			qteRemote:FireClient(player, { verdict = "Collapsed" })
		end
	end)

	PlayerStateService.PlayerGone:Connect(function(player)
		inProgress[player] = nil
		pendingOutcome[player] = nil
		pendingQTE[player] = nil
	end)
end

return NenAwakeningService
