-- PlayerStateService
-- The server-authoritative state machine required by GDD section 8.
-- Holds one state table per player, mutated ONLY through the validated API
-- below. Clients receive a throttled read-only snapshot for HUD rendering
-- and are never trusted for gameplay-affecting values.
--
-- Aura state, aura color, and downed status are additionally mirrored onto
-- the Character as attributes so every client can render other players'
-- aura VFX without extra networking.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Types = require(Shared.Types)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Util.Signal)

local PlayerStateService = {}

-- Signals other services (and future permadeath/Depths systems) hook into.
PlayerStateService.PlayerDowned = Signal.new() -- (player)
PlayerStateService.GuardBroken = Signal.new() -- (player)
PlayerStateService.SoulNodeLost = Signal.new() -- (player, remainingNodes, reason)
PlayerStateService.CharacterWiped = Signal.new() -- (player)
PlayerStateService.CombatLoggerDetected = Signal.new() -- (player, remainingTagSeconds)

local states: { [Player]: Types.PlayerState } = {}

local snapshotRemote = Remotes.Get("StateSnapshot")
local feedbackRemote = Remotes.Get("CombatFeedback")
local auraColorRemote = Remotes.Get("SetAuraColor")

local function newState(): Types.PlayerState
	return {
		hp = Constants.MAX_HP,
		maxHp = Constants.MAX_HP,
		posture = 0,
		aura = Constants.MAX_AURA,
		maxAura = Constants.MAX_AURA,
		soulNodes = Constants.STARTING_SOUL_NODES,
		memorySlotsUsed = 0,
		memorySlotCap = Constants.MEMORY_SLOT_CAP,
		money = Constants.STARTING_MONEY,

		nenAwakened = false,
		awakeningPenalties = { bypassed = false, mutilated = false },
		auraColor = table.clone(Constants.DEFAULT_AURA_COLOR),
		seiyakuBuild = nil,

		isParrying = false,
		parryStartedAt = 0,
		lastParryAt = 0,

		isBlocking = false,
		isGuardBroken = false,
		guardBreakEndsAt = 0,
		lastPostureDamageAt = 0,

		auraState = "None",
		ryuRatio = { offense = 0.5, defense = 0.5 },

		combatTagEndsAt = 0,

		isDowned = false,
		downedEndsAt = 0,

		lastAttackAt = 0,
		attackLockedUntil = 0,
		lastHatsuAt = 0,
		tenSealedUntil = 0,
	}
end

-- Recomputes max HP / max aura from permanent awakening penalties.
-- Mutilation (GDD section 3) is a permanent multiplier: -10% max HP, -15% max aura.
local function applyPenaltyCaps(state)
	if state.awakeningPenalties.mutilated then
		state.maxHp = math.floor(Constants.MAX_HP * Constants.MUTILATION_HP_MULTIPLIER)
		state.maxAura = math.floor(Constants.MAX_AURA * Constants.MUTILATION_AURA_MULTIPLIER)
	else
		state.maxHp = Constants.MAX_HP
		state.maxAura = Constants.MAX_AURA
	end
	state.hp = math.min(state.hp, state.maxHp)
	state.aura = math.min(state.aura, state.maxAura)
end

-- Mirrors render-relevant state onto the Character so all clients can react.
local function syncAttributes(player: Player, state)
	local character = player.Character
	if not character then
		return
	end
	character:SetAttribute("AuraState", state.auraState)
	character:SetAttribute("AuraColor", Color3.fromRGB(state.auraColor.r, state.auraColor.g, state.auraColor.b))
	character:SetAttribute("IsDowned", state.isDowned)
end

-- Resets combat-volatile fields on respawn while preserving session-persistent
-- progression (soul nodes, memory slots, money, awakening status/penalties).
local function resetVolatile(state)
	state.hp = state.maxHp
	state.posture = 0
	state.aura = state.maxAura
	state.isParrying = false
	state.isBlocking = false
	state.isGuardBroken = false
	state.guardBreakEndsAt = 0
	state.auraState = "None"
	state.ryuRatio = { offense = 0.5, defense = 0.5 }
	state.isDowned = false
	state.downedEndsAt = 0
	state.attackLockedUntil = 0
	state.lastHatsuAt = 0
	state.tenSealedUntil = 0
end

local function sendFeedback(player: Player, kind: string, amount: number?)
	feedbackRemote:FireClient(player, { kind = kind, amount = amount })
end

--------------------------------------------------------------------------------
-- Read API
--------------------------------------------------------------------------------

function PlayerStateService.GetState(player: Player)
	return states[player]
end

