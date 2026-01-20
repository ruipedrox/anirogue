-- Ulquiorra AI (Boss Bleach Level 2)
-- 4 Abilities:
-- 1) Dash Slash (Dash_begin, Dash, Dash_finish)
-- 2) Cero Beam (cero_charge animation + beam like Kamehameha with slower rotation)
-- 3) Trident Rain (5 tridents spawn in sky, telegraph circles, fall after delay)
-- 4) 1000 Cuts (gain speed, rapid cone damage while animation plays)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

-- Dash
local DASH_INTERVAL = (STATS and STATS.DashInterval) or 14
local DASH_TELEGRAPH = (STATS and STATS.DashTelegraph) or 1.5
local DASH_RANGE = (STATS and STATS.DashRange) or 50
local DASH_DAMAGE = (STATS and STATS.DashDamage) or 350
local DASH_AOE_RADIUS = (STATS and STATS.DashAoERadius) or 14
local DASH_PATH_DAMAGE = (STATS and STATS.DashPathTickDamage) or 160
local DASH_PATH_RADIUS = (STATS and STATS.DashPathTickRadius) or 7

-- Cero
local CERO_INTERVAL = (STATS and STATS.CeroInterval) or 18
local CERO_CHARGE = (STATS and STATS.CeroCharge) or 2.5
local CERO_DURATION = (STATS and STATS.CeroBeamDuration) or 3.0
local CERO_TICK_INTERVAL = (STATS and STATS.CeroTickInterval) or 0.3
local CERO_DAMAGE_TICK = (STATS and STATS.CeroDamagePerTick) or 120
local CERO_RANGE = (STATS and STATS.CeroRange) or 5

-- Trident
local TRIDENT_INTERVAL = (STATS and STATS.TridentInterval) or 22
local TRIDENT_COUNT = (STATS and STATS.TridentCount) or 5
local TRIDENT_FALL_DELAY = (STATS and STATS.TridentFallDelay) or 2.0
local TRIDENT_DAMAGE = (STATS and STATS.TridentDamage) or 280
local TRIDENT_AOE_RADIUS = (STATS and STATS.TridentAoERadius) or 18
local TRIDENT_HEIGHT = (STATS and STATS.TridentHeight) or 60

-- 1000 Cuts
local CUTS_INTERVAL = (STATS and STATS.CutsInterval) or 20
local CUTS_DURATION = (STATS and STATS.CutsDuration) or 3.0
local CUTS_SPEED_BOOST = (STATS and STATS.CutsMoveSpeedBoost) or 8
local CUTS_DAMAGE_TICK = (STATS and STATS.CutsDamagePerTick) or 90
local CUTS_TICK_RATE = (STATS and STATS.CutsTickRate) or 0.2
local CUTS_CONE_ANGLE = (STATS and STATS.CutsConeAngle) or 90
local CUTS_CONE_RANGE = (STATS and STATS.CutsConeRange) or 15

local SPAWN_TIME = os.clock()
local INITIAL_ATTACK_COOLDOWN = 3
local SPAWN_POS = root.Position
local MAX_MAP_RADIUS = 600

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

-- Hold last keyframe helper
local function holdLastKeyframePose(track: AnimationTrack?)
	if not track then return function() end end
	local holding = true
	task.spawn(function()
		task.wait(0.02)
		pcall(function() track.Looped = true end)
		while holding do
			if not track or not track.IsPlaying then break end
			local len = track.Length or 0
			if len > 0 then
				local tp = track.TimePosition
				if tp >= len - 0.05 then
					pcall(function()
						track:AdjustSpeed(0)
						track.TimePosition = math.max(0, len - 0.001)
						track:AdjustWeight(1)
					end)
				end
			end
			task.wait(0.05)
		end
	end)
	return function()
		holding = false
		pcall(function()
			if track and track.IsPlaying then
				track:AdjustSpeed(1)
				track:Stop(0.1)
			end
		end)
	end
end

-- Pause utility
local function isPaused()
	return ReplicatedStorage:GetAttribute("GamePaused") == true
end

local function pauseAwareWait(seconds)
	local remaining = seconds
	while remaining > 0 and running do
		if isPaused() then
			task.wait(0.05)
		else
			local dt = math.min(0.05, remaining)
			task.wait(dt)
			remaining -= dt
		end
	end
end

