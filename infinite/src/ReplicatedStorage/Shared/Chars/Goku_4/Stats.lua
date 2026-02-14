local GokuStats = {}

-- Display metadata
GokuStats.name = "Alien Warrior" -- renamed from Goku for copyright-safe display
GokuStats.stars = 4
GokuStats.icon = 84530411684994
-- Base passive stats - TANK focused (2x do 3★)
GokuStats.Passives = {
	BaseDamage = 60,   -- 2x do 3★ (30)
	Health = 1200,     -- 2x do 3★ (600)
}

-- XP dado quando consumido no Feed (4 = 15000)
GokuStats.FeedXP = 15000

return GokuStats