function PlayerStateService.IsInCombat(player: Player): boolean
	local state = states[player]
	return state ~= nil and os.clock() < state.combatTagEndsAt
end

-- True while the parry input is inside its active frame window.
function PlayerStateService.IsParryActive(player: Player, tolerance: number?): boolean
	local state = states[player]
	if not state or not state.isParrying then
		return false
	end
	local window = Constants.PARRY_WINDOW_SECONDS + (tolerance or 0)
	return (os.clock() - state.parryStartedAt) <= window
end

function PlayerStateService.CanAct(player: Player): boolean
	local state = states[player]
	if not state then
		return false
	end
	return not state.isDowned and not state.isGuardBroken
end

--------------------------------------------------------------------------------
-- Combat tag (GDD section 2 - anti-combat-logging foundation)
--------------------------------------------------------------------------------

function PlayerStateService.RefreshCombatTag(player: Player)
	local state = states[player]
	if state then
		state.combatTagEndsAt = os.clock() + Constants.COMBAT_TAG_DURATION
	end
end

--------------------------------------------------------------------------------
-- Defensive actions
--------------------------------------------------------------------------------

function PlayerStateService.TryStartParry(player: Player): boolean
	local state = states[player]
	if not state or state.isDowned or state.isGuardBroken or state.isBlocking then
		return false
	end
	local now = os.clock()
	if now - state.lastParryAt < Constants.PARRY_COOLDOWN then
		return false
	end
	state.isParrying = true
	state.parryStartedAt = now
	state.lastParryAt = now
	return true
end

function PlayerStateService.SetBlocking(player: Player, blocking: boolean): boolean
	local state = states[player]
	if not state then
		return false
	end
	if blocking and (state.isDowned or state.isGuardBroken or state.isParrying) then
		return false
	end
	state.isBlocking = blocking
	return true
end

--------------------------------------------------------------------------------
-- Aura control (gated behind Nen awakening)
--------------------------------------------------------------------------------

local VALID_AURA_STATES = { None = true, Ten = true, Zetsu = true, Ren = true, Ken = true }

function PlayerStateService.SetAuraState(player: Player, auraState: string): boolean
	local state = states[player]
	if not state or not VALID_AURA_STATES[auraState] or state.isDowned then
		return false
	end
	-- Nen gate: dormant players cannot manipulate aura at all.
	if auraState ~= "None" and not state.nenAwakened then
		return false
	end
	-- ten_seal condition aftermath: Ten is blocked until the seal expires.
	if auraState == "Ten" and os.clock() < state.tenSealedUntil then
		return false
	end
	-- Ren and Ken have upkeep; require some aura to enter them.
	if (auraState == "Ren" or auraState == "Ken") and state.aura <= 0 then
		return false
	end
	state.auraState = auraState
	syncAttributes(player, state)
	return true
end

function PlayerStateService.SetRyuRatio(player: Player, offense: number): boolean
	local state = states[player]
	if not state or type(offense) ~= "number" or offense ~= offense then
		return false
	end
	local clamped = math.clamp(offense, 0, 1)
	state.ryuRatio = { offense = clamped, defense = 1 - clamped }
	return true
end

function PlayerStateService.SetAuraColor(player: Player, r: number, g: number, b: number): boolean
	local state = states[player]
	if not state then
		return false
	end
	local function sanitize(value)
		if type(value) ~= "number" or value ~= value then
			return nil
		end
		return math.clamp(math.floor(value), 0, 255)
	end
	local red, green, blue = sanitize(r), sanitize(g), sanitize(b)
	if not red or not green or not blue then
		return false
	end
	state.auraColor = { r = red, g = green, b = blue }
	syncAttributes(player, state)
	return true
end

--------------------------------------------------------------------------------
-- Nen awakening status & permanent penalties (GDD section 3)
--------------------------------------------------------------------------------

function PlayerStateService.SetNenAwakened(player: Player, awakened: boolean)
	local state = states[player]
	if state then
		state.nenAwakened = awakened
	end
end

-- Permanent Mutilation penalty: -10% max HP, -15% max aura.
function PlayerStateService.ApplyMutilation(player: Player)
	local state = states[player]
	if not state then
		return
	end
	state.awakeningPenalties.mutilated = true
	applyPenaltyCaps(state)
end

-- Bypassed Fundamentals: efficiency/Hatsu-cost penalties are read from this
-- flag by NenAffinityService and the future Hatsu system.
function PlayerStateService.SetBypassedPenalty(player: Player)
	local state = states[player]
	if state then
		state.awakeningPenalties.bypassed = true
	end
end

--------------------------------------------------------------------------------
-- Economy
--------------------------------------------------------------------------------