-- Freeze control
local frozenCount = 0
local actionLock = 0

local function isFrozen()
	return frozenCount > 0
end

local function isActionLocked()
	return actionLock > 0
end

local function pushActionLock()
	actionLock += 1
end

local function popActionLock()
	actionLock = math.max(0, actionLock - 1)
end

local function setFrozen(flag: boolean)
	if flag then
		frozenCount += 1
	else
		frozenCount = math.max(0, frozenCount - 1)
	end
	local shouldFreeze = frozenCount > 0
	if humanoid then
		humanoid.AutoRotate = not shouldFreeze
		humanoid.WalkSpeed = shouldFreeze and 0 or MOVE_SPEED
	end
end

-- Targeting
local function getNearestPlayer(maxRange)
	local best, bestDist
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local r = char and char:FindFirstChild("HumanoidRootPart")
		if hum and r and hum.Health > 0 then
			local d = (r.Position - root.Position).Magnitude
			if (not maxRange or d <= maxRange) and (not bestDist or d < bestDist) then
				bestDist = d
				best = r
			end
		end
	end
	return best, bestDist
end

-- Area damage helper
local function areaDamage(center, radius, baseDamage)
	local waveMult = enemyModel:GetAttribute("DamageWaveMultiplier") or 1
	local dmg = baseDamage * waveMult
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local r = char and char:FindFirstChild("HumanoidRootPart")
		if hum and r and hum.Health > 0 then
			local dist = (r.Position - center).Magnitude
			if dist <= radius then
				Damage.Apply(hum, dmg)
			end
		end
	end
end

-- Telegraph linha
local function createLineTelegraph(startPos: Vector3, dir: Vector3, length: number, width: number, duration: number, color: Color3)
	dir = (dir.Magnitude > 1e-3) and dir.Unit or Vector3.new(0,0,-1)
	local part = Instance.new("Part")
	part.Name = "UlquiorraDashTelegraph"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = color or Color3.fromRGB(0, 255, 100)
	part.Transparency = 0.4
	local thickness = 0.35
	part.Size = Vector3.new(math.max(2, width), thickness, math.max(2, length))
	local look = CFrame.lookAt(startPos, startPos + dir)
	local yDrop = 0
	pcall(function()
		if root and root:IsA("BasePart") then
			yDrop = math.max(0, (root.Size.Y * 0.5) - 0.1)
		else
			yDrop = 2.0
		end
	end)
	part.CFrame = look * CFrame.new(0, -yDrop, -length/2)
	part.Parent = workspace
	task.spawn(function()
		local t = 0
		while t < duration and part.Parent do
			if isPaused() then
				task.wait(0.05)
			else
				local dt = 0.05
				local alpha = t / duration
				local pulse = 1 + math.sin(alpha * math.pi) * 0.12
				part.Size = Vector3.new(math.max(2, width) * pulse, thickness, math.max(2, length))
				part.Transparency = 0.5 + math.sin(alpha * math.pi) * 0.2
				task.wait(dt)
				t += dt
			end
		end
		if part and part.Parent then part:Destroy() end
	end)
	return part
end

-- Telegraph circular
local function createCircleTelegraph(position: Vector3, radius: number, duration: number, color: Color3)
	local part = Instance.new("Part")
	part.Name = "UlquiorraTelegraph"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Neon
	part.Color = color or Color3.fromRGB(255, 0, 0)
	part.Transparency = 0.6 -- Less visible/lower opacity
	local height = 0.5 -- Taller for better visibility (was 0.3)
	part.Size = Vector3.new(height, radius*2, radius*2)
	part.CFrame = CFrame.new(position) * CFrame.Angles(0,0,math.rad(90))
	part.Parent = workspace
	task.spawn(function()
		local t = 0
		while t < duration and part.Parent do
			if isPaused() then
				task.wait(0.05)
			else
				local dt = 0.05
				local alpha = t/duration
				-- Subtle pulse effect (0.6 ± 0.15 = 0.45 to 0.75)
				part.Transparency = 0.6 + math.sin(alpha*math.pi*4)*0.15
				task.wait(dt)
				t += dt
			end
		end
		if part and part.Parent then part:Destroy() end
	end)
	return part
end

-- ========================================
-- DASH SLASH
-- ========================================
local lastDash = 0

