-- SeiyakuController (client)
-- Full Pledge & Limitation editor (toggle with K). Players pick Conditions
-- (budget generators) and Modifiers (point spenders); SeiyakuBudget validates
-- the draft in real time. Valid builds are submitted through the server-
-- verified SubmitSeiyakuBuild RemoteFunction.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SeiyakuConfig = require(Shared:WaitForChild("SeiyakuConfig"))
local SeiyakuBudget = require(Shared:WaitForChild("SeiyakuBudget"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local submitFunction = Remotes.GetFunction("SubmitSeiyakuBuild")
local getBuildFunction = Remotes.GetFunction("GetSeiyakuBuild")
local snapshotRemote = Remotes.Get("StateSnapshot")

local nenAwakened = false
local submitPending = false

-- Draft build state.
local selectedConditions: { [string]: boolean } = {}
local selectedModifiers: { [string]: boolean } = {}
local damageBoostTier = 1 -- 1..5 when damage_boost is selected

--------------------------------------------------------------------------------
-- UI helpers
--------------------------------------------------------------------------------

local function addCorner(parent: Instance, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 6)
	corner.Parent = parent
	return corner
end

local function makeScrollColumn(parent: Instance, name: string, position: UDim2, size: UDim2)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
	frame.BorderSizePixel = 0
	frame.Parent = parent
	addCorner(frame, 8)

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, 0, 0, 28)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBlack
	header.TextSize = 15
	header.TextColor3 = Color3.fromRGB(230, 230, 235)
	header.Text = name
	header.Parent = frame

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.Position = UDim2.new(0, 8, 0, 32)
	scroll.Size = UDim2.new(1, -16, 1, -40)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	return scroll
end

local function makeToggleRow(parent: Instance, label: string, subtext: string, onToggle: (boolean) -> ()): (TextButton, (boolean) -> ())
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, -4, 0, 52)
	button.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.Parent = parent
	addCorner(button)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -12, 0, 20)
	nameLabel.Position = UDim2.new(0, 8, 0, 6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 13
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = Color3.fromRGB(235, 235, 240)
	nameLabel.Text = label
	nameLabel.Parent = button

	local detailLabel = Instance.new("TextLabel")
	detailLabel.Size = UDim2.new(1, -12, 0, 22)
	detailLabel.Position = UDim2.new(0, 8, 0, 26)
	detailLabel.BackgroundTransparency = 1
	detailLabel.Font = Enum.Font.Gotham
	detailLabel.TextSize = 11
	detailLabel.TextXAlignment = Enum.TextXAlignment.Left
	detailLabel.TextWrapped = true
	detailLabel.TextColor3 = Color3.fromRGB(170, 170, 180)
	detailLabel.Text = subtext
	detailLabel.Parent = button

	local selected = false
	local function setSelected(value: boolean)
		selected = value
		button.BackgroundColor3 = selected and Color3.fromRGB(42, 58, 48) or Color3.fromRGB(24, 24, 32)
	end

	button.Activated:Connect(function()
		setSelected(not selected)
		onToggle(selected)
	end)

	return button, setSelected
end

--------------------------------------------------------------------------------
-- Root GUI
--------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SeiyakuEditorGui"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.new(0, 720, 0, 520)
panel.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = screenGui
addCorner(panel, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 36)
title.Position = UDim2.new(0, 0, 0, 8)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextSize = 20
title.TextColor3 = Color3.fromRGB(235, 235, 240)
title.Text = "SEIYAKU EDITOR  [K]"
title.Parent = panel

local nameBox = Instance.new("TextBox")
nameBox.Position = UDim2.new(0, 16, 0, 48)
nameBox.Size = UDim2.new(1, -32, 0, 32)
nameBox.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
nameBox.BorderSizePixel = 0
nameBox.Font = Enum.Font.Gotham
nameBox.TextSize = 14
nameBox.PlaceholderText = "Hatsu name (optional)"
nameBox.Text = ""
nameBox.TextColor3 = Color3.fromRGB(230, 230, 235)
nameBox.ClearTextOnFocus = false
nameBox.Parent = panel
addCorner(nameBox)

local conditionsScroll = makeScrollColumn(panel, "CONDITIONS", UDim2.new(0, 16, 0, 92), UDim2.new(0.48, -20, 1, -160))
local modifiersScroll = makeScrollColumn(panel, "MODIFIERS", UDim2.new(0.52, 4, 0, 92), UDim2.new(0.48, -20, 1, -160))

-- damage_boost tier picker (visible only when selected)
local tierFrame = Instance.new("Frame")
tierFrame.Name = "TierPicker"
tierFrame.AnchorPoint = Vector2.new(0.5, 0)
tierFrame.Position = UDim2.new(0.75, 0, 1, -118)
tierFrame.Size = UDim2.new(0, 300, 0, 28)
tierFrame.BackgroundTransparency = 1
tierFrame.Visible = false
tierFrame.Parent = panel

local tierLabel = Instance.new("TextLabel")
tierLabel.Size = UDim2.new(0, 120, 1, 0)
tierLabel.BackgroundTransparency = 1
tierLabel.Font = Enum.Font.GothamBold
tierLabel.TextSize = 12
tierLabel.TextXAlignment = Enum.TextXAlignment.Left
tierLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
tierLabel.Text = "Damage tier:"
tierLabel.Parent = tierFrame

local tierButtons = {}
for i = 1, 5 do
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 32, 1, 0)
	btn.Position = UDim2.new(0, 120 + (i - 1) * 36, 0, 0)
	btn.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 12
	btn.TextColor3 = Color3.fromRGB(220, 220, 225)
	btn.Text = tostring(i)
	btn.Parent = tierFrame
	addCorner(btn)
	tierButtons[i] = btn
