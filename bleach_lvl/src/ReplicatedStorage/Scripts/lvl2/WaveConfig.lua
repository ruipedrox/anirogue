-- WaveConfig.lua (lvl2) - BLEACH LEVEL 2
-- Inner Soul Society - Harder difficulty

local WaveConfig = {}

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
            Vector3.new(43.331, 42.877, -77.222),
            Vector3.new(43.15,  42.877,  5.278),
            Vector3.new(125.649,42.877,  5.96),
            Vector3.new(124.832,42.877, -77.542),
        },
        Y = 42.877,
    }
}

-- Bleach themed waves - Harder difficulty with more Reapers
WaveConfig.Waves = {
    { enemies = { { id = "meele_Reaper", count = 4 }, { id = "ranged_Reaper", count = 2 } } }, -- 1
    { enemies = { { id = "meele_Reaper", count = 5 }, { id = "ranged_Reaper", count = 3 } } }, -- 2
    { enemies = { { id = "meele_Reaper", count = 6 }, { id = "ranged_Reaper", count = 3 }, { id = "regen_reaper", count = 1 } } }, -- 3
    { enemies = { { id = "meele_Reaper", count = 7 }, { id = "ranged_Reaper", count = 4 }, { id = "regen_reaper", count = 1 } } }, -- 4
    { enemies = { { id = "meele_Reaper", count = 8 }, { id = "ranged_Reaper", count = 4 }, { id = "regen_reaper", count = 2 } } }, -- 5
    { enemies = { { id = "meele_Reaper", count = 9 }, { id = "ranged_Reaper", count = 5 }, { id = "regen_reaper", count = 2 } } }, -- 6
    { enemies = { { id = "meele_Reaper", count = 10 }, { id = "ranged_Reaper", count = 5 }, { id = "regen_reaper", count = 3 } } }, -- 7
    { enemies = { { id = "meele_Reaper", count = 11 }, { id = "ranged_Reaper", count = 6 }, { id = "regen_reaper", count = 3 } } }, -- 8
    { enemies = { { id = "meele_Reaper", count = 12 }, { id = "ranged_Reaper", count = 6 }, { id = "regen_reaper", count = 4 } } }, -- 9
    { enemies = { { id = "meele_Reaper", count = 13 }, { id = "ranged_Reaper", count = 7 }, { id = "regen_reaper", count = 4 } } }, -- 10
    { enemies = { { id = "meele_Reaper", count = 14 }, { id = "ranged_Reaper", count = 7 }, { id = "regen_reaper", count = 5 } } }, -- 11
    { enemies = { { id = "meele_Reaper", count = 15 }, { id = "ranged_Reaper", count = 8 }, { id = "regen_reaper", count = 5 } } }, -- 12
    { enemies = { { id = "meele_Reaper", count = 16 }, { id = "ranged_Reaper", count = 8 }, { id = "regen_reaper", count = 6 } } }, -- 13
    { enemies = { { id = "meele_Reaper", count = 18 }, { id = "ranged_Reaper", count = 9 }, { id = "regen_reaper", count = 7 } } }, -- 14
    { enemies = { { id = "Ulquiorra", count = 1, position = Vector3.new(84.5, 42.877, -35.882) } } }, -- 15 (Boss: Ulquiorra)
}

return WaveConfig
