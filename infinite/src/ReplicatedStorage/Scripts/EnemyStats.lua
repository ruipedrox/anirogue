-- EnemyStats.lua
-- Centralized stats for all enemy types
-- Stats are indexed by enemy TYPE (melee, ranged, regen, cloner), not by visual model

local EnemyStats = {}

-- MELEE ENEMIES
-- Close-range contact damage enemies
-- BASE STATS: Very low to make infinite mode start easier than first story map
-- Infinite scaling (+10% HP, +8% Damage per wave) makes it progressively harder
EnemyStats.melee = {
	Health = 50,        -- Very low base (scales to 150+ by wave 15)
	MoveSpeed = 12,
	Damage = 5,         -- Low base damage (scales to 15+ by wave 15)
	XPDrop = 500,       -- Very high XP - target level 30 at wave 50
	GoldDrop = 0,
}

-- RANGED ENEMIES
-- Projectile-based enemies that attack from distance
EnemyStats.ranged = {
	Health = 40,        -- Even lower HP (ranged = fragile)
	MoveSpeed = 10,
	Damage = 4,         -- Low projectile damage
	XPDrop = 600,       -- Higher XP (harder to kill)
	GoldDrop = 0,
	ProjectileSpeed = 50,
	AttackRange = 40,
	AttackCooldown = 2,
}

-- REGEN ENEMIES
-- Enemies that regenerate health over time
EnemyStats.regen = {
	Health = 70,        -- More HP but still low base
	MoveSpeed = 11,
	Damage = 6,
	XPDrop = 750,       -- Very high XP for difficulty
	GoldDrop = 0,
	RegenRate = 3,      -- Reduced regen (was 5)
	RegenInterval = 1,  -- seconds between regen ticks
}

-- CLONER ENEMIES
-- Enemies that spawn additional copies of themselves
EnemyStats.cloner = {
	Health = 60,        -- Lower base HP
	MoveSpeed = 11,
	Damage = 5,
	XPDrop = 900,       -- Highest XP for most complex enemy
	GoldDrop = 0,
	CloneHealth = 25,   -- Very weak clones (was 80)
	MaxClones = 2,      -- Reduced from 3
	CloneCooldown = 10, -- Slower cloning (was 8)
}

-- Helper function to get stats by type
function EnemyStats.GetByType(enemyType)
	return EnemyStats[enemyType:lower()]
end

return EnemyStats