end

local budgetLabel = Instance.new("TextLabel")
budgetLabel.AnchorPoint = Vector2.new(0.5, 1)
budgetLabel.Position = UDim2.new(0.5, 0, 1, -52)
budgetLabel.Size = UDim2.new(1, -32, 0, 22)
budgetLabel.BackgroundTransparency = 1
budgetLabel.Font = Enum.Font.GothamBold
budgetLabel.TextSize = 15
budgetLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
budgetLabel.Text = "Budget: 0  |  Cost: 0  |  Remaining: 0"
budgetLabel.Parent = panel

local statusLabel = Instance.new("TextLabel")
statusLabel.AnchorPoint = Vector2.new(0.5, 1)
statusLabel.Position = UDim2.new(0.5, 0, 1, -32)
statusLabel.Size = UDim2.new(1, -32, 0, 18)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 13
statusLabel.TextColor3 = Color3.fromRGB(255, 170, 90)
statusLabel.Text = ""
statusLabel.Parent = panel

local submitButton = Instance.new("TextButton")
submitButton.AnchorPoint = Vector2.new(0.5, 1)
submitButton.Position = UDim2.new(0.5, 0, 1, -8)
submitButton.Size = UDim2.new(0, 220, 0, 32)
submitButton.BackgroundColor3 = Color3.fromRGB(50, 110, 70)
submitButton.Font = Enum.Font.GothamBlack
submitButton.TextSize = 14
submitButton.TextColor3 = Color3.fromRGB(240, 240, 245)
submitButton.Text = "SUBMIT CONTRACT"
submitButton.Parent = panel
addCorner(submitButton)

local dormantOverlay = Instance.new("TextLabel")
dormantOverlay.Size = UDim2.fromScale(1, 1)
dormantOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
dormantOverlay.BackgroundTransparency = 0.4
dormantOverlay.Font = Enum.Font.GothamBlack
dormantOverlay.TextSize = 22
dormantOverlay.TextColor3 = Color3.fromRGB(255, 120, 90)
dormantOverlay.Text = "NEN DORMANT\nAwaken before drafting a Seiyaku"
dormantOverlay.Visible = false
dormantOverlay.ZIndex = 10
dormantOverlay.Parent = panel
addCorner(dormantOverlay)

--------------------------------------------------------------------------------
-- Draft logic
--------------------------------------------------------------------------------

local conditionButtons: { [string]: (boolean) -> () } = {}
local modifierButtons: { [string]: (boolean) -> () } = {}

local function countSelected(map: { [string]: boolean }): number
	local count = 0
	for _ in map do
		count += 1
	end
	return count
end

local function buildPayload()
	local conditionIds = {}
	for id, active in selectedConditions do
		if active then
			table.insert(conditionIds, id)
		end
	end

	local modifiers = {}
	for id, active in selectedModifiers do
		if active then
			local entry = { id = id }
			if id == "damage_boost" then
				entry.tier = damageBoostTier
			end
			table.insert(modifiers, entry)
		end
	end

	local payload = {
		conditionIds = conditionIds,
		modifiers = modifiers,
	}
	if nameBox.Text ~= "" then
		payload.name = nameBox.Text
	end
	return payload
end

local function updateTierButtons()
	for i, btn in tierButtons do
		btn.BackgroundColor3 = i == damageBoostTier and Color3.fromRGB(60, 120, 80) or Color3.fromRGB(28, 28, 36)
	end
	local modifierDef = SeiyakuConfig.ModifiersById.damage_boost
	local tierData = modifierDef.tiers[damageBoostTier]
	tierLabel.Text = tierData and `Damage tier: +{math.floor(tierData.value * 100)}% ({tierData.cost} pts)` or "Damage tier:"
end

local function refreshValidation()
	local payload = buildPayload()
	local result = SeiyakuBudget.ValidateBuild(payload)

	local budget = result.budget or 0
	local cost = result.cost or 0
	local remaining = budget - cost

	budgetLabel.Text = `Budget: {budget}  |  Cost: {cost}  |  Remaining: {remaining}`

	if result.ok then
		statusLabel.TextColor3 = Color3.fromRGB(120, 220, 140)
		statusLabel.Text = "Contract valid - ready to submit."
		submitButton.BackgroundColor3 = Color3.fromRGB(50, 110, 70)
	elseif result.reason == "OverBudget" then
		statusLabel.TextColor3 = Color3.fromRGB(255, 120, 90)
		statusLabel.Text = `Over budget by {cost - budget} points.`
		submitButton.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
	else
		statusLabel.TextColor3 = Color3.fromRGB(255, 170, 90)
		statusLabel.Text = result.reason or "Incomplete contract."
		submitButton.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
	end

	tierFrame.Visible = selectedModifiers.damage_boost == true
