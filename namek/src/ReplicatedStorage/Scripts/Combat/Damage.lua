-- Damage.lua
-- Normal damage application

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local DamageNumbers = require(ReplicatedStorage.Scripts.Combat.DamageNumbers)

local Damage = {}

-- Optional immunities and mitigation
local function getModelFromHumanoid(hum)
	return hum and hum.Parent or nil
end

local function isInvulnerable(model)
	if not model then return false end
	local inv = model:GetAttribute("Invulnerable")
	return inv == true
end

local function applyMitigation(model, amount)
	if not model then return amount end
	-- OnlyDoTDamage: ignore direct damage entirely (still allow DoT elsewhere)
	if model:GetAttribute("OnlyDoTDamage") == true then
		return 0
	end
	-- Percent + flat reduction
	local percentRed = model:GetAttribute("PercentDamageReduction")
	if typeof(percentRed) == "number" then
		amount = amount * math.clamp(1 - percentRed, 0, 1)
	end
	local flatRed = model:GetAttribute("FlatDamageReduction")
	if typeof(flatRed) == "number" then
		amount = math.max(0, amount - flatRed)
	end
	local mult = model:GetAttribute("DamageMultiplier")
	if typeof(mult) == "number" and mult >= 0 then
		amount = amount * mult
	end
	local cap = model:GetAttribute("DamageCap")
	if typeof(cap) == "number" and cap > 0 then
		amount = math.min(amount, cap)
	end
	local maxPerHit = model:GetAttribute("MaxDamagePerHit")
	if typeof(maxPerHit) == "number" and maxPerHit > 0 then
		amount = math.min(amount, maxPerHit)
	end
	return amount
end

function Damage.Apply(humanoid: Humanoid, amount: number)
	if not humanoid or humanoid.Health <= 0 then return 0 end
	local character = humanoid.Parent
	if character and CollectionService:HasTag(character, "ShadowClone") then
		-- Friendly/cloned entity: ignore damage from generic application path
		return 0
	end
	amount = math.max(0, amount or 0)
	-- Respect invulnerability flags and simple mitigation attributes
	local model = getModelFromHumanoid(humanoid)
	if isInvulnerable(model) then return 0 end
	amount = applyMitigation(model, amount)
	if amount <= 0 then return 0 end
	humanoid:TakeDamage(amount)

	-- Instrumentation: record damage dealt by the 'creator' if present
	local ok, creator = pcall(function() return humanoid:FindFirstChild("creator") end)
	if ok and creator and creator.Value and typeof(creator.Value) == "Instance" and creator.Value:IsA("Player") then
		local player = creator.Value
		-- Ensure RunTrack/ Damage counter exists
		local runTrack = player:FindFirstChild("RunTrack")
		if not runTrack then
			runTrack = Instance.new("Folder")
			runTrack.Name = "RunTrack"
			runTrack.Parent = player
		end
		local dmgNV = runTrack:FindFirstChild("Damage")
		if not dmgNV then
			dmgNV = Instance.new("NumberValue")
			dmgNV.Name = "Damage"
			dmgNV.Value = 0
			dmgNV.Parent = runTrack
		end
		-- Accumulate damage (store raw sum)
		dmgNV.Value = (dmgNV.Value or 0) + amount
	end

	return amount
end

return Damage
