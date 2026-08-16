--!strict
-- All gameplay tuning values live here so balance passes never require
-- touching service logic. Values sourced from the GDD where specified.

local Constants = {
	-- Health & life pool
	MAX_HP = 100,
	STARTING_SOUL_NODES = 2, -- GDD section 2: characters start with 2 Soul Nodes
	DOWNED_BLEEDOUT_SECONDS = 15, -- time before a downed player bleeds out (loses a node)

	-- Posture / balance meter
	MAX_POSTURE = 100,
	POSTURE_REGEN_PER_SECOND = 8,
	POSTURE_REGEN_DELAY = 2.5, -- seconds after last posture damage before regen kicks in
	GUARD_BREAK_DURATION = 3, -- seconds spent vulnerable after posture cap is reached

	-- Melee combat
	TARGET_FRAME_RATE = 60,
	PARRY_WINDOW_FRAMES = 10, -- GDD section 8: 10-frame parry window
	PARRY_COOLDOWN = 0.8,
	PARRY_POSTURE_DAMAGE_TO_ATTACKER = 35, -- heavy posture punish on a successful parry
	PARRY_FRAME_TRAP_SECONDS = 1.2, -- attacker's attacks are locked out after being parried
	ATTACK_COOLDOWN = 0.45,
	ATTACK_RANGE = 8, -- studs, depth of the melee sweep
	ATTACK_HITBOX_SIZE = Vector3.new(5, 5, 8),
	BASE_MELEE_DAMAGE = 10,
	BLOCK_POSTURE_DAMAGE = 14, -- posture consumed by the blocker per blocked hit
	NETWORK_TOLERANCE = 0.15, -- seconds of latency slack when validating timing windows

	-- Aura state combat modifiers
	TEN_DAMAGE_REDUCTION = 0.15, -- Ten envelope reduces physical damage taken
	KEN_DAMAGE_REDUCTION = 0.4, -- Ken trades aura upkeep for strong mitigation
	ZETSU_DAMAGE_TAKEN_MULTIPLIER = 2.0, -- GDD: Zetsu drops defense to 0%, hits are true crits
	REN_DAMAGE_BONUS = 0.25, -- Ren surges outward aura, boosting strike power
	RYU_OFFENSE_SCALING = 0.3, -- max bonus damage from a full-offense Ryu allocation
	RYU_DEFENSE_SCALING = 0.3, -- max damage reduction from a full-defense Ryu allocation

	-- Aura resource
	MAX_AURA = 100,
	AURA_REGEN_PER_SECOND = 4,
	ZETSU_RECOVERY_MULTIPLIER = 2.0, -- Zetsu accelerates stamina/aura recovery
	REN_AURA_DRAIN_PER_SECOND = 6, -- Ren steadily drains aura while active
	KEN_AURA_DRAIN_PER_SECOND = 4,

	-- Combat tag / anti-combat-logging (GDD section 2)
	COMBAT_TAG_DURATION = 20,

	-- Nen progression (GDD sections 5 & 6)
	MEMORY_SLOT_CAP = 100, -- Kastro Penalty Engine hard cap
	IN_BETWEEN_AFFINITY_CHANCE = 0.02, -- rare roll landing between two adjacent types

	-- Economy
	STARTING_MONEY = 1000,

	-- Forced Nen Awakening (GDD section 3)
	AWAKENING_COST = 500, -- money charged per wheel spin
	AWAKENING_WHEEL_SECONDS = 3, -- client cinematic length; server delays outcome application to match
	AWAKENING_QTE_SECONDS = 3, -- GDD: fail the QTE within 3 seconds -> collapse
	AWAKENING_QTE_REQUIRED_HITS = 3, -- successful zone hits needed to stabilize Ten
	MUTILATION_HP_MULTIPLIER = 0.9, -- permanent -10% max HP
	MUTILATION_AURA_MULTIPLIER = 0.85, -- permanent -15% max aura
	BYPASSED_EFFICIENCY_PENALTY = 15, -- flat efficiency loss on all non-innate categories
	BYPASSED_HATSU_COST_MULTIPLIER = 1.25, -- +25% aura cost on Hatsu (consumed by future Hatsu system)

	-- Debug
	AUTO_AWAKEN_DEBUG = true, -- Studio only: auto-awaken Nen + assign affinity on join for testing

	-- Persistence (DataStore v2 + MemoryStore session locks)
	DATASTORE_NAME = "PlayerData_v1",
	SESSION_LOCK_MAP_NAME = "SessionLocks_v1",
	DATA_SCHEMA_VERSION = 1,
	AUTOSAVE_INTERVAL = 60, -- seconds between periodic saves
	SESSION_LOCK_TTL = 90, -- seconds before an abandoned lock expires
	SESSION_LOCK_RENEW_INTERVAL = 30, -- how often live sessions extend their lock
	SESSION_LOCK_RETRIES = 5,
	SESSION_LOCK_RETRY_DELAY = 2,

	-- Aura VFX
	DEFAULT_AURA_COLOR = { r = 130, g = 200, b = 255 },

	-- Hatsu (signature ability execution)
	HATSU_BASE_DAMAGE = 20,
	HATSU_BASE_AURA_COST = 25,
	HATSU_BASE_COOLDOWN = 8, -- seconds between casts (doubled if cooldown_penalty condition)
	HATSU_ACTIVATION_DELAY = 3, -- seconds for activation_delay condition charge
	HATSU_TEN_SEAL_DURATION = 10, -- seconds Ten is sealed after cast (ten_seal condition)
	HATSU_BLINDNESS_DURATION = 4, -- seconds of screen obscuration (blindness modifier)
	HATSU_STUN_EXTENSION = 1.5, -- extra attack lockout seconds (stun_extension modifier)
	HATSU_BACKFIRE_FRACTION = 0.25, -- self-damage fraction on miss (backfire condition)
	HATSU_HP_RESTRICTION_THRESHOLD = 0.3, -- hp_below_30 condition cutoff

	-- Replication
	SNAPSHOT_RATE = 10, -- Hz; how often each client receives its own state snapshot
}

Constants.PARRY_WINDOW_SECONDS = Constants.PARRY_WINDOW_FRAMES / Constants.TARGET_FRAME_RATE

return Constants
