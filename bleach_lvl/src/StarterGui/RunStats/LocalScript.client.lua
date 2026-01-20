-- RunStats UI (temporary)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Helper: format seconds to MM:SS
local function formatTime(s)
    s = tonumber(s) or 0
    local mins = math.floor(s / 60)
    local secs = math.floor(s % 60)
    return string.format("%02d:%02d", mins, secs)
end

-- Helper: compact number formatting (1.1k, 1M, etc.)
local function formatCompactNumber(n)
    n = tonumber(n) or 0
    local absn = math.abs(n)
    if absn >= 1e6 then
        local v = n / 1e6
        local s = string.format("%.1fM", v)
        -- trim trailing .0 (e.g. 1.0M -> 1M)
        s = s:gsub("%.0M", "M")
        return s
    elseif absn >= 1e3 then
        local v = n / 1e3
        local s = string.format("%.1fk", v)
        s = s:gsub("%.0k", "k")
        return s
    else
        return tostring(math.floor(n))
    end
end

-- Build UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RunStatsUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "RunStatsFrame"
frame.AnchorPoint = Vector2.new(0, 0)
frame.Position = UDim2.new(0.02, 0, 0.02, 0)
frame.Size = UDim2.new(0, 220, 0, 86)
frame.BackgroundTransparency = 0.35
frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
frame.BorderSizePixel = 0
frame.Parent = screenGui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, 0, 0, 20)
title.Font = Enum.Font.SourceSansBold
title.TextSize = 18
title.TextColor3 = Color3.fromRGB(255,255,255)
title.Text = "Run Stats"
title.Parent = frame

local function makeLabel(name, y)
    local lbl = Instance.new("TextLabel")
    lbl.Name = name
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.new(0, 8, 0, y)
    lbl.Size = UDim2.new(1, -16, 0, 22)
    lbl.Font = Enum.Font.SourceSans
    lbl.TextSize = 16
    lbl.TextColor3 = Color3.fromRGB(240,240,240)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = name .. ": --"
    lbl.Parent = frame
    return lbl
end

local timerLabel = makeLabel("Timer", 24)
local killsLabel = makeLabel("Kills", 48)
local damageLabel = makeLabel("Damage", 72)
local healingLabel = makeLabel("Healing", 96)

-- State for client-side live timer when RunStart appears
local clientStartTick = nil
local seenRunStart = 0

-- Utility to fetch numeric child value safely
local function getNumberValue(root, name)
    if not root then return nil end
    local v = root:FindFirstChild(name)
    if v and v:IsA("NumberValue") then return v.Value end
    if v and v:IsA("IntValue") then return v.Value end
    return nil
end

-- Watch for RunTrack folder
local runTrack = player:FindFirstChild("RunTrack")
if not runTrack then
    -- wait until server initializes it
    runTrack = player:WaitForChild("RunTrack")
end

-- Listen for RunStart to establish client-side tick baseline
local function handleRunStartChanged(val)
    if val and tonumber(val) and val > 0 then
        -- record local tick when we first see run start (used for live timer)
        clientStartTick = tick()
        seenRunStart = tonumber(val)
    else
        clientStartTick = nil
        seenRunStart = 0
    end
end

local rs = runTrack:FindFirstChild("RunStart")
if rs and rs:IsA("NumberValue") then
    handleRunStartChanged(rs.Value)
    rs.Changed:Connect(function(v) handleRunStartChanged(v) end)
end

-- Update loop: refresh labels 8x per second
RunService.Heartbeat:Connect(function(dt)
    if not runTrack then return end
    -- Timer: prefer RunTime (final) if non-zero, otherwise live since RunStart (client-observed)
    local runTimeVal = getNumberValue(runTrack, "RunTime") or 0
    if runTimeVal and runTimeVal > 0 then
        timerLabel.Text = "Timer: " .. formatTime(runTimeVal)
    else
        if clientStartTick then
            local elapsed = math.max(0, tick() - clientStartTick)
            timerLabel.Text = "Timer: " .. formatTime(elapsed)
        else
            timerLabel.Text = "Timer: --:--"
        end
    end

    local kills = getNumberValue(runTrack, "Kills") or 0
    killsLabel.Text = "Kills: " .. formatCompactNumber(kills)

    local damage = getNumberValue(runTrack, "Damage") or 0
    damageLabel.Text = "Damage: " .. formatCompactNumber(damage)

    local healing = getNumberValue(runTrack, "Healing") or 0
    healingLabel.Text = "Healing: " .. formatCompactNumber(healing)
end)

-- React to RunTrack being recreated (on restart). Re-hook listeners and refs.
player.ChildAdded:Connect(function(child)
    if child and child.Name == "RunTrack" and child:IsA("Folder") then
        runTrack = child
        local rs2 = runTrack:FindFirstChild("RunStart")
        if rs2 and rs2:IsA("NumberValue") then
            handleRunStartChanged(rs2.Value)
            rs2.Changed:Connect(function(v) handleRunStartChanged(v) end)
        end
    end
end)
