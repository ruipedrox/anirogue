-- Bankai.lua
-- Ichigo's Bankai transformation - increases damage and attack speed
-- Stacks with card levels

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local def = {
	Name = "Bankai",
	Rarity = "Epic/Legendary",
	Type = "Passive",
	MaxLevel = 5,
	Description = "Unlock Bankai transformation. Greatly increases damage and attack speed."
}

-- Stats per level
local statsPerLevel = {
	[1] = { damageBoost = 0.30, attackSpeedBoost = 0.20, critDamage = 0.25 },
	[2] = { damageBoost = 0.45, attackSpeedBoost = 0.30, critDamage = 0.50 },
	[3] = { damageBoost = 0.60, attackSpeedBoost = 0.40, critDamage = 0.75 },
	[4] = { damageBoost = 0.75, attackSpeedBoost = 0.50, critDamage = 1.00 },
	[5] = { damageBoost = 1.00, attackSpeedBoost = 0.60, critDamage = 1.25 }
}

-- Track active Bankai per player
local ActiveBankaiByUserId = {}

function def.OnCardAdded(player: Player, cardData, currentLevel: number)
	local level = math.clamp(currentLevel or 1, 1, def.MaxLevel)
	local stats = statsPerLevel[level]
	
	if not stats then
		warn("[Bankai] Invalid level:", level)
		return
	end
	
	-- Store current level
	if not ActiveBankaiByUserId[player.UserId] then
		ActiveBankaiByUserId[player.UserId] = {}
	end
	ActiveBankaiByUserId[player.UserId].level = level
	
	-- Add stats to player
	local damageBoost = player:GetAttribute("DamageBoost") or 0
	local attackSpeedBoost = player:GetAttribute("AttackSpeedBoost") or 0
	local critDamage = player:GetAttribute("CritDamage") or 0
	
	player:SetAttribute("DamageBoost", damageBoost + stats.damageBoost)
	player:SetAttribute("AttackSpeedBoost", attackSpeedBoost + stats.attackSpeedBoost)
	player:SetAttribute("CritDamage", critDamage + stats.critDamage)
	
	print(string.format("[Bankai] Player %s activated Bankai Lv%d: +%.0f%% damage, +%.0f%% attack speed, +%.0f%% crit damage",
		player.Name,
		level,
		stats.damageBoost * 100,
		stats.attackSpeedBoost * 100,
		stats.critDamage * 100
	))
end

function def.OnCardRemoved(player: Player, cardData)
	local data = ActiveBankaiByUserId[player.UserId]
	if not data then return end
	
	local level = data.level
	local stats = statsPerLevel[level]
	
	if stats then
		-- Remove stats from player
		local damageBoost = player:GetAttribute("DamageBoost") or 0
		local attackSpeedBoost = player:GetAttribute("AttackSpeedBoost") or 0
		local critDamage = player:GetAttribute("CritDamage") or 0
		
		player:SetAttribute("DamageBoost", math.max(0, damageBoost - stats.damageBoost))
		player:SetAttribute("AttackSpeedBoost", math.max(0, attackSpeedBoost - stats.attackSpeedBoost))
		player:SetAttribute("CritDamage", math.max(0, critDamage - stats.critDamage))
	end
	
	-- Cleanup
	ActiveBankaiByUserId[player.UserId] = nil
	
	print(string.format("[Bankai] Player %s deactivated Bankai", player.Name))
end

-- Cleanup on player leaving
game:GetService("Players").PlayerRemoving:Connect(function(player)
	ActiveBankaiByUserId[player.UserId] = nil
end)

return def
