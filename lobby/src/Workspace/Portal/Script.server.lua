-- Server: Part touch -> open Story UI (similar to Summon)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Ensure required remotes exist
local openRemote = remotes:FindFirstChild("Open_Story")
if not openRemote then
    openRemote = Instance.new("RemoteEvent")
    openRemote.Name = "Open_Story"
    openRemote.Parent = remotes
end

local StoryClientReadyRE = remotes:FindFirstChild("StoryClientReady")
if not StoryClientReadyRE then
    StoryClientReadyRE = Instance.new("RemoteEvent")
    StoryClientReadyRE.Name = "StoryClientReady"
    StoryClientReadyRE.Parent = remotes
end

local openStoryFunction = remotes:FindFirstChild("OpenStoryFunction")
if not openStoryFunction then
    openStoryFunction = Instance.new("RemoteFunction")
    openStoryFunction.Name = "OpenStoryFunction"
    openStoryFunction.Parent = remotes
end

local clientReady = {}

local part = script.Parent -- expected to be a Part named "Portal"
if part and part.Name ~= "Portal" then
    warn(string.format("[StoryPortal] Aviso: o nome do bloco é '%s', esperado 'Portal' (funcionará mesmo assim)", tostring(part.Name)))
end

local debounce = {}
local DEBOUNCE_SECONDS = 0.8

StoryClientReadyRE.OnServerEvent:Connect(function(player)
    clientReady[player.UserId] = true
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

part.Touched:Connect(function(hit)
    local player = playerFromHit(hit)
    print("[StoryPortal] Touched by:", player and player.Name, "hit:", hit and hit:GetFullName())
    if not player then return end
    local uid = player.UserId
    local now = os.clock()
    if debounce[uid] and now - debounce[uid] < DEBOUNCE_SECONDS then
        print(string.format("[StoryPortal] Debounce ativo para %s (%.2fs)", player.Name, now - debounce[uid]))
        return
    end
    debounce[uid] = now

    print(string.format("[StoryPortal] clientReady[%d]=%s", uid, tostring(clientReady[uid])))
    if clientReady[uid] ~= true then
        print("[StoryPortal] Cliente ainda não sinalizou pronto, ignorando.")
        return
    end

    -- Fire event to open Story UI
    local ok1, err1 = pcall(function()
        openRemote:FireClient(player, "Story")
    end)
    if not ok1 then
        warn(string.format("[StoryPortal] Falha ao FireClient Open_Story: %s", tostring(err1)))
    else
        print(string.format("[StoryPortal] Disparado Open_Story para %s", player.Name))
    end

    -- Also invoke RemoteFunction for confirmation (optional)
    local ok2, res2 = pcall(function()
        return openStoryFunction:InvokeClient(player, "Story")
    end)
    if not ok2 or res2 ~= true then
        warn(string.format("[StoryPortal] Cliente não confirmou abertura da UI: %s (ok=%s, res=%s)", tostring(player.Name), tostring(ok2), tostring(res2)))
    else
        print(string.format("[StoryPortal] Cliente confirmou abertura da UI: %s", tostring(player.Name)))
    end
end)
