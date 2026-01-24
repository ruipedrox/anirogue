-- Cards.lua (Ichigo_5)
-- Defines Ichigo's legendary cards

local IchigoCards = {}

IchigoCards.Definitions = {
	Legendary = {
		{
			id = "Ichigo_Legendary_Bankai",
			name = "Bankai: Tensa Zangetsu",
			description = "Unlock Bankai transformation. Greatly increases damage, attack speed and crit damage.\n\nLv1: +30% damage, +20% attack speed, +25% crit damage\nLv2: +45% damage, +30% attack speed, +50% crit damage\nLv3: +60% damage, +40% attack speed, +75% crit damage\nLv4: +75% damage, +50% attack speed, +100% crit damage\nLv5: +100% damage, +60% attack speed, +125% crit damage",
			stackable = true,
			maxLevel = 5,
			module = "Bankai",
		},
		{
			id = "Ichigo_Legendary_Getsuga",
			name = "Getsuga Tenshou",
			description = "Fire powerful energy projectiles. Projectiles pierce through all enemies.\n\nLv1: 1 projectile, 75% damage\nLv2: 1 projectile, 90% damage\nLv3: 2 projectiles (360°), 105% damage\nLv4: 2 projectiles (360°), 125% damage\nLv5: 3 projectiles (360°), 150% damage",
			stackable = true,
			maxLevel = 5,
			module = "GetsugaTenshou",
		},
	},
}

return IchigoCards
