-- CharacterTiers.lua
-- Sistema de tiers de stat para personagens.
-- Ordem: B-, B, B+, A-, A, A+, S-, S, S+, SS, SSS
-- Regras: B- = 0% (1.0). Cada passo acima aumenta +1.5% acumulativo.
-- Fórmula: multiplier = 1.0 + (index-1) * 0.015
-- (Index 1 = B-)

local CharacterTiers = {}

CharacterTiers.TierOrder = {
    "B-","B","B+",
    "A-","A","A+",
    "S-","S","S+",
    "SS","SSS"
}

-- Map para lookup rápido de índice
local indexByName = {}
for i,name in ipairs(CharacterTiers.TierOrder) do
    indexByName[name] = i
end

-- Retorna multiplicador (ex: 1.000, 1.015, 1.030, ...)
function CharacterTiers:GetMultiplier(tierName)
    local idx = indexByName[tierName]
    if not idx then return 1.0 end
    return 1.0 + (idx - 1) * 0.015
end

function CharacterTiers:GetIndex(tierName)
    return indexByName[tierName]
end

function CharacterTiers:GetNextTier(tierName)
    local idx = indexByName[tierName]
    if not idx then return nil end
    if idx >= #self.TierOrder then return nil end
    return self.TierOrder[idx + 1]
end

-- Aplica multiplicador a uma tabela de stats (retorna nova tabela ou dest)
function CharacterTiers:ApplyToStats(baseStats, tierName, dest)
    local mult = self:GetMultiplier(tierName)
    dest = dest or {}
    for k,v in pairs(baseStats) do
        if type(v) == "number" then
            dest[k] = v * mult
        else
            dest[k] = v -- copia valores não-numéricos sem alteração
        end
    end
    return dest
end

return CharacterTiers