local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Template = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Maps"):WaitForChild("MapTemplate"))

local M = Template.New()
M.Id = "Green_Planet"
M.DisplayName = "Green Planet"
M.SortOrder = 2
M.PlaceId = 0 -- replace with the actual gameplay place id for Green Planet
M.PreviewImage = "rbxassetid://0"
M.BackgroundImage = "rbxassetid://0"
M.Levels = {
    { Level = 1, BossImage = "rbxassetid://0", WaveKey = "green_planet_l1" },
    { Level = 2, BossImage = "rbxassetid://0", WaveKey = "green_planet_l2" },
    { Level = 3, BossImage = "rbxassetid://0", WaveKey = "green_planet_l3" },
}

return M
