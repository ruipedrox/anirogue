local ScouterStats = {}

-- Stats básicos
ScouterStats.Health = 100 -- base fallback
ScouterStats.Name = "Scouter"
-- Rarity label (visual only) and implicit Tier mapping
ScouterStats.Rarity = "Legendary"

-- Icon asset id (placeholder) para UI
ScouterStats.iscon = "rbxassetid://109367972136883"


ScouterStats.Levels = {
	[1] = { Health = 100 },
	[2] = { Health = 115 },
	[3] = { Health = 135 },
	[4] = { Health = 160 },
	[5] = { Health = 190 },
}

return ScouterStats