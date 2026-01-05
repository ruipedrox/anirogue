-- DoT.lua - Damage over Time system with multiple types
-- Types: burn, poison, bleed, rupture, blackflames, infection

local DoT = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DamageNumbers = require(ReplicatedStorage.Scripts.Combat.DamageNumbers)

-- Track active DoT visual effects per model
local ActiveEffects = {} -- [model] = { [dotType] = {ParticleEmitter, ...} }

-- Create visual effects for DoT types
local function createDotEffect(dotType, parent)
	local effects = {}
	
	if dotType == "burn" then
		-- Fire effect
		local fire = Instance.new("ParticleEmitter")
		fire.Name = "BurnEffect"
		fire.Texture = "rbxasset://textures/particles/fire_main.dds"
		fire.Color = ColorSequence.new(Color3.fromRGB(255, 85, 0), Color3.fromRGB(255, 170, 0))
		fire.Size = NumberSequence.new(0.5, 1)
		fire.Lifetime = NumberRange.new(0.3, 0.6)
		fire.Rate = 20
		fire.Speed = NumberRange.new(2, 4)
		fire.SpreadAngle = Vector2.new(20, 20)
		fire.LightEmission = 0.8
		fire.LightInfluence = 0
		fire.Parent = parent
		table.insert(effects, fire)
		
	elseif dotType == "poison" then
		-- Toxic gas/bubbles
		local poison = Instance.new("ParticleEmitter")
		poison.Name = "PoisonEffect"
		poison.Texture = "rbxasset://textures/particles/smoke_main.dds"
		poison.Color = ColorSequence.new(Color3.fromRGB(50, 255, 0), Color3.fromRGB(0, 200, 100))
		poison.Size = NumberSequence.new(0.4, 0.8)
		poison.Lifetime = NumberRange.new(0.5, 1)
		poison.Rate = 15
		poison.Speed = NumberRange.new(1, 2)
		poison.SpreadAngle = Vector2.new(30, 30)
		poison.LightEmission = 0.3
		poison.Transparency = NumberSequence.new(0.3, 1)
		poison.Parent = parent
		table.insert(effects, poison)
		
	elseif dotType == "bleed" then
		-- Blood drops
		local blood = Instance.new("ParticleEmitter")
		blood.Name = "BleedEffect"
		blood.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		blood.Color = ColorSequence.new(Color3.fromRGB(180, 0, 0), Color3.fromRGB(100, 0, 0))
		blood.Size = NumberSequence.new(0.2, 0.3)
		blood.Lifetime = NumberRange.new(0.4, 0.8)
		blood.Rate = 25
		blood.Speed = NumberRange.new(3, 5)
		blood.SpreadAngle = Vector2.new(40, 40)
		blood.LightEmission = 0
		blood.Acceleration = Vector3.new(0, -20, 0)
		blood.Parent = parent
		table.insert(effects, blood)
		
	elseif dotType == "rupture" then
		-- Violent blood spray
		local rupture = Instance.new("ParticleEmitter")
		rupture.Name = "RuptureEffect"
		rupture.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		rupture.Color = ColorSequence.new(Color3.fromRGB(255, 0, 0), Color3.fromRGB(150, 0, 0))
		rupture.Size = NumberSequence.new(0.3, 0.5)
		rupture.Lifetime = NumberRange.new(0.3, 0.6)
		rupture.Rate = 40
		rupture.Speed = NumberRange.new(5, 8)
		rupture.SpreadAngle = Vector2.new(50, 50)
		rupture.LightEmission = 0
		rupture.Acceleration = Vector3.new(0, -25, 0)
		rupture.Parent = parent
		table.insert(effects, rupture)
		
	elseif dotType == "blackflames" then
		-- Dark/black flames
		local blackFire = Instance.new("ParticleEmitter")
		blackFire.Name = "BlackFlamesEffect"
		blackFire.Texture = "rbxasset://textures/particles/fire_main.dds"
		blackFire.Color = ColorSequence.new(Color3.fromRGB(30, 0, 60), Color3.fromRGB(0, 0, 0))
		blackFire.Size = NumberSequence.new(0.6, 1.2)
		blackFire.Lifetime = NumberRange.new(0.5, 1)
		blackFire.Rate = 30
		blackFire.Speed = NumberRange.new(2, 5)
		blackFire.SpreadAngle = Vector2.new(25, 25)
		blackFire.LightEmission = 0.5
		blackFire.LightInfluence = 0
		blackFire.Parent = parent
		table.insert(effects, blackFire)
		
	elseif dotType == "infection" then
		-- Sickly green aura
		local infection = Instance.new("ParticleEmitter")
		infection.Name = "InfectionEffect"
		infection.Texture = "rbxasset://textures/particles/smoke_main.dds"
		infection.Color = ColorSequence.new(Color3.fromRGB(100, 255, 0), Color3.fromRGB(150, 200, 0))
		infection.Size = NumberSequence.new(1, 1.5)
		infection.Lifetime = NumberRange.new(0.8, 1.5)
		infection.Rate = 10
		infection.Speed = NumberRange.new(0.5, 1)
		infection.SpreadAngle = Vector2.new(360, 360)
		infection.LightEmission = 0.4
		infection.Transparency = NumberSequence.new(0.4, 1)
		infection.Parent = parent
		table.insert(effects, infection)
	end
	
	return effects
