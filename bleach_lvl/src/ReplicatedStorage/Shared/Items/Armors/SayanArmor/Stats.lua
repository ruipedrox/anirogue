local SayanArmorStats = {}

-- Stats básicos
SayanArmorStats.Health = 100 -- base fallback
SayanArmorStats.Name="Ape Armor"
-- Rarity label (visual only) and implicit Tier mapping
SayanArmorStats.Rarity = "Legendary"

-- Icon asset id (placeholder) para UI
SayanArmorStats.iscon = "rbxassetid://85697569031179"


SayanArmorStats.Levels = {
	[1] = { Health = 100 },
	[2] = { Health = 120 },
	[3] = { Health = 145 },
	[4] = { Health = 175 },
	[5] = { Health = 210 },
}

return SayanArmorStats