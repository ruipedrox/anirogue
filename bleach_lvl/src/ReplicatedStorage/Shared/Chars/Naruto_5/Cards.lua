-- Cards.lua (naruto_5)
-- Derived from Naruto, renamed to naruto_5 per request.

local NarutoCards = {}

NarutoCards.Definitions = {
	Legendary = {
		{
			id = "Naruto_Legendary_RasenShuriken",
			name = "Wind Shuriken",
			description = "Periodically casts wind shurikens. Each level: +1 shuriken and +40% damage.",
			unique = false,
			-- Now stackable: levels increase count and damage
			stackable = true,
			maxLevel = 5,
			image = "rbxassetid://73093466503989",
			module = "RasenShuriken",
			-- Ability stats
			cooldown = 5,          -- seconds between casts
			radius = 16,            -- explosion radius (studs)
			contactRadius = 6,   -- projectile proximity hitbox (studs)
		},
	},
	Epic = {
		{
			id = "Naruto_Epic_WIP",
			name = "Shadow Clone",
			description = "On kill:chance to spawn a clone for 5s. 10% per lvl",
			stackable = true,
			baseChance = 0.1, -- 10% per copy
			duration = 5,
			maxChance = 0.5, -- 50% maximum chance
			maxClones = 5,   -- maximum active clones per player
			image = "rbxassetid://120345525652613", -- shadow clone definitive art
			module = "ShadowClone",
		}
	},
}

-- Rarity não altera stats (apenas visual). Helpers antigos removidos.

return NarutoCards
