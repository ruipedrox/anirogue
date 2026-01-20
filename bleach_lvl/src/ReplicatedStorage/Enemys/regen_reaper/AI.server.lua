-- Melee Ninja AI: simple contact damage within 1 stud
-- This script should be cloned along with the enemy model and run server-side.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local RANGE = 3 -- increased to expand enemy engagement range
local COOLDOWN = 0.5
local DEFAULT_DAMAGE = 10

local enemyModel = script.Parent
local humanoid = enemyModel:FindFirstChildOfClass("Humanoid") or enemyModel:WaitForChild("Humanoid", 2)
local root = enemyModel.PrimaryPart or enemyModel:FindFirstChild("HumanoidRootPart") or (enemyModel:WaitForChild("HumanoidRootPart", 2))

-- Carrega apenas o Stats direto deste inimigo (sem fallback genérico)
local BASE_STATS do
    local statsModule = enemyModel:FindFirstChild("Stats")
    if statsModule and statsModule:IsA("ModuleScript") then
        local ok, data = pcall(require, statsModule)
        if ok and type(data) == "table" then
            BASE_STATS = data
        end
    end
end
-- Anti-clump parameters
local FORMATION_RADIUS_MIN = 2.5
local FORMATION_RADIUS_MAX = 4.0
local SEPARATION_RADIUS = 3.5
local SEPARATION_FORCE = 2.0

-- (enemyModel/humanoid/root declarados acima)

if not root then return end

local lastHitTimes = setmetatable({}, { __mode = "k" }) -- key: Player -> last time

-- Each enemy keeps its own formation offset around the player to avoid everyone stacking same point
local angle = math.random() * math.pi * 2
local radius = FORMATION_RADIUS_MIN + math.random() * (FORMATION_RADIUS_MAX - FORMATION_RADIUS_MIN)
local formationOffset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius

local function isAlive(h)
	return h and h.Health > 0
end

local cachedDamage
local lastDamageCheck = 0
local DAMAGE_REFRESH_INTERVAL = 1.0 -- seconds; allows wave scaling attributes to update mid-run if ever modified

local function computeBaseDamage()
	-- Always derive from Stats.lua for base (BASE_STATS), fallback to stored BaseDamage attribute, then legacy Damage
	local base
	if BASE_STATS and typeof(BASE_STATS.Damage) == "number" and BASE_STATS.Damage > 0 then
		base = BASE_STATS.Damage
	else
		local attBase = enemyModel:GetAttribute("BaseDamage")
		if typeof(attBase) == "number" and attBase > 0 then
			base = attBase
		else
			local legacy = enemyModel:GetAttribute("Damage")
			if typeof(legacy) == "number" and legacy > 0 then
				base = legacy
			end
		end
	end
	base = base or DEFAULT_DAMAGE
	local mult = enemyModel:GetAttribute("DamageWaveMultiplier")
	if typeof(mult) ~= "number" or mult <= 0 then mult = 1 end
	return base * mult
end

local function getDamage(now)
	now = now or os.clock()
	if not cachedDamage or (now - lastDamageCheck) >= DAMAGE_REFRESH_INTERVAL then
		cachedDamage = computeBaseDamage()
		lastDamageCheck = now
	end
	return cachedDamage
end

-- Immediate refresh when WaveManager (or other code) changes Damage attribute
pcall(function()
	enemyModel:GetAttributeChangedSignal("Damage"):Connect(function()
		cachedDamage = computeBaseDamage()
		lastDamageCheck = os.clock()
	end)
end)

local function getInvTimeSeconds(player)
	-- Reads final stat 'invtime' from player.Stats (NumberValue)
	if not player then return 0 end
	local stats = player:FindFirstChild("Stats")
	if not stats then return 0 end
	local nv = stats:FindFirstChild("invtime")
	if nv and nv:IsA("NumberValue") then
		return math.max(0, nv.Value)
	end
	return 0
end

local function isInvulnerable(character, now)
	if not character then return false end
	local untilTs = character:GetAttribute("InvulnerableUntil")
	if typeof(untilTs) == "number" and now < untilTs then
		return true
	end
	return false
end

local running = true

-- Pause handling: fully freeze/unfreeze enemy on global pause
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
		-- Stop current motion
		pcall(function()
			humanoid:Move(Vector3.zero)
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end)
		if root and root:IsA("BasePart") then
			root.AssemblyLinearVelocity = Vector3.new()
			root.AssemblyAngularVelocity = Vector3.new()
		end
	else
		if pauseApplied then
			-- Restore prior settings
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

