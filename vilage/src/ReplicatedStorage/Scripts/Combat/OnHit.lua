-- OnHit.lua
-- Auxiliary on-hit effects only (no base damage or DoT here)

local OnHit = {}

-- Helpers to read numbers/bools from a Stats folder
local function getNumber(stats: Folder?, name: string, default)
	local nv = stats and stats:FindFirstChild(name)
	if nv and nv:IsA("NumberValue") then return nv.Value end
	return default
end
local function getBool(stats: Folder?, name: string, default)
	local bv = stats and stats:FindFirstChild(name)
	if bv and bv:IsA("BoolValue") then return bv.Value end
	return default
end

-- context: {
--   player: Player,
--   statsFolder: Folder, -- player.Stats
-- }
-- target: Humanoid
function OnHit.Process(context, targetHumanoid: Humanoid)
	if not targetHumanoid then return end
	local stats = context and context.statsFolder
	local isCrit = context and context.isCrit or false

	local onHit = stats and stats:FindFirstChild("OnHit")
	if not onHit or not onHit:IsA("Folder") then return end

	-- Example 1: Lifesteal as FRACTION of last hit damage (e.g., 0.05 = 5%)
	-- Expect a NumberValue "Lifesteal" under Stats; if a more specific OnHit/Lifesteal value exists, use that.
	do
		local lsNode = onHit:FindFirstChild("Lifesteal")
		local lifestealPercent = nil
		if lsNode and lsNode:IsA("NumberValue") then
			lifestealPercent = lsNode.Value
		else
			lifestealPercent = getNumber(stats, "Lifesteal", 0)
		end
		if lifestealPercent and lifestealPercent > 0 then
			-- Heal exactly based on dealt damage passed from attack context
			local dealt = tonumber(context and context.dealt) or 0
			local heal = dealt * lifestealPercent
			local player = context and context.player
			local character = player and player.Character
			local hum = character and character:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and heal > 0 then
				hum.Health = math.min(hum.MaxHealth, hum.Health + heal)
			end
		end
	end

	-- Example 2: BonusDoT effect defined under OnHit (e.g., extra burn)
	-- OnHit/BonusDoT folder with NumberValues: TotalTime, TotalDamage, Tick; optional BoolValue CritScales
	do
		local dot = onHit:FindFirstChild("BonusDoT")
		if dot and dot:IsA("Folder") then
			local totalTimeVal = dot:FindFirstChild("TotalTime")
			local totalDamageVal = dot:FindFirstChild("TotalDamage")
			local tickVal = dot:FindFirstChild("Tick")
			local critScalesVal = dot:FindFirstChild("CritScales")
			local totalTime = tonumber(totalTimeVal and totalTimeVal.Value) or 0
			local totalDamage = tonumber(totalDamageVal and totalDamageVal.Value) or 0
			local tick = tonumber(tickVal and tickVal.Value) or 0.25
			local critScales = critScalesVal and critScalesVal:IsA("BoolValue") and critScalesVal.Value or false
			if totalTime > 0 and totalDamage > 0 then
				local mult = 1
				if critScales and isCrit then
					mult = getNumber(stats, "CritDamage", 1)
				end
				-- Lazy require here to avoid circulars if any
				local DoT = require(script.Parent:WaitForChild("DoT"))
				DoT.Apply(targetHumanoid, { totalTime = totalTime, totalDamage = totalDamage * mult, tick = tick })
			end
		end
	end
end

return OnHit
