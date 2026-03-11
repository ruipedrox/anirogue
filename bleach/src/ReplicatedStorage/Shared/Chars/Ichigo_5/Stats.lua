local IchigoStats = {}

-- Display metadata
IchigoStats.name = "Soul Reaper" -- Ichigo, 5-star
IchigoStats.stars = 5
IchigoStats.icon = 93346669939844 -- Substitui com o ID do ícone quando tiveres
IchigoStats.can_evolve = false
-- DAMAGE DEALER focused (5x do 3★)
IchigoStats.Passives = {
	BaseDamage = 400,  -- 5x do 3★ (40) - HIGH DAMAGE
	Health = 1000,      -- 5x do 3★ (140) - LOW HP (glass cannon)
}

-- XP dado quando consumido no Feed (5 = 50000)
IchigoStats.FeedXP = 50000

return IchigoStats
