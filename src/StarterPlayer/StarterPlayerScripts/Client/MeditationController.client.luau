-- MeditationController (client)
-- Presentation + input for Natural Meditation (GDD section 3):
--   1. M toggles the session through the ToggleMeditation RemoteFunction. The
--      server decides whether it starts; this controller only reflects the
--      answer, including rejection reasons (in combat, already awakened, ...).
--   2. While meditating a breathing ring expands and contracts on a
--      TICK_INTERVAL cycle. Press SPACE while the breath is inside the hold
--      zone to land a beat, which fires FocusTick.
--   3. Movement input is sunk at high priority via ContextActionService so the
--      character cannot walk out of the session. This is cosmetic/responsive
--      only - the server independently zeroes WalkSpeed and breaks the session
--      on positional drift, so unsinking the input locally gains nothing.
--
-- The focus bar renders the authoritative meditationProgress carried on
-- StateSnapshot, never a locally accumulated count.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local MEDITATION = Constants.MEDITATION

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local toggleFunction = Remotes.GetFunction("ToggleMeditation")
local focusTickRemote = Remotes.Get("FocusTick")
local snapshotRemote = Remotes.Get("StateSnapshot")

local TOGGLE_ACTION = "RXH_ToggleMeditation"
local BEAT_ACTION = "RXH_MeditationBeat"
local SINK_ACTION = "RXH_MeditationSinkMovement"

-- Fraction of the breath cycle around the peak that counts as a hold.
local HOLD_ZONE = 0.18

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MeditationGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 40
screenGui.Enabled = false
screenGui.Parent = playerGui

local vignette = Instance.new("Frame")
vignette.Size = UDim2.fromScale(1, 1)
vignette.BackgroundColor3 = Color3.fromRGB(4, 8, 16)
vignette.BackgroundTransparency = 0.55
vignette.BorderSizePixel = 0
vignette.Parent = screenGui

local promptLabel = Instance.new("TextLabel")
promptLabel.AnchorPoint = Vector2.new(0.5, 0.5)
promptLabel.Position = UDim2.fromScale(0.5, 0.34)
promptLabel.Size = UDim2.new(0, 620, 0, 40)
promptLabel.BackgroundTransparency = 1
promptLabel.Font = Enum.Font.GothamBold
promptLabel.TextSize = 22
promptLabel.TextColor3 = Color3.fromRGB(180, 225, 255)
promptLabel.Text = "Breathe. Press SPACE on the hold."
promptLabel.Parent = vignette

-- Breathing ring: scales with the breath cycle, brightens inside the hold zone.
local breathRing = Instance.new("Frame")
breathRing.AnchorPoint = Vector2.new(0.5, 0.5)
breathRing.Position = UDim2.fromScale(0.5, 0.52)
breathRing.Size = UDim2.fromOffset(120, 120)
breathRing.BackgroundColor3 = Color3.fromRGB(60, 120, 180)
breathRing.BackgroundTransparency = 0.35
breathRing.BorderSizePixel = 0
breathRing.Parent = vignette

local ringCorner = Instance.new("UICorner")
ringCorner.CornerRadius = UDim.new(1, 0)
ringCorner.Parent = breathRing

local ringStroke = Instance.new("UIStroke")
ringStroke.Thickness = 3
ringStroke.Color = Color3.fromRGB(150, 210, 255)
ringStroke.Transparency = 0.2
ringStroke.Parent = breathRing

local breathLabel = Instance.new("TextLabel")
breathLabel.AnchorPoint = Vector2.new(0.5, 0.5)
breathLabel.Position = UDim2.fromScale(0.5, 0.5)
breathLabel.Size = UDim2.fromScale(1, 1)
breathLabel.BackgroundTransparency = 1
breathLabel.Font = Enum.Font.Gotham
breathLabel.TextSize = 16
breathLabel.TextColor3 = Color3.fromRGB(235, 245, 255)
breathLabel.Text = "IN"
breathLabel.Parent = breathRing

local barBack = Instance.new("Frame")
barBack.AnchorPoint = Vector2.new(0.5, 0.5)
barBack.Position = UDim2.fromScale(0.5, 0.72)
barBack.Size = UDim2.new(0, 440, 0, 22)
barBack.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
barBack.BorderSizePixel = 0
barBack.Parent = vignette

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 6)
barCorner.Parent = barBack

