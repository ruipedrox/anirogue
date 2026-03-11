-- Super Buu AI: Fast melee boss with regeneration through blob spawning
-- Every 1000 damage taken spawns a Buu_blob that seeks to heal Super Buu

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")
local CombatFolder = ScriptsFolder:WaitForChild("Combat")
local Damage = require(CombatFolder:WaitForChild("Damage"))
local SFXHelper = require(ScriptsFolder:WaitForChild("SFXHelper"))
local MANY_BEAM_SFX_ID      = 120490147546127
local CANDY_BEAM_SFX_ID     = 131567785393405
local SHOUT_SFX_ID          = 83041252354792
local NORMAL_SFX_ID         = 75572923732885
local MACHINE_PUNCHES_SFX_ID = 136550902387706

local EnemysFolder = ReplicatedStorage:WaitForChild("Enemys")
local blobModel = EnemysFolder:FindFirstChild("buu_blob")

if not blobModel then
	warn("[Super Buu] buu_blob model not found in ReplicatedStorage/Enemys")
end

-- Load attack models
local AttacksFolder = EnemysFolder:FindFirstChild("Attacks")
local candyBeamModel = AttacksFolder and AttacksFolder:FindFirstChild("candy_beam")
local chocBarModel = AttacksFolder and AttacksFolder:FindFirstChild("choc_bar")
local soundWaveModel = AttacksFolder and AttacksFolder:FindFirstChild("sound_wave")
local manyChargeModel = AttacksFolder and AttacksFolder:FindFirstChild("many_charge")
local buuBallModel = AttacksFolder and AttacksFolder:FindFirstChild("buu_ball")

print("[Super Buu] AttacksFolder:", AttacksFolder)
print("[Super Buu] candyBeamModel:", candyBeamModel)
print("[Super Buu] chocBarModel:", chocBarModel)
print("[Super Buu] soundWaveModel:", soundWaveModel)
print("[Super Buu] manyChargeModel:", manyChargeModel)
print("[Super Buu] buuBallModel:", buuBallModel)

if not candyBeamModel then
	warn("[Super Buu] candy_beam model not found in ReplicatedStorage/Enemys/Attacks")
end
if not chocBarModel then
	warn("[Super Buu] choc_bar model not found in ReplicatedStorage/Enemys/Attacks")
end
if not soundWaveModel then
	warn("[Super Buu] sound_wave model not found in ReplicatedStorage/Enemys/Attacks")
end
if not manyChargeModel then
	warn("[Super Buu] many_charge model not found in ReplicatedStorage/Enemys/Attacks")
end
if not buuBallModel then
	warn("[Super Buu] buu_ball model not found in ReplicatedStorage/Enemys/Attacks")
end

local enemyModel = script.Parent
local humanoid = enemyModel:WaitForChild("Humanoid")
local root = enemyModel:WaitForChild("HumanoidRootPart")
local animator = humanoid:WaitForChild("Animator")

-- Find left arm attachment for many_charge
local leftArm = enemyModel:FindFirstChild("Left Arm")
local leftArmAttachment = leftArm and leftArm:FindFirstChild("Attachment")

if not leftArmAttachment then
	warn("[Super Buu] Left Arm Attachment not found!")
end

-- Load Stats
local STATS = nil
do
	local statsModule = enemyModel:FindFirstChild("Stats")
	if statsModule and statsModule:IsA("ModuleScript") then
		local ok, data = pcall(require, statsModule)
		if ok and type(data) == "table" then STATS = data end
	end
end

local ATTACK_COOLDOWN = (STATS and STATS.AttackCooldown) or 1.0
local ATTACK_RANGE = (STATS and STATS.AttackRange) or 6
local DAMAGE = (STATS and STATS.Damage) or 140
local MOVE_SPEED = (STATS and STATS.MoveSpeed) or 12

-- Blob spawning constants
local DAMAGE_PER_BLOB = 1000
local BLOB_HEAL_AMOUNT = 500

humanoid.WalkSpeed = MOVE_SPEED
humanoid.AutoRotate = true

local running = true
local isAttacking = false
local totalDamageTaken = 0
local lastBlobSpawn = 0
local blobSpawnCount = 0 -- Track number of blobs spawned

-- Track for blob healing
_G.SuperBuuInstance = {
	model = enemyModel,
	humanoid = humanoid,
	root = root,
	healAmount = BLOB_HEAL_AMOUNT
}

-- Load animations
local animFolder = enemyModel:FindFirstChild("Animation")
local normalAnim = nil
local candyBeamAnim = nil
local machinePunchesAnim = nil
local manyBeamAnim = nil
local shoutAnim = nil

