-- Cards.lua (Goku_4)
-- Identical to Goku_5 but without Legendary cards

local GokuCards = {}

GokuCards.Definitions = {
	Epic = {
		{
			id = "Goku_Epic_SuperWarrior",
			name = "Super Warrior",
			description = "+10% Damage, +10% Attack Speed, +4% Move Speed per level (up to 3 levels).",
			stackable = true,
			maxLevel = 3,
			-- Imagens apenas até o nível 3 neste estágio de evolução
			imageLevels = {
				"rbxassetid://123420901878187", -- lvl1
				"rbxassetid://134769709977297",  -- lvl2
				"rbxassetid://87187807222063",  -- lvl3
			},
			image = "rbxassetid://123420901878187", -- fallback
		}
	},
	-- No Legendary group for Goku_4
	-- Stat cards moved to equipment; no Rare/Common stat entries here
}

return GokuCards
