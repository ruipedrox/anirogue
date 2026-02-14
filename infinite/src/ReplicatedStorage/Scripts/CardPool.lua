local CardPool = {}

-- NOTE SOBRE RARIDADE:
-- A raridade (Common / Rare / Epic / Legendary) agora é 100% VISUAL.
-- Não altera números, não multiplica stats. Mantida para:
--   * Colorir UI / efeitos visuais
--   * Ajustar pesos de oferta (se quiseres reintroduzir no futuro)
-- Qualquer scaling deve ser definido explicitamente em cada módulo de carta (ex: SuperWarrior, Kamehameha) ou via statName/amount.

-- Debug toggle: set to true to log card collection and selection details
local DEBUG = true
local function dbg(fmt, ...)
    if not DEBUG then return end
    local msg = string.format(fmt, ...)
    print("[CardPool][Debug] " .. msg)
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CharEquipped = require(ReplicatedStorage.Scripts.CharEquiped)
local EquippedItems = require(ReplicatedStorage.Scripts.EquipedItems)

-- Collect all card definitions from equipped characters
-- Returns array of { id, name, description?, rarity, sourceChar }
function CardPool:GetCardsForPlayer(player)
    local cards = {}
    local equippedFolders = CharEquipped:GetEquippedFolders(player)
    if not equippedFolders or #equippedFolders == 0 then
        warn("[CardPool] Nenhum personagem equipado encontrado para", player and player.Name)
    end
    -- Debug: print equipped char folder names
    do
        local names = {}
        for _, f in ipairs(equippedFolders or {}) do table.insert(names, f.Name) end
        if #names > 0 then
            dbg("Equipped folders for %s: %s", player and player.Name or "?", table.concat(names, ", "))
        end
    end
    for _, charFolder in ipairs(equippedFolders) do
        local cardsModule = charFolder:FindFirstChild("Cards")
        if cardsModule and cardsModule:IsA("ModuleScript") then
            local ok, defs = pcall(require, cardsModule)
            if not ok then
                warn("[CardPool] Failed to require Cards for", charFolder.Name, defs)
            elseif type(defs) == "table" and type(defs.Definitions) == "table" then
                local perCharCount = 0
                for rarity, list in pairs(defs.Definitions) do
                    if type(list) == "table" then
                        for _, def in ipairs(list) do
                            if type(def) == "table" and def.id then
                                -- New design: skip character stat cards (migrate stats to equipment offers)
                                local isStatCard = (typeof(def.base) == "number") -- rarityMultiplier deprecated
                                
                                -- Skip cards that require unlock
                                local requiresUnlock = def.requiresUnlock
                                local canAdd = true
                                if requiresUnlock then
                                    -- Check if player has unlocked this card (e.g., Saitama's Serious Punch)
                                    if def.id == "Saitama_Legendary_Punch" then
                                        canAdd = player:GetAttribute("SaitamaAwakened") == true
                                    end
                                end
                                
                                if not isStatCard and canAdd then
                                    table.insert(cards, {
                                        id = def.id,
                                        name = def.name or def.id,
                                        description = def.description,
                                        rarity = rarity,
                                        sourceChar = charFolder.Name,
                                        image = def.image, -- imagem básica (se existir)
                                        imageLevels = def.imageLevels, -- lista para níveis (SuperWarrior)
                                        _def = def, -- internal reference if needed later
                                    })
                                    perCharCount += 1
                                end
                            end
                        end
                    end
                end
                dbg("Collected %d cards from %s", perCharCount, charFolder.Name)
            else
                warn("[CardPool] Cards module for", charFolder.Name, "did not return Definitions table")
            end
        else
            warn("[CardPool] No Cards module under", charFolder:GetFullName())
        end
    end
    -- Item-specific cards: para cada item equipado, procurar ModuleScript pai (Stats) e sibling Cards
    do
        local equipped = EquippedItems:GetEquipped(player)
        local function collectFromModule(statsTable, instance, itemType)
            if not instance or not instance.Parent then return end
            local parent = instance.Parent
            local cardsModule = parent:FindFirstChild("Cards")
            if cardsModule and cardsModule:IsA("ModuleScript") then
                local okCards, defs = pcall(require, cardsModule)
                if okCards and type(defs) == "table" and type(defs.Definitions) == "table" then
                    local rarityLabel = "Common"
                    local tier = 1
                    if type(statsTable) == "table" then
                        local r = statsTable.Rarity
                        if type(r) == "string" then rarityLabel = r end
                        local t = tonumber(statsTable.Tier); if t and t > 0 then tier = t end
                    end
                    for rarity, list in pairs(defs.Definitions) do
                        if type(list) == "table" then
                            for _, def in ipairs(list) do
                                if type(def) == "table" and def.id then
                                    table.insert(cards, {
                                        id = def.id,
                                        name = def.name or def.id,
                                        description = def.description,
                                        rarity = rarityLabel or rarity,
                                        sourceChar = itemType .. ":" .. parent.Name,
                                        image = def.image,
                                        imageLevels = def.imageLevels,
                                        _def = def,
                                        -- extra meta para aplicação de tier
                                        _tier = tier,
                                        _itemType = itemType,
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
        if equipped then
            if equipped.weapon then
                local weaponValue = player:FindFirstChild("EquippedItems") and player.EquippedItems:FindFirstChild("Weapon")
                local inst = weaponValue and weaponValue.Value
                collectFromModule(equipped.weapon, inst, "Weapon")
            end
            if equipped.armor then
                local armorValue = player:FindFirstChild("EquippedItems") and player.EquippedItems:FindFirstChild("Armor")
                local inst = armorValue and armorValue.Value
                collectFromModule(equipped.armor, inst, "Armor")
            end
            if equipped.ring then
                local ringValue = player:FindFirstChild("EquippedItems") and player.EquippedItems:FindFirstChild("Ring")
                local inst = ringValue and ringValue.Value
                collectFromModule(equipped.ring, inst, "Ring")
            end
        end
    end
    if #cards == 0 then
        warn("[CardPool] No cards collected from equipped folders")
    end
    -- Quick presence check for key cards
    do
        local hasSW = false
        for _, c in ipairs(cards) do if c.id == "Goku_Epic_SuperWarrior" then hasSW = true break end end
        if hasSW then dbg("SuperWarrior present in pool for %s", player and player.Name or "?") else dbg("SuperWarrior NOT present in pool for %s", player and player.Name or "?") end
    end
    return cards
end

-- Utility: pick N random cards from list (without replacement)
function CardPool:PickRandom(list, n)
    local pool = table.clone(list)
    local out = {}
    for i = 1, math.min(n, #pool) do
        local idx = math.random(1, #pool)
        table.insert(out, pool[idx])
        table.remove(pool, idx)
    end
    return out
end

-- New additions: rarity-weighted selection

-- Group cards by rarity: returns { Common = {...}, Epic = {...}, Legendary = {...} }
function CardPool:GroupByRarity(cards)
    local groups = {}
    for _, c in ipairs(cards or {}) do
        local r = c.rarity or "Common"
        groups[r] = groups[r] or {}
        table.insert(groups[r], c)
    end
    return groups
end

-- Roll a rarity according to weights, optionally filtering to rarities that have available cards
-- weights example: { Common = 70, Epic = 25, Legendary = 5 }
function CardPool:RollRarity(weights, availableGroups)
    local pool = {}
    local total = 0
    for r, w in pairs(weights or {}) do
        if w and w > 0 then
            if not availableGroups or (availableGroups[r] and #availableGroups[r] > 0) then
                total += w
                table.insert(pool, { r = r, w = w })
            end
        end
    end
    if total <= 0 then return nil end
    local t = math.random() * total
    local acc = 0
    for _, entry in ipairs(pool) do
        acc += entry.w
        if t <= acc then return entry.r end
    end
    return pool[#pool] and pool[#pool].r or nil
end

-- Remove a specific card object from groups (so offers are unique)
local function removeFromGroups(groups, card)
    if not groups or not card then return end
    local list = groups[card.rarity]
    if not list then return end
    for i, c in ipairs(list) do
        if c == card then
            table.remove(list, i)
            break
        end
    end
end

-- Offer N cards by first rolling rarity (weighted), then picking a card in that rarity.
-- Ensures unique cards in the offer. Falls back to any available rarity if the rolled one is empty.
function CardPool:OfferByRarity(player, count, weights)
    local all = self:GetCardsForPlayer(player)
    -- Deduplicate by id across all sources (keep the first instance)
    do
        local seen = {}
        local uniq = {}
        for _, c in ipairs(all) do
            if not seen[c.id] then
                seen[c.id] = true
                table.insert(uniq, c)
            end
        end
        all = uniq
    end
    if #all == 0 then return {} end
    -- Rarity labels are cosmetic; legendary constraints removed per new design

    -- Filter cards based on run constraints and dynamic player state
    local filteredAll = {}
    -- Determine current level and legendary gating (only at levels 5,10,15,...)
    local currentLevel = 1 -- still used by some filters; milestone logic removed
    do
        local stats = player and player:FindFirstChild("Stats")
        local lv = stats and stats:FindFirstChild("Level")
        if lv and lv:IsA("NumberValue") then currentLevel = lv.Value end
    end
    local runTrack = player and player:FindFirstChild("RunTrack")
    local chosenIds = runTrack and runTrack:FindFirstChild("ChosenCards")
    -- RasenShuriken will now be levelable; we no longer gate it as unique-per-run
    for _, c in ipairs(all) do
        local include = true
        -- Legendary constraints
        -- Legendary gating removed; keep other per-card rules below
        -- Goku SuperWarrior constraint: hide if already at max level
        if include and c.id == "Goku_Epic_SuperWarrior" then
            local maxLevel = 5
            local def = c._def
            if type(def) == "table" and typeof(def.maxLevel) == "number" then
                maxLevel = def.maxLevel
            end
            local runTrack = player and player:FindFirstChild("RunTrack")
            local forms = runTrack and runTrack:FindFirstChild("GokuForms")
            local levelNV = forms and forms:FindFirstChild("Level")
            local current = (levelNV and levelNV:IsA("IntValue") and levelNV.Value) or 0
            if current >= maxLevel then
                include = false
            end
        end
        -- RasenShuriken constraint: stop offering once level reaches card-defined maxLevel (default 5)
        if include and c.id == "Naruto_Legendary_RasenShuriken" then
            local def = c._def
            local maxLevel = 5
            if type(def) == "table" and typeof(def.maxLevel) == "number" then
                maxLevel = def.maxLevel
            end
            local runTrack = player and player:FindFirstChild("RunTrack")
            local rsFolder = runTrack and runTrack:FindFirstChild("RasenShuriken")
            local lvl = rsFolder and rsFolder:FindFirstChild("Level")
            local current = (lvl and lvl:IsA("IntValue") and lvl.Value) or 0
            if current >= maxLevel then
                include = false
            end
        end
        -- Shadow Clone constraint: stop offering once Chance reaches card-defined maxChance (default 0.5)
        if include and c.id == "Naruto_Epic_WIP" then
            local upgrades = player and player:FindFirstChild("Upgrades")
            local onKill = upgrades and upgrades:FindFirstChild("OnKill")
            local sc = onKill and onKill:FindFirstChild("ShadowClone")
            local nv = sc and sc:FindFirstChild("Chance")
            local current = (nv and nv:IsA("NumberValue")) and nv.Value or 0
            local maxChance = 0.5
            do
                local def = c._def
                if type(def) == "table" and typeof(def.maxChance) == "number" then
                    maxChance = def.maxChance
                end
            end
            if current >= maxChance then
                include = false
            end
        end
        -- Kamehameha constraint: stop offering once level reaches card-defined maxLevel (default 5)
        if include and c.id == "Goku_Legendary_Kamehameha" then
            local def = c._def
            local maxLevel = 5
            if type(def) == "table" and typeof(def.maxLevel) == "number" then
                maxLevel = def.maxLevel
            end
            local runTrack = player and player:FindFirstChild("RunTrack")
            local kFolder = runTrack and runTrack:FindFirstChild("Kamehameha")
            local lvl = kFolder and kFolder:FindFirstChild("Level")
            local current = (lvl and lvl:IsA("IntValue") and lvl.Value) or 0
            if current >= maxLevel then
                include = false
            end
        end
        -- RasenShuriken Epic variant no longer exists; no special-case needed
        -- Legendary: handled above by hasRasenLegChosen/hasRasenEpicChosen and milestone gating
        -- Global chosen-cards filter: if a card is marked unique or is one of our special uniques, and was chosen already, exclude
        if include then
            local runTrack = player and player:FindFirstChild("RunTrack")
            local chosenIds = runTrack and runTrack:FindFirstChild("ChosenCards")
            local chosenTag = chosenIds and chosenIds:FindFirstChild(c.id)
            local def = c._def
            local isSpecialUnique = (c.id == "Naruto_Epic_WIP")
            if chosenTag and chosenTag:IsA("BoolValue") and chosenTag.Value == true then
                -- Honor per-card unique flags and specific uniques like Shadow Clone
                -- Legendary rarity is cosmetic now; allow stacking legendaries like Kamehameha
                if isSpecialUnique or (type(def) == "table" and def.unique == true) then
                    include = false
                end
            end
        end
        if include then table.insert(filteredAll, c) end
    end

    -- Rarity weighting removed; pick flat from filteredAll ensuring uniqueness within the offer.
    local out = {}

    -- Consider a card stackable (can appear multiple times in the same offer) if:
    -- 1) The definition marks it stackable, or
    -- 2) It's a "stat" style card with a numeric `base` field (additive upgrade)
    local function isStackable(card)
        local def = card and card._def
        if type(def) == "table" then
            if def.stackable == true then return true end
            if typeof(def.base) == "number" then return true end
        end
        return false
    end

    -- A card is unique if def.unique == true or it's Legendary (enforced unique in one offer)
    local function isUnique(card)
        local def = card and card._def
        if type(def) == "table" and def.unique == true then return true end
        if card and card.id == "Naruto_Epic_WIP" then return true end
        if card and typeof(def) == "table" and def.source == "Equipment" then return false end
        return false
    end

    local function pickOne(list)
        if not list or #list == 0 then return nil end
        local idx = math.random(1, #list)
        return table.remove(list, idx)
    end

    local pool = table.clone(filteredAll)
    local remaining = math.max(1, count or 3)
    -- Ensure offer uniqueness unless a card is explicitly stackable
    local chosenSet = {}
    while remaining > 0 and #pool > 0 do
        local card = pickOne(pool)
        if card then
            local key = card.id
            local already = chosenSet[key]
            if not already or isStackable(card) then
                table.insert(out, card)
                chosenSet[key] = true
                remaining -= 1
            end
        end
    end
    -- Debug: print final offer
    do
        local parts = {}
        for _, c in ipairs(out) do table.insert(parts, string.format("%s(%s/%s)", c.id, c.rarity or "?", c.sourceChar or "?")) end
        dbg("Final offer: %s", table.concat(parts, ", "))
    end
    return out
end

return CardPool