-- Zabuza AI
-- Abilities:
-- 1) Dash Slash: Telegraph (1s) then rapid dash toward nearest player (clamped distance), damaging players brushed along path & AoE at impact.
-- 2) Water Dragon: Fires a fast projectile with splash damage.
-- Both abilities are pause-aware (respect ReplicatedStorage.GamePaused attribute).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local enemyModel = script.Parent
local humanoid = enemyModel:FindFirstChildOfClass("Humanoid") or enemyModel:WaitForChild("Humanoid", 2)
local root = enemyModel.PrimaryPart or enemyModel:FindFirstChild("HumanoidRootPart") or (enemyModel:WaitForChild("HumanoidRootPart", 2))
if not humanoid or not root then return end

-- Load Stats
local STATS do
	local statsModule = enemyModel:FindFirstChild("Stats") or enemyModel.Parent:FindFirstChild("Stats") or enemyModel.Parent.Parent:FindFirstChild("Stats")
	if statsModule and statsModule:IsA("ModuleScript") then
		local ok, data = pcall(require, statsModule)
		if ok and type(data) == "table" then STATS = data end
	end
end

local Damage = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("Damage"))
local Projectile = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Projectile"))
local WaterDragon = require(enemyModel.Parent:FindFirstChild("WaterDragonProjectile") or ReplicatedStorage:WaitForChild("Enemys"):WaitForChild("Zabuza"):WaitForChild("WaterDragonProjectile"))

-- Extract stat values with defaults
local MOVE_SPEED = (STATS and STATS.MoveSpeed) or 16
local DASH_INTERVAL = (STATS and STATS.DashInterval) or 8
local DASH_TELEGRAPH = (STATS and STATS.DashTelegraph) or 2.0
-- Increase dash range significantly by enforcing a higher minimum specifically for Zabuza
local DASH_RANGE_BASE = ((STATS and STATS.DashRange) or 30)
local DASH_RANGE = math.max(DASH_RANGE_BASE, 75)
local DASH_DAMAGE = (STATS and STATS.DashDamage) or 120
local DASH_AOE_RADIUS = (STATS and STATS.DashAoERadius) or 10
local DASH_PATH_TICK_DAMAGE = (STATS and STATS.DashPathTickDamage) or math.floor(DASH_DAMAGE * 0.4)
local DASH_PATH_TICK_RADIUS = (STATS and STATS.DashPathTickRadius) or 5
local WD_INTERVAL = (STATS and STATS.WaterDragonInterval) or 11
local WD_SPEED = (STATS and STATS.WaterDragonSpeed) or 95
local WD_DAMAGE = (STATS and STATS.WaterDragonDamage) or 90
local WD_PIERCE = (STATS and STATS.WaterDragonPierce) or 1
local WD_RANGE = (STATS and STATS.WaterDragonRange) or 120
local WD_AOE_RADIUS = (STATS and STATS.WaterDragonAoERadius) or 12
local ABILITY_DMG_MULT = (STATS and STATS.AbilityDamageMultiplier) or 1

-- Initial spawn cooldown to prevent immediate face-plant dash
local SPAWN_TIME = os.clock()
local INITIAL_ATTACK_COOLDOWN = 3 -- seconds
local SPAWN_POS = root.Position
local MAX_MAP_RADIUS = (enemyModel:GetAttribute("MapRadius") or 600) -- fallback map radius safeguard
-- Global cooldown between abilities to prevent instant chaining
local LAST_ABILITY_TIME = 0
local ABILITY_CHAIN_COOLDOWN = 1.0

local running = true
humanoid.Died:Connect(function() running = false end)
enemyModel.AncestryChanged:Connect(function(_, parent) if not parent then running = false end end)

-- Optional animations support: place Animation instances under a child folder named "Animations"
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
	if not animObj then
		-- Fallback: look in ReplicatedStorage.Enemys.Zabuza.Animations
		local f = ReplicatedStorage:FindFirstChild("Enemys")
		f = f and f:FindFirstChild("Zabuza")
		f = f and f:FindFirstChild("Animations")
		if f then
			local a = f:FindFirstChild(name)
			if a and a:IsA("Animation") then animObj = a end
		end
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
		tr:Play(fade or 0.1, weight or 1.0, speed or 1.0)
		return tr
	end
end

