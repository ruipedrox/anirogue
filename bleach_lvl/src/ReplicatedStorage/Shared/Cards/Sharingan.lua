-- Sharingan.lua
-- Increases crit chance and crit damage
-- Stacks with card levels

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local def = {
	Name = "Sharingan",
	Rarity = "Legendary",
	Type = "Passive",
	MaxLevel = 5, -- Can be 3, 4, or 5 depending on character tier
	Description = "The legendary dojutsu of the Uchiha clan. Increases critical hit chance and critical damage. Above 100% crit chance, gain additional crit multipliers.\n\nLv1: +5% crit chance, +50% crit damage\nLv2: +10% crit chance, +75% crit damage\nLv3: +15% crit chance, +100% crit damage\nLv4: +20% crit chance, +125% crit damage\nLv5: +25% crit chance, +150% crit damage"
}

-- Crit stats per level
local critStatsPerLevel = {
	[1] = { critChance = 0.05, critDamage = 0.50 },
	[2] = { critChance = 0.10, critDamage = 0.75 },
	[3] = { critChance = 0.15, critDamage = 1.00 },
	[4] = { critChance = 0.20, critDamage = 1.25 },
	[5] = { critChance = 0.25, critDamage = 1.50 }
}

-- Track active Sharingan per player
local ActiveSharinganByUserId = {}

function def.OnCardAdded(player: Player, cardData, currentLevel: number)
	local level = math.clamp(currentLevel or 1, 1, def.MaxLevel)
	local stats = critStatsPerLevel[level]
	
	if not stats then
		warn("[Sharingan] Invalid level:", level)
		return
	end
	
	-- Store current level
	if not ActiveSharinganByUserId[player.UserId] then
		ActiveSharinganByUserId[player.UserId] = {}
	end
	ActiveSharinganByUserId[player.UserId].level = level
	
	-- Add crit stats to player
	local critChance = player:GetAttribute("CritChance") or 0
	local critDamage = player:GetAttribute("CritDamage") or 0
	
	player:SetAttribute("CritChance", critChance + stats.critChance)
	player:SetAttribute("CritDamage", critDamage + stats.critDamage)
	
	print(string.format("[Sharingan] Player %s activated Sharingan Lv%d: %.0f%% crit chance, %.0f%% crit damage",
		player.Name,
		level,
		stats.critChance * 100,
		stats.critDamage * 100
	))
end

function def.OnCardRemoved(player: Player, cardData)
	local data = ActiveSharinganByUserId[player.UserId]
	if not data then return end
	
	local level = data.level
	local stats = critStatsPerLevel[level]
	
	if stats then
		-- Remove crit stats from player
		local critChance = player:GetAttribute("CritChance") or 0
		local critDamage = player:GetAttribute("CritDamage") or 0
		
		player:SetAttribute("CritChance", math.max(0, critChance - stats.critChance))
		player:SetAttribute("CritDamage", math.max(0, critDamage - stats.critDamage))
	end
	
	-- Cleanup
	ActiveSharinganByUserId[player.UserId] = nil
	
	print(string.format("[Sharingan] Player %s deactivated Sharingan", player.Name))
end

-- Cleanup on player leaving
game:GetService("Players").PlayerRemoving:Connect(function(player)
	ActiveSharinganByUserId[player.UserId] = nil
end)

return def
