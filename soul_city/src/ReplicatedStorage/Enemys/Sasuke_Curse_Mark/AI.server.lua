-- Sasuke Curse Mark AI
-- Copiado do Zabuza AI - mesma estrutura de dash
-- Abilities:
-- 1) Chidori Dash: Telegraph, rapid dash com lightning particles ativas

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local enemyModel = script.Parent
local humanoid = enemyModel:FindFirstChildOfClass("Humanoid") or enemyModel:WaitForChild("Humanoid", 2)
local root = enemyModel:FindFirstChild("HumanoidRootPart") or (enemyModel:WaitForChild("HumanoidRootPart", 2))
if not humanoid or not root then return end

-- Set PrimaryPart so player can target this enemy correctly
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

-- Extract stat values with defaults
local BASE_DAMAGE = (STATS and STATS.Damage) or 65
local MOVE_SPEED = (STATS and STATS.MoveSpeed) or 20

-- Chidori Dash constants
local CHIDORI_INTERVAL = 20
local CHIDORI_TELEGRAPH = 2.0
local CHIDORI_RANGE = 70
local CHIDORI_DAMAGE = BASE_DAMAGE * 2.5
local CHIDORI_PATH_DAMAGE = math.floor(BASE_DAMAGE * 1.0)
local CHIDORI_PATH_RADIUS = 5
local CHIDORI_AOE_RADIUS = 10

-- Wing Attack constants
local WING_INTERVAL = 6
local WING_WINDUP = 1.2
local WING_RANGE = 25
local WING_DAMAGE = BASE_DAMAGE * 2.0
local WING_CONE_ANGLE = 180
local WING_KNOCKBACK = 60

-- Fire Ball constants
local FIREBALL_INTERVAL = 15
local FIREBALL_RANGE = 60
local FIREBALL_DAMAGE = BASE_DAMAGE * 1.8
local FIREBALL_SPEED = 50
local FIREBALL_EXPLOSION_RADIUS = 8
local FLY_HEIGHT = 12
local FLY_DURATION = 1.5

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
	local folder = enemyModel:FindFirstChild("Animations")
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

-- Pré-carregar animações
task.spawn(function()
	task.wait(0.5)
	loadAnimationByName("Wind_up")
	loadAnimationByName("Dash")
	loadAnimationByName("Dash_Finish")
	loadAnimationByName("wing_attack")
	loadAnimationByName("Fly")
	loadAnimationByName("Fire_Ball")
	print("[Sasuke] Animações pré-carregadas")
end)

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
	-- NÃO ancorar o root para permitir animação mover o corpo
	-- if root and root:IsA("BasePart") then
	-- 	root.Anchored = shouldFreeze
	-- end
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

-- Telegraph generator (corredor retangular alinhado com a direção)
local function createLineTelegraph(startPos: Vector3, dir: Vector3, length: number, width: number, duration: number, color: Color3)
	dir = (dir.Magnitude > 1e-3) and dir.Unit or Vector3.new(0,0,-1)
	local part = Instance.new("Part")
	part.Name = "SasukeDashCorridor"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = color or Color3.fromRGB(255,70,70)
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

-- Encontrar lightning particles e lights no modelo Chidori
local chidoriFolder = enemyModel:FindFirstChild("Chidori")
local lightningParticles = {}
local lightningLights = {}

if chidoriFolder then
	for _, obj in ipairs(chidoriFolder:GetDescendants()) do
		if obj:IsA("ParticleEmitter") then
			table.insert(lightningParticles, obj)
			obj.Enabled = false
		elseif obj:IsA("PointLight") then
			table.insert(lightningLights, obj)
			obj.Enabled = false
		end
	end
end

