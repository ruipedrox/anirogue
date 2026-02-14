local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Template = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Maps"):WaitForChild("MapTemplate"))

local M = Template.New()
M.Id = "Pirate_Island"
M.DisplayName = "Pirate Island"
M.PlaceId = 0 -- replace with the actual gameplay place id for Green Planet
M.PreviewImage = "rbxassetid://92510023198914"
M.BackgroundImage = "rbxassetid://92510023198914"
M.Levels = {
    { Level = 1, BossImage = "rbxassetid://0", WaveKey = "green_planet_l1" },
    { Level = 2, BossImage = "rbxassetid://0", WaveKey = "green_planet_l2" },
    { Level = 3, BossImage = "rbxassetid://0", WaveKey = "green_planet_l3" },
}

-- Drop/Reward information for Village
-- First clear of any level: 100 Gems and 1000 Gold
-- Repeat clears (any level): 20 Gems and 200 Gold
-- Every run: guaranteed 2x Headband items
M.Drops = {
	FirstClear = { Gems = 100, Gold = 2000, PerLevel = true },
	Repeat = { Gems = 20, Gold = 500 },
	GuaranteedItemsPerRun = {
		{ Id = "xp_core", Quantity = 2 },
	},
}
return M
