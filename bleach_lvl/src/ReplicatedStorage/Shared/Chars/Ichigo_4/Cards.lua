-- Cards.lua (Ichigo_4)
-- Defines Ichigo's intermediate cards

local IchigoCards = {}

IchigoCards.Definitions = {
	Epic = {
		{
			id = "Ichigo_Epic_Bankai",
			name = "Bankai: Tensa Zangetsu",
			description = "Unlock Bankai transformation. Greatly increases damage, attack speed and crit damage.\n\nLv1: +30% damage, +20% attack speed, +25% crit damage\nLv2: +45% damage, +30% attack speed, +50% crit damage\nLv3: +60% damage, +40% attack speed, +75% crit damage",
			stackable = true,
			maxLevel = 3,
			module = "Bankai",
		},
	},
}

return IchigoCards
