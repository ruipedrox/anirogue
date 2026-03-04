local SukunaCards = {}

SukunaCards.Definitions = {
    -- Primary offensive set
    Legendary = {
        {
            id = "Sukuna_FlamingArrow",
            name = "Flaming Arrow",
            description = "Fire a burning projectile that pierces enemies. Scales with level.",
            stackable = false,
            maxLevel = 5,
			image = "rbxassetid://79953226336627",
            module = "Sukuna_FlamingArrow",
        },
        {
            id = "Sukuna_Cleave",
            name = "Cleave",
            description = "A heavy cleave that hits multiple enemies in front.",
            stackable = false,
            maxLevel = 5,
			image = "rbxassetid://101089331409278",
            module = "Sukuna_Cleave",
        },
        {
            id = "Sukuna_Dismantle",
            name = "Dismantle",
            description = "Break enemy defenses and deal bonus damage.",
            stackable = false,
            maxLevel = 5,
			image = "rbxassetid://95795933424066",
            module = "Sukuna_Dismantle",
        },
    },
    -- Ultimate move unlocked only when Cleave and Dismantle are max level
    Mythic = {
        {
            id = "Sukuna_WorldCuttingSlash",
            name = "World Cutting Slash",
            description = "Devastating single massive slash. Requires Cleave and Dismantle at max level.",
            stackable = false,
            maxLevel = 1,
			image = "rbxassetid://83590374712349",
            module = "Sukuna_WorldCuttingSlash",
            requiredCards = {
                { cardId = "Sukuna_Cleave", minLevel = 1 },
                { cardId = "Sukuna_Dismantle", minLevel = 1 },
            },
        },
    },
}

return SukunaCards
