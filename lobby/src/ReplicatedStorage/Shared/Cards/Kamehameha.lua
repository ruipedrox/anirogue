-- Kamehameha.lua
-- Legendary Goku card: Every Cooldown seconds, charge for ChargeTime, then fire a beam for BeamDuration.
-- During the beam, every TickInterval deal 50% of player's damage to all enemies touching the beam.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")
local Damage = require(ScriptsFolder:WaitForChild("Combat"):WaitForChild("Damage"))

local M = {}

local running: { [Player]: RBXScriptConnection } = {}

-- Orientation offsets (adjust if your models are built along Y-axis)
local ROTATE_X = math.rad(90) -- rotate 90 degrees around X to lay beam horizontally
local FORWARD_OFFSET_CHARGE = -2
local FORWARD_OFFSET_BEAM = -6

local function getStats(player: Player)
	local stats = player:FindFirstChild("Stats")
	if not stats then return 0, 0 end
	local function num(name, default)
		local nv = stats:FindFirstChild(name)
		if nv and nv:IsA("NumberValue") then return nv.Value end
		return default
	end
	local baseDamage = num("BaseDamage", 0)
	local dmgPercent = num("DamagePercent", 0)
	local percentMult = 1 + math.max(-0.99, (dmgPercent or 0) / 100)
	return baseDamage, percentMult
end

-- Fade out helper: tween all BaseParts to target transparency
local function fadeOut(inst: Instance, duration: number, targetTransparency: number)
	duration = math.max(0.05, duration or 0.25)
	targetTransparency = math.clamp(targetTransparency or 1, 0, 1)
	local tweens = {}
	local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local function tweenPart(p: BasePart)
		-- Skip if already at target
		if math.abs((p.Transparency or 0) - targetTransparency) < 1e-3 then return end
		local tween = TweenService:Create(p, info, { Transparency = targetTransparency })
		tween:Play()
		table.insert(tweens, tween)
	end
	if inst:IsA("Model") then
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then tweenPart(d) end
		end
	elseif inst:IsA("BasePart") then
		tweenPart(inst)
	end
	task.wait(duration)
end

local function ensureFolder(parent: Instance, name: string)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local function ensureNumber(parent: Instance, name: string, value: number)
	local nv = parent:FindFirstChild(name)
	if not nv then
		nv = Instance.new("NumberValue")
		nv.Name = name
		nv.Value = value
		nv.Parent = parent
	end
	return nv
end

local function getGokuFolder()
	-- Updated path: Chars agora está sob ReplicatedStorage.Shared
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local chars = shared and shared:FindFirstChild("Chars")
	return chars and chars:FindFirstChild("Goku_5") or nil
end

-- Mark all parts of an instance non-blocking and anchored (no physics interaction)
local function makeNonBlockingAnchored(inst: Instance)
	if inst:IsA("Model") then
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d.Anchored = true
			end
		end
	elseif inst:IsA("BasePart") then
		inst.CanCollide = false
		inst.CanTouch = false
		inst.CanQuery = false
		inst.Anchored = true
	end
end

-- Position an instance in front of hrp, laid horizontally
local function positionInFront(inst: Instance, hrp: BasePart, forwardOffset: number)
	local cf = hrp.CFrame * CFrame.new(0, 0, forwardOffset) * CFrame.Angles(ROTATE_X, 0, 0)
	if inst:IsA("Model") then
		(inst :: Model):PivotTo(cf)
	else
		(inst :: BasePart).CFrame = cf
	end
end

-- Compute the extent (comprimento) do feixe na direção que o player olha (LookVector)
local function computeForwardExtent(inst: Instance, look: Vector3)
	local function orientedExtent(cf: CFrame, size: Vector3)
		-- projeção de um OBB na direção look
		local xAxis, yAxis, zAxis = cf.RightVector, cf.UpVector, cf.LookVector
		return math.abs(size.X * xAxis:Dot(look)) + math.abs(size.Y * yAxis:Dot(look)) + math.abs(size.Z * zAxis:Dot(look))
	end
	if inst:IsA("Model") then
		local bboxCF, bboxSize = inst:GetBoundingBox()
		return orientedExtent(bboxCF, bboxSize)
	elseif inst:IsA("BasePart") then
		return orientedExtent(inst.CFrame, inst.Size)
	end
	return 0
end

-- Follow helper: update position every Heartbeat until stopped
local function startFollow(inst: Instance, hrp: BasePart, forwardOffset: number)
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not inst.Parent or not hrp.Parent then
			if conn then conn:Disconnect() end
			return
		end
		if ReplicatedStorage:GetAttribute("GamePaused") then return end
		positionInFront(inst, hrp, forwardOffset)
	end)
	return conn
