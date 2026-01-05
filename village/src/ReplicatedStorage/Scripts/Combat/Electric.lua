-- Electric.lua - Chain Lightning system
-- Not a DoT but affected by DoT efficiency
-- Stacks: multiple cards increase chain count and damage percent

local Electric = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local DamageNumbers = require(ReplicatedStorage.Scripts.Combat.DamageNumbers)

-- Track electric stacks per player
local ElectricStacks = {} -- [player] = { chainCount: number, damagePercent: number }

local function getNearestEnemies(originPos: Vector3, maxRange: number, excludeModel, maxCount: number)
	local enemies = {}
	
	for _, enemy in ipairs(CollectionService:GetTagged("Enemy")) do
		if enemy and enemy.Parent and enemy ~= excludeModel then
			local humanoid = enemy:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local ok, cf = pcall(function() return enemy:GetPivot() end)
				local pos
				if ok and typeof(cf) == "CFrame" then
					pos = cf.Position
				else
					local pp = enemy.PrimaryPart or enemy:FindFirstChild("HumanoidRootPart")
					pos = pp and pp.Position or nil
				end
				
				if pos then
					local dist = (pos - originPos).Magnitude
					if dist <= maxRange then
						table.insert(enemies, {
							model = enemy,
							humanoid = humanoid,
							position = pos,
							distance = dist
						})
					end
				end
			end
		end
	end
	
	-- Sort by distance
	table.sort(enemies, function(a, b) return a.distance < b.distance end)
	
	-- Return up to maxCount
	local result = {}
	for i = 1, math.min(maxCount, #enemies) do
		table.insert(result, enemies[i])
	end
	
	return result
end

-- Visual lightning effect between two positions
local function createLightningEffect(startPos: Vector3, endPos: Vector3)
	local distance = (endPos - startPos).Magnitude
	local midPoint = (startPos + endPos) / 2
	
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(100, 200, 255)
	beam.Transparency = 0.3
	beam.Size = Vector3.new(0.3, 0.3, distance)
	beam.CFrame = CFrame.lookAt(midPoint, endPos)
	beam.Parent = workspace
	
	-- Fade out
	task.spawn(function()
		for i = 1, 10 do
			beam.Transparency = 0.3 + (i / 10) * 0.7
			task.wait(0.03)
		end
		beam:Destroy()
	end)
end

-- Apply chain lightning effect
-- opts = { player: Player, originModel: Model, damage: number, chainCount: number?, damagePercent: number? }
function Electric.Apply(opts)
	if not opts or not opts.originModel then return end
	
	local originModel = opts.originModel
	local baseDamage = opts.damage or 0
	if baseDamage <= 0 then return end
	
	-- Get chain parameters (default or from stacks)
	local chainCount = opts.chainCount or 2
	local damagePercent = opts.damagePercent or 0.30
	
	-- Get origin position
	local ok, cf = pcall(function() return originModel:GetPivot() end)
	local originPos
	if ok and typeof(cf) == "CFrame" then
		originPos = cf.Position
	else
		local pp = originModel.PrimaryPart or originModel:FindFirstChild("HumanoidRootPart")
		if not pp then return end
		originPos = pp.Position
	end
	
	-- ALWAYS apply electric damage to the initial target first
	local originHumanoid = originModel:FindFirstChildOfClass("Humanoid")
	if originHumanoid and originHumanoid.Health > 0 then
		local electricDamage = baseDamage * damagePercent
		originHumanoid:TakeDamage(electricDamage)
		
		-- Show damage number on initial target
		DamageNumbers.Show({
			position = originPos,
			amount = electricDamage,
			damageType = "electric"
		})
	end
	
	-- If chainCount > 0, proceed with chain lightning to nearby enemies
	if chainCount <= 0 then return end
	
	-- Start chain from the initial target
	local currentPos = originPos
	local excludedModels = {[originModel] = true}
	local chainRange = 15 -- studs
	
	for i = 1, chainCount do
		-- Find next target
		local nearbyEnemies = getNearestEnemies(currentPos, chainRange, nil, 10)
		
		-- Filter out already hit enemies
		local validTargets = {}
		for _, enemy in ipairs(nearbyEnemies) do
			if not excludedModels[enemy.model] then
				table.insert(validTargets, enemy)
			end
		end
		
		if #validTargets == 0 then
			-- No more targets, chain ends
			break
		end
		
		-- Hit closest valid target
		local target = validTargets[1]
		local chainDamage = baseDamage * damagePercent
		
		-- Apply damage
		target.humanoid:TakeDamage(chainDamage)
		
		-- Show damage number
		DamageNumbers.Show({
			position = target.position,
			amount = chainDamage,
			damageType = "electric"
		})
		
		-- Visual effect
		createLightningEffect(currentPos, target.position)
		
		-- Update for next chain
		currentPos = target.position
		excludedModels[target.model] = true
		
		-- Small delay between chains
		task.wait(0.05)
	end
end

-- Add electric stack for a player (called when card is equipped)
function Electric.AddStack(player: Player, chainCount: number, damagePercent: number)
	if not ElectricStacks[player] then
		ElectricStacks[player] = {
			chainCount = 0,
			damagePercent = 0
		}
	end
	
	-- Stack: add chain count and damage percent
	ElectricStacks[player].chainCount = ElectricStacks[player].chainCount + chainCount
	ElectricStacks[player].damagePercent = ElectricStacks[player].damagePercent + damagePercent
	
	print(string.format("[Electric] Player %s now has %d chains at %.0f%% damage each", 
		player.Name, 
		ElectricStacks[player].chainCount, 
		ElectricStacks[player].damagePercent * 100
	))
end

-- Remove electric stack for a player (called when card is removed)
function Electric.RemoveStack(player: Player, chainCount: number, damagePercent: number)
	if not ElectricStacks[player] then return end
	
	ElectricStacks[player].chainCount = math.max(0, ElectricStacks[player].chainCount - chainCount)
	ElectricStacks[player].damagePercent = math.max(0, ElectricStacks[player].damagePercent - damagePercent)
	
	-- Cleanup if no stacks left
	if ElectricStacks[player].chainCount == 0 and ElectricStacks[player].damagePercent == 0 then
		ElectricStacks[player] = nil
	end
end

-- Get current electric stats for a player
function Electric.GetStats(player: Player)
	return ElectricStacks[player] or { chainCount = 0, damagePercent = 0 }
end

-- Cleanup on player leaving
game:GetService("Players").PlayerRemoving:Connect(function(player)
	ElectricStacks[player] = nil
end)

return Electric
