-- Evolve.server.lua
-- Server-side handler for evolving characters: consumes copies, materials and gold

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")

-- Ensure Remotes folder exists
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
    Remotes = Instance.new("Folder")
    Remotes.Name = "Remotes"
    Remotes.Parent = ReplicatedStorage
end

local RequestEvolve = Remotes:FindFirstChild("RequestEvolve") or Instance.new("RemoteEvent")
RequestEvolve.Name = "RequestEvolve"
RequestEvolve.Parent = Remotes

local EvolveResult = Remotes:FindFirstChild("EvolveResult") or Instance.new("RemoteEvent")
EvolveResult.Name = "EvolveResult"
EvolveResult.Parent = Remotes

local ProfileService = require(ScriptsFolder:WaitForChild("ProfileService"))
local CharacterCatalog = require(ScriptsFolder:WaitForChild("CharacterCatalog"))
local CharacterService = require(ScriptsFolder:WaitForChild("CharacterService"))
local MissionsService = require(ScriptsFolder:WaitForChild("MissionsService"))
local CharacterTiers = require(ScriptsFolder:WaitForChild("CharacterTiers"))

local SharedChars = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("Chars")

local function safeRequireCharModule(templateName, moduleName)
    if not SharedChars then return nil end
    local folder = SharedChars:FindFirstChild(templateName)
    if not folder then return nil end
    local m = folder:FindFirstChild(moduleName)
    if not m or not m:IsA("ModuleScript") then return nil end
    local ok, res = pcall(require, m)
    if not ok or type(res) ~= "table" then return nil end
    return res
end

local function normalizeMaterialId(name)
    if type(name) ~= "string" then return nil end
    -- Convert CamelCase or spaced names to snake_case lower
    local s = name:gsub("%s+","_")
    s = s:gsub("(%l)(%u)", "%1_%2")
    s = s:gsub("[^%w_]","_")
    s = s:lower()
    return s
end

