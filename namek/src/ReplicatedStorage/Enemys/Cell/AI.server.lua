-- Cell AI: Melee boss that chases players and uses special abilities
-- Base movement: chase closest player
-- Melee attack when in range
-- Special abilities: Kamehame, Super Cell transformation, TP Attack, TP Charge

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")
local CombatFolder = ScriptsFolder:WaitForChild("Combat")
local Damage = require(CombatFolder:WaitForChild("Damage"))
local SFXHelper = require(ScriptsFolder:WaitForChild("SFXHelper"))
local NORMAL_SFX_ID     = 75572923732885
local KAMEHAME_SFX_ID   = 125899048399910
local TP_SFX_ID         = 104018950862217
local TRANSFORM_SFX_ID  = 123587824975222
local POWERUP_SFX_ID    = 128025610594825

-- Attack models
local EnemysFolder = ReplicatedStorage:WaitForChild("Enemys")
local AttacksFolder = EnemysFolder:FindFirstChild("Attacks")
local kameChargeModel = AttacksFolder and AttacksFolder:FindFirstChild("kame_charge")
local kamehamehaModel = AttacksFolder and AttacksFolder:FindFirstChild("Kamehameha")

if not kameChargeModel then
	warn("[Cell] kame_charge model not found in ReplicatedStorage/Enemys/Attacks")
end
if not kamehamehaModel then
	warn("[Cell] Kamehameha model not found in ReplicatedStorage/Enemys/Attacks")
end

-- Enemy setup
local enemyModel = script.Parent
local humanoid = enemyModel:WaitForChild("Humanoid")
local root = enemyModel:WaitForChild("HumanoidRootPart")
local animator = humanoid:WaitForChild("Animator")

-- Load Stats
local STATS = nil
do
	local statsModule = enemyModel:FindFirstChild("Stats")
	if statsModule and statsModule:IsA("ModuleScript") then
		local ok, data = pcall(require, statsModule)
		if ok and type(data) == "table" then STATS = data end
	end
end

local ATTACK_COOLDOWN = (STATS and STATS.AttackCooldown) or 1.2
local ATTACK_RANGE = (STATS and STATS.AttackRange) or 5
local DAMAGE = (STATS and STATS.Damage) or 120
local MOVE_SPEED = (STATS and STATS.MoveSpeed) or 8

-- Set humanoid properties
humanoid.WalkSpeed = MOVE_SPEED
humanoid.AutoRotate = true

local running = true
local isAttacking = false
local hasTransformed = false
local isInvulnerable = false
local maxHealth = humanoid.MaxHealth

-- Load animations
local animFolder = enemyModel:FindFirstChild("Animation")
local normalAnim = nil
local kamehameAnim = nil
local superCellAnim = nil
local tpAttackAnim = nil
local tpChargeAnim = nil
local cellJrAnim = nil

if animFolder then
	local norm = animFolder:FindFirstChild("normal")
	if norm and norm:IsA("Animation") then
		normalAnim = animator:LoadAnimation(norm)
		normalAnim.Priority = Enum.AnimationPriority.Action
		normalAnim.Looped = false
		print("[Cell] Normal attack animation loaded!")
	end
	
	local kame = animFolder:FindFirstChild("kamehame")
	if kame and kame:IsA("Animation") then
		kamehameAnim = animator:LoadAnimation(kame)
		kamehameAnim.Priority = Enum.AnimationPriority.Action
		kamehameAnim.Looped = false
		print("[Cell] Kamehame animation loaded!")
	end
	
	local super = animFolder:FindFirstChild("super_cell")
	if super and super:IsA("Animation") then
		superCellAnim = animator:LoadAnimation(super)
		superCellAnim.Priority = Enum.AnimationPriority.Action
		superCellAnim.Looped = false
		print("[Cell] Super Cell animation loaded!")
	end
	
	local tpAtk = animFolder:FindFirstChild("tp_attack")
	if tpAtk and tpAtk:IsA("Animation") then
		tpAttackAnim = animator:LoadAnimation(tpAtk)
		tpAttackAnim.Priority = Enum.AnimationPriority.Action
		tpAttackAnim.Looped = false
		print("[Cell] TP Attack animation loaded!")
	end
	
	local tpChrg = animFolder:FindFirstChild("tp_charge")
	if tpChrg and tpChrg:IsA("Animation") then
		tpChargeAnim = animator:LoadAnimation(tpChrg)
		tpChargeAnim.Priority = Enum.AnimationPriority.Action
		tpChargeAnim.Looped = false
		print("[Cell] TP Charge animation loaded!")
	end
	
	local cellJr = animFolder:FindFirstChild("cell_jr")
	if cellJr and cellJr:IsA("Animation") then
		cellJrAnim = animator:LoadAnimation(cellJr)
		cellJrAnim.Priority = Enum.AnimationPriority.Action
		cellJrAnim.Looped = false
		print("[Cell] Cell Jr animation loaded!")
	end
