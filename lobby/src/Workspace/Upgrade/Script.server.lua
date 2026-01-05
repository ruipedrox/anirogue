-- Server: Part touch -> open Upgrade UI (panel '1st') with robust handshake and dual path (Event + Function)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Ensure Remotes folder exists
local remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

-- RemoteEvent to open the Upgrade UI
local openRemote = remotes:FindFirstChild("Open_Upgrade")
if not openRemote then
    openRemote = Instance.new("RemoteEvent")
    openRemote.Name = "Open_Upgrade"
    openRemote.Parent = remotes
end

-- Client readiness RemoteEvent
local UpgradeClientReadyRE = remotes:FindFirstChild("UpgradeClientReady")
if not UpgradeClientReadyRE then
    UpgradeClientReadyRE = Instance.new("RemoteEvent")
    UpgradeClientReadyRE.Name = "UpgradeClientReady"
    UpgradeClientReadyRE.Parent = remotes
end

-- RemoteFunction for explicit client confirmation
local openUpgradeFunction = remotes:FindFirstChild("OpenUpgradeFunction")
if not openUpgradeFunction then
    openUpgradeFunction = Instance.new("RemoteFunction")
    openUpgradeFunction.Name = "OpenUpgradeFunction"
    openUpgradeFunction.Parent = remotes
end

local clientReady = {} -- map<userId, boolean>

print(string.format("[UpgradeBlock] Remotes: Open_Upgrade=%s OpenUpgradeFunction=%s", tostring(openRemote and openRemote:GetFullName()), tostring(openUpgradeFunction and openUpgradeFunction:GetFullName())))

local function findTouchable(base)
    if not base then return nil end
    if base:IsA("BasePart") then return base end
    for _, d in ipairs(base:GetDescendants()) do
        if d:IsA("BasePart") then return d end
    end
    return nil
end

local part = findTouchable(script.Parent)
if not part then
    warn("[UpgradeBlock] Nenhuma BasePart encontrada para conectar Touched (parent=", script.Parent and script.Parent:GetFullName(), ")")
end
local debounce = {}
local DEBOUNCE_SECONDS = 0.8

UpgradeClientReadyRE.OnServerEvent:Connect(function(player)
    clientReady[player.UserId] = true
    print("[UpgradeBlock] Cliente pronto para Upgrade:", player.Name)
end)

Players.PlayerRemoving:Connect(function(player)
    if not player then return end
    debounce[player.UserId] = nil
    clientReady[player.UserId] = nil
end)

local function playerFromHit(hit)
    local char = hit and hit:FindFirstAncestorOfClass("Model")
    if not char then return nil end
    return Players:GetPlayerFromCharacter(char)
end

if part and part.Touched then part.Touched:Connect(function(hit)
    local player = playerFromHit(hit)
    print("[UpgradeBlock] playerFromHit:", player, player and player.Name)
    if not player then return end
    local uid = player.UserId
    local now = os.clock()
    if debounce[uid] and now - debounce[uid] < DEBOUNCE_SECONDS then
        print(string.format("[UpgradeBlock] Debounce ativo para %s (%.2fs)", player.Name, now - debounce[uid]))
        return
    end
    debounce[uid] = now

    print(string.format("[UpgradeBlock] Estado clientReady[%s]=%s", tostring(uid), tostring(clientReady[uid])))

    if clientReady[uid] ~= true then
        print("[UpgradeBlock] Cliente ainda não sinalizou pronto, ignorando.")
        return
    end

    -- Fire RemoteEvent with a payload that indicates panel '1st'
    if openRemote and openRemote:IsA("RemoteEvent") then
        print("[UpgradeBlock] Disparando evento para:", player, player and player.Name, "Remote:", openRemote)
        local ok, err = pcall(function()
            openRemote:FireClient(player, "Upgrade:1st")
        end)
        if ok then
            print(string.format("[UpgradeBlock] Fired Open_Upgrade to %s (panel=1st)", tostring(player.Name)))
        else
            warn(string.format("[UpgradeBlock] Failed to FireClient Open_Upgrade for %s: %s", tostring(player.Name), tostring(err)))
        end
    else
        warn("Remote Open_Upgrade não encontrado em ReplicatedStorage.Remotes")
    end

    -- Also try RemoteFunction for explicit open confirmation
    if openUpgradeFunction then
        print("[UpgradeBlock] Invocando RemoteFunction para:", player, player and player.Name)
        local ok, result = pcall(function()
            return openUpgradeFunction:InvokeClient(player, "Upgrade:1st")
        end)
        if ok and result == true then
            print(string.format("[UpgradeBlock] Cliente confirmou abertura da UI: %s (panel=1st)", tostring(player.Name)))
        else
            warn(string.format("[UpgradeBlock] Cliente NÃO confirmou abertura da UI: %s", tostring(player.Name)))
        end
    else
        warn("RemoteFunction OpenUpgradeFunction não encontrado em ReplicatedStorage.Remotes")
    end
end end)
