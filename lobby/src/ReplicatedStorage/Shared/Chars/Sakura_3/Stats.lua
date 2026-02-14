local SakuraStats = {}

-- Display metadata
SakuraStats.name = "Pink Medic" -- Sakura, 3-star
SakuraStats.stars = 3
SakuraStats.icon = 0 -- Substitui com o ID do ícone quando tiveres
-- Flag: whether this template supports evolution (UI reads from Stats)
SakuraStats.can_evolve = true
SakuraStats.Passives = {
	BaseDamage = 25,
	Health = 360,
}

-- XP dado quando consumido no Feed (3 = 5000)
SakuraStats.FeedXP = 5000

return SakuraStats
