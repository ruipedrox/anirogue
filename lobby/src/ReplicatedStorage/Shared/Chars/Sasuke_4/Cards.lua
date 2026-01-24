-- Cards.lua (Sasuke_4)
-- Defines Sasuke's cards

local SasukeCards = {}

SasukeCards.Definitions = {
	Legendary = {
		{
			id = "Sasuke_Legendary_Sharingan",
			name = "Sharingan",
			description = "The legendary dojutsu of the Uchiha clan. Increases critical hit chance and critical damage. Above 100% crit chance, gain additional crit multipliers.",
			stackable = true,
			maxLevel = 4,
			module = "Sharingan",
		},
	},
}

return SasukeCards
