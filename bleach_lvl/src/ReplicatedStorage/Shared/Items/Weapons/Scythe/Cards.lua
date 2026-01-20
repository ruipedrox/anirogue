local ScytheCards = {}

ScytheCards.Definitions = {
	Epic = {
		{
			id = "Equip_Weapon_DamageUp",
			name = "+% Damage (Weapon)",
			description = "Increase damage by 5%.",
			image = nil,
			source = "Equipment",
			sourceType = "Weapon",
			statName = "DamagePercent", -- percent value
			amount = 5, -- flat percent added
			stackable = true,
		},
		{
			id = "Equip_Weapon_AttackSpeed",
			name = "+Attack Speed (Weapon)",
			description = "Increase attack speed by 5%.",
			image = nil,
			source = "Equipment",
			sourceType = "Weapon",
			statName = "AttackSpeed", -- fractional value
			amount = 0.05, -- flat 5% speed
			stackable = true,
		},
	},
}

return ScytheCards