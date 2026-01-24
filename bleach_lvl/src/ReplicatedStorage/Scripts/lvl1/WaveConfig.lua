-- WaveConfig.lua - BLEACH LEVEL 1
-- Soul Society Entrance - First Bleach map (3rd story map overall)
-- Boss: Kenpachi Zaraki

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

-- 15 waves - Soul Society Entrance difficulty
WaveConfig.Waves = {
    { enemies = { { id = "meele_Reaper", count = 3 } } }, -- Wave 1
    { enemies = { { id = "meele_Reaper", count = 4 } } }, -- Wave 2
    { enemies = { { id = "meele_Reaper", count = 5 }, { id = "ranged_Reaper", count = 1 } } }, -- Wave 3
    { enemies = { { id = "meele_Reaper", count = 6 }, { id = "ranged_Reaper", count = 2 } } }, -- Wave 4
    { enemies = { { id = "meele_Reaper", count = 7 }, { id = "ranged_Reaper", count = 2 } } }, -- Wave 5
    { enemies = { { id = "meele_Reaper", count = 8 }, { id = "ranged_Reaper", count = 3 } } }, -- Wave 6
    { enemies = { { id = "meele_Reaper", count = 9 }, { id = "ranged_Reaper", count = 3 }, { id = "regen_reaper", count = 1 } } }, -- Wave 7
    { enemies = { { id = "meele_Reaper", count = 10 }, { id = "ranged_Reaper", count = 4 }, { id = "regen_reaper", count = 1 } } }, -- Wave 8
    { enemies = { { id = "meele_Reaper", count = 11 }, { id = "ranged_Reaper", count = 4 }, { id = "regen_reaper", count = 2 } } }, -- Wave 9
    { enemies = { { id = "meele_Reaper", count = 12 }, { id = "ranged_Reaper", count = 5 }, { id = "regen_reaper", count = 2 } } }, -- Wave 10
    { enemies = { { id = "meele_Reaper", count = 13 }, { id = "ranged_Reaper", count = 5 }, { id = "regen_reaper", count = 2 } } }, -- Wave 11
    { enemies = { { id = "meele_Reaper", count = 14 }, { id = "ranged_Reaper", count = 6 }, { id = "regen_reaper", count = 3 } } }, -- Wave 12
    { enemies = { { id = "meele_Reaper", count = 15 }, { id = "ranged_Reaper", count = 6 }, { id = "regen_reaper", count = 3 } } }, -- Wave 13
    { enemies = { { id = "meele_Reaper", count = 16 }, { id = "ranged_Reaper", count = 7 }, { id = "regen_reaper", count = 4 } } }, -- Wave 14
    { enemies = { { id = "Kenpachi", count = 1, position = Vector3.new(-26.95, 10.5, -0.174) } } }, -- Wave 15 (Boss: Kenpachi)
}

return WaveConfig