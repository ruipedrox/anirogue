-- PurpleShot.lua
-- Gojo's Imaginary Technique: Hollow Purple - Ultimate combination of Red and Blue
-- Combines Red and Blue visuals, merges them, then fires a devastating purple projectile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Projectile = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Projectile"))
local Damage = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("Damage"))

local def = {
	Name = "Hollow Purple",
	Rarity = "Mythic",
	Type = "Active",
	MaxLevel = 1,
	Description = "The ultimate imaginary mass. Combines Red and Blue into a devastating projectile of pure destruction. Replaces Red and Blue shots.",
	RequiredCards = {
		{ cardId = "Gojo_RedShot", minLevel = 5 },
		{ cardId = "Gojo_BlueShot", minLevel = 5 }
	}
}

-- Mirror legacy lowercase maxLevel for CardPool checks
def.maxLevel = def.MaxLevel

-- Ensure module has an id usable by RunTrack/DisabledCards (fallback to script name)
def.id = def.id or script.Name

-- Stats (only 1 level)
local stats = {
	-- Significantly increased for "very very big" effect per user request
	damagePercent = 5.0, -- 500% damage
	explosionRadius = 200, -- very large area of effect
	size = 40.0, -- very large projectile visual
	cooldown = 8.0,
	speed = 80
}

local ActivePurpleShotByUserId = {}

local function scaleModelParts(model, factor)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("SpecialMesh") then
			d.Scale = d.Scale * (factor or 1)
		elseif d:IsA("BasePart") then
			d.Size = d.Size * (factor or 1)
		end
	end
end

-- Find a reusable visual asset under ReplicatedStorage.Shared.Chars
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
local function createPurpleShotModel(size)
	-- Try to reuse an authored Purple model or Part if present
	local asset = findCharAsset("Purple") or findCharAsset("InfinitySphere")
	if asset then
		local clone = asset:Clone()
		-- If the authored asset is a single Part, wrap it in a Model so callers can rely on a Model with PrimaryPart
		if clone:IsA("BasePart") then
			-- scale the part and anchor so it doesn't fall while charging
			clone.Size = clone.Size * (size or 1)
			clone.CanCollide = false
			clone.CanTouch = false
			clone.CanQuery = false
			clone.Anchored = true
			local wrapper = Instance.new("Model")
			wrapper.Name = clone.Name .. "_Wrapper"
			clone.Parent = wrapper
			wrapper.PrimaryPart = clone
			return wrapper
		end

		-- Otherwise it's a Model: scale descendants and ensure PrimaryPart
		scaleModelParts(clone, size or 1)
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d.Anchored = true
			end
		end
		if not clone.PrimaryPart then
			for _, c in ipairs(clone:GetChildren()) do
				if c:IsA("BasePart") then
					clone.PrimaryPart = c
					break
				end
			end
		end
		return clone
	end

	local model = Instance.new("Model")
	model.Name = "PurpleShot"
	local sphere = Instance.new("Part")
	sphere.Name = "Core"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(3 * (size or 1), 3 * (size or 1), 3 * (size or 1))
	sphere.Color = Color3.fromRGB(150, 50, 200)
	sphere.Material = Enum.Material.Neon
	sphere.Anchored = false
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.CanTouch = false
	sphere.Parent = model
	model.PrimaryPart = sphere
	local particles = Instance.new("ParticleEmitter")
	particles.Texture = "rbxasset://textures/particles/smoke_main.dds"
	particles.Color = ColorSequence.new(Color3.fromRGB(200,100,255), Color3.fromRGB(100,0,200))
	particles.Size = NumberSequence.new(2.5 * (size or 1), 1.0 * (size or 1))
	particles.Lifetime = NumberRange.new(0.4, 0.8)
	particles.Rate = 60
	particles.Speed = NumberRange.new(3,8)
	particles.SpreadAngle = Vector2.new(180,180)
	particles.LightEmission = 1
	particles.Transparency = NumberSequence.new(0.1,1)
	particles.Parent = sphere
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(150,50,200)
	glow.Brightness = 5
	glow.Range = 20 * (size or 1)
	glow.Parent = sphere
	return model
end

local function createExplosion(position, radius)
	local explosion = Instance.new("Part")
	explosion.Name = "PurpleExplosion"
	explosion.Shape = Enum.PartType.Ball
	explosion.Size = Vector3.new(0.5,0.5,0.5)
	explosion.Color = Color3.fromRGB(150,50,200)
	explosion.Material = Enum.Material.Neon
	explosion.Anchored = true
	explosion.CanCollide = false
	explosion.CanQuery = false
	explosion.CanTouch = false
	explosion.Position = position
	explosion.Parent = workspace
	local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local goal = { Size = Vector3.new(radius * 2, radius * 2, radius * 2), Transparency = 1 }
	local tween = TweenService:Create(explosion, tweenInfo, goal)
	tween:Play()
	tween.Completed:Connect(function() explosion:Destroy() end)
