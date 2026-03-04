-- Aizen_PerfectIllusion.lua
-- Legendary card: periodically makes the player semi-transparent and non-collidable

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Aizen_PerfectIllusion = {}

local _active = {} -- [player] = { running = bool, thread = thread, state = table, currentOriginals = table }

local statsPerLevel = {
    -- interval = seconds between activations
    -- duration = seconds intangible
    -- transparency = target transparency during effect (0..1)
    [1] = { interval = 12, duration = 1.0, transparency = 0.5 },
    [2] = { interval = 11, duration = 1.25, transparency = 0.5 },
    [3] = { interval = 10, duration = 1.5, transparency = 0.5},
    [4] = { interval = 9,  duration = 1.75, transparency = 0.5 },
    [5] = { interval = 8,  duration = 2.0, transparency = 0.5 },
}

local function isValidCharacter(char)
    return char and char.Parent and char:IsA("Model")
end

local function applyIntangibilityToCharacter(char, stats)
    if not isValidCharacter(char) then return nil end
    local originals = {}
    for _, obj in ipairs(char:GetDescendants()) do
        if obj:IsA("BasePart") then
            originals[obj] = {
                canCollide = obj.CanCollide,
                canTouch = obj.CanTouch and true or false,
                transparency = obj.Transparency,
            }
            pcall(function()
                obj.CanCollide = false
                obj.CanTouch = false
                -- set transparency to requested value (keep higher transparency if already more transparent)
                obj.Transparency = math.max(obj.Transparency, stats.transparency or 0.5)
            end)
        end
    end
    -- also try to disable humanoid collisions if present
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function()
            -- mark model invulnerable for Damage.Apply
            local model = hum.Parent
            originals._prevInv = model:GetAttribute("Invulnerable")
            model:SetAttribute("Invulnerable", true)
        end)
    end
    return originals
end

local function revertIntangibility(originals)
    if not originals then return end
    for part, data in pairs(originals) do
        if part ~= "_prevInv" then
            if part and part.Parent then
                pcall(function()
                    part.CanCollide = data.canCollide
                    part.CanTouch = data.canTouch
                    part.Transparency = data.transparency
                end)
            end
        end
    end
    -- restore invulnerability attribute if present
    local prev = originals._prevInv
    if prev ~= nil then
        -- originals should include a reference to the model; attempt to find from any part
        for part, _ in pairs(originals) do
            if typeof(part) == "Instance" and part:IsA("BasePart") and part.Parent then
                local model = part.Parent
                pcall(function() model:SetAttribute("Invulnerable", prev) end)
                break
            end
        end
    end
end

local function startForPlayer(player, def, level)
    if not player then return end
    level = math.clamp(tonumber(level) or 1, 1, 5)
    local stats = statsPerLevel[level] or statsPerLevel[1]
    local state = { running = true, currentOriginals = nil, level = level }
    -- register active early to avoid race
    _active[player] = state
    state.thread = task.spawn(function()
        while state.running do
            -- validate character
            local char = player.Character
            if not isValidCharacter(char) then
                task.wait(1)
                continue
            end
            -- apply intangibility
            local originals = applyIntangibilityToCharacter(char, stats)
            state.currentOriginals = originals
            -- keep effect for duration
            task.wait(stats.duration or 1)
            -- revert
            revertIntangibility(originals)
            state.currentOriginals = nil
            -- start cooldown AFTER effect ends
            task.wait(stats.interval or 10)
        end
    end)
    return state
end

function Aizen_PerfectIllusion.OnCardAdded(player, def, level)
    if not player then return end
    if _active[player] then return end
    -- Ensure RunTrack entry and record current level so CardPool can detect max level
    local runTrack = player:FindFirstChild("RunTrack") or Instance.new("Folder")
    runTrack.Name = "RunTrack"
    runTrack.Parent = player
    local myFolder = runTrack:FindFirstChild(def and def.id or script.Name) or Instance.new("Folder")
    myFolder.Name = def and def.id or script.Name
    myFolder.Parent = runTrack
    local lvlNV = myFolder:FindFirstChild("Level") or Instance.new("IntValue")
    lvlNV.Name = "Level"
    lvlNV.Value = tonumber(level) or 1
    lvlNV.Parent = myFolder
    local state = startForPlayer(player, def or {}, level)
    if state then state.folder = myFolder end
    _active[player] = state
end

function Aizen_PerfectIllusion.OnLevelUp(player, newLevel)
    if not player then return end
    if _active[player] then
        Aizen_PerfectIllusion.Stop(player)
        Aizen_PerfectIllusion.OnCardAdded(player, nil, newLevel)
    end
end

function Aizen_PerfectIllusion.Stop(player)
    local v = _active[player]
    if v then
        pcall(function() v.running = false end)
        -- if currently intangible, revert immediately
        if v.currentOriginals then
            pcall(function() revertIntangibility(v.currentOriginals) end)
            v.currentOriginals = nil
        end
        _active[player] = nil
    end
end

Players.PlayerRemoving:Connect(function(plr)
    if _active[plr] then
        pcall(function() _active[plr].stop() end)
        _active[plr] = nil
    end
end)

return Aizen_PerfectIllusion
