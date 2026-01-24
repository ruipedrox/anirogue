-- RedShot.lua
-- Gojo's Cursed Technique: Reversal Red - Fires projectile that damages and pushes enemies away
-- 5 levels with increasing damage and knockback

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Projectile = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Projectile"))
local Damage = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("Damage"))

local def = {
	Name = "Reversal: Red",
	Rarity = "Legendary",
	Type = "Active",
	MaxLevel = 5,
	Description = "Fire a repulsive force projectile that damages and pushes enemies away."
}

-- Stats per level
local statsPerLevel = {
	[1] = { damagePercent = 0.50, knockbackPower = 30, size = 1.0, cooldown = 2.5 },
	[2] = { damagePercent = 0.70, knockbackPower = 40, size = 1.2, cooldown = 2.3 },
	[3] = { damagePercent = 0.90, knockbackPower = 50, size = 1.4, cooldown = 2.1 },
	[4] = { damagePercent = 1.10, knockbackPower = 60, size = 1.6, cooldown = 1.9 },
	[5] = { damagePercent = 1.30, knockbackPower = 70, size = 1.8, cooldown = 1.7 }
}

-- Track active Red Shot per player
local ActiveRedShotByUserId = {}

-- Create Red Shot projectile model
local function createRedShotModel(size)
	local model = Instance.new("Model")
	model.Name = "RedShot"
	
	local sphere = Instance.new("Part")
	sphere.Name = "Core"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(2 * size, 2 * size, 2 * size)
	sphere.Color = Color3.fromRGB(255, 50, 50)
	sphere.Material = Enum.Material.Neon
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.CanTouch = false
	sphere.Parent = model
	
	model.PrimaryPart = sphere
	
	-- Red energy particles
	local particles = Instance.new("ParticleEmitter")
	particles.Texture = "rbxasset://textures/particles/smoke_main.dds"
	particles.Color = ColorSequence.new(Color3.fromRGB(255, 100, 100), Color3.fromRGB(255, 0, 0))
	particles.Size = NumberSequence.new(1.5 * size, 0.5 * size)
	particles.Lifetime = NumberRange.new(0.3, 0.6)
	particles.Rate = 40
	particles.Speed = NumberRange.new(2, 5)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.LightEmission = 1
	particles.Transparency = NumberSequence.new(0.2, 1)
	particles.Parent = sphere
	
	return model
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

-- Fire Red Shot projectile
local function fireRedShot(player, stats)
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
	local projectileModel = createRedShotModel(stats.size)
	
	Projectile.Fire({
		origin = origin,
		direction = direction,
		speed = 80,
		lifetime = 3,
		pierce = 999, -- Infinite pierce
		damage = 0, -- We handle damage manually
		model = projectileModel,
		owner = player,
		hitCooldownPerTarget = 0.5,
		onHit = function(hitPart, enemyModel)
			local hum = enemyModel:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				-- Apply damage
				Damage.DealDamage({
					source = player,
					target = hum,
					amount = projectileDamage,
					damageType = "Ability"
				})
				
				-- Apply knockback (push away from projectile)
				local enemyHrp = enemyModel:FindFirstChild("HumanoidRootPart")
				if enemyHrp and enemyHrp:IsA("BasePart") then
					local knockbackDir = (enemyHrp.Position - hitPart.Position).Unit
					local bodyVelocity = Instance.new("BodyVelocity")
					bodyVelocity.MaxForce = Vector3.new(50000, 0, 50000)
					bodyVelocity.Velocity = knockbackDir * stats.knockbackPower
					bodyVelocity.Parent = enemyHrp
					
					task.delay(0.2, function()
						if bodyVelocity then bodyVelocity:Destroy() end
					end)
				end
			end
		end
	})
end

function def.OnEquip(player, level)
	level = math.clamp(level or 1, 1, def.MaxLevel)
	local userId = player.UserId
	
	-- Clean up existing
	if ActiveRedShotByUserId[userId] then
		def.OnUnequip(player)
	end
	
	local stats = statsPerLevel[level]
	local lastFire = 0
	
	-- Heartbeat loop to fire periodically
	local connection = RunService.Heartbeat:Connect(function()
		if not player.Parent or not player.Character then
			def.OnUnequip(player)
			return
		end
		
		local now = os.clock()
		if now - lastFire >= stats.cooldown then
			fireRedShot(player, stats)
			lastFire = now
		end
	end)
	
	ActiveRedShotByUserId[userId] = {
		connection = connection,
		level = level
	}
	
	print(string.format("[Red Shot] Equipped for %s at level %d", player.Name, level))
end

function def.OnUnequip(player)
	local userId = player.UserId
	local data = ActiveRedShotByUserId[userId]
	
	if data then
		if data.connection then
			data.connection:Disconnect()
		end
		ActiveRedShotByUserId[userId] = nil
		print(string.format("[Red Shot] Unequipped for %s", player.Name))
	end
end

function def.OnLevelUp(player, newLevel)
	if ActiveRedShotByUserId[player.UserId] then
		def.OnEquip(player, newLevel)
	end
end

return def