end

local function scaleChargeModel(model: Instance, factor: number)
	-- Try to scale meshes; fallback to BasePart size
	for _, d in ipairs((model :: Instance):GetDescendants()) do
		if d:IsA("SpecialMesh") then
			d.Scale = d.Scale * factor
		elseif d:IsA("BasePart") then
			local s = d.Size
			d.Size = Vector3.new(math.max(0.05, s.X * factor), math.max(0.05, s.Y * factor), math.max(0.05, s.Z * factor))
		end
	end
end

local function getEnemiesTouching(beam: Instance)
	local enemies: { Model } = {}
	local seen: { [Model]: boolean } = {}
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	-- Exclude nothing explicitly; we'll filter by tag later
	local function collectFromPart(part: BasePart)
		local parts = workspace:GetPartsInPart(part, overlap)
		for _, p in ipairs(parts) do
			local m = p:FindFirstAncestorOfClass("Model")
			if m and not seen[m] and CollectionService:HasTag(m, "Enemy") then
				seen[m] = true
				table.insert(enemies, m)
			end
		end
	end
	if beam:IsA("Model") then
		for _, d in ipairs(beam:GetDescendants()) do
			if d:IsA("BasePart") then
				collectFromPart(d)
			end
		end
	elseif beam:IsA("BasePart") then
		collectFromPart(beam)
	end
	return enemies
end

