local IronRingStats = {}

-- Stats básicos
IronRingStats.Health = 100 -- base fallback

-- Rarity label (visual only) and implicit Tier mapping
IronRingStats.Rarity = "Common"

-- Icon asset id (placeholder) para UI
IronRingStats.iscon = "rbxassetid://128774170605145"


IronRingStats.Levels = {
	[1] = { Health = 100 },
	[2] = { Health = 115 },
	[3] = { Health = 135 },
	[4] = { Health = 160 },
	[5] = { Health = 190 },
}

return IronRingStats