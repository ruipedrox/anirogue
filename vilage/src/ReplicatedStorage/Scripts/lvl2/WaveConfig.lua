-- WaveConfig.lua (lvl2)
-- Test config: similar to lvl1 but a bit harder and starts burst earlier

local WaveConfig = {}

WaveConfig.Rates = {
    GoldPerWavePercent = 0.03,
    XPPerWavePercent   = 0.06,
    HealthPerWavePercent = 0.08, -- reduced from 0.12
    DamagePerWavePercent = 0.07, -- reduced from 0.10
}

WaveConfig.Burst = {
    StartWave = 4,
    Min = 3,
    Max = 6,
}

WaveConfig.SpawnAreas = {
    {
        corners = {
            Vector3.new(51, 42.877, -69),
            Vector3.new(51, 42.877, -3),
            Vector3.new(117, 42.877, -3),
            Vector3.new(117, 42.877, -69),
        },
        Y = 42.877,
    }
}

-- Easier counts (primeiro mapa)
WaveConfig.Waves = {
    { enemies = { { id = "Melee Ninja", count = 3 }, { id = "Ranged Ninja", count = 1 } } }, -- 1
    { enemies = { { id = "Melee Ninja", count = 4 }, { id = "Ranged Ninja", count = 2 } } }, -- 2
    { enemies = { { id = "Melee Ninja", count = 5 }, { id = "Ranged Ninja", count = 2 } } }, -- 3
    { enemies = { { id = "Melee Ninja", count = 6 }, { id = "Ranged Ninja", count = 3 } } }, -- 4
    { enemies = { { id = "Melee Ninja", count = 7 }, { id = "Ranged Ninja", count = 3 } } }, -- 5
    { enemies = { { id = "Melee Ninja", count = 8 }, { id = "Ranged Ninja", count = 4 } } }, -- 6
    { enemies = { { id = "Melee Ninja", count = 9 }, { id = "Ranged Ninja", count = 4 } } }, -- 7
    { enemies = { { id = "Melee Ninja", count = 10 }, { id = "Ranged Ninja", count = 5 } } }, -- 8
    { enemies = { { id = "Melee Ninja", count = 11 }, { id = "Ranged Ninja", count = 5 } } }, -- 9
    { enemies = { { id = "Melee Ninja", count = 12 }, { id = "Ranged Ninja", count = 6 } } }, -- 10
    { enemies = { { id = "Melee Ninja", count = 13 }, { id = "Ranged Ninja", count = 6 } } }, -- 11
    { enemies = { { id = "Melee Ninja", count = 14 }, { id = "Ranged Ninja", count = 7 } } }, -- 12
    { enemies = { { id = "Melee Ninja", count = 15 }, { id = "Ranged Ninja", count = 7 } } }, -- 13
    { enemies = { { id = "Melee Ninja", count = 16 }, { id = "Ranged Ninja", count = 8 } } }, -- 14
    { enemies = { { id = "Gaara", count = 1, position = Vector3.new(84.5, 42.877, -35.882) } } }, -- 15 (Boss: Gaara)
}

return WaveConfig
