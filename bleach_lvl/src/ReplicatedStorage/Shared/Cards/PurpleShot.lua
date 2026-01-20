-- PurpleShot.lua
-- Gojo's Imaginary Technique: Hollow Purple - Ultimate combination of Red and Blue
-- Only available when both Red Shot and Blue Shot are at max level
-- Fires devastating purple projectile with massive damage
-- When equipped, disables Red Shot and Blue Shot firing

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Projectile = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Projectile"))
local Damage = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("Damage"))

local def = {
	Name = "Hollow Purple",
	Rarity = "Mythic",
	Type = "Active",
	MaxLevel = 1,
	Description = "The ultimate imaginary mass. Combines Red and Blue into a devastating projectile of pure destruction. Replaces Red and Blue shots.",
	-- Requirement: RedShot level 5 AND BlueShot level 5
	RequiredCards = {
		{ cardId = "RedShot", minLevel = 5 },
		{ cardId = "BlueShot", minLevel = 5 }
	}
}

-- Stats (only 1 level)
local stats = {
	damagePercent = 3.0, -- 300% damage - balanced
	explosionRadius = 12,
	size = 3.0,
	cooldown = 8.0,
	speed = 60
}

-- Track active Purple Shot per player
local ActivePurpleShotByUserId = {}

-- Create Purple Shot projectile model
local function createPurpleShotModel(size)
	local model = Instance.new("Model")
	model.Name = "PurpleShot"
	
	local sphere = Instance.new("Part")
	sphere.Name = "Core"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(3 * size, 3 * size, 3 * size)
	sphere.Color = Color3.fromRGB(150, 50, 200)
	sphere.Material = Enum.Material.Neon
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.CanTouch = false
	sphere.Parent = model
	
	model.PrimaryPart = sphere
	
	-- Purple energy particles (combination of red and blue)
	local particles = Instance.new("ParticleEmitter")
	particles.Texture = "rbxasset://textures/particles/smoke_main.dds"
	particles.Color = ColorSequence.new(Color3.fromRGB(200, 100, 255), Color3.fromRGB(100, 0, 200))
	particles.Size = NumberSequence.new(2.5 * size, 1.0 * size)
	particles.Lifetime = NumberRange.new(0.4, 0.8)
	particles.Rate = 60
	particles.Speed = NumberRange.new(3, 8)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.LightEmission = 1
	particles.Transparency = NumberSequence.new(0.1, 1)
	particles.Parent = sphere
	
	-- Add inner glow
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(150, 50, 200)
	glow.Brightness = 5
	glow.Range = 20 * size
	glow.Parent = sphere
	
	return model
end

-- Create explosion effect
local function createExplosion(position, radius)
	local explosion = Instance.new("Part")
	explosion.Name = "PurpleExplosion"
	explosion.Shape = Enum.PartType.Ball
	explosion.Size = Vector3.new(0.5, 0.5, 0.5)
	explosion.Color = Color3.fromRGB(150, 50, 200)
	explosion.Material = Enum.Material.Neon
	explosion.Anchored = true
	explosion.CanCollide = false
	explosion.CanQuery = false
	explosion.CanTouch = false
	explosion.Position = position
	explosion.Parent = workspace
	
	-- Expand explosion
	local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local goal = { Size = Vector3.new(radius * 2, radius * 2, radius * 2), Transparency = 1 }
	
	local TweenService = game:GetService("TweenService")
	local tween = TweenService:Create(explosion, tweenInfo, goal)
	tween:Play()
	
	tween.Completed:Connect(function()
		explosion:Destroy()
	end)
end

-- Find nearest enemy
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