local function tryDashSlash(now)
	if now - lastDash < DASH_INTERVAL then return end
	if now - SPAWN_TIME < INITIAL_ATTACK_COOLDOWN then return end
	local targetRoot, dist = getNearestPlayer(500)
	if not targetRoot then return end
	
	local function flatDirTo(pos: Vector3)
		local from = root.Position
		local to = Vector3.new(pos.X, from.Y, pos.Z)
		local v = (to - from)
		if v.Magnitude < 1e-3 then return Vector3.new(0,0,-1) end
		return v.Unit
	end
	
	local direction = flatDirTo(targetRoot.Position)
	
	-- Telegraph windup
	local windup = playAnim("Dash_begin", 0.1, 1.0, 1.0)
	local releaseWindupPose = holdLastKeyframePose(windup)
	setFrozen(true)
	
	local corridorWidth = math.max(4, DASH_PATH_RADIUS * 2)
	local lineTele = createLineTelegraph(root.Position, direction, DASH_RANGE, corridorWidth, DASH_TELEGRAPH + 10, Color3.fromRGB(0, 255, 100))
	
	-- Rotate toward player during windup
	local windupEnd = os.clock() + DASH_TELEGRAPH
	local lastDir = direction
	while running and os.clock() < windupEnd do
		if isPaused() then
			task.wait(0.05)
		else
			local tr = select(1, getNearestPlayer(500)) or targetRoot
			if tr then
				lastDir = flatDirTo(tr.Position)
			end
			local pos = root.Position
			root.CFrame = CFrame.lookAt(pos, pos + lastDir, Vector3.yAxis)
			
			if lineTele and lineTele.Parent then
				local look = CFrame.lookAt(pos, pos + lastDir)
				local yDrop = 0
				pcall(function()
					if root and root:IsA("BasePart") then
						yDrop = math.max(0, (root.Size.Y * 0.5) - 0.1)
					else
						yDrop = 2.0
					end
				end)
				lineTele.CFrame = look * CFrame.new(0, -yDrop, -DASH_RANGE/2)
			end
			task.wait(0.05)
		end
	end
	
	pauseAwareWait(0.3)
	
	setFrozen(false)
	if lineTele and lineTele.Parent then lineTele:Destroy() end
	releaseWindupPose()
	
	if not running or isPaused() then return end
	
	-- Execute dash
	local lockedDir = lastDir
	humanoid.AutoRotate = false
	if root and root.Anchored then root.Anchored = false end
	pushActionLock()
	
	local maxPlanned = DASH_RANGE
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { enemyModel }
	local ray = workspace:Raycast(root.Position, lockedDir * maxPlanned, rayParams)
	local obstacleDist = ray and (ray.Position - root.Position).Magnitude - 2 or maxPlanned
	local dashDist = math.max(0, math.min(maxPlanned, obstacleDist))
	local dest = root.Position + lockedDir * dashDist
	
	-- Clamp to map
	local offsetFromSpawn = dest - SPAWN_POS
	if offsetFromSpawn.Magnitude > MAX_MAP_RADIUS then
		local limitedDir = offsetFromSpawn.Unit
		dest = SPAWN_POS + limitedDir * MAX_MAP_RADIUS
		dashDist = (dest - root.Position).Magnitude
	end
	
	-- Ground validation
	local function groundHit(testPos: Vector3)
		local downParams = RaycastParams.new()
		downParams.FilterType = Enum.RaycastFilterType.Exclude
		downParams.FilterDescendantsInstances = { enemyModel }
		return workspace:Raycast(testPos + Vector3.new(0,2,0), Vector3.new(0,-150,0), downParams)
	end
	
	local hit = groundHit(dest)
	if hit then
		dest = Vector3.new(dest.X, hit.Position.Y, dest.Z)
	end
	
	-- Execute dash
	local dashAnim = playAnim("Dash", 0.05, 1.0, 1.2)
	local dashSpeed = 130
	local dashDuration = dashDist / dashSpeed
	local dashStart = os.clock()
	local dashStartPos = root.Position
	
	local damagedPlayers = {}
	
	while running and (os.clock() - dashStart) < dashDuration do
		if isPaused() then
			task.wait(0.05)
		else
			local elapsed = os.clock() - dashStart
			local alpha = math.min(1, elapsed / dashDuration)
			local currentPos = dashStartPos:Lerp(dest, alpha)
			root.CFrame = CFrame.new(currentPos, currentPos + lockedDir)
			
			-- Path damage
			for _, plr in ipairs(Players:GetPlayers()) do
				if not damagedPlayers[plr] then
					local char = plr.Character
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					local r = char and char:FindFirstChild("HumanoidRootPart")
					if hum and r and hum.Health > 0 then
						local dist = (r.Position - currentPos).Magnitude
						if dist <= DASH_PATH_RADIUS then
							local waveMult = enemyModel:GetAttribute("DamageWaveMultiplier") or 1
							Damage.Apply(hum, DASH_PATH_DAMAGE * waveMult)
							damagedPlayers[plr] = true
						end
					end
				end
			end
			
			task.wait(0.03)
		end
	end
	
	root.CFrame = CFrame.new(dest, dest + lockedDir)
	
	-- Finish
	if dashAnim then dashAnim:Stop(0.1) end
	local finishAnim = playAnim("Dash_finish", 0.05, 1.0, 1.0)
	
	task.delay(0.2, function()
		if running then
			areaDamage(root.Position, DASH_AOE_RADIUS, DASH_DAMAGE)
		end
	end)
	
	if finishAnim then
		pauseAwareWait(finishAnim.Length or 0.6)
	else
		pauseAwareWait(0.6)
	end
	
	humanoid.AutoRotate = true
	humanoid.WalkSpeed = MOVE_SPEED
	popActionLock()
	lastDash = os.clock()
