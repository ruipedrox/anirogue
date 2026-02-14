-- Cards.lua (Goku_5)
-- Two cards: HealthUp (5% base with rarity scaling) and CritChance (10/15/20%)

local GokuCards = {}

GokuCards.Definitions = {
	Epic = {
		{
			id = "Goku_Epic_SuperWarrior",
			name = "Super Warrior",
			description = "+10% Damage, +10% Attack Speed, +4% Move Speed per level (up to 5 levels).",
			stackable = true,
			maxLevel = 5,
			module = "SuperWarrior", -- module script name under Scripts/Cards
			-- Generic level-tracker metadata for client image selection
			-- folder: RunTrack child folder containing the IntValue "Level"
			-- valueName: the IntValue name (default "Level")
			-- showNextLevel: if true, UI preview shows the next level's image
			levelTracker = {
				folder = "GokuForms",
				valueName = "Level",
				showNextLevel = true,
			},
			-- Imagens por nível (1..5)
			imageLevels = {
				"rbxassetid://123420901878187", -- lvl1
				"rbxassetid://134769709977297",  -- lvl2
				"rbxassetid://87187807222063",  -- lvl3
				"rbxassetid://109230445787601",  -- lvl4
				"rbxassetid://73551236995978",  -- lvl5
			},
			image = "rbxassetid://101798892509110", -- fallback / nível 1
		}
	},
	Legendary = {
		{
			id = "Goku_Legendary_Kamehameha",
			name = "Energy Beam",
			description = "Energy Beam. Per level: -1s CD, +20% size, +10% damage.",
			-- Level scaling parameters
			stackable = true,
			maxLevel = 5,
			image = "rbxassetid://73654392193315",
			module = "Kamehameha",
			baseCooldown = 10, -- seconds at level 1
			cooldownPerLevel = -1, -- per level change
			baseDamagePercent = 10, -- percent of player's damage per tick at level 1
			damagePercentPerLevel = 10, -- +10% per additional level
			sizePerLevel = 0.20, -- +20% per additional level (relative to base)
			duration = 3, -- beam active duration (seconds)
		}
	},
	-- Stat cards moved to equipment; no Rare/Common stat entries here
}

return GokuCards
