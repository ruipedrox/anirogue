-- ProfileService.lua (ModuleScript)
-- Serviço simples de gestão de perfis (mock DataStore) + integração com AccountLeveling.
-- Futuro: substituir o mock por DataStore real com retries e locking.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")

local ProfileTemplate = require(ScriptsFolder:WaitForChild("ProfileTemplate"))
local AccountLeveling = require(ScriptsFolder:WaitForChild("AccountLeveling"))
local IdUtil = require(ScriptsFolder:WaitForChild("IdUtil"))

-- Optional: read canonical qualities / multipliers from Shared items if available
local ItemQualitiesModule = nil
local qualityList = { "rusty", "worn", "new", "polished", "perfect", "artifact" }
-- By default use uniform distribution across known qualities. We keep weight code paths for backward compatibility
local qualityWeights = nil
do
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    if shared then
        local items = shared:FindFirstChild("Items")
        if items then
            local qmod = items:FindFirstChild("ItemQualities")
            if qmod and qmod:IsA("ModuleScript") then
                local ok, qm = pcall(require, qmod)
                if ok and type(qm) == "table" then
                    ItemQualitiesModule = qm
                    -- Extract only the real quality keys (string -> number) and preserve order
                    local ordered = {}
                    for k, v in pairs(qm) do
                        if type(k) == "string" and type(v) == "number" then
                            table.insert(ordered, k)
                        end
                    end
                    -- If we found at least 3 numeric entries, prefer that ordering as the canonical qualities
                    if #ordered >= 3 then
                        qualityList = ordered
                    end
                    -- note: we keep qualityWeights default unless a specific weights table exists in module
                    if qm.Weights and type(qm.Weights) == "table" then
                        qualityWeights = qm.Weights
                    end
                end
            end
        end
    end
end

-- Validate quality utility
local function isValidQuality(q)
    if type(q) ~= "string" then return false end
    for _, name in ipairs(qualityList) do
        if name == q then return true end
    end
    return false
end

local ProfileService = {}
ProfileService._profiles = {}
ProfileService.Version = 1
ProfileService._storeName = "AniRogue_Profiles_v2"
ProfileService._store = nil

local function getStore()
    if not ProfileService._store then
        ProfileService._store = DataStoreService:GetDataStore(ProfileService._storeName)
    end
    return ProfileService._store
end

local function dsRetry(fn, max)
    max = max or 5
    local lastErr
    for i=1,max do
        local ok, res = pcall(fn)
        if ok then return true, res end
        lastErr = res
        task.wait(0.5 * i)
    end
    return false, lastErr
end

local function profileKeyForUserId(userId)
    return string.format("u_%d", tonumber(userId) or 0)
end

-- Deep copy util
local function deepCopy(tbl)
    if type(tbl) ~= "table" then return tbl end
    local t = {}
    for k,v in pairs(tbl) do
        if type(v) == "table" then
            v = deepCopy(v)
        end
        t[k] = v
    end
    return t
end

local function buildDefaultProfile()
    return deepCopy(ProfileTemplate)
end

-- Deduplicate characters: remove unintended duplicates of the same TemplateName when safe
local function dedupeCharacterInstances(profile)
    if not profile or not profile.Characters or not profile.Characters.Instances then return end
    local instances = profile.Characters.Instances
    local equippedSet = {}
    for _, id in ipairs(profile.Characters.EquippedOrder or {}) do
        equippedSet[id] = true
    end
    -- Group by TemplateName
    local byTemplate = {}
    for id, inst in pairs(instances) do
        local tpl = inst and inst.TemplateName or ""
        if tpl ~= "" then
            local g = byTemplate[tpl]
            if not g then g = {} byTemplate[tpl] = g end
            table.insert(g, { id = id, level = tonumber(inst.Level) or 1, xp = tonumber(inst.XP) or 0, tier = tostring(inst.Tier or "B-") })
        end
    end
    local seeds = { Goku_3 = true, Naruto_3 = true }
    local removed = 0
    for tpl, list in pairs(byTemplate) do
        if #list > 1 then
            -- Keep equipped ones and the best one (highest level/xp). Remove safe duplicates (level 1, xp 0) not equipped
            table.sort(list, function(a,b)
                if a.level ~= b.level then return a.level > b.level end
                return a.xp > b.xp
            end)
            local keep = {}
            for _, entry in ipairs(list) do
                if equippedSet[entry.id] then keep[entry.id] = true end
            end
            -- Always keep the top one
            if list[1] then keep[list[1].id] = true end
            for i = 1, #list do
                local e = list[i]
                if not keep[e.id] then
                    local isSeedTpl = seeds[tpl] == true
                    local safeToRemove = (e.level <= 1 and e.xp <= 0)
                    if isSeedTpl and safeToRemove then
                        instances[e.id] = nil
                        removed += 1
                    end
                end
            end
        end
    end
    if removed > 0 then
        warn(string.format("[ProfileService] Dedupe removed %d duplicate seed instances", removed))
    end