end

-- ========================================
-- CERO BEAM (like Kamehameha but slower rotation)
-- ========================================
local lastCero = 0

local function tryCeroBeam(now)
	if now - lastCero < CERO_INTERVAL then return end
	if now - SPAWN_TIME < INITIAL_ATTACK_COOLDOWN then return end
	local targetRoot, dist = getNearestPlayer(CERO_RANGE)
	if not targetRoot then return end
	
	print("[Ulquiorra] CERO STARTED")
	
	setFrozen(true)
	
	-- Charge phase (cero_charge animation)
	local chargeAnim = playAnim("cero_charge", 0.1, 1.0, 1.0)
	
	-- Wait for animation to reach last frame, then freeze it
	if chargeAnim then
		local animLength = chargeAnim.Length
		if animLength > 0 then
			-- Wait for animation to almost finish
			pauseAwareWait(math.max(0, animLength - 0.1))
			-- Freeze on last frame
			chargeAnim:AdjustSpeed(0)
		end
	end
	
	-- Clone charge model
	local attacksFolder = ReplicatedStorage:FindFirstChild("Enemys") and ReplicatedStorage.Enemys:FindFirstChild("Attacks")
	local chargeModel = attacksFolder and attacksFolder:FindFirstChild("Cero_charge")
	local chargeInstance = nil
	local chargeFollowConn = nil
	
	if chargeModel then
		chargeInstance = chargeModel:Clone()
		chargeInstance.Name = "UlquiorraCeroCharge"
		chargeInstance.Parent = workspace
		
		-- Make non-blocking
		for _, d in ipairs(chargeInstance:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d.Anchored = true
			end
		end
		
		-- Follow Ulquiorra during charge and rotate toward player
		local FORWARD_OFFSET = -4
		chargeFollowConn = RunService.Heartbeat:Connect(function()
			if not chargeInstance or not chargeInstance.Parent or not root or not root.Parent then
				if chargeFollowConn then chargeFollowConn:Disconnect() end
				return
			end
			if isPaused() then return end
			
			-- ALWAYS rotate toward player (ignore frozen/locked state)
			local tr = getNearestPlayer(CERO_RANGE)
			if tr then
				local targetDir = (tr.Position - root.Position) * Vector3.new(1, 0, 1)
				if targetDir.Magnitude > 0.001 then
					targetDir = targetDir.Unit
					-- Instant rotation during charge
					root.CFrame = CFrame.new(root.Position, root.Position + targetDir)
				end
			end
			
			local cf = root.CFrame * CFrame.new(0, 0, FORWARD_OFFSET) * CFrame.Angles(math.rad(90), 0, 0)
			if chargeInstance:IsA("Model") then
				chargeInstance:PivotTo(cf)
			elseif chargeInstance:IsA("BasePart") then
				chargeInstance.CFrame = cf
			end
		end)
	end
	
	-- Wait remaining charge time (since we already waited for animation)
	local remainingCharge = CERO_CHARGE - (chargeAnim and chargeAnim.Length or 0)
	if remainingCharge > 0 then
		pauseAwareWait(remainingCharge)
	end
	
	if chargeFollowConn then chargeFollowConn:Disconnect() end
	
	if chargeAnim then chargeAnim:Stop(0.1) end
	if chargeInstance then chargeInstance:Destroy() end
	
	if not running or isPaused() then
		setFrozen(false)
		return
	end
	
	-- Fire Cero beam (position Cero1 at origin and Cero2 at end point)
	local ceroAnim = playAnim("cero", 0.05, 1.0, 1.0)
	
	local cero1Model = attacksFolder and attacksFolder:FindFirstChild("Cero1")
	local cero2Model = attacksFolder and attacksFolder:FindFirstChild("Cero2")
	
	local cero1Instance, cero2Instance = nil, nil
	local cero1FollowConn, cero2FollowConn = nil, nil
	
	if cero1Model and cero2Model then
		-- Clone Cero1 (2 studs in front)
		cero1Instance = cero1Model:Clone()
		cero1Instance.Name = "UlquiorraCero1"
		cero1Instance.Parent = workspace
		
		-- Clone Cero2 (200 studs in front)
		cero2Instance = cero2Model:Clone()
		cero2Instance.Name = "UlquiorraCero2"
		cero2Instance.Parent = workspace
		
		-- Make all parts non-blocking
		for _, d in ipairs(cero1Instance:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d.Anchored = true
			end
		end
		for _, d in ipairs(cero2Instance:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d.Anchored = true
			end
		end
		
		-- Configure Beams to connect Cero1 and Cero2
		local att1 = cero1Instance:FindFirstChild("Attachment1", true)
		local att2 = cero2Instance:FindFirstChild("Attachment2", true)
		
		if att1 and att2 then
			-- Configure all beams in beam1 folder
			for _, beam in ipairs(cero1Instance:GetDescendants()) do
				if beam:IsA("Beam") and beam.Parent and beam.Parent.Name == "beam1" then
					beam.Attachment0 = att1
					beam.Attachment1 = att2
				end
			end
			
			-- Configure beam2
			for _, beam in ipairs(cero2Instance:GetDescendants()) do
				if beam:IsA("Beam") and beam.Name == "beam2" then
					beam.Attachment0 = att1
					beam.Attachment1 = att2
				end
			end
		end
		
		-- Cero1: 2 studs in front
		cero1FollowConn = RunService.Heartbeat:Connect(function()
			if not cero1Instance or not cero1Instance.Parent or not root or not root.Parent then
				if cero1FollowConn then cero1FollowConn:Disconnect() end
				return
			end
			if isPaused() then return end
			
			local cf = root.CFrame * CFrame.new(0, 0, -2) * CFrame.Angles(math.rad(90), 0, 0)
			if cero1Instance:IsA("Model") then
				cero1Instance:PivotTo(cf)
			elseif cero1Instance:IsA("BasePart") then
				cero1Instance.CFrame = cf
			end
		end)
		
		-- Cero2: 200 studs in front
		cero2FollowConn = RunService.Heartbeat:Connect(function()
			if not cero2Instance or not cero2Instance.Parent or not root or not root.Parent then
				if cero2FollowConn then cero2FollowConn:Disconnect() end
				return
			end
			if isPaused() then return end
			
			local cf = root.CFrame * CFrame.new(0, 0, -200) * CFrame.Angles(math.rad(90), 0, 0)
			if cero2Instance:IsA("Model") then
				cero2Instance:PivotTo(cf)
			elseif cero2Instance:IsA("BasePart") then
				cero2Instance.CFrame = cf
			end
		end)
	end
	
	-- Beam rotation (moderate speed for tracking)
	local ROTATION_SPEED = 0.15
	local beamStart = os.clock()
	local BEAM_LENGTH = 200
	
	while running and (os.clock() - beamStart) < CERO_DURATION do
		if isPaused() then
			task.wait(0.05)
		else
			-- ALWAYS rotate toward player slowly (ignore frozen/locked state)
			local tr = getNearestPlayer(CERO_RANGE)
			if tr then
				local targetDir = (tr.Position - root.Position) * Vector3.new(1, 0, 1)
				if targetDir.Magnitude > 0.001 then
					targetDir = targetDir.Unit
					local currentDir = (root.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
					local newDir = currentDir:Lerp(targetDir, ROTATION_SPEED)
					root.CFrame = CFrame.new(root.Position, root.Position + newDir)
				end
			end
			
			-- Damage: straight line 200 studs in front
			local damagedThisTick = {}
			local beamDir = (root.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
			
			for _, plr in ipairs(Players:GetPlayers()) do
				local char = plr.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local r = char and char:FindFirstChild("HumanoidRootPart")
				if hum and r and hum.Health > 0 and not damagedThisTick[hum] then
					-- TOP-DOWN: Only check XZ plane
					local ulqPos2D = Vector3.new(root.Position.X, 0, root.Position.Z)
					local playerPos2D = Vector3.new(r.Position.X, 0, r.Position.Z)
					local toPlayer = playerPos2D - ulqPos2D
					local forwardDist = toPlayer:Dot(beamDir) -- Distance along beam direction
					
					if forwardDist > 0 and forwardDist <= BEAM_LENGTH then
						-- Player is within beam length, check lateral distance
						local closestPoint = ulqPos2D + beamDir * forwardDist
						local lateralDist = (playerPos2D - closestPoint).Magnitude
						
						if lateralDist <= 8 then -- 8 studs beam width
							local waveMult = enemyModel:GetAttribute("DamageWaveMultiplier") or 1
							Damage.Apply(hum, CERO_DAMAGE_TICK * waveMult)
							damagedThisTick[hum] = true
						end
					end
				end
			end
			
			task.wait(CERO_TICK_INTERVAL)
		end
	end
	
	-- Cleanup
	if cero1FollowConn then cero1FollowConn:Disconnect() end
	if cero2FollowConn then cero2FollowConn:Disconnect() end
	if ceroAnim then ceroAnim:Stop(0.1) end
	if cero1Instance then cero1Instance:Destroy() end
	if cero2Instance then cero2Instance:Destroy() end
	
	setFrozen(false)
	humanoid.AutoRotate = true
	humanoid.WalkSpeed = MOVE_SPEED
	lastCero = os.clock()
end

-- ========================================
-- TRIDENT RAIN
-- ========================================
local lastTrident = 0

local function tryTridentRain(now)
	if now - lastTrident < TRIDENT_INTERVAL then return end
	if now - SPAWN_TIME < INITIAL_ATTACK_COOLDOWN then return end
	
	print("[Ulquiorra] TRIDENT STARTED")
	
	setFrozen(true)
	
	-- Play trident animation
	local tridentAnim = playAnim("Trident", 0.1, 1.0, 1.0)
	
	-- Get spawn area bounds from WaveConfig (same as enemy spawn area)
	local areaMin = Vector3.new(-66.95, 10, -40.674)
	local areaMax = Vector3.new(13.05, 10, 40.326)
	local groundY = 10.5
	
	-- Spawn tridents in sky
	local attacksFolder = ReplicatedStorage:FindFirstChild("Enemys") and ReplicatedStorage.Enemys:FindFirstChild("Attacks")
	local tridentModel = attacksFolder and attacksFolder:FindFirstChild("Trident")
	
	local tridentData = {}
	
	for i = 1, TRIDENT_COUNT do
		-- Random position in combat area (same as enemy spawn area)
		local randomX = math.random() * (areaMax.X - areaMin.X) + areaMin.X
		local randomZ = math.random() * (areaMax.Z - areaMin.Z) + areaMin.Z
		
		local skyPos = Vector3.new(randomX, groundY + TRIDENT_HEIGHT, randomZ)
		local groundPos = Vector3.new(randomX, groundY, randomZ)
		
		-- Spawn trident in sky
		local trident = nil
		if tridentModel then
			trident = tridentModel:Clone()
			trident.Name = "UlquiorraTrident_" .. i
			trident.Parent = workspace
			
			for _, d in ipairs(trident:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CanCollide = false
					d.CanQuery = false
					d.Anchored = true
				end
			end
			
			-- Scale up trident model
			if trident:IsA("Model") then
				local scaleFactor = 2.5
				for _, part in ipairs(trident:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Size = part.Size * scaleFactor
					end
				end
				trident:PivotTo(CFrame.new(skyPos) * CFrame.Angles(0, 0, math.rad(180))) -- Point down
			elseif trident:IsA("BasePart") then
				trident.Size = trident.Size * 2.5
				trident.CFrame = CFrame.new(skyPos) * CFrame.Angles(0, 0, math.rad(180))
			end
		end
		
		-- Create telegraph circle (brighter green for better visibility)
		local telegraph = createCircleTelegraph(groundPos, TRIDENT_AOE_RADIUS, TRIDENT_FALL_DELAY + 0.5, Color3.fromRGB(0, 255, 0))
		
		table.insert(tridentData, {
			trident = trident,
			skyPos = skyPos,
			groundPos = groundPos,
			telegraph = telegraph
		})
	end
	
	-- Wait for fall delay
	pauseAwareWait(TRIDENT_FALL_DELAY)
	
	-- Make tridents fall and deal damage
	for _, data in ipairs(tridentData) do
		task.spawn(function()
			if data.trident and data.trident.Parent then
				-- Animate fall
				local fallDuration = 0.5
				local fallStart = os.clock()
				
				while (os.clock() - fallStart) < fallDuration do
					if isPaused() then
						task.wait(0.05)
					else
						local elapsed = os.clock() - fallStart
						local alpha = math.min(1, elapsed / fallDuration)
						local currentPos = data.skyPos:Lerp(data.groundPos, alpha)
						
						if data.trident:IsA("Model") then
							data.trident:PivotTo(CFrame.new(currentPos) * CFrame.Angles(0, 0, math.rad(180)))
						elseif data.trident:IsA("BasePart") then
							data.trident.CFrame = CFrame.new(currentPos) * CFrame.Angles(0, 0, math.rad(180))
						end
						
						task.wait(0.03)
					end
				end
				
				-- Deal damage on impact
				areaDamage(data.groundPos, TRIDENT_AOE_RADIUS, TRIDENT_DAMAGE)
				
				-- Create green/black explosion effect
				local explosion = Instance.new("Explosion")
				explosion.Position = data.groundPos
				explosion.BlastRadius = TRIDENT_AOE_RADIUS
				explosion.BlastPressure = 0 -- No knockback
				explosion.DestroyJointRadiusPercent = 0 -- Don't break joints
				explosion.ExplosionType = Enum.ExplosionType.NoCraters
				explosion.Parent = workspace
				
				-- Create green particle burst
				local greenPart = Instance.new("Part")
				greenPart.Size = Vector3.new(1, 1, 1)
				greenPart.Position = data.groundPos
				greenPart.Anchored = true
				greenPart.CanCollide = false
				greenPart.CanQuery = false
				greenPart.Transparency = 1
				greenPart.Parent = workspace
				
				local greenParticles = Instance.new("ParticleEmitter")
				greenParticles.Color = ColorSequence.new(Color3.fromRGB(0, 255, 0))
				greenParticles.Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 3),
					NumberSequenceKeypoint.new(1, 0)
				})
				greenParticles.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(1, 1)
				})
				greenParticles.Lifetime = NumberRange.new(0.5, 1.0)
				greenParticles.Rate = 200
				greenParticles.Speed = NumberRange.new(20, 30)
				greenParticles.SpreadAngle = Vector2.new(180, 180)
				greenParticles.Parent = greenPart
				greenParticles:Emit(50)
				
				-- Create black smoke burst
				local blackParticles = Instance.new("ParticleEmitter")
				blackParticles.Color = ColorSequence.new(Color3.fromRGB(10, 10, 10))
				blackParticles.Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 4),
					NumberSequenceKeypoint.new(1, 8)
				})
				blackParticles.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.3),
					NumberSequenceKeypoint.new(1, 1)
				})
				blackParticles.Lifetime = NumberRange.new(0.8, 1.5)
				blackParticles.Rate = 100
				blackParticles.Speed = NumberRange.new(10, 15)
				blackParticles.SpreadAngle = Vector2.new(180, 180)
				blackParticles.Parent = greenPart
				blackParticles:Emit(30)
				
				game:GetService("Debris"):AddItem(greenPart, 2)
				
				-- Remove trident
				task.wait(0.3)
				if data.trident and data.trident.Parent then
					data.trident:Destroy()
				end
			end
		end)
	end
	
	-- Wait for animation to finish
	if tridentAnim then
		pauseAwareWait(tridentAnim.Length or 2.0)
	else
		pauseAwareWait(2.0)
	end
	
	setFrozen(false)
	humanoid.AutoRotate = true
	humanoid.WalkSpeed = MOVE_SPEED
	lastTrident = os.clock()
