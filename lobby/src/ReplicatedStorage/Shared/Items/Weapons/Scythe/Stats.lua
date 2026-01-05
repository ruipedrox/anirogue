local ScytheStats = {}

-- Stats básicos
-- Optional flat (base) values kept for compatibility; Levels will override when present
ScytheStats.BaseDamage = 25
ScytheStats.AttackSpeed = 1.2
ScytheStats.Pierce = 1
ScytheStats.Name = "X Sword"
-- Rarity label (visual only for cards) and implicit Tier mapping
ScytheStats.Rarity = "Epic"
-- Icon asset id (placeholder). Substituir por 'rbxassetid://<id>'
ScytheStats.iscon = "rbxassetid://101217885481634"

-- Discrete level scaling (1..5)
ScytheStats.Levels = {
	[1] = { BaseDamage = 25, AttackSpeed = 1.20 },
	[2] = { BaseDamage = 30, AttackSpeed = 1.22 },
	[3] = { BaseDamage = 36, AttackSpeed = 1.25 },
	[4] = { BaseDamage = 43, AttackSpeed = 1.30 },
	[5] = { BaseDamage = 51, AttackSpeed = 1.35 },
}

return ScytheStats
