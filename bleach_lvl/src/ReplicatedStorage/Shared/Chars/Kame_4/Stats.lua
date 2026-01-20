local KameStats = {}

-- Display metadata
KameStats.name = "Turtle Master"
KameStats.stars = 4
KameStats.icon = 93720933756204
-- Base passive stats (balanced similar to Alien Warrior 4-star, tweakable)
KameStats.Passives = {
    -- Substituição: Em vez de dano base, este personagem dá +5 ao MaxLevel inicial e +50% XP.
    xpgainrate = 1.5,  -- 50% mais XP ganho
    Health = 520,      -- mantém vida ligeiramente acima da média 4★
}

return KameStats
