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

-- Stats per level (as percent bonuses)
local statsPerLevel = {
	[1] = { damagePercent = 30, attackSpeedPercent = 20, critDamagePercent = 25 },
	[2] = { damagePercent = 45, attackSpeedPercent = 30, critDamagePercent = 50 },
	[3] = { damagePercent = 60, attackSpeedPercent = 40, critDamagePercent = 75 },
	[4] = { damagePercent = 75, attackSpeedPercent = 50, critDamagePercent = 100 },
	[5] = { damagePercent = 100, attackSpeedPercent = 60, critDamagePercent = 125 }
}

-- Track active Bankai per player
local ActiveBankaiByUserId = {}

local function addUpgrade(player, name, delta)
	if type(delta) ~= "number" or delta == 0 then return end
	local upgrades = player:FindFirstChild("Upgrades")
	if not upgrades then
		upgrades = Instance.new("Folder")
		upgrades.Name = "Upgrades"
		upgrades.Parent = player
	end
	local u = upgrades:FindFirstChild(name)
	if not u then
		u = Instance.new("NumberValue")
		u.Name = name
		u.Value = 0
		u.Parent = upgrades
	end
	u.Value = u.Value + delta
	-- Mirror to Stats
	local stats = player:FindFirstChild("Stats")
	if stats then
		local s = stats:FindFirstChild(name)
		if not s then
			s = Instance.new("NumberValue")
			s.Name = name
			s.Value = 0
			s.Parent = stats
		end
		s.Value = s.Value + delta
	end
end

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
	
	-- Add stats to player using Upgrades
	addUpgrade(player, "DamagePercent", stats.damagePercent)
	addUpgrade(player, "AttackSpeedPercent", stats.attackSpeedPercent)
	addUpgrade(player, "CritDamagePercent", stats.critDamagePercent)
	
	print(string.format("[Bankai] Player %s activated Bankai Lv%d: +%.0f%% damage, +%.0f%% attack speed, +%.0f%% crit damage",
		player.Name,
		level,
		stats.damagePercent,
		stats.attackSpeedPercent,
		stats.critDamagePercent
	))
	
	-- Reapply stats
	pcall(function()
		local ApplyStats = require(ReplicatedStorage.Scripts.ApplyStats)
		local EquippedItems = require(ReplicatedStorage.Scripts.EquipedItems)
		local CharEquipped = require(ReplicatedStorage.Scripts.CharEquiped)
		local items = EquippedItems:GetEquipped(player)
		local chars = CharEquipped:GetEquipped(player)
		ApplyStats:Apply(player, items, chars)
	end)
end

function def.OnCardRemoved(player: Player, cardData)
	local data = ActiveBankaiByUserId[player.UserId]
	if not data then return end
	
	local level = data.level
	local stats = statsPerLevel[level]
	
	if stats then
		-- Remove stats from player
		addUpgrade(player, "DamagePercent", -stats.damagePercent)
		addUpgrade(player, "AttackSpeedPercent", -stats.attackSpeedPercent)
		addUpgrade(player, "CritDamagePercent", -stats.critDamagePercent)
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
