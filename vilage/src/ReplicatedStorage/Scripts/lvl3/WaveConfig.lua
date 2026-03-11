-- WaveConfig.lua (lvl3)
-- Test config: harder tier, earlier burst, bigger increments

local WaveConfig = {}

WaveConfig.Rates = {
    GoldPerWavePercent = 0.04,
    XPPerWavePercent   = 0.08,
    HealthPerWavePercent = 0.10, -- reduced from 0.15
    DamagePerWavePercent = 0.09, -- reduced from 0.12
}

WaveConfig.Burst = {
    StartWave = 3,
    Min = 4,
    Max = 7,
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

WaveConfig.Waves = {
    { enemies = { { id = "Melee Ninja", count = 4 }, { id = "Ranged Ninja", count = 2 } } }, -- 1
    { enemies = { { id = "Melee Ninja", count = 5 }, { id = "Ranged Ninja", count = 2 } } }, -- 2
    { enemies = { { id = "Melee Ninja", count = 6 }, { id = "Ranged Ninja", count = 3 } } }, -- 3
    { enemies = { { id = "Melee Ninja", count = 7 }, { id = "Ranged Ninja", count = 3 } } }, -- 4
    { enemies = { { id = "Melee Ninja", count = 8 }, { id = "Ranged Ninja", count = 4 } } }, -- 5
    { enemies = { { id = "Melee Ninja", count = 9 }, { id = "Ranged Ninja", count = 4 } } }, -- 6
    { enemies = { { id = "Melee Ninja", count = 10 }, { id = "Ranged Ninja", count = 5 } } }, -- 7
    { enemies = { { id = "Melee Ninja", count = 11 }, { id = "Ranged Ninja", count = 5 } } }, -- 8
    { enemies = { { id = "Melee Ninja", count = 12 }, { id = "Ranged Ninja", count = 6 } } }, -- 9
    { enemies = { { id = "Melee Ninja", count = 13 }, { id = "Ranged Ninja", count = 6 } } }, -- 10
    { enemies = { { id = "Melee Ninja", count = 14 }, { id = "Ranged Ninja", count = 7 } } }, -- 11
    { enemies = { { id = "Melee Ninja", count = 15 }, { id = "Ranged Ninja", count = 7 } } }, -- 12
    { enemies = { { id = "Melee Ninja", count = 16 }, { id = "Ranged Ninja", count = 8 } } }, -- 13
    { enemies = { { id = "Melee Ninja", count = 17 }, { id = "Ranged Ninja", count = 8 } } }, -- 14
    { enemies = { { id = "Sasuke_Curse_Mark", count = 1, position = Vector3.new(84.5, 42.877, -35.882) } } }, -- 15 (Boss: Sasuke)
}

return WaveConfig
