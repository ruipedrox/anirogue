local Cards = {}

Cards.Definitions = {
    -- Aizen 5★ cards (populate with card entries)
    Legendary = {
        {
            id = "Aizen_Reiatsu",
            name = "Reiatsu",
            module = "Aizen_Reiatsu",
            stackable = false,
			image = "rbxassetid://130390129929242",
            maxLevel = 5,
            description = "A surrounding aura that deals periodic damage and lightly knocks enemies back.",
        },
        {
            id = "Aizen_PerfectIllusion",
            name = "Perfect Illusion",
            module = "Aizen_PerfectIllusion",
            stackable = false,
			image = "rbxassetid://134977828484453",
            maxLevel = 5,
            description = "Periodically become semi-transparent and intangible for a short duration.",
        },
    },
}

return Cards

