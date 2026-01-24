-- WaveConfig.lua (lvl2) - GREEN PLANET LEVEL 2
-- Namek Village - Medium difficulty
-- Boss: Ulquiorra

local WaveConfig = {}

-- XP same as Village for consistent progression
WaveConfig.CharacterXP = {
    BasePerWave = 100,
    GrowthPerWave = 25,
}

WaveConfig.Rates = {
    GoldPerWavePercent = 0.03,
    XPPerWavePercent   = 0.06,
    HealthPerWavePercent = 0.08,
    DamagePerWavePercent = 0.07,
}

WaveConfig.Burst = {
    StartWave = 4,
    Min = 3,
    Max = 6,
}

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

-- 15 waves - Namek Village difficulty
WaveConfig.Waves = {
    { enemies = { { id = "melee_alien", count = 4 }, { id = "ranged_alien", count = 2 } } }, -- 1
    { enemies = { { id = "melee_alien", count = 5 }, { id = "ranged_alien", count = 2 } } }, -- 2
    { enemies = { { id = "melee_alien", count = 6 }, { id = "ranged_alien", count = 3 }, { id = "cloner_alien", count = 1 } } }, -- 3
    { enemies = { { id = "melee_alien", count = 7 }, { id = "ranged_alien", count = 3 }, { id = "cloner_alien", count = 1 } } }, -- 4
    { enemies = { { id = "melee_alien", count = 8 }, { id = "ranged_alien", count = 4 }, { id = "cloner_alien", count = 2 } } }, -- 5
    { enemies = { { id = "melee_alien", count = 9 }, { id = "ranged_alien", count = 4 }, { id = "cloner_alien", count = 2 } } }, -- 6
    { enemies = { { id = "melee_alien", count = 10 }, { id = "ranged_alien", count = 5 }, { id = "cloner_alien", count = 3 } } }, -- 7
    { enemies = { { id = "melee_alien", count = 11 }, { id = "ranged_alien", count = 5 }, { id = "cloner_alien", count = 3 } } }, -- 8
    { enemies = { { id = "melee_alien", count = 12 }, { id = "ranged_alien", count = 6 }, { id = "cloner_alien", count = 3 } } }, -- 9
    { enemies = { { id = "melee_alien", count = 13 }, { id = "ranged_alien", count = 6 }, { id = "cloner_alien", count = 4 } } }, -- 10
    { enemies = { { id = "melee_alien", count = 14 }, { id = "ranged_alien", count = 7 }, { id = "cloner_alien", count = 4 } } }, -- 11
    { enemies = { { id = "melee_alien", count = 15 }, { id = "ranged_alien", count = 7 }, { id = "cloner_alien", count = 5 } } }, -- 12
    { enemies = { { id = "melee_alien", count = 16 }, { id = "ranged_alien", count = 8 }, { id = "cloner_alien", count = 5 } } }, -- 13
    { enemies = { { id = "melee_alien", count = 17 }, { id = "ranged_alien", count = 8 }, { id = "cloner_alien", count = 6 } } }, -- 14
    { enemies = { { id = "Ulquiorra", count = 1, position = Vector3.new(-26.95, 10.5, -0.174) } } }, -- 15 (Boss: Ulquiorra)
}

return WaveConfig
