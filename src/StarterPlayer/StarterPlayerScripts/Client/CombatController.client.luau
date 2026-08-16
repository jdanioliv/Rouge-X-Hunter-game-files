-- CombatController (client)
-- Captures combat input and sends *intents* to the server. The server owns
-- all outcomes; this script never computes damage or hit results.
--
-- Keybinds (foundation testing set, see README):
--   LMB          attack
--   F            parry attempt
--   RMB (hold)   block
--   T / G / Z / C / X   aura: Ten / Ren / Zetsu / Ken / None
--   Ctrl + Mouse Wheel  adjust Ryu offense/defense ratio

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local combatIntentRemote = Remotes.Get("CombatIntent")
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

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		sendCombat("Attack")
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		sendCombat("BlockStart")
	elseif input.KeyCode == Enum.KeyCode.F then
		sendCombat("Parry")
	elseif AURA_KEYBINDS[input.KeyCode] then
		auraIntentRemote:FireServer({ auraState = AURA_KEYBINDS[input.KeyCode] })
	end
end)

UserInputService.InputEnded:Connect(function(input, _gameProcessed)
	-- Always release block, even if focus moved to a UI element mid-hold.
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		sendCombat("BlockEnd")
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
