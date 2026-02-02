-- Buu Blob AI: Seeks Super Buu and heals him on contact

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local enemyModel = script.Parent
local humanoid = enemyModel:FindFirstChildOfClass("Humanoid") or enemyModel:WaitForChild("Humanoid", 2)
local root = enemyModel:FindFirstChild("HumanoidRootPart") or enemyModel:WaitForChild("HumanoidRootPart", 2)

if not root or not humanoid then return end

-- Load Stats
local STATS = nil
do
	local statsModule = enemyModel:FindFirstChild("Stats")
	if statsModule and statsModule:IsA("ModuleScript") then
		local ok, data = pcall(require, statsModule)
		if ok and type(data) == "table" then STATS = data end
	end
end

local MOVE_SPEED = (STATS and STATS.MoveSpeed) or 6
local HEAL_RANGE = 5

humanoid.WalkSpeed = MOVE_SPEED
humanoid.AutoRotate = true

local running = true
local hasHealed = false

-- Cleanup
local function cleanup()
	running = false
	print("[Buu Blob] Cleanup called")
end

humanoid.Died:Connect(function()
	cleanup()
	task.wait(2)
	if enemyModel and enemyModel.Parent then
		enemyModel:Destroy()
	end
end)

enemyModel.AncestryChanged:Connect(function(_, parent)
	if not parent then cleanup() end
end)

-- Find Super Buu
local function findSuperBuu()
	-- Check global reference first
	if _G.SuperBuuInstance and _G.SuperBuuInstance.root and _G.SuperBuuInstance.root.Parent then
		return _G.SuperBuuInstance.root, _G.SuperBuuInstance.humanoid, _G.SuperBuuInstance.healAmount
	end
	
	-- Fallback: search workspace
	for _, model in ipairs(workspace:GetChildren()) do
		if model.Name:match("Super_?Buu") and model:FindFirstChild("HumanoidRootPart") then
			local buuHum = model:FindFirstChildOfClass("Humanoid")
			if buuHum and buuHum.Health > 0 then
				return model:FindFirstChild("HumanoidRootPart"), buuHum, 500
			end
		end
	end
	
	return nil, nil, 0
end

-- Heal Super Buu on contact
local function tryHealSuperBuu()
	if hasHealed then return end
	
	local buuRoot, buuHum, healAmount = findSuperBuu()
	
	if buuRoot and buuHum and buuHum.Health > 0 then
		local dist = (buuRoot.Position - root.Position).Magnitude
		
		if dist <= HEAL_RANGE then
			hasHealed = true
			
			-- Heal Super Buu
			local newHealth = math.min(buuHum.MaxHealth, buuHum.Health + healAmount)
			buuHum.Health = newHealth
			
			print("[Buu Blob] Healed Super Buu for", healAmount, "HP!")
			
			-- Store position before destroying blob
			local healPos = root.CFrame
			
			-- Destroy blob immediately
			running = false
			enemyModel:Destroy()
			
			-- Create visual effect after blob is destroyed
			local explosion = Instance.new("Part")
			explosion.Anchored = true
			explosion.CanCollide = false
			explosion.Shape = Enum.PartType.Ball
			explosion.Material = Enum.Material.Neon
			explosion.Color = Color3.fromRGB(255, 100, 200) -- Pink
			explosion.Transparency = 0.3
			explosion.Size = Vector3.new(1, 1, 1)
			explosion.CFrame = healPos
			explosion.Parent = workspace
			
			-- Expand and fade effect
			task.spawn(function()
				local t = 0
				local duration = 0.3
				local maxSize = 8
				while t < duration and explosion.Parent do
					local alpha = t / duration
					local size = 1 + (maxSize - 1) * alpha
					explosion.Size = Vector3.new(size, size, size)
					explosion.Transparency = 0.3 + (0.7 * alpha)
					task.wait(0.03)
					t += 0.03
				end
				if explosion and explosion.Parent then
					explosion:Destroy()
				end
			end)
		end
	end
end

-- Movement loop: seek Super Buu
task.spawn(function()
	while running do
		if ReplicatedStorage:GetAttribute("GamePaused") then
			task.wait(0.05)
			continue
		end
		
		local buuRoot = findSuperBuu()
		
		if buuRoot and humanoid then
			humanoid:MoveTo(buuRoot.Position)
		end
		
		task.wait(0.1)
	end
end)

-- Contact check loop
task.spawn(function()
	while running do
		if ReplicatedStorage:GetAttribute("GamePaused") then
			task.wait(0.05)
			continue
		end
		
		tryHealSuperBuu()
		
		task.wait(0.1)
	end
end)

print("[Buu Blob] AI initialized! Seeking Super Buu...")
