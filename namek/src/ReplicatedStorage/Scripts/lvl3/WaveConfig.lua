-- WaveConfig.lua (lvl3) - GREEN PLANET LEVEL 3
-- Namek Stronghold - HARDEST difficulty
-- Boss: Aizen (Final Boss of Green Planet story)

local WaveConfig = {}

-- XP same as Village for consistent progression
WaveConfig.CharacterXP = {
    BasePerWave = 100,
    GrowthPerWave = 25,
}

WaveConfig.Rates = {
    GoldPerWavePercent = 0.04,
    XPPerWavePercent   = 0.08,
    HealthPerWavePercent = 0.10,
    DamagePerWavePercent = 0.09,
}

WaveConfig.Burst = {
    StartWave = 3,
    Min = 4,
    Max = 7,
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

-- 15 waves - Namek Stronghold MAXIMUM difficulty
WaveConfig.Waves = {
    { enemies = { { id = "melee_alien", count = 5 }, { id = "ranged_alien", count = 3 }, { id = "cloner_alien", count = 1 } } }, -- 1
    { enemies = { { id = "melee_alien", count = 6 }, { id = "ranged_alien", count = 3 }, { id = "cloner_alien", count = 2 } } }, -- 2
    { enemies = { { id = "melee_alien", count = 7 }, { id = "ranged_alien", count = 4 }, { id = "cloner_alien", count = 2 } } }, -- 3
    { enemies = { { id = "melee_alien", count = 8 }, { id = "ranged_alien", count = 5 }, { id = "cloner_alien", count = 3 } } }, -- 4
    { enemies = { { id = "melee_alien", count = 10 }, { id = "ranged_alien", count = 5 }, { id = "cloner_alien", count = 3 } } }, -- 5
    { enemies = { { id = "melee_alien", count = 11 }, { id = "ranged_alien", count = 6 }, { id = "cloner_alien", count = 4 } } }, -- 6
    { enemies = { { id = "melee_alien", count = 12 }, { id = "ranged_alien", count = 6 }, { id = "cloner_alien", count = 4 } } }, -- 7
    { enemies = { { id = "melee_alien", count = 13 }, { id = "ranged_alien", count = 7 }, { id = "cloner_alien", count = 5 } } }, -- 8
    { enemies = { { id = "melee_alien", count = 14 }, { id = "ranged_alien", count = 7 }, { id = "cloner_alien", count = 5 } } }, -- 9
    { enemies = { { id = "melee_alien", count = 15 }, { id = "ranged_alien", count = 8 }, { id = "cloner_alien", count = 6 } } }, -- 10
    { enemies = { { id = "melee_alien", count = 16 }, { id = "ranged_alien", count = 9 }, { id = "cloner_alien", count = 6 } } }, -- 11
    { enemies = { { id = "melee_alien", count = 18 }, { id = "ranged_alien", count = 9 }, { id = "cloner_alien", count = 7 } } }, -- 12
    { enemies = { { id = "melee_alien", count = 19 }, { id = "ranged_alien", count = 10 }, { id = "cloner_alien", count = 7 } } }, -- 13
    { enemies = { { id = "melee_alien", count = 20 }, { id = "ranged_alien", count = 11 }, { id = "cloner_alien", count = 8 } } }, -- 14
    { enemies = { { id = "Aizen", count = 1, position = Vector3.new(-26.95, 10.5, -0.174) } } }, -- 15 (FINAL BOSS: Aizen)
}

return WaveConfig
