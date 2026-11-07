-- AnimationController (client)
-- Plays combat animations for every character in the game:
--   - the LOCAL player's attack/parry/block animations play instantly on
--     input (client-side prediction, mirroring CombatController's intents)
--   - OTHER players' animations play from server CombatBroadcast events
--
-- Replace the "rbxassetid://0" placeholders with your real animation asset
-- ids. Entries left at 0 are skipped safely (no errors, just no animation).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local localPlayer = Players.LocalPlayer
local broadcastRemote = Remotes.Get("CombatBroadcast")

--------------------------------------------------------------------------------
-- Animation configuration (fill in real asset ids)
--------------------------------------------------------------------------------

local ANIMATION_CONFIG = {
	-- Weighted attack swing pool: heavier weights play more often.
	AttackSwings = {
		{ id = "rbxassetid://0", weight = 0.4 },
		{ id = "rbxassetid://0", weight = 0.4 },
		{ id = "rbxassetid://0", weight = 0.2 },
	},
	Parry = "rbxassetid://0",
	BlockIdle = "rbxassetid://0", -- looped while blocking
	Stagger = "rbxassetid://0", -- got parried / frame-trapped
	GuardBreak = "rbxassetid://0",
	Downed = "rbxassetid://0",
	Gripping = "rbxassetid://0", -- throat slash for now, about 2.5-3 s
}

local PLACEHOLDER = "rbxassetid://0"

--------------------------------------------------------------------------------
-- Track cache per character
--------------------------------------------------------------------------------

-- [character] = { swings = {AnimationTrack}, swingWeights = {number},
--                 named = { [name] = AnimationTrack } }
local trackCache = {}

local function loadTrack(animator: Animator, id: string, looped: boolean): AnimationTrack?
	if id == PLACEHOLDER or id == "" then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok then
		return nil
	end
	track.Looped = looped
	return track
end

local function buildTracks(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local cache = { swings = {}, swingWeights = {}, named = {} }
	for _, entry in ANIMATION_CONFIG.AttackSwings do
		local track = loadTrack(animator, entry.id, false)
		if track then
			table.insert(cache.swings, track)
			table.insert(cache.swingWeights, entry.weight)
		end
	end
	for _, name in { "Parry", "Stagger", "GuardBreak", "Downed", "Gripping" } do
		cache.named[name] = loadTrack(animator, ANIMATION_CONFIG[name], false)
	end
	cache.named.BlockIdle = loadTrack(animator, ANIMATION_CONFIG.BlockIdle, true)

	trackCache[character] = cache
end

local function watchPlayer(player: Player)
	if player.Character then
		task.spawn(buildTracks, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		buildTracks(character)
	end)
	player.CharacterRemoving:Connect(function(character)
		trackCache[character] = nil
	end)
end

--------------------------------------------------------------------------------
-- Playback
--------------------------------------------------------------------------------

local rng = Random.new()

local function pickWeighted(tracks, weights): AnimationTrack?
	if #tracks == 0 then
		return nil
	end
	local total = 0
	for _, weight in weights do
		total += weight
	end
	local pick = rng:NextNumber(0, total)
	local accumulated = 0
	for index, weight in weights do
		accumulated += weight
		if pick <= accumulated then
			return tracks[index]
		end
	end
	return tracks[#tracks]
end

local function playAttack(character: Model)
	local cache = trackCache[character]
	if not cache then
		return
	end
	local track = pickWeighted(cache.swings, cache.swingWeights)
	if track then
		track:Play(0.05)
	end
end

local function playNamed(character: Model, name: string)
	local cache = trackCache[character]
	local track = cache and cache.named[name]
	if track then
		track:Play(0.1)
	end
end

local function stopNamed(character: Model, name: string)
	local cache = trackCache[character]
	local track = cache and cache.named[name]
	if track and track.IsPlaying then
		track:Stop(0.15)
	end
end

--------------------------------------------------------------------------------
-- Local prediction (mirrors CombatController's inputs)
--------------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	local character = localPlayer.Character
	if not character then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		playAttack(character)
	elseif input.KeyCode == Enum.KeyCode.F then
		playNamed(character, "Parry")
	end
end)

--------------------------------------------------------------------------------
-- Broadcast playback for other players
--------------------------------------------------------------------------------

local BROADCAST_HANDLERS = {
	Attack = playAttack,
	Parry = function(character)
		playNamed(character, "Parry")
	end,
	Stagger = function(character)
		playNamed(character, "Stagger")
	end,
	GuardBreak = function(character)
		playNamed(character, "GuardBreak")
	end,
	Downed = function(character)
		playNamed(character, "Downed")
	end,
	Recovered = function(character)
		stopNamed(character, "Downed")
	end,
	BlockStart = function(character)
		playNamed(character, "BlockIdle")
	end,
	BlockEnd = function(character)
		stopNamed(character, "BlockIdle")
	end,
	GripStart = function(character)
		playNamed(character, "Gripping")
	end,
	GripEnd = function(character)
		stopNamed(character, "Gripping")
	end,
}

broadcastRemote.OnClientEvent:Connect(function(event)
	if type(event) ~= "table" then
		return
	end
	-- The local player's attack and parry were already predicted. Everything else
	-- is decided by the server, including a block, which starts only after F has
	-- been held, so it still applies to us.
	local isLocal = event.userId == localPlayer.UserId
	local predicted = event.kind == "Attack" or event.kind == "Parry"
	if isLocal and predicted then
		return
	end

	local player = Players:GetPlayerByUserId(event.userId)
	local character = player and player.Character
	local handler = BROADCAST_HANDLERS[event.kind]
	if character and handler then
		handler(character)
	end
end)

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

Players.PlayerAdded:Connect(watchPlayer)
for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