end

local function findNearestEnemy(playerPos)
	local nearestEnemy = nil
	local nearestDist = math.huge
	for _, enemy in ipairs(CollectionService:GetTagged("Enemy")) do
		if enemy and enemy:IsA("Model") then
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
 
-- Helper to position an instance (Model or BasePart) to a CFrame
local function positionInstance(inst, cf)
	if not inst then return end
	if inst:IsA("Model") then
		-- Prefer SetPrimaryPartCFrame when available, otherwise use PivotTo
		local ok, _ = pcall(function()
			if inst.PrimaryPart then
				inst:SetPrimaryPartCFrame(cf)
				return true
			end
		end)
		if not ok or not inst.PrimaryPart then
			if inst.PivotTo then
				pcall(function() inst:PivotTo(cf) end)
			else
				-- fallback: try to set first BasePart child
				for _, c in ipairs(inst:GetChildren()) do
					if c:IsA("BasePart") then
						c.CFrame = cf
						break
					end
				end
			end
		end
	elseif inst:IsA("BasePart") then
		inst.CFrame = cf
	end
end

local function makeNonBlockingAnchored(inst)
	if not inst then return end
	if inst:IsA("Model") then
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Anchored = true
			end
		end
	elseif inst:IsA("BasePart") then
		inst.CanCollide = false
		inst.CanQuery = false
		inst.CanTouch = false
		inst.Anchored = true
	end
end

