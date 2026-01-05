local clothArmorStats = {}

-- Stats básicos
clothArmorStats.Health = 100 -- base fallback

-- Rarity label (visual only) and implicit Tier mapping
clothArmorStats.Rarity = "Common"

-- Icon asset id (placeholder) para UI
clothArmorStats.iscon = "rbxassetid://135243364483169"


clothArmorStats.Levels = {
	[1] = { Health = 100 },
	[2] = { Health = 120 },
	[3] = { Health = 145 },
	[4] = { Health = 175 },
	[5] = { Health = 210 },
}

return clothArmorStats