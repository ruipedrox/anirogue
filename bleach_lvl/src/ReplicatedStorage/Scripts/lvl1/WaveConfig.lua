-- WaveConfig.lua - BLEACH LEVEL 1
-- First Bleach map - Soul Society entrance
-- External editable configuration for wave spawning.

local WaveConfig = {}

-- Character XP per wave (server uses this to grant XP each time a wave is cleared)
WaveConfig.CharacterXP = {
    BasePerWave = 120,
    GrowthPerWave = 30,
}

-- Global scaling rates (percent per wave AFTER the first).
WaveConfig.Rates = {
    GoldPerWavePercent = 0.02,   -- +2% gold per wave
    XPPerWavePercent   = 0.05,   -- +5% XP per wave
    HealthPerWavePercent = 0.07, -- +7% Health per wave
    DamagePerWavePercent = 0.06, -- +6% Damage per wave
}

-- Burst spawning
WaveConfig.Burst = {
    StartWave = 6, -- começa bursts na wave 6
    Min = 3,       -- mínimo por ciclo
    Max = 6,       -- máximo por ciclo
}

-- OPTIONAL: Define a rectangular spawn area override (example)
-- WaveConfig.SpawnAreas = {
--     { p1 = Vector3.new(-50, 10, -50), p2 = Vector3.new(50, 10, 50) },
-- }

-- Spawn aleatório dentro da arena (4 cantos fornecidos). Se não houver coordenadas por entry,
-- o WaveManager vai usar esta área.
WaveConfig.SpawnAreas = {
    {
        corners = {
            Vector3.new(-66.95, 10.73, 40.326),
            Vector3.new(13.05, 10.73, 40.326),
            Vector3.new(13.05, 10.23, -40.674),
            Vector3.new(-66.95, 10.23, -40.674),
        },
        Y = 10.5, -- força altura constante (caso raycast não ajuste)
    }
}

-- TEST CONFIGURATION - Aizen for testing
-- Wave 1: Aizen boss in center

WaveConfig.Waves = {
    { enemies = { 
        { id = "Aizen", count = 1, position = Vector3.new(-26.95, 10.5, -0.174) } -- Aizen boss test
    } }, -- Wave 1 TEST
}

--[[
-- Guardado aqui para referência: waves originais 6-15
-- Basta copiar de volta para dentro de WaveConfig.Waves se quiser reativar.
--    { enemies = { { id = "Melee Ninja", count = 10 }, { id = "Ranged Ninja", count = 3 } } }, -- Wave6
--    { enemies = { { id = "Melee Ninja", count = 11 }, { id = "Ranged Ninja", count = 4 } } }, -- Wave7
--    { enemies = { { id = "Melee Ninja", count = 12 }, { id = "Ranged Ninja", count = 5 } } }, -- Wave8
BLEACH BOSS REFERENCE:
- Kenpachi: Melee powerhouse (lvl 1)
- Aizen: Strategic boss with illusions (lvl 2)
- Ulquiorra: Ranged/melee hybrid with regeneration (lvl 3)
]]

return WaveConfig