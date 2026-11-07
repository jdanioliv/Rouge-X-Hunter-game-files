-- CombatService
-- Server-side resolution for the tactical melee engine (GDD section 8):
-- hitbox sweeps, 10-frame parry validation, block/posture damage, guard
-- break punishes, frame-traps on successful parries, and Grip finishers on
-- downed targets. Clients only send *intents*; every outcome is computed here.
--
-- NOTE: full history-based rewind lag compensation is a planned refinement.
-- This pass validates timing windows with a bounded network tolerance
-- (Constants.NETWORK_TOLERANCE) instead of replaying position history.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)

local PlayerStateService = require(script.Parent.PlayerStateService)
local NenAffinityService = require(script.Parent.NenAffinityService)

local CombatService = {}

local combatIntentRemote = Remotes.Get("CombatIntent")
local auraIntentRemote = Remotes.Get("AuraIntent")
local feedbackRemote = Remotes.Get("CombatFeedback")
local broadcastRemote = Remotes.Get("CombatBroadcast")

local function sendFeedback(player: Player, kind: string, amount: number?)
	feedbackRemote:FireClient(player, { kind = kind, amount = amount })
end

-- Tells every client about a transient combat event so AnimationController /
-- VFX controllers can render other players' actions.
local function broadcast(player: Player, kind: string)
	broadcastRemote:FireAllClients({ kind = kind, userId = player.UserId })
end

--------------------------------------------------------------------------------
-- Grip finisher: timed, and the attacker can be hit out of it
--------------------------------------------------------------------------------

local activeGrips: { [Player]: { victim: Player, endsAt: number } } = {}

local function startGrip(attacker: Player, victim: Player)
	if not PlayerStateService.BeginGrip(attacker, victim) then
		return
	end
	activeGrips[attacker] = { victim = victim, endsAt = os.clock() + Constants.GRIP_DURATION_SECONDS }
	PlayerStateService.RefreshCombatTag(attacker)
	PlayerStateService.RefreshCombatTag(victim)
	sendFeedback(attacker, "GripStarted")
	sendFeedback(victim, "Gripped")
	broadcast(attacker, "GripStart")
end

local function releaseGrip(attacker: Player, victim: Player)
	activeGrips[attacker] = nil
	PlayerStateService.EndGrip(attacker, victim)
	broadcast(attacker, "GripEnd")
end

local function breakGrip(attacker: Player, victim: Player)
	releaseGrip(attacker, victim)
	if attacker.Parent then
		sendFeedback(attacker, "GripBroken")
	end
	if victim.Parent then
		sendFeedback(victim, "GripBroken")
	end
end

local function landGrip(attacker: Player, victim: Player)
	releaseGrip(attacker, victim)
	sendFeedback(attacker, "Grip")
	PlayerStateService.RefreshCombatTag(attacker)
	PlayerStateService.LoseSoulNode(victim, "grip")
end

-- nil when either character has no root part.
local function distanceBetween(first: Player, second: Player): number?
	local firstCharacter = first.Character
	local secondCharacter = second.Character
	local firstRoot = firstCharacter and firstCharacter:FindFirstChild("HumanoidRootPart")
	local secondRoot = secondCharacter and secondCharacter:FindFirstChild("HumanoidRootPart")
	if not firstRoot or not secondRoot then
		return nil
	end
	return (firstRoot.Position - secondRoot.Position).Magnitude
end

local function isTooFarApart(attacker: Player, victim: Player): boolean
	local distance = distanceBetween(attacker, victim)
	return distance == nil or distance > Constants.GRIP_BREAK_DISTANCE
end

-- The Grip key: the closest downed player in reach, if any. Melee never starts a Grip.
local function handleGrip(attacker: Player)
	if not PlayerStateService.CanAttack(attacker) then
		return
	end
	local target = nil
	local closest = Constants.GRIP_START_DISTANCE
	for _, other in Players:GetPlayers() do
		local otherState = PlayerStateService.GetState(other)
		if other ~= attacker and otherState and otherState.isDowned and not otherState.isBeingGripped then
			local distance = distanceBetween(attacker, other)
			if distance and distance <= closest and PlayerStateService.IsCharacterAlive(other) then
				target = other
				closest = distance
			end
		end
	end
	if target then
		startGrip(attacker, target)
	end
end

-- Dead with no Soul Node loss recorded: the victim pressed Reset or killed their own
-- character. That must not dodge a Grip already under way.
local function victimKilledThemselves(victim: Player): boolean
	local victimState = PlayerStateService.GetState(victim)
	return victimState ~= nil and not victimState.isDead and not PlayerStateService.IsCharacterAlive(victim)