local function firePurpleShot(player)
	if not player or not player.Parent then return end
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Increase charge duration to allow a full orbit; place visuals closer to ground
	local chargeDuration = 2.4
	local pauseBeforeMerge = 1.0
	-- Use a modest orbit radius so the blue orb is near the player (better chance to hit enemies)
	local orbitRadius = 10

	-- create visuals (try to reuse assets)
	local redAsset = findCharAsset("Red") or findCharAsset("RedShot")
	local blueAsset = findCharAsset("Blue") or findCharAsset("BlueShot")

	local red, blue
	if redAsset then
		red = redAsset:Clone()
		red.Name = "Purple_RedCharge"
		-- sanitize and anchor so it doesn't fall through the world
		makeNonBlockingAnchored(red)
		red.Parent = workspace
	else
		red = Instance.new("Part")
		red.Name = "Purple_RedCharge"
		red.Shape = Enum.PartType.Ball
		red.Size = Vector3.new(2.5,2.5,2.5)
		red.Color = Color3.fromRGB(255,80,80)
		red.Material = Enum.Material.Neon
		red.Anchored = true
		red.CanCollide = false
		red.Parent = workspace
		local p = Instance.new("ParticleEmitter")
		p.Texture = "rbxasset://textures/particles/smoke_main.dds"
		p.Color = ColorSequence.new(Color3.fromRGB(255,120,120), Color3.fromRGB(255,40,40))
		p.Rate = 80
		p.Lifetime = NumberRange.new(0.2,0.5)
		p.Parent = red
	end

	if blueAsset then
		blue = blueAsset:Clone()
		blue.Name = "Purple_BlueOrbit"
		makeNonBlockingAnchored(blue)
		blue.Parent = workspace
	else
		blue = Instance.new("Part")
		blue.Name = "Purple_BlueOrbit"
		blue.Shape = Enum.PartType.Ball
		blue.Size = Vector3.new(2.5,2.5,2.5)
		blue.Color = Color3.fromRGB(100,150,255)
		blue.Material = Enum.Material.Neon
		blue.Anchored = true
		blue.CanCollide = false
		blue.Parent = workspace
		local p = Instance.new("ParticleEmitter")
		p.Texture = "rbxasset://textures/particles/smoke_main.dds"
		p.Color = ColorSequence.new(Color3.fromRGB(150,180,255), Color3.fromRGB(60,110,255))
		p.Rate = 80
		p.Lifetime = NumberRange.new(0.2,0.5)
		p.Parent = blue
	end

	local alive = true
	local angle = 0
	local elapsed = 0
	local conn

	local function pullStrong(centerPos, dt)
		for _, enemy in ipairs(CollectionService:GetTagged("Enemy")) do
			if enemy and enemy:IsA("Model") then
				local hum = enemy:FindFirstChildOfClass("Humanoid")
				local ehrp = enemy:FindFirstChild("HumanoidRootPart")
				if hum and ehrp and hum.Health > 0 then
					local dir = centerPos - ehrp.Position
					local dirXZ = Vector3.new(dir.X, 0, dir.Z)
					local dist = dirXZ.Magnitude
					if dist > 0.1 and dist <= 120 then
						local pullPercent = 1 - math.clamp(dist / 120, 0, 1)
						local desiredSpeed = math.min(400 * pullPercent, 400)
						local desiredVel = (dirXZ.Unit * desiredSpeed) + Vector3.new(0, math.clamp(ehrp.AssemblyLinearVelocity.Y * 0.2, -6, 6), 0)
						ehrp.AssemblyLinearVelocity = ehrp.AssemblyLinearVelocity:Lerp(desiredVel, math.clamp(0.9 * dt * 60, 0, 1))
					end
				end
			end
		end
	end

	conn = RunService.Heartbeat:Connect(function(dt)
		if not alive then return end
		if not player.Parent or not character.Parent then
			alive = false
			conn:Disconnect()
			if red and red.Parent then red:Destroy() end
			if blue and blue.Parent then blue:Destroy() end
			return
		end
		elapsed = elapsed + dt
		-- angular speed chosen so one full revolution takes roughly `chargeDuration` seconds
		local angularSpeed = (math.pi * 2) / math.max(0.001, chargeDuration)
		local delta = angularSpeed * dt
		angle = angle + delta

		local forward = hrp.CFrame.LookVector
		local spawnPos = hrp.Position + forward * (orbitRadius + 2) + Vector3.new(0,0.5,0)
		positionInstance(red, CFrame.new(spawnPos, spawnPos + forward))

		local offset = Vector3.new(math.cos(angle) * orbitRadius, 0, math.sin(angle) * orbitRadius)
		local bluePos = hrp.Position + offset + Vector3.new(0,0.5,0)

		positionInstance(blue, CFrame.new(bluePos))

		-- During purple charge, blue should be only visual: do not pull enemies here
		-- (pullStrong was intentionally disabled per request)
		-- if elapsed <= chargeDuration then
		--     pullStrong(bluePos, dt)
		-- end

		if elapsed >= chargeDuration + pauseBeforeMerge then
			alive = false
			conn:Disconnect()
			local mergePos = hrp.Position + forward * (orbitRadius + 2) + Vector3.new(0,0.5,0)
			positionInstance(red, CFrame.new(mergePos))
			positionInstance(blue, CFrame.new(mergePos))

			local projModel = createPurpleShotModel(stats.size)
			-- Positioning for preview; Projectile.Fire will clone and parent its own instance
			if projModel then
				positionInstance(projModel, CFrame.new(mergePos))
			end

			local origin = mergePos
			-- Aim at nearest enemy if one exists, otherwise fall back to player's look vector
			local targetHrp = findNearestEnemy(origin)
			local direction
			if targetHrp and targetHrp.Position then
				direction = (targetHrp.Position - origin)
				if direction.Magnitude < 1e-3 then
					direction = hrp.CFrame.LookVector
				end
			else
				direction = hrp.CFrame.LookVector
			end

			local playerStats = player:FindFirstChild("Stats")
			local baseDamage = 50
			if playerStats then
				local dmgValue = playerStats:FindFirstChild("BaseDamage")
				if dmgValue and dmgValue:IsA("NumberValue") then baseDamage = dmgValue.Value end
			end
			local projectileDamage = baseDamage * stats.damagePercent

			local hitSet = {}
			Projectile.Fire({
				origin = origin,
				direction = direction.Unit,
				speed = stats.speed,
				lifetime = 6,
				pierce = 999,
				damage = 0,
				model = projModel,
				owner = player,
				hitCooldownPerTarget = 0.3,
				-- Use proximity so the projectile itself has a large contact radius
				contactRadius = stats.explosionRadius,
				proximityDelay = 0.02,
				onHit = function(hitPart, enemyModel)
					if hitSet[enemyModel] then return end
					hitSet[enemyModel] = true
					local hum = enemyModel:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health > 0 then
						Damage.Apply(hum, projectileDamage)
						createExplosion(hitPart.Position, stats.explosionRadius)
						for _, e in ipairs(CollectionService:GetTagged("Enemy")) do
							if e:IsA("Model") and e ~= enemyModel then
								local eh = e:FindFirstChildOfClass("Humanoid")
								local ehrp = e:FindFirstChild("HumanoidRootPart")
								if eh and eh.Health > 0 and ehrp then
									local d = (ehrp.Position - hitPart.Position).Magnitude
									if d <= stats.explosionRadius then
										Damage.Apply(eh, projectileDamage * 0.5)
									end
								end
							end
						end
					end
				end
			})

			if red and red.Parent then red:Destroy() end
			if blue and blue.Parent then blue:Destroy() end
		end
	end)
