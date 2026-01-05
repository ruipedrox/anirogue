local MagicRingStats = {}

-- Stats básicos
MagicRingStats.Health = 100 -- base fallback
MagicRingStats.Name="Magic Ring"
-- Rarity label (visual only) and implicit Tier mapping
MagicRingStats.Rarity = "Rare"

-- Icon asset id (placeholder) para UI
MagicRingStats.iscon = "rbxassetid://118111067468844"


MagicRingStats.Levels = {
	[1] = { Health = 100 },
	[2] = { Health = 115 },
	[3] = { Health = 135 },
	[4] = { Health = 160 },
	[5] = { Health = 190 },
}

return MagicRingStats