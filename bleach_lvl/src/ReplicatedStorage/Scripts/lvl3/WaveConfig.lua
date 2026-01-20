-- WaveConfig.lua (lvl3) - BLEACH LEVEL 3
-- Hardest tier: Las Noches - Final challenge with Ulquiorra boss
-- Earlier burst, bigger increments, most enemies

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
            Vector3.new(43.331, 42.877, -77.222),
            Vector3.new(43.15,  42.877,  5.278),
            Vector3.new(125.649,42.877,  5.96),
            Vector3.new(124.832,42.877, -77.542),
        },
        Y = 42.877,
    }
}

-- Bleach themed waves - HARDEST difficulty with maximum Reapers
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
    { enemies = { { id = "Aizen", count = 1, position = Vector3.new(84.5, 42.877, -35.882) } } }, -- 15 (FINAL BOSS: Aizen - Lord of Las Noches)
}

return WaveConfig