print("[Sasuke] Encontradas " .. #lightningParticles .. " particles e " .. #lightningLights .. " lights")

-- ========================================
-- CHIDORI DASH (baseado no Dash do Zabuza)
-- ========================================
local lastChidori = 0

local function tryChidoriDash(now)
	if now - lastChidori < CHIDORI_INTERVAL then return end
	if now - SPAWN_TIME < INITIAL_ATTACK_COOLDOWN then return end
	local targetRoot, dist = getNearestPlayer(500)
	if not targetRoot then return end

	-- Evitar dash imediato ao spawn enquanto ainda está a cair
	local function isAirborne(part: BasePart): boolean
		local downParams = RaycastParams.new()
		downParams.FilterType = Enum.RaycastFilterType.Exclude
		downParams.FilterDescendantsInstances = { enemyModel }
		local ray = workspace:Raycast(part.Position, Vector3.new(0,-50,0), downParams)
		if not ray then return true end
		local distDown = (part.Position.Y - ray.Position.Y)
		return distDown > 8
	end
	if isAirborne(root) then return end

	-- Compute destination
	local function flatDirTo(pos: Vector3)
		local from = root.Position
		local to = Vector3.new(pos.X, from.Y, pos.Z)
		local v = (to - from)
		if v.Magnitude < 1e-3 then return Vector3.new(0,0,-1) end
		return v.Unit
	end
	local constantRange = CHIDORI_RANGE
	local direction = flatDirTo(targetRoot.Position)

	-- Windup com telegraph retangular (EXATAMENTE como Zabuza)
	local windup = playAnim("Wind_up", 0.1, 1.0, 1.0)
	local releaseWindupPose = holdLastKeyframePose(windup)
	setFrozen(true)  -- IGUAL AO ZABUZA
	local corridorWidth = math.max(4, CHIDORI_PATH_RADIUS * 2)
	local lineTele = createLineTelegraph(root.Position, direction, constantRange, corridorWidth, CHIDORI_TELEGRAPH + 10, Color3.fromRGB(255,70,70))
	
	-- Ativar lightning particles progressivamente
	local totalEffects = #lightningParticles + #lightningLights
	if totalEffects > 0 then
		local windupDuration = CHIDORI_TELEGRAPH
		local delayBetweenEffects = windupDuration / totalEffects
		
		task.spawn(function()
			for i, particle in ipairs(lightningParticles) do
				if not running then break end
				particle.Enabled = true
				pauseAwareWait(delayBetweenEffects)
			end
			for i, light in ipairs(lightningLights) do
				if not running then break end
				light.Enabled = true
				pauseAwareWait(delayBetweenEffects)
			end
		end)
	end
	
	-- Durante o windup: EXATAMENTE como Zabuza - rotação contínua no loop
	local windupEnd = os.clock() + CHIDORI_TELEGRAPH
	local lastDir = direction
	while running and os.clock() < windupEnd do
		if isPaused() then
			task.wait(0.05)
		else
			local tr = select(1, getNearestPlayer(500)) or targetRoot
			if tr then
				lastDir = flatDirTo(tr.Position)
			end
			-- IGUAL AO ZABUZA: rodar o root para olhar na direção do player
			local pos = root.Position
			root.CFrame = CFrame.lookAt(pos, pos + lastDir, Vector3.yAxis)
			
			-- Atualizar telegraph
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
				lineTele.CFrame = look * CFrame.new(0, -yDrop, -constantRange/2)
			end
			task.wait(0.05)
		end
	end
	
	-- Janela pre-dash: 0.5s parado
	local PRE_DASH_HOLD = 0.5
	local holdEnd = os.clock() + PRE_DASH_HOLD
	while running and os.clock() < holdEnd do
		if isPaused() then task.wait(0.05) else task.wait(0.05) end
	end
	
	-- libertar movimento (IGUAL AO ZABUZA)
	setFrozen(false)
	if not running or isPaused() then 
		if lineTele and lineTele.Parent then lineTele:Destroy() end 
		releaseWindupPose()
		for _, particle in ipairs(lightningParticles) do particle.Enabled = false end
		for _, light in ipairs(lightningLights) do light.Enabled = false end
		return 
	end

	-- Calcular destino final com raycast
	local lockedDir = lastDir
	humanoid.AutoRotate = false
	if root and root.Anchored then root.Anchored = false end
	pushActionLock()
	
	local maxPlanned = constantRange
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { enemyModel }
	local ray = workspace:Raycast(root.Position, lockedDir * maxPlanned, rayParams)
	local obstacleDist = ray and (ray.Position - root.Position).Magnitude - 2 or maxPlanned
	local dashDist = math.max(0, math.min(maxPlanned, obstacleDist))
	local dest = root.Position + lockedDir * dashDist

	-- Safety: clamp destination within map
	local offsetFromSpawn = dest - SPAWN_POS
	if offsetFromSpawn.Magnitude > MAX_MAP_RADIUS then
		local limitedDir = offsetFromSpawn.Unit
		dest = SPAWN_POS + limitedDir * MAX_MAP_RADIUS
		dashDist = (dest - root.Position).Magnitude
	end

	-- Helper to test ground
	local function groundHit(testPos: Vector3)
		local downParams = RaycastParams.new()
		downParams.FilterType = Enum.RaycastFilterType.Exclude
		downParams.FilterDescendantsInstances = { enemyModel }
		return workspace:Raycast(testPos + Vector3.new(0,2,0), Vector3.new(0,-150,0), downParams)
	end

	-- Validate ground at destination
	local hit = groundHit(dest)
	if not hit or (dest.Y - hit.Position.Y) > 25 then
		local low, high = 0, dashDist
		local best = 0
		for i = 1, 8 do
			local mid = (low + high) * 0.5
			local testPos = root.Position + lockedDir * mid
			local h = groundHit(testPos)
			if h and (testPos.Y - h.Position.Y) <= 25 then
				best = mid
				low = mid
			else
				high = mid
			end
		end
		if best < 8 then
			popActionLock()
			if lineTele and lineTele.Parent then lineTele:Destroy() end
			humanoid.AutoRotate = true
			for _, particle in ipairs(lightningParticles) do particle.Enabled = false end
			for _, light in ipairs(lightningLights) do light.Enabled = false end
			return
		end
		dashDist = best
		dest = root.Position + lockedDir * dashDist
	end

	-- ===== FASE 2: DASH =====
	lastChidori = now
	releaseWindupPose()
	pcall(function()
		if windup then
			windup:AdjustWeight(0)
			windup:Stop(0.05)
		end
	end)
	
	local dashTrack = playAnim("Dash", 0.05, 1.0, 1.0)
	local releaseDashPose = holdLastKeyframePose(dashTrack)
	
	local startPos = root.Position
	local lastDamagePos = startPos
	local lastSafePos = startPos
	
	local function updateSafe(pos: Vector3)
		local h = groundHit(pos)
		if h and (pos.Y - h.Position.Y) <= 25 then
			lastSafePos = pos
		end
	end
	updateSafe(startPos)
	
	-- Movimento através de CFrame
	local DASH_DURATION = 0.5
	local startTime = os.clock()
	local stepLen = math.max(1.5, CHIDORI_PATH_RADIUS * 0.75)
	
	while running do
		if isPaused() then
			task.wait(0.05)
		else
			local elapsed = os.clock() - startTime
			local alpha = math.min(elapsed / DASH_DURATION, 1.0)
			
			local currentPos = startPos:Lerp(dest, alpha)
			root.CFrame = CFrame.lookAt(currentPos, currentPos + lockedDir, Vector3.yAxis)
			
			updateSafe(currentPos)
			
			-- Dano contínuo
			local seg = currentPos - lastDamagePos
			local segLen = seg.Magnitude
			if segLen >= stepLen then
				local dirSeg = seg / segLen
				local steps = math.clamp(math.ceil(segLen / stepLen), 1, 12)
				for i = 1, steps do
					local p = lastDamagePos + dirSeg * (i * (segLen / steps))
					areaDamage(p, CHIDORI_PATH_RADIUS, CHIDORI_PATH_DAMAGE)
				end
				lastDamagePos = currentPos
			end
			
			if alpha >= 1.0 then
				break
			end
			
			task.wait()
		end
	end
	
	-- Dano final
	areaDamage(root.Position, CHIDORI_AOE_RADIUS, CHIDORI_DAMAGE)
	
	-- ===== FASE 3: FINISH =====
	releaseDashPose()
	pcall(function()
		if dashTrack then
			dashTrack:AdjustWeight(0)
			dashTrack:Stop(0.05)
		end
	end)
	
	local impactTrack = playAnim("Dash_Finish", 0.05, 1.0, 1.0)
	local releaseImpactPose = holdLastKeyframePose(impactTrack)
	
	local impactLength = (impactTrack and impactTrack.Length) or 0.5
	pauseAwareWait(impactLength)
	
	-- Desativar particles APÓS finish
	for _, particle in ipairs(lightningParticles) do particle.Enabled = false end
	for _, light in ipairs(lightningLights) do light.Enabled = false end
	
	releaseImpactPose()
	pcall(function()
		if impactTrack then
			impactTrack:Stop(0.2)
		end
	end)
	
	if lineTele and lineTele.Parent then lineTele:Destroy() end
	humanoid.AutoRotate = true
	popActionLock()
	
	-- Post-dash safety
	local finalOffset = root.Position - SPAWN_POS
	if finalOffset.Magnitude > (MAX_MAP_RADIUS + 50) or root.Position.Y < -20 then
		if lastSafePos then
			root.CFrame = CFrame.new(lastSafePos)
		end
	end
end

-- ========================================
-- WING ATTACK
-- ========================================
local lastWing = 0

local function tryWingAttack(now)
	if now - lastWing < WING_INTERVAL then return end
	if now - SPAWN_TIME < INITIAL_ATTACK_COOLDOWN then return end
	local targetRoot, dist = getNearestPlayer(500)
	if not targetRoot or dist > WING_RANGE then return end

	-- Helper: direção flat para o target
	local function flatDirTo(pos: Vector3)
		local from = root.Position
		local to = Vector3.new(pos.X, from.Y, pos.Z)
		local v = (to - from)
		if v.Magnitude < 1e-3 then return Vector3.new(0,0,-1) end
		return v.Unit
	end

	-- Orientar inicialmente para o player
	local initialDir = flatDirTo(targetRoot.Position)
	local initialAngle = math.atan2(initialDir.X, initialDir.Z) + math.pi
	root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, initialAngle, 0)

	-- Windup: tracking rotação enquanto anima
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false
	pushActionLock()
	
	local wingAnim = playAnim("wing_attack", 0.1, 1.0, 1.0)
	
	-- Conectar ao evento Hit da animação
	local hitConnection
	if wingAnim then
		hitConnection = wingAnim:GetMarkerReachedSignal("Hit"):Connect(function()
			-- Aplicar dano em cone 180° à frente (usar lookvector do root)
			local forward = root.CFrame.LookVector * Vector3.new(1, 0, 1) -- flat
			if forward.Magnitude > 0.01 then
				forward = forward.Unit
			else
				forward = flatDirTo(targetRoot.Position)
			end
			local centerPos = root.Position
			local halfAngle = math.rad(WING_CONE_ANGLE / 2)
			local waveMult = enemyModel:GetAttribute("DamageWaveMultiplier") or 1
			local dmg = WING_DAMAGE * waveMult
			
			for _, plr in ipairs(Players:GetPlayers()) do
				local char = plr.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local r = char and char:FindFirstChild("HumanoidRootPart")
				if hum and r and hum.Health > 0 then
					local toPlayer = (r.Position - centerPos)
					local dist = toPlayer.Magnitude
					if dist <= WING_RANGE then
						local dirToPlayer = toPlayer.Unit
						local dotProduct = forward.X * dirToPlayer.X + forward.Z * dirToPlayer.Z
						local angle = math.acos(math.clamp(dotProduct, -1, 1))
						if angle <= halfAngle then
							-- Dano
							Damage.Apply(hum, dmg)
							-- Knockback
							local knockbackDir = (dirToPlayer * Vector3.new(1, 0, 1)).Unit
							local bodyVelocity = Instance.new("BodyVelocity")
							bodyVelocity.MaxForce = Vector3.new(4e4, 0, 4e4)
							bodyVelocity.Velocity = knockbackDir * WING_KNOCKBACK
							bodyVelocity.Parent = r
							game:GetService("Debris"):AddItem(bodyVelocity, 0.2)
						end
					end
				end
			end
		end)
	end
	
	-- Durante windup: rodar para o player
	local windupEnd = os.clock() + WING_WINDUP
	local lastDir = initialDir
	
	while running and os.clock() < windupEnd do
		if isPaused() then
			task.wait(0.05)
		else
			local tr = select(1, getNearestPlayer(500)) or targetRoot
			if tr then
				lastDir = flatDirTo(tr.Position)
			end
			-- Rotação manual no Y-axis
			local pos = root.Position
			local targetAngle = math.atan2(lastDir.X, lastDir.Z) + math.pi
			root.CFrame = CFrame.new(pos) * CFrame.Angles(0, targetAngle, 0)
			task.wait(0.05)
		end
	end
	
	if not running or isPaused() then
		if hitConnection then hitConnection:Disconnect() end
		pcall(function() if wingAnim then wingAnim:Stop(0.1) end end)
		humanoid.WalkSpeed = MOVE_SPEED
		humanoid.AutoRotate = true
		popActionLock()
		return
	end
	
	-- Marcar cooldown
	lastWing = now
	
	-- Aguardar animação terminar completamente
	local animLength = (wingAnim and wingAnim.Length) or 1.5
	pauseAwareWait(math.max(0.5, animLength - WING_WINDUP))
	
	-- Cleanup
	if hitConnection then hitConnection:Disconnect() end
	pcall(function()
		if wingAnim then wingAnim:Stop(0.2) end
	end)
	
	humanoid.WalkSpeed = MOVE_SPEED
	humanoid.AutoRotate = true
	popActionLock()