end

-- Cleanup function
local function cleanup()
	running = false
	print("[Cell] Cleanup called")
end

-- Setup cleanup events
print("[Cell] Setting up cleanup events for:", enemyModel.Name)
humanoid.Died:Connect(cleanup)
print("[Cell] Humanoid Died event connected")

humanoid.HealthChanged:Connect(function(health)
	if health <= 0 then
		print("[Cell] HealthChanged to 0 - triggering cleanup")
		cleanup()
	end
end)

enemyModel.AncestryChanged:Connect(function(_, parent)
	if not parent then
		print("[Cell] AncestryChanged - model removed from workspace")
		cleanup()
	end
end)

-- Find closest player
local function findClosestPlayer()
	local closest = nil
	local shortestDist = math.huge
	
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local hum = character:FindFirstChildOfClass("Humanoid")
			local r = character:FindFirstChild("HumanoidRootPart")
			
			if r and hum and hum.Health > 0 then
				local dist = (r.Position - root.Position).Magnitude
				if dist < shortestDist then
					shortestDist = dist
					closest = r
				end
			end
		end
	end
	
	return closest, shortestDist
end

-- Kamehameha attack
local function performKamehameha(targetRoot)
	if not running or isAttacking or not kamehamehaModel or not kameChargeModel then return end
	
	isAttacking = true
	
	print("[Cell] Performing Kamehameha!")
	
	-- Find right hand attachment
	local rightHand = enemyModel:FindFirstChild("Right Arm", true) or enemyModel:FindFirstChild("RightHand", true)
	local handAttachment = rightHand and rightHand:FindFirstChildOfClass("Attachment")
	
	if not handAttachment then
		warn("[Cell] Right hand attachment not found!")
		isAttacking = false
		return
	end
	
	-- Play kamehame animation
	if kamehameAnim then
		pcall(function()
			kamehameAnim:Play(0.1, 1, 1)
		end)
	end
	SFXHelper.playAt(root, KAMEHAME_SFX_ID, 0.7, { minDist = 10, maxDist = 80 })
	
	-- Phase 1: Charge (1.5s) - spawn kame_charge on hand
	print("[Cell] Charging Kamehameha...")
	local chargeEffect = kameChargeModel:Clone()
	
	-- Position charge at hand attachment (don't weld, let existing welds in model handle it)
	if chargeEffect:IsA("Model") then
		chargeEffect:PivotTo(handAttachment.WorldCFrame)
	else
		chargeEffect.CFrame = handAttachment.WorldCFrame
	end
	
	chargeEffect.Parent = workspace
	
	-- Continuously update charge position to follow hand
	local updateChargePosition = true
	task.spawn(function()
		while updateChargePosition and chargeEffect.Parent and running do
			if chargeEffect:IsA("Model") then
				chargeEffect:PivotTo(handAttachment.WorldCFrame)
			else
				chargeEffect.CFrame = handAttachment.WorldCFrame
			end
			task.wait(0.05)
		end
	end)
	
	-- Charge phase: rotate slowly towards player
	local chargeStart = os.clock()
	local chargeDuration = 1.5
	
	while os.clock() - chargeStart < chargeDuration and running do
		if ReplicatedStorage:GetAttribute("GamePaused") then
			task.wait(0.05)
		else
			-- Slow rotation towards target
			if targetRoot and targetRoot.Parent then
				local lookDir = (targetRoot.Position - root.Position) * Vector3.new(1, 0, 1)
				if lookDir.Magnitude > 0.001 then
					local targetCF = CFrame.new(root.Position, root.Position + lookDir.Unit)
					root.CFrame = root.CFrame:Lerp(targetCF, 0.1) -- Slower rotation
				end
			end
			task.wait(0.05)
		end
	end
	
	-- Remove charge effect
	updateChargePosition = false
	if chargeEffect then chargeEffect:Destroy() end
	
	if not running then
		isAttacking = false
		return
	end
	
	-- Phase 2: Fire Kamehameha beam (1s) - spawn Kamehameha model
	print("[Cell] Firing Kamehameha beam!")
	
	local beam = kamehamehaModel:Clone()
	
	-- Setup all parts in the beam
	for _, desc in ipairs(beam:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
		end
	end
	
	beam.Parent = workspace
	
	-- Get beam primary part or first part
	local beamPart = beam:IsA("Model") and (beam.PrimaryPart or beam:FindFirstChildOfClass("BasePart")) or beam
	
	if not beamPart then
		warn("[Cell] Kamehameha has no BasePart!")
		beam:Destroy()
		isAttacking = false
		return
	end
	
	local beamStart = os.clock()
	local beamDuration = 1.0
	local damageInterval = 0.2
	local lastDamage = 0
	local damagedPlayers = {} -- Track who was damaged to avoid spam
	
	while os.clock() - beamStart < beamDuration and running do
		if ReplicatedStorage:GetAttribute("GamePaused") then
			task.wait(0.05)
		else
			-- Position beam in front of Cell, rotated to face forward (horizontal)
			if beamPart and root then
				-- Position the beam in front and rotate it to be horizontal facing forward
				local distance = 5 -- Distance in front of Cell
				local beamCFrame = root.CFrame * CFrame.new(0, 0, -distance) * CFrame.Angles(math.rad(-90), 0, 0)
				beam:PivotTo(beamCFrame)
			end
			
			-- Slow rotation towards target
			if targetRoot and targetRoot.Parent then
				local lookDir = (targetRoot.Position - root.Position) * Vector3.new(1, 0, 1)
				if lookDir.Magnitude > 0.001 then
					local targetCF = CFrame.new(root.Position, root.Position + lookDir.Unit)
					root.CFrame = root.CFrame:Lerp(targetCF, 0.1)
				end
			end
			
			-- Deal damage every 0.2s using beam hitbox
			local now = os.clock()
			if now - lastDamage >= damageInterval then
				lastDamage = now
				damagedPlayers = {} -- Reset damage tracking
				
				-- Check collision with all beam parts
				for _, beamPartObj in ipairs(beam:GetDescendants()) do
					if beamPartObj:IsA("BasePart") then
						local region = Region3.new(
							beamPartObj.Position - beamPartObj.Size/2,
							beamPartObj.Position + beamPartObj.Size/2
						):ExpandToGrid(4)
						
						for _, player in ipairs(Players:GetPlayers()) do
							if not damagedPlayers[player.UserId] then
								local character = player.Character
								if character then
									local hum = character:FindFirstChildOfClass("Humanoid")
									local playerRoot = character:FindFirstChild("HumanoidRootPart")
									
									if hum and hum.Health > 0 and playerRoot then
										-- Check if player's root is inside beam part's bounding box
										local relativePos = beamPartObj.CFrame:PointToObjectSpace(playerRoot.Position)
										local halfSize = beamPartObj.Size / 2
										
										if math.abs(relativePos.X) <= halfSize.X and
										   math.abs(relativePos.Y) <= halfSize.Y and
										   math.abs(relativePos.Z) <= halfSize.Z then
											Damage.Apply(hum, DAMAGE)
											damagedPlayers[player.UserId] = true
											print("[Cell] Kamehameha hit", player.Name, "for", DAMAGE, "damage!")
										end
									end
								end
							end
						end
					end
				end
			end
			
			task.wait(0.05)
		end
	end
	
	-- Phase 3: Fade out
	if beam and beam.Parent then
		local fadeStart = os.clock()
		local fadeDuration = 0.5
		
		while os.clock() - fadeStart < fadeDuration and beam.Parent do
			if not ReplicatedStorage:GetAttribute("GamePaused") then
				local alpha = (os.clock() - fadeStart) / fadeDuration
				
				for _, desc in ipairs(beam:GetDescendants()) do
					if desc:IsA("BasePart") then
						desc.Transparency = alpha
					end
				end
			end
			task.wait(0.05)
		end
		
		beam:Destroy()
	end
	
	isAttacking = false
	print("[Cell] Kamehameha complete!")
end

-- Super Cell Transformation
local function performSuperCellTransform()
	if hasTransformed or isAttacking then return end
	
	isAttacking = true
	hasTransformed = true
	isInvulnerable = true
	
	print("[Cell] Transforming into Super Cell!")
	
	-- Stop movement during transformation
	local originalWalkSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = 0
	
	-- Play transformation animation
	if superCellAnim then
		pcall(function()
			superCellAnim:Play(0.1, 1, 1)
		end)
	end
	SFXHelper.playAt(root, TRANSFORM_SFX_ID, 0.7, { minDist = 10, maxDist = 80 })
	
	-- Wait for animation to complete
	local animDuration = (superCellAnim and superCellAnim.Length) or 3.0
	local startTime = os.clock()
	
	while os.clock() - startTime < animDuration and running do
		if ReplicatedStorage:GetAttribute("GamePaused") then
			task.wait(0.05)
		else
			task.wait(0.05)
		end
	end
	
	if not running then
		isAttacking = false
		humanoid.WalkSpeed = originalWalkSpeed
		return
	end
	
	-- Explosion effect at the end of transformation
	local explosion = Instance.new("Part")
	explosion.Name = "TransformationExplosion"
	explosion.Anchored = true
	explosion.CanCollide = false
	explosion.Shape = Enum.PartType.Ball
	explosion.Material = Enum.Material.Neon
	explosion.Color = Color3.fromRGB(255, 255, 0) -- Yellow explosion
	explosion.Transparency = 0.3
	explosion.Size = Vector3.new(1, 1, 1)
	explosion.CFrame = root.CFrame
	explosion.Parent = workspace
	SFXHelper.playAt(root, POWERUP_SFX_ID, 0.7, { minDist = 10, maxDist = 80 })
	local expandDuration = 0.5
	local maxSize = 20
	task.spawn(function()
		local t = 0
		while t < expandDuration and explosion.Parent do
			local alpha = t / expandDuration
			local size = 1 + (maxSize - 1) * alpha
			explosion.Size = Vector3.new(size, size, size)
			explosion.Transparency = 0.3 + (0.7 * alpha)
			task.wait(0.03)
			t += 0.03
		end
		explosion:Destroy()
	end)
	
	-- Full heal
	humanoid.Health = humanoid.MaxHealth
	print("[Cell] Fully healed! Super Cell form activated!")
	
	-- Apply stat buffs
	DAMAGE = DAMAGE * 1.5
	humanoid.WalkSpeed = MOVE_SPEED * 1.2
	
	-- Enable particle emitters on ssj2 part
	local ssj2Part = enemyModel:FindFirstChild("ssj2")
	if ssj2Part then
		for _, child in ipairs(ssj2Part:GetChildren()) do
			if child:IsA("ParticleEmitter") then
				child.Enabled = true
				print("[Cell] Enabled", child.Name, "particle emitter!")
			end
		end
	else
		warn("[Cell] ssj2 part not found!")
	end
	
	isInvulnerable = false
	isAttacking = false
	print("[Cell] Super Cell transformation complete!")
end

-- Teleport Strike attack
local function performTeleportStrike(targetRoot)
	if not running or isAttacking then return end
	
	isAttacking = true
	
	print("[Cell] Performing Teleport Strike!")
	
	-- Phase 1: Charge animation (tp_charge)
	if tpChargeAnim then
		pcall(function()
			tpChargeAnim:Play(0.1, 1, 1)
		end)
	end
	
	-- Charge duration (1.5 seconds, no telegraph)
	local chargeStart = os.clock()
	local chargeDuration = 1.5
	
	while os.clock() - chargeStart < chargeDuration and running do
		if ReplicatedStorage:GetAttribute("GamePaused") then
			task.wait(0.05)
		else
			-- Slow rotation towards target during charge
			if targetRoot and targetRoot.Parent then
				local lookDir = (targetRoot.Position - root.Position) * Vector3.new(1, 0, 1)
				if lookDir.Magnitude > 0.001 then
					local targetCF = CFrame.new(root.Position, root.Position + lookDir.Unit)
					root.CFrame = root.CFrame:Lerp(targetCF, 0.1)
				end
			end
			task.wait(0.05)
		end
	end
	
	if not running then
		isAttacking = false
		return
	end
	
	-- Stop charge animation
	if tpChargeAnim and tpChargeAnim.IsPlaying then
		tpChargeAnim:Stop(0.1)
	end
	
	-- Get updated target position
	local finalTarget, distance = findClosestPlayer()
	local targetPos = targetRoot.Position
	if finalTarget then
		targetPos = finalTarget.Position
	end
	
	-- Phase 2: Teleport to target
	print("[Cell] Teleporting!")
	SFXHelper.playAt(root, TP_SFX_ID, 0.7, { minDist = 10, maxDist = 60 })
	root.CFrame = CFrame.new(targetPos)
	
	-- Phase 3: Attack animation on arrival (tp_attack)
	if tpAttackAnim then
		pcall(function()
			tpAttackAnim:Play(0.05, 1, 1)
		end)
	end
	
	-- Deal damage in area on arrival
	task.delay(0.1, function()
		if running then
			local damageRadius = 10
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				if character then
					local hum = character:FindFirstChildOfClass("Humanoid")
					local playerRoot = character:FindFirstChild("HumanoidRootPart")
					
					if hum and hum.Health > 0 and playerRoot then
						local distance = (playerRoot.Position - root.Position).Magnitude
						
						if distance <= damageRadius then
							SFXHelper.playAt(root, NORMAL_SFX_ID, 0.7, { minDist = 10, maxDist = 60 })
							local tpDamage = DAMAGE * 1.5 -- Higher damage for teleport
							Damage.Apply(hum, tpDamage)
							print("[Cell] Teleport Strike hit", player.Name, "for", tpDamage, "damage!")
						end
					end
				end
			end
		end
	end)
	
	-- Wait for attack animation to finish
	if tpAttackAnim then
		task.wait(tpAttackAnim.Length or 1.0)
	else
		task.wait(1.0)
	end
	
	isAttacking = false
	print("[Cell] Teleport Strike complete!")
end

-- Cell Jr Spawn attack
local function performCellJrSpawn(targetRoot)
	if not running or isAttacking then return end
	
	isAttacking = true
	
	print("[Cell] Spawning Cell Jrs!")
	
	-- Stop movement during animation
	local originalWalkSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = 0
	
	-- Play cell_jr animation
	if cellJrAnim then
		pcall(function()
			cellJrAnim:Play(0.1, 1, 1)
		end)
	end
	
	-- Wait 0.8 seconds then spawn 4 Cell Jrs
	task.wait(0.8)
	
	if not running then
		isAttacking = false
		return
	end
	
	-- Get Cell_jr model from Enemys folder
	local cellJrModel = EnemysFolder:FindFirstChild("Cell_jr")
	if not cellJrModel then
		warn("[Cell] Cell_jr model not found in ReplicatedStorage/Enemys!")
		isAttacking = false
		humanoid.WalkSpeed = originalWalkSpeed
		return
	end
	
	-- Spawn 4 Cell Jrs in a circle around Cell
	local spawnRadius = 8
	local angleStep = (math.pi * 2) / 4
	
	for i = 1, 4 do
		local angle = angleStep * (i - 1)
		local offsetX = math.cos(angle) * spawnRadius
		local offsetZ = math.sin(angle) * spawnRadius
		
		local spawnPos = root.Position + Vector3.new(offsetX, 0, offsetZ)
		
		-- Clone and spawn Cell Jr
		local clone = cellJrModel:Clone()
		clone.Name = "Cell_jr_" .. i
		
		local cloneRoot = clone:FindFirstChild("HumanoidRootPart")
		local cloneHum = clone:FindFirstChildOfClass("Humanoid")
		
		if cloneRoot and cloneHum then
			-- Position clone
			cloneRoot.CFrame = CFrame.new(spawnPos)
			
			-- Important: Add "Enemy" tag for targeting system
			local CollectionService = game:GetService("CollectionService")
			CollectionService:AddTag(clone, "Enemy")
			
			-- Ensure clone has proper properties for targeting
			cloneHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- Health bar controlled by targeting system
			
			-- Parent to workspace (this makes it visible and active)
			clone.Parent = workspace
			
			-- Setup death cleanup
			cloneHum.Died:Connect(function()
				task.wait(2) -- Wait 2 seconds before removing corpse
				if clone and clone.Parent then
					clone:Destroy()
				end
			end)
			
			print("[Cell] Spawned Cell Jr #" .. i .. " at", spawnPos)
		else
			warn("[Cell] Cell Jr clone missing HumanoidRootPart or Humanoid!")
			clone:Destroy()
		end
	end
	
	-- Wait for animation to finish
	if cellJrAnim then
		task.wait(cellJrAnim.Length or 2.0)
	else
		task.wait(2.0)
	end
	
	-- Restore movement
	humanoid.WalkSpeed = originalWalkSpeed
	
	isAttacking = false
	print("[Cell] Cell Jr spawn complete!")
end

-- Normal melee attack
local function performNormalAttack(targetRoot)
	if not running or isAttacking then return end
	
	isAttacking = true
	
	print("[Cell] Performing normal attack!")
	
	-- Face target
	local lookDir = (targetRoot.Position - root.Position) * Vector3.new(1, 0, 1)
	if lookDir.Magnitude > 0.001 then
		root.CFrame = CFrame.new(root.Position, root.Position + lookDir.Unit)
	end
	
	-- Play attack animation
	if normalAnim then
		pcall(function()
			normalAnim:Play(0.1, 1, 1)
		end)
	end
	SFXHelper.playAt(root, NORMAL_SFX_ID, 0.7, { minDist = 10, maxDist = 60 })
	
	-- Wait a bit then deal damage (mid-animation)
	task.wait(0.3)
	
	-- Deal damage if still in range
	if running and targetRoot and targetRoot.Parent then
		local dist = (targetRoot.Position - root.Position).Magnitude
		if dist <= ATTACK_RANGE + 2 then
			local character = targetRoot.Parent
			local hum = character:FindFirstChildOfClass("Humanoid")
			
			if hum and hum.Health > 0 then
				Damage.Apply(hum, DAMAGE)
				print("[Cell] Hit target for", DAMAGE, "damage!")
			end
		end
	end
	
	-- Wait for attack cooldown
	task.wait(ATTACK_COOLDOWN - 0.3)
	
	isAttacking = false
end

-- Rotation and movement loop: Always face and chase closest player
task.spawn(function()
	while running do
		if ReplicatedStorage:GetAttribute("GamePaused") then
			task.wait(0.05)
			continue
		end
		
		local targetRoot, distance = findClosestPlayer()
		
		if targetRoot and not isAttacking then
			-- Move toward player (humanoid:MoveTo handles rotation automatically)
			humanoid:MoveTo(targetRoot.Position)
		end
		
		task.wait(0.1)
	end
end)

-- Attack loop: check for targets in range
local lastAttack = 0
local lastKamehame = 0
local lastTeleport = 0
local lastCellJr = 0
local lastAbilityUsed = 0 -- Global cooldown tracker for abilities
local KAMEHAME_INTERVAL = 8 -- Use Kamehame every 8 seconds
local KAMEHAME_RANGE = 30 -- Can use from further away
local TELEPORT_INTERVAL = 12 -- Use Teleport every 12 seconds
local TELEPORT_RANGE = 40 -- Can teleport from further away
local CELLJR_INTERVAL = 20 -- Use Cell Jr spawn every 20 seconds
local CELLJR_RANGE = 35 -- Can spawn from medium range
local ABILITY_GLOBAL_COOLDOWN = 3 -- Minimum time between any two abilities

task.spawn(function()
	while running do
		if ReplicatedStorage:GetAttribute("GamePaused") then
			task.wait(0.05)
			continue
		end
		
		local now = os.clock()
		local targetRoot, distance = findClosestPlayer()
		
		-- Check for transformation at 50% HP
		if not hasTransformed and humanoid.Health <= (maxHealth * 0.5) then
			performSuperCellTransform()
		end
		
		if targetRoot then
			-- Priority: Cell Jr > Teleport > Kamehameha > Normal Attack
			-- Check global ability cooldown to prevent ability spam
			if now - lastCellJr >= CELLJR_INTERVAL and distance <= CELLJR_RANGE and not isAttacking and (now - lastAbilityUsed >= ABILITY_GLOBAL_COOLDOWN) then
				print("[Cell] Using Cell Jr Spawn!")
				lastCellJr = now
				lastAbilityUsed = now -- Update global ability cooldown
				lastAttack = now -- Reset attack cooldown
				performCellJrSpawn(targetRoot)
			elseif now - lastTeleport >= TELEPORT_INTERVAL and distance <= TELEPORT_RANGE and not isAttacking and (now - lastAbilityUsed >= ABILITY_GLOBAL_COOLDOWN) then
				print("[Cell] Using Teleport Strike!")
				lastTeleport = now
				lastAbilityUsed = now -- Update global ability cooldown
				lastAttack = now -- Reset attack cooldown
				performTeleportStrike(targetRoot)
			elseif now - lastKamehame >= KAMEHAME_INTERVAL and distance <= KAMEHAME_RANGE and not isAttacking and (now - lastAbilityUsed >= ABILITY_GLOBAL_COOLDOWN) then
				print("[Cell] Using Kamehameha!")
				lastKamehame = now
				lastAbilityUsed = now -- Update global ability cooldown
				lastAttack = now -- Reset attack cooldown too
				performKamehameha(targetRoot)
			elseif now - lastAttack >= ATTACK_COOLDOWN and distance <= ATTACK_RANGE and not isAttacking then
				lastAttack = now
				performNormalAttack(targetRoot)
			end
		end
		
		task.wait(0.1)
	end
end)

print("[Cell] AI initialized! Ready to fight!")

-- Invulnerability during transformation
humanoid.HealthChanged:Connect(function(health)
	if isInvulnerable then
		-- Prevent damage during transformation
		humanoid.Health = humanoid.MaxHealth
	end
end)
