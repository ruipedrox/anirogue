-- WaveConfig.lua - GREEN PLANET LEVEL 1
-- Namek Plains - First Green Planet map
-- Boss: Kenpachi

local WaveConfig = {}

-- Character XP per wave (kept similar to Village map for consistent progression)
WaveConfig.CharacterXP = {
    BasePerWave = 100,  -- Same as Village lvl1
    GrowthPerWave = 25, -- Same as Village lvl1
}

-- Global scaling rates (harder than Village)
WaveConfig.Rates = {
    GoldPerWavePercent = 0.02,   -- +2% gold per wave
    XPPerWavePercent   = 0.05,   -- +5% XP per wave
    HealthPerWavePercent = 0.07, -- +7% Health per wave
    DamagePerWavePercent = 0.06, -- +6% Damage per wave
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
            Vector3.new(-59, 10.73, 32),
            Vector3.new(5, 10.73, 32),
            Vector3.new(5, 10.23, -32),
            Vector3.new(-59, 10.23, -32),
        },
        Y = 10.5,
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
    { enemies = { { id = "Kenpachi", count = 1, position = Vector3.new(-26.95, 10.5, -0.174) } } }, -- Wave 15 (Boss: Kenpachi)
}

return WaveConfig