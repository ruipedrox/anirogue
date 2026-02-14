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
-- Debug: print initialization info so we can confirm which Part this script is attached to
pcall(function()
    local full = part and part.GetFullName and part:GetFullName() or tostring(part)
    print(string.format("[StoryPortal] INIT on %s (Name=%s, Class=%s)", full, tostring(part and part.Name), tostring(part and part.ClassName)))
    local m = (part and part.GetAttribute) and part:GetAttribute("Mode") or nil
    print(string.format("[StoryPortal] INIT Mode attribute: %s", tostring(m)))
end)
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

    -- detect if this portal is configured to open Infinite mode
    local portalMode = nil
    pcall(function()
        if part.GetAttribute then
            portalMode = part:GetAttribute("Mode")
        end
    end)
    if not portalMode then
        local lname = tostring(part.Name or ""):lower()
        if lname:find("infinite") or lname:find("inf") then portalMode = "Infinite" end
    end

    print(string.format("[StoryPortal] clientReady[%d]=%s", uid, tostring(clientReady[uid])))
    if clientReady[uid] ~= true and portalMode ~= "Infinite" then
        -- for Story mode, require client handshake as before
        print("[StoryPortal] Cliente ainda não sinalizou pronto, ignorando.")
        return
    end

    -- Fire event to open Story UI
    local payload = (portalMode == "Infinite") and "Infinite" or "Story"

    -- If Infinite mode, prepare maps list from ReplicatedStorage.Shared.Maps.Infinite and send as payload.maps
    local sendPayload = payload
    if payload == "Infinite" then
        pcall(function()
            local RS = game:GetService("ReplicatedStorage")
            local Shared = RS:FindFirstChild("Shared")
            local Maps = Shared and Shared:FindFirstChild("Maps")
            local infiniteFolder = Maps and Maps:FindFirstChild("Infinite")
            local mapsList = {}
            if infiniteFolder then
                for _, folder in ipairs(infiniteFolder:GetChildren()) do
                    if folder and folder:IsA("Folder") then
                        local mod = folder:FindFirstChild("Map")
                        if mod and mod:IsA("ModuleScript") then
                            local okm, m = pcall(function() return require(mod) end)
                            if okm and type(m) == "table" then
                                -- Sanitize the map table to a plain serializable table containing only data fields
                                local simple = {
                                    Id = m.Id,
                                    DisplayName = m.DisplayName,
                                    PreviewImage = m.PreviewImage,
                                    BackgroundImage = m.BackgroundImage,
                                    Levels = m.Levels,
                                    Drops = m.Drops,
                                    SortOrder = m.SortOrder,
                                    Description = m.Description,
                                    IsInfinite = m.IsInfinite,
                                    RecommendedPower = m.RecommendedPower,
                                }
                                table.insert(mapsList, simple)
                            end
                        end
                    end
                end
            end
            sendPayload = { mode = "Infinite", maps = mapsList }
        end)
    end

    local ok1, err1 = pcall(function()
        openRemote:FireClient(player, sendPayload)
    end)
    if not ok1 then
        warn(string.format("[StoryPortal] Falha ao FireClient Open_Story: %s", tostring(err1)))
    else
        print(string.format("[StoryPortal] Disparado Open_Story('%s') para %s", tostring(payload), player.Name))
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
