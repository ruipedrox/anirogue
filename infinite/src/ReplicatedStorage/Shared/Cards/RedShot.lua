-- RedShot.lua
-- Gojo's Cursed Technique: Reversal Red - Fires projectile that damages and pushes enemies away
-- 5 levels with increasing damage and knockback

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Projectile = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Projectile"))
local Damage = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("Damage"))

local SFXHelper      = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("SFXHelper"))
local REDSHOT_SFX_ID = 138240839016415
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- Try to find model assets under ReplicatedStorage.Shared.Chars (e.g. Gojo_5 -> Red/Blue/Purple)
local function findCharAsset(partName)
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	if not shared then return nil end
	local chars = shared:FindFirstChild("Chars")
	if not chars then return nil end
	for _, group in ipairs(chars:GetChildren()) do
		if group:IsA("Folder") or group:IsA("Model") then
			local candidate = group:FindFirstChild(partName)
			if candidate then return candidate end
		end
	end
	return nil
end

local def = {
	Name = "Reversal: Red",
	Rarity = "Legendary",
	Type = "Active",
	MaxLevel = 5,
	Description = "Fire a repulsive force projectile that damages and pushes enemies away."
}

-- Backwards-compat helper used by CardPool
def.maxLevel = def.maxLevel or def.MaxLevel
def.id = def.id or script.Name

-- Stats per level
local statsPerLevel = {
	-- chargeTime: seconds to charge before launching; forwardOffset: spawn distance from player
	[1] = { damagePercent = 1.0,  knockbackPower = 30, size = 1.0, cooldown = 6.0, chargeTime = 1.3, forwardOffset = 8 },
	[2] = { damagePercent = 1.25, knockbackPower = 40, size = 1.5, cooldown = 5.5, chargeTime = 1.3, forwardOffset = 8.5 },
	[3] = { damagePercent = 1.50, knockbackPower = 50, size = 2.0, cooldown = 5.0, chargeTime = 1.3, forwardOffset = 9 },
	[4] = { damagePercent = 1.75, knockbackPower = 60, size = 2.5, cooldown = 4.5, chargeTime = 1.3, forwardOffset = 9.5 },
	[5] = { damagePercent = 2.0,  knockbackPower = 70, size = 3.0, cooldown = 4.0, chargeTime = 1.3, forwardOffset = 10 }
}

-- Track active Red Shot per player
local ActiveRedShotByUserId = {}

-- Create Red Shot projectile model
local function createRedShotModel(size)
	-- Try to reuse an authored model (Gojo_5/Red or RedShot) if present
	local asset = findCharAsset("Red") or findCharAsset("RedShot")
	if asset then
		local aClone = asset:Clone()
		-- If the authored asset is a single Part, wrap it in a Model so callers can rely on model.PrimaryPart
		if aClone:IsA("BasePart") then
			local wrapper = Instance.new("Model")
			wrapper.Name = (aClone.Name ~= "" and aClone.Name) or "RedShotModel"
			-- scale part
			aClone.Size = aClone.Size * (size or 1)
			aClone.CanCollide = false
			aClone.CanTouch = false
			aClone.CanQuery = false
			aClone.Anchored = true
			aClone.Parent = wrapper
			wrapper.PrimaryPart = aClone
			return wrapper
		end

		-- If it's a Model, scale descendants and ensure PrimaryPart
		for _, d in ipairs(aClone:GetDescendants()) do
			if d:IsA("SpecialMesh") then
				d.Scale = d.Scale * (size or 1)
			elseif d:IsA("BasePart") then
				d.Size = d.Size * (size or 1)
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d.Anchored = true
			end
		end
		if not aClone.PrimaryPart then
			for _, c in ipairs(aClone:GetChildren()) do
				if c:IsA("BasePart") then
					aClone.PrimaryPart = c
					break
				end
			end
		end
		return aClone
	end

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