end

function def.OnEquip(player, level)
	local userId = player.UserId
	if ActivePurpleShotByUserId[userId] then def.OnUnequip(player) end

	local RedShot = require(script.Parent:WaitForChild("RedShot"))
	local BlueShot = require(script.Parent:WaitForChild("BlueShot"))
	if RedShot.OnUnequip then pcall(RedShot.OnUnequip, player) end
	if BlueShot.OnUnequip then pcall(BlueShot.OnUnequip, player) end

	local runTrack = player:FindFirstChild("RunTrack") or Instance.new("Folder")
	runTrack.Name = "RunTrack"
	runTrack.Parent = player
	local disabled = runTrack:FindFirstChild("DisabledCards") or Instance.new("Folder")
	disabled.Name = "DisabledCards"
	disabled.Parent = runTrack
	local function setDisabled(id)
		if not id or id == "" then return end
		local v = disabled:FindFirstChild(id) or Instance.new("BoolValue")
		v.Name = id
		v.Value = true
		v.Parent = disabled
	end
	setDisabled("Gojo_RedShot")
	setDisabled("Gojo_BlueShot")

	-- Also mark all card ids that reference this module (module == script.Name) so CardPool excludes them.
	-- This handles cases where the card's id (e.g. "Gojo_PurpleShot") differs from this module filename.
	local function disableCardsReferencingModule(moduleName)
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		if not shared then return end
		local chars = shared:FindFirstChild("Chars")
		if not chars then return end
		for _, char in ipairs(chars:GetChildren()) do
			local cardsModule = char:FindFirstChild("Cards")
			if cardsModule and cardsModule:IsA("ModuleScript") then
				local ok, defs = pcall(require, cardsModule)
				if ok and type(defs) == "table" and type(defs.Definitions) == "table" then
					for _, list in pairs(defs.Definitions) do
						if type(list) == "table" then
							for _, cardDef in ipairs(list) do
								if type(cardDef) == "table" and cardDef.id and (cardDef.module == moduleName or cardDef.module == script.Name) then
									setDisabled(cardDef.id)
								end
							end
						end
					end
				end
			end
		end
	end
	disableCardsReferencingModule(script.Name)

	-- Also mark this module name itself (fallback)
	setDisabled(def.id or script.Name)

	-- Ensure a RunTrack entry for this card exists and set its Level to the equipped level
	local myFolder = runTrack:FindFirstChild(myId) or Instance.new("Folder")
	myFolder.Name = myId
	myFolder.Parent = runTrack
	local lvlNV = myFolder:FindFirstChild("Level") or Instance.new("IntValue")
	lvlNV.Name = "Level"
	lvlNV.Value = tonumber(level) or (def.maxLevel or 1)
	lvlNV.Parent = myFolder

	local lastFire = 0
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

	ActivePurpleShotByUserId[userId] = { connection = connection }
	print(string.format("[Hollow Purple] Equipped for %s - Red and Blue disabled", player.Name))
end

function def.OnUnequip(player)
	local userId = player.UserId
	local data = ActivePurpleShotByUserId[userId]
	if data then
		if data.connection then pcall(function() data.connection:Disconnect() end) end
		ActivePurpleShotByUserId[userId] = nil
		print(string.format("[Hollow Purple] Unequipped for %s", player.Name))
	end
end

function def.OnUnequipCleanup(player)
	local runTrack = player and player:FindFirstChild("RunTrack")
	if not runTrack then return end
	local disabled = runTrack:FindFirstChild("DisabledCards")
	if not disabled then return end
	for _, id in ipairs({"Gojo_RedShot", "Gojo_BlueShot", (def.id or script.Name)}) do
		local v = disabled:FindFirstChild(id)
		if v and v:IsA("BoolValue") then v:Destroy() end
	end
end

local _origOnUnequip = def.OnUnequip
function def.OnUnequip(player)
	_origOnUnequip(player)
	def.OnUnequipCleanup(player)
end

function def.OnCardAdded(player, defTable, level)
	def.OnEquip(player, level or 1)
end

function def.Apply(player, defTable)
	def.OnEquip(player, 1)
end

function def.OnLevelUp(player, newLevel)
	if ActivePurpleShotByUserId[player.UserId] then
		def.OnEquip(player, newLevel)
	end
end

return def
