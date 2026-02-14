local KunaiStats = {}

-- Stats básicos
-- Optional flat (base) values kept for compatibility; Levels will override when present
KunaiStats.BaseDamage = 25
KunaiStats.AttackSpeed = 1.2
KunaiStats.Pierce = 1

-- Rarity label (visual only for cards) and implicit Tier mapping
KunaiStats.Rarity = "Common"
-- Icon asset id (placeholder). Substituir por 'rbxassetid://<id>'
KunaiStats.iscon = "rbxassetid://96100617774398"

-- Discrete level scaling (1..5)
KunaiStats.Levels = {
	[1] = { BaseDamage = 25, AttackSpeed = 1.2},
	[2] = { BaseDamage = 30, AttackSpeed = 1.22 },
	[3] = { BaseDamage = 36, AttackSpeed = 1.25 },
	[4] = { BaseDamage = 43, AttackSpeed = 1.30 },
	[5] = { BaseDamage = 51, AttackSpeed = 1.35 },
}

return KunaiStats
