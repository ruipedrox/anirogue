-- CharacterTiers.lua (vila)
-- Tier curve: B- = 0%; each step up adds +1.5%
-- Order follows lobby to keep parity

local CharacterTiers = {}

CharacterTiers.TierOrder = {
    "B-","B","B+",
    "A-","A","A+",
    "S-","S","S+",
    "SS","SSS"
}

local indexByName = {}
for i, name in ipairs(CharacterTiers.TierOrder) do
    indexByName[name] = i
end

function CharacterTiers:GetMultiplier(tierName)
    local idx = indexByName[tierName]
    if not idx then return 1.0 end
    return 1.0 + (idx - 1) * 0.015
end

function CharacterTiers:ApplyToStats(baseStats, tierName, dest)
    local mult = self:GetMultiplier(tierName)
    dest = dest or {}
    for k, v in pairs(baseStats) do
        if type(v) == "number" then
            dest[k] = v * mult
        else
            dest[k] = v
        end
    end
    return dest
end

return CharacterTiers