-- Helpers copied/adapted from Kamehameha for charge behavior
local function makeNonBlockingAnchored(inst)
	if inst:IsA("Model") then
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d.Anchored = true
			end
		end
	elseif inst:IsA("BasePart") then
		inst.CanCollide = false
		inst.CanTouch = false
		inst.CanQuery = false
		inst.Anchored = true
	end
end

local function positionInFront(inst, hrp, forwardOffset)
	local forward = hrp.CFrame.LookVector
	-- place closer to the ground for more consistent enemy hits
	local spawnPos = hrp.Position + forward * (forwardOffset or 4) + Vector3.new(0, 0.5, 0)
	local cf = CFrame.new(spawnPos, spawnPos + forward)
	if inst:IsA("Model") then
		inst:PivotTo(cf)
	else
		inst.CFrame = cf
	end
end

local function startFollow(inst, hrp, forwardOffset)
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not inst.Parent or not hrp.Parent then
			if conn then conn:Disconnect() end
			return
		end
		if ReplicatedStorage:GetAttribute("GamePaused") then return end
		positionInFront(inst, hrp, forwardOffset)
	end)
	return conn
end

local function scaleChargeModel(model, factor)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("SpecialMesh") then
			d.Scale = d.Scale * factor
		elseif d:IsA("BasePart") then
			local s = d.Size
			d.Size = Vector3.new(math.max(0.05, s.X * factor), math.max(0.05, s.Y * factor), math.max(0.05, s.Z * factor))
		end
	end
end

local function captureOriginalScales(model)
	local t = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("SpecialMesh") then
			t[d] = d.Scale
		elseif d:IsA("BasePart") then
			t[d] = d.Size
		end
	end
	return t
end

