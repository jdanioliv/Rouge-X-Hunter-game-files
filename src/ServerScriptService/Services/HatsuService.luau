-- HatsuService
-- Server-side execution for the player's stored Seiyaku (Pledge & Limitation)
-- contract. Every activation re-verifies ALL active conditions against live
-- PlayerStateService data, spends aura (with the +25% Bypassed penalty when
-- applicable), resolves modifier effects, and applies post-cast consequences.
--
-- Activation: client fires HatsuIntent (bound to Q in HatsuController).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local SeiyakuConfig = require(Shared.SeiyakuConfig)
local Remotes = require(Shared.Remotes)

local PlayerStateService = require(script.Parent.PlayerStateService)
local NenAffinityService = require(script.Parent.NenAffinityService)

local HatsuService = {}

local hatsuIntentRemote = Remotes.Get("HatsuIntent")
local hatsuEffectRemote = Remotes.Get("HatsuEffect")
local feedbackRemote = Remotes.Get("CombatFeedback")
local broadcastRemote = Remotes.Get("CombatBroadcast")

-- Players mid activation_delay charge; prevents double-firing.
local charging: { [Player]: boolean } = {}

local function sendFeedback(player: Player, kind: string, amount: number?)
	feedbackRemote:FireClient(player, { kind = kind, amount = amount })
end

local function broadcast(player: Player, kind: string)
	broadcastRemote:FireAllClients({ kind = kind, userId = player.UserId })
end

--------------------------------------------------------------------------------
-- Build helpers
--------------------------------------------------------------------------------

local function hasCondition(build, conditionId: string): boolean
	for _, id in build.conditionIds do
		if id == conditionId then
			return true
		end
	end
	return false
end

local function getModifier(build, modifierId: string)
	for _, selection in build.modifiers do
		if selection.id == modifierId then
			return selection
		end
	end
	return nil
end

local function getAuraCost(player: Player): number
	local cost = Constants.HATSU_BASE_AURA_COST
	local state = PlayerStateService.GetState(player)
	if state and state.awakeningPenalties.bypassed then
		cost = math.ceil(cost * Constants.BYPASSED_HATSU_COST_MULTIPLIER)
	end
	return cost
end

local function getCooldown(build): number
	local cooldown = Constants.HATSU_BASE_COOLDOWN
	if hasCondition(build, "cooldown_penalty") then
		cooldown *= 2
	end
	return cooldown
end

--------------------------------------------------------------------------------
-- Condition verification (live state at cast time)
--------------------------------------------------------------------------------

local function verifyConditions(player: Player, build, targetPlayer: Player?): (boolean, string?)
	local state = PlayerStateService.GetState(player)
	if not state then
		return false, "NoState"
	end

	if hasCondition(build, "hp_below_30") then
		if state.hp / state.maxHp >= Constants.HATSU_HP_RESTRICTION_THRESHOLD then
			return false, "HpTooHigh"
		end
	end

	if hasCondition(build, "target_restriction") then
		if not targetPlayer then
			return false, "NoValidTarget"
		end
		local character = targetPlayer.Character
		-- Placeholder until Hunter License / faction systems exist: the target
		-- must carry a HunterLicense or FactionTarget attribute on their character.
		local licensed = character and (character:GetAttribute("HunterLicense") == true
			or character:GetAttribute("FactionTarget") == true)
		if not licensed then
			return false, "InvalidTarget"
		end
	end

	return true, nil
end

--------------------------------------------------------------------------------
-- Hit detection (optionally doubled for aoe_expansion modifier)
--------------------------------------------------------------------------------

local function sweepHitbox(attackerCharacter: Model, aoeExpanded: boolean): { Model }
	local rootPart = attackerCharacter:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return {}
	end

	local hitboxSize = Constants.ATTACK_HITBOX_SIZE
	if aoeExpanded then
		hitboxSize = hitboxSize * Constants.HATSU_AOE_HITBOX_MULTIPLIER
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { attackerCharacter }

	local sweepCFrame = rootPart.CFrame * CFrame.new(0, 0, -(Constants.ATTACK_RANGE / 2 + 1))
	local parts = workspace:GetPartBoundsInBox(sweepCFrame, hitboxSize, overlapParams)

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
-- Damage & modifier resolution
--------------------------------------------------------------------------------

