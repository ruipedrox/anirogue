local ThornmailArmorCards = {}

ThornmailArmorCards.Definitions = {
	Rare = {
		{
			id = "Equip_Armor_Health",
			name = "+% Max Health (Armor)",
			description = "Increase max health by 10% per armor tier.",
			image = nil,
			source = "Equipment",
			sourceType = "Armor",
			statName = "HealthPercent", -- percent value
			amountPerTier = 10,
			stackable = true,
		},
	},
}

return ThornmailArmorCards