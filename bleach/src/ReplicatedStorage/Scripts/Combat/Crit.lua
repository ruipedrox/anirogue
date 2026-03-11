-- Crit.lua
-- Resolve critical hit with multi-crit support

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DamageNumbers = require(ReplicatedStorage.Scripts.Combat.DamageNumbers)

local Crit = {}

-- Returns critMultiplier, critCount
-- Supports multiple crits when critChance > 100%
-- Example: 110% = guaranteed 1 crit + 10% chance for 2nd crit
function Crit.Resolve(critChance: number?, critDamage: number?)
	local cc = tonumber(critChance) or 0
	local cd = tonumber(critDamage) or 1
	
	if cc <= 0 then
		return 1, 0 -- No crit
	end
	
	local critCount = 0
	local remainingChance = cc
	
	-- Roll for each 100% of crit chance
	while remainingChance > 0 do
		if remainingChance >= 1.0 then
			-- Guaranteed crit
			critCount = critCount + 1
			remainingChance = remainingChance - 1.0
		else
			-- Roll for remaining chance
			if math.random() < remainingChance then
				critCount = critCount + 1
			end
			break
		end
	end
	
	if critCount == 0 then
		return 1, 0 -- No crit
	end
	
	-- Calculate total multiplier: 1 + (critDamage * critCount)
	local mult = 1 + (cd * critCount)
	return mult, critCount
end

-- Apply damage with crit and show damage number
-- opts = { player: Player, target: Model, baseDamage: number, position: Vector3? }
function Crit.ApplyDamage(opts)
	if not opts or not opts.player or not opts.target then return 0, 0 end
	
	local player = opts.player
	local target = opts.target
	local baseDamage = opts.baseDamage or 0
	local position = opts.position
	
	-- Get crit stats from player
	local critChance = player:GetAttribute("CritChance") or 0
	local critDamage = player:GetAttribute("CritDamage") or 0
	
	-- Roll for crit
	local critMult, critCount = Crit.Resolve(critChance, critDamage)
	local finalDamage = baseDamage * critMult
	
	-- Apply damage
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:TakeDamage(finalDamage)
	end
	
	-- Show damage number
	if not position then
		local ok, cf = pcall(function() return target:GetPivot() end)
		if ok and typeof(cf) == "CFrame" then
			position = cf.Position
		else
			local hrp = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
			position = hrp and hrp.Position or Vector3.new(0, 0, 0)
		end
	end
	
	DamageNumbers.Show({
		position = position,
		amount = finalDamage,
		damageType = critCount > 0 and "crit" or "normal",
		critCount = critCount
	})
	
	return finalDamage, critCount
end

return Crit