local function computeHatsuDamage(player: Player, build): number
	local state = PlayerStateService.GetState(player)
	if not state then
		return 0
	end

	local damage = Constants.HATSU_BASE_DAMAGE

	-- damage_boost modifier tiers.
	local boostSelection = getModifier(build, "damage_boost")
	if boostSelection and boostSelection.tier then
		local modifierDef = SeiyakuConfig.ModifiersById.damage_boost
		local tierData = modifierDef and modifierDef.tiers and modifierDef.tiers[boostSelection.tier]
		if tierData then
			damage *= 1 + tierData.value
		end
	end

	-- Ren / Ryu offensive scaling (same rules as melee).
	if state.auraState == "Ren" then
		damage *= 1 + Constants.REN_DAMAGE_BONUS
	end
	if state.auraState ~= "None" and state.auraState ~= "Zetsu" then
		damage *= 1 + (state.ryuRatio.offense * Constants.RYU_OFFENSE_SCALING)
	end

	-- Hatsu scales with the caster's innate Nen category efficiency.
	local affinity = NenAffinityService.GetAffinity(player)
	if affinity then
		local categoryMultiplier = NenAffinityService.GetEffectMultiplier(player, affinity.primary)
		if categoryMultiplier > 0 then
			local blend = Constants.HATSU_AFFINITY_BLEND
			damage *= (1 - blend) + blend * categoryMultiplier
		end
	end

	return damage
end

-- Returns whether the ability connected with this target. A parry or block counts:
-- the caster aimed true, so that is not a miss for the backfire condition.
local function resolveHitOnPlayer(attacker: Player, victim: Player, build, damage: number): boolean
	local victimState = PlayerStateService.GetState(victim)
	if not victimState or victimState.isDowned or not PlayerStateService.IsCharacterAlive(victim) then
		return false
	end

	PlayerStateService.RefreshCombatTag(attacker)
	PlayerStateService.RefreshCombatTag(victim)

	local guardBreak = getModifier(build, "guard_break") ~= nil

	-- Parry still works unless guard_break bypasses the entire defensive layer.
	if not guardBreak and PlayerStateService.IsParryActive(victim, Constants.NETWORK_TOLERANCE) then
		PlayerStateService.ApplyPostureDamage(attacker, Constants.PARRY_POSTURE_DAMAGE_TO_ATTACKER)
		PlayerStateService.ExtendAttackLockout(attacker, Constants.PARRY_FRAME_TRAP_SECONDS)
		sendFeedback(victim, "ParrySuccess")
		sendFeedback(attacker, "GotParried")
		broadcast(attacker, "Stagger")
		return true
	end

	-- Block: guard_break skips this entirely and deals full raw damage.
	if not guardBreak and victimState.isBlocking and not victimState.isGuardBroken then
		PlayerStateService.ApplyPostureDamage(victim, Constants.BLOCK_POSTURE_DAMAGE)
		sendFeedback(victim, "Blocked")
		return true
	end

	if victimState.isGuardBroken then
		damage *= Constants.GUARD_BROKEN_DAMAGE_MULTIPLIER
	end

	local dealt = PlayerStateService.ApplyDamage(victim, damage, attacker)
	sendFeedback(attacker, "Hit", dealt)

	-- Modifier: temporary blindness.
	if getModifier(build, "blindness") then
		hatsuEffectRemote:FireClient(victim, {
			kind = "Blindness",
			duration = Constants.HATSU_BLINDNESS_DURATION,
			attackerUserId = attacker.UserId,
		})
	end

	-- Modifier: stun duration extension.
	if getModifier(build, "stun_extension") then
		PlayerStateService.ExtendAttackLockout(victim, Constants.HATSU_STUN_EXTENSION)
	end

	return true
end

local function resolveHitOnNpc(attacker: Player, npcModel: Model, damage: number): boolean
	local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(damage)
		PlayerStateService.RefreshCombatTag(attacker)
		sendFeedback(attacker, "Hit")
		return true
	end
	return false
end

--------------------------------------------------------------------------------
-- Execution
--------------------------------------------------------------------------------

