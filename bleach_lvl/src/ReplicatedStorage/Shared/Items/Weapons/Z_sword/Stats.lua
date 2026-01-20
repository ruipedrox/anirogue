local Z_swordStats = {}

-- Stats básicos
-- Optional flat (base) values kept for compatibility; Levels will override when present
Z_swordStats.BaseDamage = 25
Z_swordStats.AttackSpeed = 1.2
Z_swordStats.Pierce = 1
Z_swordStats.Name = "X Sword"
-- Rarity label (visual only for cards) and implicit Tier mapping
Z_swordStats.Rarity = "Legendary"
-- Icon asset id (placeholder). Substituir por 'rbxassetid://<id>'
Z_swordStats.iscon = "rbxassetid://140082124499250"

-- Discrete level scaling (1..5)
Z_swordStats.Levels = {
	[1] = { BaseDamage = 25, AttackSpeed = 1.20 },
	[2] = { BaseDamage = 30, AttackSpeed = 1.22 },
	[3] = { BaseDamage = 36, AttackSpeed = 1.25 },
	[4] = { BaseDamage = 43, AttackSpeed = 1.30 },
	[5] = { BaseDamage = 51, AttackSpeed = 1.35 },
}

return Z_swordStats
