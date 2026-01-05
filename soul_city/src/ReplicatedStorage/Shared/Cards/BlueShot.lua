-- BlueShot.lua
-- Gojo's Cursed Technique: Lapse Blue - Fires projectile that damages and pulls enemies toward it
-- 5 levels with increasing damage and pull force

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Projectile = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Projectile"))
local Damage = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("Damage"))

local def = {
	Name = "Lapse: Blue",
	Rarity = "Legendary",
	Type = "Active",
	MaxLevel = 5,
	Description = "Fire an attractive force projectile that damages and pulls enemies toward it."
}

-- Stats per level
local statsPerLevel = {
	[1] = { damagePercent = 0.40, pullPower = 25, size = 1.0, cooldown = 2.5 },
	[2] = { damagePercent = 0.60, pullPower = 35, size = 1.2, cooldown = 2.3 },
	[3] = { damagePercent = 0.80, pullPower = 45, size = 1.4, cooldown = 2.1 },
	[4] = { damagePercent = 1.00, pullPower = 55, size = 1.6, cooldown = 1.9 },
	[5] = { damagePercent = 1.20, pullPower = 65, size = 1.8, cooldown = 1.7 }
}

-- Track active Blue Shot per player
local ActiveBlueShotByUserId = {}

-- Create Blue Shot projectile model
local function createBlueShotModel(size)
	local model = Instance.new("Model")
	model.Name = "BlueShot"
	
	local sphere = Instance.new("Part")
	sphere.Name = "Core"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(2 * size, 2 * size, 2 * size)
	sphere.Color = Color3.fromRGB(50, 100, 255)
	sphere.Material = Enum.Material.Neon
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.CanTouch = false
	sphere.Parent = model
	
	model.PrimaryPart = sphere
	
	-- Blue energy particles
	local particles = Instance.new("ParticleEmitter")
	particles.Texture = "rbxasset://textures/particles/smoke_main.dds"
	particles.Color = ColorSequence.new(Color3.fromRGB(100, 150, 255), Color3.fromRGB(0, 50, 255))
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

-- Fire Blue Shot projectile
local function fireBlueShot(player, stats)
	local character = player.Character
	if not character then return end
	
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	local targetHrp = findNearestEnemy(hrp.Position)
	if not targetHrp then return end
	
	local origin = hrp.Position + Vector3.new(0, 2, 0)
	local direction = (targetHrp.Position - origin).Unit
	
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
	local projectileModel = createBlueShotModel(stats.size)
	
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
				
				-- Apply pull (toward projectile)
				local enemyHrp = enemyModel:FindFirstChild("HumanoidRootPart")
				if enemyHrp and enemyHrp:IsA("BasePart") then
					local pullDir = (hitPart.Position - enemyHrp.Position).Unit
					local bodyVelocity = Instance.new("BodyVelocity")
					bodyVelocity.MaxForce = Vector3.new(50000, 0, 50000)
					bodyVelocity.Velocity = pullDir * stats.pullPower
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
	if ActiveBlueShotByUserId[userId] then
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
			fireBlueShot(player, stats)
			lastFire = now
		end
	end)
	
	ActiveBlueShotByUserId[userId] = {
		connection = connection,
		level = level
	}
	
	print(string.format("[Blue Shot] Equipped for %s at level %d", player.Name, level))
end

function def.OnUnequip(player)
	local userId = player.UserId
	local data = ActiveBlueShotByUserId[userId]
	
	if data then
		if data.connection then
			data.connection:Disconnect()
		end
		ActiveBlueShotByUserId[userId] = nil
		print(string.format("[Blue Shot] Unequipped for %s", player.Name))
	end
end

function def.OnLevelUp(player, newLevel)
	if ActiveBlueShotByUserId[player.UserId] then
		def.OnEquip(player, newLevel)
	end
end

return def
