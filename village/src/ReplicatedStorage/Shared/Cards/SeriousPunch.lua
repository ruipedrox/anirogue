-- SeriousPunch.lua
-- Saitama's ultimate ability - hits ALL enemies on the map
-- Deals 1000% of player's total damage every 90 seconds

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local def = {
	Name = "Serious Punch",
	Rarity = "Legendary",
	Type = "Active",
	MaxLevel = 1,
	Description = "One serious punch that hits ALL enemies on the map."
}

-- Track active Serious Punch per player
local ActivePunchByUserId = {}

-- Execute Serious Punch - damage ALL enemies
local function executeSeriousPunch(player)
	-- Get player damage
	local baseDamage = player:GetAttribute("Damage") or 10
	local punchDamage = baseDamage * 10.0 -- 1000%
	
	-- Get all enemies on the map
	local enemiesHit = 0
	for _, enemy in ipairs(CollectionService:GetTagged("Enemy")) do
		if enemy:IsA("Model") then
			local hum = enemy:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				hum:TakeDamage(punchDamage)
				enemiesHit = enemiesHit + 1
				
				-- Show damage number
				local DamageNumbers = require(ReplicatedStorage.Scripts.Combat.DamageNumbers)
				local pos
				local ok, cf = pcall(function() return enemy:GetPivot() end)
				if ok and typeof(cf) == "CFrame" then
					pos = cf.Position
				else
					local hrp = enemy:FindFirstChild("HumanoidRootPart") or enemy.PrimaryPart
					pos = hrp and hrp.Position or Vector3.new(0, 0, 0)
				end
				
				if pos then
					DamageNumbers.Show({
						position = pos,
						amount = punchDamage,
						damageType = "crit" -- Show as crit for impact
					})
				end
			end
		end
	end
	
	print(string.format("[Serious Punch] Player %s punched %d enemies for %.0f damage each!",
		player.Name,
		enemiesHit,
		punchDamage
	))
end

-- Auto-punch loop
local function startPunchLoop(player)
	local cooldown = 90 -- seconds
	
	local thread = task.spawn(function()
		while true do
			-- Wait for cooldown
			task.wait(cooldown)
			
			-- Check if player still has the card
			if not ActivePunchByUserId[player.UserId] then
				break
			end
			
			-- Respect pause
			while ReplicatedStorage:GetAttribute("GamePaused") do
				task.wait(0.1)
			end
			
			-- Check if player still exists
			if not player.Parent or not player.Character then
				break
			end
			
			-- Execute punch
			executeSeriousPunch(player)
		end
	end)
	
	return thread
end

function def.OnCardAdded(player: Player, cardData, currentLevel: number)
	-- Check if player has awakened (Serious Training level 10)
	if not player:GetAttribute("SaitamaAwakened") then
		warn(string.format("[Serious Punch] Player %s tried to add Serious Punch without awakening!", player.Name))
		return
	end
	
	-- Cancel old thread if re-adding
	if ActivePunchByUserId[player.UserId] then
		local oldData = ActivePunchByUserId[player.UserId]
		if oldData.thread then
			task.cancel(oldData.thread)
		end
	end
	
	-- Start auto-punch loop
	local thread = startPunchLoop(player)
	
	ActivePunchByUserId[player.UserId] = {
		thread = thread
	}
	
	-- Execute first punch immediately
	task.delay(1, function()
		if ActivePunchByUserId[player.UserId] then
			executeSeriousPunch(player)
		end
	end)
	
	print(string.format("[Serious Punch] Player %s activated Serious Punch!", player.Name))
end

function def.OnCardRemoved(player: Player, cardData)
	local data = ActivePunchByUserId[player.UserId]
	if not data then return end
	
	-- Cancel auto-punch thread
	if data.thread then
		task.cancel(data.thread)
	end
	
	-- Cleanup
	ActivePunchByUserId[player.UserId] = nil
	
	print(string.format("[Serious Punch] Player %s deactivated Serious Punch", player.Name))
end

-- Cleanup on player leaving
game:GetService("Players").PlayerRemoving:Connect(function(player)
	local data = ActivePunchByUserId[player.UserId]
	if data and data.thread then
		task.cancel(data.thread)
	end
	ActivePunchByUserId[player.UserId] = nil
end)

return def
