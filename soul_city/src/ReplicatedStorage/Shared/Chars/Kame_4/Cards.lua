-- Cards.lua (Kame_4)
-- Turtle Master character cards (4-star). Contains an Epic progression card that increases MaxLevel.

local KameCards = {}

KameCards.Definitions = {
    Epic = {
        {
            id = "Kame_Epic_MasteryFocus",
            name = "Mastery Focus",
            rarity = "Epic",
            description = "+10% XP gain per card level.",
            stackable = true,
            maxLevel = 5,
            -- Each level raises player.Stats.xpgainrate by +10% (handled by module)
            module = "IncreaseMaxLevel",
            -- Single image for all levels (pedido: sem imagens por nível)
            image = "rbxassetid://00000000000000", -- TODO: substituir pelo asset real
            -- Mantemos levelTracker caso o UI use para mostrar progresso numérico, mas sem trocar imagem.
            levelTracker = {
                folder = "KameMastery",
                valueName = "Level",
                showNextLevel = false, -- não precisamos de preview de próxima imagem
            },
        },
    },
}

return KameCards
