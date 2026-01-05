-- NOVA VERSÃO: Carrega dinamicamente personagens a partir de `ReplicatedStorage/Shared/Chars`.
-- Cada personagem encontra-se numa pasta (ex: Goku_3) contendo:
--   Stats.lua -> retorna tabela com pelo menos: name (display), stars (raridade), Passives (stats base lvl1)
--   Cards.lua (opcional) -> retorna tabela com .Definitions (pool de cartas exclusivas do personagem)
-- OBJETIVO: Fornecer catálogo unificado para UI (summon, seleção, inventário) no Lobby e outros mapas.
-- Estrutura de saída por entry:
--   template        = "Goku_3" (nome da pasta)
--   displayName     = "Alien Warrior" (Stats.name ou template)
--   stars           = 3
--   lvl1_stats      = { BaseDamage=..., Health=..., ... } (copiado de Passives)
--   cards           = { <rarityGroup>=array de defs ... } (de Cards.Definitions) OU nil
--   cardCount       = número total de cartas exclusivas (contagem flatten)
--   icon_id         = placeholder (podes substituir por spritesheet / asset real)
--   source          = "Character"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CharsFolder = Shared:WaitForChild("Chars")

local Catalog = {
    List = {},      -- [templateName] = entry
    Ordered = {},   -- array ordenada por stars desc, depois nome
    Loaded = false,
}

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
            for _, _ in ipairs(group) do
                count += 1
            end
        end
    end
    return count
end

function Catalog:_load()
    if self.Loaded then return end
    self.Loaded = true

    for _, charFolder in ipairs(CharsFolder:GetChildren()) do
        if charFolder:IsA("Folder") then
            local templateName = charFolder.Name
            local statsModule = charFolder:FindFirstChild("Stats")
            local cardsModule = charFolder:FindFirstChild("Cards")
            local statsData, cardsData
            if statsModule and statsModule:IsA("ModuleScript") then
                local ok, res = pcall(require, statsModule)
                if ok and type(res) == "table" then
                    statsData = res
                else
                    warn("[CharacterCatalog] Erro ao requerer Stats de", templateName, res)
                end
            end
            if cardsModule and cardsModule:IsA("ModuleScript") then
                local ok2, res2 = pcall(require, cardsModule)
                if ok2 and type(res2) == "table" then
                    cardsData = res2
                else
                    warn("[CharacterCatalog] Erro ao requerer Cards de", templateName, res2)
                end
            end

            -- Construir entry
            local displayName = (statsData and statsData.name) or templateName
            print(string.format("[CharacterCatalog] %s: displayName='%s' (stats.name='%s')", templateName, tostring(displayName), tostring(statsData and statsData.name)))
            local stars = (statsData and statsData.stars) or 0
            local passives = (statsData and statsData.Passives) or {}
            local lvl1Stats = shallowCopy(passives)
            local cardsDefs = cardsData and cardsData.Definitions or nil
            local iconId = (statsData and statsData.icon) or 0
            print(string.format("[CharacterCatalog] %s: stats.icon=%s, final icon_id=rbxassetid://%s", templateName, tostring(statsData and statsData.icon), tostring(iconId)))
            local entry = {
                template = templateName,
                displayName = displayName,
                stars = stars,
                lvl1_stats = lvl1Stats,
                cards = cardsDefs,
                cardCount = flattenCardDefs(cardsDefs),
                icon_id = "rbxassetid://" .. tostring(iconId),
                source = "Character",
            }
            self.List[templateName] = entry
        end
    end

    -- Preencher Ordered
    for _, data in pairs(self.List) do
        table.insert(self.Ordered, data)
    end
    table.sort(self.Ordered, function(a,b)
        if a.stars == b.stars then
            return (a.displayName or a.template) < (b.displayName or b.template)
        end
        return a.stars > b.stars
    end)
end

function Catalog:Get(templateName)
    self:_load()
    return self.List[templateName]
end

function Catalog:GetAllMap()
    self:_load()
    return self.List
end

function Catalog:GetOrdered()
    self:_load()
    return self.Ordered
end

function Catalog:Iter()
    self:_load()
    local i = 0
    local ordered = self.Ordered
    return function()
        i += 1
        return ordered[i]
    end
end

-- Validação rápida para debugging / UI build
function Catalog:Validate()
    self:_load()
    for name, data in pairs(self.List) do
        if type(data.stars) ~= "number" or data.stars <= 0 then
            warn("[CharacterCatalog][Validate] 'stars' ausente ou inválido em", name)
        end
        if not data.lvl1_stats or not next(data.lvl1_stats) then
            warn("[CharacterCatalog][Validate] 'lvl1_stats' vazio em", name)
        end
        if not data.displayName then
            warn("[CharacterCatalog][Validate] displayName ausente em", name)
        end
    end
end

return Catalog