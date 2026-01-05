-- WaveConfig.lua
-- External editable configuration for wave spawning.
-- Edit this file to control wave composition and scaling.

local WaveConfig = {}

-- Character XP per wave (server uses this to grant XP each time a wave is cleared)
-- Tune these numbers as desired. Example below: 100 XP on wave 1, +25 per additional wave.
WaveConfig.CharacterXP = {
    BasePerWave = 100,
    GrowthPerWave = 25,
}

-- Global scaling rates (percent per wave AFTER the first).
WaveConfig.Rates = {
    GoldPerWavePercent = 0.02,   -- +2% gold per wave (waveIndex-1)
    XPPerWavePercent   = 0.05,   -- +5% XP per wave
    HealthPerWavePercent = 0.06, -- +6% Health per wave (reduced from 10% - easier)
    DamagePerWavePercent = 0.05, -- +5% Damage per wave (reduced from 8% - easier)
}

-- Burst spawning (opcional): a partir da wave StartWave, spawna grupos aleatórios entre Min e Max.
-- Se quiser desativar, basta comentar ou remover este bloco.
WaveConfig.Burst = {
    StartWave = 5, -- começa bursts na wave 5
    Min = 4,       -- mínimo por ciclo
    Max = 7,       -- máximo por ciclo
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
            Vector3.new(43.331, 42.877, -77.222),
            Vector3.new(43.15,  42.877,  5.278),
            Vector3.new(125.649,42.877,  5.96),
            Vector3.new(124.832,42.877, -77.542),
        },
        Y = 42.877, -- força altura constante (caso raycast não ajuste)
    }
}

-- Waves definition:
-- Each wave entry: { enemies = { { id = "Melee Ninja", count = 5 }, ... } }
-- Optional per entry positioning:
--   * position = Vector3.new(x,y,z)              -> all of that entry spawn at same spot
--   * positions = { Vector3.new(...), ... }      -> cycles through list
--   * area = { p1 = Vector3.new(), p2 = Vector3.new() } -> overrides global area for that entry
-- If none provided, WaveManager fallback spawn logic is used.

-- 15 waves com dificuldade progressiva (mais fácil - primeiro mapa)
WaveConfig.Waves = {
    { enemies = { { id = "Melee Ninja", count = 2 } } }, -- Wave 1
    { enemies = { { id = "Melee Ninja", count = 3 } } }, -- Wave 2
    { enemies = { { id = "Melee Ninja", count = 4 }, { id = "Ranged Ninja", count = 1 } } }, -- Wave 3
    { enemies = { { id = "Melee Ninja", count = 5 }, { id = "Ranged Ninja", count = 2 } } }, -- Wave 4
    { enemies = { { id = "Melee Ninja", count = 6 }, { id = "Ranged Ninja", count = 2 } } }, -- Wave 5
    { enemies = { { id = "Melee Ninja", count = 7 }, { id = "Ranged Ninja", count = 3 } } }, -- Wave 6
    { enemies = { { id = "Melee Ninja", count = 8 }, { id = "Ranged Ninja", count = 3 } } }, -- Wave 7
    { enemies = { { id = "Melee Ninja", count = 9 }, { id = "Ranged Ninja", count = 4 } } }, -- Wave 8
    { enemies = { { id = "Melee Ninja", count = 10 }, { id = "Ranged Ninja", count = 4 } } }, -- Wave 9
    { enemies = { { id = "Melee Ninja", count = 11 }, { id = "Ranged Ninja", count = 5 } } }, -- Wave 10
    { enemies = { { id = "Melee Ninja", count = 12 }, { id = "Ranged Ninja", count = 5 } } }, -- Wave 11
    { enemies = { { id = "Melee Ninja", count = 13 }, { id = "Ranged Ninja", count = 6 } } }, -- Wave 12
    { enemies = { { id = "Melee Ninja", count = 14 }, { id = "Ranged Ninja", count = 6 } } }, -- Wave 13
    { enemies = { { id = "Melee Ninja", count = 15 }, { id = "Ranged Ninja", count = 7 } } }, -- Wave 14
    { enemies = { { id = "Zabuza", count = 1, position = Vector3.new(84.5, 42.877, -35.882) } } }, -- Wave 15 (Boss: Zabuza)
}

--[[
-- Guardado aqui para referência: waves originais 6-15
-- Basta copiar de volta para dentro de WaveConfig.Waves se quiser reativar.
--    { enemies = { { id = "Melee Ninja", count = 10 }, { id = "Ranged Ninja", count = 3 } } }, -- Wave6
--    { enemies = { { id = "Melee Ninja", count = 11 }, { id = "Ranged Ninja", count = 4 } } }, -- Wave7
--    { enemies = { { id = "Melee Ninja", count = 12 }, { id = "Ranged Ninja", count = 5 } } }, -- Wave8
--    { enemies = { { id = "Melee Ninja", count = 13 }, { id = "Ranged Ninja", count = 6 } } }, -- Wave9
--    { enemies = { { id = "Gaara", count = 1 }, { id = "Melee Ninja", count = 10 }, { id = "Ranged Ninja", count = 4 } } }, -- Wave10 Boss
--    { enemies = { { id = "Melee Ninja", count = 14 }, { id = "Ranged Ninja", count = 6 } } }, -- Wave11
--    { enemies = { { id = "Melee Ninja", count = 15 }, { id = "Ranged Ninja", count = 7 } } }, -- Wave12
--    { enemies = { { id = "Melee Ninja", count = 14 }, { id = "Ranged Ninja", count = 7 }, { id = "Haku", count = 1 } } }, -- Wave13
--    { enemies = { { id = "Melee Ninja", count = 15 }, { id = "Ranged Ninja", count = 8 }, { id = "Haku", count = 1 } } }, -- Wave14
--    { enemies = { { id = "Sasuke Curse Mark", count = 1 }, { id = "Melee Ninja", count = 12 }, { id = "Ranged Ninja", count = 6 } } }, -- Wave15 Final Boss
]]

return WaveConfig
