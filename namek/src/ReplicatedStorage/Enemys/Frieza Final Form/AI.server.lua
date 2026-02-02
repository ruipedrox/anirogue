-- Frieza Final Form AI: Ranged boss that fires Death Beam laser from finger
-- The Death Beam is a special laser effect composed of 3 parts that animate out

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")
local CombatFolder = ScriptsFolder:WaitForChild("Combat")
local Damage = require(CombatFolder:WaitForChild("Damage"))
local Projectile = require(ScriptsFolder:WaitForChild("Projectile"))

-- Find Death_beam, destructo_disk, and Super_nova models from Enemys/Attacks folder
local EnemysFolder = ReplicatedStorage:WaitForChild("Enemys")
local AttacksFolder = EnemysFolder:FindFirstChild("Attacks")
local deathBeamModel = AttacksFolder and AttacksFolder:FindFirstChild("Death_beam")
local destructoDiskModel = AttacksFolder and AttacksFolder:FindFirstChild("destructo_disk")
local superNovaModel = AttacksFolder and AttacksFolder:FindFirstChild("Super_nova")

if not deathBeamModel then
	warn("[Frieza] Death_beam model not found in ReplicatedStorage/Enemys/Attacks folder")
	return
end

if not destructoDiskModel then
	warn("[Frieza] destructo_disk model not found in ReplicatedStorage/Enemys/Attacks folder")
end

if not superNovaModel then
	warn("[Frieza] Super_nova model not found in ReplicatedStorage/Enemys/Attacks folder")
end

local enemyModel = script.Parent
local humanoid = enemyModel:FindFirstChildOfClass("Humanoid") or enemyModel:WaitForChild("Humanoid", 2)
local root = enemyModel.PrimaryPart or enemyModel:FindFirstChild("HumanoidRootPart") or (enemyModel:WaitForChild("HumanoidRootPart", 2))

if not root or not humanoid then return end

-- Find LeftHand and RightHand attachments
local leftHand = enemyModel:FindFirstChild("LeftHand", true)
local rightHand = enemyModel:FindFirstChild("RightHand", true)
local leftAttachment, rightAttachment

if leftHand then
	leftAttachment = leftHand:FindFirstChild("LeftGripAttachment") or leftHand:FindFirstChild("LeftWristRigAttachment")
end

if rightHand then
	rightAttachment = rightHand:FindFirstChild("RightGripAttachment") or rightHand:FindFirstChild("RightWristRigAttachment")
end

if not leftAttachment then
	warn("[Frieza] LeftHand attachment not found; attacks will not work properly")
end

if not rightAttachment then
	warn("[Frieza] RightHand attachment not found; Destructo Disc will not work")
end

-- Load Animations
local attackAnim
local deathBeamAnim
local destructoDiscAnim
local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end

local animFolder = enemyModel:FindFirstChild("Animation")
if animFolder then
	local anim = animFolder:FindFirstChild("Normal")
	if anim and anim:IsA("Animation") then
		attackAnim = animator:LoadAnimation(anim)
		attackAnim.Priority = Enum.AnimationPriority.Action
		attackAnim.Looped = false
	end
	
	local dbAnim = animFolder:FindFirstChild("death_beam")
	if dbAnim and dbAnim:IsA("Animation") then
		deathBeamAnim = animator:LoadAnimation(dbAnim)
		deathBeamAnim.Priority = Enum.AnimationPriority.Action
		deathBeamAnim.Looped = false
	end
	
	local ddAnim = animFolder:FindFirstChild("destructo_disc")
	if ddAnim and ddAnim:IsA("Animation") then
		destructoDiscAnim = animator:LoadAnimation(ddAnim)
		destructoDiscAnim.Priority = Enum.AnimationPriority.Action
		destructoDiscAnim.Looped = false
	end
	
	local snAnim = animFolder:FindFirstChild("super_nova")
	if snAnim and snAnim:IsA("Animation") then
		superNovaAnim = animator:LoadAnimation(snAnim)
		superNovaAnim.Priority = Enum.AnimationPriority.Action
		superNovaAnim.Looped = false
		print("[Frieza] Super Nova animation loaded!")
	else
		warn("[Frieza] Super Nova animation NOT found!")
	end
end

print("[Frieza] superNovaModel=", superNovaModel, "superNovaAnim=", superNovaAnim)

-- Load local Stats module
local STATS do
	local statsModule = enemyModel:FindFirstChild("Stats")
	if statsModule and statsModule:IsA("ModuleScript") then
		local ok, data = pcall(require, statsModule)
		if ok and type(data) == "table" then STATS = data end
	end
end

