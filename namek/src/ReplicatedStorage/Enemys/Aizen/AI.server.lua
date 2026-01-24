-- Aizen AI
-- Boss bleach lvl 3
-- Abilities:
-- 1) Normal Attack: melee slash when in range
-- 2) Hado 90 (Kurohitsugi): Spawn black box on player, increases opacity, immobilizes, then implodes for damage
-- 3) Kyoka Suigetsu (Trick): Makes Aizen intangible and immune to damage for duration

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local enemyModel = script.Parent
local humanoid = enemyModel:FindFirstChildOfClass("Humanoid") or enemyModel:WaitForChild("Humanoid", 2)
local root = enemyModel:FindFirstChild("HumanoidRootPart") or (enemyModel:WaitForChild("HumanoidRootPart", 2))
if not humanoid or not root then return end

if not enemyModel.PrimaryPart then
	enemyModel.PrimaryPart = root
end

-- Load Stats
local STATS do
	local statsModule = enemyModel:FindFirstChild("Stats")
	if statsModule and statsModule:IsA("ModuleScript") then
		local ok, data = pcall(require, statsModule)
		if ok and type(data) == "table" then STATS = data end
	end
end

local Damage = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("Damage"))

-- Extract stat values
local MOVE_SPEED = (STATS and STATS.MoveSpeed) or 16
local ATTACK_RANGE = (STATS and STATS.AttackRange) or 10
local ATTACK_COOLDOWN = (STATS and STATS.AttackCooldown) or 1.8
local ATTACK_DAMAGE = (STATS and STATS.AttackDamage) or 100

-- Hado 90
local HADO_INTERVAL = (STATS and STATS.HadoInterval) or 35
local HADO_RANGE = (STATS and STATS.HadoRange) or 80
local HADO_BUILDUP = (STATS and STATS.HadoBuildupTime) or 2.5
local HADO_DAMAGE = (STATS and STATS.HadoDamage) or 400

-- Kyoka Suigetsu (Trick)
local TRICK_INTERVAL = (STATS and STATS.TrickInterval) or 25
local TRICK_DURATION = (STATS and STATS.TrickDuration) or 5.0

-- Clone Illusion
local CLONE_INTERVAL = (STATS and STATS.CloneInterval) or 30
local CLONE_COUNT = (STATS and STATS.CloneCount) or 4
local CLONE_HEALTH = (STATS and STATS.CloneHealth) or 200
local CLONE_MOVE_SPEED = (STATS and STATS.CloneMoveSpeed) or 20
local CLONE_EXPLOSION_DAMAGE = (STATS and STATS.CloneExplosionDamage) or 250
local CLONE_EXPLOSION_RADIUS = (STATS and STATS.CloneExplosionRadius) or 10

local INITIAL_ATTACK_COOLDOWN = 3
local SPAWN_POS = root.Position
local MAX_MAP_RADIUS = 600
local SPAWN_TIME = os.clock()

local running = true
humanoid.Died:Connect(function() running = false end)
enemyModel.AncestryChanged:Connect(function(_, parent) if not parent then running = false end end)

-- Animation system
local animator: Animator? = humanoid:FindFirstChildOfClass("Animator")
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end
local animTracks: { [string]: AnimationTrack } = {}

local function loadAnimationByName(name: string): AnimationTrack?
	if animTracks[name] then return animTracks[name] end
	local folder = enemyModel:FindFirstChild("Animation")
	local animObj: Animation? = nil
	if folder then
		animObj = folder:FindFirstChild(name)
		if animObj and not animObj:IsA("Animation") then animObj = nil end
	end
	if animObj and animator then
		local track = animator:LoadAnimation(animObj)
		animTracks[name] = track
		return track
	end
	return nil
end

local function playAnim(name: string, fade: number?, weight: number?, speed: number?)
	local tr = loadAnimationByName(name)
	if tr then
		if tr.Length == 0 then
			local timeout = 0
			while tr.Length == 0 and timeout < 50 do
				task.wait(0.05)
				timeout = timeout + 1
			end
		end
		tr:Play(fade or 0.1, weight or 1.0, speed or 1.0)
		return tr
	end
end

-- ========================================
-- UTILITY FUNCTIONS
-- ========================================
local paused = false
local function isPaused()
	return paused
end

local function pauseAwareWait(duration)
	local elapsed = 0
	while elapsed < duration do
		if not isPaused() then
			elapsed = elapsed + 0.05
		end
		task.wait(0.05)
	end
end

local frozenState = false
local function isFrozen()
	return frozenState
end