if animFolder then
	local norm = animFolder:FindFirstChild("normal")
	if norm and norm:IsA("Animation") then
		normalAnim = animator:LoadAnimation(norm)
		normalAnim.Priority = Enum.AnimationPriority.Action
		normalAnim.Looped = false
		print("[Super Buu] Normal attack animation loaded!")
	end
	
	local candy = animFolder:FindFirstChild("candy_beam")
	if candy and candy:IsA("Animation") then
		candyBeamAnim = animator:LoadAnimation(candy)
		candyBeamAnim.Priority = Enum.AnimationPriority.Action
		candyBeamAnim.Looped = false
		print("[Super Buu] Candy Beam animation loaded!")
	end
	
	local machine = animFolder:FindFirstChild("machine_punches")
	if machine and machine:IsA("Animation") then
		machinePunchesAnim = animator:LoadAnimation(machine)
		machinePunchesAnim.Priority = Enum.AnimationPriority.Action
		machinePunchesAnim.Looped = false
		print("[Super Buu] Machine Punches animation loaded!")
	end
	
	local many = animFolder:FindFirstChild("many_beam")
	if many and many:IsA("Animation") then
		manyBeamAnim = animator:LoadAnimation(many)
		manyBeamAnim.Priority = Enum.AnimationPriority.Action
		manyBeamAnim.Looped = false
		print("[Super Buu] Many Beam animation loaded!")
	end
	
	local shout = animFolder:FindFirstChild("shout")
	if shout and shout:IsA("Animation") then
		shoutAnim = animator:LoadAnimation(shout)
		shoutAnim.Priority = Enum.AnimationPriority.Action
		shoutAnim.Looped = false
		print("[Super Buu] Shout animation loaded!")
	end
end

-- Cleanup
local function cleanup()
	running = false
	_G.SuperBuuInstance = nil
	print("[Super Buu] Cleanup called")
end

humanoid.Died:Connect(cleanup)

humanoid.HealthChanged:Connect(function(health)
	if health <= 0 then
		cleanup()
	end
end)

enemyModel.AncestryChanged:Connect(function(_, parent)
	if not parent then
		cleanup()
	end
end)

-- Spawn blob when damage threshold reached
local function spawnBlob()
	if not blobModel or not running then return end
	
	local now = os.clock()
	if now - lastBlobSpawn < 1 then return end -- Cooldown between spawns
	
	lastBlobSpawn = now
	blobSpawnCount = blobSpawnCount + 1
	
	-- Use same random method as WaveManager: random angle and radius
	local angle = math.random() * math.pi * 2
	local radius = 10 + math.random() * 10 -- 10-20 studs
	local offsetX = math.cos(angle) * radius
	local offsetZ = math.sin(angle) * radius
	
	local spawnPos = Vector3.new(
		root.Position.X + offsetX,
		45.211,
		root.Position.Z + offsetZ
	)
	
	local blob = blobModel:Clone()
	blob.Name = "Buu_blob_" .. os.clock()
	
	local blobRoot = blob:FindFirstChild("HumanoidRootPart")
	local blobHum = blob:FindFirstChildOfClass("Humanoid")
	
	if blobRoot and blobHum then
		blobRoot.CFrame = CFrame.new(spawnPos)
		blob.Parent = workspace
		
		-- Add Enemy tag
		local CollectionService = game:GetService("CollectionService")
		CollectionService:AddTag(blob, "Enemy")
		
		print("[Super Buu] Spawned Buu blob at", spawnPos)
	else
		blob:Destroy()
	end
end

-- Track damage taken
humanoid.HealthChanged:Connect(function(health)
	if not running then return end
	
	local maxHealth = humanoid.MaxHealth
	local currentDamage = maxHealth - health
	local damageSinceLastBlob = currentDamage - totalDamageTaken
	
	if damageSinceLastBlob >= DAMAGE_PER_BLOB then
		totalDamageTaken = currentDamage
		spawnBlob()
	end
end)

-- Find closest player
local function findClosestPlayer()
	local bestDist = math.huge
	local bestRoot = nil
	
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local hum = character:FindFirstChildOfClass("Humanoid")
			local playerRoot = character:FindFirstChild("HumanoidRootPart")
			
			if hum and hum.Health > 0 and playerRoot then
				local dist = (playerRoot.Position - root.Position).Magnitude
				if dist < bestDist then
					bestDist = dist
					bestRoot = playerRoot
				end
			end
		end
	end
	
	return bestRoot, bestDist
