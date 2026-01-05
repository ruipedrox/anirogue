-- Cards.lua (Naruto)
-- Defines Naruto's cards by rarity and basic effects.
-- Legendary: Every 4 attacks, throw a Rasenshuriken (for now, only override projectile model on those attacks)

local NarutoCards = {}

NarutoCards.Definitions = {
	Epic = {
		{
			id = "Naruto_Epic_WIP",
			name = "Shadow Clone",
			description = "On kill:chance to spawn a clone for 5s. 5% per lvl",
			stackable = true,
			baseChance = 0.05, -- 5% per copy
			duration = 5,
			maxChance = 0.5, -- 50% maximum chance
			maxClones = 3,   -- maximum active clones per player
			image = "rbxassetid://120345525652613",
		}
	},
	-- Stat cards moved to equipment; no Rare/Common stat entries here
}

-- Rarity no longer altera números (apenas visual). Helpers antigos removidos.

return NarutoCards
