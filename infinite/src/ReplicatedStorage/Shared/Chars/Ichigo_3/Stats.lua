local IchigoStats = {}

-- Display metadata
IchigoStats.name = "Soul Reaper" -- Ichigo, 3-star
IchigoStats.stars = 3
IchigoStats.icon = 0 -- Substitui com o ID do ícone quando tiveres
-- DAMAGE DEALER focused (high damage, low HP)
IchigoStats.Passives = {
	BaseDamage = 40,
	Health = 140,
}

-- XP dado quando consumido no Feed (3 = 5000)
IchigoStats.FeedXP = 5000

return IchigoStats