end

-- Normal melee attack
local function performNormalAttack(targetRoot)
	if not running or isAttacking then return end
	
	isAttacking = true
	
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
	task.wait(0.3)
	
	if running and targetRoot and targetRoot.Parent then
		local dist = (targetRoot.Position - root.Position).Magnitude
		if dist <= ATTACK_RANGE + 2 then
			local character = targetRoot.Parent
			local hum = character:FindFirstChildOfClass("Humanoid")
			
			if hum and hum.Health > 0 then
				Damage.Apply(hum, DAMAGE)
				print("[Super Buu] Hit target for", DAMAGE, "damage!")
			end
		end
	end
	
	task.wait(ATTACK_COOLDOWN - 0.3)
	isAttacking = false
end

-- Machine Punches attack: rapid cone damage while moving fast
local function performMachinePunches(targetRoot)
	if not running or isAttacking then return end
	
	isAttacking = true
	
	print("[Super Buu] Machine Punches started!")
	
	-- Play machine_punches animation
	if machinePunchesAnim then
		pcall(function()
			machinePunchesAnim:Play(0.1, 1, 1)
		end)
	end
	
	-- Boost movement speed
	local originalSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = MOVE_SPEED + 5 -- Moderate speed boost during attack
	humanoid.AutoRotate = true
	
	-- Wait 0.7s before starting damage
	local attackStart = os.clock()
	while os.clock() - attackStart < 0.7 and running do
		if ReplicatedStorage:GetAttribute("GamePaused") then
			task.wait(0.05)
		else
			-- Keep moving toward target during windup
			local currentTarget = findClosestPlayer()
			if currentTarget then
				humanoid:MoveTo(currentTarget.Position)
			end
			task.wait(0.05)
		end
	end
	
	-- Rapid cone damage for 2 seconds
	local damageStart = os.clock()
	SFXHelper.playAt(root, MACHINE_PUNCHES_SFX_ID, 0.7, { minDist = 10, maxDist = 60 })
	local nextTick = damageStart
	local damageInterval = 0.3 -- Slower tick rate
	local damageDuration = 2.5
	local coneAngle = 90 -- degrees
	local coneRange = 12 -- studs
	local tickDamage = DAMAGE * 0.6 -- 60% of normal damage per tick
	
	while running and (os.clock() - damageStart) < damageDuration do
		if ReplicatedStorage:GetAttribute("GamePaused") then
			task.wait(0.05)
		else
			local currentTime = os.clock()
			
			-- Keep moving toward target during attack
			local currentTarget = findClosestPlayer()
			if currentTarget then
				humanoid:MoveTo(currentTarget.Position)
			end
			
			if currentTime >= nextTick then
				nextTick = currentTime + damageInterval
				
				-- Deal cone damage
				local lookDir = root.CFrame.LookVector
				local halfAngle = math.rad(coneAngle / 2)
				
				for _, player in ipairs(Players:GetPlayers()) do
					local character = player.Character
					if character then
						local hum = character:FindFirstChildOfClass("Humanoid")
						local playerRoot = character:FindFirstChild("HumanoidRootPart")
						
						if hum and hum.Health > 0 and playerRoot then
							-- Top-down cone check (ignore Y)
							local toPlayer = (playerRoot.Position - root.Position) * Vector3.new(1, 0, 1)
							local dist = toPlayer.Magnitude
							
							if dist <= coneRange then
								local dirToPlayer = toPlayer.Unit
								local angle = math.acos(math.clamp(lookDir:Dot(dirToPlayer), -1, 1))
								
								if angle <= halfAngle then
									-- Player is in cone
									Damage.Apply(hum, tickDamage)
									print("[Super Buu] Machine Punches hit", player.Name, "for", tickDamage, "damage!")
								end
							end
						end
					end
				end
			end
			
			task.wait(0.05)
		end
	end
	
	-- Restore speed
	humanoid.WalkSpeed = originalSpeed
	
	if machinePunchesAnim and machinePunchesAnim.IsPlaying then
		machinePunchesAnim:Stop(0.1)
	end
	
	isAttacking = false
	print("[Super Buu] Machine Punches complete!")
end