-- Stop when enemy dies or is removed
if humanoid then
	humanoid.Died:Connect(function()
		running = false
	end)
end

enemyModel.AncestryChanged:Connect(function(_, parent)
	if not parent then running = false end
end)

task.spawn(function()
	-- Two loops: one for movement/chase (less frequent), and one for contact damage (more frequent)
	-- Movement loop
end)

task.spawn(function()
	while running do
		if ReplicatedStorage:GetAttribute("GamePaused") then
			applyPauseState(true)
			task.wait(0.05)
			continue
		else
			applyPauseState(false)
		end
		-- Determine desired move speed from attributes/stats
		local moveSpeed = enemyModel:GetAttribute("MoveSpeed")
		if typeof(moveSpeed) ~= "number" or moveSpeed <= 0 then
			-- Fallback to Humanoid.WalkSpeed if not provided
			moveSpeed = (humanoid and humanoid.WalkSpeed) or 16
		end
		if humanoid then humanoid.WalkSpeed = moveSpeed end

		-- Find nearest alive player to chase
		local bestPlr, bestDist, bestPos
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local phum = char and char:FindFirstChildOfClass("Humanoid")
			local proot = char and char:FindFirstChild("HumanoidRootPart")
			if proot and phum and phum.Health > 0 then
				local d = (proot.Position - root.Position).Magnitude
				if not bestDist or d < bestDist then
					bestDist = d
					bestPlr = plr
					bestPos = proot.Position
				end
			end
		end

		if bestPos and humanoid then
			-- Separation steering from nearby enemies to reduce clumping
			local sep = Vector3.zero
			local processed = 0
			for _, other in ipairs(CollectionService:GetTagged("Enemy")) do
				if other ~= enemyModel and other.Parent then
					local oroot = other.PrimaryPart or other:FindFirstChild("HumanoidRootPart")
					if oroot then
						local delta = root.Position - oroot.Position
						local dist = delta.Magnitude
						if dist > 0.001 and dist < SEPARATION_RADIUS then
							local push = (SEPARATION_RADIUS - dist) / SEPARATION_RADIUS
							sep += (delta.Unit * push)
							processed += 1
							if processed >= 10 then break end -- cap cost
						end
					end
				end
			end
			if sep.Magnitude > 0 then
				sep = sep.Unit * SEPARATION_FORCE
			end

			-- Target a position around the player instead of exact center
			local desired = bestPos + formationOffset + sep
			humanoid:MoveTo(desired)
		end

		task.wait(0.25) -- update path/target 4x per second
	end
end)

task.spawn(function()
	while running do
		if ReplicatedStorage:GetAttribute("GamePaused") then
			applyPauseState(true)
			task.wait(0.05)
			continue
		else
			applyPauseState(false)
		end
		-- Contact damage loop
		local now = os.clock()
		local epos = root.Position
		local dmg = getDamage(now)

		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local phum = char and char:FindFirstChildOfClass("Humanoid")
			local proot = char and char:FindFirstChild("HumanoidRootPart")
			if proot and isAlive(phum) then
				local dist = (proot.Position - epos).Magnitude
				if dist <= RANGE then
					-- Global invulnerability window based on player's final stat 'invtime'
					if isInvulnerable(char, now) then
						continue
					end
					local last = lastHitTimes[plr] or 0
					if now - last >= COOLDOWN then
						lastHitTimes[plr] = now
						phum:TakeDamage(dmg)
						-- Apply invulnerability frames
						local invs = getInvTimeSeconds(plr)
						if invs > 0 then
							char:SetAttribute("InvulnerableUntil", now + invs)
						end
					end
				end
			end
		end
		task.wait(0.1)
	end
end)

-- REGEN REAPER UNIQUE: Health regeneration loop (affected by DOT heal reduction)
task.spawn(function()
	while running do
		if ReplicatedStorage:GetAttribute("GamePaused") then
			task.wait(0.05)
			continue
		end
		
		if humanoid and isAlive(humanoid) then
			local regenRate = (BASE_STATS and BASE_STATS.HealthRegen) or 25
			local healReduction = enemyModel:GetAttribute("HealReduction") or 0
			local actualRegen = regenRate * (1 - healReduction)
			
			if actualRegen > 0 then
				humanoid.Health = math.min(humanoid.Health + actualRegen, humanoid.MaxHealth)
			end
		end
		
		task.wait(1) -- regen every second
	end
end)

return true
