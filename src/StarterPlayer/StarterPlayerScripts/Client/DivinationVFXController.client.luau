-- DivinationVFXController (client)
-- Renders the Water Divination tell (GDD section 3). The server has already
-- rolled and committed the affinity by the time DivinationOutcome arrives; this
-- controller only plays the reveal, so nothing here is gameplay-authoritative.
--
-- One animation per category, matching the canon tells:
--   Enhancement    - the water rises and overflows the rim
--   Transmutation  - the water's colour shifts as its taste changes
--   Conjuration    - impurities materialise and settle in the glass
--   Emission       - the colour flashes rapidly
--   Manipulation   - the leaf drifts across the surface on its own
--   Specialization - an unclassifiable aura pulse
--
-- Prop convention: the tagged "DivinationCup" instance may be a Model
-- containing parts named "Water" and "Leaf". Both are optional - a bare part
-- still gets the reveal UI and a pulse on itself.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local DIVINATION = Constants.DIVINATION

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local outcomeRemote = Remotes.Get("DivinationOutcome")

--------------------------------------------------------------------------------
-- Reveal UI
--------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DivinationGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 45
screenGui.Enabled = false
screenGui.Parent = playerGui

local titleLabel = Instance.new("TextLabel")
titleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
titleLabel.Position = UDim2.fromScale(0.5, 0.24)
titleLabel.Size = UDim2.new(0, 640, 0, 56)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.TextSize = 36
titleLabel.TextColor3 = Color3.fromRGB(240, 245, 255)
titleLabel.TextStrokeTransparency = 0.3
titleLabel.Text = ""
titleLabel.Parent = screenGui

local messageLabel = Instance.new("TextLabel")
messageLabel.AnchorPoint = Vector2.new(0.5, 0.5)
messageLabel.Position = UDim2.fromScale(0.5, 0.32)
messageLabel.Size = UDim2.new(0, 640, 0, 60)
messageLabel.BackgroundTransparency = 1
messageLabel.Font = Enum.Font.Gotham
messageLabel.TextSize = 18
messageLabel.TextColor3 = Color3.fromRGB(215, 225, 240)
messageLabel.TextWrapped = true
messageLabel.TextStrokeTransparency = 0.6
messageLabel.Text = ""
messageLabel.Parent = screenGui

local revealToken = 0

local CATEGORY_COLORS = {
	Enhancement = Color3.fromRGB(255, 120, 90),
	Transmutation = Color3.fromRGB(190, 130, 255),
	Conjuration = Color3.fromRGB(120, 200, 160),
	Emission = Color3.fromRGB(255, 210, 100),
	Manipulation = Color3.fromRGB(120, 180, 255),
	Specialization = Color3.fromRGB(240, 240, 250),
}

local function showReveal(title: string, message: string, color: Color3, duration: number)
	revealToken += 1
	local token = revealToken

	titleLabel.Text = title
	titleLabel.TextColor3 = color
	messageLabel.Text = message
	screenGui.Enabled = true

	task.delay(duration, function()
		if token == revealToken then
			screenGui.Enabled = false
			titleLabel.Text = ""
			messageLabel.Text = ""
		end
	end)
end

--------------------------------------------------------------------------------
-- Prop resolution
--------------------------------------------------------------------------------

type CupParts = {
	root: BasePart?,
	water: BasePart?,
	leaf: BasePart?,
}

local function resolveCup(instance: Instance?): CupParts
	if not instance then
		return { root = nil, water = nil, leaf = nil }
	end

	local root: BasePart? = nil
	if instance:IsA("BasePart") then
		root = instance
	elseif instance:IsA("Model") then
		root = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
	end

	local water = instance:FindFirstChild("Water", true)
	local leaf = instance:FindFirstChild("Leaf", true)

	return {
		root = root,
		water = (water and water:IsA("BasePart")) and water or nil,
		leaf = (leaf and leaf:IsA("BasePart")) and leaf or nil,
	}
end

--------------------------------------------------------------------------------
-- Category animations
--
-- Every animation is purely local and self-cleaning: originals are restored (or
-- clones are used) so a second divination on the same prop starts clean.
--------------------------------------------------------------------------------

local function tween(instance: Instance, info: TweenInfo, goal: { [string]: any })
	local created = TweenService:Create(instance, info, goal)
	created:Play()
	return created
end

-- The water rises past the rim and spills over.
local function animateEnhancement(parts: CupParts, duration: number)
	local water = parts.water or parts.root
	if not water then
		return
	end

	local originalSize = water.Size
	local originalCFrame = water.CFrame
	tween(water, TweenInfo.new(duration * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = originalSize + Vector3.new(0, originalSize.Y * 1.4, 0),
		CFrame = originalCFrame + Vector3.new(0, originalSize.Y * 0.7, 0),
	})

	task.delay(duration * 0.75, function()
		if water.Parent then
			tween(water, TweenInfo.new(duration * 0.25), { Size = originalSize, CFrame = originalCFrame })
		end
	end)
end

-- Colour walks through the spectrum as the taste changes.
local function animateTransmutation(parts: CupParts, duration: number)
	local water = parts.water or parts.root
	if not water then
		return
	end

	local originalColor = water.Color
	task.spawn(function()
		local started = os.clock()
		while os.clock() - started < duration and water.Parent do
			local progress = (os.clock() - started) / duration
			water.Color = Color3.fromHSV(progress % 1, 0.65, 0.95)
			task.wait(0.05)
		end
		if water.Parent then
			water.Color = originalColor
		end
	end)
end

