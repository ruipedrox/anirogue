-- CardCatalog.lua
-- Agrega todas as cartas disponíveis vindas de:
--   * Personagens: Shared/Chars/*/Cards.lua (.Definitions)
--   * Itens: Shared/Items/(Weapons|Armors|Rings)/*/Cards.lua (.Definitions)
-- Fornece indexação por id, raridade, fonte (Character/Item), e util para UI de escolha/summon.
-- Cada carta no catálogo possui estrutura normalizada:
--   id, name, description, rarityGroup (ex: Common, Rare, Legendary), source ("Character"|"Item"), sourceId (ex: Goku_3, Kunai), sourceType (Weapon/Armor/Ring/Character), def (tabela original), image
-- NOTA: Mantém a referência original em def para uso pelo CardDispatcher.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CharsFolder = Shared:WaitForChild("Chars")
local ItemsFolder = Shared:WaitForChild("Items")

local CardCatalog = {
    ById = {},          -- [cardId] = entry
    ByRarity = {},      -- [rarityGroup] = { entries }
    BySource = {},      -- [sourceId] = { entries }
    All = {},           -- array de todas entradas
    Loaded = false,
}

local TYPE_FOLDERS = {
    { container = CharsFolder, source = "Character" },
}

-- Adiciona dinamicamente os três grupos de items
for _, folderName in ipairs({"Weapons","Armors","Rings"}) do
    table.insert(TYPE_FOLDERS, { container = ItemsFolder:WaitForChild(folderName), source = "Item", itemTypeFolder = folderName })
end

local function addEntry(self, entry)
    if not entry or not entry.id then return end
    -- Evitar colisão de ids; se duplicado, anexar sufixo baseado em sourceId
    if self.ById[entry.id] then
        local newId = entry.id .. "_" .. entry.sourceId
        warn("[CardCatalog] ID duplicado de carta '"..entry.id.."' ajustado para '"..newId.."'")
        entry.id = newId
    end
    self.ById[entry.id] = entry
    self.BySource[entry.sourceId] = self.BySource[entry.sourceId] or {}
    table.insert(self.BySource[entry.sourceId], entry)
    self.ByRarity[entry.rarityGroup] = self.ByRarity[entry.rarityGroup] or {}
    table.insert(self.ByRarity[entry.rarityGroup], entry)
    table.insert(self.All, entry)
end

function CardCatalog:_load()
    if self.Loaded then return end
    self.Loaded = true

    for _, spec in ipairs(TYPE_FOLDERS) do
        local container = spec.container
        local isCharacter = spec.source == "Character"
        for _, sub in ipairs(container:GetChildren()) do
            if sub:IsA("Folder") then
                local srcId = sub.Name
                local cardsModule = sub:FindFirstChild("Cards")
                if cardsModule and cardsModule:IsA("ModuleScript") then
                    local ok, cardsData = pcall(require, cardsModule)
                    if ok and type(cardsData) == "table" and type(cardsData.Definitions) == "table" then
                        for rarityGroup, arr in pairs(cardsData.Definitions) do
                            if type(arr) == "table" then
                                for _, def in ipairs(arr) do
                                    if type(def) == "table" then
                                        local entry = {
                                            id = def.id or (srcId .. "_" .. tostring(rarityGroup) .. "_" .. tostring(_)),
                                            name = def.name or def.id or "Unnamed",
                                            description = def.description or "",
                                            rarityGroup = rarityGroup,
                                            source = spec.source,
                                            sourceId = srcId,
                                            sourceType = isCharacter and "Character" or (spec.itemTypeFolder and spec.itemTypeFolder:sub(1, #spec.itemTypeFolder-1) or "Item"), -- singular naive
                                            def = def,
                                            image = def.image,
                                        }
                                        addEntry(self, entry)
                                    end
                                end
                            end
                        end
                    else
                        warn("[CardCatalog] Erro Cards em", srcId, cardsData)
                    end
                end
            end
        end
    end

    -- Ordenar All por rarityGroup depois nome
    table.sort(self.All, function(a,b)
        if a.rarityGroup == b.rarityGroup then
            return a.name < b.name
        end
        return tostring(a.rarityGroup) < tostring(b.rarityGroup)
    end)

    -- Também ordenar buckets
    for _, bucket in pairs(self.ByRarity) do
        table.sort(bucket, function(a,b) return a.name < b.name end)
    end
    for _, bucket in pairs(self.BySource) do
        table.sort(bucket, function(a,b) return a.name < b.name end)
    end
end

function CardCatalog:Get(cardId)
    self:_load()
    return self.ById[cardId]
end

function CardCatalog:GetAll()
    self:_load()
    return self.All
end

function CardCatalog:GetByRarity(rarityGroup)
    self:_load()
    return self.ByRarity[rarityGroup] or {}
end

function CardCatalog:GetBySource(sourceId)
    self:_load()
    return self.BySource[sourceId] or {}
end

function CardCatalog:SearchByName(fragment)
    self:_load()
    fragment = string.lower(fragment or "")
    local out = {}
    if #fragment == 0 then return out end
    for _, e in ipairs(self.All) do
        if string.find(string.lower(e.name), fragment, 1, true) then
            out[#out+1] = e
        end
    end
    return out
end

function CardCatalog:Validate()
    self:_load()
    for id, e in pairs(self.ById) do
        if not e.def then
            warn("[CardCatalog][Validate] Carta sem def", id)
        end
        if not e.name or #e.name == 0 then
            warn("[CardCatalog][Validate] Carta sem name", id)
        end
    end
end

return CardCatalog
