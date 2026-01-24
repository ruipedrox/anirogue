-- Aizen Stats (Boss Green Planet Level 3 - Final Boss)
-- Strategic boss with 3 abilities: Normal Attack, Energy Blast, Phase Shift
return {
	Health = 15000,             -- Final boss health (higher than Ulquiorra)
	MoveSpeed = 16,
	Damage = 150,               -- High base damage
	XPDrop = 1500,
	GoldDrop = 1000,
	
	-- Normal Attack
	AttackRange = 6,            -- melee range
	AttackCooldown = 1.8,       -- seconds between attacks
	AttackDamage = 100,         -- normal attack damage
	
	-- Hado 90 (Kurohitsugi)
	HadoInterval = 35,          -- seconds between Hado attempts
	HadoRange = 80,             -- max range to target player
	HadoBuildupTime = 2.5,      -- time for box to build up opacity
	HadoDamage = 400,           -- massive damage on implosion
	
	-- Kyoka Suigetsu (Trick - Intangibility)
	TrickInterval = 25,         -- seconds between trick activations
	TrickDuration = 5.0,        -- duration of intangibility
	
	-- Clone Illusion
	CloneInterval = 30,         -- seconds between clone attacks
	CloneCount = 4,             -- number of clones to spawn
	CloneHealth = 500,          -- clone HP
	CloneMoveSpeed = 20,        -- clone movement speed
	CloneExplosionDamage = 250, -- damage on contact
	CloneExplosionRadius = 10,  -- explosion radius
}