-- Specks of debris materialise inside the glass and settle.
local function animateConjuration(parts: CupParts, duration: number)
	local water = parts.water or parts.root
	if not water then
		return
	end

	for index = 1, 8 do
		local speck = Instance.new("Part")
		speck.Size = Vector3.new(0.08, 0.08, 0.08)
		speck.Shape = Enum.PartType.Ball
		speck.Color = Color3.fromRGB(60, 50, 40)
		speck.Material = Enum.Material.Sand
		speck.Anchored = true
		speck.CanCollide = false
		speck.CanQuery = false
		speck.CanTouch = false
		speck.Transparency = 1
		speck.CFrame = water.CFrame * CFrame.new(math.random(-4, 4) / 10, water.Size.Y * 0.4, math.random(-4, 4) / 10)
		speck.Parent = water

		task.delay(index * 0.08, function()
			if not speck.Parent then
				return
			end
			tween(speck, TweenInfo.new(0.3), { Transparency = 0 })
			tween(speck, TweenInfo.new(duration * 0.7, Enum.EasingStyle.Sine), {
				CFrame = speck.CFrame - Vector3.new(0, water.Size.Y * 0.7, 0),
			})
		end)

		Debris:AddItem(speck, duration)
	end
end

-- Rapid strobing flashes across the surface.
local function animateEmission(parts: CupParts, duration: number)
	local water = parts.water or parts.root
	if not water then
		return
	end

	local originalColor = water.Color
	local light = Instance.new("PointLight")
	light.Color = CATEGORY_COLORS.Emission
	light.Range = 10
	light.Brightness = 0
	light.Parent = water
	Debris:AddItem(light, duration)

	task.spawn(function()
		local started = os.clock()
		while os.clock() - started < duration and water.Parent do
			water.Color = CATEGORY_COLORS.Emission
			light.Brightness = 4
			task.wait(0.06)
			water.Color = originalColor
			light.Brightness = 0.5
			task.wait(0.06)
		end
		if water.Parent then
			water.Color = originalColor
		end
	end)
end

-- The leaf slides across the surface with nothing touching it.
local function animateManipulation(parts: CupParts, duration: number)
	local leaf = parts.leaf
	if not leaf then
		-- No leaf prop: rock the cup itself so the tell still reads.
		local root = parts.water or parts.root
		if root then
			local originalCFrame = root.CFrame
			tween(root, TweenInfo.new(duration * 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 1, true), {
				CFrame = originalCFrame * CFrame.Angles(0, math.rad(25), 0),
			})
		end
		return
	end

	local originalCFrame = leaf.CFrame
	local drift = TweenInfo.new(duration * 0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 1, true)
	tween(leaf, drift, { CFrame = originalCFrame * CFrame.new(0.35, 0, 0.2) * CFrame.Angles(0, math.rad(70), 0) })

	task.delay(duration, function()
		if leaf.Parent then
			leaf.CFrame = originalCFrame
		end
	end)
end

-- Something unclassifiable: a slow aura pulse in every direction.
local function animateSpecialization(parts: CupParts, duration: number)
	local anchor = parts.water or parts.root
	if not anchor then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local light = Instance.new("PointLight")
	light.Color = CATEGORY_COLORS.Specialization
	light.Range = 4
	light.Brightness = 1
	light.Parent = anchor
	Debris:AddItem(light, duration)

	for pulse = 1, 3 do
		task.delay((pulse - 1) * (duration / 3), function()
			if not anchor.Parent then
				return
			end
			local ring = Instance.new("Part")
			ring.Shape = Enum.PartType.Ball
			ring.Size = Vector3.new(0.4, 0.4, 0.4)
			ring.Color = CATEGORY_COLORS.Specialization
			ring.Material = Enum.Material.Neon
			ring.Anchored = true
			ring.CanCollide = false
			ring.CanQuery = false
			ring.CanTouch = false
			ring.Transparency = 0.2
			ring.CFrame = anchor.CFrame
			ring.Parent = anchor
			Debris:AddItem(ring, duration / 3)

			tween(ring, TweenInfo.new(duration / 3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(6, 6, 6),
				Transparency = 1,
			})
			tween(light, TweenInfo.new(duration / 6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), {
				Brightness = 6,
			})
		end)
	end

	Debris:AddItem(attachment, duration)
end

local ANIMATIONS: { [string]: (CupParts, number) -> () } = {
	Enhancement = animateEnhancement,
	Transmutation = animateTransmutation,
	Conjuration = animateConjuration,
	Emission = animateEmission,
	Manipulation = animateManipulation,
	Specialization = animateSpecialization,
}

--------------------------------------------------------------------------------
-- Remote wiring
--------------------------------------------------------------------------------

outcomeRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	if not payload.success then
		-- Rejected attempt (not enough focus, already awakened): message only.
		showReveal("THE WATER IS STILL", payload.message or "Nothing happens.", Color3.fromRGB(255, 180, 110), 3)
		return
	end

	local result = payload.result
	local category = payload.category or (type(result) == "table" and result.category)
	if type(category) ~= "string" then
		return
	end

	local duration = type(payload.revealSeconds) == "number" and payload.revealSeconds or DIVINATION.REVEAL_SECONDS
	local title = DIVINATION.CATEGORY_TITLES[category] or category
	local message = (type(result) == "table" and result.message) or DIVINATION.CATEGORY_TELLS[category] or ""
	local color = CATEGORY_COLORS[category] or Color3.fromRGB(240, 245, 255)

	showReveal(string.upper(title), message, color, duration + 2)

	local animate = ANIMATIONS[category]
	if animate then
		local parts = resolveCup(payload.cup)
		if parts.root or parts.water then
			animate(parts, duration)
		end
	end
end)
