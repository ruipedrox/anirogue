-- CardDispatcher.lua
-- Único ponto para aplicar qualquer carta (presentes ou futuras) sem if-chains no server.
-- Contrato de definição de carta (tabela def dentro de meta._def):
--   module = "Name"            -> ModuleScript em Scripts/Cards/Name com função Apply(player, def)
--   (OU)
--   statName + (amount | amountPerTier) -> carta de aumento de stat direto
--   amount            -> valor fixo (percent se DamagePercent/HealthPercent, fracionário noutros)
--   amountPerTier     -> multiplicado por meta._tier (tier do item) se existir
--   stackable=true    -> pode ser escolhida várias vezes (controlado no CardPool)
--   maxLevel          -> usado pelos módulos para limitar níveis
-- Qualquer lógica especial de aura, loops, etc. fica dentro do módulo apontado por 'module'.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CardsFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Cards")

local Dispatcher = {}

-- Cache de módulos de cartas já requeridos
local _moduleCache: { [string]: any } = {}
-- Cartas aplicadas por jogador (tracking simples por id) para eventuais limpezas
local _playerCards: { [Player]: { [string]: boolean } } = {}

-- Obtém (e faz require se necessário) o ModuleScript da carta (campo def.module)
function Dispatcher.GetModule(name: string)
    if type(name) ~= "string" or #name == 0 then return nil end
    if _moduleCache[name] ~= nil then return _moduleCache[name] end
    local modScript = CardsFolder:FindFirstChild(name)
    if not modScript then
        warn("[CardDispatcher] Module not found:", name)
        _moduleCache[name] = false
        return nil
    end
    local ok, mod = pcall(require, modScript)
    if not ok then
        warn("[CardDispatcher] Error requiring module", name, mod)
        _moduleCache[name] = false
        return nil
    end
    _moduleCache[name] = mod
    return mod
end

-- Permite consultar se um jogador já tem uma carta aplicada (por id meta.id)
function Dispatcher.HasPlayerCard(player: Player, cardId: string)
    local set = _playerCards[player]
    return set and set[cardId] or false
end

-- Marca que o jogador recebeu a carta
local function markPlayerCard(player: Player, cardId: string)
    if not player or not cardId then return end
    local set = _playerCards[player]
    if not set then
        set = {}
        _playerCards[player] = set
    end
    set[cardId] = true
end

-- Limpa tracking (chamar em PlayerRemoving)
function Dispatcher.ClearPlayer(player: Player)
    _playerCards[player] = nil
end

-- Tenta chamar Stop(player) em todos módulos que possuam essa função (para loops/aura)
function Dispatcher.StopAllForPlayer(player: Player)
    for name, mod in pairs(_moduleCache) do
        if mod and type(mod) == "table" then
            local stopFn = rawget(mod, "Stop")
            if type(stopFn) == "function" then
                pcall(stopFn, player)
            end
        end
    end
end

-- Upgrades bucket: ApplyStats reads from here every time and folds into Stats before applying to Humanoid
local function ensureUpgrades(player: Player)
    local upgrades = player:FindFirstChild("Upgrades")
    if not upgrades then
        upgrades = Instance.new("Folder")
        upgrades.Name = "Upgrades"
        upgrades.Parent = player
    end
    return upgrades
end

local function addUpgrade(player: Player, name: string, delta: number)
    if type(delta) ~= "number" or delta == 0 then return end
    local upgrades = ensureUpgrades(player)
    local nv = upgrades:FindFirstChild(name)
    if not nv then
        nv = Instance.new("NumberValue")
        nv.Name = name
        nv.Value = 0
        nv.Parent = upgrades
    end
    nv.Value += delta
end

-- Aplica uma carta genérica.
-- meta: tabela enviada ao cliente (contém _def, _tier se equipamento)
-- currentLevel: nível atual da carta (para cartas stackable)
function Dispatcher.ApplyCard(player: Player, meta, currentLevel: number?)
    if not player or not meta then return end
    local def = meta._def or meta -- fallback
    if type(def) ~= "table" then return end
    local level = currentLevel or 1

    -- 1) Se tem module, despacha para o módulo
    if type(def.module) == "string" and #def.module > 0 then
        local mod = Dispatcher.GetModule(def.module)
        if mod then
            -- Check for OnCardAdded (for stackable cards with levels)
            if type(mod.OnCardAdded) == "function" then
                local ok2, err = pcall(mod.OnCardAdded, player, def, level)
                if not ok2 then
                    warn("[CardDispatcher] Error calling OnCardAdded", def.module, err)
                else
                    markPlayerCard(player, meta.id or def.module)
                end
            -- Fallback to Apply for legacy cards
            elseif type(mod.Apply) == "function" then
                local ok2, err = pcall(mod.Apply, player, def)
                if not ok2 then
                    warn("[CardDispatcher] Error applying module", def.module, err)
                else
                    markPlayerCard(player, meta.id or def.module)
                end
            end
        end
        return
    end

    -- 2) Stat card (equipment ou futura) baseada em amount / amountPerTier
    local statName = def.statName
    if type(statName) == "string" then
        local delta = 0
        if type(def.amount) == "number" then
            delta = def.amount
        elseif type(def.amountPerTier) == "number" then
            local tier = meta._tier or def.tier or 1
            delta = def.amountPerTier * tier
        end
        if delta ~= 0 then
            -- Write to Upgrades so ApplyStats will fold and then update Humanoid (MaxHealth, etc)
            addUpgrade(player, statName, delta)
            -- Trigger a stats recompute now
            local okApply, ApplyStats = pcall(function()
                return require(ReplicatedStorage.Scripts.ApplyStats)
            end)
            if okApply and ApplyStats and type(ApplyStats.Apply) == "function" then
                local EquippedItems = require(ReplicatedStorage.Scripts.EquipedItems)
                local CharEquipped = require(ReplicatedStorage.Scripts.CharEquiped)
                local items = EquippedItems:GetEquipped(player)
                local chars = CharEquipped:GetEquipped(player)
                pcall(function() ApplyStats:Apply(player, items, chars) end)
            end
        end
        return
    end

    -- 3) Sem handler conhecido
    warn("[CardDispatcher] No handler for card id", meta.id or "<unknown>")
end

return Dispatcher