-- Hold last keyframe pose helper: keeps an AnimationTrack paused at its end pose until released.
-- Returns a release() function that will stop the track when called.
local function holdLastKeyframePose(track: AnimationTrack?)
	if not track then return function() end end
	local holding = true
	task.spawn(function()
		-- Allow short delay to ensure track has started
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

local function applyPauseState(paused)
	if not humanoid then return end
	if paused then
		humanoid.WalkSpeed = 0
	else
		humanoid.WalkSpeed = MOVE_SPEED
	end
end

-- Freeze control: make Zabuza completely still during certain phases (cast, dash windup, etc.)
local frozenCount = 0
local actionLock = 0 -- inhibits baseline movement while performing abilities (e.g., dash)
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
	if root and root:IsA("BasePart") then
		root.Anchored = shouldFreeze
	end
end
local function withFrozen(duration: number)
	setFrozen(true)
	pauseAwareWait(duration)
	setFrozen(false)
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
	local dmg = baseDamage * waveMult * ABILITY_DMG_MULT
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

-- Telegraph generator (cylinder)
local function createTelegraph(position: Vector3, radius: number, duration: number, color: Color3)
	local part = Instance.new("Part")
	part.Name = "ZabuzaTelegraph"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Neon
	part.Color = color or Color3.fromRGB(255, 90, 90)
	part.Transparency = 0.55
	local height = 0.3
	part.Size = Vector3.new(height, radius*2, radius*2)
	part.CFrame = CFrame.new(position) * CFrame.Angles(0,0,math.rad(90))
	part.Parent = workspace
	-- Simple pulse
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
	end)
	return part
end

-- Telegraph generator (rectangular corridor aligned with direction)
local function createLineTelegraph(startPos: Vector3, dir: Vector3, length: number, width: number, duration: number, color: Color3)
	dir = (dir.Magnitude > 1e-3) and dir.Unit or Vector3.new(0,0,-1)
	local part = Instance.new("Part")
	part.Name = "ZabuzaDashCorridor"
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
	-- place center halfway along the corridor, right above the ground near the character feet
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
				-- subtle pulse on width and transparency
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

