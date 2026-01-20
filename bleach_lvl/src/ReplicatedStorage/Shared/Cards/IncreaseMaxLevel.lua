-- IncreaseMaxLevel.lua
-- Card Module: Applies +2 MaxLevel per card level (stackable up to maxLevel defined in card meta)
-- Integration: CardDispatcher.ApplyCard will call Apply(player, meta) when this card is chosen.
-- Tracks its own level in RunTrack folder: RunTrack/IncreaseMaxLevel/Level (IntValue)

local MODULE_FOLDER_NAME = "IncreaseMaxLevel"
local VALUE_NAME = "Level"
-- PER_LEVEL_BONUS is multiplicative percent (e.g., 0.10 = +10% per card level)
local PER_LEVEL_BONUS = 0.10

local IncreaseMaxLevel = {}

local function getLevelObjects(player)
	local runTrack = player:FindFirstChild("RunTrack")
	if not runTrack then
		runTrack = Instance.new("Folder")
		runTrack.Name = "RunTrack"
		runTrack.Parent = player
	end
	local folder = runTrack:FindFirstChild(MODULE_FOLDER_NAME) or Instance.new("Folder")
	folder.Name = MODULE_FOLDER_NAME
	folder.Parent = runTrack
	local level = folder:FindFirstChild(VALUE_NAME) or Instance.new("IntValue")
	level.Name = VALUE_NAME
	level.Parent = folder
	return folder, level
end

local function ensureXPRateNV(player)
	local stats = player:FindFirstChild("Stats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "Stats"
		stats.Parent = player
	end
	local nv = stats:FindFirstChild("xpgainrate")
	if not nv then
		nv = Instance.new("NumberValue")
		nv.Name = "xpgainrate"
		nv.Value = 1 -- base multiplier
		nv.Parent = stats
	end
	return nv
end

local function applyBonus(player, currentCardLevel)
	local nv = ensureXPRateNV(player)
	-- Store base once for reversibility
	local base = nv:GetAttribute("_BaseValue")
	if not base then
		base = nv.Value
		nv:SetAttribute("_BaseValue", base)
	end
	-- New multiplier = base * (1 + PER_LEVEL_BONUS * currentCardLevel)
	nv.Value = base * (1 + PER_LEVEL_BONUS * currentCardLevel)
end

function IncreaseMaxLevel.Apply(player, meta)
	local folder, level = getLevelObjects(player)
	local current = level.Value or 0
	local newLevel = math.min((current + 1), meta.maxLevel or 1)
	level.Value = newLevel
	applyBonus(player, newLevel)
end

return IncreaseMaxLevel
