-- CharacterService.lua (ModuleScript)
-- Gestão de inventário de personagens (instâncias, tiers, equip) no lobby.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")

local ProfileService = require(ScriptsFolder:WaitForChild("ProfileService"))
local IdUtil = require(ScriptsFolder:WaitForChild("IdUtil"))
local CharacterTiers = require(ScriptsFolder:WaitForChild("CharacterTiers"))
local AccountLeveling = require(ScriptsFolder:WaitForChild("AccountLeveling"))
local CharacterCatalog = require(ScriptsFolder:WaitForChild("CharacterCatalog"))

local CharacterService = {}

-- Leveling curve (must match run place CharacterLeveling.lua)
local HARD_CAP = 80
local BASE_XP = 100
local GROWTH = 1.10

local function XPRequired(level)
    if (tonumber(level) or 0) >= HARD_CAP then return 0 end
    return math.floor(BASE_XP * (GROWTH ^ ((tonumber(level) or 1) - 1)) + 0.5)
end

function CharacterService:AddCharacter(player, templateName, opts)
    local profile = ProfileService:Get(player)
    if not profile then return nil, "NoProfile" end
    if type(templateName) ~= "string" then return nil, "BadTemplate" end
    -- Capacidade
    local cap = profile.Characters.Capacity or 50
    local current = 0
    for _ in pairs(profile.Characters.Instances) do current += 1 end
    if current >= cap then
        return nil, "InventoryFull"
    end
    local id = IdUtil:GenerateInstanceId(templateName)

    -- Tier: se não for fornecido em opts, escolher aleatoriamente (chance uniforme)
    local tier
    if opts and opts.Tier then
        tier = opts.Tier
    else
        local order = CharacterTiers.TierOrder
        if #order > 0 then
            tier = order[math.random(1, #order)]
        else
            tier = "B-" -- fallback de segurança
        end
    end

    profile.Characters.Instances[id] = {
        TemplateName = templateName,
        Level = (opts and opts.Level) or 1,
        XP = (opts and opts.XP) or 0,
        Tier = tier,
    }
    if opts and opts.AutoEquip then
        local slotsAllowed = AccountLeveling:GetAllowedEquipSlots(profile.Account.Level)
        if #profile.Characters.EquippedOrder < slotsAllowed then
            local newCat = CharacterCatalog:Get(templateName)
            local newDisplay = (newCat and newCat.displayName) or templateName
            local duplicate = false
            for _, instId in ipairs(profile.Characters.EquippedOrder) do
                local inst2 = profile.Characters.Instances[instId]
                if inst2 then
                    local cat2 = CharacterCatalog:Get(inst2.TemplateName)
                    local disp2 = (cat2 and cat2.displayName) or inst2.TemplateName
                    if disp2 == newDisplay then
                        duplicate = true
                        break
                    end
                end
            end
            if not duplicate then
                table.insert(profile.Characters.EquippedOrder, id)
            end
        end
    end
    return id
end

function CharacterService:GetInstancePreviews(player, ids)
    local profile = ProfileService:Get(player)
    if not profile then return {} end
    local out = {}
    if type(ids) == "table" and #ids > 0 then
        for _, id in ipairs(ids) do
            local inst = profile.Characters.Instances[id]
            if inst then
                out[#out+1] = { Id = id, Template = inst.TemplateName, Level = inst.Level or 1, Tier = inst.Tier or "B-" }
            end
        end
    else
        for id, inst in pairs(profile.Characters.Instances) do
            out[#out+1] = { Id = id, Template = inst.TemplateName, Level = inst.Level or 1, Tier = inst.Tier or "B-" }
        end
    end
    return out
end

function CharacterService:EquipCharacters(player, orderedIds)
    local profile = ProfileService:Get(player)
    if not profile then return false, "NoProfile" end
    if type(orderedIds) ~= "table" then return false, "BadPayload" end
    local maxSlots = AccountLeveling:GetAllowedEquipSlots(profile.Account.Level)
    local newList, seen, usedDisplay = {}, {}, {}
    for _, id in ipairs(orderedIds) do
        if #newList >= maxSlots then break end
        if type(id) == "string" and not seen[id] and profile.Characters.Instances[id] then
            local inst = profile.Characters.Instances[id]
            local cat = CharacterCatalog:Get(inst.TemplateName)
            local display = (cat and cat.displayName) or inst.TemplateName
            if not usedDisplay[display] then
                table.insert(newList, id)
                seen[id] = true
                usedDisplay[display] = true
            end
        end
    end
    if #newList == 0 then
        local used = {}
        for id, inst in pairs(profile.Characters.Instances) do
            if #newList >= maxSlots then break end
            local cat = CharacterCatalog:Get(inst.TemplateName)
            local display = (cat and cat.displayName) or inst.TemplateName
            if not used[display] then
                table.insert(newList, id)
                used[display] = true
            end
        end
    end
    profile.Characters.EquippedOrder = newList
    return true
end

-- Equipar uma única instância (adiciona ao fim mantendo regras de slots e duplicados de displayName)
function CharacterService:EquipOne(player, instanceId)
    local profile = ProfileService:Get(player)
    if not profile then return false, "NoProfile" end
    if type(instanceId) ~= "string" then return false, "BadId" end
    local inst = profile.Characters.Instances[instanceId]
    if not inst then return false, "NoInstance" end
    -- Já equipado?
    for _, id in ipairs(profile.Characters.EquippedOrder) do
        if id == instanceId then
            return true, "Already"
        end
    end
    local maxSlots = AccountLeveling:GetAllowedEquipSlots(profile.Account.Level)
    local order = profile.Characters.EquippedOrder
    -- Contar ocupados reais (não placeholders)
    local occupied = 0
    for i, v in ipairs(order) do
        if v and v ~= "" and v ~= "_EMPTY_" then occupied += 1 end
    end
    if occupied >= maxSlots then
        return false, "SlotsFull"
    end
    -- Evitar duplicar displayName
    local cat = CharacterCatalog:Get(inst.TemplateName)
    local display = (cat and cat.displayName) or inst.TemplateName
    for _, id in ipairs(profile.Characters.EquippedOrder) do
        local inst2 = profile.Characters.Instances[id]
        if inst2 then
            local cat2 = CharacterCatalog:Get(inst2.TemplateName)
            local disp2 = (cat2 and cat2.displayName) or inst2.TemplateName
            if disp2 == display then
                return false, "DuplicateDisplay"
            end
        end
    end
    -- Procurar primeiro buraco (placeholder) para reutilizar
    for i = 1, maxSlots do
        if order[i] == nil or order[i] == "" or order[i] == "_EMPTY_" then
            order[i] = instanceId
            return true
        end
    end
    -- Se não achou (lista menor que maxSlots), append
    table.insert(order, instanceId)
    return true
end

function CharacterService:UnequipOne(player, instanceId)
    local profile = ProfileService:Get(player)
    if not profile then return false, "NoProfile" end
    local order = profile.Characters.EquippedOrder
    local removed = false
    for i, id in ipairs(order) do
        if id == instanceId then
            order[i] = "_EMPTY_" -- placeholder mantém posição
            removed = true
            break
        end
    end
    if not removed then return false, "NotEquipped" end
    return true
end

function CharacterService:SetTier(player, instanceId, newTier)
    local profile = ProfileService:Get(player)
    if not profile then return false, "NoProfile" end
    local inst = profile.Characters.Instances[instanceId]
    if not inst then return false, "NoInstance" end
    if not CharacterTiers:GetIndex(newTier) then return false, "BadTier" end
    inst.Tier = newTier
    return true
end

function CharacterService:AddCharacterXP(player, instanceId, amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then return false, "NoXP" end
    local profile = ProfileService:Get(player)
    if not profile then return false, "NoProfile" end
    local inst = profile.Characters.Instances[instanceId]
    if not inst then return false, "NoInstance" end
    inst.XP = (inst.XP or 0) + amount
    inst.Level = inst.Level or 1
    -- Apply level-ups immediately using the same curve used in the run server
    while inst.Level < HARD_CAP do
        local need = XPRequired(inst.Level)
        if need <= 0 or inst.XP < need then break end
        inst.XP -= need
        inst.Level += 1
    end
    return true
end

print("[CharacterService Module] Loaded")
return CharacterService