local ATTACK_COOLDOWN = (STATS and STATS.AttackCooldown) or 1.5
local ATTACK_RANGE = (STATS and STATS.AttackRange) or 60
local DAMAGE = (STATS and STATS.Damage) or 150
local BARRAGE_DAMAGE = DAMAGE * 0.5 -- Reduced damage for barrage attack
local PROJECTILE_SIZE = (STATS and STATS.ProjectileSize) or 3
local CONE_ANGLE = 15 -- Cone angle in degrees for barrage attack
local CONE_RANGE = 50 -- Range of cone damage

local running = true
local pauseApplied = false
local savedWalkSpeed, savedJumpPower, savedAutoRotate
local activeBeams = {} -- Track active laser beams for cleanup
local activeConeBeams = {} -- Track cone beams for barrage attack
local activeDiscs = {} -- Track destructo discs for cleanup
local activeTweens = {} -- Track active tweens to cancel on death
local isAttacking = false -- Lock rotation during attack
local isBarraging = false -- Slow rotation during barrage

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
			humanoid.WalkSpeed = savedWalkSpeed or 0
			humanoid.JumpPower = savedJumpPower or 50
			humanoid.AutoRotate = (savedAutoRotate == nil) and true or savedAutoRotate
			pcall(function()
				humanoid:ChangeState(Enum.HumanoidStateType.Running)
			end)
			pauseApplied = false
		end
	end
end

