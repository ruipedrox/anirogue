local KameStats = {}

-- Display metadata
KameStats.name = "Turtle Master"
KameStats.stars = 4
KameStats.icon = 93720933756204
KameStats.can_evolve = false
-- Base passive stats - XP boost character com vida decente
KameStats.Passives = {
    xpgainrate = 2.0,  -- 100% mais XP ganho (upgrade do 1.5)
    Health = 1000,     -- Vida 4★ padrão (grande upgrade)
}

-- XP dado quando consumido no Feed (4 = 15000)
KameStats.FeedXP = 15000

return KameStats
