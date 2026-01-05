-- Cards.lua (Uryu_3)
-- Defines Uryu's basic cards

local UryuCards = {}

UryuCards.Definitions = {
	-- Basic cards for 3-star Uryu
	Common = {
		{
			id = "Uryu_Common_Precision",
			name = "Quincy Precision",
			description = "Increases damage by 10%.",
			stackable = true,
			maxLevel = 3,
			module = "DamageBoost",
		},
	},
	Rare = {
		{
			id = "Uryu_Rare_Bow",
			name = "Spiritual Bow",
			description = "Increases attack speed by 8%.",
			stackable = true,
			maxLevel = 3,
			module = "AttackSpeed",
		},
	},
}

return UryuCards
