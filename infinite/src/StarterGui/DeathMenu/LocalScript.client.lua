-- DeathMenu LocalScript (Infinite Mode)
-- Shows death menu with Restart and Exit options only.
-- NO REVIVE (would break leaderboard integrity)

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local gui = script.Parent
if not gui:IsA("ScreenGui") then
	warn("DeathMenu LocalScript parent is not a ScreenGui")
end

-- Build UI dynamically
local frame = Instance.new("Frame")
frame.Name = "Container"
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.fromScale(0.5, 0.5)
frame.Size = UDim2.fromScale(0.3, 0.35)
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
title.Size = UDim2.fromScale(1, 0.15)
title.Position = UDim2.fromScale(0, 0)
title.Font = Enum.Font.GothamBold
title.Text = "You Died"
title.TextColor3 = Color3.fromRGB(255, 60, 60)
title.TextScaled = true
title.Parent = frame

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.BackgroundTransparency = 1
subtitle.Size = UDim2.fromScale(1, 0.1)
subtitle.Position = UDim2.fromScale(0, 0.15)
subtitle.Font = Enum.Font.Gotham
subtitle.Text = "Your progress has been saved"
subtitle.TextColor3 = Color3.fromRGB(200, 200, 200)
subtitle.TextScaled = true
subtitle.Parent = frame

local buttonList = Instance.new("UIListLayout")
buttonList.Padding = UDim.new(0.035, 0)
buttonList.HorizontalAlignment = Enum.HorizontalAlignment.Center
buttonList.VerticalAlignment = Enum.VerticalAlignment.Top
buttonList.SortOrder = Enum.SortOrder.LayoutOrder
buttonList.Parent = frame

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0.3, 0)
padding.PaddingLeft = UDim.new(0.05, 0)
padding.PaddingRight = UDim.new(0.05, 0)
padding.Parent = frame

local function makeButton(text)
	local b = Instance.new("TextButton")
	b.Name = text:gsub("%s+", "")
	b.Size = UDim2.fromScale(1, 0.18)
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

-- Only Restart and Exit buttons (no revive for leaderboard integrity)
local restartBtn = makeButton("Restart from Wave 1")
local exitBtn = makeButton("Return to Lobby")

-- Remote wiring
local remotesFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
if not remotesFolder then
	local t0 = os.clock()
	while os.clock() - t0 < 5 do
		remotesFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
		if remotesFolder then break end
		task.wait(0.25)
	end
end
if not remotesFolder then
	warn("[DeathMenu] Remotes folder not found - buttons disabled")
end
local restartRemote = remotesFolder and remotesFolder:FindFirstChild("DeathMenuRestart") or nil

-- Dark overlay
local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.BackgroundColor3 = Color3.new(0,0,0)
overlay.BackgroundTransparency = 0.35
overlay.BorderSizePixel = 0
overlay.Size = UDim2.fromScale(1,1)
overlay.Visible = false
overlay.ZIndex = frame.ZIndex - 1
overlay.Parent = gui

-- Button bindings
restartBtn.MouseButton1Click:Connect(function()
	if restartRemote then restartRemote:FireServer() end
	print("[DeathMenu] Restart clicked -> server")
	if frame then frame.Visible = false end
	if overlay then overlay.Visible = false end
end)

exitBtn.MouseButton1Click:Connect(function()
	print("[DeathMenu] Exit to lobby clicked")
	-- Fire server remote to save rewards and teleport to lobby
	local returnRemote = remotesFolder and remotesFolder:FindFirstChild("RunReturnToLobby")
	if returnRemote then
		returnRemote:FireServer()
	else
		warn("[DeathMenu] RunReturnToLobby remote not found")
	end
	if frame then frame.Visible = false end
	if overlay then overlay.Visible = false end
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
