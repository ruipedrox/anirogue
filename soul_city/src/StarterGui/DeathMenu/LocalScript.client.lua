-- DeathMenu LocalScript
-- Shows a simple menu when the local player's Humanoid dies.
-- Buttons: Revive, Restart Level, Exit (return to lobby) - currently only print placeholders.

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local gui = script.Parent
if not gui:IsA("ScreenGui") then
	warn("DeathMenu LocalScript parent is not a ScreenGui")
end

-- Build UI dynamically (so only this script needed).
local frame = Instance.new("Frame")
frame.Name = "Container"
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.fromScale(0.5, 0.5)
frame.Size = UDim2.fromScale(0.3, 0.4)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
frame.BackgroundTransparency = 0.15
frame.BorderSizePixel = 0
frame.Visible = false
frame.Parent = gui

local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(0, 12)
uiCorner.Parent = frame

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Size = UDim2.fromScale(1, 0.12)
title.Position = UDim2.fromScale(0, 0)
title.Font = Enum.Font.GothamBold
title.Text = "You Died"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextScaled = true
title.Parent = frame

local buttonList = Instance.new("UIListLayout")
buttonList.Padding = UDim.new(0.025, 0)
buttonList.HorizontalAlignment = Enum.HorizontalAlignment.Center
buttonList.VerticalAlignment = Enum.VerticalAlignment.Top
buttonList.SortOrder = Enum.SortOrder.LayoutOrder
buttonList.Parent = frame

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0.15, 0)
padding.PaddingLeft = UDim.new(0.05, 0)
padding.PaddingRight = UDim.new(0.05, 0)
padding.Parent = frame

local function makeButton(text)
	local b = Instance.new("TextButton")
	b.Name = text:gsub("%s+", "")
	b.Size = UDim2.fromScale(1, 0.14)
	b.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamSemibold
	b.Text = text
	b.TextScaled = true
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(90, 90, 120)
	stroke.Parent = b
	b.Parent = frame
	return b
end

local reviveBtn = makeButton("Revive")
local restartBtn = makeButton("Restart Level")
local exitBtn = makeButton("Exit")

-- Remote wiring (tolerante: evita infinite yield se Remotes demorar)
local remotesFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
if not remotesFolder then
	-- Tentativa suave de aguardar alguns segundos
	local t0 = os.clock()
	while os.clock() - t0 < 5 do
		remotesFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
		if remotesFolder then break end
		task.wait(0.25)
	end
end
if not remotesFolder then
	warn("[DeathMenu] Pasta Remotes não encontrada - botões desativados")
end
local reviveRemote = remotesFolder and remotesFolder:FindFirstChild("DeathMenuRevive") or nil
local restartRemote = remotesFolder and remotesFolder:FindFirstChild("DeathMenuRestart") or nil

-- Optional dark overlay
local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.BackgroundColor3 = Color3.new(0,0,0)
overlay.BackgroundTransparency = 0.35
overlay.BorderSizePixel = 0
overlay.Size = UDim2.fromScale(1,1)
overlay.Visible = false
overlay.ZIndex = frame.ZIndex - 1
overlay.Parent = gui

-- Bind buttons after overlay exists to avoid nil access
reviveBtn.MouseButton1Click:Connect(function()
	if reviveRemote then reviveRemote:FireServer() end
	print("[DeathMenu] Revive clicked -> server")
	if frame then frame.Visible = false end
	if overlay then overlay.Visible = false end
end)
restartBtn.MouseButton1Click:Connect(function()
	if restartRemote then restartRemote:FireServer() end
	print("[DeathMenu] Restart Level clicked -> server")
	if frame then frame.Visible = false end
	if overlay then overlay.Visible = false end
end)
exitBtn.MouseButton1Click:Connect(function()
	print("[DeathMenu] Exit clicked (not implemented)")
end)

-- Show/hide logic
local function show()
	overlay.Visible = true
	frame.Visible = true
end
local function hide()
	overlay.Visible = false
	frame.Visible = false
end

local function hookCharacter(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	hum.Died:Connect(function()
		show()
	end)
end

player.CharacterAdded:Connect(function(c)
	hide()
	hookCharacter(c)
end)
if player.Character then
	hookCharacter(player.Character)
end

-- Initially hidden; will appear on death.
