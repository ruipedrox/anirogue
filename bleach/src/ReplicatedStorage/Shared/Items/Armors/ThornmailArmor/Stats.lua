local ThornmailArmorStats = {}

-- Stats básicos
ThornmailArmorStats.Health = 100 -- base fallback
ThornmailArmorStats.Name="Thornmail Armor"
-- Rarity label (visual only) and implicit Tier mapping
ThornmailArmorStats.Rarity = "Rare"

-- Icon asset id (placeholder) para UI
ThornmailArmorStats.iscon = "rbxassetid://107800334919945"


ThornmailArmorStats.Levels = {
	[1] = { Health = 100 },
	[2] = { Health = 120 },
	[3] = { Health = 145 },
	[4] = { Health = 175 },
	[5] = { Health = 210 },
}

return ThornmailArmorStats