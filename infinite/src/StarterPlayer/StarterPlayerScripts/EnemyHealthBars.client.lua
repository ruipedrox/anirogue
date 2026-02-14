local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- Creates a BillboardGui health bar for a given enemy Model
local function createHealthBar(enemy)
    if not enemy or not enemy:IsA("Model") then return nil end
    local humanoid = enemy:FindFirstChildOfClass("Humanoid")
    if not humanoid then return nil end

    local root = enemy:FindFirstChild("HumanoidRootPart")
    if not root then
        -- Try to wait briefly for root (some enemies may set PrimaryPart later)
        root = enemy:WaitForChild("HumanoidRootPart", 2)
        if not root then return nil end
    end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "HealthBar"
    billboard.Adornee = root
    billboard.ExtentsOffset = Vector3.new(0, 3.5, 0)
    billboard.Size = UDim2.new(0, 80, 0, 10)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 200
    billboard.Parent = enemy

    local bg = Instance.new("Frame")
    bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    bg.BorderSizePixel = 0
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.Parent = billboard

    local uiCorner = Instance.new("UICorner")
    uiCorner.CornerRadius = UDim.new(0, 4)
    uiCorner.Parent = bg

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
    fill.BorderSizePixel = 0
    fill.Size = UDim2.new(1, 0, 1, 0)
    fill.Parent = bg

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 4)
    fillCorner.Parent = fill

    local function update()
        if not humanoid or humanoid.MaxHealth <= 0 then return end
        local frac = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
        fill.Size = UDim2.new(frac, 0, 1, 0)
        -- Optional color shift from green to red
        local r = math.clamp(255 * (1 - frac), 0, 255)
        local g = math.clamp(255 * frac, 0, 255)
        fill.BackgroundColor3 = Color3.fromRGB(r, g, 60)
    end

    update()
    humanoid.HealthChanged:Connect(update)
    humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(update)

    enemy.AncestryChanged:Connect(function(_, parent)
        if not parent then
            if billboard and billboard.Parent then billboard:Destroy() end
        end
    end)

    return billboard
end

-- Attach to existing tagged enemies
for _, enemy in ipairs(CollectionService:GetTagged("Enemy")) do
    if enemy:IsA("Model") and not enemy:FindFirstChild("HealthBar") then
        createHealthBar(enemy)
    end
end

-- Listen for new enemies
CollectionService:GetInstanceAddedSignal("Enemy"):Connect(function(enemy)
    if enemy and enemy:IsA("Model") then
        -- Defer a tiny bit to let Humanoid/Root exist
        task.defer(function()
            if enemy and enemy.Parent and not enemy:FindFirstChild("HealthBar") then
                createHealthBar(enemy)
            end
        end)
    end
end)

-- Cleanup when tag removed
CollectionService:GetInstanceRemovedSignal("Enemy"):Connect(function(enemy)
    if enemy and enemy:IsA("Model") then
        local hb = enemy:FindFirstChild("HealthBar")
        if hb then hb:Destroy() end
    end
end)
