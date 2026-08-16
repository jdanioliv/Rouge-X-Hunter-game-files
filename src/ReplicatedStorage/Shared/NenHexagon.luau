--!strict
-- Pure data + pure functions implementing GDD sections 5 and 6:
-- the Togashi-memo hexagonal efficiency model and the Kastro Penalty
-- Engine memory slot cost tiers. No Roblox API calls, so this module
-- is unit-testable in plain Luau.

local Types = require(script.Parent.Types)

type NenCategory = Types.NenCategory
type Affinity = Types.Affinity

local NenHexagon = {}

NenHexagon.Categories = {
	"Enhancement",
	"Transmutation",
	"Conjuration",
	"Emission",
	"Manipulation",
	"Specialization",
} :: { NenCategory }

-- Efficiency tables straight from the GDD (section 6). Rows are the innate
-- category, columns are the target category being learned/used.
-- Note the asymmetric Conjurer/Manipulator rows and the 1% Specialization
-- access those two types get; all others get 0% Specialization.
local EFFICIENCY: { [NenCategory]: { [NenCategory]: number } } = {
	Enhancement = {
		Enhancement = 100,
		Transmutation = 80,
		Emission = 80,
		Conjuration = 60,
		Manipulation = 60,
		Specialization = 0,
	},
	Transmutation = {
		Transmutation = 100,
		Enhancement = 80,
		Conjuration = 80,
		Emission = 60,
		Manipulation = 40,
		Specialization = 0,
	},
	Conjuration = {
		Conjuration = 100,
		Transmutation = 80,
		Enhancement = 60,
		Manipulation = 60,
		Emission = 40,
		Specialization = 1,
	},
	Emission = {
		Emission = 100,
		Enhancement = 80,
		Manipulation = 80,
		Transmutation = 60,
		Conjuration = 40,
		Specialization = 0,
	},
	Manipulation = {
		Manipulation = 100,
		Emission = 80,
		Enhancement = 60,
		Conjuration = 60,
		Transmutation = 40,
		Specialization = 1,
	},
	-- Specialists use custom matrices per Hatsu contract (GDD); this is the
	-- baseline before contract-specific overrides exist.
	Specialization = {
		Specialization = 100,
		Enhancement = 60,
		Transmutation = 60,
		Conjuration = 60,
		Emission = 60,
		Manipulation = 60,
	},
}

-- Memory slot cost per skill node by efficiency tier (GDD section 5,
-- "Kastro Penalty Engine"). Below 40% the category is locked entirely.
local SLOT_COST_TIERS: { { threshold: number, cost: number } } = {
	{ threshold = 100, cost = 1 }, -- innate type mastery
	{ threshold = 80, cost = 2 }, -- adjacent category
	{ threshold = 60, cost = 3 }, -- secondary adjacent category
	{ threshold = 40, cost = 5 }, -- opposite category
}

-- Adjacent pairs on the hexagon eligible for rare in-between affinity rolls
-- (Specialization is excluded; you cannot roll half-Specialist).
NenHexagon.AdjacentPairs = {
	{ "Enhancement", "Transmutation" },
	{ "Enhancement", "Emission" },
	{ "Transmutation", "Conjuration" },
	{ "Emission", "Manipulation" },
	{ "Conjuration", "Manipulation" },
} :: { { NenCategory } }

-- Returns the efficiency (0..100) a player with the given affinity has when
-- learning or using the target category. In-between affinities use the best
-- of their two parent categories.
function NenHexagon.GetEfficiency(affinity: Affinity, target: NenCategory): number
	local primary = EFFICIENCY[affinity.primary][target]
	local secondary = affinity.secondary
	if secondary then
		return math.max(primary, EFFICIENCY[secondary][target])
	end
	return primary
end

-- Returns the memory slot cost for one skill node at the given efficiency,
-- or nil if the category is locked (efficiency below 40%).
function NenHexagon.GetMemorySlotCost(efficiency: number): number?
	for _, tier in SLOT_COST_TIERS do
		if efficiency >= tier.threshold then
			return tier.cost
		end
	end
	return nil
end

-- Convenience: damage/effect scaling multiplier for using an ability of the
-- target category (100% efficiency -> 1.0, 60% -> 0.6, etc.).
function NenHexagon.GetEffectMultiplier(affinity: Affinity, target: NenCategory): number
	return NenHexagon.GetEfficiency(affinity, target) / 100
end

function NenHexagon.IsCategoryLocked(affinity: Affinity, target: NenCategory): boolean
	return NenHexagon.GetMemorySlotCost(NenHexagon.GetEfficiency(affinity, target)) == nil
end

return NenHexagon
