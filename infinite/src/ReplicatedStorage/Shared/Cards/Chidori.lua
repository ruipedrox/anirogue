-- Chidori.lua
-- Applies electric damage on hit (chain lightning)
-- Stacks with card levels

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Electric = require(ReplicatedStorage.Scripts.Combat.Electric)

local def = {
	Name = "Chidori",
	Rarity = "Legendary",
	Type = "OnHit",
	MaxLevel = 5,
	Description = "Lightning blade technique. Your attacks chain lightning to nearby enemies, dealing electric damage.\n\nLv1: 2 chains, 30% damage each\nLv2: 2 chains, 35% damage each\nLv3: 3 chains, 40% damage each\nLv4: 3 chains, 45% damage each\nLv5: 4 chains, 50% damage each"
}

-- Electric stats per level
local electricStatsPerLevel = {
	[1] = { chainCount = 2, damagePercent = 0.30 },
	[2] = { chainCount = 2, damagePercent = 0.35 },
	[3] = { chainCount = 3, damagePercent = 0.40 },
	[4] = { chainCount = 3, damagePercent = 0.45 },
	[5] = { chainCount = 4, damagePercent = 0.50 }
}

-- Track active Chidori per player
local ActiveChidoriByUserId = {}

function def.OnCardAdded(player: Player, cardData, currentLevel: number)
	local maxLv = (type(cardData) == "table" and tonumber(cardData.maxLevel)) or def.MaxLevel
	local level = math.clamp(currentLevel or 1, 1, maxLv)

	-- Regista nível no RunTrack para que CardPool pare de oferecer ao atingir max level
	do
		local cardId = (type(cardData) == "table" and cardData.id) or "Sasuke_Legendary_Chidori"
		local runTrack = player:FindFirstChild("RunTrack")
		if not runTrack then runTrack = Instance.new("Folder") runTrack.Name = "RunTrack" runTrack.Parent = player end
		local myFolder = runTrack:FindFirstChild(cardId) or Instance.new("Folder")
		myFolder.Name = cardId; myFolder.Parent = runTrack
		local lvlNV = myFolder:FindFirstChild("Level") or Instance.new("IntValue")
		lvlNV.Name = "Level"; lvlNV.Value = level; lvlNV.Parent = myFolder
	end

	local stats = electricStatsPerLevel[level]
	
	if not stats then
		warn("[Chidori] Invalid level:", level)
		return
	end
	
	-- Store current level
	if not ActiveChidoriByUserId[player.UserId] then
		ActiveChidoriByUserId[player.UserId] = {}
	end
	ActiveChidoriByUserId[player.UserId].level = level
	ActiveChidoriByUserId[player.UserId].stats = stats
	
	-- Add electric stacks to player
	Electric.AddStack(player, stats.chainCount, stats.damagePercent)
	
	print(string.format("[Chidori] Player %s activated Chidori Lv%d: %d chains at %.0f%% damage",
		player.Name,
		level,
		stats.chainCount,
		stats.damagePercent * 100
	))
end

function def.OnCardRemoved(player: Player, cardData)
	local data = ActiveChidoriByUserId[player.UserId]
	if not data then return end
	
	local stats = data.stats
	
	if stats then
		-- Remove electric stacks from player
		Electric.RemoveStack(player, stats.chainCount, stats.damagePercent)
	end
	
	-- Cleanup
	ActiveChidoriByUserId[player.UserId] = nil
	
	print(string.format("[Chidori] Player %s deactivated Chidori", player.Name))
end

-- Cleanup on player leaving
game:GetService("Players").PlayerRemoving:Connect(function(player)
	ActiveChidoriByUserId[player.UserId] = nil
end)

return def
