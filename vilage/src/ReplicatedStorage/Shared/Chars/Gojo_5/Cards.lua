-- Cards.lua (Gojo_5)
-- Defines Gojo's signature cards from Jujutsu Kaisen

local GojoCards = {}

GojoCards.Definitions = {
	-- Legendary cards - Gojo's signature techniques
	Legendary = {
		{
			id = "Gojo_Infinity",
			name = "Infinity",
			description = "Slows enemies based on proximity. Closer enemies are slowed more. Lvl1: 10%-40% | Lvl5: 20%-80%",
			stackable = false,
			maxLevel = 5,
			image = "rbxassetid://138257935037509",
			module = "Infinity",
		},
		{
			id = "Gojo_RedShot",
			name = "Reversal: Red",
			description = "Fire repulsive force projectiles that damage and push enemies away.",
			stackable = false,
			maxLevel = 5,
			image = "rbxassetid://126447845624162",
			module = "RedShot",
		},
		{
			id = "Gojo_BlueShot",
			name = "Lapse: Blue",
			description = "Fire attractive force projectiles that damage and pull enemies inward.",
			stackable = false,
			maxLevel = 5,
			image = "rbxassetid://88936494266860",
			module = "BlueShot",
		},
	},
	-- Mythic card - Ultimate technique
	Mythic = {
		{
			id = "Gojo_PurpleShot",
			name = "Hollow Purple",
			description = "The imaginary mass. Devastating purple projectile that combines Red and Blue. Requires both at max level. Replaces Red and Blue.",
			stackable = false,
			maxLevel = 1,
			image = "rbxassetid://88996889608340",
			module = "PurpleShot",
			requiredCards = {
				{ cardId = "Gojo_RedShot", minLevel = 1 },
				{ cardId = "Gojo_BlueShot", minLevel = 1 },
			},
		},
	},
}

return GojoCards
