-- SeriousPunch.lua
-- Saitama's ultimate ability - hits ALL enemies on the map
-- Deals 1000% of player's total damage. (Test cooldown: every 5 seconds)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local def = {
	Name = "Serious Punch",
	Rarity = "Legendary",
	Type = "Active",
	MaxLevel = 1,
	-- Mark as unique so CardPool will stop offering it after chosen once
	unique = true,
	Description = "One serious punch that hits ALL enemies on the map."
}

-- Track active Serious Punch per player
local ActivePunchByUserId = {}

-- Execute Serious Punch - damage ALL enemies
local Damage = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("Damage"))
local DamageNumbers = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("DamageNumbers"))
local SFXHelper = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("SFXHelper"))
local SERIOUS_PUNCH_SFX_ID = 101127853379229

-- Helper: try to find Saitama assets (Fist and ShockWave) under Shared/Chars/Saitama* folders
local function findSaitamaAsset(name)
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	if not shared then return nil end
	local chars = shared:FindFirstChild("Chars")
	if not chars then return nil end
	for _, child in ipairs(chars:GetChildren()) do
		if type(child.Name) == "string" and (string.find(child.Name:lower(), "saitama") or string.find(child.Name:lower(), "saitama_")) then
			local asset = child:FindFirstChild(name) or child:FindFirstChild(name:lower()) or child:FindFirstChild(name:upper())
			if asset then return asset end
			-- try deeper search
			local found = child:FindFirstChild(name, true)
			if found then return found end
		end
	end
	return nil
end

local function safeCloneModel(model)
	if not model then return nil end
	local ok, clone = pcall(function() return model:Clone() end)
	if ok and clone then return clone end
	return nil
end

local function scaleModelAnimated(model, startScale, endScale, duration)
	if not model then return end
	duration = duration or 1
	-- collect base parts and their original sizes/offsets relative to PrimaryPart
	local primary = model.PrimaryPart or (model:FindFirstChildWhichIsA("BasePart") )
	if not primary then return end
	local originals = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			originals[part] = {Size = part.Size, CFrame = part.CFrame}
		end
	end
	local startTime = tick()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local now = tick()
		local t = math.clamp((now - startTime) / duration, 0, 1)
		local s = startScale + (endScale - startScale) * t
		for part, info in pairs(originals) do
			if part and part.Parent then
				-- Scale size (approximate)
				local newSize = info.Size * s
				part.Size = newSize
				-- Reposition relative to primary
				if primary and primary.Parent then
					local rel = info.CFrame:ToObjectSpace(primary.CFrame)
					part.CFrame = primary.CFrame * CFrame.new(rel.Position * s)
				end
			end
		end
		if t >= 1 then
			conn:Disconnect()
		end
	end)
end

local function moveDownAndImpact(modelInstance, startPos, maxDistance, speed, ignoreInst)
	-- returns impactPosition or nil
	if not modelInstance then return nil end
	local currentPos = startPos
	local step = 0.02
	local rcParams = RaycastParams.new()
	rcParams.FilterType = Enum.RaycastFilterType.Exclude
	rcParams.FilterDescendantsInstances = { modelInstance }
	if ignoreInst then
		for _, v in ipairs(ignoreInst) do table.insert(rcParams.FilterDescendantsInstances, v) end
	end
	local traveled = 0
	while traveled < (maxDistance or 500) and modelInstance.Parent do
		local dt = step
		local moveDist = (speed or 120) * dt
		local rayResult = workspace:Raycast(currentPos, Vector3.new(0, - (moveDist + 0.5), 0), rcParams)
		if rayResult then
			local hitPos = rayResult.Position
			-- move model to just above hit and return
			if modelInstance:IsA("Model") and modelInstance.PrimaryPart then
				local targetCFrame = CFrame.new(hitPos + Vector3.new(0, 2, 0), hitPos + Vector3.new(0, 1, 0))
				modelInstance:PivotTo(targetCFrame)
			elseif modelInstance:IsA("BasePart") then
				modelInstance.CFrame = CFrame.new(hitPos + Vector3.new(0, 2, 0), hitPos + Vector3.new(0, 1, 0))
			end
			return hitPos
		else
			-- advance
			currentPos = currentPos + Vector3.new(0, -moveDist, 0)
			traveled = traveled + moveDist
			if modelInstance:IsA("Model") and modelInstance.PrimaryPart then
				modelInstance:PivotTo(CFrame.new(currentPos, currentPos + Vector3.new(0, -1, 0)))
			elseif modelInstance:IsA("BasePart") then
				modelInstance.CFrame = CFrame.new(currentPos, currentPos + Vector3.new(0, -1, 0))
			end
			task.wait(dt)
		end
	end
	return nil
