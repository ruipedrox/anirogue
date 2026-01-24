-- Kenpachi AI
-- Boss bleach lvl 1
-- Abilities:
-- 1) Normal Attack: melee slash when in range
-- 2) Dash Slash: Telegraph (Dash_begin), rapid dash (Dash), finish strike (Dash_finish)
-- 3) Teleport Strike: Charge animation (Teleport_charge), teleport to player, damage on arrival

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
local MOVE_SPEED = (STATS and STATS.MoveSpeed) or 14
local ATTACK_RANGE = (STATS and STATS.AttackRange) or 6
local ATTACK_COOLDOWN = (STATS and STATS.AttackCooldown) or 1.8
local ATTACK_DAMAGE = (STATS and STATS.AttackDamage) or 85

local DASH_INTERVAL = (STATS and STATS.DashInterval) or 12
local DASH_TELEGRAPH = (STATS and STATS.DashTelegraph) or 1.5
local DASH_RANGE = (STATS and STATS.DashRange) or 45
local DASH_DAMAGE = (STATS and STATS.DashDamage) or 150
local DASH_AOE_RADIUS = (STATS and STATS.DashAoERadius) or 12
local DASH_PATH_DAMAGE = (STATS and STATS.DashPathTickDamage) or 65
local DASH_PATH_RADIUS = (STATS and STATS.DashPathTickRadius) or 6

local TELEPORT_INTERVAL = (STATS and STATS.TeleportInterval) or 18
local TELEPORT_CHARGE = (STATS and STATS.TeleportCharge) or 2.0
local TELEPORT_RANGE = (STATS and STATS.TeleportRange) or 80
local TELEPORT_DAMAGE = (STATS and STATS.TeleportDamage) or 200
local TELEPORT_AOE_RADIUS = (STATS and STATS.TeleportAoERadius) or 15

local INITIAL_ATTACK_COOLDOWN = 3
local SPAWN_POS = root.Position
local MAX_MAP_RADIUS = 600

-- Set spawn time AFTER humanoid is loaded and ready
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
	-- Não ancorar para permitir animações moverem o corpo
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

-- Telegraph generator (linha retangular)
local function createLineTelegraph(startPos: Vector3, dir: Vector3, length: number, width: number, duration: number, color: Color3)
	-- TOP-DOWN: Ignore Y axis (height) for aiming
	dir = dir * Vector3.new(1, 0, 1)
	dir = (dir.Magnitude > 1e-3) and dir.Unit or Vector3.new(0,0,-1)
	local part = Instance.new("Part")
	part.Name = "KenpachiDashTelegraph"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = color or Color3.fromRGB(255, 200, 50)
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

-- Telegraph circular (para teleport)
local function createCircleTelegraph(position: Vector3, radius: number, duration: number, color: Color3)
	local part = Instance.new("Part")
	part.Name = "KenpachiTeleportTelegraph"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Neon
	part.Color = color or Color3.fromRGB(255, 0, 0)
	part.Transparency = 0.55
	local height = 0.3
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
				part.Transparency = 0.55 + math.sin(alpha*math.pi)*0.2
				task.wait(dt)
				t += dt
			end
		end
		if part and part.Parent then part:Destroy() end
	end)
	return part
end

-- ========================================
-- NORMAL ATTACK (melee like Zabuza)
-- ========================================
local lastNormalAttack = 0
local isAttacking = false