-- Fire Purple Shot projectile
local function firePurpleShot(player)
	local character = player.Character
	if not character then return end
	
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	local targetHrp = findNearestEnemy(hrp.Position)
	if not targetHrp then return end
	
	local origin = hrp.Position + Vector3.new(0, 2, 0)
	-- TOP-DOWN: Ignore Y axis when aiming
	local direction = (targetHrp.Position - origin) * Vector3.new(1, 0, 1)
	if direction.Magnitude < 1e-3 then
		direction = Vector3.new(0, 0, -1)
	else
		direction = direction.Unit
	end
	
	-- Get base damage from player stats
	local playerStats = player:FindFirstChild("Stats")
	local baseDamage = 50
	if playerStats then
		local dmgValue = playerStats:FindFirstChild("BaseDamage")
		if dmgValue and dmgValue:IsA("NumberValue") then
			baseDamage = dmgValue.Value
		end
	end
	
	local projectileDamage = baseDamage * stats.damagePercent
	local projectileModel = createPurpleShotModel(stats.size)
	local hitEnemies = {} -- Track enemies hit by this specific purple shot
	
	Projectile.Fire({
		origin = origin,
		direction = direction,
		speed = stats.speed,
		lifetime = 5,
		pierce = 999, -- Infinite pierce
		damage = 0, -- We handle damage manually
		model = projectileModel,
		owner = player,
		hitCooldownPerTarget = 0.3,
		onHit = function(hitPart, enemyModel)
			-- Only damage each enemy once per purple shot
			if hitEnemies[enemyModel] then return end
			hitEnemies[enemyModel] = true
			
			local hum = enemyModel:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				-- Apply massive damage
				Damage.DealDamage({
					source = player,
					target = hum,
					amount = projectileDamage,
					damageType = "Ability"
				})
				
				-- Create explosion effect
				local hitPos = hitPart.Position
				createExplosion(hitPos, stats.explosionRadius)
				
				-- Damage all enemies in explosion radius
				for _, enemy in ipairs(CollectionService:GetTagged("Enemy")) do
					if enemy:IsA("Model") and enemy ~= enemyModel then
						local enemyHum = enemy:FindFirstChildOfClass("Humanoid")
						local enemyHrp = enemy:FindFirstChild("HumanoidRootPart")
						
						if enemyHum and enemyHum.Health > 0 and enemyHrp then
							local dist = (enemyHrp.Position - hitPos).Magnitude
							if dist <= stats.explosionRadius then
								-- Apply AOE damage (50% of main damage)
								Damage.DealDamage({
									source = player,
									target = enemyHum,
									amount = projectileDamage * 0.5,
									damageType = "Ability"
								})
							end
						end
					end
				end
			end
		end
	})
end

function def.OnEquip(player, level)
	local userId = player.UserId
	
	-- Clean up existing
	if ActivePurpleShotByUserId[userId] then
		def.OnUnequip(player)
	end
	
	-- Disable Red Shot and Blue Shot if they're active
	local RedShot = require(script.Parent:WaitForChild("RedShot"))
	local BlueShot = require(script.Parent:WaitForChild("BlueShot"))
	
	if RedShot.OnUnequip then RedShot.OnUnequip(player) end
	if BlueShot.OnUnequip then BlueShot.OnUnequip(player) end
	
	local lastFire = 0
	
	-- Heartbeat loop to fire periodically
	local connection = RunService.Heartbeat:Connect(function()
		if not player.Parent or not player.Character then
			def.OnUnequip(player)
			return
		end
		
		local now = os.clock()
		if now - lastFire >= stats.cooldown then
			firePurpleShot(player)
			lastFire = now
		end
	end)
	
	ActivePurpleShotByUserId[userId] = {
		connection = connection
	}
	
	print(string.format("[Hollow Purple] Equipped for %s - Red and Blue disabled", player.Name))
end

function def.OnUnequip(player)
	local userId = player.UserId
	local data = ActivePurpleShotByUserId[userId]
	
	if data then
		if data.connection then
			data.connection:Disconnect()
		end
		ActivePurpleShotByUserId[userId] = nil
		print(string.format("[Hollow Purple] Unequipped for %s", player.Name))
	end
end

return def
