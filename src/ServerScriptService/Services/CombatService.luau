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

	-- A corpse waiting to respawn is not a target: no more nodes to take from it.
	if not PlayerStateService.IsCharacterAlive(victim) then
		return
	end

	PlayerStateService.RefreshCombatTag(attacker)
	PlayerStateService.RefreshCombatTag(victim)

	-- Grip finisher: striking a downed target destroys a Soul Node (GDD section 2).
	if victimState.isDowned then
		sendFeedback(attacker, "Grip")
		PlayerStateService.LoseSoulNode(victim, "grip")
		return
	end

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
end

return CombatService
