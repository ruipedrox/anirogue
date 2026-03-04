local IchigoStats = {}

-- Display metadata
IchigoStats.name = "Soul Reaper" -- Ichigo, 4-star
IchigoStats.stars = 4
IchigoStats.icon = 97549849466641 -- Substitui com o ID do ícone quando tiveres
-- Flag: whether this template supports evolution (UI reads from Stats)
IchigoStats.can_evolve = true
-- DAMAGE DEALER focused (2x do 3★)
IchigoStats.Passives = {
	BaseDamage = 80,   -- 2x do 3★ (40)
	Health = 280,      -- 2x do 3★ (140)
}

-- XP dado quando consumido no Feed (4 = 15000)
IchigoStats.FeedXP = 15000

return IchigoStats
