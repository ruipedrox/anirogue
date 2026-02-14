local GokuStats = {}

-- Display metadata
GokuStats.name = "Alien Warrior" -- renamed from Goku for copyright-safe display
GokuStats.stars = 3
GokuStats.icon = 91156103882629

-- Base passive stats - TANK focused (high HP, moderate damage)
GokuStats.Passives = {
	BaseDamage = 30,
	Health = 600,
}

-- XP dado quando consumido no Feed (3★ = 5000)
GokuStats.FeedXP = 5000

return GokuStats
