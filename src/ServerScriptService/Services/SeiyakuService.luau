-- SeiyakuService
-- Server-side validation and storage for Seiyaku (Pledge & Limitation)
-- builds. Every submission is re-validated with the shared SeiyakuBudget
-- module regardless of what the client editor claimed, then sanitized into a
-- fresh table (never storing client-provided tables directly) and persisted
-- with the player's profile. Ability EXECUTION arrives with the Hatsu combat
-- phase; this service only owns the contract itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local SeiyakuBudget = require(Shared.SeiyakuBudget)

local PlayerStateService = require(script.Parent.PlayerStateService)

local SeiyakuService = {}

local submitFunction = Remotes.GetFunction("SubmitSeiyakuBuild")
local getBuildFunction = Remotes.GetFunction("GetSeiyakuBuild")

local MAX_NAME_LENGTH = 40

-- Rebuilds the payload from scratch so only expected fields with expected
-- types ever reach state/persistence.
local function sanitizeBuild(build)
	local sanitized = {
		name = nil,
		conditionIds = {},
		modifiers = {},
	}
	if type(build.name) == "string" then
		sanitized.name = string.sub(build.name, 1, MAX_NAME_LENGTH)
	end
	for _, id in build.conditionIds do
		table.insert(sanitized.conditionIds, tostring(id))
	end
	for _, selection in build.modifiers do
		table.insert(sanitized.modifiers, {
			id = tostring(selection.id),
			tier = type(selection.tier) == "number" and selection.tier or nil,
		})
	end
	return sanitized
end

function SeiyakuService.Init()
	getBuildFunction.OnServerInvoke = function(player)
		local state = PlayerStateService.GetState(player)
		if not state or not state.nenAwakened then
			return { build = nil }
		end
		return { build = PlayerStateService.GetSeiyakuBuild(player) }
	end

	submitFunction.OnServerInvoke = function(player, build)
		local state = PlayerStateService.GetState(player)
		if not state then
			return { success = false, reason = "NoState" }
		end
		if not state.nenAwakened then
			return { success = false, reason = "NenDormant" }
		end

		local result = SeiyakuBudget.ValidateBuild(build)
		if not result.ok then
			return { success = false, reason = result.reason, budget = result.budget, cost = result.cost }
		end

		PlayerStateService.SetSeiyakuBuild(player, sanitizeBuild(build))
		return { success = true, budget = result.budget, cost = result.cost, build = sanitizeBuild(build) }
	end
end

return SeiyakuService
