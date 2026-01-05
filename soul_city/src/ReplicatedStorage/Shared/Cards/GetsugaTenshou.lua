-- GetsugaTenshou.lua
-- Ichigo's Getsuga Tenshou - fires powerful energy projectiles at nearest enemy
-- Projectiles have infinite pierce and scale with card level

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Projectile = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Projectile"))

local def = {
	Name = "Getsuga Tenshou",
	Rarity = "Legendary",
	Type = "Active",
	MaxLevel = 5,
	Description = "Fire powerful energy projectiles at the nearest enemy. Projectiles pierce through all enemies."
}

-- Stats per level
local statsPerLevel = {
	[1] = { projectileCount = 1, damagePercent = 0.20, size = 1.0, cooldown = 3.0 },
	[2] = { projectileCount = 1, damagePercent = 0.40, size = 1.0, cooldown = 2.8 },
	[3] = { projectileCount = 2, damagePercent = 0.60, size = 1.5, cooldown = 2.6 },
	[4] = { projectileCount = 2, damagePercent = 0.80, size = 1.5, cooldown = 2.4 },
	[5] = { projectileCount = 3, damagePercent = 1.00, size = 2.0, cooldown = 2.0 }
}

-- Track active Getsuga per player
local ActiveGetsugaByUserId = {}

-- Cache for Getsuga model
local getsugaModelSource = nil
local function getGetsugaModel()
	if getsugaModelSource then return getsugaModelSource end
	
	-- Search for getsuga model in Ichigo_5 folder
	local charsFolder = ReplicatedStorage:FindFirstChild("Shared")
	charsFolder = charsFolder and charsFolder:FindFirstChild("Chars")
	local ichigoFolder = charsFolder and charsFolder:FindFirstChild("Ichigo_5")
	
	if ichigoFolder then
		local getsuga = ichigoFolder:FindFirstChild("Getsuga", true)
		if getsuga then
			getsugaModelSource = getsuga
			print("[Getsuga] Found Getsuga model in Ichigo_5")
			return getsugaModelSource
		end
	end
	
	warn("[Getsuga] Could not find Getsuga model in Ichigo_5, will create default")
	return nil
end

-- Create Getsuga projectile model (fallback if model not found)
local function createGetsugaModel(size)
	local model = Instance.new("Model")
	model.Name = "GetsugaTenshou"
	
	-- Main blade part
	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Size = Vector3.new(0.5 * size, 3 * size, 5 * size)
	blade.Color = Color3.fromRGB(0, 150, 255)
	blade.Material = Enum.Material.Neon
	blade.Anchored = true
	blade.CanCollide = false
	blade.CanQuery = false
	blade.CanTouch = false
	blade.Parent = model
	
	model.PrimaryPart = blade
	
	-- Energy trail effect
	local trail = Instance.new("ParticleEmitter")
	trail.Name = "EnergyTrail"
	trail.Texture = "rbxasset://textures/particles/smoke_main.dds"
	trail.Color = ColorSequence.new(Color3.fromRGB(100, 200, 255), Color3.fromRGB(0, 100, 200))
	trail.Size = NumberSequence.new(2 * size, 3 * size)
	trail.Lifetime = NumberRange.new(0.3, 0.6)
	trail.Rate = 50
	trail.Speed = NumberRange.new(0, 2)
	trail.SpreadAngle = Vector2.new(20, 20)
	trail.LightEmission = 1
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Parent = blade
	
	return model
end

-- Find nearest enemy to player
local function findNearestEnemy(playerPos)
	local nearestEnemy = nil
	local nearestDist = math.huge
	
	for _, enemy in ipairs(CollectionService:GetTagged("Enemy")) do
		if enemy:IsA("Model") then
			local hum = enemy:FindFirstChildOfClass("Humanoid")
			local hrp = enemy:FindFirstChild("HumanoidRootPart")
			
			if hum and hum.Health > 0 and hrp then
				local dist = (hrp.Position - playerPos).Magnitude
				if dist < nearestDist then
					nearestDist = dist
					nearestEnemy = hrp
				end
			end
		end
	end
	
	return nearestEnemy
end

