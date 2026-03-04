local GokuStats = {}

-- Display metadata
GokuStats.name = "Alien Warrior" -- renamed from Goku for copyright-safe display
GokuStats.stars = 5
GokuStats.icon = 91451628148715
GokuStats.can_evolve = false
-- Base passive stats - TANK focused (5x do 3★)
GokuStats.Passives = {
	BaseDamage = 150,  -- 5x do 3★ (30)
	Health = 3000,     -- 5x do 3★ (600) - ULTRA TANK
}

-- XP dado quando consumido no Feed (5 = 50000)
GokuStats.FeedXP = 50000

return GokuStats