function M.Start(player: Player)
	if running[player] then return end
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not player or not player.Parent then if conn then conn:Disconnect() end running[player] = nil return end
		-- pause-aware
		if ReplicatedStorage:GetAttribute("GamePaused") then return end
		local upgrades = player:FindFirstChild("Upgrades")
		local onInterval = upgrades and upgrades:FindFirstChild("OnInterval") or ensureFolder(ensureFolder(player, "Upgrades"), "OnInterval")
		local cfg = onInterval:FindFirstChild("Kamehameha") or ensureFolder(onInterval, "Kamehameha")
		local cooldownNV = ensureNumber(cfg, "Cooldown", 10)
		local chargeNV = ensureNumber(cfg, "ChargeTime", 2)
		local durationNV = ensureNumber(cfg, "BeamDuration", 3)
		local tickNV = ensureNumber(cfg, "TickInterval", 0.5)
		local dmgPctNV = ensureNumber(cfg, "DamagePercent", 50)
		local sizeScaleNV = ensureNumber(cfg, "SizeScale", 1)
		local remainingNV = cfg:FindFirstChild("Remaining")
		if not remainingNV then
			remainingNV = Instance.new("NumberValue")
			remainingNV.Name = "Remaining"
			remainingNV.Value = cooldownNV.Value
			remainingNV.Parent = cfg
		end
		-- countdown
		remainingNV.Value = math.max(0, remainingNV.Value - dt)
		if remainingNV.Value > 0 then return end
		-- Try to perform cast; only reset on success
		local character = player.Character
		local hrp = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
		if not (character and hrp) then return end
		local goku = getGokuFolder()
		local chargeTemplate = goku and goku:FindFirstChild("kame_charge")
		local beamTemplate = goku and goku:FindFirstChild("Kamehameha")
		if not chargeTemplate or not beamTemplate then return end

		-- Guard: prevent re-entrancy during charge/beam duration
		local busy = cfg:FindFirstChild("Casting")
		if not busy then
			busy = Instance.new("BoolValue")
			busy.Name = "Casting"
			busy.Value = false
			busy.Parent = cfg
		end
		if busy.Value then return end
		busy.Value = true

		-- Charge phase (scale up over ChargeTime)
		local charge = chargeTemplate:Clone()
		charge.Name = "Kame_Charge_Instance"
		charge.Parent = character
		makeNonBlockingAnchored(charge)
		-- Place slightly in front and keep following the HRP during charge
		positionInFront(charge, hrp, FORWARD_OFFSET_CHARGE)
		local chargeFollowConn = startFollow(charge, hrp, FORWARD_OFFSET_CHARGE)
		-- Animate scale from 0.5x to 1.5x over charge time
		local t = 0
		local startFactor, endFactor = 0.5, 1.5
		while t < chargeNV.Value do
			if ReplicatedStorage:GetAttribute("GamePaused") then
				RunService.Heartbeat:Wait()
			else
				local dt2 = task.wait(0.05) or 0.05
				t = t + dt2
				local alpha = math.clamp(t / chargeNV.Value, 0, 1)
				local factor = startFactor + (endFactor - startFactor) * alpha
				scaleChargeModel(charge, factor / math.max(0.01, (charge:GetAttribute("LastScale") or startFactor)))
				charge:SetAttribute("LastScale", factor)
			end
			if not charge.Parent then break end
		end
		if chargeFollowConn then chargeFollowConn:Disconnect() end
		pcall(function() charge:Destroy() end)

		-- Fire beam
		local beam = beamTemplate:Clone()
		beam.Name = "Kamehameha_Instance"
		beam.Parent = character
		-- Make non-colliding, anchored
		makeNonBlockingAnchored(beam)
		-- Coloca inicialmente para poder medir bounding box já orientado
		positionInFront(beam, hrp, FORWARD_OFFSET_BEAM)
		local look = hrp.CFrame.LookVector
		-- Medir tamanho base (scale 1) uma única vez e armazenar no template
		local baseForwardSize: number = beamTemplate:GetAttribute("BaseForwardSize")
		local backFaceDist: number = beamTemplate:GetAttribute("BackFaceDistance")
		if not baseForwardSize then
			baseForwardSize = computeForwardExtent(beam, look)
			beamTemplate:SetAttribute("BaseForwardSize", baseForwardSize)
			-- Distância que a face traseira tinha originalmente (offset para frente - metade do comprimento)
			-- FORWARD_OFFSET_BEAM é negativo (para frente). Distância positiva para frente = -FORWARD_OFFSET_BEAM.
			backFaceDist = (-FORWARD_OFFSET_BEAM) - (baseForwardSize / 2)
			beamTemplate:SetAttribute("BackFaceDistance", backFaceDist)
		else
			backFaceDist = backFaceDist or 0
		end
		-- Apply size scaling based on level
		local function scaleBeam(inst: Instance, factor: number)
			if factor == 1 then return end
			if inst:IsA("Model") then
				for _, d in ipairs(inst:GetDescendants()) do
					if d:IsA("SpecialMesh") then
						d.Scale = d.Scale * factor
					elseif d:IsA("BasePart") then
						local s = d.Size
						d.Size = Vector3.new(math.max(0.05, s.X * factor), math.max(0.05, s.Y * factor), math.max(0.05, s.Z * factor))
					end
				end
			elseif inst:IsA("BasePart") then
				local s = inst.Size
				inst.Size = Vector3.new(math.max(0.05, s.X * factor), math.max(0.05, s.Y * factor), math.max(0.05, s.Z * factor))
			end
		end
		scaleBeam(beam, math.max(0.1, sizeScaleNV.Value))
		-- Recalcular comprimento após scale
		local currentForwardSize = computeForwardExtent(beam, look)
		-- Queremos manter a face traseira sempre à mesma distância do player (backFaceDist)
		-- Novo offset para colocar o pivot mais à frente = backFaceDist + currentForwardSize/2
		local desiredForwardDistance = backFaceDist + currentForwardSize / 2 -- distância positiva em studs para frente do HRP até o pivot
		local dynamicForwardOffset = -desiredForwardDistance -- negativo porque usamos CFrame.new(0,0,negativo)
		positionInFront(beam, hrp, dynamicForwardOffset)
		local beamFollowConn = startFollow(beam, hrp, dynamicForwardOffset)
		if beam:IsA("Model") then
			local primary = beam.PrimaryPart or beam:FindFirstChild("HumanoidRootPart")
			if primary then
				primary.CFrame = hrp.CFrame * CFrame.new(0, 0, dynamicForwardOffset) * CFrame.Angles(ROTATE_X, 0, 0)
			end
		elseif beam:IsA("BasePart") then
			beam.CFrame = hrp.CFrame * CFrame.new(0, 0, dynamicForwardOffset) * CFrame.Angles(ROTATE_X, 0, 0)
		end

		-- Damage ticks during duration
		local elapsed = 0
		local baseDamage, percentMult = getStats(player)
		local perTick = (baseDamage * percentMult) * math.max(0, dmgPctNV.Value) / 100
		while elapsed < durationNV.Value do
			if not beam.Parent then break end
			if ReplicatedStorage:GetAttribute("GamePaused") then
				RunService.Heartbeat:Wait()
			else
				-- damage enemies touching the beam now
				local touched = {}
				if beam:IsA("Model") then
					for _, m in ipairs(getEnemiesTouching(beam)) do table.insert(touched, m) end
				else
					local enemies = getEnemiesTouching(beam) -- handles BasePart too
					for _, m in ipairs(enemies) do table.insert(touched, m) end
				end
				for _, enemy in ipairs(touched) do
					local hum = enemy:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health > 0 then
						local creator = hum:FindFirstChild("creator")
						if not creator then
							creator = Instance.new("ObjectValue")
							creator.Name = "creator"
							creator.Value = player
							creator.Parent = hum
							task.delay(2, function() if creator and creator.Parent then creator:Destroy() end end)
						end
						Damage.Apply(hum, perTick)
					end
				end
				local dt3 = task.wait(math.max(0.01, tickNV.Value)) or tickNV.Value
				elapsed = elapsed + dt3
			end
		end
		if beamFollowConn then beamFollowConn:Disconnect() end
		-- Visual polish: fade-out the beam as it disappears (laser effect)
		fadeOut(beam, 0.35, 1)
		pcall(function() beam:Destroy() end)
		-- Reset cooldown after successful cast and clear casting flag
		remainingNV.Value = cooldownNV.Value
		busy.Value = false
	end)
	running[player] = conn
