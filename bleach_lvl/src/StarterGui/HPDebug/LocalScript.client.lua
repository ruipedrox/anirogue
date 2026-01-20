local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- Guarantee a ScreenGui in PlayerGui
local function ensureGui()
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then return nil end
	local existing = pg:FindFirstChild("HPDebugGui")
	if not existing then
		existing = Instance.new("ScreenGui")
		existing.Name = "HPDebugGui"
		existing.ResetOnSpawn = false
		existing.IgnoreGuiInset = true
		existing.Parent = pg
	end
	return existing
end

local gui = ensureGui() or script.Parent -- fallback
-- Re-ensure after character spawn (PlayerGui can be reconstructed)
player.CharacterAdded:Connect(function()
	task.defer(function()
		gui = ensureGui() or gui
	end)
end)

-- Create / reuse label
local label = (gui and gui:FindFirstChild("Label")) or nil
if not label then
	label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(0, 200, 0, 30)
	label.Position = UDim2.new(0, 12, 0, 110)
	label.BackgroundTransparency = 0.25
	label.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.fromRGB(255,255,255)
	label.TextStrokeTransparency = 0.4
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.Text = "HP: -- / --"
	if gui then label.Parent = gui end
end

local humanoid
local function bindHumanoid()
    local char = player.Character
    if not char then return end
    humanoid = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 2)
    if not humanoid then return end
    label.Text = string.format("HP: %d / %d", math.floor(humanoid.Health), math.floor(humanoid.MaxHealth))
    -- HealthChanged updates current value; MaxHealth polls separately
    humanoid.HealthChanged:Connect(function()
        label.Text = string.format("HP: %d / %d", math.floor(humanoid.Health), math.floor(humanoid.MaxHealth))
    end)
end

player.CharacterAdded:Connect(function()
	bindHumanoid()
end)

if player.Character then bindHumanoid() end

local accum = 0
RunService.Heartbeat:Connect(function(dt)
	accum += dt
	if accum > 0.2 then -- periodic refresh to catch MaxHealth adjustments
		accum = 0
		if not gui or not gui.Parent then
			gui = ensureGui() or gui
			if gui and not label.Parent then label.Parent = gui end
		end
		if humanoid and humanoid.Parent then
			label.Text = string.format("HP: %d / %d", math.floor(humanoid.Health+0.5), math.floor(humanoid.MaxHealth+0.5))
		else
			bindHumanoid()
		end
	end
end)
