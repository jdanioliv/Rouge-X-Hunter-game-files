-- AuraVFXController (client)
-- Renders aura envelopes for EVERY character in the game. Driven entirely by
-- the character attributes PlayerStateService mirrors server-side:
--   AuraState (string)  - Ten / Ren / Zetsu / Ken / None
--   AuraColor (Color3)  - the player's RGB aura selection
--   IsDowned  (boolean) - kills the aura while downed
--
-- Ten is a faint envelope, Ren a dense outward surge, Ken a bright shell.
-- Zetsu and None emit nothing (closed aura pores).

local Players = game:GetService("Players")

--------------------------------------------------------------------------------
-- Per-state emitter presets
--------------------------------------------------------------------------------

local STATE_PRESETS = {
	None = { enabled = false },
	Zetsu = { enabled = false },
	Ten = {
		enabled = true,
		rate = 12,
		speed = 0.6,
		lifetime = 0.8,
		size = 1.3,
		transparencyStart = 0.55,
	},
	Ren = {
		enabled = true,
		rate = 50,
		speed = 2.8,
		lifetime = 1.1,
		size = 2.2,
		transparencyStart = 0.15,
	},
	Ken = {
		enabled = true,
		rate = 30,
		speed = 1.2,
		lifetime = 0.9,
		size = 1.8,
		transparencyStart = 0.3,
	},
}

local DEFAULT_COLOR = Color3.fromRGB(130, 200, 255)

--------------------------------------------------------------------------------
-- Emitter management
--------------------------------------------------------------------------------

local emitters: { [Model]: ParticleEmitter } = {}

local function createEmitter(rootPart: BasePart): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "AuraEmitter"
	emitter.Enabled = false
	emitter.LightEmission = 0.8
	emitter.LightInfluence = 0
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 1.5, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-40, 40)
	emitter.Parent = rootPart
	return emitter
end

local function applyAura(character: Model)
	local emitter = emitters[character]
	if not emitter then
		return
	end

	local auraState = character:GetAttribute("AuraState")
	local isDowned = character:GetAttribute("IsDowned") == true
	local preset = STATE_PRESETS[auraState] or STATE_PRESETS.None

	if not preset.enabled or isDowned then
		emitter.Enabled = false
		return
	end

	local color = character:GetAttribute("AuraColor")
	if typeof(color) ~= "Color3" then
		color = DEFAULT_COLOR
	end

	emitter.Color = ColorSequence.new(color)
	emitter.Rate = preset.rate
	emitter.Speed = NumberRange.new(preset.speed * 0.7, preset.speed)
	emitter.Lifetime = NumberRange.new(preset.lifetime * 0.7, preset.lifetime)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, preset.size),
		NumberSequenceKeypoint.new(1, preset.size * 0.3),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, preset.transparencyStart),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Enabled = true
end

local function watchCharacter(character: Model)
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not rootPart then
		return
	end

	emitters[character] = createEmitter(rootPart)

	for _, attribute in { "AuraState", "AuraColor", "IsDowned" } do
		character:GetAttributeChangedSignal(attribute):Connect(function()
			applyAura(character)
		end)
	end
	applyAura(character)
end

local function watchPlayer(player: Player)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		watchCharacter(character)
	end)
	player.CharacterRemoving:Connect(function(character)
		emitters[character] = nil
	end)
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