local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Color3.fromRGB(90, 180, 240)
barFill.BorderSizePixel = 0
barFill.Parent = barBack

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 6)
fillCorner.Parent = barFill

local barLabel = Instance.new("TextLabel")
barLabel.AnchorPoint = Vector2.new(0.5, 0.5)
barLabel.Position = UDim2.fromScale(0.5, 0.5)
barLabel.Size = UDim2.fromScale(1, 1)
barLabel.BackgroundTransparency = 1
barLabel.Font = Enum.Font.GothamBold
barLabel.TextSize = 14
barLabel.TextColor3 = Color3.fromRGB(235, 245, 255)
barLabel.Text = "Focus 0 / 100"
barLabel.Parent = barBack

-- Small persistent toast for rejections and interrupts (visible outside the overlay).
local toastLabel = Instance.new("TextLabel")
toastLabel.AnchorPoint = Vector2.new(0.5, 0)
toastLabel.Position = UDim2.fromScale(0.5, 0.12)
toastLabel.Size = UDim2.new(0, 520, 0, 30)
toastLabel.BackgroundTransparency = 1
toastLabel.Font = Enum.Font.GothamBold
toastLabel.TextSize = 18
toastLabel.TextColor3 = Color3.fromRGB(255, 190, 110)
toastLabel.TextStrokeTransparency = 0.4
toastLabel.Text = ""
toastLabel.Visible = false
toastLabel.Parent = screenGui

local toastToken = 0

local function showToast(text: string)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = text
	toastLabel.Visible = true
	-- Kept on its own ScreenGui layer so it survives the overlay being hidden.
	screenGui.Enabled = true
	task.delay(3, function()
		if token == toastToken then
			toastLabel.Visible = false
			toastLabel.Text = ""
		end
	end)
end

--------------------------------------------------------------------------------
-- Session state
--------------------------------------------------------------------------------

local isMeditating = false
local togglePending = false
local sessionStartedAt = 0
local lastBeatAt = 0
local tickInterval = MEDITATION.TICK_INTERVAL
local maxProgress = MEDITATION.MAX_PROGRESS
local displayedProgress = 0

local REJECTION_TEXT = {
	AlreadyAwakened = "Your Nen is already awakened.",
	Incapacitated = "You cannot meditate right now.",
	InCombat = "Too dangerous - you are still in combat.",
	AlreadyFocused = "Your focus is already full. Find a Water Divination cup.",
	NoCharacter = "You need a body to meditate.",
	NoState = "Your character is still loading.",
	AlreadyMeditating = "Already meditating.",
}

--------------------------------------------------------------------------------
-- Movement sinking
--------------------------------------------------------------------------------

local function sinkMovement(): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

local function bindSessionActions()
	ContextActionService:BindActionAtPriority(
		SINK_ACTION,
		sinkMovement,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.PlayerActions.CharacterForward,
		Enum.PlayerActions.CharacterBackward,
		Enum.PlayerActions.CharacterLeft,
		Enum.PlayerActions.CharacterRight,
		Enum.PlayerActions.CharacterJump
	)
end

local function unbindSessionActions()
	ContextActionService:UnbindAction(SINK_ACTION)
	ContextActionService:UnbindAction(BEAT_ACTION)
end

--------------------------------------------------------------------------------
-- Breath cycle
--------------------------------------------------------------------------------

-- Returns 0..1 through the current breath, where 1 is full inhale (the hold).
local function breathPhase(now: number): number
	local elapsed = (now - sessionStartedAt) % tickInterval
	return elapsed / tickInterval
end

-- The hold sits at the top of the inhale, centred on the cycle boundary.
local function isInHoldZone(phase: number): boolean
	return phase >= (1 - HOLD_ZONE) or phase <= HOLD_ZONE
end

