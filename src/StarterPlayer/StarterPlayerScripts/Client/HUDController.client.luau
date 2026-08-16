-- HUDController (client)
-- Builds a lightweight programmatic HUD and renders the server's throttled
-- state snapshots: HP / Posture / Aura bars, combat tag countdown, aura state,
-- Ryu ratio, soul nodes, Nen affinity, and combat feedback flashes.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local snapshotRemote = Remotes.Get("StateSnapshot")
local feedbackRemote = Remotes.Get("CombatFeedback")
local affinityRemote = Remotes.Get("AffinityAssigned")

--------------------------------------------------------------------------------
-- UI construction helpers
--------------------------------------------------------------------------------

local function makeBar(parent: Instance, order: number, label: string, fillColor: Color3)
	local container = Instance.new("Frame")
	container.Name = label .. "Bar"
	container.Size = UDim2.new(1, 0, 0, 18)
	container.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	container.BorderSizePixel = 0
	container.LayoutOrder = order
	container.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = container

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	fill.Parent = container

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill

	local text = Instance.new("TextLabel")
	text.Name = "Label"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextSize = 12
	text.TextColor3 = Color3.fromRGB(240, 240, 240)
	text.TextStrokeTransparency = 0.5
	text.Text = label
	text.Parent = container

	return container, fill, text
end

local function makeLabel(parent: Instance, order: number, name: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.new(1, 0, 0, 16)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(220, 220, 220)
	label.TextStrokeTransparency = 0.6
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.LayoutOrder = order
	label.Text = ""
	label.Parent = parent
	return label
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RougeXHunterHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Bottom-left stat panel
local panel = Instance.new("Frame")
panel.Name = "StatPanel"
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 16, 1, -16)
panel.Size = UDim2.new(0, 260, 0, 150)
panel.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
panel.BackgroundTransparency = 0.35
panel.BorderSizePixel = 0
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = panel

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 8)
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 10)
padding.Parent = panel

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 5)
layout.Parent = panel

local _, hpFill, hpText = makeBar(panel, 1, "HP", Color3.fromRGB(200, 60, 60))
local _, postureFill, postureText = makeBar(panel, 2, "Posture", Color3.fromRGB(220, 180, 60))
local _, auraFill, auraText = makeBar(panel, 3, "Aura", Color3.fromRGB(80, 170, 230))

local statusLabel = makeLabel(panel, 4, "StatusLabel") -- aura state + ryu ratio
local soulLabel = makeLabel(panel, 5, "SoulLabel") -- soul nodes + memory slots
local affinityLabel = makeLabel(panel, 6, "AffinityLabel")

-- Top-center combat tag countdown
local combatTagLabel = Instance.new("TextLabel")
combatTagLabel.Name = "CombatTag"
combatTagLabel.AnchorPoint = Vector2.new(0.5, 0)
combatTagLabel.Position = UDim2.new(0.5, 0, 0, 12)
combatTagLabel.Size = UDim2.new(0, 320, 0, 26)
combatTagLabel.BackgroundTransparency = 1
combatTagLabel.Font = Enum.Font.GothamBlack
combatTagLabel.TextSize = 20
combatTagLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
combatTagLabel.TextStrokeTransparency = 0.4
combatTagLabel.Visible = false
combatTagLabel.Parent = screenGui

-- Center feedback flash ("PARRY!", "GUARD BREAK", ...)
local flashLabel = Instance.new("TextLabel")
flashLabel.Name = "FeedbackFlash"
flashLabel.AnchorPoint = Vector2.new(0.5, 0.5)
flashLabel.Position = UDim2.new(0.5, 0, 0.35, 0)
flashLabel.Size = UDim2.new(0, 400, 0, 40)
flashLabel.BackgroundTransparency = 1
flashLabel.Font = Enum.Font.GothamBlack
flashLabel.TextSize = 30
flashLabel.TextStrokeTransparency = 0.3
flashLabel.TextTransparency = 1
flashLabel.Text = ""
flashLabel.Parent = screenGui

