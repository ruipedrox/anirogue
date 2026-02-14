-- Cards.lua (Sakura_4)
-- Defines Sakura's healing card

local SakuraCards = {}

SakuraCards.Definitions = {
	Epic = {
		{
			id = "Sakura_Heal",
			name = "Medical Ninjutsu",
			description = "Heal every 15 seconds. Heal scales with your damage. (Lv1: 5%, Lv2: 10%, Lv3: 15%)",
			module = "MedicalNinjutsu", -- Points to Cards/MedicalNinjutsu.lua
			stackable = true,
			interval = 15, -- seconds between heals
			-- Heal amount = BaseDamage * healMultiplier * level
			healMultiplier = {
				[1] = 0.05,  -- Level 1: 5% of BaseDamage
				[2] = 0.10,  -- Level 2: 10% of BaseDamage
				[3] = 0.15,  -- Level 3: 15% of BaseDamage
			},
			maxLevel = 3,
			image = "rbxassetid://0", -- Substitui com ID do ícone
		}
	},
}

return SakuraCards