function PlayerStateService.GetMoney(player: Player): number
	local state = states[player]
	return state and state.money or 0
end

function PlayerStateService.AddMoney(player: Player, amount: number)
	local state = states[player]
	if state then
		state.money = math.max(0, state.money + amount)
	end
end

function PlayerStateService.TrySpendMoney(player: Player, amount: number): boolean
	local state = states[player]
	if not state or state.money < amount then
		return false
	end
	state.money -= amount
	return true
end

--------------------------------------------------------------------------------
-- Seiyaku build storage (validated by SeiyakuService before reaching here)
--------------------------------------------------------------------------------

function PlayerStateService.SetSeiyakuBuild(player: Player, build)
	local state = states[player]
	if state then
		state.seiyakuBuild = build
	end
end

function PlayerStateService.GetSeiyakuBuild(player: Player)
	local state = states[player]
	return state and state.seiyakuBuild or nil
end

function PlayerStateService.TrySpendAura(player: Player, amount: number): boolean
	local state = states[player]
	if not state or state.aura < amount then
		return false
	end
	state.aura -= amount
	return true
end

function PlayerStateService.SealTen(player: Player, duration: number)
	local state = states[player]
	if not state then
		return
	end
	state.tenSealedUntil = os.clock() + duration
	if state.auraState == "Ten" then
		state.auraState = "None"
		syncAttributes(player, state)
	end
end

function PlayerStateService.GetLastHatsuAt(player: Player): number
	local state = states[player]
	return state and state.lastHatsuAt or 0
end

function PlayerStateService.SetLastHatsuAt(player: Player, timestamp: number)
	local state = states[player]
	if state then
		state.lastHatsuAt = timestamp
	end
end

function PlayerStateService.ExtendAttackLockout(player: Player, seconds: number)
	local state = states[player]
	if not state then
		return
	end
	state.attackLockedUntil = math.max(state.attackLockedUntil, os.clock() + seconds)
end

--------------------------------------------------------------------------------
-- Damage resolution
--------------------------------------------------------------------------------

-- Applies HP damage with aura-state and Ryu mitigation. Returns the final
-- damage dealt. Downing and soul node loss are handled internally.
function PlayerStateService.ApplyDamage(player: Player, baseAmount: number, attacker: Player?): number
	local state = states[player]
	if not state or state.isDowned then
		return 0
	end

	local multiplier = 1
	if state.auraState == "Zetsu" then
		-- Aura pores closed: 0% defense, hits land as true criticals.
		multiplier = Constants.ZETSU_DAMAGE_TAKEN_MULTIPLIER
	elseif state.auraState == "Ten" then
		multiplier = 1 - Constants.TEN_DAMAGE_REDUCTION
	elseif state.auraState == "Ken" then
		multiplier = 1 - Constants.KEN_DAMAGE_REDUCTION
	end

	-- Ryu: defensive allocation grants additional scaling mitigation, but only
	-- while aura is actually flowing (not in None/Zetsu).
	if state.auraState ~= "None" and state.auraState ~= "Zetsu" then
		multiplier *= 1 - (state.ryuRatio.defense * Constants.RYU_DEFENSE_SCALING)
	end

	local finalDamage = math.max(0, baseAmount * multiplier)
	state.hp = math.max(0, state.hp - finalDamage)

	PlayerStateService.RefreshCombatTag(player)
	if attacker then
		PlayerStateService.RefreshCombatTag(attacker)
	end

	sendFeedback(player, "TookHit", finalDamage)

	if state.hp <= 0 then
		PlayerStateService.EnterDownedState(player)
	end

	return finalDamage
end

-- Applies posture damage; triggers Guard Break at cap (GDD section 8).
function PlayerStateService.ApplyPostureDamage(player: Player, amount: number)
	local state = states[player]
	if not state or state.isDowned then
		return
	end

	state.posture = state.posture + amount
	state.lastPostureDamageAt = os.clock()

	if state.posture >= Constants.MAX_POSTURE then
		state.posture = 0
		state.isGuardBroken = true
		state.isBlocking = false
		state.isParrying = false
		state.guardBreakEndsAt = os.clock() + Constants.GUARD_BREAK_DURATION
		PlayerStateService.GuardBroken:Fire(player)
		sendFeedback(player, "GuardBreak")
	end
end

--------------------------------------------------------------------------------
-- Downed state, Grip finishers, soul nodes (GDD section 2 foundation)
--------------------------------------------------------------------------------