local function onBeat(_actionName: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin or not isMeditating then
		return Enum.ContextActionResult.Pass
	end

	local now = os.clock()
	-- Local cadence guard so a mistimed flurry does not spam the remote; the
	-- server applies its own authoritative interval check regardless.
	if (now - lastBeatAt) < (tickInterval * 0.5) then
		return Enum.ContextActionResult.Sink
	end

	if isInHoldZone(breathPhase(now)) then
		lastBeatAt = now
		focusTickRemote:FireServer()
		ringStroke.Color = Color3.fromRGB(140, 255, 180)
		breathRing.BackgroundColor3 = Color3.fromRGB(70, 170, 120)
	else
		ringStroke.Color = Color3.fromRGB(255, 120, 120)
		breathRing.BackgroundColor3 = Color3.fromRGB(120, 60, 70)
	end

	return Enum.ContextActionResult.Sink
end

--------------------------------------------------------------------------------
-- Session open/close
--------------------------------------------------------------------------------

local function openSession(response)
	isMeditating = true
	sessionStartedAt = os.clock()
	-- Seeded to the session start, not 0: the breath cycle opens inside a hold
	-- zone, and the server requires a full TICK_INTERVAL before the first beat
	-- counts. Without this the opening press would be silently rejected.
	lastBeatAt = sessionStartedAt
	tickInterval = type(response.tickInterval) == "number" and response.tickInterval or MEDITATION.TICK_INTERVAL
	maxProgress = type(response.maxProgress) == "number" and response.maxProgress or MEDITATION.MAX_PROGRESS

	screenGui.Enabled = true
	vignette.Visible = true
	promptLabel.Text = "Breathe. Press SPACE on the hold."

	bindSessionActions()
	ContextActionService:BindAction(BEAT_ACTION, onBeat, false, Enum.KeyCode.Space)
end

local function closeSession(message: string?)
	isMeditating = false
	unbindSessionActions()
	vignette.Visible = false
	if message then
		showToast(message)
	else
		screenGui.Enabled = false
	end
end

local function requestToggle()
	if togglePending then
		return
	end
	togglePending = true

	task.spawn(function()
		local ok, response = pcall(function()
			return toggleFunction:InvokeServer()
		end)
		togglePending = false

		if not ok or type(response) ~= "table" then
			closeSession("Meditation unavailable right now.")
			return
		end

		if response.isMeditating then
			openSession(response)
		else
			local reason = response.reason
			if reason then
				closeSession(REJECTION_TEXT[reason] or "You cannot meditate right now.")
			else
				closeSession() -- clean player-requested stop
			end
		end
	end)
end

local function onToggleAction(_actionName: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		requestToggle()
	end
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction(TOGGLE_ACTION, onToggleAction, false, Enum.KeyCode.M)

--------------------------------------------------------------------------------
-- Render loop
--------------------------------------------------------------------------------

RunService.RenderStepped:Connect(function()
	if not isMeditating then
		return
	end

	local phase = breathPhase(os.clock())
	-- Smooth inhale/exhale: a cosine gives an ease at both ends of the breath.
	local eased = (1 - math.cos(phase * math.pi * 2)) * 0.5
	local diameter = 110 + eased * 90
	breathRing.Size = UDim2.fromOffset(diameter, diameter)

	local inHold = isInHoldZone(phase)
	breathLabel.Text = inHold and "HOLD" or (phase < 0.5 and "OUT" or "IN")
	ringStroke.Thickness = inHold and 5 or 3
	ringStroke.Transparency = inHold and 0 or 0.35
end)

--------------------------------------------------------------------------------
-- Authoritative progress + server-side interrupts
--------------------------------------------------------------------------------

snapshotRemote.OnClientEvent:Connect(function(snapshot)
	if type(snapshot) ~= "table" or type(snapshot.meditationProgress) ~= "number" then
		return
	end

	maxProgress = snapshot.maxMeditationProgress or maxProgress
	displayedProgress = snapshot.meditationProgress
	barFill.Size = UDim2.fromScale(math.clamp(displayedProgress / maxProgress, 0, 1), 1)
	barLabel.Text = `Focus {math.floor(displayedProgress)} / {maxProgress}`

	-- The server is the only authority on whether the session is still alive:
	-- damage, movement, downing, and missed beats all end it there first.
	if isMeditating and not snapshot.isMeditating then
		if displayedProgress >= maxProgress then
			closeSession("Focus complete. Seek the Water Divination cup.")
		else
			closeSession("Your focus is broken.")
		end
	end
end)
