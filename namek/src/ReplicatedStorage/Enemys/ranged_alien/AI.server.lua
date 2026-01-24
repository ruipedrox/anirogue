-- Ranged Reaper AI: keeps distance and fires energy ball projectiles at players
-- SPECIAL: Uses 2 animations - AttackBegin (when stopping to attack) and Attack (loop while attacking)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")
local Projectile = require(ScriptsFolder:WaitForChild("Projectile"))

-- Find energyball model from Enemys/Attacks folder
local EnemysFolder = ReplicatedStorage:WaitForChild("Enemys")
local AttacksFolder = EnemysFolder:FindFirstChild("Attacks")
local energyballModel = AttacksFolder and AttacksFolder:FindFirstChild("energyball")

if not energyballModel then
	warn("[RangedReaper] energyball model not found in ReplicatedStorage/Enemys/Attacks folder; using default projectile.")
end

local enemyModel = script.Parent
local humanoid = enemyModel:FindFirstChildOfClass("Humanoid") or enemyModel:WaitForChild("Humanoid", 2)
local root = enemyModel.PrimaryPart or enemyModel:FindFirstChild("HumanoidRootPart") or (enemyModel:WaitForChild("HumanoidRootPart", 2))

if not root or not humanoid then return end

-- Load Animations: AttackBegin and Attack
local attackBeginAnim, attackLoopAnim
local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end

local animFolder = enemyModel:FindFirstChild("Animation")
if animFolder then
	local beginAnim = animFolder:FindFirstChild("AttackBegin") or animFolder:FindFirstChild("attack start")
	if beginAnim and beginAnim:IsA("Animation") then
		attackBeginAnim = animator:LoadAnimation(beginAnim)
		attackBeginAnim.Priority = Enum.AnimationPriority.Action
	end
	
	local loopAnim = animFolder:FindFirstChild("Attack") or animFolder:FindFirstChild("attack")
	if loopAnim and loopAnim:IsA("Animation") then
		attackLoopAnim = animator:LoadAnimation(loopAnim)
		attackLoopAnim.Priority = Enum.AnimationPriority.Action
		attackLoopAnim.Looped = false -- play once per shot
	end
end

-- Load local Stats module
local STATS do
	local statsModule = enemyModel:FindFirstChild("Stats") or enemyModel.Parent:FindFirstChild("Stats")
	if statsModule and statsModule:IsA("ModuleScript") then
		local ok, data = pcall(require, statsModule)
		if ok and type(data) == "table" then STATS = data end
	end
	if not STATS then
		local id = enemyModel:GetAttribute("EnemyId") or "ranged_Reaper"
		local folder = ReplicatedStorage:FindFirstChild("Enemys")
		folder = folder and folder:FindFirstChild(id)
		local sm = folder and folder:FindFirstChild("Stats")
		if sm and sm:IsA("ModuleScript") then
			local ok, data = pcall(require, sm)
			if ok and type(data) == "table" then STATS = data end
		end
	end
end

local ATTACK_INTERVAL = (STATS and STATS.AttackInterval) or 0.6
local ATTACK_RANGE = (STATS and STATS.AttackRange) or 85
local PROJECTILE_SPEED = (STATS and STATS.ProjectileSpeed) or 100
local PROJECTILE_DAMAGE = (STATS and STATS.ProjectileDamage) or 15
local PIERCE = (STATS and STATS.Pierce) or 1

-- DISABLED: Ranged Reaper no longer flees or maintains distance (was causing bugs)
-- local DESIRED_MIN = 30
-- local DESIRED_MAX = 50

local running = true
local isInAttackStance = false -- track if we're in attack mode (played AttackBegin)

local running = true
local isInAttackStance = false -- track if we're in attack mode (played AttackBegin)

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
			humanoid.WalkSpeed = savedWalkSpeed or 15
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

-- Movement loop: DISABLED - Ranged Reaper now stays in place (no fleeing/kiting)
-- Just rotate to face nearest player
task.spawn(function()
	while running do
		if ReplicatedStorage:GetAttribute("GamePaused") then
			applyPauseState(true)
			task.wait(0.05)
			continue
		else
			applyPauseState(false)
		end

		-- Seek nearest player and face them
		local bestRoot
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local r = char and char:FindFirstChild("HumanoidRootPart")
			if r and hum and hum.Health > 0 then
				local d = (r.Position - root.Position).Magnitude
				if not bestRoot or d < (bestRoot and (root.Position - bestRoot.Position).Magnitude or math.huge) then
					bestRoot = r
				end
			end
		end

		-- Stay in place, just rotate to face player
		if bestRoot then
			humanoid:Move(Vector3.zero) -- Stop all movement
			-- TOP-DOWN: Face the player (ignoring Y)
			local lookDir = (bestRoot.Position - root.Position) * Vector3.new(1, 0, 1)
			if lookDir.Magnitude > 0.001 then
				root.CFrame = CFrame.new(root.Position, root.Position + lookDir.Unit)
			end
		end

		task.wait(0.2)
	end
end)

-- Shooting loop with 2-animation system
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
			-- Acquire target to fire
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
				-- First time entering attack stance: play AttackBegin
				if not isInAttackStance then
					isInAttackStance = true
					if attackBeginAnim then
						pcall(function()
							attackBeginAnim:Play(0.1, 1, 1)
						end)
						task.wait(attackBeginAnim.Length or 0.5) -- wait for begin animation
					end
				end
				
				lastShot = now
				local origin = root.Position + Vector3.new(0, 1.6, 0)
			-- TOP-DOWN: Ignore Y axis when aiming projectile
			local dir = (bestRoot.Position - origin) * Vector3.new(1, 0, 1)
			if dir.Magnitude < 1e-3 then
				dir = Vector3.new(0, 0, -1)
			else
				dir = dir.Unit
			end
				-- Play attack loop animation (plays once per shot)
				if attackLoopAnim then
					pcall(function()
						attackLoopAnim:Play(0.05, 1, 1)
					end)
				end
				
				-- Fire energyball projectile
				Projectile.Fire({
					origin = origin,
					direction = dir,
					speed = PROJECTILE_SPEED,
				lifetime = 5,
					pierce = PIERCE,
					damage = PROJECTILE_DAMAGE,
					owner = enemyModel,
					ignore = { enemyModel },
					orientationOffset = CFrame.new(),
					spinPerSecond = math.rad(360),
					spinAxis = "Y",
					contactRadius = 0,
					hitCooldownPerTarget = 0.25,
					model = energyballModel,
				})
			else
				-- No target in range, reset attack stance
				isInAttackStance = false
			end
		end
		task.wait(0.05)
	end
end)

return true
