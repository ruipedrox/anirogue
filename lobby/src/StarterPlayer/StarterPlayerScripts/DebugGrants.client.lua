-- DebugGrants.client.lua
-- K: +10000 Gems, L: +10000 Coins (Studio-only server handlers)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AddGems = Remotes:WaitForChild("DebugAddGems")
local AddCoins = Remotes:WaitForChild("DebugAddCoins")

local DEFAULT_AMOUNT = 10000

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.K then
		AddGems:FireServer(DEFAULT_AMOUNT)
	elseif input.KeyCode == Enum.KeyCode.L then
		AddCoins:FireServer(DEFAULT_AMOUNT)
	end
end)
