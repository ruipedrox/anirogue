-- Slow.lua - Movement speed reduction system
-- Multiple slows DO NOT stack; only the strongest slow is applied
-- Example: 20% slow + 30% slow = only 30% slow is active

local Slow = {}
local CollectionService = game:GetService("CollectionService")

-- Track active slows per enemy
-- [humanoid] = { slows = { {percent, endTime, originalSpeed} }, currentPercent }
local ActiveSlows = {}

-- Apply slow effect to a target humanoid
-- opts = {
--   percent: number,        -- Slow percentage (0.2 = 20% slow, 0.5 = 50% slow)
--   duration: number,       -- Duration in seconds
-- }
function Slow.Apply(targetHumanoid: Humanoid, opts)
	if not targetHumanoid or targetHumanoid.Health <= 0 then return end
	if not opts or not opts.percent or not opts.duration then return end
	
	local percent = math.clamp(tonumber(opts.percent) or 0, 0, 1)
	local duration = tonumber(opts.duration) or 0
	
	if percent <= 0 or duration <= 0 then return end
	
	-- Initialize tracking for this humanoid if not exists
	if not ActiveSlows[targetHumanoid] then
		ActiveSlows[targetHumanoid] = {
			slows = {},
			currentPercent = 0,
			originalSpeed = targetHumanoid.WalkSpeed
		}
	end
	
	local data = ActiveSlows[targetHumanoid]
	local endTime = os.clock() + duration
	
	-- Add this slow to the list
	table.insert(data.slows, {
		percent = percent,
		endTime = endTime,
		originalSpeed = data.originalSpeed
	})
	
	-- Update to strongest slow
	updateStrongestSlow(targetHumanoid, data)
	
	-- Schedule cleanup when this slow expires
	task.delay(duration, function()
		cleanupExpiredSlows(targetHumanoid)
	end)
end

-- Update humanoid speed to match the strongest active slow
function updateStrongestSlow(humanoid: Humanoid, data)
	local now = os.clock()
	local maxPercent = 0
	
	-- Find strongest slow
	for _, slow in ipairs(data.slows) do
		if slow.endTime > now and slow.percent > maxPercent then
			maxPercent = slow.percent
		end
	end
	
	-- Apply strongest slow
	if maxPercent > 0 then
		local reduction = 1 - maxPercent
		humanoid.WalkSpeed = data.originalSpeed * reduction
		data.currentPercent = maxPercent
	else
		-- No active slows, restore original speed
		humanoid.WalkSpeed = data.originalSpeed
		data.currentPercent = 0
	end
end

-- Clean up expired slows and update speed
function cleanupExpiredSlows(humanoid: Humanoid)
	if not humanoid or humanoid.Health <= 0 then
		ActiveSlows[humanoid] = nil
		return
	end
	
	local data = ActiveSlows[humanoid]
	if not data then return end
	
	local now = os.clock()
	local newSlows = {}
	
	-- Remove expired slows
	for _, slow in ipairs(data.slows) do
		if slow.endTime > now then
			table.insert(newSlows, slow)
		end
	end
	
	data.slows = newSlows
	
	-- If no slows remain, clean up completely
	if #newSlows == 0 then
		humanoid.WalkSpeed = data.originalSpeed
		ActiveSlows[humanoid] = nil
	else
		-- Update to strongest remaining slow
		updateStrongestSlow(humanoid, data)
	end
end

-- Get current slow info for a humanoid (for UI/debugging)
function Slow.GetInfo(humanoid: Humanoid)
	local data = ActiveSlows[humanoid]
	if not data then return nil end
	
	local now = os.clock()
	local activeCount = 0
	local maxPercent = 0
	local remainingTime = 0
	
	for _, slow in ipairs(data.slows) do
		if slow.endTime > now then
			activeCount += 1
			if slow.percent > maxPercent then
				maxPercent = slow.percent
				remainingTime = slow.endTime - now
			end
		end
	end
	
	return {
		isSlowed = maxPercent > 0,
		percent = maxPercent,
		activeSlows = activeCount,
		remainingTime = remainingTime,
		originalSpeed = data.originalSpeed,
		currentSpeed = humanoid.WalkSpeed
	}
end

-- Clear all slows from a humanoid (useful for cleanse effects)
function Slow.Clear(humanoid: Humanoid)
	local data = ActiveSlows[humanoid]
	if not data then return end
	
	humanoid.WalkSpeed = data.originalSpeed
	ActiveSlows[humanoid] = nil
end

-- Cleanup when humanoid dies
local function onHumanoidDied(humanoid: Humanoid)
	ActiveSlows[humanoid] = nil
end

-- Hook into humanoid death events
CollectionService:GetInstanceAddedSignal("Enemy"):Connect(function(enemy)
	local humanoid = enemy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			onHumanoidDied(humanoid)
		end)
	end
end)

return Slow
