local NarutoStats = {}

-- Display metadata
NarutoStats.name = "Fox Boy" -- renamed from Naruto for copyright-safe display
NarutoStats.stars = 3
NarutoStats.icon = 79851758907859
-- Flag: whether this template supports evolution (UI reads from Stats)
NarutoStats.can_evolve = true
NarutoStats.Passives = {
	BaseDamage = 5,
	Health = 100,
}

-- XP dado quando consumido no Feed (3 = 5000)
NarutoStats.FeedXP = 5000

return NarutoStats