local function applyPostCast(player: Player, build)
	if hasCondition(build, "ten_seal") then
		PlayerStateService.SealTen(player, Constants.HATSU_TEN_SEAL_DURATION)
	end
end

local function executeHatsu(player: Player)
	local state = PlayerStateService.GetState(player)
	local build = PlayerStateService.GetSeiyakuBuild(player)
	if not state or not build or not PlayerStateService.CanAttack(player) then
		return
	end

	local now = os.clock()
	local cooldown = getCooldown(build)
	if now - state.lastHatsuAt < cooldown then
		return
	end

	-- Checked before the aura is spent, so a missing character costs nothing.
	local character = player.Character
	if not character then
		return
	end

	local auraCost = getAuraCost(player)
	if not PlayerStateService.TrySpendAura(player, auraCost) then
		return
	end

	-- Pick the first valid player target in range for target_restriction checks.
	local aoeExpanded = getModifier(build, "aoe_expansion") ~= nil
	local victims = sweepHitbox(character, aoeExpanded)

	local primaryTarget: Player? = nil
	for _, victimModel in victims do
		local victimPlayer = Players:GetPlayerFromCharacter(victimModel)
		if victimPlayer and victimPlayer ~= player then
			primaryTarget = victimPlayer
			break
		end
	end

	local conditionsOk, reason = verifyConditions(player, build, primaryTarget)
	if not conditionsOk then
		-- Refund aura when conditions fail at execution time.
		PlayerStateService.RefundAura(player, auraCost)
		sendFeedback(player, "TookHit") -- reuse flash as a generic "failed" ping
		warn(`[HatsuService] {player.Name} Hatsu blocked: {reason}`)
		return
	end

	PlayerStateService.SetLastHatsuAt(player, now)
	broadcast(player, "Attack") -- reuse attack broadcast for animation hook

	local damage = computeHatsuDamage(player, build)
	local hitCount = 0

	for _, victimModel in victims do
		local victimPlayer = Players:GetPlayerFromCharacter(victimModel)
		if victimPlayer and victimPlayer ~= player then
			-- Per-target restriction re-check for multi-hit AoE.
			local targetOk = verifyConditions(player, build, victimPlayer)
			if targetOk then
				if resolveHitOnPlayer(player, victimPlayer, build, damage) then
					hitCount += 1
				end
			end
		elseif victimModel ~= character then
			if resolveHitOnNpc(player, victimModel, damage) then
				hitCount += 1
			end
		end
	end

	-- backfire condition: missing deals 25% of the ability's damage to the caster.
	if hasCondition(build, "backfire") and hitCount == 0 then
		local selfDamage = damage * Constants.HATSU_BACKFIRE_FRACTION
		PlayerStateService.ApplyDamage(player, selfDamage) -- also sends the caster's TookHit
	end

	applyPostCast(player, build)
end

local function preflight(player: Player, build): boolean
	local state = PlayerStateService.GetState(player)
	if not state or not PlayerStateService.CanAttack(player) then
		return false
	end
	local now = os.clock()
	if now - state.lastHatsuAt < getCooldown(build) then
		return false
	end
	if state.aura < getAuraCost(player) then
		return false
	end
	return true
end

local function beginActivation(player: Player)
	local build = PlayerStateService.GetSeiyakuBuild(player)
	if not build or not preflight(player, build) then
		return
	end

	if hasCondition(build, "activation_delay") then
		if charging[player] then
			return
		end
		charging[player] = true
		broadcast(player, "BlockStart") -- charge pose hook
		task.delay(Constants.HATSU_ACTIVATION_DELAY, function()
			charging[player] = nil
			if player.Parent then
				broadcast(player, "BlockEnd")
				executeHatsu(player)
			end
		end)
	else
		executeHatsu(player)
	end
end

local function onHatsuIntent(player: Player)
	local state = PlayerStateService.GetState(player)
	if not state or not state.nenAwakened then
		return
	end
	if not PlayerStateService.GetSeiyakuBuild(player) then
		return
	end
	if charging[player] then
		return
	end
	beginActivation(player)
end

function HatsuService.Init()
	hatsuIntentRemote.OnServerEvent:Connect(onHatsuIntent)

	Players.PlayerRemoving:Connect(function(player)
		charging[player] = nil
	end)
end

return HatsuService
