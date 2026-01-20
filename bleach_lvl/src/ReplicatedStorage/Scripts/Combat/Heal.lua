-- Heal.lua
-- Healing utility for players

local Heal = {}

-- Apply healing to a humanoid, respecting max health
function Heal.Apply(humanoid: Humanoid, amount: number)
	if not humanoid or humanoid.Health <= 0 then return 0 end
	
	local model = humanoid.Parent
	if not model then return 0 end
	
	-- Check if healing is disabled
	if model:GetAttribute("NoHealing") == true then
		return 0
	end
	
	-- Apply healing reduction from DoTs
	local healReduction = model:GetAttribute("HealingReduction")
	if typeof(healReduction) == "number" and healReduction > 0 then
		amount = amount * (1 - healReduction)
	end
	
	-- Apply healing multiplier if exists
	local healMult = model:GetAttribute("HealingMultiplier")
	if typeof(healMult) == "number" and healMult >= 0 then
		amount = amount * healMult
	end
	
	-- Cap healing at max health
	local maxHealth = humanoid.MaxHealth
	local currentHealth = humanoid.Health
	local actualHeal = math.min(amount, maxHealth - currentHealth)
	
	if actualHeal > 0 then
		humanoid.Health = currentHealth + actualHeal
	end
	
	return actualHeal
end

return Heal
