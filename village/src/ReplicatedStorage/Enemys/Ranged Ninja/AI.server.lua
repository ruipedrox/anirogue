-- Ranged Ninja AI: keeps distance and fires projectiles at players

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")
local Projectile = require(ScriptsFolder:WaitForChild("Projectile"))

-- Shared Kunai assets (model + attack animation) so projectile & throw anim come from Shared folder
local KunaiFolder = ReplicatedStorage:FindFirstChild("Shared")
KunaiFolder = KunaiFolder and KunaiFolder:FindFirstChild("Items")
KunaiFolder = KunaiFolder and KunaiFolder:FindFirstChild("Weapons")
KunaiFolder = KunaiFolder and KunaiFolder:FindFirstChild("Kunai")

-- Robust lookup for Kunai model (accept common name variants or descendants)
local function findKunaiModel(rootFolder: Instance?): Instance?
	if not rootFolder then return nil end
	local candidates = {}
	local function consider(inst: Instance)
		if inst:IsA("BasePart") then
			table.insert(candidates, inst)
		elseif inst:IsA("Model") then
			-- Prefer model primary part if it has one
			table.insert(candidates, inst)
		end
	end
	-- Direct names (case variants)
	for _, name in ipairs({"kunai","Kunai","KUNAI"}) do
		local child = rootFolder:FindFirstChild(name)
		if child then consider(child) end
	end
	-- Descendants containing 'kunai'
	for _, d in ipairs(rootFolder:GetDescendants()) do
		if (d:IsA("Model") or d:IsA("BasePart")) and string.find(string.lower(d.Name), "kunai") then
			consider(d)
		end
	end
	if #candidates == 0 then return nil end
	-- Rank: prefer BasePart over Model; then fewest BaseParts; then smallest volume
	table.sort(candidates, function(a,b)
		local function partCount(obj)
			if obj:IsA("BasePart") then return 1 end
			local c = 0
			for _, x in ipairs(obj:GetDescendants()) do if x:IsA("BasePart") then c += 1 end end
			return c
		end
		local function volume(obj)
			if obj:IsA("BasePart") then
				local s = obj.Size
				return s.X * s.Y * s.Z
			end
			local primary: BasePart? = nil
			if obj:IsA("Model") then
				primary = obj.PrimaryPart
				if not primary then
					for _, x in ipairs(obj:GetDescendants()) do if x:IsA("BasePart") then primary = x break end end
				end
			end
			if not primary then return math.huge end
			local s = primary.Size
			return s.X * s.Y * s.Z
		end
		local pcA, pcB = partCount(a), partCount(b)
		if pcA ~= pcB then return pcA < pcB end
		local va, vb = volume(a), volume(b)
		return va < vb
	end)
	return candidates[1]
end

local kunaiModelSource = findKunaiModel(KunaiFolder)

-- Animation variants accepted: Attack, Throw, Shoot
local function findKunaiAnimation(rootFolder: Instance?): Animation?
	if not rootFolder then return nil end
	for _, name in ipairs({"Attack","Throw","Shoot"}) do
		local a = rootFolder:FindFirstChild(name)
		if a and a:IsA("Animation") then return a end
	end
	-- Descendant search fallback
	for _, d in ipairs(rootFolder:GetDescendants()) do
		if d:IsA("Animation") and string.find(string.lower(d.Name), "attack") then
			return d
		end
	end
	return nil
end
local attackAnimationSource = findKunaiAnimation(KunaiFolder)

if not kunaiModelSource then
	warn("[RangedNinja] Kunai model not found in Shared.Items.Weapons.Kunai; using default projectile.")
end
if not attackAnimationSource then
	warn("[RangedNinja] Kunai attack animation not found (Attack/Throw/Shoot). No throw animation will play.")
end

local animator: Animator? = nil
local attackTrack: AnimationTrack? = nil

local enemyModel = script.Parent
local humanoid = enemyModel:FindFirstChildOfClass("Humanoid") or enemyModel:WaitForChild("Humanoid", 2)
local root = enemyModel.PrimaryPart or enemyModel:FindFirstChild("HumanoidRootPart") or (enemyModel:WaitForChild("HumanoidRootPart", 2))

if not root or not humanoid then return end

