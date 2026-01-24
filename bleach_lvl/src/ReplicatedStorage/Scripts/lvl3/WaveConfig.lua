-- WaveConfig.lua (lvl3) - BLEACH LEVEL 3
-- Las Noches - HARDEST difficulty
-- Boss: Aizen Sosuke (Final Boss of Bleach story)

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

-- 15 waves - Las Noches MAXIMUM difficulty
WaveConfig.Waves = {
    { enemies = { { id = "meele_Reaper", count = 5 }, { id = "ranged_Reaper", count = 3 }, { id = "regen_reaper", count = 1 } } }, -- 1
    { enemies = { { id = "meele_Reaper", count = 6 }, { id = "ranged_Reaper", count = 3 }, { id = "regen_reaper", count = 2 } } }, -- 2
    { enemies = { { id = "meele_Reaper", count = 7 }, { id = "ranged_Reaper", count = 4 }, { id = "regen_reaper", count = 2 } } }, -- 3
    { enemies = { { id = "meele_Reaper", count = 8 }, { id = "ranged_Reaper", count = 5 }, { id = "regen_reaper", count = 3 } } }, -- 4
    { enemies = { { id = "meele_Reaper", count = 10 }, { id = "ranged_Reaper", count = 5 }, { id = "regen_reaper", count = 3 } } }, -- 5
    { enemies = { { id = "meele_Reaper", count = 11 }, { id = "ranged_Reaper", count = 6 }, { id = "regen_reaper", count = 4 } } }, -- 6
    { enemies = { { id = "meele_Reaper", count = 12 }, { id = "ranged_Reaper", count = 6 }, { id = "regen_reaper", count = 4 } } }, -- 7
    { enemies = { { id = "meele_Reaper", count = 13 }, { id = "ranged_Reaper", count = 7 }, { id = "regen_reaper", count = 5 } } }, -- 8
    { enemies = { { id = "meele_Reaper", count = 14 }, { id = "ranged_Reaper", count = 7 }, { id = "regen_reaper", count = 5 } } }, -- 9
    { enemies = { { id = "meele_Reaper", count = 15 }, { id = "ranged_Reaper", count = 8 }, { id = "regen_reaper", count = 6 } } }, -- 10
    { enemies = { { id = "meele_Reaper", count = 16 }, { id = "ranged_Reaper", count = 9 }, { id = "regen_reaper", count = 6 } } }, -- 11
    { enemies = { { id = "meele_Reaper", count = 18 }, { id = "ranged_Reaper", count = 9 }, { id = "regen_reaper", count = 7 } } }, -- 12
    { enemies = { { id = "meele_Reaper", count = 19 }, { id = "ranged_Reaper", count = 10 }, { id = "regen_reaper", count = 7 } } }, -- 13
    { enemies = { { id = "meele_Reaper", count = 20 }, { id = "ranged_Reaper", count = 11 }, { id = "regen_reaper", count = 8 } } }, -- 14
    { enemies = { { id = "Aizen", count = 1, position = Vector3.new(-26.95, 10.5, -0.174) } } }, -- 15 (FINAL BOSS: Aizen)
}

return WaveConfig
