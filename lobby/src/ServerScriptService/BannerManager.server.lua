-- Garante que CurrentBanner existe logo no início
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local bannerValue = ReplicatedStorage:FindFirstChild("CurrentBanner")
if not bannerValue then
    bannerValue = Instance.new("StringValue")
    bannerValue.Name = "CurrentBanner"
    bannerValue.Parent = ReplicatedStorage
    bannerValue.Value = "" -- Inicializa vazio
end
-- BannerManager.server.lua
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local BannerUpdated = remotes:FindFirstChild("BannerUpdated")
local BannerDataStore = DataStoreService:GetDataStore("GlobalBanner")
local HttpService = game:GetService("HttpService")

-- Função para calcular o timestamp do próximo horário de troca (meia em meia hora)
local function getCurrentBannerTimestamp()
    local now = os.time()
    local utc = os.date("!*t", now)
    local minutes = math.floor(utc.min / 30) * 30
    utc.min = minutes
    utc.sec = 0
    return os.time(utc)
end

-- Função para gerar um novo banner (exemplo, personalize como quiser)
local function generateBanner()
    -- Aqui você pode usar seu SummonModule ou lógica customizada
    return {
        generatedAt = getCurrentBannerTimestamp(),
        entries = {
            -- Exemplo de banner, substitua pela sua lógica real
            {id = "Goku_5", rarity = 5, icon_id = "rbxassetid://91806970218225"},
            {id = "Goku_4", rarity = 4, icon_id = "rbxassetid://84530411684994"},
            {id = "Kame_4", rarity = 4, icon_id = "rbxassetid://93720933756204"},
            {id = "Goku_3", rarity = 3, icon_id = "rbxassetid://91156103882629"},
            {id = "Naruto_3", rarity = 3, icon_id = "rbxassetid://135505550864938"},
            {id = "Krillin_3", rarity = 3, icon_id = "rbxassetid://102208659147364"},
        }
    }
end

-- Função para salvar banner no DataStore
local function saveBanner(banner)
    local ok, err = pcall(function()
        BannerDataStore:SetAsync("CurrentBanner", banner)
    end)
    if not ok then
        warn("[BannerManager] Erro ao salvar banner:", err)
    end
end

-- Função para carregar banner do DataStore
local function loadBanner()
    local ok, data = pcall(function()
        return BannerDataStore:GetAsync("CurrentBanner")
    end)
    if ok and data then
        return data
    end
    return nil
end

-- Função principal: garante que o banner está correto para o horário
local function ensureBanner()
    local timestamp = getCurrentBannerTimestamp()
    local banner = loadBanner()
    if not banner or banner.generatedAt ~= timestamp then
        banner = generateBanner()
        saveBanner(banner)
        print("[BannerManager] Banner gerado e salvo para timestamp:", timestamp)
    else
        print("[BannerManager] Banner já está correto para timestamp:", timestamp)
    end
    return banner
end

-- Atualiza e envia banner para todos os clientes
local function broadcastBanner()
    local banner = ensureBanner()
    if BannerUpdated then
        BannerUpdated:FireAllClients(banner)
        print("[BannerManager] Banner broadcast para todos os clientes.")
    end
end

-- Timer para atualizar banner a cada minuto (garante troca exata)
spawn(function()
    while true do
        broadcastBanner()
        wait(60)
    end
end)

-- Opcional: ao player entrar, envia banner
game.Players.PlayerAdded:Connect(function(player)
    local banner = ensureBanner()
    if BannerUpdated then
        BannerUpdated:FireClient(player, banner)
    end
end)-- BannerManager.server.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")

-- require the sibling module in the same folder
local manager = require(script.Parent:WaitForChild("BannerManager.module"))

-- Rotate banners every 30 minutes on the wall-clock half-hour marks (00 and 30)
local ROTATE_SECONDS = 30 * 60 -- 30 minutes

-- Leader election settings (lease via DataStore UpdateAsync)
local LEADER_KEY = "banner_leader"
local LEASE_SECONDS = 45
local RENEW_INTERVAL = 15

-- Testing flag: when true, generate & publish a new banner every 10 seconds.
-- Intended for local/Studio testing only. Keep disabled in production.
local TEST_BANNER_LOOP = false
local TEST_LOOP_INTERVAL = 10 -- seconds

local serverId = HttpService:GenerateGUID(false)
local leader = false
local ds = DataStoreService:GetDataStore("GlobalBanners")

-- Admin trigger RemoteEvent (allow admins to force a GenerateAndPublish)
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "Remotes"
    remotesFolder.Parent = ReplicatedStorage
end
local adminTrigger = remotesFolder:FindFirstChild("BannerAdminTrigger")
if not adminTrigger then
    adminTrigger = Instance.new("RemoteEvent")
    adminTrigger.Name = "BannerAdminTrigger"
    adminTrigger.Parent = remotesFolder
end