end

-- ===== Story progression helpers =====
local function loadStoryMaps()
    local RS = game:GetService("ReplicatedStorage")
    local Shared = RS:FindFirstChild("Shared")
    if not Shared then return {} end
    local Maps = Shared:FindFirstChild("Maps")
    if not Maps then return {} end
    local Story = Maps:FindFirstChild("Story")
    if not Story then return {} end
    local mapsList = {}
    for _, folder in ipairs(Story:GetChildren()) do
        if folder:IsA("Folder") then
            local mod = folder:FindFirstChild("Map")
            if mod and mod:IsA("ModuleScript") then
                local okMap, map = pcall(function() return require(mod) end)
                if okMap and type(map) == "table" then
                    table.insert(mapsList, map)
                end
            end
        end
    end
    table.sort(mapsList, function(a,b)
        local ao = tonumber(a.SortOrder) or math.huge
        local bo = tonumber(b.SortOrder) or math.huge
        if ao ~= bo then return ao < bo end
        local ad = tostring(a.DisplayName or a.Id or "")
        local bd = tostring(b.DisplayName or b.Id or "")
        return ad:lower() < bd:lower()
    end)
    return mapsList
end

local function ensureStoryStructure(profile)
    profile.Story = profile.Story or {}
    profile.Story.Maps = profile.Story.Maps or {}
    -- Ensure first map unlocked to Level 1 by default
    local list = loadStoryMaps()
    local firstId = list[1] and (list[1].Id or list[1].DisplayName)
    if firstId then
        local mp = profile.Story.Maps[firstId]
        if not mp then mp = { MaxUnlockedLevel = 0, LevelsCompleted = {} } profile.Story.Maps[firstId] = mp end
        if (mp.MaxUnlockedLevel or 0) < 1 then mp.MaxUnlockedLevel = 1 end
    end
    -- Auto-backfill: if player has completed L3 of a map, ensure the next map is unlocked to L1
    for i = 1, math.max(0, (#list - 1)) do
        local curr = list[i]
        local nextm = list[i + 1]
        local currId = curr and (curr.Id or curr.DisplayName)
        local nextId = nextm and (nextm.Id or nextm.DisplayName)
        if currId and nextId then
            local cent = profile.Story.Maps[currId]
            if cent and cent.LevelsCompleted and cent.LevelsCompleted[3] == true then
                local nent = profile.Story.Maps[nextId]
                if not nent then
                    nent = { MaxUnlockedLevel = 0, LevelsCompleted = {} }
                    profile.Story.Maps[nextId] = nent
                end
                if (nent.MaxUnlockedLevel or 0) < 1 then
                    nent.MaxUnlockedLevel = 1
                end
            end
        end
    end
    return list
end

-- Ensure stackable Drops structure (e.g., evolve items like headband)
local function ensureDropsStructure(profile)
    profile.Drops = profile.Drops or {}
    profile.Drops.evolve = profile.Drops.evolve or {}
    return profile.Drops
end

local function buildStorySnapshot(profile)
    local list = loadStoryMaps()
    local order = {}
    for _, m in ipairs(list) do order[#order+1] = m.Id or m.DisplayName end
    return {
        Maps = deepCopy(profile.Story and profile.Story.Maps or {}),
        Order = order,
        FirstMapId = order[1],
    }
end

function ProfileService:GetStorySnapshot(player)
    local profile = self._profiles[player]
    if not profile then return { error = "NoProfile" } end
    ensureStoryStructure(profile)
    return buildStorySnapshot(profile)
end

function ProfileService:MarkStoryLevelCompleted(player, mapId, level)
    if type(mapId) ~= "string" or type(level) ~= "number" then return false, "BadArgs" end
    local profile = self._profiles[player]
    if not profile then return false, "NoProfile" end
    ensureStoryStructure(profile)
    profile.Story.Maps[mapId] = profile.Story.Maps[mapId] or { MaxUnlockedLevel = 0, LevelsCompleted = {} }
    local entry = profile.Story.Maps[mapId]
    entry.LevelsCompleted = entry.LevelsCompleted or {}
    entry.LevelsCompleted[level] = true
    local maxU = tonumber(entry.MaxUnlockedLevel) or 0
    if level < 3 then
        if maxU < (level + 1) then entry.MaxUnlockedLevel = level + 1 end
    else
        -- Completed level 3: unlock next map's level 1 if exists
        local list = loadStoryMaps()
        local idxById = {}
        for i, m in ipairs(list) do idxById[m.Id or m.DisplayName] = i end
        local idx = idxById[mapId]
        if idx and list[idx + 1] then
            local nextId = list[idx + 1].Id or list[idx + 1].DisplayName
            local n = profile.Story.Maps[nextId]
            if not n then n = { MaxUnlockedLevel = 0, LevelsCompleted = {} } profile.Story.Maps[nextId] = n end
            if (n.MaxUnlockedLevel or 0) < 1 then n.MaxUnlockedLevel = 1 end
        end
    end
    return true, buildStorySnapshot(profile)
end

-- Migração Items Owned para modelo de instâncias (Version >=2)
local function migrateEquipmentToInstances(profile)
    if not profile.Items then return end
    if not profile.Items.Owned then return end

    local categories = { "Weapons", "Armors", "Rings" }
    local changed = false
    for _, cat in ipairs(categories) do
        local catTbl = profile.Items.Owned[cat]
        if catTbl and not catTbl.Instances then
            -- Detecta formato antigo: chaves são templates -> { Level = X }
            local newInstances = {}
            -- helper: pick random quality (weighted)
                    local function pickRandomQuality()
                                -- uniform pick among qualityList
                                local idx = math.random(1, #qualityList)
                                return qualityList[idx]
                            end

            for templateName, data in pairs(catTbl) do
                if templateName ~= "Instances" then
                    local instId = IdUtil:GenerateInstanceId(templateName)
                    local q = (type(data) == "table" and data.Quality)
                    if q == nil or (type(q) == "string" and q:match("^%s*$")) then
                        q = pickRandomQuality()
                        warn(string.format("[ProfileService] migrate: assigned random Quality '%s' to migrated item %s (template=%s)", tostring(q), tostring(instId), tostring(templateName)))
                    elseif not isValidQuality(q) then
                        -- Someone (or a module) may have injected a non-quality key like a Colors table
                        warn(string.format("[ProfileService] migrate: invalid Quality value '%s' on migrated item %s (template=%s) - replacing with random quality", tostring(q), tostring(instId), tostring(templateName)))
                        q = pickRandomQuality()
                    end
                    newInstances[instId] = {
                        Template = templateName,
                        Level = (type(data)=="table" and data.Level) or 1,
                        Quality = q,
                    }
                end
            end
            profile.Items.Owned[cat] = { Instances = newInstances }
            changed = true
        end
    end

    -- Atualizar referências Equipped se ainda apontarem para template names
    if profile.Items.Equipped then
        local mapTemplateToInstance = {}
        for _, cat in ipairs(categories) do
            local catTbl = profile.Items.Owned[cat]
            if catTbl and catTbl.Instances then
                for instId, instData in pairs(catTbl.Instances) do
                    if instData.Template and not mapTemplateToInstance[instData.Template] then
                        mapTemplateToInstance[instData.Template] = instId
                    end
                end
            end
        end
        -- Campos esperados: Weapon, Armor, Ring
        for key, val in pairs(profile.Items.Equipped) do
            if val and mapTemplateToInstance[val] then
                profile.Items.Equipped[key] = mapTemplateToInstance[val]
                changed = true
            end
        end
    end
    return changed
end


-- Public API: grant an item instance to a player's profile (assigns random quality if not provided)
-- category should be one of: "Weapons","Armors","Rings" (accept singular too)
function ProfileService:AddItem(player, category, templateName, opts)
    if type(category) ~= "string" or type(templateName) ~= "string" then return nil, "BadArgs" end
    local profile = self._profiles[player]
    if not profile then return nil, "NoProfile" end
    local cat = category
    if cat == "Weapon" then cat = "Weapons" end
    if cat == "Armor" then cat = "Armors" end
    if cat == "Ring" then cat = "Rings" end
    -- Ensure item structures are migrated/initialized so we never index nil
    profile.Items = profile.Items or {}
    profile.Items.Owned = profile.Items.Owned or {}
    -- Run category migration in case this profile still uses the old Owned->template format
    -- migrateEquipmentToInstances will convert categories that lack an Instances table
    pcall(function() migrateEquipmentToInstances(profile) end)
    -- Defensive fallback: ensure the category table and Instances map exist
    if type(profile.Items.Owned[cat]) ~= "table" then
        profile.Items.Owned[cat] = { Instances = {} }
    elseif profile.Items.Owned[cat].Instances == nil then
        profile.Items.Owned[cat].Instances = {}
    end
    local instances = profile.Items.Owned[cat].Instances
    local id = IdUtil:GenerateInstanceId(templateName)
    local level = (opts and opts.Level) or 1
    local quality = (opts and opts.Quality)
    if quality == nil or (type(quality) == "string" and quality:match("^%s*$")) then
        quality = qualityList[math.random(1, #qualityList)]
        warn(string.format("[ProfileService] AddItem: assigned random Quality '%s' to new instance %s (template=%s)", tostring(quality), tostring(id), tostring(templateName)))
    elseif not isValidQuality(quality) then
        warn(string.format("[ProfileService] AddItem: provided Quality '%s' is invalid - replacing with random quality for new instance %s (template=%s)", tostring(quality), tostring(id), tostring(templateName)))
        quality = qualityList[math.random(1, #qualityList)]
    end
    instances[id] = { Template = templateName, Level = level, Quality = quality }
    return id
end

function ProfileService:Get(player)
    return self._profiles[player]
end

function ProfileService:CreateOrLoad(player)
    -- Load from DataStore or create new
    local key = profileKeyForUserId(player.UserId)
    local loaded
    local ok, res = dsRetry(function()
        return getStore():GetAsync(key)
    end)
    if ok and type(res) == "table" then
        loaded = res
    end
    local profile = loaded or buildDefaultProfile()
    if profile.Version ~= self.Version then
        profile.Version = self.Version
    end
    AccountLeveling:EnsureStructure(profile)

    -- Migração para Version >=2 (itens per-instância)
    if (profile.Version or 1) >= 2 then
        local migrated = migrateEquipmentToInstances(profile)
        if migrated then
            print("[ProfileService] Migração equipment -> Instances aplicada para jogador", player.Name)
        end
    end

    -- SEED DEFAULTS ONLY IF EMPTY: evitar sobrescrever perfis existentes
    local instCount = 0
    for _ in pairs(profile.Characters.Instances) do instCount += 1 end
    if instCount == 0 then
        -- Criar 2 instâncias seed apenas para perfis novos
        local seeds = { "Goku_3", "Naruto_3" }
        local newOrder = {}
        for _, templateName in ipairs(seeds) do
            local newId = IdUtil:GenerateInstanceId(templateName)
            profile.Characters.Instances[newId] = { TemplateName = templateName, Level = 1, XP = 0, Tier = "B-" }
            table.insert(newOrder, newId)
            -- garantir desbloqueio
            local unlocked = profile.Characters.UnlockedTemplates
            local found = false
            for _, t in ipairs(unlocked) do if t == templateName then found = true break end end
            if not found then table.insert(unlocked, templateName) end
        end
        profile.Characters.EquippedOrder = newOrder
    end

    -- One-time cleanup: remove duplicate seed characters accidentally created previously
    pcall(function() dedupeCharacterInstances(profile) end)

    -- Sanitizar EquippedOrder: remover ids inválidos, placeholders e duplicados; não forçar templates
    do
        local order = profile.Characters.EquippedOrder or {}
        local maxSlots = AccountLeveling:GetAllowedEquipSlots(profile.Account.Level)
        local seen = {}
        local cleaned = {}
        for _, id in ipairs(order) do
            if type(id) == "string" and id ~= "" and id ~= "_EMPTY_" then
                local inst = profile.Characters.Instances[id]
                if inst and not seen[id] then
                    table.insert(cleaned, id)
                    seen[id] = true
                    if #cleaned >= maxSlots then break end
                end
            end
        end
        -- Se após limpeza não houver nada equipado, escolher até maxSlots quaisquer instâncias distintas por display (opcional)
        if #cleaned == 0 then
            local usedDisplay = {}
            for instId, inst in pairs(profile.Characters.Instances) do
                local display = inst.TemplateName
                if not usedDisplay[display] then
                    table.insert(cleaned, instId)
                    usedDisplay[display] = true
                    if #cleaned >= maxSlots then break end
                end
            end
        end
        profile.Characters.EquippedOrder = cleaned
    end
    -- Ensure Drops bag exists
    pcall(function() ensureDropsStructure(profile) end)
    -- Ensure Meta structure for applied runs (idempotency marker)
    profile.Meta = profile.Meta or {}
    profile.Meta.AppliedRuns = profile.Meta.AppliedRuns or {}

    self._profiles[player] = profile
    -- Ensure Story structure and default unlocks
    pcall(function() ensureStoryStructure(profile) end)
    return profile
end

function ProfileService:Save(player)
    local profile = self._profiles[player]
    if not profile then return false, "NoProfile" end
    local key = profileKeyForUserId(player.UserId)
    local ok, err = dsRetry(function()
        return getStore():SetAsync(key, profile)
    end)
    if not ok then
        warn("[ProfileService] Save failed for", player.UserId, err)
        return false, err
    end
    return true
end

function ProfileService:Remove(player)
    -- Save on removal then clear
    pcall(function() self:Save(player) end)
    self._profiles[player] = nil
end

function ProfileService:ApplyAccountDelta(player, delta)
    local profile = self._profiles[player]
    if not profile then return end
    local acc = profile.Account
    local xpAdd = 0
    for k, v in pairs(delta) do
        if k == "XP" then
            xpAdd += tonumber(v) or 0
        elseif type(v) == "number" and acc[k] ~= nil then
            acc[k] = acc[k] + v
        end
    end
    if xpAdd > 0 then
        AccountLeveling:AddXP(profile, xpAdd)
    end
    return profile
end

-- Add stackable drop item into profile.Drops[category][id] += quantity
function ProfileService:AddDropItem(player, category, id, quantity)
    if type(category) ~= "string" or category == "" then return false, "BadCategory" end
    if type(id) ~= "string" or id == "" then return false, "BadId" end
    quantity = tonumber(quantity) or 0
    if quantity <= 0 then return false, "NoQty" end
    local profile = self._profiles[player]
    if not profile then return false, "NoProfile" end
    profile.Drops = profile.Drops or {}
    profile.Drops[category] = profile.Drops[category] or {}
    local bag = profile.Drops[category]
    bag[id] = (tonumber(bag[id]) or 0) + quantity
    return true
end

-- Atualiza o recorde de wave infinita se o novo valor for maior
function ProfileService:SetHighInfWave(player, wave)
    wave = tonumber(wave) or 0
    if wave <= 0 then return false, "wave<=0" end
    local profile = self._profiles[player]
    if not profile then return false, "no_profile" end
    local acc = profile.Account
    if (acc.HighInfWave or 0) < wave then
        acc.HighInfWave = wave
        return true
    end
    return false, "not_higher"
end

function ProfileService:BuildClientSnapshot(profile)
    local instList = {}
    local charCount = 0
    for instId, data in pairs(profile.Characters.Instances) do
        instList[#instList+1] = {
            Id = instId,
            Template = data.TemplateName,
            Level = data.Level,
            XP = data.XP,
            Tier = data.Tier or "B-",
        }
        charCount += 1
    end
    -- Converter Items Owned (novo modelo) em estrutura amigável para o cliente:
    -- Para cada categoria (Weapons/Armors/Rings) fornecer:
    --   List = { {Id=..., Template=..., Level=...}, ... }
    --   Equipped = instanceId ou nil
    local itemsSnapshot = {}
    local owned = profile.Items and profile.Items.Owned or {}
    local equipped = profile.Items and profile.Items.Equipped or {}
    for categoryName, categoryTable in pairs(owned) do
        local list = {}
        if type(categoryTable) == "table" then
            if categoryTable.Instances then
                for instId, instData in pairs(categoryTable.Instances) do
                    -- Garantir Quality default se ausente
                        if instData then
                        if instData.Quality == nil or (type(instData.Quality) == "string" and instData.Quality:match("^%s*$")) then
                            warn(string.format("[ProfileService] BuildClientSnapshot: fixing blank Quality for inst=%s template=%s", tostring(instId), tostring(instData.Template)))
                            instData.Quality = "rusty"
                        elseif not isValidQuality(instData.Quality) then
                            warn(string.format("[ProfileService] BuildClientSnapshot: invalid Quality '%s' for inst=%s template=%s - replacing with 'rusty'", tostring(instData.Quality), tostring(instId), tostring(instData.Template)))
                            instData.Quality = "rusty"
                        end
                        list[#list+1] = {
                            Id = instId,
                            Template = instData.Template,
                            Level = instData.Level or 1,
                            Quality = instData.Quality or "rusty",
                        }
                    end
                end
            else
                -- Fallback (modelo antigo sem migração): as chaves são templates
                for templateName, data in pairs(categoryTable) do
                    local q = (type(data)=="table" and data.Quality) or "rusty"
                    list[#list+1] = {
                        Id = templateName, -- sem instancia única
                        Template = templateName,
                        Level = (type(data)=="table" and data.Level) or 1,
                        Quality = q,
                    }
                end
            end
        end
        table.sort(list, function(a,b)
            if a.Template == b.Template then return a.Id < b.Id end
            return a.Template < b.Template
        end)
        itemsSnapshot[categoryName] = {
            List = list,
            Equipped = equipped and equipped[string.sub(categoryName,1,#categoryName-1)] or nil -- tentativa fraca; cliente pode usar Items.Equipped também
        }
    end

    return {
        Version = profile.Version,
        Account = AccountLeveling:GetSnapshot(profile),
        Characters = {
            EquippedOrder = profile.Characters.EquippedOrder,
            Count = #profile.Characters.EquippedOrder,
            CurrentCount = charCount,
            Capacity = profile.Characters.Capacity or 50,
            UnlockedCount = #profile.Characters.UnlockedTemplates,
            Instances = instList,
        },
        Items = {
            Owned = deepCopy(profile.Items.Owned or {}), -- manter envio raw (retro compat) se UI antiga depender
            Equipped = deepCopy(profile.Items.Equipped or {}),
            Categories = itemsSnapshot, -- novo formato já estruturado
        },
        Drops = deepCopy(profile.Drops or {}),
        HighInfWave = profile.Account.HighInfWave or 0,
    }
end


-- Equip/Unequip API
-- category should be "Weapons"/"Armors"/"Rings" (singular accepted)
function ProfileService:EquipItem(player, instanceId)
    if not instanceId then return false, "BadArgs" end
    local profile = self._profiles[player]
    if not profile then return false, "NoProfile" end
    -- Ensure Owned map exists
    profile.Items = profile.Items or {}
    profile.Items.Owned = profile.Items.Owned or {}
    profile.Items.Equipped = profile.Items.Equipped or {}
    -- Ensure legacy formats (template keys) are migrated to Instances map
    pcall(function() migrateEquipmentToInstances(profile) end)
    -- Find which category the instance belongs to
    local categories = { Weapons = true, Armors = true, Rings = true }
    -- First try exact instance id lookup
    for catName, _ in pairs(profile.Items.Owned) do
        local cat = profile.Items.Owned[catName]
        if cat and cat.Instances and cat.Instances[instanceId] then
            local singular = string.sub(catName, 1, #catName-1)
            profile.Items.Equipped = profile.Items.Equipped or {}
            profile.Items.Equipped[singular] = instanceId
            return true
        end
    end
    -- Fallback: maybe client sent a template name instead of an instance id
    -- Search Instances for a matching Template field equal to the provided instanceId string
    if type(instanceId) == "string" then
        for catName, _ in pairs(profile.Items.Owned) do
            local cat = profile.Items.Owned[catName]
            if cat and cat.Instances then
                for instId, instData in pairs(cat.Instances) do
                    if instData and instData.Template == instanceId then
                        local singular = string.sub(catName, 1, #catName-1)
                        profile.Items.Equipped = profile.Items.Equipped or {}
                        profile.Items.Equipped[singular] = instId
                        return true
                    end
                end
            end
        end
        -- Diagnostic: print Owned structure and Templates to help debug client/server mismatch
        warn(string.format("[ProfileService][EquipItem] Fallback search failed for '%s' - Owned categories:", tostring(instanceId)))
        for catName, cat in pairs(profile.Items.Owned) do
            if cat and cat.Instances then
                for instId, instData in pairs(cat.Instances) do
                    warn(string.format("  cat=%s instId=%s Template=%s", tostring(catName), tostring(instId), tostring(instData and instData.Template)))
                end
            else
                warn(string.format("  cat=%s has no Instances (legacy format?)", tostring(catName)))
            end
        end
    end
    return false, "NotFound"
end

function ProfileService:UnequipItem(player, slotName)
    if type(slotName) ~= "string" then return false, "BadArgs" end
    local profile = self._profiles[player]
    if not profile then return false, "NoProfile" end
    profile.Items = profile.Items or {}
    profile.Items.Equipped = profile.Items.Equipped or {}
    -- Accept singular names Weapon/Armor/Ring
    if profile.Items.Equipped[slotName] then
        profile.Items.Equipped[slotName] = nil
        return true
    end
    return false, "NotEquipped"
end

print("[ProfileService] Module loaded")
return ProfileService
