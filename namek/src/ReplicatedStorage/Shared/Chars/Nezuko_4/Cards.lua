-- Cards.lua (Nezuko_4)
-- Defines Nezuko's cards grouped by rarity.

local NezukoCards = {}

NezukoCards.Definitions = {
	Epic = {
		{
			id = "Nezuko_SearingFrenzy",
			name = "Searing Frenzy",
			description = "Spin attack that deals AoE damage and applies a burning DoT. Scales per level.",
			stackable = false,
			module = "Nezuko_SearingFrenzy",
			maxLevel = 3,
			image = "rbxassetid://76666775515433", -- optional
		},
	},
}

return NezukoCards
