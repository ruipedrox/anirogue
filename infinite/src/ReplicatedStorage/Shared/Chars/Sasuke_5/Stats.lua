local SasukeStats = {}

-- Display metadata
SasukeStats.name = "Avenger" -- Sasuke, 5-star
SasukeStats.stars = 5
SasukeStats.icon = 0 -- Substitui com o ID do ícone quando tiveres
-- DAMAGE DEALER focused (5x do 3★)
SasukeStats.Passives = {
	BaseDamage = 300,  -- 5x do 3★ (60) - HIGHEST DAMAGE
	Health = 750,      -- 5x do 3★ (150) - LOW HP (glass cannon)
}

-- XP dado quando consumido no Feed (5 = 50000)
SasukeStats.FeedXP = 50000

return SasukeStats
