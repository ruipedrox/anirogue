-- WaveConfig.lua - GREEN PLANET LEVEL 1
-- Namek Plains - First Green Planet map
-- Boss: Freeza

local WaveConfig = {}

-- Character XP per wave (kept similar to Village map for consistent progression)
WaveConfig.CharacterXP = {
    BasePerWave = 100,  -- Same as Village lvl1
    GrowthPerWave = 25, -- Same as Village lvl1
}

-- Global scaling rates (intermediário: mais difícil que Village, mais fácil que Bleach)
WaveConfig.Rates = {
    GoldPerWavePercent = 0.025,   -- +2.5% gold per wave
    XPPerWavePercent   = 0.055,   -- +5.5% XP per wave
    HealthPerWavePercent = 0.065, -- +6.5% Health per wave (Village=6%, Bleach=7%)
    DamagePerWavePercent = 0.055, -- +5.5% Damage per wave (Village=5%, Bleach=6%)
}

-- Burst spawning
WaveConfig.Burst = {
    StartWave = 5, -- começa bursts na wave 5
    Min = 3,
    Max = 6,
}

-- Spawn area
WaveConfig.SpawnAreas = {
    {
        corners = {
            Vector3.new(108.816, 45.211, 33.316),
            Vector3.new(188.64, 45.211, 33.316),
            Vector3.new(188.64, 45.211, 113.492),
            Vector3.new(108.816, 45.211, 113.492),
        },
        Y = 45.211,
    }
}

-- 15 waves - Namek Plains difficulty
WaveConfig.Waves = {
    { enemies = { { id = "melee_alien", count = 3 } } }, -- Wave 1
    { enemies = { { id = "melee_alien", count = 4 } } }, -- Wave 2
    { enemies = { { id = "melee_alien", count = 5 }, { id = "ranged_alien", count = 1 } } }, -- Wave 3
    { enemies = { { id = "melee_alien", count = 6 }, { id = "ranged_alien", count = 2 } } }, -- Wave 4
    { enemies = { { id = "melee_alien", count = 7 }, { id = "ranged_alien", count = 2 } } }, -- Wave 5
    { enemies = { { id = "melee_alien", count = 8 }, { id = "ranged_alien", count = 3 } } }, -- Wave 6
    { enemies = { { id = "melee_alien", count = 9 }, { id = "ranged_alien", count = 3 }, { id = "cloner_alien", count = 1 } } }, -- Wave 7
    { enemies = { { id = "melee_alien", count = 10 }, { id = "ranged_alien", count = 4 }, { id = "cloner_alien", count = 1 } } }, -- Wave 8
    { enemies = { { id = "melee_alien", count = 11 }, { id = "ranged_alien", count = 4 }, { id = "cloner_alien", count = 2 } } }, -- Wave 9
    { enemies = { { id = "melee_alien", count = 12 }, { id = "ranged_alien", count = 5 }, { id = "cloner_alien", count = 2 } } }, -- Wave 10
    { enemies = { { id = "melee_alien", count = 13 }, { id = "ranged_alien", count = 5 }, { id = "cloner_alien", count = 2 } } }, -- Wave 11
    { enemies = { { id = "melee_alien", count = 14 }, { id = "ranged_alien", count = 6 }, { id = "cloner_alien", count = 3 } } }, -- Wave 12
    { enemies = { { id = "melee_alien", count = 15 }, { id = "ranged_alien", count = 6 }, { id = "cloner_alien", count = 3 } } }, -- Wave 13
    { enemies = { { id = "melee_alien", count = 16 }, { id = "ranged_alien", count = 7 }, { id = "cloner_alien", count = 4 } } }, -- Wave 14
    { enemies = { { id = "Frieza", count = 1, position = Vector3.new(148.73, 45.21, 73.4) } } }, -- Wave 15 (Boss: Freeza - Centro do mapa)
}

return WaveConfig