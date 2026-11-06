--!strict
-- The Forced Nen Awakening outcome wheel (GDD section 3). Pure data + a
-- weighted roll, shared so the client can render the wheel cinematic with the
-- same metadata the server rolls against. Also holds the QTE marker formula, so
-- the bar the client draws and the check the server runs cannot disagree.

local AwakeningOutcomes = {}

-- Display order around the wheel.
AwakeningOutcomes.Order = { "Clean", "Exhaustion", "Mutilation", "Bypassed", "Fatal" }

AwakeningOutcomes.Info = {
	Clean = {
		weight = 35,
		title = "Clean Awakening",
		description = "Your aura nodes open safely. The Water Divination reveals your Nen affinity.",
		color = { r = 120, g = 220, b = 140 },
	},
	Exhaustion = {
		weight = 25,
		title = "Lethal Exhaustion",
		description = "Life energy is leaking uncontrollably! Balance your aura into Ten before you collapse!",
		color = { r = 255, g = 200, b = 80 },
	},
	Mutilation = {
		weight = 20,
		title = "Aura Node Mutilation",
		description = "Your aura nodes are permanently scarred. Max HP and max Aura are reduced forever.",
		color = { r = 220, g = 100, b = 60 },
	},
	Bypassed = {
		weight = 15,
		title = "Bypassed Fundamentals",
		description = "You awaken, but skipping conditioning permanently damages your aura efficiency.",
		color = { r = 170, g = 130, b = 255 },
	},
	Fatal = {
		weight = 5,
		title = "Fatal Overload",
		description = "Total aura rupture. Your life force is torn away.",
		color = { r = 255, g = 60, b = 60 },
	},
}

function AwakeningOutcomes.Roll(random: Random): string
	local total = 0
	for _, outcome in AwakeningOutcomes.Order do
		total += AwakeningOutcomes.Info[outcome].weight
	end
	local pick = random:NextNumber(0, total)
	local accumulated = 0
	for _, outcome in AwakeningOutcomes.Order do
		accumulated += AwakeningOutcomes.Info[outcome].weight
		if pick <= accumulated then
			return outcome
		end
	end
	return "Clean"
end

-- Marker position on the QTE bar (0..1) at this many seconds into the QTE.
-- The oscillation speeds up as the collapse timer runs down.
function AwakeningOutcomes.QTEMarkerPosition(elapsed: number): number
	local frequency = 6 + elapsed * 1.5
	return 0.5 + 0.45 * math.sin(elapsed * frequency)
end

function AwakeningOutcomes.IsQTEHit(elapsed: number, zoneHalfWidth: number): boolean
	return math.abs(AwakeningOutcomes.QTEMarkerPosition(elapsed) - 0.5) <= zoneHalfWidth
end

return AwakeningOutcomes