end

-- ========================================
-- 1000 CUTS (rapid cone damage)
-- ========================================
local lastCuts = 0

local function try1000Cuts(now)
	if now - lastCuts < CUTS_INTERVAL then return end
	if now - SPAWN_TIME < INITIAL_ATTACK_COOLDOWN then return end
	local targetRoot, dist = getNearestPlayer(100)
	if not targetRoot then return end
	
	print("[Ulquiorra] 1000 CUTS STARTED")
	
	-- Play 1000_cuts animation
	local cutsAnim = playAnim("1000_cuts", 0.1, 1.0, 1.0)
	
	-- Boost movement speed
	local originalSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = MOVE_SPEED + CUTS_SPEED_BOOST
	humanoid.AutoRotate = true -- Allow rotation during cuts
	
	-- Rapid cone damage loop
	local cutsStart = os.clock()
	local nextTick = cutsStart
	
	while running and (os.clock() - cutsStart) < CUTS_DURATION do
		if isPaused() then
			task.wait(0.05)
		else
			local currentTime = os.clock()
			
			-- Keep moving toward target during 1000 Cuts
			local currentTarget, currentDist = getNearestPlayer(500)
			if currentTarget then
				humanoid:MoveTo(currentTarget.Position)
			end
			
			if currentTime >= nextTick then
				nextTick = currentTime + CUTS_TICK_RATE
				
				-- Deal cone damage
				local lookDir = root.CFrame.LookVector
				local halfAngle = math.rad(CUTS_CONE_ANGLE / 2)
				
				for _, plr in ipairs(Players:GetPlayers()) do
					local char = plr.Character
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					local r = char and char:FindFirstChild("HumanoidRootPart")
					if hum and r and hum.Health > 0 then
						-- TOP-DOWN: Ignore Y when calculating cone direction
						local toPlayer = (r.Position - root.Position) * Vector3.new(1, 0, 1)
						local dist = toPlayer.Magnitude
						
						if dist <= CUTS_CONE_RANGE then
							local dirToPlayer = toPlayer.Unit
							local angle = math.acos(lookDir:Dot(dirToPlayer))
							
							if angle <= halfAngle then
								-- Player is in cone
								local waveMult = enemyModel:GetAttribute("DamageWaveMultiplier") or 1
								Damage.Apply(hum, CUTS_DAMAGE_TICK * waveMult)
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
	
	if cutsAnim then cutsAnim:Stop(0.1) end
	
	lastCuts = os.clock()
