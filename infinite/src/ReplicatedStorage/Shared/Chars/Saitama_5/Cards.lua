-- Cards.lua (Saitama_5)
-- Defines Saitama's unique cards

local SaitamaCards = {}

SaitamaCards.Definitions = {
	Legendary = {
		{
			id = "Saitama_Legendary_Training",
			name = "Serious Training",
			description = "100 push-ups, 100 sit-ups, 100 squats, and 10km running EVERY DAY!\n\nReach level 10 to unlock true power:\n100x base damage\n300x base health\nUnlock Serious Punch card",
			stackable = true,
			maxLevel = 10,
			image = "rbxassetid://103934000538353",
			module = "SeriousTraining",
		},
		{
			id = "Saitama_Legendary_Punch",
			name = "Serious Punch",
			description = "One serious punch that hits ALL enemies on the map. Deals 1000% of your total damage.\n\nCooldown: 90 seconds\n\n(Requires Serious Training Level 10)",
			stackable = false,
			maxLevel = 1,
			image = "rbxassetid://91904237732238",
			module = "SeriousPunch",
			-- Requires Serious Training level 10 to unlock
				requiresUnlock = true,
				unlockAttribute = "SeriousTrainingLevel",
				unlockMinValue = 10,
			unique = true, -- prevent re-offer after chosen once
		},
	},
}

return SaitamaCards