local function tryNormalAttack(targetRoot)
	local now = os.clock()
	if now - lastNormalAttack < ATTACK_COOLDOWN then return false end
	if now - SPAWN_TIME < INITIAL_ATTACK_COOLDOWN then return false end
	if isAttacking then return false end
	
	local dist = (targetRoot.Position - root.Position).Magnitude
	if dist > ATTACK_RANGE then return false end
	
	isAttacking = true
	lastNormalAttack = now
	
	-- Stop movement
	humanoid.WalkSpeed = 0
	
	-- Play attack animation
	local attackAnim = playAnim("Normal_attack", 0.1, 1.0, 1.0)
	
	-- Deal damage after 0.3s
	task.delay(0.3, function()
		if not running then return end
		local currentDist = (targetRoot.Position - root.Position).Magnitude
		if currentDist <= ATTACK_RANGE + 2 then
			local waveMult = enemyModel:GetAttribute("DamageWaveMultiplier") or 1
			local dmg = ATTACK_DAMAGE * waveMult
			local char = targetRoot.Parent
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				Damage.Apply(hum, dmg)
			end
		end
	end)
	
	-- Wait for animation to complete
	if attackAnim then
		pauseAwareWait(attackAnim.Length or 0.8)
	else
		pauseAwareWait(0.8)
	end
	
	-- Resume movement
	if not isFrozen() then
		humanoid.WalkSpeed = MOVE_SPEED
	end
	isAttacking = false
	
	return true
end

