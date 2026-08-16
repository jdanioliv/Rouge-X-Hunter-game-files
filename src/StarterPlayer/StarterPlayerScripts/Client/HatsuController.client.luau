-- HatsuController (client)
-- Fires HatsuIntent on Q to activate the stored Seiyaku contract, and
-- renders victim-side Hatsu effects (blindness overlay) from server events.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local hatsuIntentRemote = Remotes.Get("HatsuIntent")
local hatsuEffectRemote = Remotes.Get("HatsuEffect")

--------------------------------------------------------------------------------
-- Activation input (Q)
--------------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Q then
		hatsuIntentRemote:FireServer()
	end
end)

--------------------------------------------------------------------------------
-- Blindness overlay (blindness modifier)
--------------------------------------------------------------------------------

local blindnessGui = Instance.new("ScreenGui")
blindnessGui.Name = "HatsuBlindnessGui"
blindnessGui.ResetOnSpawn = false
blindnessGui.DisplayOrder = 40
blindnessGui.IgnoreGuiInset = true
blindnessGui.Enabled = false
blindnessGui.Parent = playerGui

local veil = Instance.new("Frame")
veil.Size = UDim2.fromScale(1, 1)
veil.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
veil.BackgroundTransparency = 0.15
veil.BorderSizePixel = 0
veil.Parent = blindnessGui

-- Aura noise: semi-transparent flickering patches.
local noise = Instance.new("ImageLabel")
noise.Size = UDim2.fromScale(1, 1)
noise.BackgroundTransparency = 1
noise.Image = "rbxassetid://9422529663" -- generic noise texture; replace if desired
noise.ImageTransparency = 0.55
noise.ScaleType = Enum.ScaleType.Tile
noise.TileSize = UDim2.fromOffset(256, 256)
noise.Parent = veil

local blindnessToken = 0

hatsuEffectRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.kind ~= "Blindness" then
		return
	end
	local duration = type(payload.duration) == "number" and payload.duration or 4

	blindnessToken += 1
	local token = blindnessToken
	blindnessGui.Enabled = true

	task.spawn(function()
		local endTime = os.clock() + duration
		while os.clock() < endTime and token == blindnessToken do
			-- Subtle flicker to sell "aura noise".
			noise.ImageTransparency = 0.45 + math.random() * 0.25
			task.wait(0.08)
		end
		if token == blindnessToken then
			blindnessGui.Enabled = false
		end
	end)
end)
