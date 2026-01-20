-- Infinity.lua
-- Gojo's Infinity - Slows enemies based on proximity (closer = stronger slow)
-- Level 1: 10%-40% slow | Level 5: 20%-80% slow

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Slow = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("Slow"))

local def = {
	Name = "Infinity",
	Rarity = "Legendary",
	Type = "Passive",
	MaxLevel = 5,
	Description = "Slows enemies based on proximity. Closer enemies are slowed more."
}

-- Stats per level: minSlow (at max range), maxSlow (at min range), range, tickRate
local statsPerLevel = {
	[1] = { minSlow = 0.10, maxSlow = 0.40, range = 20, tickRate = 0.5, duration = 1.0 },
	[2] = { minSlow = 0.12, maxSlow = 0.50, range = 22, tickRate = 0.5, duration = 1.0 },
	[3] = { minSlow = 0.15, maxSlow = 0.60, range = 24, tickRate = 0.5, duration = 1.0 },
	[4] = { minSlow = 0.17, maxSlow = 0.70, range = 26, tickRate = 0.5, duration = 1.0 },
	[5] = { minSlow = 0.20, maxSlow = 0.80, range = 28, tickRate = 0.5, duration = 1.0 }
}

-- Track active Infinity per player
local ActiveInfinityByUserId = {}

-- Apply proximity-based slow to nearby enemies
local function applyInfinitySlow(playerChar, stats)
	local hrp = playerChar:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	local playerPos = hrp.Position
	
	for _, enemy in ipairs(CollectionService:GetTagged("Enemy")) do
		if enemy:IsA("Model") then
			local hum = enemy:FindFirstChildOfClass("Humanoid")
			local enemyHrp = enemy:FindFirstChild("HumanoidRootPart")
			
			if hum and hum.Health > 0 and enemyHrp then
				local distance = (enemyHrp.Position - playerPos).Magnitude
				
				if distance <= stats.range then
					-- Calculate slow percentage based on distance
					-- Closer = stronger slow (maxSlow), farther = weaker slow (minSlow)
					local distanceRatio = math.clamp(distance / stats.range, 0, 1)
					local slowPercent = stats.maxSlow - (distanceRatio * (stats.maxSlow - stats.minSlow))
					
					-- Apply slow
					Slow.Apply(hum, {
						percent = slowPercent,
						duration = stats.duration
					})
				end
			end
		end
	end
end

-- Visual effect for Infinity (optional blue aura)
local function createInfinityEffect(character, range)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	
	local effect = Instance.new("Part")
	effect.Name = "InfinityEffect"
	effect.Size = Vector3.new(range * 2, 0.5, range * 2)
	effect.Shape = Enum.PartType.Cylinder
	effect.Material = Enum.Material.Neon
	effect.Color = Color3.fromRGB(100, 200, 255)
	effect.Transparency = 0.85
	effect.Anchored = true
	effect.CanCollide = false
	effect.CanQuery = false
	effect.CanTouch = false
	effect.CFrame = hrp.CFrame * CFrame.Angles(0, 0, math.pi/2)
	effect.Parent = workspace
	
	return effect
end

function def.OnEquip(player, level)
	level = math.clamp(level or 1, 1, def.MaxLevel)
	local userId = player.UserId
	
	-- Clean up existing
	if ActiveInfinityByUserId[userId] then
		def.OnUnequip(player)
	end
	
	local stats = statsPerLevel[level]
	local character = player.Character
	if not character then return end
	
	local effect = createInfinityEffect(character, stats.range)
	
	-- Heartbeat loop to apply slow
	local connection = RunService.Heartbeat:Connect(function()
		if not player.Parent or not character.Parent then
			def.OnUnequip(player)
			return
		end
		
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp and effect then
			effect.CFrame = hrp.CFrame * CFrame.Angles(0, 0, math.pi/2)
		end
		
		applyInfinitySlow(character, stats)
		task.wait(stats.tickRate)
	end)
	
	ActiveInfinityByUserId[userId] = {
		connection = connection,
		effect = effect,
		level = level
	}
	
	print(string.format("[Infinity] Equipped for %s at level %d (Range: %d, Slow: %.0f%%-%.0f%%)",
		player.Name, level, stats.range, stats.minSlow * 100, stats.maxSlow * 100))
end

function def.OnUnequip(player)
	local userId = player.UserId
	local data = ActiveInfinityByUserId[userId]
	
	if data then
		if data.connection then
			data.connection:Disconnect()
		end
		if data.effect then
			data.effect:Destroy()
		end
		ActiveInfinityByUserId[userId] = nil
		print(string.format("[Infinity] Unequipped for %s", player.Name))
	end
end

function def.OnLevelUp(player, newLevel)
	if ActiveInfinityByUserId[player.UserId] then
		def.OnEquip(player, newLevel)
	end
end

return def
