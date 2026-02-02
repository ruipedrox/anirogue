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

-- Crit stats per level (as percent bonuses)
local critStatsPerLevel = {
	[1] = { critChancePercent = 5, critDamagePercent = 50 },
	[2] = { critChancePercent = 10, critDamagePercent = 75 },
	[3] = { critChancePercent = 15, critDamagePercent = 100 },
	[4] = { critChancePercent = 20, critDamagePercent = 125 },
	[5] = { critChancePercent = 25, critDamagePercent = 150 }
}

-- Track active Sharingan per player
local ActiveSharinganByUserId = {}

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
	
	-- Add crit stats using Upgrades
	addUpgrade(player, "CritChancePercent", stats.critChancePercent)
	addUpgrade(player, "CritDamagePercent", stats.critDamagePercent)
	
	print(string.format("[Sharingan] Player %s activated Sharingan Lv%d: %.0f%% crit chance, %.0f%% crit damage",
		player.Name,
		level,
		stats.critChancePercent,
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
	local data = ActiveSharinganByUserId[player.UserId]
	if not data then return end
	
	local level = data.level
	local stats = critStatsPerLevel[level]
	
	if stats then
		-- Remove crit stats
		addUpgrade(player, "CritChancePercent", -stats.critChancePercent)
		addUpgrade(player, "CritDamagePercent", -stats.critDamagePercent)
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