end

local function stepGrips()
	local now = os.clock()
	for attacker, grip in activeGrips do
		local victim = grip.victim
		local attackerState = PlayerStateService.GetState(attacker)
		local victimState = PlayerStateService.GetState(victim)

		if not attackerState or not victimState then
			breakGrip(attacker, victim) -- one of them left the game
		elseif victimKilledThemselves(victim) then
			landGrip(attacker, victim)
		elseif not PlayerStateService.IsCharacterAlive(victim) then
			breakGrip(attacker, victim) -- something else already took a Soul Node
		elseif not attackerState.isGripping or attackerState.isDowned or attackerState.isGuardBroken then
			breakGrip(attacker, victim)
		elseif not PlayerStateService.IsCharacterAlive(attacker) then
			breakGrip(attacker, victim)
		elseif not victimState.isDowned or isTooFarApart(attacker, victim) then
			breakGrip(attacker, victim)
		elseif now >= grip.endsAt then
			landGrip(attacker, victim)
		end
	end
end

--------------------------------------------------------------------------------
-- Hit detection: box sweep in front of the attacker's root part
--------------------------------------------------------------------------------

-- Returns a list of hit Models with Humanoids, excluding the attacker.
local function sweepHitbox(attackerCharacter: Model): { Model }
	local rootPart = attackerCharacter:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return {}
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { attackerCharacter }

	-- Box centered ATTACK_RANGE/2 + 1 studs in front of the attacker.
	local sweepCFrame = rootPart.CFrame * CFrame.new(0, 0, -(Constants.ATTACK_RANGE / 2 + 1))
	local parts = workspace:GetPartBoundsInBox(sweepCFrame, Constants.ATTACK_HITBOX_SIZE, overlapParams)

	local seen = {}
	local victims = {}
	for _, part in parts do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and not seen[model] and model:FindFirstChildOfClass("Humanoid") then
			seen[model] = true
			table.insert(victims, model)
		end
	end
	return victims
end

--------------------------------------------------------------------------------
-- Damage calculation
--------------------------------------------------------------------------------

local function computeAttackDamage(attacker: Player): number
	local state = PlayerStateService.GetState(attacker)
	if not state then
		return 0
	end

	local damage = Constants.BASE_MELEE_DAMAGE

	-- Ren surges outward aura, boosting strike power.
	if state.auraState == "Ren" then
		damage *= 1 + Constants.REN_DAMAGE_BONUS
	end

	-- Ryu: offensive allocation scales damage while aura is flowing.
	if state.auraState ~= "None" and state.auraState ~= "Zetsu" then
		damage *= 1 + (state.ryuRatio.offense * Constants.RYU_OFFENSE_SCALING)
	end

	-- Basic strikes are Enhancement-scaled: an Enhancer's raw melee hits harder
	-- than an off-type's. Blended so off-types are weaker but not unplayable. A
	-- dormant player has no efficiency at all, so hits weakest of everyone.
	local enhancementMultiplier = NenAffinityService.GetEffectMultiplier(attacker, "Enhancement")
	local blend = Constants.MELEE_AFFINITY_BLEND
	damage *= (1 - blend) + blend * enhancementMultiplier

	return damage
end

--------------------------------------------------------------------------------
-- Attack resolution
--------------------------------------------------------------------------------

local function resolveHitOnPlayer(attacker: Player, victim: Player)
	local victimState = PlayerStateService.GetState(victim)
	local attackerState = PlayerStateService.GetState(attacker)
	if not victimState or not attackerState then
		return
	end

	-- A corpse is not a target, and a downed player can only be Gripped, with the Grip key.
	if not PlayerStateService.IsCharacterAlive(victim) or victimState.isDowned then
		return
	end

	PlayerStateService.RefreshCombatTag(attacker)
	PlayerStateService.RefreshCombatTag(victim)

	-- Parry check: negates all damage, frame-traps the attacker, and inflicts
	-- heavy posture damage on them (GDD section 8).
	if PlayerStateService.IsParryActive(victim, Constants.NETWORK_TOLERANCE) then
		PlayerStateService.ApplyPostureDamage(attacker, Constants.PARRY_POSTURE_DAMAGE_TO_ATTACKER)
		PlayerStateService.ExtendAttackLockout(attacker, Constants.PARRY_FRAME_TRAP_SECONDS)
		sendFeedback(victim, "ParrySuccess")
		sendFeedback(attacker, "GotParried")
		broadcast(attacker, "Stagger")
		return
	end

	-- Block check: blocking converts the hit into posture damage.
	if victimState.isBlocking and not victimState.isGuardBroken then
		PlayerStateService.ApplyPostureDamage(victim, Constants.BLOCK_POSTURE_DAMAGE)
		sendFeedback(victim, "Blocked")
		return
	end

	-- Clean hit. Guard-broken targets take bonus damage as the punish window.
	local damage = computeAttackDamage(attacker)
	if victimState.isGuardBroken then
		damage *= Constants.GUARD_BROKEN_DAMAGE_MULTIPLIER
	end
	local dealt = PlayerStateService.ApplyDamage(victim, damage, attacker)
	sendFeedback(attacker, "Hit", dealt)