-- Fire Getsuga projectile
local function fireGetsuga(player, level)
	local stats = statsPerLevel[level]
	if not stats then return end
	
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	-- Get base damage from player
	local baseDamage = player:GetAttribute("Damage") or 10
	local projectileDamage = baseDamage * stats.damagePercent
	
	-- Find nearest enemy or use random direction
	local targetPos = findNearestEnemy(hrp.Position)
	local direction
	
	if targetPos then
		-- Aim at enemy
		direction = (targetPos.Position - hrp.Position).Unit
	else
		-- No enemies alive, fire in random direction
		local randomAngle = math.random() * math.pi * 2
		direction = Vector3.new(math.cos(randomAngle), 0, math.sin(randomAngle))
	end
	
	-- Fire multiple projectiles in 360° pattern
	for i = 1, stats.projectileCount do
		-- Calculate angle for even distribution in 360°
		local angleStep = math.rad(360 / stats.projectileCount)
		local angle = angleStep * (i - 1)
		
		-- Apply rotation around Y axis
		local spreadDir = CFrame.new(Vector3.zero, direction) * CFrame.Angles(0, angle, 0)
		local finalDir = spreadDir.LookVector
		
		-- Get or create projectile model
		local modelSource = getGetsugaModel()
		local projectileModel
		
		if modelSource then
			-- Clone the getsuga model and scale it
			projectileModel = modelSource:Clone()
			
			-- Scale the model and ensure parts are configured for projectiles
			if projectileModel:IsA("Model") then
				local primaryPart = projectileModel.PrimaryPart or projectileModel:FindFirstChildWhichIsA("BasePart")
				if primaryPart then
					-- Scale all parts in the model and configure for projectile use
					for _, obj in ipairs(projectileModel:GetDescendants()) do
						if obj:IsA("BasePart") then
							obj.Size = obj.Size * stats.size
							obj.Anchored = true
							obj.CanCollide = false
							obj.CanQuery = false
							obj.CanTouch = false
						end
					end
				end
			elseif projectileModel:IsA("BasePart") then
				projectileModel.Size = projectileModel.Size * stats.size
				projectileModel.Anchored = true
				projectileModel.CanCollide = false
				projectileModel.CanQuery = false
				projectileModel.CanTouch = false
			end
		else
			-- Fallback to created model
			projectileModel = createGetsugaModel(stats.size)
		end
		
		task.delay(i * 0.05, function() -- Slight delay between projectiles
			Projectile.Fire({
				origin = hrp.Position + Vector3.new(0, 2, 0),
				direction = finalDir,
				speed = 40,
				lifetime = 5,
				pierce = math.huge, -- Infinite pierce
				damage = projectileDamage,
				owner = player,
				ignore = { char },
				model = projectileModel,
				orientationOffset = CFrame.Angles(0, math.rad(-45), 0),
				contactRadius = 1.5 * stats.size,
				hitCooldownPerTarget = 0.5,
			})
		end)
	end
	
	print(string.format("[Getsuga] Player %s fired Getsuga Tenshou Lv%d: %d projectiles, %.0f damage each",
		player.Name,
		level,
		stats.projectileCount,
		projectileDamage
	))
end

-- Auto-fire loop
local function startGetsugaLoop(player, level)
	local stats = statsPerLevel[level]
	if not stats then return end
	
	local thread = task.spawn(function()
		while true do
			-- Wait for cooldown
			task.wait(stats.cooldown)
			
			-- Check if player still has the card
			if not ActiveGetsugaByUserId[player.UserId] then
				break
			end
			
			-- Respect pause
			while ReplicatedStorage:GetAttribute("GamePaused") do
				task.wait(0.1)
			end
			
			-- Check if player still exists
			if not player.Parent or not player.Character then
				break
			end
			
			-- Fire Getsuga
			fireGetsuga(player, level)
		end
	end)
	
	return thread
end

function def.OnCardAdded(player: Player, cardData, currentLevel: number)
	local level = math.clamp(currentLevel or 1, 1, def.MaxLevel)
	local stats = statsPerLevel[level]
	
	if not stats then
		warn("[Getsuga] Invalid level:", level)
		return
	end
	
	-- Cancel old thread if upgrading
	if ActiveGetsugaByUserId[player.UserId] then
		local oldData = ActiveGetsugaByUserId[player.UserId]
		if oldData.thread then
			task.cancel(oldData.thread)
		end
	end
	
	-- Start auto-fire loop
	local thread = startGetsugaLoop(player, level)
	
	ActiveGetsugaByUserId[player.UserId] = {
		level = level,
		thread = thread
	}
	
	print(string.format("[Getsuga] Player %s activated Getsuga Tenshou Lv%d", player.Name, level))
end

function def.OnCardRemoved(player: Player, cardData)
	local data = ActiveGetsugaByUserId[player.UserId]
	if not data then return end
	
	-- Cancel auto-fire thread
	if data.thread then
		task.cancel(data.thread)
	end
	
	-- Cleanup
	ActiveGetsugaByUserId[player.UserId] = nil
	
	print(string.format("[Getsuga] Player %s deactivated Getsuga Tenshou", player.Name))
end

-- Cleanup on player leaving
game:GetService("Players").PlayerRemoving:Connect(function(player)
	local data = ActiveGetsugaByUserId[player.UserId]
	if data and data.thread then
		task.cancel(data.thread)
	end
	ActiveGetsugaByUserId[player.UserId] = nil
end)

return def
