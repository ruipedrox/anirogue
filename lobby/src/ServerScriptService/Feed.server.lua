-- Feed.server.lua
-- Handler server-side para a mecânica de "Feed": consumir instâncias de personagens (feeders)
-- para dar XP a um personagem principal.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")

-- Ensure Remotes folder exists (some scripts expect it early)
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
    Remotes = Instance.new("Folder")
    Remotes.Name = "Remotes"
    Remotes.Parent = ReplicatedStorage
end

local RequestFeed = Remotes:FindFirstChild("RequestFeed") or Instance.new("RemoteEvent")
RequestFeed.Name = "RequestFeed"
RequestFeed.Parent = Remotes

local FeedResult = Remotes:FindFirstChild("FeedResult") or Instance.new("RemoteEvent")
FeedResult.Name = "FeedResult"
FeedResult.Parent = Remotes

local ProfileService = require(ScriptsFolder:WaitForChild("ProfileService"))
local CharacterService = require(ScriptsFolder:WaitForChild("CharacterService"))
local CharacterCatalog = require(ScriptsFolder:WaitForChild("CharacterCatalog"))

local SharedChars = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("Chars")

local function safeRequireCharStats(templateName)
    if not SharedChars then return nil end
    local folder = SharedChars:FindFirstChild(templateName)
    if not folder then return nil end
    local statsModule = folder:FindFirstChild("Stats")
    if not statsModule or not statsModule:IsA("ModuleScript") then return nil end
    local ok, res = pcall(require, statsModule)
    if not ok or type(res) ~= "table" then return nil end
    return res
end

-- Calculate feed XP for a given instance (fallbacks to 0)
-- Feed calculation policy:
-- 1) If the character Stats module defines `FeedXP`, use that (designed feed-only chars).
-- 2) Otherwise compute the instance's total XP value (sum of XP required for past levels + current XP)
--    and apply an effectiveness multiplier (e.g. 0.5) so feeding is not 100% efficient.
local FEED_EFFECTIVENESS = 0.5
local HARD_CAP = 80
local BASE_XP = 100
local GROWTH = 1.10

local function XPRequired(level)
    if (tonumber(level) or 0) >= HARD_CAP then return 0 end
    return math.floor(BASE_XP * (GROWTH ^ ((tonumber(level) or 1) - 1)) + 0.5)
end

local function getFeedXPForInstance(inst)
    if not inst or type(inst.TemplateName) ~= "string" then return 0 end
    local template = inst.TemplateName
    -- Prefer explicit FeedXP in the character stats module (feed-only materials)
    local stats = safeRequireCharStats(template)
    local level = tonumber(inst.Level) or 1
    local curXP = tonumber(inst.XP) or 0
    -- Sum XP required for completed levels
    local total = 0
    for l = 1, (level - 1) do
        total = total + XPRequired(l)
    end
    total = total + curXP

    if stats and type(stats.FeedXP) == "number" then
        -- Use explicit FeedXP PLUS a fraction of the instance's actual XP value
        local fractional = math.floor(total * FEED_EFFECTIVENESS + 0.5)
        return math.max(0, math.floor(stats.FeedXP) + fractional)
    end

    -- Otherwise compute the cumulative XP value of the instance and apply effectiveness
    local value = math.floor(total * FEED_EFFECTIVENESS + 0.5)
    -- Fallback: if value is still zero, use a small based on stars
    if value <= 0 then
        local cat = CharacterCatalog:Get(template)
        if cat and cat.stars then value = cat.stars * 1000 end
    end
    return math.max(0, value)
end

-- Helper: is instance equipped?
local function isEquipped(profile, instanceId)
    if not profile or not profile.Characters or not profile.Characters.EquippedOrder then return false end
    for _, id in ipairs(profile.Characters.EquippedOrder) do
        if id == instanceId then return true end
    end
    return false
end

-- Main handler
RequestFeed.OnServerEvent:Connect(function(player, mainId, feederIds)
    local result = { Success = false, Message = nil, Main = nil, Removed = {} }
    -- Basic validation of args
    if type(mainId) ~= "string" or type(feederIds) ~= "table" then
        result.Message = "BadArgs"
        FeedResult:FireClient(player, result)
        return
    end

    local profile = ProfileService:Get(player)
    if not profile then
        result.Message = "NoProfile"
        FeedResult:FireClient(player, result)
        return
    end

    local mainInst = profile.Characters and profile.Characters.Instances and profile.Characters.Instances[mainId]
    if not mainInst then
        result.Message = "MainNotFound"
        FeedResult:FireClient(player, result)
        return
    end

    -- Prevent feeding if main already at cap
    if mainInst.Level and mainInst.Level >= 80 then
        result.Message = "MainAtCap"
        FeedResult:FireClient(player, result)
        return
    end

    -- Validate feeders and compute total XP
    local totalXP = 0
    local toRemove = {}
    for _, fid in ipairs(feederIds) do
        if type(fid) ~= "string" then
            result.Message = "BadFeederId"
            FeedResult:FireClient(player, result)
            return
        end
        if fid == mainId then
            result.Message = "CannotFeedSelf"
            FeedResult:FireClient(player, result)
            return
        end
        local finst = profile.Characters.Instances[fid]
        if not finst then
            result.Message = "FeederNotFound"
            FeedResult:FireClient(player, result)
            return
        end
        if isEquipped(profile, fid) then
            result.Message = "FeederEquipped"
            FeedResult:FireClient(player, result)
            return
        end
        local xp = getFeedXPForInstance(finst)
        totalXP = totalXP + xp
        table.insert(toRemove, fid)
    end

    if totalXP <= 0 then
        result.Message = "NoFeedXP"
        FeedResult:FireClient(player, result)
        return
    end

    -- Apply XP to main (CharacterService handles level ups and cap)
    local ok, err = pcall(function()
        CharacterService:AddCharacterXP(player, mainId, totalXP)
    end)
    if not ok then
        result.Message = "ApplyXPError"
        FeedResult:FireClient(player, result)
        return
    end

    -- Remove feeders from profile
    for _, fid in ipairs(toRemove) do
        profile.Characters.Instances[fid] = nil
        -- Also remove from EquippedOrder if present (shouldn't be, but safe)
        local eq = profile.Characters.EquippedOrder or {}
        for i = #eq, 1, -1 do
            if eq[i] == fid then
                table.remove(eq, i)
            end
        end
    end

    -- Build success result
    result.Success = true
    result.Message = "OK"
    local newInst = profile.Characters.Instances[mainId]
    result.Main = { Id = mainId, Level = newInst.Level or 1, XP = newInst.XP or 0 }
    result.Removed = toRemove

    -- Fire a ProfileUpdated snapshot so client UIs refresh (Equip/Chars/Inv)
    local profileUpdated = Remotes:FindFirstChild("ProfileUpdated")
    if profileUpdated and typeof(profileUpdated.FireClient) == "function" then
        pcall(function()
            profileUpdated:FireClient(player, { full = ProfileService:BuildClientSnapshot(profile) })
        end)
    end

    FeedResult:FireClient(player, result)
    print(string.format("[Feed] %s fed %d feeders to %s -> +%d XP (new L%d XP=%d)", player.Name, #toRemove, mainId, totalXP, result.Main.Level, result.Main.XP))
end)

print("[Feed.server] Loaded")
