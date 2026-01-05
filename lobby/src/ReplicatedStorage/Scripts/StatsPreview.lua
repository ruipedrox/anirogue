-- StatsPreview.lua
-- Calcula pré-visualização de stats de um personagem combinando:
-- * lvl1_stats vindos agora do CharacterCatalog (derivados de Passives em Shared/Chars/<Template>/Stats.lua)
-- * Multiplicador de Tier
-- * Scaling de Level (placeholder: +2% por nível acima de 1) -> ajusta conforme curva real
-- Ordem de aplicação: Base (lvl1) -> Tier -> LevelScaling

local CharacterTiers = require(script.Parent.CharacterTiers)
local CharacterCatalog = require(script.Parent.CharacterCatalog)

local StatsPreview = {}

-- Fallback de stats base por TemplateName (podes substituir com require de Chars/<Template>/Stats)
local FALLBACK_BASE = {
    Goku_3 = { BaseDamage = 40, Health = 400 },
    Naruto_3 = { BaseDamage = 38, Health = 420 },
    Goku_4 = { BaseDamage = 45, Health = 450 },
    Naruto_4 = { BaseDamage = 44, Health = 460 },
    Goku_5 = { BaseDamage = 50, Health = 500 },
    Naruto_5 = { BaseDamage = 50, Health = 500 },
    Krillin_3 = { BaseDamage = 30, Health = 350 },
    Kame_4 = { BaseDamage = 42, Health = 440 },
}

local function clone(tbl)
    local t = {}
    for k,v in pairs(tbl) do t[k] = v end
    return t
end

-- Level scaling (placeholder)
local function applyLevelScaling(stats, level)
    level = math.max(1, level or 1)
    if level <= 1 then return stats end
    -- Exemplo: +2% por nível acima de 1
    local mult = 1 + (level - 1) * 0.02
    for k,v in pairs(stats) do
        if type(v) == "number" then
            stats[k] = v * mult
        end
    end
    return stats
end

function StatsPreview:GetBaseStats(templateName)
    -- 1) Tentar catálogo
    local cat = CharacterCatalog:Get(templateName)
    if cat and cat.lvl1_stats then
        return clone(cat.lvl1_stats)
    end
    -- 2) Fallback interno
    return clone(FALLBACK_BASE[templateName] or { BaseDamage = 25, Health = 300 })
end

-- Retorna tabela de stats finais + breakdown
function StatsPreview:Build(templateName, level, tier)
    tier = tier or "B-"
    local base = self:GetBaseStats(templateName)
    local tierMult = CharacterTiers:GetMultiplier(tier)
    -- Aplica multiplicador de Tier
    for k,v in pairs(base) do
        if type(v) == "number" then
            base[k] = v * tierMult
        end
    end
    -- Aplica scaling de Level
    applyLevelScaling(base, level)
    return {
        Template = templateName,
        Level = level or 1,
        Tier = tier,
        Stats = base,
        TierMultiplier = tierMult,
    }
end

-- Constrói preview para várias instâncias do profile
-- instancesArray: { { Id=..., Template=..., Level=..., Tier=... }, ... }
function StatsPreview:BuildForInstances(instancesArray)
    local out = {}
    for _, inst in ipairs(instancesArray or {}) do
        out[#out+1] = self:Build(inst.Template, inst.Level, inst.Tier)
    end
    return out
end

return StatsPreview