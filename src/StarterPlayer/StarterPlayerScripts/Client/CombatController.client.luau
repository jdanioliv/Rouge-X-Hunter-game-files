-- CombatController (client)
-- Captures combat input and sends *intents* to the server. The server owns
-- all outcomes; this script never computes damage or hit results.
--
-- Keybinds (foundation testing set, see README):
--   LMB          attack
--   F (tap)      parry
--   F (hold)     parry, then block for as long as it is held
--   B            Grip a downed player right next to you
--   T / G / Z / C / X   aura: Ten / Ren / Zetsu / Ken / None
--   Ctrl + Mouse Wheel  adjust Ryu offense/defense ratio

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local combatIntentRemote = Remotes.Get("CombatIntent")
local snapshotRemote = Remotes.Get("StateSnapshot")
local auraIntentRemote = Remotes.Get("AuraIntent")

local RYU_STEP = 0.1
local ryuOffense = 0.5

local AURA_KEYBINDS = {
	[Enum.KeyCode.T] = "Ten",
	[Enum.KeyCode.G] = "Ren",
	[Enum.KeyCode.Z] = "Zetsu",
	[Enum.KeyCode.C] = "Ken",
	[Enum.KeyCode.X] = "None",
}

local function sendCombat(action: string)
	combatIntentRemote:FireServer({ action = action })
end

local BLOCK_RESEND_SECONDS = 0.25

local defendPressId = 0 -- invalidates the hold timer of an earlier press
local blockSent = false
local lastBlockSentAt = 0

local function sendBlockStart()
	blockSent = true
	lastBlockSentAt = os.clock()
	sendCombat("BlockStart")
end

local function beginDefend()
	defendPressId += 1
	local pressId = defendPressId
	sendCombat("Parry")
	task.delay(Constants.BLOCK_HOLD_DELAY, function()
		if pressId == defendPressId then
			sendBlockStart()
		end
	end)
end

local function endDefend()
	defendPressId += 1
	if blockSent then
		blockSent = false
		sendCombat("BlockEnd")
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		sendCombat("Attack")
	elseif input.KeyCode == Enum.KeyCode.F then
		beginDefend()
	elseif input.KeyCode == Enum.KeyCode.B then
		sendCombat("Grip")
	elseif AURA_KEYBINDS[input.KeyCode] then
		auraIntentRemote:FireServer({ auraState = AURA_KEYBINDS[input.KeyCode] })
	end
end)

UserInputService.InputEnded:Connect(function(input, _gameProcessed)
	-- Always release block, even if focus moved to a UI element mid-hold.
	if input.KeyCode == Enum.KeyCode.F then
		endDefend()
	end
end)

-- The server drops a block on guard break, downing and respawn. If F is still held
-- once blocking is possible again, ask for it back rather than leave the player
-- holding the key with no guard up.
snapshotRemote.OnClientEvent:Connect(function(snapshot)
	if type(snapshot) ~= "table" then
		return
	end
	-- The server may refuse a Ryu change, as it does during a Grip, so its value wins.
	if type(snapshot.ryuOffense) == "number" then
		ryuOffense = snapshot.ryuOffense
	end
	if not blockSent then
		return
	end
	if snapshot.isBlocking or snapshot.isGuardBroken or snapshot.isDowned then
		return
	end
	if os.clock() - lastBlockSentAt >= BLOCK_RESEND_SECONDS then
		sendBlockStart()
	end
end)

-- Ryu real-time aura allocation: Ctrl + scroll shifts offense/defense split.
UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseWheel then
		return
	end
	local ctrlHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	if not ctrlHeld then
		return
	end

	local direction = input.Position.Z -- +1 scroll up, -1 scroll down
	ryuOffense = math.clamp(ryuOffense + direction * RYU_STEP, 0, 1)
	auraIntentRemote:FireServer({ ryuOffense = ryuOffense })
end)
