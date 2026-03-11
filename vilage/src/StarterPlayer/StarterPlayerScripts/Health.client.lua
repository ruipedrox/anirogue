-- Override Roblox default Health script to disable automatic health regeneration.
-- Leaving this script present prevents the CoreScripts Health script from being inserted.

local Players = game:GetService("Players")

local function onCharacter(char)
    -- Optional: enforce no-regen server-side as well by setting a custom attribute or similar
    -- For now, do nothing; the mere presence of this script disables default regen.
end

local player = Players.LocalPlayer
if player.Character then onCharacter(player.Character) end
player.CharacterAdded:Connect(onCharacter)
