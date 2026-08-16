-- SkillTreeController (client)
-- Hexagonal Nen skill tree UI (toggle with N). The six categories are laid
-- out at hexagon vertices matching the Togashi memo model. Costs and
-- efficiencies are computed locally from the shared NenHexagon module (pure
-- functions of the affinity the server already sent us), but every purchase
-- is verified server-side through the PurchaseSkillNode RemoteFunction.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local NenHexagon = require(Shared:WaitForChild("NenHexagon"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local affinityRemote = Remotes.Get("AffinityAssigned")
local snapshotRemote = Remotes.Get("StateSnapshot")
local purchaseFunction = Remotes.GetFunction("PurchaseSkillNode")

--------------------------------------------------------------------------------
-- Client-side view of progression (server remains authoritative)
--------------------------------------------------------------------------------

local affinityData = nil -- { primary, secondary?, bypassed, learnedNodes }
local memorySlotsUsed = 0
local memorySlotCap = Constants.MEMORY_SLOT_CAP
local nenAwakened = false
local purchasePending = false

-- Mirrors NenAffinityService.GetEfficiency including the Bypassed penalty.
local function getEfficiency(category: string): number?
	if not affinityData or not affinityData.primary then
		return nil
	end
	local affinity = { primary = affinityData.primary, secondary = affinityData.secondary }
	local efficiency = NenHexagon.GetEfficiency(affinity, category)
	local innate = category == affinityData.primary or category == affinityData.secondary
	if affinityData.bypassed and not innate and efficiency > 0 then
		efficiency = math.max(0, efficiency - Constants.BYPASSED_EFFICIENCY_PENALTY)
	end
	return efficiency
end

--------------------------------------------------------------------------------
-- UI construction
--------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SkillTreeGui"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = playerGui

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.AnchorPoint = Vector2.new(0.5, 0.5)
backdrop.Position = UDim2.fromScale(0.5, 0.5)
backdrop.Size = UDim2.new(0, 560, 0, 560)
backdrop.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
backdrop.BackgroundTransparency = 0.15
backdrop.BorderSizePixel = 0
backdrop.Parent = screenGui

local backdropCorner = Instance.new("UICorner")
backdropCorner.CornerRadius = UDim.new(0, 12)
backdropCorner.Parent = backdrop

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 34)
title.Position = UDim2.new(0, 0, 0, 8)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextSize = 20
title.TextColor3 = Color3.fromRGB(235, 235, 240)
title.Text = "NEN HEXAGON - SKILL TREE  [N]"
title.Parent = backdrop

-- Center readout: memory pool + dormant notice.
local centerLabel = Instance.new("TextLabel")
centerLabel.AnchorPoint = Vector2.new(0.5, 0.5)
centerLabel.Position = UDim2.fromScale(0.5, 0.5)
centerLabel.Size = UDim2.new(0, 200, 0, 70)
centerLabel.BackgroundTransparency = 1
centerLabel.Font = Enum.Font.GothamBold
centerLabel.TextSize = 15
centerLabel.TextColor3 = Color3.fromRGB(230, 230, 235)
centerLabel.TextWrapped = true
centerLabel.Parent = backdrop

-- Bottom message line (purchase errors etc.)
local messageLabel = Instance.new("TextLabel")
messageLabel.AnchorPoint = Vector2.new(0.5, 1)
messageLabel.Position = UDim2.new(0.5, 0, 1, -10)
messageLabel.Size = UDim2.new(1, -20, 0, 20)
messageLabel.BackgroundTransparency = 1
messageLabel.Font = Enum.Font.Gotham
messageLabel.TextSize = 14
messageLabel.TextColor3 = Color3.fromRGB(255, 170, 90)
messageLabel.Text = ""
messageLabel.Parent = backdrop

-- Six category nodes at hexagon vertices (Enhancement on top, matching the
-- Togashi memo layout).
local HEX_ORDER = { "Enhancement", "Transmutation", "Conjuration", "Specialization", "Manipulation", "Emission" }
local HEX_RADIUS = 200

local nodeButtons: { [string]: { button: TextButton, info: TextLabel } } = {}

for index, category in HEX_ORDER do
	local angle = math.rad((index - 1) * 60 - 90)
	local offsetX = math.cos(angle) * HEX_RADIUS
	local offsetY = math.sin(angle) * HEX_RADIUS

	local button = Instance.new("TextButton")
	button.Name = category .. "Node"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.new(0.5, offsetX, 0.5, offsetY)
	button.Size = UDim2.new(0, 140, 0, 92)
	button.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 15
	button.TextColor3 = Color3.fromRGB(240, 240, 245)
	button.Text = ""
	button.AutoButtonColor = true
	button.Parent = backdrop

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 24)
	nameLabel.Position = UDim2.new(0, 0, 0, 6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextSize = 15
	nameLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
	nameLabel.Text = category
	nameLabel.Parent = button

	local infoLabel = Instance.new("TextLabel")
	infoLabel.Size = UDim2.new(1, -8, 1, -34)
	infoLabel.Position = UDim2.new(0, 4, 0, 30)
	infoLabel.BackgroundTransparency = 1
	infoLabel.Font = Enum.Font.Gotham
	infoLabel.TextSize = 12
	infoLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
	infoLabel.TextWrapped = true
	infoLabel.Text = ""
	infoLabel.Parent = button

	nodeButtons[category] = { button = button, info = infoLabel }
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

local function refresh()
	centerLabel.Text = `MEMORY\n{memorySlotsUsed} / {memorySlotCap}`

	for category, node in nodeButtons do
		local efficiency = getEfficiency(category)
		if not nenAwakened or not efficiency then
			node.button.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
			node.info.Text = "Dormant"
		else
			local cost = NenHexagon.GetMemorySlotCost(efficiency)
			local learned = affinityData.learnedNodes[category] or 0
			local innate = category == affinityData.primary or category == affinityData.secondary

			if innate then
				node.button.BackgroundColor3 = Color3.fromRGB(38, 52, 44)
			elseif cost then
				node.button.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
			else
				node.button.BackgroundColor3 = Color3.fromRGB(40, 22, 22)
			end

			if cost then
				node.info.Text = `Efficiency {efficiency}%\nCost: {cost} slot{cost > 1 and "s" or ""} / node\nLearned: {learned}`
			else
				node.info.Text = `Efficiency {efficiency}%\nLOCKED\nLearned: {learned}`
			end
		end
	end

	if not nenAwakened then
		centerLabel.Text = "NEN DORMANT\nSeek a Forced Awakening"
	end
end

local function showMessage(text: string)
	messageLabel.Text = text
	task.delay(2.5, function()
		if messageLabel.Text == text then
			messageLabel.Text = ""
		end
	end)
end

--------------------------------------------------------------------------------
-- Purchases (server-verified)
--------------------------------------------------------------------------------

local FAILURE_MESSAGES = {
	CategoryLocked = "That category is locked for your affinity.",
	MemorySaturated = "Memory saturated - the Kastro Trap has claimed you.",
	NenDormant = "Your Nen is dormant.",
	InvalidCategory = "Invalid category.",
}

for category, node in nodeButtons do
	node.button.Activated:Connect(function()
		if purchasePending or not nenAwakened or not affinityData then
			return
		end
		purchasePending = true
		task.spawn(function()
			local ok, response = pcall(function()
				return purchaseFunction:InvokeServer(category)
			end)
			purchasePending = false
			if not ok or type(response) ~= "table" then
				showMessage("Purchase failed - try again.")
				return
			end

			if type(response.learnedNodes) == "table" then
				affinityData.learnedNodes = response.learnedNodes
			end
			if type(response.memorySlotsUsed) == "number" then
				memorySlotsUsed = response.memorySlotsUsed
			end

			if response.success then
				showMessage(`Learned a {category} node.`)
			else
				showMessage(FAILURE_MESSAGES[response.reason] or `Purchase failed ({tostring(response.reason)})`)
			end
			refresh()
		end)
	end)
end

--------------------------------------------------------------------------------
-- Data feeds
--------------------------------------------------------------------------------

affinityRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.primary then
		affinityData = {
			primary = payload.primary,
			secondary = payload.secondary,
			bypassed = payload.bypassed == true,
			learnedNodes = type(payload.learnedNodes) == "table" and payload.learnedNodes or {},
		}
	else
		affinityData = nil -- wiped back to dormant
	end
	refresh()
end)

snapshotRemote.OnClientEvent:Connect(function(snapshot)
	memorySlotsUsed = snapshot.memorySlotsUsed
	memorySlotCap = snapshot.memorySlotCap
	nenAwakened = snapshot.nenAwakened
	if screenGui.Enabled then
		refresh()
	end
end)

--------------------------------------------------------------------------------
-- Toggle
--------------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.N then
		screenGui.Enabled = not screenGui.Enabled
		if screenGui.Enabled then
			refresh()
		end
	end
end)

refresh()
