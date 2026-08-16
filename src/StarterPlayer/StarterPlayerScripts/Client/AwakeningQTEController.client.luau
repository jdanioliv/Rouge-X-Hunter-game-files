-- AwakeningQTEController (client)
-- Cinematic presentation for the Forced Nen Awakening (GDD section 3):
--   1. AwakeningResult arrives -> full-screen overlay, outcome wheel spins
--      and decelerates over AWAKENING_WHEEL_SECONDS, landing on the rolled
--      outcome, then reveals its title + description.
--   2. If the outcome is Lethal Exhaustion the server fires AwakeningQTE:
--      a fast-twitch aura-balance bar appears. Press SPACE while the marker
--      is inside the target zone the required number of times before the
--      collapse timer expires. The result is reported to the server, which
--      enforces its own deadline (this UI cannot cheat the timing).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local AwakeningOutcomes = require(Shared:WaitForChild("AwakeningOutcomes"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local resultRemote = Remotes.Get("AwakeningResult")
local qteRemote = Remotes.Get("AwakeningQTE")

--------------------------------------------------------------------------------
-- Overlay management
--------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AwakeningGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 50
screenGui.Enabled = false
screenGui.Parent = playerGui

local overlay = Instance.new("Frame")
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.35
overlay.BorderSizePixel = 0
overlay.Parent = screenGui

local wheelLabel = Instance.new("TextLabel")
wheelLabel.AnchorPoint = Vector2.new(0.5, 0.5)
wheelLabel.Position = UDim2.fromScale(0.5, 0.38)
wheelLabel.Size = UDim2.new(0, 600, 0, 60)
wheelLabel.BackgroundTransparency = 1
wheelLabel.Font = Enum.Font.GothamBlack
wheelLabel.TextSize = 38
wheelLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
wheelLabel.TextStrokeTransparency = 0.3
wheelLabel.Text = ""
wheelLabel.Parent = overlay

local descriptionLabel = Instance.new("TextLabel")
descriptionLabel.AnchorPoint = Vector2.new(0.5, 0.5)
descriptionLabel.Position = UDim2.fromScale(0.5, 0.5)
descriptionLabel.Size = UDim2.new(0, 620, 0, 70)
descriptionLabel.BackgroundTransparency = 1
descriptionLabel.Font = Enum.Font.Gotham
descriptionLabel.TextSize = 18
descriptionLabel.TextColor3 = Color3.fromRGB(220, 220, 225)
descriptionLabel.TextWrapped = true
descriptionLabel.Text = ""
descriptionLabel.Parent = overlay

-- QTE bar pieces (hidden until Exhaustion).
local qteFrame = Instance.new("Frame")
qteFrame.AnchorPoint = Vector2.new(0.5, 0.5)
qteFrame.Position = UDim2.fromScale(0.5, 0.65)
qteFrame.Size = UDim2.new(0, 440, 0, 34)
qteFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
qteFrame.BorderSizePixel = 0
qteFrame.Visible = false
qteFrame.Parent = overlay

local qteCorner = Instance.new("UICorner")
qteCorner.CornerRadius = UDim.new(0, 6)
qteCorner.Parent = qteFrame

local ZONE_HALF_WIDTH = 0.12 -- fraction of the bar on each side of center

local targetZone = Instance.new("Frame")
targetZone.AnchorPoint = Vector2.new(0.5, 0)
targetZone.Position = UDim2.fromScale(0.5, 0)
targetZone.Size = UDim2.fromScale(ZONE_HALF_WIDTH * 2, 1)
targetZone.BackgroundColor3 = Color3.fromRGB(70, 160, 90)
targetZone.BackgroundTransparency = 0.4
targetZone.BorderSizePixel = 0
targetZone.Parent = qteFrame

local marker = Instance.new("Frame")
marker.AnchorPoint = Vector2.new(0.5, 0)
marker.Size = UDim2.new(0, 8, 1, 0)
marker.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
marker.BorderSizePixel = 0
marker.Parent = qteFrame

local qteStatusLabel = Instance.new("TextLabel")
qteStatusLabel.AnchorPoint = Vector2.new(0.5, 0.5)
qteStatusLabel.Position = UDim2.fromScale(0.5, 0.74)
qteStatusLabel.Size = UDim2.new(0, 500, 0, 30)
qteStatusLabel.BackgroundTransparency = 1
qteStatusLabel.Font = Enum.Font.GothamBold
qteStatusLabel.TextSize = 18
qteStatusLabel.TextColor3 = Color3.fromRGB(255, 210, 120)
qteStatusLabel.Visible = false
qteStatusLabel.Parent = overlay

local function hideOverlay()
	screenGui.Enabled = false
	qteFrame.Visible = false
	qteStatusLabel.Visible = false
	wheelLabel.Text = ""
	descriptionLabel.Text = ""
end

local function outcomeColor(outcome: string): Color3
	local info = AwakeningOutcomes.Info[outcome]
	if info then
		return Color3.fromRGB(info.color.r, info.color.g, info.color.b)
	end
	return Color3.fromRGB(240, 240, 245)
end

--------------------------------------------------------------------------------
-- Wheel cinematic
--------------------------------------------------------------------------------

local cinematicToken = 0 -- invalidates stale async sequences

local function playWheel(outcome: string)
	cinematicToken += 1
	local token = cinematicToken

	screenGui.Enabled = true
	qteFrame.Visible = false
	qteStatusLabel.Visible = false
	descriptionLabel.Text = "Your aura nodes are being forced open..."
	descriptionLabel.TextColor3 = Color3.fromRGB(220, 220, 225)

	task.spawn(function()
		local duration = Constants.AWAKENING_WHEEL_SECONDS
		local started = os.clock()
		local index = 0

		-- Spin with deceleration: tick delay grows quadratically.
		while os.clock() - started < duration do
			if token ~= cinematicToken then
				return
			end
			index += 1
			local cycled = AwakeningOutcomes.Order[(index - 1) % #AwakeningOutcomes.Order + 1]
			wheelLabel.Text = AwakeningOutcomes.Info[cycled].title
			wheelLabel.TextColor3 = outcomeColor(cycled)

			local progress = (os.clock() - started) / duration
			task.wait(0.05 + progress * progress * 0.35)
		end

		if token ~= cinematicToken then
			return
		end

		-- Land on the actual server-rolled outcome.
		local info = AwakeningOutcomes.Info[outcome]
		wheelLabel.Text = info.title
		wheelLabel.TextColor3 = outcomeColor(outcome)
		descriptionLabel.Text = info.description

		-- Exhaustion hands off to the QTE (server fires it at wheel end);
		-- everything else fades out after a beat.
		if outcome ~= "Exhaustion" then
			task.wait(3)
			if token == cinematicToken then
				hideOverlay()
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Fast-twitch balance QTE
--------------------------------------------------------------------------------

local qteActive = false
local qteHits = 0
local qteRequired = 0
local qteEndsAt = 0
local qteMarkerPosition = 0.5
local qteStartedAt = 0

local function finishQTE(success: boolean)
	if not qteActive then
		return
	end
	qteActive = false
	qteRemote:FireServer({ success = success })

	local token = cinematicToken
	if success then
		qteStatusLabel.Text = "AURA STABILIZED"
		qteStatusLabel.TextColor3 = Color3.fromRGB(120, 230, 140)
		wheelLabel.Text = "TEN ACHIEVED"
		wheelLabel.TextColor3 = Color3.fromRGB(120, 230, 140)
		descriptionLabel.Text = "You wrestle the leaking aura under control. Your Nen awakens."
	else
		qteStatusLabel.Text = "COLLAPSE"
		qteStatusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		wheelLabel.Text = "PHYSICAL COLLAPSE"
		wheelLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		descriptionLabel.Text = "Your life energy tears free. Darkness takes you."
	end
	task.delay(2.5, function()
		if token == cinematicToken then
			hideOverlay()
		end
	end)
end

local function startQTE(duration: number, requiredHits: number)
	qteActive = true
	qteHits = 0
	qteRequired = requiredHits
	qteStartedAt = os.clock()
	qteEndsAt = qteStartedAt + duration

	screenGui.Enabled = true
	qteFrame.Visible = true
	qteStatusLabel.Visible = true
	wheelLabel.Text = "BALANCE YOUR AURA INTO TEN"
	wheelLabel.TextColor3 = Color3.fromRGB(255, 210, 120)
	descriptionLabel.Text = "Press SPACE when the marker is inside the green zone!"
end

RunService.RenderStepped:Connect(function()
	if not qteActive then
		return
	end

	local now = os.clock()
	if now >= qteEndsAt then
		finishQTE(false)
		return
	end

	-- Oscillation speeds up as the collapse timer runs down.
	local elapsed = now - qteStartedAt
	local frequency = 6 + elapsed * 1.5
	qteMarkerPosition = 0.5 + 0.45 * math.sin(elapsed * frequency)
	marker.Position = UDim2.fromScale(qteMarkerPosition, 0)

	local remaining = qteEndsAt - now
	qteStatusLabel.Text = `Hits {qteHits}/{qteRequired}   Collapse in {string.format("%.1f", remaining)}s`
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not qteActive then
		return
	end
	if input.KeyCode ~= Enum.KeyCode.Space then
		return
	end

	if math.abs(qteMarkerPosition - 0.5) <= ZONE_HALF_WIDTH then
		qteHits += 1
		targetZone.BackgroundColor3 = Color3.fromRGB(110, 230, 130)
		task.delay(0.1, function()
			targetZone.BackgroundColor3 = Color3.fromRGB(70, 160, 90)
		end)
		if qteHits >= qteRequired then
			finishQTE(true)
		end
	else
		targetZone.BackgroundColor3 = Color3.fromRGB(200, 80, 80)
		task.delay(0.1, function()
			targetZone.BackgroundColor3 = Color3.fromRGB(70, 160, 90)
		end)
	end
end)

--------------------------------------------------------------------------------
-- Remote wiring
--------------------------------------------------------------------------------

resultRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	if payload.outcome == "Rejected" then
		-- Brief toast, no cinematic.
		cinematicToken += 1
		local token = cinematicToken
		screenGui.Enabled = true
		wheelLabel.Text = payload.reason == "InsufficientFunds" and "NOT ENOUGH MONEY" or "ALREADY AWAKENED"
		wheelLabel.TextColor3 = Color3.fromRGB(255, 170, 90)
		descriptionLabel.Text = ""
		task.delay(2, function()
			if token == cinematicToken then
				hideOverlay()
			end
		end)
		return
	end

	if AwakeningOutcomes.Info[payload.outcome] then
		playWheel(payload.outcome)
	end
end)

qteRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	local duration = type(payload.duration) == "number" and payload.duration or Constants.AWAKENING_QTE_SECONDS
	local requiredHits = type(payload.requiredHits) == "number" and payload.requiredHits
		or Constants.AWAKENING_QTE_REQUIRED_HITS
	startQTE(duration, requiredHits)
end)
