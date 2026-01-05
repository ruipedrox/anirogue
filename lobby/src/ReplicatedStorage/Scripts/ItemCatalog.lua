-- ItemCatalog.lua
-- Agregador dinâmico de todos os itens em Shared/Items (Weapons, Armors, Rings)
-- Cada item encontra-se numa pasta (ex: Weapons/Kunai) contendo:
--   Stats.lua -> define stats base + Levels (cada nível com overrides)
--   Cards.lua (opcional) -> .Definitions com cartas específicas (por raridade)
-- Estrutura por entry retornada:
--   id            = "Kunai" (nome da pasta)
--   itemType      = "Weapon" | "Armor" | "Ring"
--   rarity        = Stats.Rarity ou "Common"
--   lvl1_stats    = stats de Levels[1] (ou base se não existir Levels)
--   levels        = número de níveis possíveis (tamanho de Levels)
--   cards         = Cards.Definitions ou nil
--   cardCount     = total de cartas exclusivas
--   icon_id       = placeholder rbxassetid (podes mapear depois)
--   source        = "Item"
--   rawStats      = tabela completa retornada por Stats (para UI avançada)
-- Fornece acesso por tipo, por id e listas ordenadas por raridade asc + nome.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemsFolder = Shared:WaitForChild("Items")

local ItemCatalog = {
    ByType = {
        Weapon = {},
        Armor = {},
        Ring = {},
    },
    List = {},      -- [id] = entry (ids únicos mesmo entre tipos assumindo nomes diferentes)
    Ordered = {},   -- array de todos itens (qualquer tipo)
    Loaded = false,
}

local TYPE_FOLDERS = {
    Weapons = "Weapon",
    Armors = "Armor",
    Rings = "Ring",
}

local rarityOrder = {
    Common = 1,
    Uncommon = 2,
    Rare = 3,
    Epic = 4,
    Legendary = 5,
    Mythic = 6,
}

local function rarityRank(r)
    return rarityOrder[r] or 99
end

local function shallowCopy(src)
    local t = {}
    for k,v in pairs(src) do t[k] = v end
    return t
end

local function flattenCardDefs(defTable)
    if type(defTable) ~= "table" then return 0 end
    local count = 0
    for _, group in pairs(defTable) do
        if type(group) == "table" then
            for _ , _ in ipairs(group) do
                count += 1
            end
        end
    end
    return count
end

function ItemCatalog:_load()
    if self.Loaded then return end
    self.Loaded = true

    for folderName, typeName in pairs(TYPE_FOLDERS) do
        local container = ItemsFolder:FindFirstChild(folderName)
        if container then
            for _, itemFolder in ipairs(container:GetChildren()) do
                if itemFolder:IsA("Folder") then
                    local id = itemFolder.Name
                    local statsModule = itemFolder:FindFirstChild("Stats")
                    local cardsModule = itemFolder:FindFirstChild("Cards")
                    local statsData, cardsData
                    if statsModule and statsModule:IsA("ModuleScript") then
                        local ok, res = pcall(require, statsModule)
                        if ok and type(res) == "table" then
                            statsData = res
                        else
                            warn("[ItemCatalog] Erro Stats", id, res)
                        end
                    end
                    if cardsModule and cardsModule:IsA("ModuleScript") then
                        local ok2, res2 = pcall(require, cardsModule)
                        if ok2 and type(res2) == "table" then
                            cardsData = res2
                        else
                            warn("[ItemCatalog] Erro Cards", id, res2)
                        end
                    end

                    local rarity = (statsData and statsData.Rarity) or "Common"
                    local levelsTbl = statsData and statsData.Levels or nil
                    local lvl1 = {}
                    -- Copiar valores base primeiro
                    if statsData then
                        for k,v in pairs(statsData) do
                            if type(v) == "number" or type(v) == "boolean" then
                                lvl1[k] = v
                            end
                        end
                    end
                    -- Overrides de Level 1
                    if levelsTbl and levelsTbl[1] then
                        for k,v in pairs(levelsTbl[1]) do
                            lvl1[k] = v
                        end
                    end

                    local cardsDefs = cardsData and cardsData.Definitions or nil
                    local entry = {
                        id = id,
                        itemType = typeName,
                        rarity = rarity,
                        lvl1_stats = shallowCopy(lvl1),
                        levels = levelsTbl and #levelsTbl or 1,
                        cards = cardsDefs,
                        cardCount = flattenCardDefs(cardsDefs),
                        icon_id = "rbxassetid://0",
                        source = "Item",
                        rawStats = statsData,
                    }
                    self.List[id] = entry
                    self.ByType[typeName][id] = entry
                end
            end
        end
    end

    for _, e in pairs(self.List) do table.insert(self.Ordered, e) end
    table.sort(self.Ordered, function(a,b)
        local ra, rb = rarityRank(a.rarity), rarityRank(b.rarity)
        if ra == rb then
            if a.itemType == b.itemType then
                return a.id < b.id
            end
            return a.itemType < b.itemType
        end
        return ra < rb
    end)
end

function ItemCatalog:Get(id)
    self:_load()
    return self.List[id]
end

function ItemCatalog:GetByType(itemType)
    self:_load()
    return self.ByType[itemType] or {}
end

function ItemCatalog:GetOrdered()
    self:_load()
    return self.Ordered
end

function ItemCatalog:Iter(itemType)
    self:_load()
    local list
    if itemType then
        local bucket = self.ByType[itemType]
        list = {}
        for _, e in pairs(bucket) do list[#list+1] = e end
        table.sort(list, function(a,b) return a.id < b.id end)
    else
        list = self.Ordered
    end
    local i = 0
    return function()
        i += 1
        return list[i]
    end
end

function ItemCatalog:Validate()
    self:_load()
    for id, e in pairs(self.List) do
        if not e.lvl1_stats or not next(e.lvl1_stats) then
            warn("[ItemCatalog][Validate] lvl1_stats vazio em", id)
        end
        if not e.rarity then
            warn("[ItemCatalog][Validate] rarity ausente em", id)
        end
    end
end

return ItemCatalog
