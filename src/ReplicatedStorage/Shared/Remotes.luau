--!strict
-- Single source of truth for RemoteEvents and RemoteFunctions. The server
-- creates them lazily; clients wait for them. Any name not in the registry is
-- a hard error, which catches typos at require-time instead of silently
-- yielding forever.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local REMOTE_EVENT_NAMES: { [string]: boolean } = {
	CombatIntent = true, -- client -> server: attack / parry / block intents
	AuraIntent = true, -- client -> server: aura state changes, Ryu ratio
	SetAuraColor = true, -- client -> server: aura RGB selection
	StateSnapshot = true, -- server -> client: throttled HUD state
	CombatFeedback = true, -- server -> client: parry/hit/guard-break flashes
	CombatBroadcast = true, -- server -> ALL clients: animation/VFX events
	AffinityAssigned = true, -- server -> client: rolled Nen affinity info
	AwakeningResult = true, -- server -> client: awakening wheel outcome
	AwakeningQTE = true, -- both ways: server starts the QTE, client reports presses, server sends the verdict
	HatsuIntent = true, -- client -> server: activate stored Seiyaku Hatsu
	HatsuEffect = true, -- server -> client: blindness and other victim-side effects
	FocusTick = true, -- client -> server: one rhythm hit during Natural Meditation
	DivinationOutcome = true, -- server -> client: Water Divination result + cup VFX cue
}

local REMOTE_FUNCTION_NAMES: { [string]: boolean } = {
	PurchaseSkillNode = true, -- client invokes: buy a skill node (server-verified)
	SubmitSeiyakuBuild = true, -- client invokes: validate + store a Seiyaku build
	GetSeiyakuBuild = true, -- client invokes: fetch stored build for editor hydration
	ToggleMeditation = true, -- client invokes: enter/leave Natural Meditation (server decides)
}

local Remotes = {}

local function getFolder(): Folder
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder :: Folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local function getRemote(name: string, className: "RemoteEvent" | "RemoteFunction"): Instance
	local folder = getFolder()
	if RunService:IsServer() then
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
		return remote
	end
	return folder:WaitForChild(name)
end

function Remotes.Get(name: string): RemoteEvent
	assert(REMOTE_EVENT_NAMES[name], `Unknown remote event "{name}" - add it to the registry in Remotes.luau`)
	return getRemote(name, "RemoteEvent") :: RemoteEvent
end

function Remotes.GetFunction(name: string): RemoteFunction
	assert(REMOTE_FUNCTION_NAMES[name], `Unknown remote function "{name}" - add it to the registry in Remotes.luau`)
	return getRemote(name, "RemoteFunction") :: RemoteFunction
end

return Remotes