local function hasEnoughMaterials(profile, reqs)
    local missing = {}
    local bag = (profile.Drops and profile.Drops.evolve) or {}
    for _, r in ipairs(reqs or {}) do
        local k = normalizeMaterialId(r.template or "")
        local need = tonumber(r.count) or 0
        local have = tonumber(bag[k]) or 0
        if have < need then
            table.insert(missing, { template = r.template, have = have, need = need, key = k })
        end
    end
    return (#missing == 0), missing
end

local function consumeMaterials(profile, reqs)
    local bag = profile.Drops or {}
    bag.evolve = bag.evolve or {}
    for _, r in ipairs(reqs or {}) do
        local k = normalizeMaterialId(r.template or "")
        local need = tonumber(r.count) or 0
        bag.evolve[k] = (tonumber(bag.evolve[k]) or 0) - need
        if bag.evolve[k] <= 0 then bag.evolve[k] = nil end
    end
    profile.Drops = bag
end

local function isEquipped(profile, instanceId)
    if not profile or not profile.Characters or not profile.Characters.EquippedOrder then return false end
    for _, id in ipairs(profile.Characters.EquippedOrder) do
        if id == instanceId then return true end
    end
    return false
end

RequestEvolve.OnServerEvent:Connect(function(player, mainId, sacrificeIds)
    local res = { Success = false, Message = nil, Main = nil, Removed = {}, Materials = {} }
    if type(mainId) ~= "string" or type(sacrificeIds) ~= "table" then
        res.Message = "BadArgs"
        EvolveResult:FireClient(player, res)
        return
    end

    local profile = ProfileService:Get(player)
    if not profile then
        res.Message = "NoProfile"
        EvolveResult:FireClient(player, res)
        return
    end

    local mainInst = profile.Characters and profile.Characters.Instances and profile.Characters.Instances[mainId]
    if not mainInst then
        res.Message = "MainNotFound"
        EvolveResult:FireClient(player, res)
        return
    end

    -- Ensure a char stats module allows evolving
    local stats = safeRequireCharModule(mainInst.TemplateName or "", "Stats")
    if stats and stats.can_evolve == false then
        res.Message = "CannotEvolve"
        EvolveResult:FireClient(player, res)
        return
    end

    -- Load Evolve rules
    local evolveRules = safeRequireCharModule(mainInst.TemplateName or "", "Evolve")
    if not evolveRules or type(evolveRules.evolve_to) ~= "string" then
        res.Message = "NoEvolveRule"
        EvolveResult:FireClient(player, res)
        return
    end

    local required_level = tonumber(evolveRules.required_level) or 1
    if tonumber(mainInst.Level) < required_level then
        res.Message = "MainLevelTooLow"
        EvolveResult:FireClient(player, res)
        return
    end

    -- Check gold cost
    if evolveRules.cost and type(evolveRules.cost.Gold) == "number" then
        local have = (profile.Account and tonumber(profile.Account.Coins)) or 0
        if have < evolveRules.cost.Gold then
            res.Message = "NotEnoughGold"
            EvolveResult:FireClient(player, res)
            return
        end
    end

    -- Validate materials
    local okMat, missing = hasEnoughMaterials(profile, evolveRules.materials_req or {})
    if not okMat then
        res.Message = "NotEnoughMaterials"
        res.Missing = missing
        EvolveResult:FireClient(player, res)
        return
    end

    -- Validate copies: ensure sacrificeIds supplied satisfy copies_req
    local copiesReq = evolveRules.copies_req or {}
    local requiredByTemplate = {}
    local totalRequired = 0
    for _, cr in ipairs(copiesReq) do
        local tpl = tostring(cr.template or "")
        local cnt = tonumber(cr.count) or 0
        requiredByTemplate[tpl] = (requiredByTemplate[tpl] or 0) + cnt
        totalRequired = totalRequired + cnt
    end

    -- Quick check: sacrificeIds length must be at least totalRequired
    if #sacrificeIds < totalRequired then
        res.Message = "NotEnoughCopiesSelected"
        EvolveResult:FireClient(player, res)
        return
    end

    -- Validate each supplied sacrifice id
    local toRemove = {}
    local countsSeen = {}
    for _, sid in ipairs(sacrificeIds) do
        if type(sid) ~= "string" then
            res.Message = "BadSacrificeId"
            EvolveResult:FireClient(player, res)
            return
        end
        if sid == mainId then
            res.Message = "CannotSacrificeMain"
            EvolveResult:FireClient(player, res)
            return
        end
        local sinst = profile.Characters.Instances[sid]
        if not sinst then
            res.Message = "SacrificeNotFound"
            EvolveResult:FireClient(player, res)
            return
        end
        if evolveRules.forbid_equipped_sacrifice and isEquipped(profile, sid) then
            res.Message = "SacrificeEquipped"
            EvolveResult:FireClient(player, res)
            return
        end
        -- Count toward required template quotas
        countsSeen[sinst.TemplateName] = (countsSeen[sinst.TemplateName] or 0) + 1
        table.insert(toRemove, sid)
    end

    -- Ensure countsSeen satisfy requiredByTemplate
    for tpl, need in pairs(requiredByTemplate) do
        if (countsSeen[tpl] or 0) < need then
            res.Message = "SelectedCopiesMismatch"
            res.Required = { template = tpl, need = need, got = countsSeen[tpl] or 0 }
            EvolveResult:FireClient(player, res)
            return
        end
    end

    -- All validations passed. Apply changes atomically inside pcall
    local ok, err = pcall(function()
        -- Deduct gold
        if evolveRules.cost and type(evolveRules.cost.Gold) == "number" then
            profile.Account = profile.Account or {}
            profile.Account.Coins = (profile.Account.Coins or 0) - evolveRules.cost.Gold
        end

        -- Consume materials
        consumeMaterials(profile, evolveRules.materials_req or {})

        -- Remove sacrifice instances
        for _, sid in ipairs(toRemove) do
            profile.Characters.Instances[sid] = nil
            -- also scrub from EquippedOrder if present
            local eq = profile.Characters.EquippedOrder or {}
            for i = #eq, 1, -1 do
                if eq[i] == sid then table.remove(eq, i) end
            end
        end

        -- Update main template
        local oldTemplate = mainInst.TemplateName
        mainInst.TemplateName = evolveRules.evolve_to

        -- Carry over XP if requested (by leaving Level/XP as-is we already carried it)
        if evolveRules.carry_over_xp then
            -- nothing extra required, keep Level and XP
        else
            -- reset progress if not carrying XP
            mainInst.Level = 1
            mainInst.XP = 0
        end

        -- Increase Potential expressed as Tier steps (advance tier up to SSS)
        if type(evolveRules.potential_increase) == "number" then
            mainInst.Tier = mainInst.Tier or "B-"
            for i = 1, evolveRules.potential_increase do
                local nextTier = CharacterTiers:GetNextTier(mainInst.Tier)
                if not nextTier then break end
                mainInst.Tier = nextTier
            end
        end

        -- Increment missions/analytics
        pcall(function() MissionsService:IncrementEvolves(profile) end)

        -- Build result
        res.Success = true
        res.Message = "OK"
        res.Main = { Id = mainId, Template = mainInst.TemplateName, Level = mainInst.Level or 1, XP = mainInst.XP or 0 }
        res.Removed = toRemove
        res.Materials = evolveRules.materials_req or {}
    end)

    if not ok then
        res.Success = false
        res.Message = "ApplyError"
        EvolveResult:FireClient(player, res)
        return
    end

    -- Fire snapshot and result
    local profileUpdated = Remotes:FindFirstChild("ProfileUpdated")
    if profileUpdated and typeof(profileUpdated.FireClient) == "function" then
        pcall(function()
            profileUpdated:FireClient(player, { full = ProfileService:BuildClientSnapshot(profile) })
        end)
    end

    -- Persist
    pcall(function() ProfileService:Save(player) end)

    EvolveResult:FireClient(player, res)
    print(string.format("[Evolve] %s evolved %s -> %s, removed %d objects", player.Name, tostring(mainId), tostring(evolveRules.evolve_to), #res.Removed))
end)

print("[Evolve.server] Loaded")