local function setFrozen(shouldFreeze)
	frozenState = shouldFreeze
	if humanoid then
		humanoid.AutoRotate = not shouldFreeze
		humanoid.WalkSpeed = shouldFreeze and 0 or MOVE_SPEED
	end
end

local actionLockCount = 0
local function isActionLocked()
	return actionLockCount > 0
end

local function pushActionLock()
	actionLockCount = actionLockCount + 1
	setFrozen(true)
end

local function popActionLock()
	actionLockCount = math.max(0, actionLockCount - 1)
	if actionLockCount == 0 then
		setFrozen(false)
	end
end

-- Get nearest player
local function getNearestPlayer(maxDist)
	local nearest = nil
	local nearestDist = maxDist or math.huge
	
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local r = char and char:FindFirstChild("HumanoidRootPart")
		if hum and r and hum.Health > 0 then
			local dist = (r.Position - root.Position).Magnitude
			if dist < nearestDist then
				nearest = r
				nearestDist = dist
			end
		end
	end
	
	return nearest, nearestDist
end

-- Flat direction (top-down)
local function flatDirTo(targetPos: Vector3)
	local diff = (targetPos - root.Position) * Vector3.new(1, 0, 1)
	if diff.Magnitude > 0.001 then
		return diff.Unit
	end
	return root.CFrame.LookVector * Vector3.new(1, 0, 1)
end

-- Area damage
local function areaDamage(center: Vector3, radius: number, damage: number)
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local r = char and char:FindFirstChild("HumanoidRootPart")
		if hum and r and hum.Health > 0 then
			local dist = (r.Position - center).Magnitude
			if dist <= radius then
				local waveMult = enemyModel:GetAttribute("DamageWaveMultiplier") or 1
				Damage.Apply(hum, damage * waveMult)
			end
		end
	end
end

-- ========================================
-- NORMAL ATTACK
-- ========================================
local lastAttack = -999

local function tryNormalAttack(now)
	if now - lastAttack < ATTACK_COOLDOWN then return end
	local targetRoot, dist = getNearestPlayer(ATTACK_RANGE)
	if not targetRoot then return end
	
	pushActionLock()
	
	-- Face target
	local dir = flatDirTo(targetRoot.Position)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir, Vector3.yAxis)
	
	-- Play attack animation
	local attackAnim = playAnim("aizen_normal", 0.1, 1.0, 1.0)
	
	if attackAnim then
		pauseAwareWait(attackAnim.Length or 0.6)
	else
		pauseAwareWait(0.6)
	end
	
	-- Deal damage
	areaDamage(root.Position + dir * 3, ATTACK_RANGE, ATTACK_DAMAGE)
	
	popActionLock()
	lastAttack = os.clock()
end

-- ========================================
-- HADO 90 (Kurohitsugi)
-- ========================================
local lastHado = -999