end

-- Apply visual effects to model
local function applyVisualEffect(model, dotType)
	if not model or not dotType then return end
	
	-- Find or create attachment point
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	local attachment = hrp:FindFirstChild("DoTEffectAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "DoTEffectAttachment"
		attachment.Parent = hrp
	end
	
	-- Initialize tracking
	if not ActiveEffects[model] then
		ActiveEffects[model] = {}
	end
	
	-- Remove old effects of same type
	if ActiveEffects[model][dotType] then
		for _, effect in ipairs(ActiveEffects[model][dotType]) do
			if effect and effect.Parent then
				effect:Destroy()
			end
		end
	end
	
	-- Create and store new effects
	local effects = createDotEffect(dotType, attachment)
	ActiveEffects[model][dotType] = effects
end

-- Remove visual effects from model
local function removeVisualEffect(model, dotType)
	if not model or not dotType then return end
	if not ActiveEffects[model] or not ActiveEffects[model][dotType] then return end
	
	for _, effect in ipairs(ActiveEffects[model][dotType]) do
		if effect and effect.Parent then
			effect:Destroy()
		end
	end
	
	ActiveEffects[model][dotType] = nil
	
	-- Clean up attachment if no effects left
	if next(ActiveEffects[model]) == nil then
		ActiveEffects[model] = nil
		local hrp = model:FindFirstChild("HumanoidRootPart")
		if hrp then
			local attachment = hrp:FindFirstChild("DoTEffectAttachment")
			if attachment then
				attachment:Destroy()
			end
		end
	end
end

-- DoT Type definitions
local DOT_TYPES = {
	-- Basic DoTs: 20% player damage over 5s, 50% healing reduction
	burn = {
		duration = 5,
		damagePercent = 0.20,
		healReduction = 0.50,
		category = "basic"
	},
	poison = {
		duration = 5,
		damagePercent = 0.20,
		healReduction = 0.50,
		category = "basic"
	},
	bleed = {
		duration = 5,
		damagePercent = 0.20,
		healReduction = 0.50,
		category = "basic"
	},
	
	-- Advanced DoTs: 50% player damage over 10s, 10% damage amplification (stacks)
	rupture = {
		duration = 10,
		damagePercent = 0.50,
		damageAmpPercent = 0.10,
		category = "advanced"
	},
	blackflames = {
		duration = 10,
		damagePercent = 0.50,
		damageAmpPercent = 0.10,
		category = "advanced"
	},
	
	-- Special DoT: 100% healing reduction, 10% damage amplification (stacks with advanced)
	infection = {
		duration = 10,
		damagePercent = 0,
		healReduction = 1.0,
		damageAmpPercent = 0.10,
		category = "special"
	}
}

-- Track active DoTs per enemy
local ActiveDoTs = {} -- [model] = { [dotType] = {expiryTime, playerDamage, thread} }

local function getModelFromHumanoid(hum)
	return hum and hum.Parent or nil
end

-- Update enemy debuff attributes based on active DoTs
local function updateDebuffs(model)
	if not model then return end
	
	local dots = ActiveDoTs[model]
	if not dots then return end
	
	-- Calculate total healing reduction (max of all active DoTs)
	local maxHealReduction = 0
	for dotType, data in pairs(dots) do
		local config = DOT_TYPES[dotType]
		if config and config.healReduction then
			maxHealReduction = math.max(maxHealReduction, config.healReduction)
		end
	end
	
	-- Calculate total damage amplification (stacks)
	local totalDamageAmp = 0
	for dotType, data in pairs(dots) do
		local config = DOT_TYPES[dotType]
		if config and config.damageAmpPercent then
			totalDamageAmp = totalDamageAmp + config.damageAmpPercent
		end
	end
	
	-- Apply attributes
	if maxHealReduction > 0 then
		model:SetAttribute("HealingReduction", maxHealReduction)
	else
		model:SetAttribute("HealingReduction", nil)
	end
	
	if totalDamageAmp > 0 then
		-- DamageMultiplier makes enemy take more damage
		local currentMult = model:GetAttribute("DamageMultiplier") or 1
		-- Reset to base first (assuming base is 1), then apply DoT amp
		model:SetAttribute("DamageMultiplier", 1 + totalDamageAmp)
	else
		-- Reset to default if no damage amp
		if model:GetAttribute("DamageMultiplier") then
			model:SetAttribute("DamageMultiplier", 1)
		end
	end
end

-- Apply DoT to a humanoid
-- opts = { dotType: string, playerDamage: number, tick: number? }
function DoT.Apply(humanoid: Humanoid, opts)
	local h = humanoid
	if not h or h.Health <= 0 then return end
	
	local model = getModelFromHumanoid(h)
	if not model then return end
	
	if model:GetAttribute("ImmuneDoT") == true then
		return
	end
	
	local dotType = opts and opts.dotType or "burn"
	local config = DOT_TYPES[dotType]
	if not config then
		warn("[DoT] Unknown DoT type:", dotType)
		return
	end
	
	local playerDamage = math.max(0, tonumber(opts and opts.playerDamage) or 0)
	local tick = math.max(0.05, tonumber(opts and opts.tick) or 0.25)
	
	-- Initialize tracking
	if not ActiveDoTs[model] then
		ActiveDoTs[model] = {}
	end
	
	-- Check if same DoT type already exists - just reset duration, don't stack
	if ActiveDoTs[model][dotType] then
		local oldData = ActiveDoTs[model][dotType]
		if oldData.thread then
			task.cancel(oldData.thread)
		end
		print(string.format("[DoT] %s already active, resetting duration", dotType))
	end
	
	-- Calculate damage
	local totalDamage = playerDamage * config.damagePercent
	local ticks = math.max(1, math.floor(config.duration / tick + 0.5))
	local perTick = totalDamage / ticks
	
	-- Start DoT thread
	local expiryTime = os.clock() + config.duration
	local thread = task.spawn(function()
		for i = 1, ticks do
			-- Respect global game pause
			while ReplicatedStorage:GetAttribute("GamePaused") do
				task.wait(0.05)
			end
			
			if not h or h.Health <= 0 or not h.Parent then
				break
			end
			
			if perTick > 0 then
				h:TakeDamage(perTick)
				
				-- Show damage number
				local pos
				local ok, cf = pcall(function() return model:GetPivot() end)
				if ok and typeof(cf) == "CFrame" then
					pos = cf.Position
				else
					local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
					pos = hrp and hrp.Position or Vector3.new(0, 0, 0)
				end
				
				DamageNumbers.Show({
					position = pos,
					amount = perTick,
					damageType = dotType
				})
			end
			
			task.wait(tick)
		end
		
		-- Cleanup when done
		if ActiveDoTs[model] and ActiveDoTs[model][dotType] then
			ActiveDoTs[model][dotType] = nil
			if next(ActiveDoTs[model]) == nil then
				ActiveDoTs[model] = nil
			end
			
			-- Remove visual effect
			removeVisualEffect(model, dotType)
			
			updateDebuffs(model)
		end
	end)
	
	-- Store DoT data
	ActiveDoTs[model][dotType] = {
		expiryTime = expiryTime,
		playerDamage = playerDamage,
		thread = thread
	}
	
	-- Apply visual effect
	applyVisualEffect(model, dotType)
	
	-- Update debuffs immediately
	updateDebuffs(model)
end

-- Cleanup when model is destroyed
game:GetService("CollectionService"):GetInstanceRemovedSignal("Enemy"):Connect(function(model)
	if ActiveDoTs[model] then
		for dotType, data in pairs(ActiveDoTs[model]) do
			if data.thread then
				task.cancel(data.thread)
			end
		end
		ActiveDoTs[model] = nil
	end
	
	-- Remove all visual effects
	if ActiveEffects[model] then
		for dotType, effects in pairs(ActiveEffects[model]) do
			for _, effect in ipairs(effects) do
				if effect and effect.Parent then
					effect:Destroy()
				end
			end
		end
		ActiveEffects[model] = nil
	end
end)

return DoT
