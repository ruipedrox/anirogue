-- VictoryMenu LocalScript (placeholder)
-- Shows simple choices when a run ends with Win=true.
-- Buttons: Play Again, Next Level, Return to Lobby.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

local gui = script.Parent
if not gui:IsA("ScreenGui") then
	warn("VictoryMenu LocalScript parent is not a ScreenGui")
end

do
	-- If a DeathMenu exists, ensure VictoryMenu renders above it
	pcall(function() gui.DisplayOrder = 20 end)
end

-- Build UI dynamically
local frame = Instance.new("Frame")
frame.Name = "Container"
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.fromScale(0.5, 0.5)
frame.Size = UDim2.fromScale(0.35, 0.45)
frame.BackgroundColor3 = Color3.fromRGB(18, 26, 38)
frame.BackgroundTransparency = 0.08
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
title.Position = UDim2.fromScale(0, 0.015)
title.Font = Enum.Font.GothamBold
title.Text = "Victory!"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextScaled = true
title.Parent = frame

local sub = Instance.new("TextLabel")
sub.Name = "Subtitle"
sub.BackgroundTransparency = 1
sub.Size = UDim2.fromScale(0.95, 0.08)
sub.Position = UDim2.fromScale(0.025, 0.135)
sub.Font = Enum.Font.Gotham
sub.Text = "Choose what to do next"
sub.TextColor3 = Color3.fromRGB(200, 210, 220)
sub.TextScaled = true
sub.Parent = frame

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0.025, 0)
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.VerticalAlignment = Enum.VerticalAlignment.Top
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = frame

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0.23, 0)
padding.PaddingLeft = UDim.new(0.05, 0)
padding.PaddingRight = UDim.new(0.05, 0)
padding.Parent = frame

local function makeButton(label)
	local b = Instance.new("TextButton")
	b.Name = label:gsub("%s+", "")
	b.Size = UDim2.fromScale(1, 0.13)
	b.BackgroundColor3 = Color3.fromRGB(40, 70, 110)
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamSemibold
	b.Text = label
	b.TextScaled = true
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(90, 120, 170)
	stroke.Parent = b
	b.Parent = frame
	return b
end

local againBtn = makeButton("Play Again")
local nextBtn = makeButton("Next Level")
local lobbyBtn = makeButton("Return to Lobby")

-- Overlay behind the menu
local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 0.35
overlay.BorderSizePixel = 0
overlay.Size = UDim2.fromScale(1, 1)
overlay.Visible = false
overlay.ZIndex = frame.ZIndex - 1
overlay.Parent = gui

local function show()
	overlay.Visible = true
	frame.Visible = true
end
local function hide()
	overlay.Visible = false
	frame.Visible = false
end

-- Wire remotes
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	local t0 = os.clock()
	while os.clock() - t0 < 5 do
		remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if remotes then break end
		task.wait(0.2)
	end
end

local RunPlayAgain = remotes and remotes:FindFirstChild("RunPlayAgain")
local RunNextLevel = remotes and remotes:FindFirstChild("RunNextLevel")
local RunReturnToLobby = remotes and remotes:FindFirstChild("RunReturnToLobby")

againBtn.MouseButton1Click:Connect(function()
	if RunPlayAgain then
		-- disable buttons and keep menu visible while waiting for server
		againBtn.Active = false; nextBtn.Active = false; lobbyBtn.Active = false
		RunPlayAgain:FireServer()
		-- safety re-enable after 6s
		task.delay(6, function()
			if againBtn then againBtn.Active = true end
			if nextBtn then nextBtn.Active = true end
			if lobbyBtn then lobbyBtn.Active = true end
		end)
	end
	-- keep menu visible until server responds
end)
nextBtn.MouseButton1Click:Connect(function()
	if RunNextLevel then
		-- disable buttons to prevent double clicks and keep menu visible for feedback
		againBtn.Active = false; nextBtn.Active = false; lobbyBtn.Active = false
		RunNextLevel:FireServer()
		-- safety timeout: re-enable after 6s if no response
		task.delay(6, function()
			if againBtn then againBtn.Active = true end
			if nextBtn then nextBtn.Active = true end
			if lobbyBtn then lobbyBtn.Active = true end
		end)
	end
	-- keep menu visible until server responds
end)
lobbyBtn.MouseButton1Click:Connect(function()
	if RunReturnToLobby then RunReturnToLobby:FireServer() end
	hide()
end)