-- Require admin helper
local okAdmin, Admin = pcall(function()
    return require(script.Parent:WaitForChild("BannerAdmin.module"))
end)
if not okAdmin or not Admin then
    warn("[BannerManager] Could not require BannerAdmin.module; admin trigger will be unavailable")
end

-- RemoteEvent handler for admin-triggered generation
adminTrigger.OnServerEvent:Connect(function(player)
    if not okAdmin or not Admin then
        warn("[BannerManager] Admin module missing, ignoring admin trigger from", player and player.Name)
        return
    end
    if not Admin:IsAdmin(player.UserId) then
        warn("[BannerManager] Unauthorized BannerAdminTrigger attempt by", player.Name)
        return
    end
    print("[BannerManager] Admin trigger invoked by", player.Name)
    local ok, err = pcall(function()
        manager:GenerateAndPublish()
    end)
    if not ok then warn("[BannerManager] Admin GenerateAndPublish failed:", err) end
end)

-- Attempt to claim leadership using UpdateAsync
local function tryClaimLeader()
    local ok, res = pcall(function()
        return ds:UpdateAsync(LEADER_KEY, function(old)
            local now = os.time()
            if not old or type(old) ~= "table" or (old.expiresAt or 0) < now then
                return { owner = serverId, expiresAt = now + LEASE_SECONDS }
            end
            return old
        end)
    end)
    if ok and type(res) == "table" and res.owner == serverId then
        leader = true
        print("[BannerManager] This server is leader:", serverId)
        return true
    end
    leader = false
    return false
end

local function renewLease()
    local ok, res = pcall(function()
        return ds:UpdateAsync(LEADER_KEY, function(old)
            if old and type(old) == "table" and old.owner == serverId then
                old.expiresAt = os.time() + LEASE_SECONDS
                return old
            end
            return old
        end)
    end)
    if ok then
        if type(res) == "table" and res.owner == serverId then
            -- renewal succeeded, keep leadership
            return true
        else
            -- someone else took leadership
            if leader then
                leader = false
                print("[BannerManager] Lost leadership:", serverId)
            end
            return false
        end
    else
        warn("[BannerManager] renewLease UpdateAsync failed (ignored)")
        return false
    end
end

-- Attempt to become leader; keep trying every few seconds until acquired.
local function beginLeaderElection()
    spawn(function()
        while not leader do
            local ok = tryClaimLeader()
            if ok then break end
            wait(5)
        end

        -- If still not leader but we're in Studio, promote this process for easier testing
        if not leader and RunService:IsStudio() then
            leader = true
            print("[BannerManager] Running as leader in Studio (fallback)")
        end

        -- If leader, start renewal loop
        if leader then
            spawn(function()
                while leader do
                    wait(RENEW_INTERVAL)
                    renewLease()
                end
            end)
        end
    end)
end

-- Attempt to initialize and broadcast or generate initial banner
local function init()
    local stored = manager:Load()
    if stored then
        print("[BannerManager] Loaded existing banner, broadcasting to clients.")
        manager:Broadcast(stored)
    else
        print("[BannerManager] No existing banner found, generating initial banner.")
        manager:GenerateAndPublish()
    end
end

-- Start leader election (non-blocking)
beginLeaderElection()

-- Leader-only: rotation loop and optional test loop will be started below after leadership is established.

-- Helper to start leader loops once this server is leader
local function startLeaderLoops()
    spawn(function()
        while not leader do wait(1) end
        -- rotation loop aligned to wall-clock half-hour marks (00 and 30)
        while leader do
            local now = os.time()
            local dt = os.date("*t", now)
            local minute = dt.min
            local second = dt.sec
            local minutesPastHalf = minute % 30
            local secondsToWait = (30 - minutesPastHalf) * 60 - second
            if minutesPastHalf == 0 and second == 0 then
                secondsToWait = 0
            end
            if secondsToWait <= 0 then
                secondsToWait = 30 * 60
            end
            -- wait until the next half-hour boundary, unless leadership is lost
            local waited = 0
            while waited < secondsToWait and leader do
                local chunk = math.min(1, secondsToWait - waited)
                wait(chunk)
                waited = waited + chunk
            end
            if not leader then break end
            print("[BannerManager] Generating scheduled rotating banner (leader) - aligned to half-hour")
            manager:GenerateAndPublish()
        end
    end)

    if TEST_BANNER_LOOP then
        spawn(function()
            while not leader do wait(1) end
            while leader do
                print("[BannerManager] (TEST) Generating and publishing banner (every ", TEST_LOOP_INTERVAL, "s)")
                local ok, err = pcall(function()
                    manager:GenerateAndPublish()
                end)
                if not ok then warn("[BannerManager] (TEST) GenerateAndPublish failed:", err) end
                wait(TEST_LOOP_INTERVAL)
            end
        end)
    end
end

startLeaderLoops()
-- Run init once and let leader loops manage subsequent generation
init()
