local HttpService = game:GetService("HttpService")

local BannerManager = {}

function BannerManager:UpdateReplicatedBanner(banner)
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local bannerValue = ReplicatedStorage:FindFirstChild("CurrentBanner")
    if not bannerValue then
        bannerValue = Instance.new("StringValue")
        bannerValue.Name = "CurrentBanner"
        bannerValue.Parent = ReplicatedStorage
    end
    bannerValue.Value = HttpService:JSONEncode(banner)
end
-- BannerManager.module.lua
-- Always generate and broadcast a new banner on startup
-- Responsibilities:
--  - Generate periodic banners (using the canonical CharacterCatalog)
--  - Persist current banner to DataStore
--  - Publish updates to other servers via MessagingService
--  - Fire ReplicatedStorage.Remotes.BannerUpdated to clients

local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- We'll build pools dynamically from the game's CharacterCatalog (canonical source)
local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")
local CharacterCatalog = nil
local okCat, catMod = pcall(function()
    return require(ScriptsFolder:WaitForChild("CharacterCatalog"))
end)
if okCat and catMod then
    CharacterCatalog = catMod
else
    warn("[BannerManager] Could not require CharacterCatalog; banner randomization will be limited.")
end

-- BannerManager já definido no topo, não redefinir!
-- local BannerManager = {}
local DATASTORE_NAME = "GlobalBanners"
local KEY = "current_banner"
local MESSAGE_TOPIC = "BannerUpdated_v1"

local ds = DataStoreService:GetDataStore(DATASTORE_NAME)

local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "Remotes"
    remotesFolder.Parent = ReplicatedStorage
end

local bannerEvent = remotesFolder:FindFirstChild("BannerUpdated")
if not bannerEvent then
    bannerEvent = Instance.new("RemoteEvent")
    bannerEvent.Name = "BannerUpdated"
    bannerEvent.Parent = remotesFolder
end

local function safePublish(payload)
    local attempts = 0
    local maxAttempts = 3
    local delaySecs = 1
    while attempts < maxAttempts do
        attempts = attempts + 1
        local ok, err = pcall(function()
            MessagingService:PublishAsync(MESSAGE_TOPIC, payload)
        end)
        if ok then return true end
        warn("[BannerManager] Publish attempt", attempts, "failed:", err)
        wait(delaySecs)
        delaySecs = delaySecs * 2
    end
    warn("[BannerManager] Publish failed after attempts")
    return false
end

function BannerManager:Broadcast(banner)
    -- Fire to local clients
    local ok, err = pcall(function()
        bannerEvent:FireAllClients(banner)
    end)
    if not ok then warn("[BannerManager] FireAllClients failed:", err) end

    -- Publish so other servers pick up
    local payload = { banner = banner }
    safePublish(payload)
end

function BannerManager:Save(banner)
    local attempts = 0
    local maxAttempts = 3
    local delaySecs = 1
    while attempts < maxAttempts do
        attempts = attempts + 1
        local ok, err = pcall(function()
            ds:SetAsync(KEY, banner)
        end)
        if ok then return true end
        warn("[BannerManager] Save attempt", attempts, "failed:", err)
        wait(delaySecs)
        delaySecs = delaySecs * 2
    end
    warn("[BannerManager] Save failed after attempts")
    return false
end

function BannerManager:Load()
    local attempts = 0
    local maxAttempts = 3
    local delaySecs = 1
    while attempts < maxAttempts do
        attempts = attempts + 1
        local ok, res = pcall(function()
            return ds:GetAsync(KEY)
        end)
        if ok then return res end
        warn("[BannerManager] Load attempt", attempts, "failed:", res)
        wait(delaySecs)
        delaySecs = delaySecs * 2
    end
    warn("[BannerManager] Load failed after attempts")
    return nil
end

-- Generate-and-publish helper (used by scheduler and admin)
-- Sample n unique elements from a table (array of ids)
local function sampleUnique(arr, n)
    local copy = {}
    for i,v in ipairs(arr) do copy[i] = v end
    local res = {}
    if n >= #copy then
        for i=1,#copy do table.insert(res, copy[i]) end
        return res
    end
    for i=1,n do
        local idx = math.random(1, #copy)
        table.insert(res, copy[idx])
        table.remove(copy, idx)
    end
    return res
end

local function buildPoolsFromCatalog()
    local pools = {}
    for i=1,6 do pools[i] = {} end
    if not CharacterCatalog then return pools end
    local all = CharacterCatalog:GetAllMap()
    for template, entry in pairs(all) do
        local stars = tonumber(entry.stars) or tonumber(entry.stars) or 0
        if stars >=1 and stars <=6 then
            table.insert(pools[stars], template)
        end
    end
    return pools
end

local function GenerateRandomBannerFromCatalog()
    -- Pools by stars
    local pools = buildPoolsFromCatalog()
    -- Request: 1x 5★, 2x 4★, 3x 3★
    local entries = {}
    local function pushFrom(stars, count)
        local pool = pools[stars] or {}
        local picks = sampleUnique(pool, count)
        for _, id in ipairs(picks) do
            local catEntry = CharacterCatalog and CharacterCatalog:Get(id)
            local icon_id = "rbxassetid://0"
            if catEntry then
                if catEntry.icon_id and type(catEntry.icon_id) == "string" and catEntry.icon_id:match("^rbxassetid://%d+$") then
                    icon_id = catEntry.icon_id
                else
                    -- Try to get icon from stats.icon field if icon_id is missing
                    if catEntry.icon and tonumber(catEntry.icon) then
                        icon_id = "rbxassetid://" .. tostring(catEntry.icon)
                        print(string.format("[BannerManager] icon_id missing, using stats.icon for %s: %s", id, icon_id))
                    else
                        warn(string.format("[BannerManager] Unit %s has invalid or missing icon_id, using fallback.", id))
                    end
                end
            else
                warn(string.format("[BannerManager] Catalog entry missing for unit %s, using fallback icon.", id))
            end
            print(string.format("[BannerManager] Banner entry: id=%s, rarity=%d, icon_id=%s", id, stars, icon_id))
            table.insert(entries, { id = id, rarity = stars, icon_id = icon_id })
        end
    end
    pushFrom(5, 1)
    pushFrom(4, 2)
    pushFrom(3, 3)
    print("[BannerManager] Final banner entries:", game:GetService("HttpService"):JSONEncode(entries))
    -- Print each entry for diagnostics
    for i, entry in ipairs(entries) do
        print(string.format("[BannerManager] Entry %d: id=%s, rarity=%s, icon_id=%s", i, tostring(entry.id), tostring(entry.rarity), tostring(entry.icon_id)))
    end
    -- Maintain order: 5★ entries first, then 4★, then 3★ (no cross-rarity shuffle)
    local banner = { entries = entries, generatedAt = os.time() }
    print("[BannerManager] Banner to send:", game:GetService("HttpService"):JSONEncode(banner))
    return banner
end

function BannerManager:GenerateAndPublish()
    local banner = GenerateRandomBannerFromCatalog()
    self:Save(banner)
    self:Broadcast(banner)
    self:UpdateReplicatedBanner(banner)
    return banner
end

-- Messaging subscription

-- On startup, always generate and broadcast a new banner
spawn(function()
    wait(1) -- Give time for everything to initialize
    print("[BannerManager] Forcing new banner generation and broadcast on startup...")
    BannerManager:GenerateAndPublish()
end)

return BannerManager
