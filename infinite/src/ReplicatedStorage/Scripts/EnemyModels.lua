-- EnemyModels.lua
-- Maps enemy TYPES to available visual models
-- When spawning an enemy of a specific type, a random model from this list is chosen

local EnemyModels = {}

-- MELEE enemy models
-- All melee-type enemies use melee_AI.server.lua
EnemyModels.melee = {
	"meele_Reaper",    -- Bleach Reaper (dark theme)
	"Melee Ninja",     -- Naruto Ninja (orange/black)
	"melee_alien",     -- DBZ Alien (white/purple)
}

-- RANGED enemy models
-- All ranged-type enemies use ranged_AI.server.lua
EnemyModels.ranged = {
	"ranged_Reaper",   -- Bleach Reaper with ranged attacks
	"Ranged Ninja",    -- Naruto Ninja with projectiles
	"ranged_alien",    -- DBZ Alien with energy blasts
}

-- REGEN enemy models
-- All regen-type enemies use regen_AI.server.lua
EnemyModels.regen = {
	"regen_reaper",    -- Bleach Reaper with regeneration
	-- Add more regen models here when created
}

-- CLONER enemy models
-- All cloner-type enemies use cloner_AI.server.lua
EnemyModels.cloner = {
	"cloner_alien",    -- DBZ Alien that spawns clones
	-- Add more cloner models here when created
}

-- Helper function to get a random model name for a type
function EnemyModels.GetRandomModel(enemyType)
	local modelList = EnemyModels[enemyType:lower()]
	if not modelList or #modelList == 0 then
		warn("[EnemyModels] No models found for type:", enemyType)
		return nil
	end
	
	local randomIndex = math.random(1, #modelList)
	return modelList[randomIndex]
end

-- Helper function to get all models for a type
function EnemyModels.GetAllModels(enemyType)
	return EnemyModels[enemyType:lower()] or {}
end

return EnemyModels
