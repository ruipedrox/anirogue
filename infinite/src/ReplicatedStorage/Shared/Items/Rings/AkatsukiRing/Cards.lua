local AkatsukiRingCards = {}

AkatsukiRingCards.Definitions = {
	Epic = {
		{
			id = "Equip_Ring_CritChance",
			name = "+Crit Chance (Ring)",
			description = "Increase crit chance by 5% per ring tier.",
			image = nil,
			source = "Equipment",
			sourceType = "Ring",
			statName = "CritChance", -- fractional value
			amountPerTier = 0.05,
			stackable = true,
		},
		{
			id = "Equip_Ring_Lifesteal",
			name = "+Lifesteal (Ring)",
			description = "Increase lifesteal by 2% per ring tier.",
			image = nil,
			source = "Equipment",
			sourceType = "Ring",
			statName = "Lifesteal", -- fractional value
			amountPerTier = 0.02,
			stackable = true,
		},
	},
}

return AkatsukiRingCards