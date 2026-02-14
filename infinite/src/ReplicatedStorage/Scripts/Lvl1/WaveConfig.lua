-- WaveConfig.lua - INFINITE MODE
-- One Piece Themed Infinite Mode
-- No boss waves - endless scaling difficulty

local WaveConfig = {}

-- Infinite mode: no character XP per wave (rewards are items/gold/gems only)
WaveConfig.CharacterXP = {
    BasePerWave = 0,
    GrowthPerWave = 0,
}

-- Aggressive scaling for infinite mode
WaveConfig.Rates = {
    GoldPerWavePercent = 0.0,    -- No gold per wave (only milestone rewards)
    XPPerWavePercent   = 0.0,    -- No XP per wave (only milestone rewards)
    HealthPerWavePercent = 0.10, -- +10% Health per wave (aggressive scaling)
    DamagePerWavePercent = 0.08, -- +8% Damage per wave (aggressive scaling)
}

-- Burst spawning starts early
WaveConfig.Burst = {
    StartWave = 3,
    Min = 4,
    Max = 8,
}

-- Spawn area (One Piece themed infinite map)
WaveConfig.SpawnAreas = {
    {
        corners = {
            Vector3.new(89.99, 35.589, -129.819),
            Vector3.new(201.99, 35.589, -129.819),
            Vector3.new(201.99, 35.589, -17.819),
            Vector3.new(89.99, 35.589, -17.819),
        },
        Y = 35.589,
    }
}

-- Arena bounds for random target generation
WaveConfig.ArenaBounds = {
    min = Vector3.new(89.99, 35.589, -129.819),
    max = Vector3.new(201.99, 35.589, -17.819),
}

-- Infinite waves: procedurally generated
-- Base pattern repeats with increasing difficulty
WaveConfig.InfiniteMode = true

-- Generate 60 base waves, then repeat last 10 (waves 51-60) infinitely
-- NOTE: Using enemy TYPES (melee, ranged, regen, cloner) instead of specific models
--       WaveManager will randomly select visual models from EnemyModels.lua
function WaveConfig.GenerateWave(waveNumber)
    local baseCount = 3 + math.floor(waveNumber * 0.8) -- Scales with wave number
    local enemies = {}
    
    -- Add melee enemies (TYPE: visual model chosen randomly)
    local meleeCount = math.max(1, math.floor(baseCount * 0.4))
    table.insert(enemies, { type = "melee", count = meleeCount })
    
    -- Add ranged enemies (starts at wave 3)
    if waveNumber >= 3 then
        local rangedCount = math.max(1, math.floor(baseCount * 0.3))
        table.insert(enemies, { type = "ranged", count = rangedCount })
    end
    
    -- Add regen enemies (starts at wave 7)
    if waveNumber >= 7 then
        local regenCount = math.max(1, math.floor(baseCount * 0.15))
        table.insert(enemies, { type = "regen", count = regenCount })
    end
    
    -- Add cloner enemies (starts at wave 15)
    if waveNumber >= 15 then
        local clonerCount = math.max(1, math.floor(baseCount * 0.15))
        table.insert(enemies, { type = "cloner", count = clonerCount })
    end
    
    return { enemies = enemies }
end

-- Generate 60 waves
WaveConfig.Waves = {}
for i = 1, 60 do
    WaveConfig.Waves[i] = WaveConfig.GenerateWave(i)
end

-- After wave 60, repeat waves 51-60 infinitely
WaveConfig.RepeatWavesStart = 51
WaveConfig.RepeatWavesEnd = 60

return WaveConfig