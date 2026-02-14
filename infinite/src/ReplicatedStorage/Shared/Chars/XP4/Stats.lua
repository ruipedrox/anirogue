local XP4Stats = {}

-- XP Monster Tier 4 - evolução intermediária
XP4Stats.name = "XP Golem"
XP4Stats.stars = 2
XP4Stats.icon = 92749049461009 -- Usando mesmo icon do evolve_core temporariamente

-- Stats baixos - usado principalmente para evolução
XP4Stats.Passives = {
	BaseDamage = 15,
	Health = 300,
}

-- XP dado quando consumido no Feed - muito alto
XP4Stats.FeedXP = 100000

return XP4Stats
