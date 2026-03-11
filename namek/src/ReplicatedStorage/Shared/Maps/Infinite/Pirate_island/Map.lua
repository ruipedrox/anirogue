local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Template = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Maps"):WaitForChild("MapTemplate"))

local M = Template.New()
M.Id = "Pirate_Island"
M.DisplayName = "Pirate Island"
M.PlaceId = 92510023198914 -- replace with the actual gameplay place id for Green Planet
M.PreviewImage = "rbxassetid://92780265236521"
M.BackgroundImage = "rbxassetid://92780265236521"
M.Levels = {
	-- Infinite-mode WaveKey: use a map-specific key so Infinite runner resolves the correct config
	{ Level = 1, BossImage = "rbxassetid://0", WaveKey = "pirate_island_l1" },
}

M.Drops = {
	-- First clear rewards (apply per-level when PerLevel=true)
	-- Infinite-mode milestone rewards: granted every 10 waves by server logic.
	-- This section documents the possible milestone rewards and is used by UIs to display expectations.
	Milestone = {
		Every = 10, -- rewards awarded on waves 10,20,30,...
		-- Base reward formula (server uses tier = wave/10):
		-- Gold = 50 + (tier * 30), Gems = 2 + floor(tier * 0.5)
		BaseGold = 50,
		GoldPerTier = 30,
		BaseGems = 5,
		GemsPerTierFraction = 0.5,
		-- Character XP roll: represent as separate entries so UI can show distinct icons
		CharacterXP = {
			{ Id = "xp3", Chance = 0.7 },
			{ Id = "xp4", Chance = 0.3 },
		},
		-- Independent evolve item drops (server constants)
		EvolveShard = { Chance = 0.40, Min = 2, Max = 4 },
		EvolveCore = { Chance = 0.40, Min = 1, Max = 2 },
	},
	-- No FirstClear/Repeat or guaranteed headband for Infinite maps
	GuaranteedItemsPerRun = {},
}
return M
