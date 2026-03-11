local NarutoStats = {}

-- Display metadata
NarutoStats.name = "Fox Boy" -- renamed from Naruto for copyright-safe display
NarutoStats.stars = 5
NarutoStats.icon = 124820783784126
NarutoStats.can_evolve = false
-- Base passive stats - ULTRA upgrade from 3★
NarutoStats.Passives = {
	BaseDamage = 200,  -- Massivo upgrade (40x do 3★)
	Health = 2500,     -- Massivo upgrade (20x do 3★)
}

-- XP dado quando consumido no Feed (5 = 50000)
NarutoStats.FeedXP = 50000

return NarutoStats
