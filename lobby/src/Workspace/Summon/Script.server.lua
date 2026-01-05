-- Server: Part touch -> open Summon UI (robusto, com timestamps e logs)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local openRemote = remotes:WaitForChild("Open_Summon") -- must exist
local SummonClientReadyRE = remotes:FindFirstChild("SummonClientReady")
if not SummonClientReadyRE then
    SummonClientReadyRE = Instance.new("RemoteEvent")
    SummonClientReadyRE.Name = "SummonClientReady"
    SummonClientReadyRE.Parent = remotes
end

local openSummonFunction = remotes:FindFirstChild("OpenSummonFunction")
if not openSummonFunction then
    openSummonFunction = Instance.new("RemoteFunction")
    openSummonFunction.Name = "OpenSummonFunction"
    openSummonFunction.Parent = remotes
end

local clientReady = {} -- <--- Inicializado ANTES de qualquer uso!

print(string.format("[SummonBlock] Resolved remote: Open_Summon=%s", tostring(openRemote and openRemote:GetFullName())))

local part = script.Parent
local debounce = {}
local DEBOUNCE_SECONDS = 0.8

SummonClientReadyRE.OnServerEvent:Connect(function(player)
    clientReady[player.UserId] = true
end)

-- Clean up when player leaves (keep debounce cleanup only)
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

part.Touched:Connect(function(hit)
    local player = playerFromHit(hit)
    print("[SummonBlock] playerFromHit:", player, player and player.Name)
    if not player then return end
    local uid = player.UserId
    local now = os.clock()
    if debounce[uid] and now - debounce[uid] < DEBOUNCE_SECONDS then
        print(string.format("[SummonBlock] Debounce ativo para %s (%.2fs)", player.Name, now - debounce[uid]))
        return
    end
    debounce[uid] = now

    print(string.format("[SummonBlock] Estado clientReady[%s]=%s", tostring(uid), tostring(clientReady[uid])))

    if clientReady[uid] ~= true then
        print("[SummonBlock] Cliente ainda não sinalizou pronto, ignorando.")
        return
    end

    if openRemote and openRemote:IsA("RemoteEvent") then
        print("[SummonBlock] Disparando evento para:", player, player and player.Name, "Remote:", openRemote)
        local ok, err = pcall(function()
            openRemote:FireClient(player, "Summon")
        end)
        if ok then
            print(string.format("[SummonBlock] Fired Open_Summon to %s", tostring(player.Name)))
        else
            warn(string.format("[SummonBlock] Failed to FireClient Open_Summon for %s: %s", tostring(player.Name), tostring(err)))
        end
    else
        warn("Remote Open_Summon não encontrado em ReplicatedStorage.Remotes")
    end

    if openSummonFunction then
        print("[SummonBlock] Invocando RemoteFunction para:", player, player and player.Name)
        local ok, result = pcall(function()
            return openSummonFunction:InvokeClient(player, "Summon")
        end)
        if ok and result == true then
            print(string.format("[SummonBlock] Cliente confirmou abertura da UI: %s", tostring(player.Name)))
        else
            warn(string.format("[SummonBlock] Cliente NÃO confirmou abertura da UI: %s", tostring(player.Name)))
        end
    else
        warn("RemoteFunction OpenSummonFunction não encontrado em ReplicatedStorage.Remotes")
    end
end)