-- Prepare animator and attack track if shared Kunai animation exists
task.spawn(function()
	if humanoid then
		animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		if attackAnimationSource and attackAnimationSource:IsA("Animation") then
			local ok, track = pcall(function()
				return animator:LoadAnimation(attackAnimationSource)
			end)
			if ok and track then
				track.Priority = Enum.AnimationPriority.Action
				attackTrack = track
			end
		end
	end
end)
-- Lazy refresh helpers for Kunai model/animation in case Shared assets load later or get renamed
local lastKunaiLookup = 0
local function getKunaiAssets()
	local now = os.clock()
	-- Recheck at most every 2 seconds if missing
	if (not kunaiModelSource) and (lastKunaiLookup == 0 or now - lastKunaiLookup > 2) then
		lastKunaiLookup = now
		-- Try canonical path first
		local base = ReplicatedStorage:FindFirstChild("Shared")
		base = base and base:FindFirstChild("Items")
		base = base and base:FindFirstChild("Weapons")
		base = base and base:FindFirstChild("Kunai")
		kunaiModelSource = findKunaiModel(base or ReplicatedStorage)
		if not attackAnimationSource then
			attackAnimationSource = findKunaiAnimation(base or ReplicatedStorage)
			if attackAnimationSource and animator and (not attackTrack) then
				local ok, track = pcall(function()
					return animator:LoadAnimation(attackAnimationSource)
				end)
				if ok and track then
					track.Priority = Enum.AnimationPriority.Action
					attackTrack = track
				end
			end
		end
		if kunaiModelSource then
			warn("[RangedNinja] Kunai model found late; switching to Shared model for projectiles.")
		end
	end
	return kunaiModelSource, attackAnimationSource
end


-- Load local Stats module (inside the model or from ReplicatedStorage by EnemyId)
local STATS do
	local statsModule = enemyModel:FindFirstChild("Stats") or enemyModel.Parent:FindFirstChild("Stats")
	if statsModule and statsModule:IsA("ModuleScript") then
		local ok, data = pcall(require, statsModule)
		if ok and type(data) == "table" then STATS = data end
	end
	if not STATS then
		local id = enemyModel:GetAttribute("EnemyId") or "Ranged Ninja"
		local folder = ReplicatedStorage:FindFirstChild("Enemys")
		folder = folder and folder:FindFirstChild(id)
		local sm = folder and folder:FindFirstChild("Stats")
		if sm and sm:IsA("ModuleScript") then
			local ok, data = pcall(require, sm)
			if ok and type(data) == "table" then STATS = data end
		end
	end
end

local ATTACK_INTERVAL = (STATS and STATS.AttackInterval) or 1.15
local ATTACK_RANGE = (STATS and STATS.AttackRange) or 95
local PROJECTILE_SPEED = (STATS and STATS.ProjectileSpeed) or 95
local PROJECTILE_DAMAGE = (STATS and STATS.ProjectileDamage) or 13
local PIERCE = (STATS and STATS.Pierce) or 1

local DESIRED_MIN = 35
local DESIRED_MAX = 55

local running = true

-- Pause handling: freeze enemy while paused
local pauseApplied = false
local savedWalkSpeed, savedJumpPower, savedAutoRotate
local function applyPauseState(paused)
	if not humanoid or not root then return end
	if paused then
		if not pauseApplied then
			savedWalkSpeed = humanoid.WalkSpeed
			savedJumpPower = humanoid.JumpPower
			savedAutoRotate = humanoid.AutoRotate
			pauseApplied = true
		end
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false
		pcall(function()
			humanoid:Move(Vector3.zero)
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end)
		root.AssemblyLinearVelocity = Vector3.new()
		root.AssemblyAngularVelocity = Vector3.new()
	else
		if pauseApplied then
			humanoid.WalkSpeed = savedWalkSpeed or 16
			humanoid.JumpPower = savedJumpPower or 50
			humanoid.AutoRotate = (savedAutoRotate == nil) and true or savedAutoRotate
			pcall(function()
				humanoid:ChangeState(Enum.HumanoidStateType.Running)
			end)
			pauseApplied = false
		end
	end
end

if humanoid then humanoid.Died:Connect(function() running = false end) end
enemyModel.AncestryChanged:Connect(function(_, parent) if not parent then running = false end end)

