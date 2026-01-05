-- CharacterInventory.lua
-- Constrói visão unificada do inventário de personagens de um jogador, enriquecendo
-- cada instância com dados de catálogo (displayName, stars, lvl1_stats, cards) e preview de stats calculados.
-- Uso previsto: UI de lista, summon results, ecrã de upgrades.
--
-- API:
--   CharacterInventory.Build(profile) -> {
--       EquippedOrder = { instanceId, ... },
--       Instances = { [instanceId] = EnrichedInstance },
--       OrderedList = { EnrichedInstance, ... } -- ordenada por stars desc, depois displayName
--   }
-- EnrichedInstance campos:
--   Id, TemplateName, Level, XP, Tier,
--   Catalog = { template, displayName, stars, lvl1_stats, cardCount, ... },
--   Preview = { Stats = { .. escalados .. }, TierMultiplier, Level, Tier },
--   -- (futuro) Progress (xp needed, percent, etc.)
--
-- NOTA: Recebe profile (servidor) ou snapshot (cliente) desde que siga estrutura ProfileTemplate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")

local CharacterCatalog = require(ScriptsFolder:WaitForChild("CharacterCatalog"))
local StatsPreview = require(ScriptsFolder:WaitForChild("StatsPreview"))

local AccountLeveling = require(ScriptsFolder:WaitForChild("AccountLeveling"))
local CharacterInventory = {}
-- Retorna o número de slots de equip permitidos pelo nível do player
function CharacterInventory.GetAllowedEquipSlots(level)
    return AccountLeveling:GetAllowedEquipSlots(level)
end

-- Utilidade: verificar espaço restante (server side principalmente)
function CharacterInventory.HasSpace(profileOrSnapshot)
    if not profileOrSnapshot then return false, 0, 0 end
    local chars = profileOrSnapshot.Characters or {}
    local cap = chars.Capacity or 50
    local count = 0
    if chars.Instances then
        for _ in pairs(chars.Instances) do count += 1 end
    end
    local remaining = math.max(0, cap - count)
    return remaining > 0, remaining, cap
end

local function enrichInstance(instanceId, raw, catalogEntry)
    local templateName = raw.TemplateName or raw.Template
    local level = raw.Level or 1
    local tier = raw.Tier or "B-"
    local preview = StatsPreview:Build(templateName, level, tier)
    return {
        Id = instanceId,
        TemplateName = templateName,
        Level = level,
        XP = raw.XP or 0,
        Tier = tier,
        Catalog = catalogEntry,
        Preview = preview,
    }
end

function CharacterInventory.Build(profileOrSnapshot)
    if not profileOrSnapshot then return { EquippedOrder = {}, Instances = {}, OrderedList = {} } end
    local chars = profileOrSnapshot.Characters or { Instances = {}, EquippedOrder = {} }
    local outInstances = {}
    local ordered = {}
    local count = 0
    for instanceId, inst in pairs(chars.Instances or {}) do
        local templateName = inst.TemplateName or inst.Template
        local cat = CharacterCatalog:Get(templateName)
        local enriched = enrichInstance(instanceId, inst, cat)
        outInstances[instanceId] = enriched
        table.insert(ordered, enriched)
        count += 1
    end
    table.sort(ordered, function(a,b)
        local sa = (a.Catalog and a.Catalog.stars) or 0
        local sb = (b.Catalog and b.Catalog.stars) or 0
        if sa == sb then
            local na = (a.Catalog and a.Catalog.displayName) or a.TemplateName
            local nb = (b.Catalog and b.Catalog.displayName) or b.TemplateName
            return na < nb
        end
        return sa > sb
    end)
    local account = profileOrSnapshot.Account or {}
    local level = account.Level or 1
    local allowedSlots = CharacterInventory.GetAllowedEquipSlots(level)
    local equippedOrder = chars.EquippedOrder or {}
    -- Limita EquippedOrder ao número de slots permitidos
    local limitedEquippedOrder = {}
    for i = 1, math.min(#equippedOrder, allowedSlots) do
        table.insert(limitedEquippedOrder, equippedOrder[i])
    end
    return {
        EquippedOrder = limitedEquippedOrder,
        Instances = outInstances,
        OrderedList = ordered,
        Capacity = chars.Capacity or 50,
        CurrentCount = count,
        AllowedEquipSlots = allowedSlots,
    }
end

return CharacterInventory
