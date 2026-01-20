-- Cards.lua (Ichigo_3)
-- Defines Ichigo's basic cards

local IchigoCards = {}

IchigoCards.Definitions = {
	-- Basic cards for 3-star Ichigo
	Common = {
		{
			id = "Ichigo_Common_Resolve",
			name = "Soul Reaper's Resolve",
			description = "Increases damage by 10%.",
			stackable = true,
			maxLevel = 3,
			module = "DamageBoost",
		},
	},
	Rare = {
		{
			id = "Ichigo_Rare_Zanpakuto",
			name = "Zanpakuto Mastery",
			description = "Increases attack speed by 8%.",
			stackable = true,
			maxLevel = 3,
			module = "AttackSpeed",
		},
	},
}

return IchigoCards