local function tryHado90(now)
	if now - lastHado < HADO_INTERVAL then return end
	local targetRoot, dist = getNearestPlayer(HADO_RANGE)
	if not targetRoot then return end
	
	local targetPlayer = Players:GetPlayerFromCharacter(targetRoot.Parent)
	if not targetPlayer then return end
	
	pushActionLock()
	
	-- Face target
	local dir = flatDirTo(targetRoot.Position)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir, Vector3.yAxis)
	
	-- Play Hado animation
	local hadoAnim = playAnim("Hado", 0.1, 1.0, 1.0)
	
	-- Spawn True_Hado90 model on player
	local attacksFolder = ReplicatedStorage:FindFirstChild("Enemys") and ReplicatedStorage.Enemys:FindFirstChild("Attacks")
	local hadoModel = attacksFolder and attacksFolder:FindFirstChild("True_Hado90")
	local hadoInstance = nil
	local targetHumanoid = targetRoot.Parent:FindFirstChildOfClass("Humanoid")
	local originalWalkSpeed = targetHumanoid and targetHumanoid.WalkSpeed or 16
	
	if hadoModel and targetRoot then
		hadoInstance = hadoModel:Clone()
		hadoInstance.Name = "AizenHado90"
		hadoInstance.Parent = workspace
		
		-- Position on player
		if hadoInstance:IsA("Model") then
			hadoInstance:PivotTo(CFrame.new(targetRoot.Position))
		elseif hadoInstance:IsA("BasePart") then
			hadoInstance.CFrame = CFrame.new(targetRoot.Position)
		end
		
		-- Make non-blocking
		for _, d in ipairs(hadoInstance:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d.Anchored = true
			end
		end
		
		-- Immobilize player
		if targetHumanoid then
			targetHumanoid.WalkSpeed = 0
		end
		
		-- Gradually increase opacity (reach full opacity at 1.0s, damage at 1.8s)
		local OPACITY_BUILDUP = 1.0
	task.spawn(function()
		local startTime = os.clock()
		while hadoInstance and hadoInstance.Parent and (os.clock() - startTime) < OPACITY_BUILDUP do
			local alpha = (os.clock() - startTime) / OPACITY_BUILDUP
			
			for _, d in ipairs(hadoInstance:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Transparency = 1 - alpha -- Start transparent, become opaque
				end
			end
			
			task.wait(0.05)
		end
		
		-- Ensure full opacity
		if hadoInstance and hadoInstance.Parent then
			for _, d in ipairs(hadoInstance:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Transparency = 0
				end
			end
		end
	end)
end

-- Wait for animation damage event
local damageTriggered = false

if hadoAnim then
	-- Listen for damage marker
	local markerConn
	markerConn = hadoAnim:GetMarkerReachedSignal("damage"):Connect(function()
		damageTriggered = true
		if markerConn then markerConn:Disconnect() end
	end)
	
	-- Wait for damage event or timeout
	local waitStart = os.clock()
	while (os.clock() - waitStart) < 3.0 and not damageTriggered do
			task.wait(0.05)
		end
		
		if markerConn then markerConn:Disconnect() end
	else
		pauseAwareWait(HADO_BUILDUP)
	end
	
	-- Implode and damage
	if hadoInstance and hadoInstance.Parent then
		-- Deal damage FIRST
		if targetHumanoid and targetHumanoid.Health > 0 then
			local waveMult = enemyModel:GetAttribute("DamageWaveMultiplier") or 1
			Damage.Apply(targetHumanoid, HADO_DAMAGE * waveMult)
		end
		
		-- Fast visual implosion effect (scale entire model from 0.242 to 0)
		task.spawn(function()
			local implosionTime = 0.25 -- Slightly slower
			local startTime = os.clock()
			local initialScale = 0.242 -- Model's actual scale in ReplicatedStorage
			
			if hadoInstance:IsA("Model") then
				while hadoInstance and hadoInstance.Parent and (os.clock() - startTime) < implosionTime do
					local alpha = (os.clock() - startTime) / implosionTime
					local scale = initialScale * (1 - alpha) -- 0.242 -> 0.0
					
					-- Scale entire model uniformly
					hadoInstance:ScaleTo(scale)
					
					task.wait(0.02)
				end
			else
				-- Single part
				local startSize = hadoInstance.Size
				while hadoInstance and hadoInstance.Parent and (os.clock() - startTime) < implosionTime do
					local alpha = (os.clock() - startTime) / implosionTime
					local scale = initialScale * (1 - alpha)
					
					hadoInstance.Size = startSize * scale
					
					task.wait(0.02)
				end
			end
			
			if hadoInstance then hadoInstance:Destroy() end
		end)
	end
	
	-- Restore player movement
	if targetHumanoid then
		targetHumanoid.WalkSpeed = originalWalkSpeed
	end
	
	if hadoAnim then hadoAnim:Stop(0.1) end
	
	popActionLock()
	lastHado = os.clock()
end

-- ========================================
-- KYOKA SUIGETSU (Trick - Intangibility)
-- ========================================
local lastTrick = -999
local isTrickActive = false

local function tryKyokaSuigetsu(now)
	if now - lastTrick < TRICK_INTERVAL then return end
	if isTrickActive then return end
	
	pushActionLock()
	
	-- Activate intangibility IMMEDIATELY
	isTrickActive = true
	enemyModel:SetAttribute("Invulnerable", true)
	
	-- Play Trick animation
	local trickAnim = playAnim("Trick", 0.1, 1.0, 1.0)
	
	-- Make Aizen semi-transparent
	for _, part in ipairs(enemyModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = math.min(1, part.Transparency + 0.5)
		end
	end
	
	if trickAnim then
		pauseAwareWait(trickAnim.Length or 1.0)
		trickAnim:Stop(0.1)
	else
		pauseAwareWait(1.0)
	end
	
	popActionLock()
	
	-- Spawn background task to maintain intangibility for 5 seconds
	task.spawn(function()
		local trickStart = os.clock()
		
		while isTrickActive and (os.clock() - trickStart) < TRICK_DURATION do
			task.wait(0.1)
		end
		
		-- Deactivate after duration
		isTrickActive = false
		enemyModel:SetAttribute("Invulnerable", false)
		
		-- Restore visibility
		for _, part in ipairs(enemyModel:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Transparency = math.max(0, part.Transparency - 0.5)
			end
		end
	end)
	
	lastTrick = os.clock()
end

-- ========================================
-- CLONE ILLUSION
-- ========================================
local lastClone = -999

local function tryCloneIllusion(now)
	if now - lastClone < CLONE_INTERVAL then return end
	
	pushActionLock()
	
	-- Play Clone animation with events
	local cloneAnim = playAnim("Clones", 0.1, 1.0, 1.0)
	
	-- Find Aizen's sword to fade
	local sword = enemyModel:FindFirstChild("Aizens Katana", true)
	local originalSwordTransparency = {}
	
	if sword then
		-- Store transparency of all parts in the sword
		for _, descendant in ipairs(sword:GetDescendants()) do
			if descendant:IsA("BasePart") then
				originalSwordTransparency[descendant] = descendant.Transparency
			end
		end
		
		-- Also include the sword itself if it's a BasePart
		if sword:IsA("BasePart") then
			originalSwordTransparency[sword] = sword.Transparency
		end
	end
	
	local clonesSpawned = false
	local activeClones = {}
	
	if cloneAnim then
		-- Listen for animation events
		local startFadeConn, endFadeConn, appearConn
		
		-- Event 1: start_fade at 1.2s - sword starts fading
		startFadeConn = cloneAnim:GetMarkerReachedSignal("start_fade"):Connect(function()
			if sword then
				task.spawn(function()
					local fadeTime = 0.7 -- 1.2s to 1.9s = 0.7s duration
					local fadeStart = os.clock()
					
					while (os.clock() - fadeStart) < fadeTime do
						local alpha = (os.clock() - fadeStart) / fadeTime
						
						for part, origTrans in pairs(originalSwordTransparency) do
							if part and part.Parent then
								part.Transparency = origTrans + (1 - origTrans) * alpha -- Fade to 1
							end
						end
						
						task.wait(0.03)
					end
					
					-- Ensure full transparency
					for part, _ in pairs(originalSwordTransparency) do
						if part and part.Parent then
							part.Transparency = 1
						end
					end
				end)
			end
			if startFadeConn then startFadeConn:Disconnect() end
		end)
		
		-- Event 2: end_fade at 1.9s - spawn clones
		endFadeConn = cloneAnim:GetMarkerReachedSignal("end_fade"):Connect(function()
			if not clonesSpawned then
				clonesSpawned = true
				
				print("[Aizen] Spawning clones...")
				
				-- Spawn 4 clones around Aizen
				local angleStep = (2 * math.pi) / CLONE_COUNT
				local spawnRadius = 15
				
				for i = 1, CLONE_COUNT do
					local angle = angleStep * (i - 1)
					local offsetX = math.cos(angle) * spawnRadius
					local offsetZ = math.sin(angle) * spawnRadius
					local spawnPos = root.Position + Vector3.new(offsetX, 0, offsetZ)
					
					-- Clone the entire Aizen model
					local cloneModel = enemyModel:Clone()
					cloneModel.Name = "AizenClone_" .. i
					cloneModel.Parent = workspace
					
					local cloneRoot = cloneModel:FindFirstChild("HumanoidRootPart")
					local cloneHum = cloneModel:FindFirstChildOfClass("Humanoid")
					
					if cloneRoot and cloneHum then
						-- Spawn clone facing the player
						local targetRoot = getNearestPlayer(500)
						if targetRoot then
							cloneRoot.CFrame = CFrame.new(spawnPos, targetRoot.Position)
						else
							cloneRoot.CFrame = CFrame.new(spawnPos)
						end
						
						cloneHum.Health = CLONE_HEALTH
						cloneHum.MaxHealth = CLONE_HEALTH
						cloneHum.WalkSpeed = CLONE_MOVE_SPEED
					cloneHum.AutoRotate = true -- Ensure clone rotates toward movement direction
					
					-- Remove ALL scripts from clone to prevent AI execution
					for _, descendant in ipairs(cloneModel:GetDescendants()) do
						if descendant:IsA("Script") or descendant:IsA("LocalScript") then
							descendant:Destroy()
						end
					end
					
					-- Make clone semi-transparent
					for _, part in ipairs(cloneModel:GetDescendants()) do
						if part:IsA("BasePart") then
							part.Transparency = math.min(1, part.Transparency + 0.3)
						end
					end
					
					-- Track clone
					table.insert(activeClones, {model = cloneModel, hum = cloneHum, root = cloneRoot})
					
					print("[Aizen] Clone " .. i .. " spawned at", spawnPos)
					
					-- Clone behavior: move toward player and explode on contact
					task.spawn(function()
					local cloneRunning = true
					
					cloneHum.Died:Connect(function()
						cloneRunning = false
					end)
					
					while cloneRunning and cloneHum.Health > 0 do
						local targetRoot, dist = getNearestPlayer(500)
						if targetRoot then
						cloneHum:MoveTo(targetRoot.Position)
						
						-- Recalculate distance after moving
						local currentDist = (cloneRoot.Position - targetRoot.Position).Magnitude
						
						-- Check for contact explosion
				if currentDist <= 3 then
					-- Explode
					areaDamage(cloneRoot.Position, CLONE_EXPLOSION_RADIUS, CLONE_EXPLOSION_DAMAGE)
					
					-- Explosion particles
					local explosionPart = Instance.new("Part")
					explosionPart.Size = Vector3.new(1, 1, 1)
					explosionPart.Position = cloneRoot.Position
					explosionPart.Anchored = true
					explosionPart.CanCollide = false
					explosionPart.Transparency = 1
					explosionPart.Parent = workspace
					
					local particles = Instance.new("ParticleEmitter")
					particles.Texture = "rbxasset://textures/particles/smoke_main.dds"
					particles.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(138, 43, 226)), ColorSequenceKeypoint.new(1, Color3.fromRGB(75, 0, 130))})
					particles.Size = NumberSequence.new(3, 10)
					particles.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1)})
					particles.Lifetime = NumberRange.new(0.5, 1)
					particles.Rate = 100
					particles.Speed = NumberRange.new(15, 25)
					particles.SpreadAngle = Vector2.new(180, 180)
					particles.Enabled = true
					particles.Parent = explosionPart
					
					-- Visual explosion
					local explosion = Instance.new("Explosion")
					explosion.Position = cloneRoot.Position
					explosion.BlastRadius = CLONE_EXPLOSION_RADIUS
					explosion.BlastPressure = 0
					explosion.DestroyJointRadiusPercent = 0
					explosion.ExplosionType = Enum.ExplosionType.NoCraters
					explosion.Parent = workspace
					
					-- Cleanup
					cloneModel:Destroy()
					task.delay(2, function()
						particles.Enabled = false
						game:GetService("Debris"):AddItem(explosionPart, 3)
					end)
					cloneRunning = false
				end
			end
			
			task.wait(0.03)
		end
	end)
				else
					print("[Aizen] Clone " .. i .. " failed to spawn - missing HumanoidRootPart or Humanoid")
				end
			end
		end
		if endFadeConn then endFadeConn:Disconnect() end
	end)
	
	-- Event 3: appear at 4.0s - restore sword
	appearConn = cloneAnim:GetMarkerReachedSignal("appear"):Connect(function()
		if sword then
			for part, origTrans in pairs(originalSwordTransparency) do
				if part and part.Parent then
					part.Transparency = origTrans
				end
			end
		end
		if appearConn then appearConn:Disconnect() end
	end)
		
		-- Wait for animation to finish
		pauseAwareWait(cloneAnim.Length or 4.0)
		
		-- Cleanup connections
		if startFadeConn then startFadeConn:Disconnect() end
		if endFadeConn then endFadeConn:Disconnect() end
		if appearConn then appearConn:Disconnect() end
		
		cloneAnim:Stop(0.1)
	end
	
	popActionLock()
	lastClone = os.clock()
