local AkatsukiRingStats = {}

-- Stats básicos
AkatsukiRingStats.Health = 100 -- base fallback
AkatsukiRingStats.Name="Iron Ring"
-- Rarity label (visual only) and implicit Tier mapping
AkatsukiRingStats.Rarity = "Epic"

-- Icon asset id (placeholder) para UI
AkatsukiRingStats.iscon = "rbxassetid://133066891202328"


AkatsukiRingStats.Levels = {
	[1] = { Health = 100 },
	[2] = { Health = 115 },
	[3] = { Health = 135 },
	[4] = { Health = 160 },
	[5] = { Health = 190 },
}

return AkatsukiRingStats