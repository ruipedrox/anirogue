-- Zabuza Stats (enhanced for special abilities)
return {
	Health = 2400,
	MoveSpeed = 12,
	Damage = 42,
	XPDrop = 260,
	GoldDrop = 160,
	-- Dash (Silent Killing assault)
	DashInterval = 8,          -- seconds between dash attempts
	DashTelegraph = 1.0,        -- preview duration before dash
	DashRange = 32,             -- max dash travel distance toward target
	DashDamage = 130,           -- damage applied in final AoE
	DashAoERadius = 10,         -- radius of damage on dash impact
	DashPathTickDamage = 55,    -- damage applied to players brushed during dash movement
	DashPathTickRadius = 5,     -- radius around Zabuza during dash to apply tick damage
	-- Water Dragon Jutsu
	WaterDragonInterval = 11,   -- seconds between casts
	WaterDragonSpeed = 95,      -- projectile speed
	WaterDragonDamage = 90,     -- direct hit damage (and used for splash scaling)
	WaterDragonPierce = 1,      -- pierce count
	WaterDragonRange = 120,     -- max travel distance (approx via lifetime)
	WaterDragonAoERadius = 12,  -- splash radius on impact
	-- Future expansion placeholders (for balancing / wave scaling hooks)
	AbilityDamageMultiplier = 1,
}
