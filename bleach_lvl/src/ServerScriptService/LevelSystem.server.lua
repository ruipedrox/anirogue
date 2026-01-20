-- LevelSystem.server.lua
-- Server-side level / XP manager.
-- Responsibilities:
--  * Ensure each player has Stats folder with Level + XP values
--  * Provide AddXP(player, amount) to award XP
--  * Handle level ups (XP threshold) and fire RemoteEvent R_Events.Level_up to that player
--  * RemoteEvent args: newLevel, oldLevel
--  * Threshold formula currently: xpNeeded = BasePerLevel * level  (editable)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- RemoteEvent path (must already exist): ReplicatedStorage.R_Events.Level_up
local eventsFolder = ReplicatedStorage:WaitForChild("R_Events")
local levelUpEvent = eventsFolder:WaitForChild("Level_up")

-- CONFIG
local BASE_XP_PER_LEVEL = 100  -- You can tweak or make this scale non-linearly
local SCALE_EXPONENT = 1       -- If you want exponential growth set > 1 (e.g. 1.15)

local LevelSystem = {}

local function getOrCreateStats(player: Player)
    local stats = player:FindFirstChild("Stats")
    if not stats then
        stats = Instance.new("Folder")
        stats.Name = "Stats"
        stats.Parent = player
    end
    local level = stats:FindFirstChild("Level")
    if not level then
        level = Instance.new("NumberValue")
        level.Name = "Level"
        level.Value = 1
        level.Parent = stats
    end
    local xp = stats:FindFirstChild("XP")
    if not xp then
        xp = Instance.new("NumberValue")
        xp.Name = "XP"
        xp.Value = 0
        xp.Parent = stats
    end
    return stats, level, xp
end

local function xpRequiredFor(level: number): number
    return math.floor(BASE_XP_PER_LEVEL * (level ^ SCALE_EXPONENT))
end

local function fireLevelUp(player: Player, newLevel: number, oldLevel: number)
    -- Only fire if actually increased
    if newLevel > oldLevel then
        levelUpEvent:FireClient(player, newLevel, oldLevel)
    end
end

-- Public: Award XP (will handle multiple level ups if large amount)
function LevelSystem.AddXP(player: Player, amount: number)
    if not player or amount <= 0 then return end
    local stats, level, xp = getOrCreateStats(player)
    xp.Value += amount

    local leveled = false
    local oldLevel = level.Value
    while true do
        local needed = xpRequiredFor(level.Value)
        if xp.Value >= needed then
            xp.Value -= needed
            level.Value += 1
            leveled = true
        else
            break
        end
    end
    if leveled then
        fireLevelUp(player, level.Value, oldLevel)
    end
end

-- Optional helper: Set level directly (no XP distribution). Fires event if level increased.
function LevelSystem.SetLevel(player: Player, newLevel: number)
    if not player or newLevel <= 0 then return end
    local stats, level = getOrCreateStats(player)
    local old = level.Value
    if newLevel > old then
        level.Value = newLevel
        fireLevelUp(player, newLevel, old)
    end
end

-- Setup per-player (ensures data exists & attaches change listener if someone else changes Level directly)
local function onPlayerAdded(player: Player)
    local stats, level = getOrCreateStats(player)
    -- Store last reported level in an attribute to detect external changes
    level:SetAttribute("_LastReportedLevel", level.Value)
    level:GetPropertyChangedSignal("Value"):Connect(function()
        local last = level:GetAttribute("_LastReportedLevel") or level.Value
        if level.Value > last then
            fireLevelUp(player, level.Value, last)
            level:SetAttribute("_LastReportedLevel", level.Value)
        elseif level.Value < last then
            -- If lowered, just update attribute (no event)
            level:SetAttribute("_LastReportedLevel", level.Value)
        end
    end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
    onPlayerAdded(p)
end

-- (Optional) Expose globally for quick testing: _G.AddXP(player, amount)
pcall(function()
    _G.AddXP = LevelSystem.AddXP
end)

return LevelSystem