end

-- ========================================
-- MAIN AI LOOP
-- ========================================
humanoid.WalkSpeed = MOVE_SPEED

task.spawn(function()
	pauseAwareWait(1.0)
	
	while running do
		if isPaused() then
			task.wait(0.1)
		else
			local now = os.clock()
			local targetRoot, dist = getNearestPlayer(500)
			
			if targetRoot then
				-- Priority: Trick (low health) > Clone Illusion > Hado90 > Normal Attack
				if humanoid.Health < (humanoid.MaxHealth * 0.5) and now - lastTrick >= TRICK_INTERVAL and not isActionLocked() then
					tryKyokaSuigetsu(now)
				elseif now - lastClone >= CLONE_INTERVAL and dist <= 40 and not isActionLocked() then
					tryCloneIllusion(now)
				elseif now - lastHado >= HADO_INTERVAL and dist <= HADO_RANGE and not isActionLocked() then
					tryHado90(now)
				elseif dist <= ATTACK_RANGE and not isActionLocked() then
					tryNormalAttack(now)
				elseif not isFrozen() then
					-- Always move toward player when not frozen (even during trick)
					humanoid:MoveTo(targetRoot.Position)
				end
			end
			
			task.wait(0.15)
		end
	end
end)

print("[Aizen] AI initialized - All according to plan...")
