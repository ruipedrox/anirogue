-- Infinity.lua
-- Gojo's Infinity - Slows enemies based on proximity (closer = stronger slow)
-- Level 1: 10%-40% slow | Level 5: 20%-80% slow

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Slow = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("Slow"))
local ProjectileStats = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("ProjectileStats"))

local def = {
	Name = "Infinity",
	Rarity = "Legendary",
	Type = "Passive",
	MaxLevel = 5,
	Description = "Slows enemies based on proximity. Closer enemies are slowed more."
}

-- Backwards-compat helper used by CardPool
def.maxLevel = def.maxLevel or def.MaxLevel
def.id = def.id or script.Name

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

	-- Try to use a prebuilt InfinitySphere model if available under ReplicatedStorage.Shared.Chars/Gojo*
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local chars = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("Chars")
	local sphere = nil
	if chars then
		for _, c in ipairs(chars:GetChildren()) do
			if type(c.Name) == "string" and string.find(c.Name:lower(), "gojo") then
				sphere = c:FindFirstChild("InfinitySphere") or c:FindFirstChild("Infinity_Sphere") or c:FindFirstChild("InfinitySphere", true)
				if sphere then break end
			end
		end
	end
	if sphere then
		local clone = sphere:Clone()
		-- Position and scale the sphere to the desired range
		if clone:IsA("Model") then
			-- Do not rescale the model when spawning; position it and weld to HRP for instant follow
			local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
			clone.Parent = workspace
			if primary then
				-- position
				primary.CFrame = hrp.CFrame
				-- ensure physics flags
				primary.CanCollide = false
				primary.CanQuery = false
				primary.CanTouch = false
				primary.Massless = true
				primary.Anchored = false
				-- weld to HRP for zero-lag follow
				local weld = Instance.new("WeldConstraint")
				weld.Name = "InfinityWeld"
				weld.Part0 = hrp
				weld.Part1 = primary
				weld.Parent = primary
			else
				-- Fallback: pivot whole model to HRP if no primary
				pcall(function() clone:PivotTo(hrp.CFrame) end)
			end
			return clone
		else
			-- For single BasePart assets, force a consistent size (30,30,30), position and weld
			clone.Parent = workspace
			if clone:IsA("BasePart") then
				clone.Size = Vector3.new(30, 30, 30)
				clone.CFrame = hrp.CFrame * CFrame.Angles(0, 0, math.pi/2)
				clone.CanCollide = false
				clone.CanQuery = false
				clone.CanTouch = false
				clone.Massless = true
				clone.Anchored = false
				local weld = Instance.new("WeldConstraint")
				weld.Name = "InfinityWeld"
				weld.Part0 = hrp
				weld.Part1 = clone
				weld.Parent = clone
			end
			return clone
		end
	end

	-- Fallback: create a simple part with consistent size
	local effect = Instance.new("Part")
	effect.Name = "InfinityEffect"
	effect.Size = Vector3.new(30, 30, 30)
	effect.Shape = Enum.PartType.Cylinder
	effect.Material = Enum.Material.Neon
	effect.Color = Color3.fromRGB(100, 200, 255)
	effect.Transparency = 0.85
	effect.Anchored = false
	effect.CanCollide = false
	effect.CanQuery = false
	effect.CanTouch = false
	effect.Massless = true
	effect.CFrame = hrp.CFrame * CFrame.Angles(0, 0, math.pi/2)
	effect.Parent = workspace
	-- Weld fallback part to HRP for instant follow
	local weld = Instance.new("WeldConstraint")
	weld.Name = "InfinityWeld"
	weld.Part0 = hrp
	weld.Part1 = effect
	weld.Parent = effect

	return effect
end

function def.OnEquip(player, level, maxLevel)
	level = math.clamp(level or 1, 1, maxLevel or def.MaxLevel)
	local userId = player.UserId
	
	-- Clean up existing
	if ActiveInfinityByUserId[userId] then
		def.OnUnequip(player)
	end

	-- Ensure RunTrack entry exists and reflect equipped level so CardPool can exclude when at max
	local runTrack = player:FindFirstChild("RunTrack") or Instance.new("Folder")
	runTrack.Name = "RunTrack"
	runTrack.Parent = player
	local myFolder = runTrack:FindFirstChild(def.id or script.Name) or Instance.new("Folder")
	myFolder.Name = def.id or script.Name
	myFolder.Parent = runTrack
	local lvlNV = myFolder:FindFirstChild("Level") or Instance.new("IntValue")
	lvlNV.Name = "Level"
	lvlNV.Value = tonumber(level) or (def.MaxLevel or def.maxLevel or 1)
	lvlNV.Parent = myFolder
	
	local stats = statsPerLevel[level]
	local character = player.Character
	if not character then return end
	
	local effect = createInfinityEffect(character, stats.range)

	-- Register aura with ProjectileStats so projectiles consult this registry
	ProjectileStats.RegisterAura(player, { range = stats.range, minSlow = stats.minSlow, maxSlow = stats.maxSlow })
	
	-- Heartbeat loop to apply slow
	-- Smooth follow + ticked slow application without yielding inside Heartbeat
	local acc = 0
	local connection = RunService.Heartbeat:Connect(function(delta)
		if not player.Parent or not character.Parent then
			def.OnUnequip(player)
			return
		end
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp and effect then
			-- If we welded the effect to the HRP (InfinityWeld exists) the weld enforces position with no lag.
			-- Only manually update position when no weld was created (defensive).
			local hasWeld = false
			if effect and effect.FindFirstChild then
				hasWeld = (effect:FindFirstChild("InfinityWeld", true) ~= nil)
			end
			if not hasWeld then
				if effect:IsA("Model") then
					local primary = effect.PrimaryPart or effect:FindFirstChildWhichIsA("BasePart")
					if primary then
						primary.CFrame = hrp.CFrame * CFrame.Angles(0, 0, math.pi/2)
					else
						pcall(function() effect:PivotTo(hrp.CFrame * CFrame.Angles(0, 0, math.pi/2)) end)
					end
				else
					effect.CFrame = hrp.CFrame * CFrame.Angles(0, 0, math.pi/2)
				end
			end
		end
		acc = acc + (delta or 0)
		if acc >= stats.tickRate then
			acc = acc - stats.tickRate
			applyInfinitySlow(character, stats)
		end
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

	-- Unregister aura
	ProjectileStats.UnregisterAura(player)
end

function def.OnLevelUp(player, newLevel)
	if ActiveInfinityByUserId[player.UserId] then
		def.OnEquip(player, newLevel)
	end
end

-- Compatibility for CardDispatcher: called when a card instance is added (levelable/stackable support)
function def.OnCardAdded(player, defTable, level)
	-- defTable is the card definition from the character Cards.lua; level indicates chosen level
	def.OnEquip(player, level or 1, defTable and tonumber(defTable.maxLevel))
end

-- Allow CardDispatcher.StopAllForPlayer to stop this aura
function def.Stop(player)
	def.OnUnequip(player)
end

return def