end

local function executeSeriousPunch(player)
	-- Get player damage from Stats folder
	local playerStats = player:FindFirstChild("Stats")
	local baseDamage = 10
	if playerStats then
		local dmgValue = playerStats:FindFirstChild("BaseDamage")
		if dmgValue and dmgValue:IsA("NumberValue") then
			baseDamage = dmgValue.Value
		end
	end
	local punchDamage = baseDamage * 10.0 -- 1000%

	-- Determine impact origin (above player's HumanoidRootPart)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
	if not hrp then return end
	local origin = hrp.Position

	-- Find assets
	local fistSource = findSaitamaAsset("Fist") or findSaitamaAsset("fist")
	local shockSource = findSaitamaAsset("ShockWave") or findSaitamaAsset("Shockwave") or findSaitamaAsset("shockwave")

	-- Spawn fist high above (increase for more dramatic fall)
	local spawnHeight = 150
	local startPos = origin + Vector3.new(0, spawnHeight, 0)
	local fist
	if fistSource then
		fist = safeCloneModel(fistSource)
	else
		-- fallback: simple neon part
		local p = Instance.new("Part")
		p.Name = "SeriousFist"
		p.Size = Vector3.new(6, 20, 6)
		p.Color = Color3.fromRGB(255, 200, 160)
		p.Material = Enum.Material.Neon
		p.Anchored = true
		fist = p
	end
	if fist then
		if fist:IsA("Model") and not fist.PrimaryPart then
			local pp = fist:FindFirstChildWhichIsA("BasePart")
			if pp then fist.PrimaryPart = pp end
		end
		-- orient fist to face downward using lookAt so it's aligned to -Y
		local initialCFrame = CFrame.new(startPos, startPos + Vector3.new(0, -1, 0))
		if fist:IsA("Model") then
			fist.Parent = workspace
			fist:PivotTo(initialCFrame)
		else
			fist.Parent = workspace
			fist.CFrame = initialCFrame
		end
	end

	-- Move fist down until impact (slower speed for dramatic effect)
	local impactPos = moveDownAndImpact(fist, startPos, 1000, 37.5, { char })
	if not impactPos then
		-- cleanup and return
		if fist and fist.Parent then fist:Destroy() end
		return
	end

	-- Spawn shockwave at impact
	local shock
	if shockSource then
		shock = safeCloneModel(shockSource)
		if shock then
			if shock:IsA("Model") and not shock.PrimaryPart then
				local pp = shock:FindFirstChildWhichIsA("BasePart")
				if pp then shock.PrimaryPart = pp end
			end
			shock.Parent = workspace
			if shock:IsA("Model") then
				shock:SetPrimaryPartCFrame(CFrame.new(impactPos))
			else
				shock.CFrame = CFrame.new(impactPos)
			end
		end
	else
		local ring = Instance.new("Part")
		ring.Name = "ShockWave"
		ring.Size = Vector3.new(2, 0.5, 2)
		ring.Anchored = true
		ring.CanCollide = false
		ring.Transparency = 0.25
		ring.Color = Color3.fromRGB(255, 220, 160)
		ring.Parent = workspace
		ring.CFrame = CFrame.new(impactPos)
		shock = ring
	end

	-- Apply damage to all enemies (server-authoritative)
	-- SFX no impacto
	do
		local impactPart = Instance.new("Part")
		impactPart.Anchored = true
		impactPart.CanCollide = false
		impactPart.Transparency = 1
		impactPart.Size = Vector3.new(1, 1, 1)
		impactPart.Position = impactPos
		impactPart.Parent = workspace
		SFXHelper.playAt(impactPart, SERIOUS_PUNCH_SFX_ID, 1, { minDist = 30, maxDist = 300, lifetime = 5 })
		task.delay(6, function() pcall(function() impactPart:Destroy() end) end)
	end

	local enemiesHit = 0
	for _, enemy in ipairs(CollectionService:GetTagged("Enemy")) do
		if enemy and enemy:IsA("Model") then
			local hum = enemy:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				pcall(function() Damage.Apply(hum, punchDamage) end)
				enemiesHit = enemiesHit + 1
				-- show damage number at enemy position
				local pos
				local ok, cf = pcall(function() return enemy:GetPivot() end)
				if ok and typeof(cf) == "CFrame" then
					pos = cf.Position
				else
					local hrpE = enemy:FindFirstChild("HumanoidRootPart") or enemy.PrimaryPart
					pos = hrpE and hrpE.Position or impactPos
				end
				if pos then
					DamageNumbers.Show({ position = pos, amount = punchDamage, damageType = "crit" })
				end
			end
		end
	end

	print(string.format("[Serious Punch] Player %s punched %d enemies for %.0f damage each at %s",
		player.Name, enemiesHit, punchDamage, tostring(impactPos)
	))

	-- Animate shockwave scale up and cleanup
	if shock then
		-- try to scale from small to target over ~1 second
		task.spawn(function()
			local duration = 1.0
			-- If model, animate parts sizes relative to primary
			if shock:IsA("Model") then
				-- scale much larger for dramatic effect
				scaleModelAnimated(shock, 0.05, 8.0, duration)
			else
				-- tween transparency and grow to a large radius
				local goal = { Size = Vector3.new(240, 0.5, 240), Transparency = 1 }
				local tween = TweenService:Create(shock, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
				tween:Play()
			end
			task.wait(duration + 0.05)
			if shock and shock.Parent then shock:Destroy() end
		end)
	end

	-- Clean up fist
	if fist and fist.Parent then fist:Destroy() end
end

-- Auto-punch loop
local function startPunchLoop(player)
	local cooldown = 90 -- seconds (locked)
	
	local thread = task.spawn(function()
		while true do
			-- Wait for cooldown
			task.wait(cooldown)
			
			-- Check if player still has the card
			if not ActivePunchByUserId[player.UserId] then
				break
			end
			
			-- Respect pause
			while ReplicatedStorage:GetAttribute("GamePaused") do
				task.wait(0.1)
			end
			
			-- Check if player still exists
			if not player.Parent or not player.Character then
				break
			end
			
			-- Execute punch
			executeSeriousPunch(player)
		end
	end)
	
	return thread
end

function def.OnCardAdded(player: Player, cardData, currentLevel: number)
	-- Locked: only unlocked when SeriousTrainingLevel >= 10
	local stLevel = player:GetAttribute("SeriousTrainingLevel")
	if not (type(stLevel) == "number" and stLevel >= 10) then
		warn(string.format("[Serious Punch] Player %s tried to add Serious Punch without SeriousTraining Level 10! (has %s)", player.Name, tostring(stLevel)))
		return
	end
	
	-- Cancel old thread if re-adding
	if ActivePunchByUserId[player.UserId] then
		local oldData = ActivePunchByUserId[player.UserId]
		if oldData.thread then
			task.cancel(oldData.thread)
		end
	end
	
	-- Start auto-punch loop
	local thread = startPunchLoop(player)
	
	ActivePunchByUserId[player.UserId] = {
		thread = thread
	}

	-- Ensure RunTrack level is recorded (make card behave like other levelable cards)
	local runTrack = player:FindFirstChild("RunTrack") or Instance.new("Folder")
	runTrack.Name = "RunTrack"
	runTrack.Parent = player
	local spFolder = runTrack:FindFirstChild("SeriousPunch") or Instance.new("Folder")
	spFolder.Name = "SeriousPunch"
	spFolder.Parent = runTrack
	local lvl = spFolder:FindFirstChild("Level") or Instance.new("IntValue")
	lvl.Name = "Level"
	lvl.Parent = spFolder
	local maxLevel = (typeof(def.MaxLevel) == "number" and def.MaxLevel) or 1
	lvl.Value = math.min(maxLevel, (lvl.Value or 0) + 1)
	
	-- Execute first punch immediately
	task.delay(1, function()
		if ActivePunchByUserId[player.UserId] then
			executeSeriousPunch(player)
		end
	end)
	
	print(string.format("[Serious Punch] Player %s activated Serious Punch!", player.Name))
end

function def.OnCardRemoved(player: Player, cardData)
	local data = ActivePunchByUserId[player.UserId]
	if not data then return end
	
	-- Cancel auto-punch thread
	if data.thread then
		task.cancel(data.thread)
	end
	
	-- Cleanup
	ActivePunchByUserId[player.UserId] = nil
	
	print(string.format("[Serious Punch] Player %s deactivated Serious Punch", player.Name))
end

-- Cleanup on player leaving
game:GetService("Players").PlayerRemoving:Connect(function(player)
	local data = ActivePunchByUserId[player.UserId]
	if data and data.thread then
		task.cancel(data.thread)
	end
	ActivePunchByUserId[player.UserId] = nil
end)

return def
