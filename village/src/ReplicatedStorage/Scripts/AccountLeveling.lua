-- AccountLeveling.lua
-- Account-wide (persistent/infinite) leveling separate from run/character leveling.
-- Goal: use same XP inflow source as character wave XP (per-wave + completion bonus)
-- so balancing only touches WaveConfig, but with a different requirement curve
-- that is NOT exponential (to avoid late-game impossibility) and still slow early.
--
-- Design targets:
--  * First full run (~6,638 XP with current WaveConfig and completion bonus) reaches level 3.
--  * Unlock extra character equip slots at levels 5, 10, 20 (1 slot always available; then +1 each threshold, up to 4 total).
--  * Infinite progression: no hard cap – polynomial growth with power 1.2 (sub‑exponential).
--
-- Requirement formula (polynomial mode):
--   XPRequired(L) = BasePoly + ScalePoly * (L-1)^PowerPoly  for L >= 1
-- Parameters chosen (rounded for readability) to match the first-run target:
--   BasePoly  = 2800
--   ScalePoly = 450
--   PowerPoly = 1.2
-- Checkpoints (approx, individual level-up costs):
--   1->2 = 2800
--   2->3 = 2800 + 450*2^1.2 ≈ 3834   (cumulative ≈ 6634 ~ first run 6638 XP -> hits level 3 + a few XP leftover)
--   3->4 ≈ 4490
--   4->5 ≈ 5140  (cumulative to 5 ≈ 16k)
--   9->10 ≈  ~ (2800 + 450*9^1.2) ≈ 18k
--   19->20 ≈  ~ 31k
--
-- Tuning guidance:
--  * Faster early game: lower BasePoly (e.g. 2400) OR lower Power (e.g. 1.15)
--  * Slower early / stronger stretch: raise ScalePoly or Power.
--  * Introduce periodic ramps every 100 levels if needed: multiply by (1 + 0.15 * floor((L-1)/100)).
--
-- Public API:
--   AccountLeveling:Ensure(player) -> levelValue, xpValue, reqValue
--   AccountLeveling:AddXP(player, amount) -> levelsGained
--   AccountLeveling:GetXPData(player) -> { level, xp, required, fraction }
--   AccountLeveling:GetRequiredXP(level)
--   AccountLeveling:PredictTotalXP(targetLevel)
--   AccountLeveling:GetAllowedEquipSlots(level)
--
-- Internal value names under player.Stats:
--   AccountLevel (IntValue)
--   AccountXP (IntValue)
--   AccountXPRequired (IntValue)

local AccountLeveling = {}

AccountLeveling.BasePoly = 2800
AccountLeveling.ScalePoly = 450
AccountLeveling.PowerPoly = 1.2

-- Equip slot thresholds (beyond the always-available first slot)
AccountLeveling.SlotUnlockLevels = {5, 10, 20} -- total cap of 4 slots

local function ensureStatsFolder(player)
	local stats = player:FindFirstChild("Stats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "Stats"
		stats.Parent = player
	end
	return stats
end

local function ensureNumber(parent, name, default)
	local nv = parent:FindFirstChild(name)
	if not nv then
		nv = Instance.new("IntValue")
		nv.Name = name
		nv.Value = default or 0
		nv.Parent = parent
	end
	return nv
end

function AccountLeveling:GetRequiredXP(level)
	level = math.max(1, tonumber(level) or 1)
	local n = level - 1
	local req = self.BasePoly + self.ScalePoly * (n ^ self.PowerPoly)
	return math.floor(req + 0.5)
end

function AccountLeveling:GetAllowedEquipSlots(level)
	local slots = 1
	for _, thr in ipairs(self.SlotUnlockLevels) do
		if level >= thr then
			slots += 1
		end
	end
	if slots > 4 then slots = 4 end
	return slots
end

function AccountLeveling:Ensure(player)
	local stats = ensureStatsFolder(player)
	local lvl = ensureNumber(stats, "AccountLevel", 1)
	if lvl.Value < 1 then lvl.Value = 1 end
	local xp = ensureNumber(stats, "AccountXP", 0)
	local req = stats:FindFirstChild("AccountXPRequired")
	if not req then
		req = Instance.new("IntValue")
		req.Name = "AccountXPRequired"
		req.Parent = stats
	end
	req.Value = self:GetRequiredXP(lvl.Value)
	-- Hook level change (if externally modified)
	if not lvl:GetAttribute("_AccHooked") then
		lvl.Changed:Connect(function()
			if lvl.Value < 1 then lvl.Value = 1 end
			req.Value = self:GetRequiredXP(lvl.Value)
		end)
		lvl:SetAttribute("_AccHooked", true)
	end
	return lvl, xp, req
end

function AccountLeveling:AddXP(player, amount)
	amount = tonumber(amount) or 0
	if amount <= 0 then return 0 end
	local lvl, xp, req = self:Ensure(player)
	xp.Value += amount
	local gained = 0
	while xp.Value >= req.Value do
		xp.Value -= req.Value
		lvl.Value += 1
		gained += 1
		req.Value = self:GetRequiredXP(lvl.Value)
	end
	return gained
end

function AccountLeveling:GetXPData(player)
	if not player then return nil end
	local lvl, xp, req = self:Ensure(player)
	local required = math.max(1, req.Value)
	return {
		level = lvl.Value,
		xp = xp.Value,
		required = required,
		fraction = math.clamp(xp.Value / required, 0, 1)
	}
end

function AccountLeveling:PredictTotalXP(targetLevel)
	targetLevel = math.max(1, targetLevel)
	local sum = 0
	for l = 1, targetLevel - 1 do
		sum += self:GetRequiredXP(l)
	end
	return sum
end

return AccountLeveling
