local Cards = {}

Cards.Definitions = {
    -- Luffy 5★ cards
    Legendary = {
        {
            id = "Luffy_Legendary_GumGumGatling",
            name = "Gum-Gum Gatling",
            module = "Luffy_GumGumGatling",
            stackable = false,
            maxLevel = 5,
			description = "Unleashes a 2s cone of Gum-Gum projectiles that deal damage on touch.",
			image = "rbxassetid://81319370438913",
        },
        {
            id = "Luffy_Rare_GumGumGear",
            name = "Gum-Gum Gear",
            module = "Luffy_Gear",
            stackable = true,
            maxLevel = 5,
			description = "Periodically grants increased attack speed and movement speed for 10s.",
			image = "rbxassetid://136805952993792",
        }
    }
}

return Cards