end

-- ========================================
-- FIRE BALL ATTACK
-- ========================================
local lastFireBall = 0

-- Reference to Fireball model
local fireballTemplate = ReplicatedStorage:WaitForChild("Enemys"):FindFirstChild("Fireball")
if not fireballTemplate then
	warn("[Sasuke] Fireball model not found in ReplicatedStorage.Enemys")
end

local function tryFireBallAttack(now)
	if now - lastFireBall < FIREBALL_INTERVAL then return end
	if now - SPAWN_TIME < INITIAL_ATTACK_COOLDOWN then return end
	local targetRoot, dist = getNearestPlayer(500)
	if not targetRoot or dist > FIREBALL_RANGE then return end
	if not fireballTemplate then return end

	-- Lock movement
	pushActionLock()
	
	-- Play Fly animation (deixar animação controlar altura)
	local flyAnim = playAnim("Fly", 0.2, 1.0, 1.0)
	if not flyAnim then
		popActionLock()
		return
	end
	
	-- Hold last keyframe da animação Fly
	local releaseFlyPose = holdLastKeyframePose(flyAnim)
	
	-- Aguardar animação Fly terminar
	local flyLength = flyAnim.Length or 1.5
	pauseAwareWait(flyLength)
	
	-- Determine number of fireballs (2-5)
	local fireballCount = math.random(2, 5)
	print("[Sasuke] Launching " .. fireballCount .. " fireballs")
	
	-- Helper: direção flat para o target
	local function flatDirTo(pos: Vector3)
		local from = root.Position
		local to = Vector3.new(pos.X, from.Y, pos.Z)
		local v = (to - from)
		if v.Magnitude < 1e-3 then return Vector3.new(0,0,-1) end
		return v.Unit
	end
	
	print("[Sasuke] Starting fireball loop...")
	
	-- Launch fireballs
	for i = 1, fireballCount do
		print("[Sasuke] Fireball iteration", i, "of", fireballCount)
		if not running or isPaused() then 
			print("[Sasuke] Breaking loop - running:", running, "isPaused:", isPaused())
			break 
		end
		
		-- Rodar SUAVEMENTE na direção do player antes de cada fireball
		local currentTarget = select(1, getNearestPlayer(500))
		if currentTarget then
			print("[Sasuke] Rotating towards target...")
			local dir = flatDirTo(currentTarget.Position)
			local targetAngle = math.atan2(dir.X, dir.Z) + math.pi
			
			-- Smooth rotation over 0.3 seconds
			local rotationTime = 0.3
			local startTime = os.clock()
			local startCF = root.CFrame
			local targetCF = CFrame.new(root.Position) * CFrame.Angles(0, targetAngle, 0)
			
			while os.clock() - startTime < rotationTime and running do
				if isPaused() then
					task.wait(0.05)
				else
					local alpha = math.min((os.clock() - startTime) / rotationTime, 1.0)
					root.CFrame = startCF:Lerp(targetCF, alpha)
					task.wait()
				end
			end
			print("[Sasuke] Rotation complete")
		else
			print("[Sasuke] No target found for rotation")
		end
		
		print("[Sasuke] Playing Fire_Ball animation...")
		-- Play Fire_Ball animation
		local fireballAnim = playAnim("Fire_Ball", 0.1, 1.0, 1.0)
		
		if fireballAnim then
			print("[Sasuke] Fire_Ball animation loaded, Length:", fireballAnim.Length)
			print("[Sasuke] Connecting to 'Launch' marker signal...")
			
			-- Conectar ao evento "Launch" da animação ANTES de pausar
			local launchConnection
			local markerFired = false
			launchConnection = fireballAnim:GetMarkerReachedSignal("Launch"):Connect(function()
				print("[Sasuke] ===== Launch marker triggered! =====")
				markerFired = true
				
				-- Snapshot da posição do player
				local targetPlayer = select(1, getNearestPlayer(500))
				if not targetPlayer then 
					print("[Sasuke] No target player found for fireball")
					return 
				end
				
				local targetPosition = targetPlayer.Position
				
				-- Clonar o modelo Fireball
				local fireball = fireballTemplate:Clone()
				fireball.Name = "SasukeFireball"
				
				-- Posicionar na cabeça do Sasuke (já que está no ar)
				local head = enemyModel:FindFirstChild("Head")
				local startPos = head and head.Position or root.Position
				print("[Sasuke] Spawning fireball at", startPos, "targeting", targetPosition)
				local primaryPart = fireball:IsA("Model") and fireball.PrimaryPart or fireball
				
				if fireball:IsA("Model") then
					if primaryPart then
						print("[Sasuke] Setting Model PrimaryPart position")
						fireball:SetPrimaryPartCFrame(CFrame.new(startPos))
					else
						warn("[Sasuke] Fireball Model has no PrimaryPart!")
						return
					end
				else
					print("[Sasuke] Setting Part position")
					fireball.CFrame = CFrame.new(startPos)
				end
				
				fireball.Parent = workspace
				print("[Sasuke] Fireball added to workspace")
				
				-- Calcular direção para o target
				local direction = (targetPosition - startPos).Unit
				local distance = (targetPosition - startPos).Magnitude
				
				-- Animar o projectile
				task.spawn(function()
					local traveled = 0
					local maxLifetime = 5
					local elapsed = 0
					
					while elapsed < maxLifetime and fireball.Parent and traveled < distance + 10 do
						if isPaused() then
							task.wait(0.05)
						else
							local dt = task.wait()
							elapsed += dt
							
							-- Mover fireball
							local moveAmount = FIREBALL_SPEED * dt
							traveled += moveAmount
							
							local currentPos = primaryPart and primaryPart.Position or fireball.Position
							local newPos = currentPos + direction * moveAmount
							
							if fireball:IsA("Model") and primaryPart then
								fireball:SetPrimaryPartCFrame(CFrame.new(newPos))
							else
								fireball.CFrame = CFrame.new(newPos)
							end
							
							-- Check collision com players
							for _, plr in ipairs(Players:GetPlayers()) do
								local char = plr.Character
								local hum = char and char:FindFirstChildOfClass("Humanoid")
								local r = char and char:FindFirstChild("HumanoidRootPart")
								if hum and r and hum.Health > 0 then
									local distToPlayer = (r.Position - newPos).Magnitude
									if distToPlayer <= 5 then
										-- Explosion e dano
										areaDamage(newPos, FIREBALL_EXPLOSION_RADIUS, FIREBALL_DAMAGE)
										
										-- Explosion effect
										local explosion = Instance.new("Part")
										explosion.Shape = Enum.PartType.Ball
										explosion.Size = Vector3.new(1, 1, 1)
										explosion.Material = Enum.Material.Neon
										explosion.Color = Color3.fromRGB(255, 150, 0)
										explosion.Anchored = true
										explosion.CanCollide = false
										explosion.Transparency = 0.3
										explosion.Position = newPos
										explosion.Parent = workspace
										
										task.spawn(function()
											for j = 1, 10 do
												local scale = j / 10
												explosion.Size = Vector3.new(FIREBALL_EXPLOSION_RADIUS * 2 * scale, FIREBALL_EXPLOSION_RADIUS * 2 * scale, FIREBALL_EXPLOSION_RADIUS * 2 * scale)
												explosion.Transparency = 0.3 + (scale * 0.7)
												task.wait(0.05)
											end
											explosion:Destroy()
										end)
										
										fireball:Destroy()
										return
									end
								end
							end
							
							-- Check se chegou ao destino ou passou
							if traveled >= distance then
								-- Explosion no chão
								areaDamage(newPos, FIREBALL_EXPLOSION_RADIUS, FIREBALL_DAMAGE)
								
								-- Explosion effect
								local explosion = Instance.new("Part")
								explosion.Shape = Enum.PartType.Ball
								explosion.Size = Vector3.new(1, 1, 1)
								explosion.Material = Enum.Material.Neon
								explosion.Color = Color3.fromRGB(255, 150, 0)
								explosion.Anchored = true
								explosion.CanCollide = false
								explosion.Transparency = 0.3
								explosion.Position = newPos
								explosion.Parent = workspace
								
								task.spawn(function()
									for j = 1, 10 do
										local scale = j / 10
										explosion.Size = Vector3.new(FIREBALL_EXPLOSION_RADIUS * 2 * scale, FIREBALL_EXPLOSION_RADIUS * 2 * scale, FIREBALL_EXPLOSION_RADIUS * 2 * scale)
										explosion.Transparency = 0.3 + (scale * 0.7)
										task.wait(0.05)
									end
									explosion:Destroy()
								end)
								
								fireball:Destroy()
								return
							end
						end
					end
					
					-- Timeout ou saiu do mapa
					if fireball and fireball.Parent then
						fireball:Destroy()
					end
				end)
			end)
			
			-- Wait for animation to reach the marker (não pausar antes disso)
			local fireballLength = fireballAnim.Length or 1.0
			print("[Sasuke] Waiting for animation to complete (", fireballLength, "seconds)...")
			pauseAwareWait(fireballLength)
			print("[Sasuke] Animation wait complete. Marker fired:", markerFired)
			
			-- Cleanup
			if launchConnection then launchConnection:Disconnect() end
			pcall(function() fireballAnim:Stop(0.1) end)
		else
			warn("[Sasuke] Failed to load Fire_Ball animation!")
		end
		
		-- Small delay between fireballs
		if i < fireballCount then
			pauseAwareWait(0.3)
		end
	end
	
	-- Mark cooldown
	lastFireBall = now
	
	-- Cleanup
	releaseFlyPose()
	pcall(function() if flyAnim then flyAnim:Stop(0.2) end end)
	popActionLock()
end

-- ========================================
-- BASELINE MOVEMENT
-- ========================================
task.spawn(function()
	while running do
		if isPaused() then
			task.wait(0.05)
			continue
		end
		
		if not isActionLocked() and not isFrozen() then
			local targetRoot = getNearestPlayer(200)
			if targetRoot and humanoid then
				humanoid.WalkSpeed = MOVE_SPEED
				humanoid:MoveTo(targetRoot.Position)
			end
		end
		
		task.wait(0.5)
	end
end)

-- ========================================
-- ABILITY LOOP
-- ========================================
task.spawn(function()
	pauseAwareWait(INITIAL_ATTACK_COOLDOWN)
	
	while running do
		if isPaused() then
			task.wait(0.1)
			continue
		end
		
		local now = os.clock()
		
		-- Tentar Fire Ball primeiro (range médio-longo)
		tryFireBallAttack(now)
		
		-- Tentar Wing Attack (range curto)
		if now - lastFireBall > 2 then
			tryWingAttack(now)
		end
		
		-- Se não conseguiu Wing, tentar Chidori Dash
		if now - lastWing > 2 and now - lastFireBall > 2 then
			tryChidoriDash(now)
		end
		
		task.wait(1.0)
	end
end)
