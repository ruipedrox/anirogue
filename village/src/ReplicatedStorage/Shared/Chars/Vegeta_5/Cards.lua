-- Cards.lua (Vegeta_5)
local Cards = {}

-- Minimal Cards definition placeholder for Vegeta_5
Cards.Definitions = {
    Legendary = {
        {
            id = "Vegeta_PrideBarrage",
            name = "Pride Barrage",
            module = "Vegeta_PrideBarrage",
            stackable = false,
			image = "rbxassetid://116080324099377",
            maxLevel = 5,
            description = "Target an enemy and bombard them with ki for 2s.",
        },
        {
            id = "Vegeta_PurpleBeam",
            name = "Purple Beam",
            module = "PurpleBeam",
            stackable = false,
			image = "rbxassetid://74051328527831",
            maxLevel = 5,
            description = "Charge and fire a concentrated beam—targets enemy with highest HP.",
        },
    },
}

return Cards
