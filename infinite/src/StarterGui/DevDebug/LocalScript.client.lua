local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DebugInit = Remotes:WaitForChild("DebugInit")

local function showPayload(payload)
    local gui = player:FindFirstChildOfClass("PlayerGui")
    if not gui then return end
    local screen = Instance.new("ScreenGui") screen.Name = "DevDebugGui" screen.ResetOnSpawn = false screen.Parent = gui
    local frame = Instance.new("ScrollingFrame") frame.Size = UDim2.new(0, 380, 0, 180) frame.Position = UDim2.new(0, 12, 0, 160) frame.BackgroundTransparency = 0.2 frame.Parent = screen
    local y = 8
    local function addLine(txt)
        local l = Instance.new("TextLabel") l.Size = UDim2.new(1, -16, 0, 18) l.Position = UDim2.new(0, 8, 0, y) l.BackgroundTransparency = 1 l.TextStrokeTransparency = 0.5 l.TextSize = 14 l.Font = Enum.Font.SourceSansBold l.Text = tostring(txt) l.TextColor3 = Color3.new(1,1,1) l.TextXAlignment = Enum.TextXAlignment.Left l.Parent = frame
        y = y + 20
    end
    addLine("Dev Debug Payload for " .. tostring(payload.Player or "<player>"))
    addLine("StoryMapId=" .. tostring(payload.StoryMapId) .. " Level=" .. tostring(payload.StoryLevel) .. " LevelName=" .. tostring(payload.LevelName))
    addLine("Equipped Serialize: Weapon=" .. tostring(payload.EquippedSerialize and payload.EquippedSerialize.Weapon) .. " Armor=" .. tostring(payload.EquippedSerialize and payload.EquippedSerialize.Armor) .. " Ring=" .. tostring(payload.EquippedSerialize and payload.EquippedSerialize.Ring))
    addLine("PlayerStats.Health=" .. tostring(payload.PlayerStatsHealth))
    if payload.Chars and #payload.Chars > 0 then
        for i,c in ipairs(payload.Chars) do
            addLine(string.format("Char[%d]=%s Level=%s Tier=%s", i, tostring(c.Name), tostring(c.Level), tostring(c.Tier)))
        end
    end
    -- Auto-remove after 20s
    task.delay(20, function() pcall(function() screen:Destroy() end) end)
end

DebugInit.OnClientEvent:Connect(function(payload)
    pcall(function() showPayload(payload) end)
end)