-- Dash ability
local lastDash = 0
local function tryDash(now)
	if now - lastDash < DASH_INTERVAL then return end
	if now - SPAWN_TIME < INITIAL_ATTACK_COOLDOWN then return end
	local targetRoot, dist = getNearestPlayer(500)
	if not targetRoot then return end

	-- Evitar dash imediato ao spawn enquanto ainda está a cair / não estabilizado.
	-- Verifica se o root está muito acima do chão local (raycast para baixo) e cancela se diferença > 8.
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

	-- Compute destination (clamp dash distance)
	local function flatDirTo(pos: Vector3)
		local from = root.Position
		local to = Vector3.new(pos.X, from.Y, pos.Z)
		local v = (to - from)
		if v.Magnitude < 1e-3 then return Vector3.new(0,0,-1) end
		return v.Unit
	end
	local constantRange = DASH_RANGE
	local direction = flatDirTo(targetRoot.Position)

	-- Windup com telegraph retangular em frente ao Zabuza (corredor do dash)
	local windup = playAnim("DashWindup", 0.1, 1.0, 1.0)
	local releaseWindupPose = holdLastKeyframePose(windup)
	setFrozen(true)
	local corridorWidth = math.max(4, DASH_PATH_TICK_RADIUS * 2)
	-- Criar o telegraph e mantê-lo durante todo o ataque (windup + hold + dash)
	local lineTele = createLineTelegraph(root.Position, direction, constantRange, corridorWidth, DASH_TELEGRAPH + 10, Color3.fromRGB(255,70,70))
	-- Durante o windup: Zabuza não se mexe, mas vai girando para o player; telegraph roda junto; comprimento é constante
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
			-- rodar o root para olhar na direção do player (somente yaw)
			local pos = root.Position
			root.CFrame = CFrame.lookAt(pos, pos + lastDir, Vector3.yAxis)
			-- atualizar orientação do telegraph para acompanhar a rotação
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
	-- Janela pre-dash: 0.5s parado e sem girar (root continua ancorado), para permitir reação do player.
	local PRE_DASH_HOLD = 0.5
	local holdEnd = os.clock() + PRE_DASH_HOLD
	-- já estamos frozen; não atualizar rotação; só esperar respeitando pause
	while running and os.clock() < holdEnd do
		if isPaused() then task.wait(0.05) else task.wait(0.05) end
	end
	-- libertar movimento mas manter orientação travada para dash
	setFrozen(false) -- isto desancora
	if not running or isPaused() then if lineTele and lineTele.Parent then lineTele:Destroy() end releaseWindupPose() return end

	-- Travar rotação durante o dash (linha reta) e calcular destino final com raycast nessa direção final do windup
	local lockedDir = lastDir
	humanoid.AutoRotate = false
	if root and root.Anchored then root.Anchored = false end -- segurança: garantir que pode mover
	pushActionLock()
	local maxPlanned = constantRange
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { enemyModel }
	local ray = workspace:Raycast(root.Position, lockedDir * maxPlanned, rayParams)
	local obstacleDist = ray and (ray.Position - root.Position).Magnitude - 2 or maxPlanned
	local dashDist = math.max(0, math.min(maxPlanned, obstacleDist))
	local dest = root.Position + lockedDir * dashDist

	-- Safety: clamp destination within a reasonable radius around spawn to avoid leaving map.
	local offsetFromSpawn = dest - SPAWN_POS
	if offsetFromSpawn.Magnitude > MAX_MAP_RADIUS then
		local limitedDir = offsetFromSpawn.Unit
		dest = SPAWN_POS + limitedDir * MAX_MAP_RADIUS
		dashDist = (dest - root.Position).Magnitude
	end

	-- Helper to test ground at a position (returns ray result or nil)
	local function groundHit(testPos: Vector3)
		local downParams = RaycastParams.new()
		downParams.FilterType = Enum.RaycastFilterType.Exclude
		downParams.FilterDescendantsInstances = { enemyModel }
		return workspace:Raycast(testPos + Vector3.new(0,2,0), Vector3.new(0,-150,0), downParams)
	end

	-- Validate ground at destination; if no ground or too far above ground, binary search shorten the dash path.
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
			-- Abort dash: unsafe (would leave map or no ground soon)
			popActionLock()
			if lineTele and lineTele.Parent then lineTele:Destroy() end
			humanoid.AutoRotate = true
			return
		end
		dashDist = best
		dest = root.Position + lockedDir * dashDist
	end

	-- ===== FASE 2: DASH (movimento rápido) =====
	lastDash = now
	-- Parar windup e iniciar animação Dash
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
	
	-- Movimento através de CFrame (smooth e rápido)
	local DASH_DURATION = 0.5 -- duração do dash em segundos
	local startTime = os.clock()
	local stepLen = math.max(1.5, DASH_PATH_TICK_RADIUS * 0.75)
	
	while running do
		if isPaused() then
			task.wait(0.05)
		else
			local elapsed = os.clock() - startTime
			local alpha = math.min(elapsed / DASH_DURATION, 1.0)
			
			-- Interpolar posição suavemente
			local currentPos = startPos:Lerp(dest, alpha)
			root.CFrame = CFrame.lookAt(currentPos, currentPos + lockedDir, Vector3.yAxis)
			
			updateSafe(currentPos)
			
			-- Dano contínuo durante o dash
			local seg = currentPos - lastDamagePos
			local segLen = seg.Magnitude
			if segLen >= stepLen then
				local dirSeg = seg / segLen
				local steps = math.clamp(math.ceil(segLen / stepLen), 1, 12)
				for i = 1, steps do
					local p = lastDamagePos + dirSeg * (i * (segLen / steps))
					areaDamage(p, DASH_PATH_TICK_RADIUS, DASH_PATH_TICK_DAMAGE)
				end
				lastDamagePos = currentPos
			end
			
			if alpha >= 1.0 then
				break
			end
			
			task.wait()
		end
	end
	
	-- ===== FASE 3: FINISH (animação de impacto) =====
	releaseDashPose()
	pcall(function()
		if dashTrack then
			dashTrack:AdjustWeight(0)
			dashTrack:Stop(0.05)
		end
	end)
	
	local impactTrack = playAnim("DashImpact", 0.05, 1.0, 1.0)
	local releaseImpactPose = holdLastKeyframePose(impactTrack)
	
	-- Esperar animação de impacto completar
	local impactLength = (impactTrack and impactTrack.Length) or 0.5
	pauseAwareWait(impactLength)
	
	-- Limpar tudo
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
	
	LAST_ABILITY_TIME = os.clock()
end

