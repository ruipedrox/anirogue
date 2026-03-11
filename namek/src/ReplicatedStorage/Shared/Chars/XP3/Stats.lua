local XP3Stats = {}

-- XP Monster Tier 3 - evolução básica
XP3Stats.name = "XP Slime"
XP3Stats.stars = 3
XP3Stats.icon = 122812729588216 -- Usando mesmo icon do evolve_shard temporariamente

-- Stats muito baixos - usado apenas para evolução
XP3Stats.Passives = {
	BaseDamage = 5,
	Health = 100,
}

-- XP dado quando consumido no Feed - muito alto para incentivar uso
XP3Stats.FeedXP = 25000

return XP3Stats
