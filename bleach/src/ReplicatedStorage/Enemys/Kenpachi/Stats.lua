-- Kenpachi Stats (Boss Bleach Level 1 - Third Story Map)
-- Brutal melee fighter with dash and teleport abilities
-- Much stronger than Naruto/DBZ bosses
return {
	Health = 8500,              -- Boss health for third map
	MoveSpeed = 14,
	Damage = 120,               -- High base damage
	XPDrop = 850,
	GoldDrop = 550,
	
	-- Normal Attack (like Zabuza's melee)
	AttackRange = 6,
	AttackCooldown = 1.8,
	AttackDamage = 180,         -- Strong normal attacks
	
	-- Dash Slash (like Sasuke's Chidori dash)
	DashInterval = 12,          -- seconds between dash attempts
	DashTelegraph = 1.5,        -- preview duration before dash
	DashRange = 45,             -- max dash travel distance
	DashDamage = 320,           -- High dash impact damage
	DashAoERadius = 12,         -- radius of damage on dash impact
	DashPathTickDamage = 140,   -- Heavy path damage
	DashPathTickRadius = 6,     -- radius around Kenpachi during dash
	
	-- Teleport Strike
	TeleportInterval = 18,      -- seconds between teleport attempts
	TeleportCharge = 2.0,       -- charge duration (animation Teleport_charge)
	TeleportRange = 80,         -- max range to teleport to player
	TeleportDamage = 450,       -- Massive teleport strike damage
	TeleportAoERadius = 15,     -- impact radius
}