local function applyScaleFromOriginals(origTable, factor)
	for inst, orig in pairs(origTable) do
		if inst and inst.Parent then
			if typeof(orig) == "Vector3" then
				inst.Size = orig * factor
			else
				inst.Scale = orig * factor
			end
		end
	end
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

	-- Spawn the charge visual in front of the player (do not change part size)
	local forward = hrp.CFrame.LookVector
	local spawnPos = hrp.Position + forward * ((stats.forwardOffset or 4) + (stats.size or 1)) + Vector3.new(0, 0.5, 0)
	local chargeModel = createRedShotModel(stats.size)
	if chargeModel and chargeModel.PrimaryPart then
		chargeModel:PivotTo(CFrame.new(spawnPos, spawnPos + forward))
	end
	chargeModel.Parent = workspace

	-- SFX 3D: tocar no modelo do charge (segue o projétil)
	do
		local sfxPart = chargeModel:IsA("Model") and chargeModel.PrimaryPart or (chargeModel:IsA("BasePart") and chargeModel)
		if sfxPart then
			SFXHelper.playAt(sfxPart, REDSHOT_SFX_ID, 0.85, { minDist = 15, maxDist = 80, lifetime = 3 })
		end
	end

	-- capture particle original rates for transition
	local particleRates = {}
	for _, d in ipairs(chargeModel:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			particleRates[d] = d.Rate
		end
	end

	-- Kamehameha-like charge: anchor, follow and scale over time
	makeNonBlockingAnchored(chargeModel)
	positionInFront(chargeModel, hrp, stats.forwardOffset or 4)
	local followConn = startFollow(chargeModel, hrp, stats.forwardOffset or 4)
	local originals = captureOriginalScales(chargeModel)
	local chargeTime = math.max(0.01, stats.chargeTime or 0.8)
	local elapsed = 0
	local targetScale = 1 + (2 * (stats.size or 1))
	local finalScale = 1
	while elapsed < chargeTime do
		local dt = RunService.Heartbeat:Wait()
		elapsed = elapsed + dt
		local alpha = math.clamp(elapsed / chargeTime, 0, 1)
		local factor = 1 + alpha * (targetScale - 1)
		applyScaleFromOriginals(originals, factor)
		-- fade particle rates progressively
		for emitter, r in pairs(particleRates) do
			if emitter and emitter.Parent then
				emitter.Rate = r * (0.5 + 0.5 * alpha)
			end
		end
	end

	finalScale = targetScale
	if followConn then followConn:Disconnect() end
	applyScaleFromOriginals(originals, finalScale)

	-- Smooth transition before firing: shrink slightly and fade particles
	local transTime = 0.12
	local tElapsed = 0
	local startScale = finalScale
	local endScale = math.max(0.4, finalScale * 0.6)
	while tElapsed < transTime do
		local dt = RunService.Heartbeat:Wait()
		tElapsed = tElapsed + dt
		local a = math.clamp(tElapsed / transTime, 0, 1)
		local factor = startScale * (1 - a) + endScale * a
		applyScaleFromOriginals(originals, factor)
		for emitter, r in pairs(particleRates) do
			if emitter and emitter.Parent then
				emitter.Rate = r * (1 - a)
			end
		end
	end

	-- compute origin/direction at moment of fire
	local origin
	if chargeModel and chargeModel.PrimaryPart then
		origin = chargeModel.PrimaryPart.Position
	else
		origin = hrp.Position + hrp.CFrame.LookVector * (stats.forwardOffset or 4)
	end
	local currentForward = hrp.CFrame.LookVector
	local dirXZ = currentForward * Vector3.new(1, 0, 1)
	local direction
	if dirXZ.Magnitude < 1e-3 then
		direction = Vector3.new(0, 0, -1)
	else
		direction = dirXZ.Unit
	end

	-- destroy charge visual after transition
	if chargeModel and chargeModel.Parent then
		pcall(function() chargeModel:Destroy() end)
	end

	-- (origin and direction computed at firing time above)
	
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
	-- Ensure projectile matches the final visual scale from the charge
	local scaleForProjectile = (finalScale or 1) * (stats.size or 1)
	local projectileModel = createRedShotModel(scaleForProjectile)
	
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
				Damage.Apply(hum, projectileDamage, { damageType = "Ability" })
				
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

				-- Clean up charge visual after firing
				if chargeModel and chargeModel.Parent then
					pcall(function() chargeModel:Destroy() end)
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
	local charging = false

	-- Heartbeat loop to fire periodically (avoid overlapping charges)
	local connection = RunService.Heartbeat:Connect(function()
		if not player.Parent or not player.Character then
			def.OnUnequip(player)
			return
		end

		local now = os.clock()
		if not charging and (now - lastFire >= stats.cooldown) then
			charging = true
			lastFire = now -- start cooldown from charge start to prevent overlapping
			task.spawn(function()
				local ok, err = pcall(fireRedShot, player, stats)
				if not ok then warn("[RedShot] fireRedShot error:", err) end
				charging = false
			end)
		end
	end)
	
	ActiveRedShotByUserId[userId] = {
		connection = connection,
		level = level
	}

	-- Ensure RunTrack entry exists and reflect equipped level so CardPool can exclude when at max
	local runTrack = player:FindFirstChild("RunTrack") or Instance.new("Folder")
	runTrack.Name = "RunTrack"
	runTrack.Parent = player
	local myFolder = runTrack:FindFirstChild(def.id or script.Name) or Instance.new("Folder")
	myFolder.Name = def.id or script.Name
	myFolder.Parent = runTrack
	local lvlNV = myFolder:FindFirstChild("Level") or Instance.new("IntValue")
	lvlNV.Name = "Level"
	lvlNV.Value = tonumber(level) or (def.MaxLevel or def.maxLevel or 1)
	lvlNV.Parent = myFolder
	
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

-- Compatibility for CardDispatcher: called when a card instance is added (levelable/stackable support)
function def.OnCardAdded(player, defTable, level)
    def.OnEquip(player, level or 1)
end

return def
