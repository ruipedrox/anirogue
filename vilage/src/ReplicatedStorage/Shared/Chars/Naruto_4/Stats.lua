local NarutoStats = {}

-- Display metadata
NarutoStats.name = "Fox Boy" -- renamed from Naruto for copyright-safe display
NarutoStats.stars = 4
NarutoStats.icon = 70456541518237
-- Flag: whether this template supports evolution (UI reads from Stats)
NarutoStats.can_evolve = true
-- Base passive stats - MAJOR upgrade from 3★
NarutoStats.Passives = {
	BaseDamage = 90,   -- Grande upgrade do 3★ (5 dmg era muito fraco)
	Health = 900,      -- Grande upgrade do 3★ (100 HP era muito fraco)
}

-- XP dado quando consumido no Feed (4 = 15000)
NarutoStats.FeedXP = 15000

return NarutoStats
