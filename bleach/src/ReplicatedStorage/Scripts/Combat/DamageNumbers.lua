-- DamageNumbers.lua
-- Visual feedback for damage dealt with color-coded damage types

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DamageNumbers = {}

-- Toggle damage numbers on/off
DamageNumbers.Enabled = true

-- Get or create RemoteEvent for client-server communication
local function getRemoteEvent()
	local remote = ReplicatedStorage:FindFirstChild("ShowDamageNumber")
	if not remote then
		if RunService:IsServer() then
			remote = Instance.new("RemoteEvent")
			remote.Name = "ShowDamageNumber"
			remote.Parent = ReplicatedStorage
			print("[DamageNumbers] RemoteEvent created on server")
		else
			-- Client: wait for server to create it
			remote = ReplicatedStorage:WaitForChild("ShowDamageNumber", 10)
			print("[DamageNumbers] RemoteEvent found on client")
		end
	end
	return remote
end

-- Color configurations for each damage type
local DamageColors = {
	normal = Color3.fromRGB(255, 255, 255), -- White
	crit = Color3.fromRGB(255, 50, 50), -- Red
	bleed = Color3.fromRGB(200, 0, 0), -- Dark red
	rupture = Color3.fromRGB(30, 30, 30), -- Black
	blackflames = Color3.fromRGB(30, 30, 30), -- Black (with white outline)
	burn = Color3.fromRGB(255, 140, 0), -- Orange
	poison = Color3.fromRGB(0, 255, 100), -- Green
	infection = Color3.fromRGB(255, 100, 200), -- Pink
	electric = Color3.fromRGB(100, 200, 255) -- Blue
}

-- Display damage number at position (CLIENT ONLY)
-- opts = { position: Vector3, amount: number, damageType: string?, critCount: number? }
local function showDamageNumberClient(opts)
	if not DamageNumbers.Enabled then return end
	if not opts or not opts.position or not opts.amount then return end
	
	local position = opts.position
	local amount = math.floor(opts.amount)
	local damageType = opts.damageType or "normal"
	local critCount = opts.critCount or 0
	
	-- Determine display type
	local displayType = damageType
	if critCount > 0 then
		displayType = "crit"
	end
	
	-- Get color
	local color = DamageColors[displayType] or DamageColors.normal
	
	-- Create billboard
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 100, 0, 40)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = nil
	billboard.Parent = workspace
	
	-- Create label
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.5
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = billboard
	
	-- Special outline for black flames
	if displayType == "blackflames" then
		label.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
		label.TextStrokeTransparency = 0.3
	end
	
	-- Format text
	local text = tostring(amount)
	if critCount > 0 then
		if critCount == 1 then
			text = "CRIT! " .. text
		else
			text = string.format("CRIT x%d! %d", critCount, amount)
		end
	end
	label.Text = text
	
	-- Position billboard
	local part = Instance.new("Part")
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Anchored = true
	part.Position = position
	part.Parent = workspace
	billboard.Adornee = part
	
	-- Random offset
	local randomX = math.random(-20, 20) / 10
	local randomZ = math.random(-20, 20) / 10
	
	-- Animate: rise up and fade out
	local tweenInfo = TweenInfo.new(
		1.5, -- Duration
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	
	local goal = {
		StudsOffset = Vector3.new(randomX, 6, randomZ)
	}
	
	local tween = TweenService:Create(billboard, tweenInfo, goal)
	tween:Play()
	
	-- Fade out
	task.spawn(function()
		task.wait(0.5)
		for i = 1, 20 do
			label.TextTransparency = i / 20
			label.TextStrokeTransparency = 0.5 + (i / 20) * 0.5
			task.wait(0.05)
		end
		billboard:Destroy()
		part:Destroy()
	end)
end

-- Main Show function - works on both server and client
function DamageNumbers.Show(opts)
	if not DamageNumbers.Enabled then return end
	
	if RunService:IsClient() then
		-- Client: show directly
		print("[DamageNumbers] Client showing:", opts.amount, opts.damageType)
		showDamageNumberClient(opts)
	else
		-- Server: send to all clients
		print("[DamageNumbers] Server sending:", opts.amount, opts.damageType)
		local remote = getRemoteEvent()
		if remote then
			remote:FireAllClients(opts)
		else
			warn("[DamageNumbers] RemoteEvent not found!")
		end
	end
end

-- Setup client listener if on client
if RunService:IsClient() then
	print("[DamageNumbers] Setting up client listener...")
	local remote = getRemoteEvent()
	if remote then
		remote.OnClientEvent:Connect(function(opts)
			print("[DamageNumbers] Client received event:", opts.amount, opts.damageType)
			showDamageNumberClient(opts)
		end)
		print("[DamageNumbers] Client listener connected!")
	else
		warn("[DamageNumbers] Failed to setup client listener - RemoteEvent not found")
	end
end

return DamageNumbers
