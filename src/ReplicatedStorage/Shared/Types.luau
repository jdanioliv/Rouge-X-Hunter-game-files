--!strict
-- Shared Luau type definitions used across server services and client controllers.

export type NenCategory =
	"Enhancement"
	| "Transmutation"
	| "Conjuration"
	| "Emission"
	| "Manipulation"
	| "Specialization"

export type AuraState = "None" | "Ten" | "Zetsu" | "Ren" | "Ken"

-- Natural Meditation session state. Transient and server-owned: only the
-- accumulated `focusProgress` survives into PersistedData.meditationProgress.
-- `lastTickTimestamp` is the server clock reading of the last ACCEPTED
-- FocusTick and is what makes tick-rate spoofing detectable.
export type MeditationState = {
	isMeditating: boolean,
	focusProgress: number, -- 0..Constants.MEDITATION.MAX_PROGRESS
	lastTickTimestamp: number,
}

-- Server -> client outcome of the Water Divination ceremony.
export type DivinationResult = {
	category: NenCategory,
	success: boolean,
	message: string?,
}

-- A player's innate Nen affinity. `secondary` is only set for rare
-- in-between rolls (e.g. Killua/Machi between Transmutation and Enhancement).
export type Affinity = {
	primary: NenCategory,
	secondary: NenCategory?,
}

export type RyuRatio = {
	offense: number, -- 0..1
	defense: number, -- 0..1, always 1 - offense
}

export type AuraColor = {
	r: number, -- 0..255
	g: number,
	b: number,
}

-- Permanent consequences from the Forced Nen Awakening wheel (GDD section 3).
export type AwakeningPenalties = {
	bypassed: boolean, -- -15% non-innate efficiency, +25% Hatsu aura cost
	mutilated: boolean, -- -10% max HP, -15% max aura
}

export type AwakeningOutcome = "Clean" | "Exhaustion" | "Mutilation" | "Bypassed" | "Fatal"

-- AwakeningQTE remote, server -> client: starts the QTE, then sends its verdict.
export type AwakeningQTEStart = {
	duration: number,
	requiredHits: number,
}
export type AwakeningQTEVerdict = {
	verdict: "Stabilized" | "Collapsed",
}
-- AwakeningQTE remote, client -> server: one press, stamped with the client's QTE
-- time. The server recomputes the marker at that time and judges the hit itself.
export type AwakeningQTEPress = {
	elapsed: number,
}

-- A validated Seiyaku (Pledge & Limitation) build (GDD section 4).
export type SeiyakuModifierSelection = {
	id: string,
	tier: number?, -- required for tiered modifiers (e.g. damage_boost)
}

export type SeiyakuBuild = {
	name: string?,
	conditionIds: { string },
	modifiers: { SeiyakuModifierSelection },
}

-- Full authoritative state. Lives ONLY on the server; never trusted from clients.
export type PlayerState = {
	hp: number,
	maxHp: number,
	posture: number,
	aura: number,
	maxAura: number,
	soulNodes: number,
	memorySlotsUsed: number,
	memorySlotCap: number,
	money: number,

	nenAwakened: boolean,
	meditationProgress: number, -- 0..MEDITATION.MAX_PROGRESS; 100 unlocks Water Divination
	isMeditating: boolean, -- mirrored here for replication; MeditationService is the only writer
	awakeningPenalties: AwakeningPenalties,
	auraColor: AuraColor,
	seiyakuBuild: SeiyakuBuild?,

	isParrying: boolean,
	parryStartedAt: number,
	lastParryAt: number,

	isBlocking: boolean,
	isGuardBroken: boolean,
	guardBreakEndsAt: number,
	lastPostureDamageAt: number,

	auraState: AuraState,
	ryuRatio: RyuRatio,

	combatTagEndsAt: number,

	isDowned: boolean,
	isDead: boolean, -- killed by a Soul Node loss and waiting to respawn

	lastAttackAt: number,
	attackLockedUntil: number, -- frame-trap lockout after being parried
	lastHatsuAt: number,
	tenSealedUntil: number, -- Ten blocked until this timestamp (ten_seal condition)
}

-- Read-only subset replicated to the owning client for HUD rendering.
export type StateSnapshot = {
	hp: number,
	maxHp: number,
	posture: number,
	maxPosture: number,
	aura: number,
	maxAura: number,
	soulNodes: number,
	memorySlotsUsed: number,
	memorySlotCap: number,
	money: number,
	nenAwakened: boolean,
	meditationProgress: number,
	maxMeditationProgress: number,
	isMeditating: boolean,
	auraState: AuraState,
	ryuOffense: number,
	combatTagRemaining: number,
	isBlocking: boolean,
	isGuardBroken: boolean,
	isDowned: boolean,
}

-- Serialized profile stored in DataStore (see DataPersistenceService).
export type PersistedData = {
	schemaVersion: number,
	soulNodes: number,
	memorySlotsUsed: number,
	money: number,
	nenAwakened: boolean,
	meditationProgress: number,
	awakeningPenalties: AwakeningPenalties,
	auraColor: AuraColor,
	affinity: Affinity?,
	learnedNodes: { [string]: number },
	seiyakuBuild: SeiyakuBuild?,
}

-- Client -> server combat intent payload.
export type CombatIntent = {
	action: "Attack" | "Parry" | "BlockStart" | "BlockEnd",
}

-- Client -> server aura intent payload.
export type AuraIntent = {
	auraState: AuraState?,
	ryuOffense: number?,
}

-- Server -> client combat feedback for HUD flashes.
export type CombatFeedback = {
	kind: "ParrySuccess" | "GotParried" | "GuardBreak" | "Hit" | "TookHit" | "Blocked" | "Downed" | "SoulNodeLost" | "Grip",
	amount: number?,
}

-- Server -> all clients: transient combat events for animation/VFX rendering.
export type CombatBroadcast = {
	kind: "Attack" | "Parry" | "Stagger" | "GuardBreak" | "Downed" | "Recovered" | "BlockStart" | "BlockEnd",
	userId: number,
}

return {}