end

local function hydrateFromBuild(build)
	selectedConditions = {}
	selectedModifiers = {}
	nameBox.Text = build.name or ""

	for _, id in build.conditionIds or {} do
		selectedConditions[id] = true
	end
	for _, selection in build.modifiers or {} do
		selectedModifiers[selection.id] = true
		if selection.id == "damage_boost" and selection.tier then
			damageBoostTier = selection.tier
		end
	end

	for id, setSelected in conditionButtons do
		setSelected(selectedConditions[id] == true)
	end
	for id, setSelected in modifierButtons do
		setSelected(selectedModifiers[id] == true)
	end

	updateTierButtons()
	refreshValidation()
end

--------------------------------------------------------------------------------
-- Populate condition / modifier lists
--------------------------------------------------------------------------------

for _, condition in SeiyakuConfig.Conditions do
	local _, setSelected = makeToggleRow(
		conditionsScroll,
		`{condition.name}  (+{condition.points})`,
		condition.description,
		function(active)
			if active then
				if countSelected(selectedConditions) >= SeiyakuConfig.MAX_CONDITIONS then
					selectedConditions[condition.id] = nil
					setSelected(false)
					statusLabel.Text = `Max {SeiyakuConfig.MAX_CONDITIONS} conditions.`
					return
				end
				selectedConditions[condition.id] = true
			else
				selectedConditions[condition.id] = nil
			end
			refreshValidation()
		end
	)
	conditionButtons[condition.id] = setSelected
end

for _, modifier in SeiyakuConfig.Modifiers do
	local costText = modifier.cost and `{modifier.cost} pts` or "tiered"
	local _, setSelected = makeToggleRow(
		modifiersScroll,
		`{modifier.name}  ({costText})`,
		modifier.description,
		function(active)
			if active then
				if countSelected(selectedModifiers) >= SeiyakuConfig.MAX_MODIFIERS then
					selectedModifiers[modifier.id] = nil
					setSelected(false)
					statusLabel.Text = `Max {SeiyakuConfig.MAX_MODIFIERS} modifiers.`
					return
				end
				selectedModifiers[modifier.id] = true
			else
				selectedModifiers[modifier.id] = nil
			end
			refreshValidation()
		end
	)
	modifierButtons[modifier.id] = setSelected
end

for i, btn in tierButtons do
	btn.Activated:Connect(function()
		damageBoostTier = i
		updateTierButtons()
		refreshValidation()
	end)
end

nameBox:GetPropertyChangedSignal("Text"):Connect(refreshValidation)

submitButton.Activated:Connect(function()
	if submitPending or not nenAwakened then
		return
	end
	local payload = buildPayload()
	local preview = SeiyakuBudget.ValidateBuild(payload)
	if not preview.ok then
		refreshValidation()
		return
	end

	submitPending = true
	submitButton.Text = "SUBMITTING..."
	task.spawn(function()
		local ok, response = pcall(function()
			return submitFunction:InvokeServer(payload)
		end)
		submitPending = false
		submitButton.Text = "SUBMIT CONTRACT"

		if not ok or type(response) ~= "table" then
			statusLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
			statusLabel.Text = "Submission failed - try again."
			return
		end

		if response.success then
			statusLabel.TextColor3 = Color3.fromRGB(120, 220, 140)
			statusLabel.Text = "Contract sealed and stored."
			if type(response.build) == "table" then
				hydrateFromBuild(response.build)
			end
		else
			statusLabel.TextColor3 = Color3.fromRGB(255, 120, 90)
			statusLabel.Text = response.reason or "Server rejected the contract."
		end
	end)
end)

--------------------------------------------------------------------------------
-- Open / close + hydration
--------------------------------------------------------------------------------

local function fetchStoredBuild()
	if not nenAwakened then
		return
	end
	task.spawn(function()
		local ok, response = pcall(function()
			return getBuildFunction:InvokeServer()
		end)
		if ok and type(response) == "table" and type(response.build) == "table" then
			hydrateFromBuild(response.build)
		end
	end)
end

local function toggleEditor()
	screenGui.Enabled = not screenGui.Enabled
	dormantOverlay.Visible = not nenAwakened
	if screenGui.Enabled then
		fetchStoredBuild()
		refreshValidation()
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.K then
		toggleEditor()
	end
end)

snapshotRemote.OnClientEvent:Connect(function(snapshot)
	nenAwakened = snapshot.nenAwakened
	if screenGui.Enabled then
		dormantOverlay.Visible = not nenAwakened
	end
end)

refreshValidation()
