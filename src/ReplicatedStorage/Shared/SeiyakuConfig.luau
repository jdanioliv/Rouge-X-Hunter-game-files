--!strict
-- Seiyaku (Pledge & Limitation) balance data, straight from GDD section 4.
-- Conditions GENERATE budget points; modifiers SPEND them. Pure data so both
-- the future client editor and the server validator read the same numbers.

local SeiyakuConfig = {}

-- Build-wide caps ("expenditure caps").
SeiyakuConfig.MAX_CONDITIONS = 4
SeiyakuConfig.MAX_MODIFIERS = 3

export type Condition = {
	id: string,
	name: string,
	points: number,
	description: string,
}

export type ModifierTier = {
	cost: number,
	value: number, -- meaning depends on the modifier (e.g. damage bonus fraction)
}

export type Modifier = {
	id: string,
	name: string,
	cost: number?, -- flat-cost modifiers
	tiers: { ModifierTier }?, -- tiered modifiers (cost varies by tier)
	description: string,
}

SeiyakuConfig.Conditions = {
	{
		id = "hp_below_30",
		name = "HP Restriction",
		points = 3,
		description = "Usable only below 30% HP.",
	},
	{
		id = "target_restriction",
		name = "Target Restriction",
		points = 4,
		description = "Usable only against Hunter License holders or designated Faction targets.",
	},
	{
		id = "activation_delay",
		name = "Activation Delay",
		points = 2,
		description = "Requires a 3-second static charging animation before execution.",
	},
	{
		id = "cooldown_penalty",
		name = "Cooldown Penalty",
		points = 2,
		description = "Increases base ability cooldown by 100%.",
	},
	{
		id = "ten_seal",
		name = "Self-Debuff",
		points = 4,
		description = "Seals your own Ten for 10 seconds after casting.",
	},
	{
		id = "backfire",
		name = "Backfire Penalty",
		points = 5,
		description = "Missing the ability deals 25% of its damage to you.",
	},
} :: { Condition }

SeiyakuConfig.Modifiers = {
	{
		id = "guard_break",
		name = "Guard Break",
		cost = 3,
		description = "Bypasses enemy posture entirely, dealing full raw damage through blocks.",
	},
	{
		id = "blindness",
		name = "Temporary Blindness",
		cost = 3,
		description = "Obscures the target's screen with darkness/aura noise for 4 seconds.",
	},
	{
		id = "damage_boost",
		name = "Damage Multiplier",
		tiers = {
			{ cost = 2, value = 0.25 },
			{ cost = 3, value = 0.45 },
			{ cost = 4, value = 0.6 },
			{ cost = 5, value = 0.8 },
			{ cost = 6, value = 1.0 },
		},
		description = "Increases base damage scaling from +25% up to +100%.",
	},
	{
		id = "aoe_expansion",
		name = "Area of Effect Expansion",
		cost = 2,
		description = "Doubles the blast radius or vector width of the Hatsu strike.",
	},
	{
		id = "stun_extension",
		name = "Stun Duration Extension",
		cost = 3,
		description = "Extends opponent hit-stagger by 1.5 seconds, enabling combo routes.",
	},
} :: { Modifier }

-- Lookup maps built once at require time.
SeiyakuConfig.ConditionsById = {} :: { [string]: Condition }
for _, condition in SeiyakuConfig.Conditions do
	SeiyakuConfig.ConditionsById[condition.id] = condition
end

SeiyakuConfig.ModifiersById = {} :: { [string]: Modifier }
for _, modifier in SeiyakuConfig.Modifiers do
	SeiyakuConfig.ModifiersById[modifier.id] = modifier
end

return SeiyakuConfig