-- Auto-show when server signals end-of-run with Win=true
local RunCompleted = remotes and remotes:FindFirstChild("RunCompleted")
if RunCompleted and RunCompleted:IsA("RemoteEvent") then
	RunCompleted.OnClientEvent:Connect(function(summary)
		if type(summary) == "table" and summary.Win then
			show()
		end
	end)
end

		-- Listen for PlayAgain feedback
		local RunPlayAgainResult = remotes and remotes:FindFirstChild("RunPlayAgainResult")
		if RunPlayAgainResult and RunPlayAgainResult:IsA("RemoteEvent") then
			RunPlayAgainResult.OnClientEvent:Connect(function(payload)
				local msg = (type(payload) == "table" and payload.message) or tostring(payload)
				if not msg then return end
				local existing = frame:FindFirstChild("StatusMsg")
				if existing then existing:Destroy() end
				local lbl = Instance.new("TextLabel")
				lbl.Name = "StatusMsg"
				lbl.BackgroundTransparency = 1
				lbl.TextColor3 = Color3.fromRGB(220,220,220)
				lbl.Font = Enum.Font.Gotham
				lbl.TextScaled = true
				lbl.Size = UDim2.new(1, -40, 0, 24)
				lbl.Position = UDim2.new(0, 20, 0, 84)
				lbl.Text = msg
				lbl.Parent = frame
				if againBtn then againBtn.Active = true end
				if nextBtn then nextBtn.Active = true end
				if lobbyBtn then lobbyBtn.Active = true end
				task.delay(3.5, function()
					if lbl and lbl.Parent then pcall(function() lbl:Destroy() end) end
					if payload and type(payload) == "table" and payload.success then
						task.delay(0.25, function() hide() end)
					end
				end)
			end)
		end

-- Listen for next-level feedback from server and surface a small temporary notice
local RunNextLevelResult = remotes and remotes:FindFirstChild("RunNextLevelResult")
if RunNextLevelResult and RunNextLevelResult:IsA("RemoteEvent") then
	RunNextLevelResult.OnClientEvent:Connect(function(payload)
		-- payload = { success = bool, reason = optional, message = string }
		local msg = (type(payload) == "table" and payload.message) or tostring(payload)
		if not msg then return end
		-- show a small ephemeral label under the title
		local existing = frame:FindFirstChild("StatusMsg")
		if existing then existing:Destroy() end
		local lbl = Instance.new("TextLabel")
		lbl.Name = "StatusMsg"
		lbl.BackgroundTransparency = 1
		lbl.TextColor3 = Color3.fromRGB(220,220,220)
		lbl.Font = Enum.Font.Gotham
		lbl.TextScaled = true
		lbl.Size = UDim2.new(1, -40, 0, 24)
		lbl.Position = UDim2.new(0, 20, 0, 84)
		lbl.Text = msg
		lbl.Parent = frame
		-- Auto-hide after 3.5s
		-- restore buttons on any response
		if againBtn then againBtn.Active = true end
		if nextBtn then nextBtn.Active = true end
		if lobbyBtn then lobbyBtn.Active = true end
		-- Auto-hide message after 3.5s and hide menu on success
		task.delay(3.5, function()
			if lbl and lbl.Parent then pcall(function() lbl:Destroy() end) end
			if payload and type(payload) == "table" and payload.success then
				-- small delay so message is readable before hiding
				task.delay(0.25, function() hide() end)
			end
		end)
	end)
end

-- Also reflect attribute changes (in case of no summary payload)
local RS = ReplicatedStorage
local function checkShowFromAttrs()
	local ended = RS:GetAttribute("RunEnded")
	local win = RS:GetAttribute("RunWin")
	local awaiting = Players.LocalPlayer:GetAttribute("AwaitingRunChoice")
	if ended and win and awaiting then
		show()
	end
end
RS:GetAttributeChangedSignal("RunEnded"):Connect(checkShowFromAttrs)
RS:GetAttributeChangedSignal("RunWin"):Connect(checkShowFromAttrs)
player:GetAttributeChangedSignal("AwaitingRunChoice"):Connect(checkShowFromAttrs)

-- initial state
checkShowFromAttrs()
