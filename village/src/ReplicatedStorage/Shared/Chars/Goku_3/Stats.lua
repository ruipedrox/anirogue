local GokuStats = {}

-- Display metadata
GokuStats.name = "Alien Warrior" -- renamed from Goku for copyright-safe display
GokuStats.stars = 3
GokuStats.icon = 91540305880581

-- Flag: whether this template supports evolution (UI reads from Stats)
GokuStats.can_evolve = true

-- Base passive stats - TANK focused (high HP, moderate damage)
GokuStats.Passives = {
	BaseDamage = 30,
	Health = 600,
}

-- XP dado quando consumido no Feed (3★ = 5000)
GokuStats.FeedXP = 5000

return GokuStats
