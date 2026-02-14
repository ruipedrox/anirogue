local XP5Stats = {}

-- XP Monster Tier 5 - evolução final
XP5Stats.name = "XP Dragon"
XP5Stats.stars = 3
XP5Stats.icon = 114655951919645 -- Usando mesmo icon do wish_ball temporariamente

-- Stats moderados - forma final
XP5Stats.Passives = {
	BaseDamage = 40,
	Health = 800,
}

-- XP dado quando consumido no Feed - extremamente alto
XP5Stats.FeedXP = 250000

return XP5Stats
