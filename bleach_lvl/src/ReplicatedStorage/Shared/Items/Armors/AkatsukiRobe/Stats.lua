local AkatsukiRobeStats = {}

-- Stats básicos
AkatsukiRobeStats.Health = 100 -- base fallback
AkatsukiRobeStats.Name="Ape Armor"
-- Rarity label (visual only) and implicit Tier mapping
AkatsukiRobeStats.Rarity = "Epic"

-- Icon asset id (placeholder) para UI
AkatsukiRobeStats.iscon = "rbxassetid://115045895099037"


AkatsukiRobeStats.Levels = {
	[1] = { Health = 100 },
	[2] = { Health = 120 },
	[3] = { Health = 145 },
	[4] = { Health = 175 },
	[5] = { Health = 210 },
}

return AkatsukiRobeStats