-- Cleanup function for when Frieza dies
local function cleanup()
	running = false
	print("[Frieza] Cleanup called - destroying all beams")
	print("[Frieza] Active normal beams:", #activeBeams)
	print("[Frieza] Active cone beams:", #activeConeBeams)
	
	-- Cancel all active tweens
	for _, tween in ipairs(activeTweens) do
		pcall(function() tween:Cancel() end)
	end
	activeTweens = {}
	
	-- Destroy all active beams (Normal attack)
	for i, beamData in ipairs(activeBeams) do
		print("[Frieza] Destroying normal beam", i)
		if beamData.beam then pcall(function() beamData.beam:Destroy() end) end
		if beamData.beamIn then pcall(function() beamData.beamIn:Destroy() end) end
		if beamData.beamPart then pcall(function() beamData.beamPart:Destroy() end) end
	end
	activeBeams = {}
	
	-- Destroy all cone beams (Barrage attack) - SAME METHOD AS NORMAL ATTACK
	for i, beamData in ipairs(activeConeBeams) do
		print("[Frieza] Destroying cone beam", i, "has beam:", beamData.beam ~= nil, "has beamIn:", beamData.beamIn ~= nil, "has beamPart:", beamData.beamPart ~= nil)
		if beamData.beam then 
			local success = pcall(function() beamData.beam:Destroy() end)
			print("[Frieza] Destroyed beam model:", success)
		end
		if beamData.beamIn then 
			local success = pcall(function() beamData.beamIn:Destroy() end)
			print("[Frieza] Destroyed beamIn:", success)
		end
		if beamData.beamPart then 
			local success = pcall(function() beamData.beamPart:Destroy() end)
			print("[Frieza] Destroyed beamPart:", success)
		end
	end
	activeConeBeams = {}
	
	-- Destroy all destructo discs
	-- Note: Projectile system handles cleanup automatically
	activeDiscs = {}
	
	print("[Frieza] Cleanup completed")
end

print("[Frieza] Setting up cleanup events for:", enemyModel.Name)
if humanoid then 
	print("[Frieza] Humanoid found, connecting Died event")
	humanoid.Died:Connect(function()
		print("[Frieza] Humanoid.Died event triggered!")
		cleanup()
	end)
	
	-- Additional health check for when Died event doesn't fire
	humanoid.HealthChanged:Connect(function(health)
		if health <= 0 then
			print("[Frieza] HealthChanged to 0 - triggering cleanup")
			cleanup()
		end
	end)
	
	-- Check when humanoid is being removed
	humanoid.AncestryChanged:Connect(function(_, parent)
		if not parent then
			print("[Frieza] Humanoid removed from parent - triggering cleanup")
			cleanup()
		end
	end)
else
	warn("[Frieza] No humanoid found!")
end

enemyModel.AncestryChanged:Connect(function(_, parent) 
	if not parent then 
		print("[Frieza] AncestryChanged (removed from workspace)")
		cleanup()
	end 
end)

-- Rotation loop: Face nearest player
task.spawn(function()
	while running do
		if ReplicatedStorage:GetAttribute("GamePaused") then
			applyPauseState(true)
			task.wait(0.05)
			continue
		else
			applyPauseState(false)
		end

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

		if bestRoot and not isAttacking then
			humanoid:Move(Vector3.zero)
			local lookDir = (bestRoot.Position - root.Position) * Vector3.new(1, 0, 1)
			if lookDir.Magnitude > 0.001 then
				-- Smooth rotation: slow for barrage (0.08), normal for everything else (0.3)
				local lerpSpeed = isBarraging and 0.08 or 0.3
				local targetCF = CFrame.new(root.Position, root.Position + lookDir.Unit)
				root.CFrame = root.CFrame:Lerp(targetCF, lerpSpeed)
			end
		end

		task.wait(0.05)
	end
end)

-- Death Beam attack function
local function fireDeathBeam(targetPos)
	if not leftAttachment then return end
	
	-- Clone Death_beam model
	local beam = deathBeamModel:Clone()
	local beamPart = beam:FindFirstChild("Part", true)
	local beamIn = beam:FindFirstChild("Beam_in", true)
	
	if not beamPart or not beamIn then
		warn("[Frieza] Death_beam missing parts (Part, Beam_in)")
		warn("Found parts:", beamPart, beamIn)
		beam:Destroy()
		return
	end
	
	-- Track this beam for cleanup
	local beamData = {beam = beam, beamPart = beamPart, beamIn = beamIn}
	table.insert(activeBeams, beamData)
	
	-- Position Part at the attachment (finger tip)
	local startPos = leftAttachment.WorldPosition
	-- Ignore Y component to keep laser horizontal (top-down view)
	local targetFlat = Vector3.new(targetPos.X, startPos.Y, targetPos.Z)
	local direction = (targetFlat - startPos).Unit
	
	-- Weld Part to attachment so it follows hand
	beamPart.CFrame = CFrame.new(startPos, startPos + direction)
	beamPart.Parent = workspace
	
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = leftHand
	weld.Part1 = beamPart
	weld.Parent = beamPart
	
	-- Setup beam_in (preserve original size for width/height)
	local beamInOriginalSize = beamIn.Size
	
	beamIn.Size = Vector3.new(0.1, beamInOriginalSize.Y, beamInOriginalSize.Z)
	-- Start at finger tip, rotated to point along beam direction
	beamIn.CFrame = CFrame.new(startPos, startPos + direction) * CFrame.Angles(0, math.rad(90), 0)
	beamIn.Parent = workspace
	
	-- Use fixed beam length based on ATTACK_RANGE
	local beamLength = ATTACK_RANGE
	
	-- Animate beam extending forward (0.1s for fast stretch)
	-- Beam_in extends to full beam length
	local extendTime = 0.1
	
	-- As part extends, its center moves forward (half of final length)
	local beamInGoal = {
		Size = Vector3.new(beamLength, beamInOriginalSize.Y, beamInOriginalSize.Z),
		CFrame = CFrame.new(startPos + direction * (beamLength / 2), startPos + direction * beamLength) * CFrame.Angles(0, math.rad(90), 0)
	}
	
	local tweenInfo = TweenInfo.new(extendTime, Enum.EasingStyle.Linear)
	local tweenIn = TweenService:Create(beamIn, tweenInfo, beamInGoal)
	
	tweenIn:Play()
	
	-- Apply damage along the beam path
	task.wait(extendTime * 0.5) -- Damage mid-animation
	
	local hitModels = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local charRoot = char and char:FindFirstChild("HumanoidRootPart")
		if charRoot and hum and hum.Health > 0 then
			-- Check if player is close to beam path
			local toPlayer = charRoot.Position - startPos
			local alongBeam = toPlayer:Dot(direction)
			if alongBeam >= 0 and alongBeam <= beamLength then
				local closestPoint = startPos + direction * alongBeam
				local distToBeam = (charRoot.Position - closestPoint).Magnitude
				if distToBeam <= PROJECTILE_SIZE * 1.5 then
					Damage.Apply(hum, DAMAGE)
					table.insert(hitModels, char)
				end
			end
		end
	end
	
	-- Keep beam visible briefly (total duration ~0.15s)
	task.wait(0.05)
	if beam then beam:Destroy() end
	if beamIn then beamIn:Destroy() end
	if beamPart then beamPart:Destroy() end
	
	-- Remove from active beams list
	for i = #activeBeams, 1, -1 do
		if activeBeams[i] == beamData then
			table.remove(activeBeams, i)
			break
		end
	end
end

-- Check if a position is inside the cone in front of Frieza
local function isInCone(targetPos)
	if not root or not leftAttachment then return false end
	
	local startPos = leftAttachment.WorldPosition
	local forward = root.CFrame.LookVector
	
	-- Flatten to horizontal plane
	forward = Vector3.new(forward.X, 0, forward.Z).Unit
	local toTarget = (targetPos - startPos) * Vector3.new(1, 0, 1)
	
	local distance = toTarget.Magnitude
	if distance > CONE_RANGE or distance < 0.1 then return false end
	
	local direction = toTarget.Unit
	local dotProduct = forward:Dot(direction)
	local angleRadians = math.acos(math.clamp(dotProduct, -1, 1))
	local angleDegrees = math.deg(angleRadians)
	
	return angleDegrees <= CONE_ANGLE
end

-- Fire death beam barrage (multiple lasers in random directions within cone)
local function fireDeathBeamBarrage()
	if not running or not leftAttachment or not leftHand then return end
	
	-- Damage loop: continuously damage players inside cone
	local damageActive = true
	local damageThread = task.spawn(function()
		local startTime = os.clock()
		while damageActive and running and os.clock() - startTime < 1.5 do
			if not running then break end -- Check if Frieza died
			
			-- Check all players
			for _, plr in ipairs(Players:GetPlayers()) do
				local char = plr.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local r = char and char:FindFirstChild("HumanoidRootPart")
				
				if r and hum and hum.Health > 0 and isInCone(r.Position) then
					-- Apply reduced damage for barrage
					pcall(function()
						Damage.Apply(hum, BARRAGE_DAMAGE)
					end)
				end
			end
			
			task.wait(0.1)
		end
		damageActive = false
	end)
	
	-- Spawn random lasers within cone between 1s and 2.5s of animation (1.5s duration)
	local spawnActive = true
	task.spawn(function()
		local startTime = os.clock()
		while spawnActive and running and os.clock() - startTime < 1.5 do
			-- Spawn 2-3 lasers per iteration for more coverage
			local lasersToSpawn = math.random(2, 3)
			
			for i = 1, lasersToSpawn do
				if not running then break end
				
				-- Create a laser in random direction within cone
				local beamClone = deathBeamModel:Clone()
				local part = beamClone:FindFirstChild("Part", true)
				local beam_in = beamClone:FindFirstChild("Beam_in", true)
				
				if not part or not beam_in then
					beamClone:Destroy()
					continue
				end
				
				-- Random angle within cone using uniform distribution
				local randomAngle = math.rad((math.random() * 2 - 1) * CONE_ANGLE)
				
				-- Position at hand
				beamClone.Parent = workspace
				
				part.Position = leftAttachment.WorldPosition
				
				-- Weld to hand so it follows Frieza's rotation (like Normal attack)
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = leftHand
				weld.Part1 = part
				weld.Parent = part
				
				-- Store original size
				local originalSize = beam_in.Size
				beam_in.Size = Vector3.new(0.1, originalSize.Y, originalSize.Z)
				
				-- Calculate random direction within cone relative to Frieza's current facing
				local forward = root.CFrame.LookVector
				forward = Vector3.new(forward.X, 0, forward.Z).Unit
				
				-- Apply random cone angle
				local right = Vector3.new(-forward.Z, 0, forward.X)
				local randomDir = (forward + right * math.tan(randomAngle)).Unit
				
				-- Position beam parts
				local beamLength = CONE_RANGE
				local midpoint = leftAttachment.WorldPosition + randomDir * (beamLength / 2)
				
				beam_in.CFrame = CFrame.new(midpoint, midpoint + randomDir) * CFrame.Angles(0, math.rad(90), 0)
				
				-- Track for cleanup (same structure as Normal attack)
				local beamData = { beam = beamClone, beamPart = part, beamIn = beam_in }
				table.insert(activeConeBeams, beamData)
				
				-- Animate laser extending
				local extendTime = 0.08
				local tweenInfo = TweenInfo.new(extendTime, Enum.EasingStyle.Linear)
				local goal = { Size = Vector3.new(beamLength, originalSize.Y, originalSize.Z) }
				local tween = TweenService:Create(beam_in, tweenInfo, goal)
				table.insert(activeTweens, tween) -- Track tween for cleanup
				tween:Play()
				
				-- Destroy after brief display (same as Normal attack)
				task.delay(0.2, function()
					if beamClone then beamClone:Destroy() end
					if beam_in then beam_in:Destroy() end
					if part then part:Destroy() end
					
					-- Remove from activeConeBeams tracking
					for j = #activeConeBeams, 1, -1 do
						if activeConeBeams[j] == beamData then
							table.remove(activeConeBeams, j)
							break
						end
					end
				end)
			end
			
			-- Spawn rate (about 25-30 lasers per second)
			task.wait(0.05)
		end
		spawnActive = false
	end)
end

-- Destructo Disc attack function
local function fireDestructoDisc(targetPos)
	if not destructoDiskModel or not leftAttachment or not rightAttachment then 
		warn("[Frieza] Cannot fire Destructo Disc - missing model or attachments")
		return 
	end
	
	isAttacking = true -- Lock rotation during disc attack
	
	-- Clone discs for both hands
	local leftDisc = destructoDiskModel:Clone()
	local rightDisc = destructoDiskModel:Clone()
	
	-- Find the main part of each disc
	local leftPart = leftDisc:IsA("BasePart") and leftDisc or leftDisc:FindFirstChildWhichIsA("BasePart", true)
	local rightPart = rightDisc:IsA("BasePart") and rightDisc or rightDisc:FindFirstChildWhichIsA("BasePart", true)
	
	if not leftPart or not rightPart then
		warn("[Frieza] Destructo disc has no BasePart")
		leftDisc:Destroy()
		rightDisc:Destroy()
		isAttacking = false
		return
	end
	
	-- Start fully transparent (will fade in)
	for _, desc in ipairs(leftDisc:GetDescendants()) do
		if desc:IsA("BasePart") then desc.Transparency = 1 end
	end
	for _, desc in ipairs(rightDisc:GetDescendants()) do
		if desc:IsA("BasePart") then desc.Transparency = 1 end
	end
	
	-- Parent to workspace
	leftDisc.Parent = workspace
	rightDisc.Parent = workspace
	
	-- Keep anchored and non-collidable until launch
	leftPart.CanCollide = false
	rightPart.CanCollide = false
	leftPart.Anchored = true
	rightPart.Anchored = true
	
	-- Position discs at attachments with 90 degree rotation
	leftPart.CFrame = leftAttachment.WorldCFrame * CFrame.Angles(0, math.rad(90), 0)
	rightPart.CFrame = rightAttachment.WorldCFrame * CFrame.Angles(0, math.rad(90), 0)
	
	-- Track discs (no weld, we'll update position manually)
	local leftDiscData = { disc = leftDisc }
	local rightDiscData = { disc = rightDisc }
	table.insert(activeDiscs, leftDiscData)
	table.insert(activeDiscs, rightDiscData)
	
	-- Left disc: fade in and follow left hand until 2 seconds
	local leftActive = true
	task.spawn(function()
		local startTime = tick()
		while leftActive and running and leftPart and leftPart.Parent do
			local elapsed = tick() - startTime
			
			-- Stop at 2 seconds (when disc launches)
			if elapsed >= 2 then break end
			
			-- Fade in during first second
			if elapsed < 1 then
				local alpha = elapsed
				local transparency = 1 - alpha
				
				for _, desc in ipairs(leftDisc:GetDescendants()) do
					if desc:IsA("BasePart") then desc.Transparency = transparency end
				end
			else
				-- Ensure fully visible
				for _, desc in ipairs(leftDisc:GetDescendants()) do
					if desc:IsA("BasePart") then desc.Transparency = 0 end
				end
			end
			
			-- Follow left hand attachment with 90 degree rotation
			if leftAttachment then
				leftPart.CFrame = leftAttachment.WorldCFrame * CFrame.Angles(0, math.rad(90), 0)
			end
			
			task.wait()
		end
	end)
	
	-- Right disc: fade in and follow right hand until 3 seconds
	local rightActive = true
	task.spawn(function()
		local startTime = tick()
		while rightActive and running and rightPart and rightPart.Parent do
			local elapsed = tick() - startTime
			
			-- Stop at 3 seconds (when disc launches)
			if elapsed >= 3 then break end
			
			-- Fade in during first second
			if elapsed < 1 then
				local alpha = elapsed
				local transparency = 1 - alpha
				
				for _, desc in ipairs(rightDisc:GetDescendants()) do
					if desc:IsA("BasePart") then desc.Transparency = transparency end
				end
			else
				-- Ensure fully visible
				for _, desc in ipairs(rightDisc:GetDescendants()) do
					if desc:IsA("BasePart") then desc.Transparency = 0 end
				end
			end
			
			-- Follow right hand attachment with 90 degree rotation
			if rightAttachment then
				rightPart.CFrame = rightAttachment.WorldCFrame * CFrame.Angles(0, math.rad(90), 0)
			end
			
			task.wait()
		end
	end)
	
	-- Launch left disc at 2 seconds
	task.delay(2, function()
		leftActive = false -- Stop follow loop
		if not running or not root then return end
		
		-- Get launch position and direction
		local launchPos = leftAttachment and leftAttachment.WorldPosition or (root.Position + Vector3.new(0, 2, 0))
		local direction = root.CFrame.LookVector
		
		-- Destroy visual disc on hand
		if leftDisc then leftDisc:Destroy() end
		
		-- Create projectile disc using Projectile.Fire (like Getsuga Tenshou)
		local projectileModel = destructoDiskModel:Clone()
		
		-- Make fully visible
		for _, desc in ipairs(projectileModel:GetDescendants()) do
			if desc:IsA("BasePart") then 
				desc.Transparency = 0
				desc.Anchored = true
				desc.CanCollide = false
				desc.CanQuery = false
				desc.CanTouch = false
			end
		end
		
		-- Fire using Projectile module
		Projectile.Fire({
			origin = launchPos,
			direction = direction,
			speed = 80,
			lifetime = 5,
			pierce = math.huge, -- Infinite pierce like Getsuga
			damage = DAMAGE * 0.8,
			owner = enemyModel,
			ignore = { enemyModel },
			model = projectileModel,
			orientationOffset = CFrame.Angles(0, 0, math.rad(90)), -- Rotate 90 degrees on Z axis (horizontal/lying down)
			contactRadius = 2,
			hitCooldownPerTarget = 0.5,
		})
	end)
	
	-- Launch right disc at 3 seconds
	task.delay(3, function()
		rightActive = false -- Stop follow loop
		if not running or not root then return end
		
		-- Get launch position and direction
		local launchPos = rightAttachment and rightAttachment.WorldPosition or (root.Position + Vector3.new(0, 2, 0))
		local direction = root.CFrame.LookVector
		
		-- Destroy visual disc on hand
		if rightDisc then rightDisc:Destroy() end
		
		-- Create projectile disc using Projectile.Fire (like Getsuga Tenshou)
		local projectileModel = destructoDiskModel:Clone()
		
		-- Make fully visible
		for _, desc in ipairs(projectileModel:GetDescendants()) do
			if desc:IsA("BasePart") then 
				desc.Transparency = 0
				desc.Anchored = true
				desc.CanCollide = false
				desc.CanQuery = false
				desc.CanTouch = false
			end
		end
		
		-- Fire using Projectile module
		Projectile.Fire({
			origin = launchPos,
			direction = direction,
			speed = 80,
			lifetime = 5,
			pierce = math.huge, -- Infinite pierce like Getsuga
			damage = DAMAGE * 0.8,
			owner = enemyModel,
			ignore = { enemyModel },
			model = projectileModel,
			orientationOffset = CFrame.Angles(0, 0, math.rad(90)), -- Rotate 90 degrees on Z axis (horizontal/lying down)
			contactRadius = 2,
			hitCooldownPerTarget = 0.5,
		})
	end)
end

-- Super Nova attack function: ultimate attack with massive AoE damage
local function fireSuperNova(targetPos)
	print("[Frieza] fireSuperNova called! running=", running, "superNovaModel=", superNovaModel)
	
	if not running or not superNovaModel then 
		warn("[Frieza] Aborting Super Nova - running or model missing")
		return 
	end
	
	print("[Frieza] Charging Super Nova!")
	
	-- Clone the Super Nova model (it's a Model with multiple parts)
	local superNova = superNovaModel:Clone()
	
	-- Keep scripts active - they handle the rotation animation
	
	-- Anchor all parts and make them non-collidable, store original sizes
	local originalSizes = {}
	for _, desc in ipairs(superNova:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
			originalSizes[desc] = desc.Size
		end
	end
	
	-- Position the model high above Frieza's head using PivotTo
	local startPos = root.Position + Vector3.new(0, 20, 0)
	if superNova:IsA("Model") then
		superNova:PivotTo(CFrame.new(startPos))
	else
		superNova.Position = startPos
	end
	superNova.Parent = workspace
	
	-- Store original scale (we'll use Model:ScaleTo for Models)
	local originalScale = 1
	
	-- Phase 1: Grow from scale 0.1 to 2.0 between 1.7s and 2.5s (0.8s duration)
	local startScale = 0.1
	local endScale = 2.0
	local growStart = 1.7
	local growEnd = 2.5
	local growDuration = growEnd - growStart
	
	-- Start invisible, will fade in during growth
	for _, desc in ipairs(superNova:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Transparency = 1
		end
	end
	
	-- Animation loop: grow the model and fade in
	local elapsed = 0
	
	task.spawn(function()
		while running and elapsed <= growEnd and superNova.Parent do
			elapsed = elapsed + task.wait()
			
			if elapsed >= growStart and elapsed <= growEnd then
				-- Calculate scale progress (0 to 1)
				local alpha = (elapsed - growStart) / growDuration
				local currentScale = startScale + (endScale - startScale) * alpha
				
				-- Apply scale to all parts individually
				for part, originalSize in pairs(originalSizes) do
					if part and part.Parent then
						part.Size = originalSize * currentScale
					end
				end
				
				-- Fade in: from transparent to visible
				for _, desc in ipairs(superNova:GetDescendants()) do
					if desc:IsA("BasePart") then
						desc.Transparency = 1 - alpha
					end
				end
				
				-- Keep position high above Frieza
				if root and superNova:IsA("Model") then
					superNova:PivotTo(CFrame.new(root.Position + Vector3.new(0, 20, 0)))
				end
			end
		end
		
		-- Final scale reached
		if running and superNova.Parent then
			for part, originalSize in pairs(originalSizes) do
				if part and part.Parent then
					part.Size = originalSize * endScale
				end
			end
		end
	end)
	
	-- Phase 2: At 3 seconds, snapshot player position and launch
	task.delay(3, function()
		if not running or not superNova.Parent then return end
		
		print("[Frieza] Launching Super Nova!")
		
		-- Snapshot target position (where player is at 3s)
		local snapshotPos = targetPos
		
		-- Create preview circle on the ground showing impact area
		local damageRadius = 35 -- Very large area
		local previewCircle = Instance.new("Part")
		previewCircle.Name = "SuperNovaPreview"
		previewCircle.Shape = Enum.PartType.Cylinder
		previewCircle.Size = Vector3.new(0.5, damageRadius * 2, damageRadius * 2)
		previewCircle.CFrame = CFrame.new(snapshotPos.X, snapshotPos.Y + 0.5, snapshotPos.Z) * CFrame.Angles(0, 0, math.rad(90))
		previewCircle.Anchored = true
		previewCircle.CanCollide = false
		previewCircle.Material = Enum.Material.Neon
		previewCircle.Color = Color3.fromRGB(255, 100, 0)
		previewCircle.Transparency = 0.5
		previewCircle.Parent = workspace
		
		-- Launch the model downward to the snapshot position
		local launchDuration = 1.5 -- Slow descent
		local startCFrame = superNova:IsA("Model") and superNova:GetPivot() or CFrame.new(superNova.Position)
		local endPos = Vector3.new(snapshotPos.X, snapshotPos.Y + 2, snapshotPos.Z)
		
		local launchElapsed = 0
		while launchElapsed < launchDuration and running and superNova.Parent do
			launchElapsed = launchElapsed + task.wait()
			local alpha = launchElapsed / launchDuration
			
			-- Lerp position from start to end
			local newPos = startCFrame.Position:Lerp(endPos, alpha)
			if superNova:IsA("Model") then
				superNova:PivotTo(CFrame.new(newPos))
			else
				superNova.Position = newPos
			end
		end
		
		-- Impact: explosion effect and massive damage
		if running and superNova.Parent then
			print("[Frieza] Super Nova impact!")
			
			-- Get impact position from model
			local impactPos = superNova:IsA("Model") and superNova:GetPivot().Position or superNova.Position
			
			-- Create explosion effect (bright flash)
			local explosion = Instance.new("Part")
			explosion.Name = "SuperNovaExplosion"
			explosion.Shape = Enum.PartType.Ball
			explosion.Size = Vector3.new(5, 5, 5)
			explosion.Position = impactPos
			explosion.Anchored = true
			explosion.CanCollide = false
			explosion.Material = Enum.Material.Neon
			explosion.Color = Color3.fromRGB(255, 200, 0)
			explosion.Transparency = 0
			explosion.Parent = workspace
			
			-- Expand explosion
			local expandTween = TweenService:Create(explosion, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(damageRadius * 2, damageRadius * 2, damageRadius * 2),
				Transparency = 1
			})
			expandTween:Play()
			
			-- Deal massive AoE damage
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				if character then
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					local playerRoot = character:FindFirstChild("HumanoidRootPart")
					
					if humanoid and humanoid.Health > 0 and playerRoot then
						local distance = (playerRoot.Position - impactPos).Magnitude
						
						if distance <= damageRadius then
							-- Very high damage for ultimate attack
							local damageAmount = DAMAGE * 3
							Damage.Apply(humanoid, damageAmount)
							print("[Frieza] Super Nova hit", player.Name, "for", damageAmount, "damage!")
						end
					end
				end
			end
			
			-- Cleanup after explosion
			task.delay(0.5, function()
				if explosion then explosion:Destroy() end
			end)
			
			-- Cleanup preview circle
			if previewCircle then
				local fadeTween = TweenService:Create(previewCircle, TweenInfo.new(0.3), { Transparency = 1 })
				fadeTween:Play()
				task.delay(0.3, function()
					if previewCircle then previewCircle:Destroy() end
				end)
			end
			
			-- Destroy the Super Nova model immediately after impact
			if superNova and superNova.Parent then
				print("[Frieza] Destroying Super Nova model...")
				superNova:Destroy()
			end
		end
	end)
end

-- Attack loop
local lastAttack = 0
local attackIndex = 0 -- Normal rotation: 0=Single Beam, 1=Barrage, 2=Destructo Disc, 3=Super Nova
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
		if now - lastAttack >= ATTACK_COOLDOWN then
			-- Find target
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
				lastAttack = now
				
				print("[Frieza] Attack triggered! attackIndex=", attackIndex, "superNovaModel=", superNovaModel)
				
				-- Cycle through 3 attack types
				if attackIndex == 1 and deathBeamAnim then
					-- Death Beam Barrage: Frieza can rotate, lasers follow hand
					isAttacking = false -- Allow rotation during barrage
					isBarraging = true -- Slow rotation during barrage
					
					-- Face target initially
					local lookDir = (bestRoot.Position - root.Position) * Vector3.new(1, 0, 1)
					if lookDir.Magnitude > 0.001 then
						root.CFrame = CFrame.new(root.Position, root.Position + lookDir.Unit)
					end
					
					pcall(function()
						deathBeamAnim:Play(0.05, 1, 1)
					end)
					
					-- Wait 1 second before starting barrage
					task.wait(1)
					
					-- Fire barrage (1.5s duration from 1s to 2.5s)
					if running then
						fireDeathBeamBarrage()
					end
					
					-- Wait for animation to finish
					task.wait((deathBeamAnim.Length or 2.5) - 1)
					isBarraging = false -- Resume normal rotation speed
					
				elseif attackIndex == 2 and destructoDiscAnim and destructoDiskModel then
					-- Destructo Disc: allow rotation at normal speed
					isAttacking = false -- Allow rotation during disc charge
					
					-- Face target initially
					local lookDir = (bestRoot.Position - root.Position) * Vector3.new(1, 0, 1)
					if lookDir.Magnitude > 0.001 then
						root.CFrame = CFrame.new(root.Position, root.Position + lookDir.Unit)
					end
					
					-- Play animation
					pcall(function()
						destructoDiscAnim:Play(0.05, 1, 1)
					end)
					
					-- Fire discs (they handle their own timing)
					if running then
						fireDestructoDisc(bestRoot.Position)
					end
					
					-- Wait for full animation (3 seconds for both discs)
					task.wait(destructoDiscAnim.Length or 3)
					
				elseif attackIndex == 3 and superNovaModel then
					-- Super Nova: ultimate attack with massive AoE
					isAttacking = false -- Allow rotation during charge to track player
					
					print("[Frieza] Starting Super Nova attack!")
					
					-- SNAPSHOT target position immediately (bestRoot might become nil later)
					local targetSnapshot = bestRoot and bestRoot.Position or root.Position
					
					-- Face target initially
					local lookDir = (targetSnapshot - root.Position) * Vector3.new(1, 0, 1)
					if lookDir.Magnitude > 0.001 then
						root.CFrame = CFrame.new(root.Position, root.Position + lookDir.Unit)
					end
					
				-- Play Super Nova animation
				if superNovaAnim then
					pcall(function()
						superNovaAnim:Play(0.1, 1, 1)
					end)
				end
				
				print("[Frieza] About to call fireSuperNova with snapshot position...")
				
				-- Fire Super Nova with snapshot position
				fireSuperNova(targetSnapshot)
				
				print("[Frieza] Waiting 5 seconds for Super Nova to complete...")
				
				-- Wait for full attack duration (3s charge + 1.5s descent + 0.5s explosion)
				task.wait(5)
					local targetSnapshot = bestRoot.Position
					
					-- Lock rotation and face target
					isAttacking = true
					local lookDir = (targetSnapshot - root.Position) * Vector3.new(1, 0, 1)
					if lookDir.Magnitude > 0.001 then
						root.CFrame = CFrame.new(root.Position, root.Position + lookDir.Unit)
					end
					
					-- Play attack animation and wait for "beam" event
					if attackAnim then
						local beamFired = false
						local animConnection
						
						-- Listen for the "beam" animation event
						animConnection = attackAnim:GetMarkerReachedSignal("beam"):Connect(function()
							if not beamFired and running then
								beamFired = true
								fireDeathBeam(targetSnapshot)
							end
							if animConnection then
								animConnection:Disconnect()
							end
						end)
						
						pcall(function()
							attackAnim:Play(0.05, 1, 1) -- Normal speed
						end)
						
						-- Wait for animation to complete then unlock rotation
						task.wait(attackAnim.Length or 1)
						isAttacking = false
					else
						-- Fallback if no animation
						task.wait(0.57)
						if running then
							fireDeathBeam(targetSnapshot)
						end
						isAttacking = false
					end
				end
				
				-- Cycle to next attack type (0, 1, 2, 3, then back to 0)
				attackIndex = (attackIndex + 1) % 4
			end
		end
		
		task.wait(0.05)
	end
end)

return true