end

function M.Stop(player: Player)
	local conn = running[player]
	if conn then conn:Disconnect() end
	running[player] = nil
end

-- Apply or level-up the Kamehameha card for the player.
-- Ensures config exists under Upgrades/OnInterval/Kamehameha, increments level up to max,
-- computes effective cooldown/damage/size and writes values, then starts the loop.
function M.Apply(player: Player, def)
	def = def or {}
	if not player or not player.Parent then return end
	local upgrades = player:FindFirstChild("Upgrades") or ensureFolder(player, "Upgrades")
	local onInterval = upgrades:FindFirstChild("OnInterval") or ensureFolder(upgrades, "OnInterval")
	local cfg = onInterval:FindFirstChild("Kamehameha") or ensureFolder(onInterval, "Kamehameha")

	-- Level tracking under RunTrack
	local runTrack = player:FindFirstChild("RunTrack")
	if not runTrack then runTrack = Instance.new("Folder") runTrack.Name = "RunTrack" runTrack.Parent = player end
	local kFolder = runTrack:FindFirstChild("Kamehameha") or Instance.new("Folder")
	kFolder.Name = "Kamehameha"
	kFolder.Parent = runTrack
	local lvl = kFolder:FindFirstChild("Level") or Instance.new("IntValue")
	lvl.Name = "Level"
	lvl.Parent = kFolder
	local maxLevel = (typeof(def.maxLevel) == "number" and def.maxLevel) or 5
	lvl.Value = math.min(maxLevel, (lvl.Value or 0) + 1)

	-- Compute effective params from def + level
	local L = math.max(1, lvl.Value)
	local baseCooldown = typeof(def.baseCooldown) == "number" and def.baseCooldown or 10
	local cdPerLevel = typeof(def.cooldownPerLevel) == "number" and def.cooldownPerLevel or -1
	local baseDmgPct = typeof(def.baseDamagePercent) == "number" and def.baseDamagePercent or 10
	local dmgPerLevel = typeof(def.damagePercentPerLevel) == "number" and def.damagePercentPerLevel or 10
	local sizePerLevel = typeof(def.sizePerLevel) == "number" and def.sizePerLevel or 0.25
	-- Extra bonus applied only at the final level (último nível)
	local finalLevelExtra = typeof(def.finalLevelExtra) == "number" and def.finalLevelExtra or 0.25
	local duration = typeof(def.duration) == "number" and def.duration or 3
	local chargeTime = typeof(def.chargeTime) == "number" and def.chargeTime or 2
	local tickInterval = typeof(def.tickInterval) == "number" and def.tickInterval or 0.5

	local effectiveCooldown = baseCooldown + cdPerLevel * (L - 1)
	local effectiveDamagePercent = math.max(0, baseDmgPct + dmgPerLevel * (L - 1))
	-- Base scaling 25% por nível; no último nível aplica um bónus adicional
	local sizeScale = 1 + math.max(0, sizePerLevel * (L - 1)) + ((L >= maxLevel) and math.max(0, finalLevelExtra) or 0)

	-- Write/update values (idempotent)
	local cdNV = ensureNumber(cfg, "Cooldown", effectiveCooldown); cdNV.Value = effectiveCooldown
	local chargeNV = ensureNumber(cfg, "ChargeTime", chargeTime); chargeNV.Value = chargeTime
	local durNV = ensureNumber(cfg, "BeamDuration", duration); durNV.Value = duration
	local tickNV = ensureNumber(cfg, "TickInterval", tickInterval); tickNV.Value = tickInterval
	local dmgNV = ensureNumber(cfg, "DamagePercent", effectiveDamagePercent); dmgNV.Value = effectiveDamagePercent
	local sizeNV = ensureNumber(cfg, "SizeScale", sizeScale); sizeNV.Value = sizeScale

	-- Start loop (idempotent)
	M.Start(player)
end

return M