-- ========================================
-- DASH SLASH (like Sasuke's Chidori dash)
-- ========================================
local lastDash = 0

local function tryDashSlash(now)
	if now - lastDash < DASH_INTERVAL then return end
	if now - SPAWN_TIME < INITIAL_ATTACK_COOLDOWN then return end
	local targetRoot, dist = getNearestPlayer(500)
	if not targetRoot then return end
	
	-- Helper to get flat direction (TOP-DOWN: ignore Y)
	local function flatDirTo(pos: Vector3)
		local from = root.Position
		-- Only use X and Z, ignore Y
		local to = Vector3.new(pos.X, from.Y, pos.Z)
		local v = (to - from)
		if v.Magnitude < 1e-3 then return Vector3.new(0,0,-1) end
		return v.Unit
	end
	
	local direction = flatDirTo(targetRoot.Position)
	
	-- Telegraph windup (Dash_begin animation)
	local windup = playAnim("Dash_begin", 0.1, 1.0, 1.0)
	local releaseWindupPose = holdLastKeyframePose(windup)
	setFrozen(true)
	
	local corridorWidth = math.max(4, DASH_PATH_RADIUS * 2)
	local lineTele = createLineTelegraph(root.Position, direction, DASH_RANGE, corridorWidth, DASH_TELEGRAPH + 10, Color3.fromRGB(255, 200, 50))
	
	-- During windup: continuously rotate toward player
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
			
			-- Update telegraph
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
	
	-- Pre-dash hold
	local PRE_DASH_HOLD = 0.3
	pauseAwareWait(PRE_DASH_HOLD)
	
	-- Release movement
	setFrozen(false)
	if lineTele and lineTele.Parent then lineTele:Destroy() end
	releaseWindupPose()
	
	if not running or isPaused() then return end
	
	-- Lock direction and execute dash
	local lockedDir = lastDir
	humanoid.AutoRotate = false
	if root and root.Anchored then root.Anchored = false end
	pushActionLock()
	
	-- Calculate dash distance with raycast
	local maxPlanned = DASH_RANGE
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { enemyModel }
	local ray = workspace:Raycast(root.Position, lockedDir * maxPlanned, rayParams)
	local obstacleDist = ray and (ray.Position - root.Position).Magnitude - 2 or maxPlanned
	local dashDist = math.max(0, math.min(maxPlanned, obstacleDist))
	local dest = root.Position + lockedDir * dashDist
	
	-- Clamp to map radius
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
	
	-- Execute dash with Dash animation
	local dashAnim = playAnim("Dash", 0.05, 1.0, 1.2)
	local dashSpeed = 120
	local dashDuration = dashDist / dashSpeed
	local dashStart = os.clock()
	local dashStartPos = root.Position
	
	-- Path damage tracking
	local damagedPlayers = {}
	
	while running and (os.clock() - dashStart) < dashDuration do
		if isPaused() then
			task.wait(0.05)
		else
			local elapsed = os.clock() - dashStart
			local alpha = math.min(1, elapsed / dashDuration)
			local currentPos = dashStartPos:Lerp(dest, alpha)
			root.CFrame = CFrame.new(currentPos, currentPos + lockedDir)
			
			-- Apply path damage
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
	
	-- Dash finish animation
	if dashAnim then dashAnim:Stop(0.1) end
	local finishAnim = playAnim("Dash_finish", 0.05, 1.0, 1.0)
	
	-- Final AoE damage
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
-- TELEPORT STRIKE
-- ========================================
local lastTeleport = 0

local function tryTeleportStrike(now)
	if now - lastTeleport < TELEPORT_INTERVAL then return end
	if now - SPAWN_TIME < INITIAL_ATTACK_COOLDOWN then return end
	local targetRoot, dist = getNearestPlayer(TELEPORT_RANGE)
	if not targetRoot then return end
	
	pushActionLock()
	setFrozen(true)
	
	-- Charge animation (Teleport_charge)
	local chargeAnim = playAnim("Teleport_charge", 0.1, 1.0, 1.0)
	
	-- TOP-DOWN: Telegraph at target (ignore Y difference)
	local targetPos = Vector3.new(targetRoot.Position.X, root.Position.Y, targetRoot.Position.Z)
	local telegraph = createCircleTelegraph(targetPos, TELEPORT_AOE_RADIUS, TELEPORT_CHARGE + 1, Color3.fromRGB(255, 0, 0))
	
	-- Charge duration
	pauseAwareWait(TELEPORT_CHARGE)
	
	if not running or isPaused() then
		if telegraph and telegraph.Parent then telegraph:Destroy() end
		if chargeAnim then chargeAnim:Stop(0.1) end
		setFrozen(false)
		popActionLock()
		return
	end
	
	-- Get updated target position
	local finalTarget, finalDist = getNearestPlayer(TELEPORT_RANGE)
	if finalTarget then
		targetPos = finalTarget.Position
	end
	
	-- Teleport effect (pode adicionar particles aqui)
	if chargeAnim then chargeAnim:Stop(0.05) end
	
	-- Instant teleport
	root.CFrame = CFrame.new(targetPos)
	
	-- Teleport animation on arrival
	local teleportAnim = playAnim("Teleport", 0.05, 1.0, 1.0)
	
	-- Massive damage on arrival
	task.delay(0.1, function()
		if running then
			areaDamage(root.Position, TELEPORT_AOE_RADIUS, TELEPORT_DAMAGE)
		end
	end)
	
	if telegraph and telegraph.Parent then telegraph:Destroy() end
	
	if teleportAnim then
		pauseAwareWait(teleportAnim.Length or 0.8)
	else
		pauseAwareWait(0.8)
	end
	
	setFrozen(false)
	humanoid.WalkSpeed = MOVE_SPEED
	humanoid.AutoRotate = true
	popActionLock()
	lastTeleport = os.clock()
end

-- ========================================
-- MAIN AI LOOP
-- ========================================
task.spawn(function()
	pauseAwareWait(0.5)
	
	while running do
		if isPaused() then
			task.wait(0.1)
		else
			local now = os.clock()
			local targetRoot, dist = getNearestPlayer(500)
			
			if targetRoot then
				print(string.format("[Kenpachi] Target found! Dist=%.1f Locked=%s Attacking=%s", dist, tostring(isActionLocked()), tostring(isAttacking)))
				
				-- Priority: Teleport > Dash > Normal Attack
				if now - lastTeleport >= TELEPORT_INTERVAL and dist <= TELEPORT_RANGE and not isActionLocked() then
					print("[Kenpachi] Trying TELEPORT")
					tryTeleportStrike(now)
				elseif now - lastDash >= DASH_INTERVAL and dist > ATTACK_RANGE and dist <= 60 and not isActionLocked() then
					print("[Kenpachi] Trying DASH")
					tryDashSlash(now)
				elseif not isActionLocked() and not isAttacking then
					-- Try normal attack if in range
					if dist <= ATTACK_RANGE then
						print("[Kenpachi] Trying NORMAL ATTACK")
						tryNormalAttack(targetRoot)
					else
						-- Move toward player
						humanoid:MoveTo(targetRoot.Position)
					end
				end
			else
				print("[Kenpachi] No target found!")
			end
			
			task.wait(0.1)
		end
	end
end)

print("[Kenpachi] AI initialized - Ready for battle!")