function PlayerStateService.EnterDownedState(player: Player)
	local state = states[player]
	if not state or state.isDowned then
		return
	end
	state.isDowned = true
	state.downedEndsAt = os.clock() + Constants.DOWNED_BLEEDOUT_SECONDS
	state.isBlocking = false
	state.isParrying = false
	state.auraState = "None"
	syncAttributes(player, state)

	-- Physically incapacitate the character while downed.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.PlatformStand = true
	end

	PlayerStateService.PlayerDowned:Fire(player)
	sendFeedback(player, "Downed")
end

-- Strips a soul node (Grip finisher, bleed-out, awakening failure, or future
-- disconnect payload). Kills the character; at 0 nodes triggers the wipe path.
function PlayerStateService.LoseSoulNode(player: Player, reason: string)
	local state = states[player]
	if not state then
		return
	end

	state.soulNodes = math.max(0, state.soulNodes - 1)
	PlayerStateService.SoulNodeLost:Fire(player, state.soulNodes, reason)
	sendFeedback(player, "SoulNodeLost", state.soulNodes)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = 0
	end

	if state.soulNodes <= 0 then
		-- Foundation-phase wipe: reset the in-memory character. Erases level
		-- stats, Nen, money - everything except account-bound unlocks (future).
		-- DataPersistenceService subscribes to CharacterWiped and saves the
		-- reset immediately so a wipe cannot be escaped by crashing the server.
		warn(`[PlayerStateService] {player.Name} lost their final Soul Node - character wiped`)
		states[player] = newState()
		PlayerStateService.CharacterWiped:Fire(player)
	end
end

--------------------------------------------------------------------------------
-- Memory slots (consumed via NenAffinityService)
--------------------------------------------------------------------------------

function PlayerStateService.CanAffordMemorySlots(player: Player, cost: number): boolean
	local state = states[player]
	return state ~= nil and (state.memorySlotsUsed + cost) <= state.memorySlotCap
end

function PlayerStateService.SpendMemorySlots(player: Player, cost: number): boolean
	if not PlayerStateService.CanAffordMemorySlots(player, cost) then
		return false
	end
	local state = states[player]
	state.memorySlotsUsed += cost
	return true
end

--------------------------------------------------------------------------------
-- Persistence API (called by DataPersistenceService)
--------------------------------------------------------------------------------

-- Serializes the persistent slice of this player's state.
function PlayerStateService.BuildPersistedData(player: Player)
	local state = states[player]
	if not state then
		return nil
	end
	return {
		soulNodes = state.soulNodes,
		memorySlotsUsed = state.memorySlotsUsed,
		money = state.money,
		nenAwakened = state.nenAwakened,
		awakeningPenalties = table.clone(state.awakeningPenalties),
		auraColor = table.clone(state.auraColor),
		seiyakuBuild = state.seiyakuBuild,
	}
end

-- Hydrates state from a loaded profile. Defensive about malformed data since
-- schemas evolve; anything missing keeps its default.
function PlayerStateService.ApplyPersistedData(player: Player, data)
	local state = states[player]
	if not state or type(data) ~= "table" then
		return
	end

	if type(data.soulNodes) == "number" then
		state.soulNodes = math.clamp(math.floor(data.soulNodes), 0, Constants.STARTING_SOUL_NODES)
	end
	if type(data.memorySlotsUsed) == "number" then
		state.memorySlotsUsed = math.clamp(math.floor(data.memorySlotsUsed), 0, state.memorySlotCap)
	end
	if type(data.money) == "number" then
		state.money = math.max(0, math.floor(data.money))
	end

	state.nenAwakened = data.nenAwakened == true
	if type(data.awakeningPenalties) == "table" then
		state.awakeningPenalties.bypassed = data.awakeningPenalties.bypassed == true
		state.awakeningPenalties.mutilated = data.awakeningPenalties.mutilated == true
	end
	if type(data.auraColor) == "table" then
		PlayerStateService.SetAuraColor(player, data.auraColor.r, data.auraColor.g, data.auraColor.b)
	end
	if type(data.seiyakuBuild) == "table" then
		state.seiyakuBuild = data.seiyakuBuild
	end

	-- Studio debug override survives hydration so testing never gets locked out.
	if RunService:IsStudio() and Constants.AUTO_AWAKEN_DEBUG then
		state.nenAwakened = true
	end

	applyPenaltyCaps(state)
	syncAttributes(player, state)
end

--------------------------------------------------------------------------------
-- Heartbeat simulation + snapshot replication
--------------------------------------------------------------------------------