-- Movement/spacing loop
task.spawn(function()
	while running do
		if ReplicatedStorage:GetAttribute("GamePaused") then
			applyPauseState(true)
			task.wait(0.05)
			continue
		else
			applyPauseState(false)
		end

		-- Seek nearest player
		local bestRoot, bestDist
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local r = char and char:FindFirstChild("HumanoidRootPart")
			if r and hum and hum.Health > 0 then
				local d = (r.Position - root.Position).Magnitude
				if not bestDist or d < bestDist then
					bestDist = d
					bestRoot = r
				end
			end
		end

		-- Move to keep distance
		if bestRoot then
			local d = bestDist or math.huge
			local moveSpeed = enemyModel:GetAttribute("MoveSpeed")
			if typeof(moveSpeed) ~= "number" or moveSpeed <= 0 then
				moveSpeed = humanoid.WalkSpeed
			end
			humanoid.WalkSpeed = moveSpeed

			local desiredPos
			if d < DESIRED_MIN then
				-- too close: move away
				local dir = (root.Position - bestRoot.Position)
				if dir.Magnitude > 0.001 then dir = dir.Unit else dir = Vector3.new(1,0,0) end
				desiredPos = root.Position + dir * (DESIRED_MIN - d + 6)
			elseif d > DESIRED_MAX then
				-- too far: move closer but keep range
				local dir = (bestRoot.Position - root.Position)
				if dir.Magnitude > 0.001 then dir = dir.Unit else dir = Vector3.new(1,0,0) end
				desiredPos = root.Position + dir * (d - DESIRED_MAX + 6)
			else
				-- Already in desired range, stop moving
				desiredPos = root.Position
				humanoid:Move(Vector3.zero)
			end
			if desiredPos and desiredPos ~= root.Position then 
				humanoid:MoveTo(desiredPos) 
			end
		end

		task.wait(0.2)
	end
end)

-- Shooting loop
local lastShot = 0
task.spawn(function()
	while running do
		if ReplicatedStorage:GetAttribute("GamePaused") then
			applyPauseState(true)
			task.wait(0.05)
			continue
		else
			applyPauseState(false)
		end
		local now = os.clock()
		if now - lastShot >= ATTACK_INTERVAL then
			-- Acquire target again to fire
			local bestRoot, bestDist
			for _, plr in ipairs(Players:GetPlayers()) do
				local char = plr.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local r = char and char:FindFirstChild("HumanoidRootPart")
				if r and hum and hum.Health > 0 then
					local d = (r.Position - root.Position).Magnitude
					if d <= ATTACK_RANGE and (not bestDist or d < bestDist) then
						bestDist = d
						bestRoot = r
					end
				end
			end
			if bestRoot then
				lastShot = now
				local origin = root.Position + Vector3.new(0,1.6,0)
				local dir = (bestRoot.Position - origin)
				if dir.Magnitude > 0.001 then dir = dir.Unit else dir = Vector3.new(0,0,-1) end
				-- Refresh Kunai assets if needed
				local modelSource, _ = getKunaiAssets()
				-- Play shared attack animation if available
				if attackTrack then
					pcall(function()
						attackTrack:Play(0.05, 1, 1)
					end)
				end
				-- Choose model and orientation depending on Shared Kunai availability
				-- If we have a custom model, face its forward (+Z) toward travel direction; else keep legacy sideways offset
				-- Compute orientation offset: if the Kunai part is taller (Y largest), rotate it to lie horizontally along +Z direction
				local orientationOffset
				if modelSource and modelSource:IsA("BasePart") then
					local s = modelSource.Size
					if s.Y > s.X and s.Y > s.Z then
						orientationOffset = CFrame.Angles(math.rad(90), 0, 0)
					else
						orientationOffset = CFrame.new()
					end
				else
					orientationOffset = CFrame.Angles(0, math.rad(-90), 0)
				end
				Projectile.Fire({
					origin = origin,
					direction = dir,
					speed = PROJECTILE_SPEED,
				lifetime = 5,
					pierce = PIERCE,
					damage = PROJECTILE_DAMAGE,
					owner = enemyModel,
					ignore = { enemyModel },
					orientationOffset = orientationOffset,
					spinPerSecond = math.rad(360),
					spinAxis = "Y",
					contactRadius = 0,
					hitCooldownPerTarget = 0.25,
					model = modelSource,
				})

			end
		end
		task.wait(0.05)
	end
end)

return true
