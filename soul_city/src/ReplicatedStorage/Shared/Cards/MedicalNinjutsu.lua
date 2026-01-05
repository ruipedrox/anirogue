-- MedicalNinjutsu.lua (Sakura healing card)
-- Periodically heals the player based on their BaseDamage stat

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")
local Heal = require(ScriptsFolder:WaitForChild("Combat"):WaitForChild("Heal"))

local M = {}

-- Track active healing loops per player
local ActiveHealingByUserId: {[number]: {thread: thread, level: number}} = {}

local function getPlayerStats(player: Player)
	local statsFolder = player:FindFirstChild("Stats")
	if not statsFolder then return nil end
	
	local baseDamageValue = statsFolder:FindFirstChild("BaseDamage")
	return baseDamageValue and baseDamageValue.Value or 0
end

local function startHealingLoop(player: Player, level: number, interval: number, healMultipliers: {[number]: number})
	local userId = player.UserId
	
	-- Stop existing loop if any
	if ActiveHealingByUserId[userId] then
		local old = ActiveHealingByUserId[userId]
		if old.thread then
			task.cancel(old.thread)
		end
	end
	
	local thread = task.spawn(function()
		while player.Parent and player:FindFirstChild("Character") do
			task.wait(interval)
			
			local char = player.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local baseDamage = getPlayerStats(player)
				local multiplier = healMultipliers[level] or 1.0
				local healAmount = baseDamage * multiplier
				
				if healAmount > 0 then
					Heal.Apply(humanoid, healAmount)
					print(string.format("[MedicalNinjutsu] Healed %s for %.1f HP (Level %d)", player.Name, healAmount, level))
				end
			end
		end
	end)
	
	ActiveHealingByUserId[userId] = {
		thread = thread,
		level = level
	}
end

function M.OnCardAdded(player: Player, cardData: {[string]: any}, currentLevel: number)
	-- Extract card parameters
	local interval = cardData.interval or 10
	local healMultipliers = cardData.healMultiplier or {[1] = 0.5, [2] = 0.75, [3] = 1.0}
	
	print(string.format("[MedicalNinjutsu] Card added for %s at level %d", player.Name, currentLevel))
	
	-- Start/restart healing loop with new level
	startHealingLoop(player, currentLevel, interval, healMultipliers)
end

function M.OnCardRemoved(player: Player, cardData: {[string]: any})
	local userId = player.UserId
	
	-- Stop healing loop
	if ActiveHealingByUserId[userId] then
		local data = ActiveHealingByUserId[userId]
		if data.thread then
			task.cancel(data.thread)
		end
		ActiveHealingByUserId[userId] = nil
	end
	
	print(string.format("[MedicalNinjutsu] Card removed for %s", player.Name))
end

-- Cleanup on player leaving
Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	if ActiveHealingByUserId[userId] then
		local data = ActiveHealingByUserId[userId]
		if data.thread then
			task.cancel(data.thread)
		end
		ActiveHealingByUserId[userId] = nil
	end
end)

return M
