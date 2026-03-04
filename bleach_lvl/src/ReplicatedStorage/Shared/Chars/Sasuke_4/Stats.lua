local SasukeStats = {}

-- Display metadata
SasukeStats.name = "Avenger" -- Sasuke, 4-star
SasukeStats.stars = 4
SasukeStats.icon = 78202057215882 -- Substitui com o ID do ícone quando tiveres
-- Flag: whether this template supports evolution (UI reads from Stats)
SasukeStats.can_evolve = true
-- DAMAGE DEALER focused (2x do 3★)
SasukeStats.Passives = {
	BaseDamage = 120,  -- 2x do 3★ (60)
	Health = 300,      -- 2x do 3★ (150)
}

-- XP dado quando consumido no Feed (4 = 15000)
SasukeStats.FeedXP = 15000

return SasukeStats