-- Candy Beam attack: fires beam that stuns player with chocolate bar
local function performCandyBeam(targetRoot)
	if not running or isAttacking or not candyBeamModel then return end
	
	isAttacking = true
	
	-- Stop movement and rotation
	local originalSpeed = humanoid.WalkSpeed
	local originalAutoRotate = humanoid.AutoRotate
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false
	
	-- Face target initially
	local lookDir = (targetRoot.Position - root.Position) * Vector3.new(1, 0, 1)
	if lookDir.Magnitude > 0.001 then
		root.CFrame = CFrame.new(root.Position, root.Position + lookDir.Unit)
	end
	
	-- Play candy beam animation
	if candyBeamAnim then
		pcall(function()
			candyBeamAnim:Play(0.1, 1, 1)
		end)
	end
	SFXHelper.playAt(root, CANDY_BEAM_SFX_ID, 0.7, { minDist = 10, maxDist = 80 })
	task.wait(1.0)
	
	if not running then
		isAttacking = false
		return
	end
	
	-- Spawn candy_beam model in front of Buu
	print("[Super Buu] Firing Candy Beam!")
	
	local beam = candyBeamModel:Clone()
	
	print("[Super Buu] Beam cloned:", beam)
	print("[Super Buu] Beam ClassName:", beam.ClassName)
	print("[Super Buu] Beam children count:", #beam:GetChildren())
	for _, child in ipairs(beam:GetChildren()) do
		print("[Super Buu] Beam child:", child.Name, child.ClassName)
	end
	
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
		warn("[Super Buu] Candy Beam has no BasePart!")
		beam:Destroy()
		isAttacking = false
		return
	end
	
	local beamStart = os.clock()
	local beamDuration = 0.5
	local stunnedPlayers = {} -- Track who was stunned
	
	while os.clock() - beamStart < beamDuration and running do
		if ReplicatedStorage:GetAttribute("GamePaused") then
			task.wait(0.05)
		else
			-- Position beam in front of Buu, rotated horizontal
			if beamPart and root then
				local distance = 15
				local beamCFrame = root.CFrame * CFrame.new(0, 0, -distance) * CFrame.Angles(0, 0, 0)
				beam:PivotTo(beamCFrame)
			end
			
			-- Check for player hits
			local beamParts = {}
			
			-- If beam itself is a BasePart, add it
			if beam:IsA("BasePart") then
				table.insert(beamParts, beam)
			end
			
			-- Add all descendant BaseParts
			for _, desc in ipairs(beam:GetDescendants()) do
				if desc:IsA("BasePart") then
					table.insert(beamParts, desc)
				end
			end
			
			print("[Super Buu] Checking collisions. Beam parts count:", #beamParts)
			
			for _, player in ipairs(Players:GetPlayers()) do
				if not stunnedPlayers[player.UserId] then
					local character = player.Character
					if character then
						local playerHum = character:FindFirstChildOfClass("Humanoid")
						local playerRoot = character:FindFirstChild("HumanoidRootPart")
						
						if playerHum and playerHum.Health > 0 and playerRoot then
							print("[Super Buu] Checking player:", player.Name, "at position:", playerRoot.Position)
							
							-- Check distance to each beam part
							for _, beamPartObj in ipairs(beamParts) do
								local dist = (beamPartObj.Position - playerRoot.Position).Magnitude
								
								if dist <= 15 then -- Within 15 studs of any beam part
									stunnedPlayers[player.UserId] = true
									print("[Super Buu] Candy Beam hit player:", player.Name, "Distance:", dist)
									
									-- Stun player
									local originalPlayerSpeed = playerHum.WalkSpeed
									local originalJumpPower = playerHum.JumpPower
									local originalPlayerAutoRotate = playerHum.AutoRotate
									
									print("[Super Buu] Stunning player. Original speed:", originalPlayerSpeed)
									
									playerHum.WalkSpeed = 0
									playerHum.JumpPower = 0
									playerHum.AutoRotate = false
									
									-- Clone and spawn choc_bar on player
									print("[Super Buu] chocBarModel exists?", chocBarModel ~= nil)
									if chocBarModel then
										local chocBar = chocBarModel:Clone()
										print("[Super Buu] Cloned choc_bar:", chocBar)
										chocBar.Parent = workspace
										
										-- Make choc_bar non-collidable
										for _, part in ipairs(chocBar:GetDescendants()) do
											if part:IsA("BasePart") then
												part.CanCollide = false
												part.Anchored = true
											end
										end
										
										print("[Super Buu] Spawned choc_bar on", player.Name, "at", playerRoot.Position)
										
										-- Follow player for 2 seconds
										local followConnection
										followConnection = game:GetService("RunService").Heartbeat:Connect(function()
											if chocBar and chocBar.Parent and playerRoot and playerRoot.Parent then
												-- Rotate choc_bar 90 degrees then move back in its own space
												chocBar:PivotTo(playerRoot.CFrame * CFrame.Angles(math.rad(90), math.rad(90), 0))
											else
												if followConnection then
													followConnection:Disconnect()
												end
											end
										end)
										
										-- Remove stun after 2 seconds
										task.delay(2.0, function()
											print("[Super Buu] Removing stun from", player.Name)
											
											-- Disconnect follow
											if followConnection then
												followConnection:Disconnect()
											end
											
											-- Destroy chocolate bar
											if chocBar and chocBar.Parent then
												chocBar:Destroy()
												print("[Super Buu] Destroyed choc_bar")
											end
											
											-- Restore player movement
											if playerHum and playerHum.Parent then
												playerHum.WalkSpeed = originalPlayerSpeed
												playerHum.JumpPower = originalJumpPower
												playerHum.AutoRotate = originalPlayerAutoRotate
												print("[Super Buu] Player unstunned! Speed restored to", originalPlayerSpeed)
											end
										end)
									else
										print("[Super Buu] chocBarModel is nil!")
									end
									
									break -- Exit beam parts loop once hit
								end
							end -- for _, beamPartObj
						end -- if playerHum
					end -- if character
				end -- if not stunnedPlayers
			end -- for _, player
			
			task.wait(0.05)
		end
	end
	
	-- Destroy beam
	if beam and beam.Parent then
		beam:Destroy()
	end
	
	-- Restore Super Buu movement
	humanoid.WalkSpeed = originalSpeed
	humanoid.AutoRotate = originalAutoRotate
	
	isAttacking = false
	print("[Super Buu] Candy Beam complete!")
end

-- Shout attack: 180° cone damage with sound wave visual
local function performShout(targetRoot)
	if not running or isAttacking or not soundWaveModel then return end
	
	isAttacking = true
	
	print("[Super Buu] Shout started!")
	
	-- Stop movement but keep rotation enabled (slow)
	local originalSpeed = humanoid.WalkSpeed
	local originalAutoRotate = humanoid.AutoRotate
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = true -- Can rotate slowly
	
	-- Face target initially
	local lookDir = (targetRoot.Position - root.Position) * Vector3.new(1, 0, 1)
	if lookDir.Magnitude > 0.001 then
		root.CFrame = CFrame.new(root.Position, root.Position + lookDir.Unit)
	end
	
	-- Play shout animation
	if shoutAnim then
		pcall(function()
			shoutAnim:Play(0.1, 1, 1)
		end)
	end
	
	-- 1.5s charge phase
	task.wait(1.5)
	
	if not running then
		isAttacking = false
		return
	end
	SFXHelper.playAt(root, SHOUT_SFX_ID, 0.7, { minDist = 10, maxDist = 80 })
	
	-- Clone sound_wave model
	local soundWave = soundWaveModel:Clone()
	soundWave.Parent = workspace
	
	-- Anchor all parts to prevent falling
	for _, part in ipairs(soundWave:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	if soundWave:IsA("BasePart") then
		soundWave.Anchored = true
	end
	
	-- Position sound_wave in front of Buu
	local soundWaveDistance = 2
	soundWave:PivotTo(root.CFrame * CFrame.new(0, 0, -soundWaveDistance) * CFrame.Angles(0, math.rad(-90), 0))
	
	-- Damage phase constants
	local SHOUT_RANGE = 25
	local SHOUT_DAMAGE = 30
	local damagePhaseStart = os.clock()
	local damagePhaseDuration = 1.0
	local damageInterval = 0.2
	local nextDamageTick = damagePhaseStart
	
	-- Start scale animation loop
	local scaleRunning = true
	local originalSize = soundWave:GetScale()
	
	task.spawn(function()
		while scaleRunning do
			-- Scale from 0.2 to 2.0 over 0.2 seconds
			local startTime = os.clock()
			local duration = 0.2
			local minScale = 0.2
			local maxScale = 2.0
			
			while os.clock() - startTime < duration and scaleRunning do
				local elapsed = os.clock() - startTime
				local alpha = elapsed / duration
				local currentScale = minScale + (maxScale - minScale) * alpha
				
				soundWave:ScaleTo(currentScale)
				
				task.wait()
			end
			
			if not scaleRunning then break end
			
			-- Ensure we hit max scale
			soundWave:ScaleTo(maxScale)
		end
	end)
	
	-- Damage phase loop
	local damagedPlayers = {} -- Track players hit this phase
	
	while os.clock() - damagePhaseStart < damagePhaseDuration do
		if not running then break end
		
		local now = os.clock()
		
		-- Check if it's time for damage tick
		if now >= nextDamageTick then
			nextDamageTick = now + damageInterval
			
			-- Get Buu's forward direction (top-down)
			local buuForward = root.CFrame.LookVector * Vector3.new(1, 0, 1)
			if buuForward.Magnitude > 0.001 then
				buuForward = buuForward.Unit
			end
			
			local halfAngle = math.rad(90) -- 180° cone = 90° half angle
			
			-- Check all players
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				if character then
					local playerRoot = character:FindFirstChild("HumanoidRootPart")
					local playerHum = character:FindFirstChildOfClass("Humanoid")
					
					if playerRoot and playerHum and playerHum.Health > 0 then
						-- Top-down cone check
						local toPlayer = (playerRoot.Position - root.Position) * Vector3.new(1, 0, 1)
						local dist = toPlayer.Magnitude
						
						if dist <= SHOUT_RANGE then
							local dirToPlayer = toPlayer.Unit
							local angle = math.acos(math.clamp(buuForward:Dot(dirToPlayer), -1, 1))
							
							if angle <= halfAngle then
								-- Player is in 180° cone
								Damage.Apply(playerHum, SHOUT_DAMAGE)
								print("[Super Buu] Shout hit", player.Name, "for", SHOUT_DAMAGE, "damage!")
							end
						end
					end
				end
			end
		end
		
		task.wait(0.05)
	end
	
	-- Stop scale animation
	scaleRunning = false
	
	-- Destroy sound wave
	if soundWave and soundWave.Parent then
		soundWave:Destroy()
	end
	
	-- Restore movement
	humanoid.WalkSpeed = originalSpeed
	humanoid.AutoRotate = originalAutoRotate
	
	if shoutAnim and shoutAnim.IsPlaying then
		shoutAnim:Stop(0.1)
	end
	
	isAttacking = false
	print("[Super Buu] Shout complete!")
end

-- Many Beam attack: spawn 20 random targets, charge, then rain buu_balls in arcs
local function performManyBeam(targetRoot)
	if not running or isAttacking or not manyChargeModel or not buuBallModel or not leftArmAttachment then return end
	
	isAttacking = true
	
	print("[Super Buu] Many Beam started!")
	
	-- Stop movement
	local originalSpeed = humanoid.WalkSpeed
	local originalAutoRotate = humanoid.AutoRotate
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false
	
	-- Face target initially
	local lookDir = (targetRoot.Position - root.Position) * Vector3.new(1, 0, 1)
	if lookDir.Magnitude > 0.001 then
		root.CFrame = CFrame.new(root.Position, root.Position + lookDir.Unit)
	end
	
	-- Play many_beam animation
	if manyBeamAnim then
		pcall(function()
			manyBeamAnim:Play(0.1, 1, 1)
		end)
	end
	SFXHelper.playAt(root, MANY_BEAM_SFX_ID, 0.7, { minDist = 10, maxDist = 80 })
	
	-- Get arena bounds from ReplicatedStorage
	local arenaBounds = nil
	local mapConfig = ReplicatedStorage:FindFirstChild("Scripts")
	if mapConfig then
		mapConfig = mapConfig:FindFirstChild("namek")
		if mapConfig then
			mapConfig = mapConfig:FindFirstChild("WaveConfig")
			if mapConfig and mapConfig:IsA("ModuleScript") then
				local ok, config = pcall(require, mapConfig)
				if ok and config and config.ArenaBounds then
					arenaBounds = config.ArenaBounds
				end
			end
		end
	end
	
	-- Mark 20 random positions on the map
	local targetPositions = {}
	local previewMarkers = {}
	local PREVIEW_RADIUS = 8
	local BALL_DAMAGE = 50
	
	-- Generate 20 random positions within arena bounds
	for i = 1, 20 do
		local targetPos = nil
		
		if arenaBounds and arenaBounds.min and arenaBounds.max then
			-- Use arena bounds
			local mn, mx = arenaBounds.min, arenaBounds.max
			local x = mn.X + (mx.X - mn.X) * math.random()
			local z = mn.Z + (mx.Z - mn.Z) * math.random()
			
			-- Raycast down to find ground
			local rayOrigin = Vector3.new(x, 100, z)
			local rayDirection = Vector3.new(0, -200, 0)
			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			raycastParams.FilterDescendantsInstances = {enemyModel}
			
			local rayResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
			
			if rayResult then
				targetPos = rayResult.Position
			else
				-- Fallback to random Y
				targetPos = Vector3.new(x, root.Position.Y, z)
			end
		else
			-- Fallback: use random positions around target
			local randomOffset = Vector3.new(
				math.random(-40, 40),
				0,
				math.random(-40, 40)
			)
			targetPos = targetRoot.Position + randomOffset
		end
		
		table.insert(targetPositions, targetPos)
		
		-- Create red circle preview marker
		local preview = Instance.new("Part")
		preview.Name = "ManyBeamPreview"
		preview.Shape = Enum.PartType.Cylinder
		preview.Size = Vector3.new(0.5, PREVIEW_RADIUS * 2, PREVIEW_RADIUS * 2)
		preview.CFrame = CFrame.new(targetPos) * CFrame.Angles(0, 0, math.rad(90))
		preview.Anchored = true
		preview.CanCollide = false
		preview.Material = Enum.Material.Neon
		preview.Color = Color3.fromRGB(255, 0, 0)
		preview.Transparency = 0.5
		preview.Parent = workspace
		
		table.insert(previewMarkers, preview)
	end
	
	-- Spawn many_charge on left arm attachment
	local handCharge = manyChargeModel:Clone()
	handCharge.Parent = workspace
	
	-- Anchor all parts
	for _, part in ipairs(handCharge:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	if handCharge:IsA("BasePart") then
		handCharge.Anchored = true
	end
	
	-- Position at left arm attachment
	local updateHandCharge
	updateHandCharge = game:GetService("RunService").Heartbeat:Connect(function()
		if handCharge and handCharge.Parent and leftArmAttachment and leftArmAttachment.Parent then
			handCharge:PivotTo(leftArmAttachment.WorldCFrame)
		end
	end)
	
	-- Wait 2 seconds (charge time)
	task.wait(2.0)
	
	-- Stop updating hand charge position
	if updateHandCharge then
		updateHandCharge:Disconnect()
	end
	
	-- Destroy hand charge
	if handCharge and handCharge.Parent then
		handCharge:Destroy()
	end
	
	if not running then
		-- Clean up previews
		for _, preview in ipairs(previewMarkers) do
			if preview and preview.Parent then
				preview:Destroy()
			end
		end
		isAttacking = false
		return
	end
	
	-- Launch buu_balls every 0.2s for 1 second (5 projectiles)
	local projectileCount = 5
	local launchInterval = 0.2
	
	for i = 1, projectileCount do
		if not running then break end
		
		-- Launch buu_balls to all 20 targets
		for targetIndex, targetPos in ipairs(targetPositions) do
			if not running then break end
			
			-- Spawn buu_ball
			local ball = buuBallModel:Clone()
			ball.Parent = workspace
			
			-- Get primary part or first BasePart
			local ballPart = nil
			if ball:IsA("Model") then
				ballPart = ball.PrimaryPart or ball:FindFirstChildWhichIsA("BasePart")
			elseif ball:IsA("BasePart") then
				ballPart = ball
			end
			
			if ballPart then
				-- Start position: left arm attachment
				local startPos = leftArmAttachment.WorldPosition
				local endPos = targetPos
				
				-- Arc trajectory parameters
				local arcHeight = 30 -- Height of the arc
				local duration = 1.0 -- Travel time
				
				-- Launch projectile in arc
				task.spawn(function()
					local startTime = os.clock()
					
					while os.clock() - startTime < duration do
						if not ball or not ball.Parent then break end
						
						local elapsed = os.clock() - startTime
						local alpha = elapsed / duration
						
						-- Linear interpolation for X and Z
						local currentPos = startPos:Lerp(endPos, alpha)
						
						-- Parabolic arc for Y
						local arcProgress = 4 * alpha * (1 - alpha) -- Parabola: peaks at 0.5
						currentPos = currentPos + Vector3.new(0, arcHeight * arcProgress, 0)
						
						-- Update position
						if ball:IsA("Model") then
							ball:PivotTo(CFrame.new(currentPos))
						else
							ball.Position = currentPos
						end
						
						task.wait()
					end
					
					-- Projectile reached ground
					if ball and ball.Parent then
						-- Create pink explosion
						local explosion = Instance.new("Explosion")
						explosion.Position = endPos
						explosion.BlastRadius = PREVIEW_RADIUS
						explosion.BlastPressure = 0
						explosion.DestroyJointRadiusPercent = 0
						explosion.ExplosionType = Enum.ExplosionType.NoCraters
						explosion.Parent = workspace
						
						-- Make explosion pink
						local light = Instance.new("PointLight")
						light.Color = Color3.fromRGB(255, 105, 180)
						light.Brightness = 5
						light.Range = 20
						light.Parent = explosion
						
						task.delay(0.5, function()
							if explosion and explosion.Parent then
								explosion:Destroy()
							end
						end)
						
						-- Deal damage in area
						for _, player in ipairs(Players:GetPlayers()) do
							local character = player.Character
							if character then
								local playerRoot = character:FindFirstChild("HumanoidRootPart")
								local playerHum = character:FindFirstChildOfClass("Humanoid")
								
								if playerRoot and playerHum and playerHum.Health > 0 then
									local dist = (playerRoot.Position - endPos).Magnitude
									
									if dist <= PREVIEW_RADIUS then
										Damage.Apply(playerHum, BALL_DAMAGE)
										print("[Super Buu] Buu Ball hit", player.Name, "for", BALL_DAMAGE, "damage!")
									end
								end
							end
						end
						
						-- Destroy ball
						ball:Destroy()
					end
				end)
			end
		end
		
		-- Wait before next volley
		if i < projectileCount then
			task.wait(launchInterval)
		end
	end
	
	-- Wait for projectiles to land
	task.wait(1.5)
	
	-- Clean up preview markers
	for _, preview in ipairs(previewMarkers) do
		if preview and preview.Parent then
			preview:Destroy()
		end
	end
	
	-- Restore movement
	humanoid.WalkSpeed = originalSpeed
	humanoid.AutoRotate = originalAutoRotate
	
	if manyBeamAnim and manyBeamAnim.IsPlaying then
		manyBeamAnim:Stop(0.1)
	end
	
	isAttacking = false
	print("[Super Buu] Many Beam complete!")
end

-- Movement loop
task.spawn(function()
	while running do
		if ReplicatedStorage:GetAttribute("GamePaused") then
			task.wait(0.05)
			continue
		end
		
		local targetRoot = findClosestPlayer()
		
		if targetRoot and not isAttacking then
			humanoid:MoveTo(targetRoot.Position)
		end
		
		task.wait(0.1)
	end
end)

-- Attack loop
local lastAttack = 0
local lastMachinePunches = 0
local lastCandyBeam = 0
local lastShout = 0
local lastManyBeam = 0
local MACHINE_PUNCHES_INTERVAL = 10 -- Use every 10 seconds
local MACHINE_PUNCHES_RANGE = 20 -- Can use from medium range
local CANDY_BEAM_INTERVAL = 15 -- Use every 15 seconds
local CANDY_BEAM_RANGE = 35 -- Long range beam
local SHOUT_INTERVAL = 20 -- Use every 20 seconds
local SHOUT_RANGE = 25 -- Medium range cone
local MANY_BEAM_INTERVAL = 25 -- Use every 25 seconds
local MANY_BEAM_RANGE = 40 -- Medium-long range

task.spawn(function()
	while running do
		if ReplicatedStorage:GetAttribute("GamePaused") then
			task.wait(0.05)
			continue
		end
		
		local now = os.clock()
		local targetRoot, distance = findClosestPlayer()
		
		if targetRoot then
			-- Priority: Many Beam > Shout > Candy Beam > Machine Punches > Normal Attack
			if now - lastManyBeam >= MANY_BEAM_INTERVAL and distance <= MANY_BEAM_RANGE and not isAttacking then
				print("[Super Buu] Using Many Beam!")
				lastManyBeam = now
				lastAttack = now
				performManyBeam(targetRoot)
			elseif now - lastShout >= SHOUT_INTERVAL and distance <= SHOUT_RANGE and not isAttacking then
				print("[Super Buu] Using Shout!")
				lastShout = now
				lastAttack = now
				performShout(targetRoot)
			elseif now - lastCandyBeam >= CANDY_BEAM_INTERVAL and distance <= CANDY_BEAM_RANGE and not isAttacking then
				print("[Super Buu] Using Candy Beam!")
				lastCandyBeam = now
				lastAttack = now
				performCandyBeam(targetRoot)
			elseif now - lastMachinePunches >= MACHINE_PUNCHES_INTERVAL and distance <= MACHINE_PUNCHES_RANGE and not isAttacking then
				print("[Super Buu] Using Machine Punches!")
				lastMachinePunches = now
				lastAttack = now
				performMachinePunches(targetRoot)
			elseif now - lastAttack >= ATTACK_COOLDOWN and distance <= ATTACK_RANGE and not isAttacking then
				lastAttack = now
				performNormalAttack(targetRoot)
			end
		end
		
		task.wait(0.1)
	end
end)

print("[Super Buu] AI initialized! Ready to fight!")