-- Water Dragon ability
local lastWD = 0
local function tryWaterDragon(now)
	if now - lastWD < WD_INTERVAL then return end
	if now - SPAWN_TIME < INITIAL_ATTACK_COOLDOWN then return end
	local targetRoot, dist = getNearestPlayer(WD_RANGE)
	if not targetRoot or not dist then return end
	lastWD = now
	
	-- Telegraph durante a animação
	local dir = (targetRoot.Position - root.Position)
	dir = (dir.Magnitude > 1e-3) and dir.Unit or Vector3.new(0,0,-1)
	local corridorLength = math.min((targetRoot.Position - root.Position).Magnitude, 20)
	local corridorWidth = math.max(4, WD_AOE_RADIUS * 1.25)
	
	-- Congelar completamente durante Cast (ancorar root)
	pushActionLock()
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false
	if root then root.Anchored = true end -- Ancorar para não se mexer durante cast
	
	local tele = createLineTelegraph(root.Position, dir, corridorLength, corridorWidth, 3.0, Color3.fromRGB(90,140,255))
	
	-- Tocar animação Cast completa
	local castTrack = playAnim("Cast", 0.1, 1.0, 1.0)
	
	-- Conectar evento "dragon" para disparar projétil
	if castTrack then
		local ok, sig = pcall(function() return castTrack:GetMarkerReachedSignal("dragon") end)
		if ok and sig then 
			sig:Connect(function()
				print("[Zabuza] Evento 'dragon' - disparando projétil")
				if not running or isPaused() then return end
				
				local waveMult = enemyModel:GetAttribute("DamageWaveMultiplier") or 1
				local dmg = WD_DAMAGE * waveMult * ABILITY_DMG_MULT
				local currentTarget = getNearestPlayer(WD_RANGE)
				if currentTarget then
					local origin = root.Position + (currentTarget.Position - root.Position).Unit * 2
					WaterDragon.Fire({
						origin = origin,
						targetPos = currentTarget.Position,
						damage = dmg,
						splashRadius = WD_AOE_RADIUS,
						splashDamage = math.floor(dmg * 0.7),
						speed = WD_SPEED,
						pierce = WD_PIERCE,
						lifetime = WD_RANGE / WD_SPEED + 0.5,
					})
				end
			end)
		end
	end
	
	-- Esperar animação completa
	local animLength = (castTrack and castTrack.Length) or 2.0
	pauseAwareWait(animLength)
	
	-- Limpar e voltar ao normal
	if tele and tele.Parent then tele:Destroy() end
	if root then root.Anchored = false end -- Desancorar após cast
	popActionLock()
	humanoid.WalkSpeed = MOVE_SPEED
	humanoid.AutoRotate = true
	if castTrack and castTrack.IsPlaying then castTrack:Stop(0.2) end
	
	LAST_ABILITY_TIME = os.clock()
end

-- Movement loop (baseline chase when not dashing/casting)
task.spawn(function()
	while running do
		if isPaused() then
			applyPauseState(true)
			task.wait(0.05)
			continue
		else
			applyPauseState(false)
		end
		local targetRoot, _ = getNearestPlayer(300)
		if targetRoot and not isFrozen() and not isActionLocked() then
			humanoid:MoveTo(targetRoot.Position + Vector3.new(0,0,0))
		end
		task.wait(0.25)
	end
end)

-- Ability scheduler
task.spawn(function()
	while running do
		if isPaused() then
			task.wait(0.05)
			continue
		end
		local now = os.clock()
		-- Skip any abilities until initial cooldown expires
		if now - SPAWN_TIME < INITIAL_ATTACK_COOLDOWN then
			task.wait(0.1)
			continue
		end
		-- Enforce a global 1s cooldown between ability executions
		if (now - LAST_ABILITY_TIME) < ABILITY_CHAIN_COOLDOWN then
			task.wait(0.05)
			continue
		end
		local targetRoot, dist = getNearestPlayer(400)
		if targetRoot and dist then
			local dashInRange = dist <= DASH_RANGE * 1.2
			local dashReady = (now - lastDash >= DASH_INTERVAL)
			local waterReady = (now - lastWD >= WD_INTERVAL)
			-- Prioridade: tentar dash se está em range e pronto; senão tentar Water Dragon se pronto.
			if dashInRange and dashReady then
				tryDash(now)
			elseif waterReady then
				tryWaterDragon(now)
			end
		end
		task.wait(0.1)
	end
end)

return true
