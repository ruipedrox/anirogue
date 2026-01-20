-- Ulquiorra Stats (Boss Bleach Level 2 - Third Story Map)
-- Complex boss with 4 abilities: Dash, Cero beam, Trident rain, 1000 Cuts
return {
	Health = 12000,             -- Boss lvl2 health
	MoveSpeed = 16,
	Damage = 140,               -- High base damage
	XPDrop = 1200,
	GoldDrop = 750,
	
	-- Dash Slash (like Sasuke/Kenpachi)
	DashInterval = 14,          -- seconds between dash attempts
	DashTelegraph = 1.5,        -- preview duration before dash
	DashRange = 50,             -- max dash travel distance
	DashDamage = 350,           -- High dash impact damage
	DashAoERadius = 14,         -- radius of damage on dash impact
	DashPathTickDamage = 160,   -- Heavy path damage
	DashPathTickRadius = 7,     -- radius around Ulquiorra during dash
	
	-- Cero (Kamehameha-like beam)
	CeroInterval = 18,          -- seconds between cero attempts
	CeroCharge = 2.5,           -- charge duration (cero_charge animation)
	CeroBeamDuration = 3.0,     -- beam active duration
	CeroTickInterval = 0.3,     -- damage tick rate during beam
	CeroDamagePerTick = 120,    -- damage per tick (high sustained damage)
	CeroRange = 150,            -- beam travel distance
	
	-- Trident Rain
	TridentInterval = 22,       -- seconds between trident attacks
	TridentCount = 5,           -- number of tridents to spawn
	TridentFallDelay = 2.0,     -- delay before tridents fall (telegraph time)
	TridentDamage = 280,        -- damage per trident impact
	TridentAoERadius = 12,      -- impact radius per trident
	TridentHeight = 60,         -- spawn height above ground
	
	-- 1000 Cuts (rapid cone damage)
	CutsInterval = 20,          -- seconds between 1000 cuts
	CutsDuration = 3.0,         -- animation duration (1000_cuts)
	CutsMoveSpeedBoost = 8,     -- extra movement speed during cuts
	CutsDamagePerTick = 90,     -- damage per hit
	CutsTickRate = 0.2,         -- 5 hits per second (1/0.2 = 5)
	CutsConeAngle = 90,         -- cone angle in degrees (45° each side)
	CutsConeRange = 15,         -- cone range in studs
}
