local Cards = {}

Cards.Definitions = {
    Epic = {
        {
            id = "Zoro_SwordsmansFocus",
            name = "Swordsman's Focus",
            description = "Each enemy killed grants +2% Base Damage. Max stacks = level * 5.",
            stackable = false,
            maxLevel = 5,
			image = "rbxassetid://130748259447382",
            module = "Zoro_SwordsmansFocus",
        },
    },
    Legendary = {
        {
            id = "Zoro_Santoryu",
            name = "Santoryu",
                -- (note: this card grants +2 projectiles per card level)
                description = "Zoro 5★ exclusive: Base attack fires additional projectiles. Each card level adds +2 projectiles to base attack.",
            stackable = false,
            maxLevel = 5,
			image = "rbxassetid://88248050432141",
            module = "Zoro_Santoryu",
        },
    },
}

return Cards
