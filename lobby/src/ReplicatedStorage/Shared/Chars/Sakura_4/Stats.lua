local SakuraStats = {}

-- Display metadata
SakuraStats.name = "Pink Medic" -- Sakura, 4-star
SakuraStats.stars = 4
SakuraStats.icon = 0 -- Substitui com o ID do ícone quando tiveres
SakuraStats.can_evolve = false
SakuraStats.Passives = {
	BaseDamage = 50,   -- 2x do 3★ (25)
	Health = 720,      -- 2x do 3★ (360)
}

-- XP dado quando consumido no Feed (4 = 15000)
SakuraStats.FeedXP = 15000

return SakuraStats
