local SasukeStats = {}

-- Display metadata
SasukeStats.name = "Avenger" -- Sasuke, 3-star
SasukeStats.stars = 3
SasukeStats.icon = 73677977872129 -- Substitui com o ID do ícone quando tiveres
-- Flag: whether this template supports evolution (UI reads from Stats)
SasukeStats.can_evolve = true
-- DAMAGE DEALER focused (very high damage, low HP)
SasukeStats.Passives = {
	BaseDamage = 60,
	Health = 150,
}

-- XP dado quando consumido no Feed (3 = 5000)
SasukeStats.FeedXP = 5000

return SasukeStats
