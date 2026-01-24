local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Módulo de progressão
local Leveling = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Leveling"))

local player = Players.LocalPlayer
local frame = script.Parent  -- Frame que contém BG -> XP_Bar, XP_under, Label

local bg = frame:WaitForChild("BG")
local bar = bg:WaitForChild("XP_Bar")
local bar_under = bg:WaitForChild("XP_under")
local label = bg:WaitForChild("Label")

-- Suavização
local smooth = 6
local displayedRatio = 0

-- State that can be re-bound when Stats appear
local stats, xp, level, req
local needed = 1

-- Forward declaration to allow references inside bindStats callbacks
local tryInit

local statsWatchConnected = false
local function connectStatsWatch()
	if stats and not statsWatchConnected then
		statsWatchConnected = true
		stats.ChildAdded:Connect(function(child)
			if child.Name == "XP" or child.Name == "Level" or child.Name == "XPRequired" then
				task.delay(0.05, function()
					if tryInit then tryInit() end
				end)
			end
		end)
		stats.ChildRemoved:Connect(function(child)
			if child.Name == "XP" or child.Name == "Level" then
				label.Text = "--/--"
				task.delay(0.05, function()
					if tryInit then tryInit() end
				end)
			end
		end)
	end
end

local function bindStats(timeout)
	timeout = timeout or 5
	local t0 = os.clock()
	stats = player:FindFirstChild("Stats")
	while not stats and os.clock() - t0 < timeout do
		stats = player:FindFirstChild("Stats")
		task.wait(0.1)
	end
	if not stats then return false end

	-- Ensure we watch for late creation of values
	connectStatsWatch()

	xp = stats:FindFirstChild("XP")
	level = stats:FindFirstChild("Level")
	local t1 = os.clock()
	while (not xp or not level) and os.clock() - t1 < timeout do
		xp = stats:FindFirstChild("XP")
		level = stats:FindFirstChild("Level")
		task.wait(0.1)
	end
	if not xp or not level then return false end

	req = stats:FindFirstChild("XPRequired")
	if req and req:IsA("NumberValue") then
		needed = math.max(1, tonumber(req.Value) or 1)
		req.Changed:Connect(function()
			needed = math.max(1, tonumber(req.Value) or 1)
		end)
	else
		needed = Leveling:GetRequiredXP(level.Value)
	end
	if needed <= 0 then needed = 1 end

	-- Rebind level change listener
	level.Changed:Connect(function()
		if req and req:IsA("NumberValue") then
			needed = math.max(1, tonumber(req.Value) or 1)
		else
			needed = Leveling:GetRequiredXP(level.Value)
			if needed <= 0 then needed = 1 end
		end
		-- snap
		local currentXP = xp.Value
		local target = math.clamp(currentXP / needed, 0, 1)
		displayedRatio = target
		bar.Size = UDim2.new(target, 0, 1, 0)
		bar_under.Size = UDim2.new(target, 0, 0.85, 0)
		label.Text = string.format("%d / %d", currentXP, needed)
	end)
	-- Rebind if XP/Level nodes are replaced during a restart/reset
	connectStatsWatch()
	return true
end

tryInit = function()
	if not bindStats(5) then
		-- hide or show placeholder
		label.Text = "--/--"
		return
	end
	-- initial sync
	local currentXP = xp.Value
	local target = math.clamp(currentXP / needed, 0, 1)
	displayedRatio = target
	bar.Size = UDim2.new(target, 0, 1, 0)
	bar_under.Size = UDim2.new(target, 0, 0.85, 0)
	label.Text = string.format("%d / %d", currentXP, needed)
end

tryInit()

-- Reattempt binding on CharacterAdded (Stats recreated)
player.CharacterAdded:Connect(function()
	task.wait(0.25)
	tryInit()
end)

-- Also listen for Stats folder being re-created outside respawn (e.g., during Restart)
player.ChildAdded:Connect(function(child)
	if child.Name == "Stats" then
		task.delay(0.05, function()
			tryInit()
		end)
	end
end)

RunService.Heartbeat:Connect(function(dt)
	if not xp or not level then return end
	local currentXP = xp.Value
	local targetRatio = math.clamp(currentXP / needed, 0, 1)
	displayedRatio = displayedRatio + (targetRatio - displayedRatio) * math.clamp(smooth * dt, 0, 1)
	bar.Size = UDim2.new(displayedRatio, 0, 1, 0)
	bar_under.Size = UDim2.new(displayedRatio, 0, 0.85, 0)
	label.Text = string.format("%d / %d", currentXP, needed)
end)