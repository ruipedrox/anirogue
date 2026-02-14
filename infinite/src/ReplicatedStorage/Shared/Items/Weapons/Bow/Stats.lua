local BowStats = {}

-- Stats básicos
-- Optional flat (base) values kept for compatibility; Levels will override when present
BowStats.BaseDamage = 25
BowStats.AttackSpeed = 1.2
BowStats.Pierce = 1
BowStats.Name="Bow"
-- Rarity label (visual only for cards) and implicit Tier mapping
BowStats.Rarity = "Rare"
-- Icon asset id (placeholder). Substituir por 'rbxassetid://<id>'
BowStats.iscon = "rbxassetid://117386118147738"

-- Discrete level scaling (1..5)
BowStats.Levels = {
	[1] = { BaseDamage = 25, AttackSpeed = 1.20 },
	[2] = { BaseDamage = 30, AttackSpeed = 1.22 },
	[3] = { BaseDamage = 36, AttackSpeed = 1.25 },
	[4] = { BaseDamage = 43, AttackSpeed = 1.30 },
	[5] = { BaseDamage = 51, AttackSpeed = 1.35 },
}

return BowStats