--------------------------------------------------------------------------------
-- Snapshot rendering
--------------------------------------------------------------------------------

-- Track the combat tag as an end-time so the countdown ticks smoothly
-- between 10 Hz snapshots.
local combatTagEndsAt = 0

snapshotRemote.OnClientEvent:Connect(function(snapshot)
	hpFill.Size = UDim2.fromScale(math.clamp(snapshot.hp / snapshot.maxHp, 0, 1), 1)
	hpText.Text = `HP  {math.floor(snapshot.hp)} / {snapshot.maxHp}`

	postureFill.Size = UDim2.fromScale(math.clamp(snapshot.posture / snapshot.maxPosture, 0, 1), 1)
	postureText.Text = snapshot.isGuardBroken and "GUARD BROKEN" or `Posture  {math.floor(snapshot.posture)}`

	auraFill.Size = UDim2.fromScale(math.clamp(snapshot.aura / snapshot.maxAura, 0, 1), 1)
	auraText.Text = `Aura  {math.floor(snapshot.aura)}`

	if snapshot.nenAwakened then
		local offensePercent = math.floor(snapshot.ryuOffense * 100 + 0.5)
		statusLabel.Text = `Aura State: {snapshot.auraState}   Ryu {offensePercent}/{100 - offensePercent}`
	else
		statusLabel.Text = "Nen: DORMANT - seek a Forced Awakening"
	end

	soulLabel.Text = `Soul Nodes: {snapshot.soulNodes}   Money: {snapshot.money}   Memory: {snapshot.memorySlotsUsed}/{snapshot.memorySlotCap}`

	combatTagEndsAt = os.clock() + snapshot.combatTagRemaining
end)

RunService.RenderStepped:Connect(function()
	local remaining = combatTagEndsAt - os.clock()
	if remaining > 0 then
		combatTagLabel.Visible = true
		combatTagLabel.Text = `IN COMBAT  {string.format("%.1f", remaining)}s`
	else
		combatTagLabel.Visible = false
	end
end)

--------------------------------------------------------------------------------
-- Feedback flashes
--------------------------------------------------------------------------------

local FEEDBACK_STYLES = {
	ParrySuccess = { text = "PARRY!", color = Color3.fromRGB(120, 220, 255) },
	GotParried = { text = "PARRIED!", color = Color3.fromRGB(255, 120, 120) },
	GuardBreak = { text = "GUARD BREAK", color = Color3.fromRGB(255, 180, 60) },
	Blocked = { text = "BLOCKED", color = Color3.fromRGB(200, 200, 200) },
	Downed = { text = "DOWNED", color = Color3.fromRGB(255, 60, 60) },
	SoulNodeLost = { text = "SOUL NODE DESTROYED", color = Color3.fromRGB(180, 60, 255) },
	Grip = { text = "GRIP EXECUTED", color = Color3.fromRGB(255, 60, 120) },
}

local flashTween: Tween? = nil

feedbackRemote.OnClientEvent:Connect(function(feedback)
	if type(feedback) ~= "table" then
		return
	end
	local style = FEEDBACK_STYLES[feedback.kind]
	if not style then
		return -- Hit/TookHit are intentionally silent for now (damage numbers later)
	end

	flashLabel.Text = style.text
	flashLabel.TextColor3 = style.color
	flashLabel.TextTransparency = 0

	if flashTween then
		flashTween:Cancel()
	end
	flashTween = TweenService:Create(
		flashLabel,
		TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1 }
	)
	flashTween:Play()
end)

--------------------------------------------------------------------------------
-- Affinity display
--------------------------------------------------------------------------------

affinityRemote.OnClientEvent:Connect(function(affinity)
	if type(affinity) ~= "table" or not affinity.primary then
		affinityLabel.Text = "Affinity: None (Dormant)"
		return
	end
	if affinity.secondary then
		affinityLabel.Text = `Affinity: {affinity.primary} / {affinity.secondary} (In-Between)`
	else
		affinityLabel.Text = `Affinity: {affinity.primary}`
	end
end)
