-- Cards.lua (Sasuke_5)
-- Defines Sasuke's cards

local SasukeCards = {}

SasukeCards.Definitions = {
	Legendary = {
		{
			id = "Sasuke_Legendary_Sharingan",
			name = "Sharingan",
			description = "The legendary dojutsu of the Uchiha clan. Increases critical hit chance and critical damage. Above 100% crit chance, gain additional crit multipliers.",
			stackable = true,
			maxLevel = 5,
			module = "Sharingan",
		},
		{
			id = "Sasuke_Legendary_Chidori",
			name = "Chidori",
			description = "Lightning blade technique. Your attacks chain lightning to nearby enemies, dealing electric damage.",
			stackable = true,
			maxLevel = 5,
			module = "Chidori",
		},
	},
}

return SasukeCards