end

local function resolveHitOnNpc(attacker: Player, npcModel: Model)
	local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(computeAttackDamage(attacker))
		PlayerStateService.RefreshCombatTag(attacker)
		sendFeedback(attacker, "Hit")
	end
end

local function handleAttack(player: Player)
	local state = PlayerStateService.GetState(player)
	if not state or not PlayerStateService.CanAttack(player) then
		return
	end

	local now = os.clock()
	if now - state.lastAttackAt < Constants.ATTACK_COOLDOWN then
		return
	end
	PlayerStateService.SetLastAttackAt(player, now)
	broadcast(player, "Attack")

	local character = player.Character
	if not character then
		return
	end

	for _, victimModel in sweepHitbox(character) do
		local victimPlayer = Players:GetPlayerFromCharacter(victimModel)
		if victimPlayer then
			resolveHitOnPlayer(player, victimPlayer)
		else
			resolveHitOnNpc(player, victimModel)
		end
	end
end

--------------------------------------------------------------------------------
-- Intent routing
--------------------------------------------------------------------------------

local function onCombatIntent(player: Player, intent)
	if type(intent) ~= "table" or type(intent.action) ~= "string" then
		return -- malformed payload; drop silently
	end

	if intent.action == "Attack" then
		handleAttack(player)
	elseif intent.action == "Parry" then
		if PlayerStateService.TryStartParry(player) then
			broadcast(player, "Parry")
		end
	elseif intent.action == "BlockStart" then
		if PlayerStateService.SetBlocking(player, true) then
			broadcast(player, "BlockStart")
		end
	elseif intent.action == "BlockEnd" then
		if PlayerStateService.SetBlocking(player, false) then
			broadcast(player, "BlockEnd")
		end
	elseif intent.action == "Grip" then
		handleGrip(player)
	end
end

local function onAuraIntent(player: Player, intent)
	if type(intent) ~= "table" then
		return
	end

	if type(intent.auraState) == "string" then
		PlayerStateService.SetAuraState(player, intent.auraState)
	end
	if type(intent.ryuOffense) == "number" then
		PlayerStateService.SetRyuRatio(player, intent.ryuOffense)
	end
end

function CombatService.Init()
	combatIntentRemote.OnServerEvent:Connect(onCombatIntent)
	auraIntentRemote.OnServerEvent:Connect(onAuraIntent)

	-- Relay state-machine events to all clients for stagger/downed animations.
	PlayerStateService.GuardBroken:Connect(function(player)
		broadcast(player, "BlockEnd") -- the state machine dropped their block
		broadcast(player, "GuardBreak")
	end)
	PlayerStateService.PlayerDowned:Connect(function(player)
		broadcast(player, "BlockEnd")
		broadcast(player, "Downed")
	end)
	PlayerStateService.PlayerRecovered:Connect(function(player)
		broadcast(player, "Recovered")
	end)

	-- This fires before ApplyDamage can down the attacker, so the Grip is released
	-- before EnterDownedState records their walk speed. Only a hit restarts the victim's
	-- recovery. A Grip broken any other way lets their healing carry on.
	PlayerStateService.PlayerDamaged:Connect(function(player)
		local grip = activeGrips[player]
		if grip then
			local victim = grip.victim
			if victimKilledThemselves(victim) then
				landGrip(player, victim)
			else
				breakGrip(player, victim)
				PlayerStateService.RestartDownedRecovery(victim)
			end
		end
	end)

	-- Quitting during a Grip costs what the Grip would have. This runs before the final
	-- save, and on the last Soul Node it wipes the character.
	PlayerStateService.PlayerLeaving:Connect(function(player)
		for attacker, grip in activeGrips do
			if grip.victim == player then
				landGrip(attacker, player)
				return
			end
		end
	end)

	RunService.Heartbeat:Connect(stepGrips)
end

return CombatService