end

-- ========================================
-- MAIN AI LOOP
-- ========================================
task.spawn(function()
	pauseAwareWait(1.0)
	
	print("[Ulquiorra] AI loop starting - WalkSpeed:", humanoid.WalkSpeed, "Frozen:", isFrozen())
	
	while running do
		if isPaused() then
			task.wait(0.1)
		else
			local now = os.clock()
			local targetRoot, dist = getNearestPlayer(500)
			
			if targetRoot then
				print("[Ulquiorra] Target found! Dist:", math.floor(dist), "Frozen:", isFrozen())
				-- Priority: Trident > Cero > Cuts > Dash
				if now - lastTrident >= TRIDENT_INTERVAL then
					print("[Ulquiorra] Trying TRIDENT")
					tryTridentRain(now)
				elseif now - lastCero >= CERO_INTERVAL and dist <= CERO_RANGE then
					print("[Ulquiorra] Trying CERO")
					tryCeroBeam(now)
				elseif now - lastCuts >= CUTS_INTERVAL and dist <= 50 then
					print("[Ulquiorra] Trying 1000 CUTS")
					try1000Cuts(now)
				elseif now - lastDash >= DASH_INTERVAL and dist > 15 and dist <= 60 then
					print("[Ulquiorra] Trying DASH")
					tryDashSlash(now)
				elseif not isFrozen() then
					-- Always move toward player when not attacking (for 1000 Cuts positioning)
					print("[Ulquiorra] Moving to player - Current WalkSpeed:", humanoid.WalkSpeed)
					humanoid:MoveTo(targetRoot.Position)
				else
					print("[Ulquiorra] Cannot move - Frozen:", isFrozen())
				end
			end
		end
		
		task.wait(0.15)
	end
end)

print("[Ulquiorra] AI initialized - Las Noches awaits!")