local function buildSnapshot(state): Types.StateSnapshot
	return {
		hp = state.hp,
		maxHp = state.maxHp,
		posture = state.posture,
		maxPosture = Constants.MAX_POSTURE,
		aura = state.aura,
		maxAura = state.maxAura,
		soulNodes = state.soulNodes,
		memorySlotsUsed = state.memorySlotsUsed,
		memorySlotCap = state.memorySlotCap,
		money = state.money,
		nenAwakened = state.nenAwakened,
		auraState = state.auraState,
		ryuOffense = state.ryuRatio.offense,
		combatTagRemaining = math.max(0, state.combatTagEndsAt - os.clock()),
		isBlocking = state.isBlocking,
		isGuardBroken = state.isGuardBroken,
		isDowned = state.isDowned,
	}
end

local function stepPlayer(player: Player, state, deltaTime: number)
	local now = os.clock()

	-- Expire the parry window.
	if state.isParrying and (now - state.parryStartedAt) > Constants.PARRY_WINDOW_SECONDS then
		state.isParrying = false
	end

	-- Recover from guard break.
	if state.isGuardBroken and now >= state.guardBreakEndsAt then
		state.isGuardBroken = false
	end

	-- Posture regeneration after a grace period.
	if state.posture > 0 and (now - state.lastPostureDamageAt) >= Constants.POSTURE_REGEN_DELAY then
		state.posture = math.max(0, state.posture - Constants.POSTURE_REGEN_PER_SECOND * deltaTime)
	end

	-- Aura economy: Ren/Ken drain, everything else regenerates
	-- (Zetsu at an accelerated rate per the GDD).
	if state.auraState == "Ren" then
		state.aura -= Constants.REN_AURA_DRAIN_PER_SECOND * deltaTime
	elseif state.auraState == "Ken" then
		state.aura -= Constants.KEN_AURA_DRAIN_PER_SECOND * deltaTime
	else
		local regen = Constants.AURA_REGEN_PER_SECOND
		if state.auraState == "Zetsu" then
			regen *= Constants.ZETSU_RECOVERY_MULTIPLIER
		end
		state.aura = math.min(state.maxAura, state.aura + regen * deltaTime)
	end
	-- Aura exhausted: forcibly drop surging states back to Ten.
	if state.aura <= 0 then
		state.aura = 0
		if state.auraState == "Ren" or state.auraState == "Ken" then
			state.auraState = "Ten"
			syncAttributes(player, state)
		end
	end

	-- Downed bleed-out.
	if state.isDowned and now >= state.downedEndsAt then
		PlayerStateService.LoseSoulNode(player, "bleedout")
	end
end

function PlayerStateService.Init()
	local function onPlayerAdded(player: Player)
		local state = newState()
		states[player] = state

		-- Studio debug: auto-awaken Nen and assign an affinity so combat and
		-- the skill tree are testable without running the Awakening NPC flow.
		-- The require is lazy to avoid a load-time circular dependency
		-- (NenAffinityService requires this module at the top level).
		if RunService:IsStudio() and Constants.AUTO_AWAKEN_DEBUG then
			state.nenAwakened = true
			task.defer(function()
				local NenAffinityService = require(script.Parent.NenAffinityService)
				if player.Parent and not NenAffinityService.GetAffinity(player) then
					NenAffinityService.AssignAffinity(player)
				end
			end)
		end

		player.CharacterAdded:Connect(function()
			local currentState = states[player]
			if currentState then
				resetVolatile(currentState)
				syncAttributes(player, currentState)
			end
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local state = states[player]
		if state and os.clock() < state.combatTagEndsAt then
			-- Combat logger detected. The full disconnect payload (30s pinned
			-- avatar + automated execution) is future permadeath work; the
			-- detection hook fires now so that system can attach here.
			local remaining = state.combatTagEndsAt - os.clock()
			warn(`[PlayerStateService] {player.Name} disconnected while combat-tagged ({math.ceil(remaining)}s remaining)`)
			PlayerStateService.CombatLoggerDetected:Fire(player, remaining)
		end
		states[player] = nil
	end)

	-- Aura RGB selection (foundation for the future character creation suite).
	auraColorRemote.OnServerEvent:Connect(function(player, color)
		if type(color) == "table" then
			PlayerStateService.SetAuraColor(player, color.r, color.g, color.b)
		end
	end)

	-- Simulation step.
	RunService.Heartbeat:Connect(function(deltaTime)
		for player, state in states do
			stepPlayer(player, state, deltaTime)
		end
	end)

	-- Throttled snapshot replication to each owning client.
	task.spawn(function()
		local interval = 1 / Constants.SNAPSHOT_RATE
		while true do
			task.wait(interval)
			for player, state in states do
				snapshotRemote:FireClient(player, buildSnapshot(state))
			end
		end
	end)
end

return PlayerStateService
