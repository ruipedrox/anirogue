-- SeriousTraining.lua
-- Saitama's unique training card - unlocks true power at level 10
-- Grants massive base stat multipliers when fully trained

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local def = {
	Name = "Serious Training",
	Rarity = "Legendary",
	Type = "Passive",
	MaxLevel = 10,
	Description = "100 push-ups, 100 sit-ups, 100 squats, and 10km running EVERY DAY!"
}

-- Track training progress per player
local TrainingByUserId = {}

function def.OnCardAdded(player: Player, cardData, currentLevel: number)
	local level = math.clamp(currentLevel or 1, 1, def.MaxLevel)
	
	-- Store level
	if not TrainingByUserId[player.UserId] then
		TrainingByUserId[player.UserId] = {}
	end
	
	-- Remove old buffs if upgrading
	local oldLevel = TrainingByUserId[player.UserId].level
	if oldLevel == 10 then
		-- Remove old level 10 buffs
		local oldBaseDmg = player:GetAttribute("BaseDamage") or 10
		local oldBaseHP = player:GetAttribute("BaseHealth") or 10
		
		player:SetAttribute("DamageBoost", math.max(0, (player:GetAttribute("DamageBoost") or 0) - 99.0))
		player:SetAttribute("HealthBoost", math.max(0, (player:GetAttribute("HealthBoost") or 0) - 299.0))
	end
	
	TrainingByUserId[player.UserId].level = level
	
	-- Level 10 = AWAKENING
	if level == 10 then
		-- Get base stats (original character stats before any boosts)
		local baseDamage = 10 -- Saitama's base damage
		local baseHealth = 10 -- Saitama's base health
		
		-- Apply massive multipliers: 100x damage, 300x health
		local damageBoost = player:GetAttribute("DamageBoost") or 0
		local healthBoost = player:GetAttribute("HealthBoost") or 0
		
		player:SetAttribute("DamageBoost", damageBoost + 99.0) -- 100x = base + 99x boost
		player:SetAttribute("HealthBoost", healthBoost + 299.0) -- 300x = base + 299x boost
		
		-- Unlock Serious Punch in card pool
		player:SetAttribute("SaitamaAwakened", true)
		
		-- Heal player to new max HP
		local char = player.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Health = hum.MaxHealth
			end
		end
		
		print(string.format("[Serious Training] Player %s has AWAKENED! 100x damage, 300x health, Serious Punch unlocked!",
			player.Name
		))
	else
		print(string.format("[Serious Training] Player %s training level %d/10...",
			player.Name,
			level
		))
	end
end

function def.OnCardRemoved(player: Player, cardData)
	local data = TrainingByUserId[player.UserId]
	if not data then return end
	
	local level = data.level
	
	-- Remove level 10 buffs if active
	if level == 10 then
		local damageBoost = player:GetAttribute("DamageBoost") or 0
		local healthBoost = player:GetAttribute("HealthBoost") or 0
		
		player:SetAttribute("DamageBoost", math.max(0, damageBoost - 99.0))
		player:SetAttribute("HealthBoost", math.max(0, healthBoost - 299.0))
		
		-- Remove awakening flag
		player:SetAttribute("SaitamaAwakened", nil)
	end
	
	-- Cleanup
	TrainingByUserId[player.UserId] = nil
	
	print(string.format("[Serious Training] Player %s stopped training", player.Name))
end

-- Cleanup on player leaving
game:GetService("Players").PlayerRemoving:Connect(function(player)
	TrainingByUserId[player.UserId] = nil
end)

return def
