-- SuperWarrior.lua (no loop)
-- Provides helper to equip the correct Goku aura (SW1, SW2, SW3, SWG, SWB) for a given level.
-- Called once when the card is chosen / level increases.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local M = {}

-- Internal helpers reused from other card modules
local function ensureFolder(parent: Instance, name: string)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local function ensureNumber(parent: Instance, name: string, value: number)
	local nv = parent:FindFirstChild(name)
	if not nv then
		nv = Instance.new("NumberValue")
		nv.Name = name
		nv.Value = value
		nv.Parent = parent
	end
	return nv
end

local function clearAura(character: Model)
	local oldContainer = character:FindFirstChild("GokuAuraContainer")
	if oldContainer then pcall(function() oldContainer:Destroy() end) end
	local oldHighlight = character:FindFirstChild("GokuAura")
	if oldHighlight then pcall(function() oldHighlight:Destroy() end) end
end

local function equipNow(player: Player, level: number)
	local character = player.Character
	if not player or not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	if not hrp then return end
	clearAura(character)
	local charsFolder = ReplicatedStorage:FindFirstChild("Chars")
	local gokuFolder = charsFolder and charsFolder:FindFirstChild("Goku_5")
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local charsFolder = shared and shared:FindFirstChild("Chars")
	local gokuFolder = charsFolder and charsFolder:FindFirstChild("Goku_5")
	if not gokuFolder then return end
	local names = { "ssj1", "ssj2", "ssj3", "ssg", "ssb" }
	local idx = math.clamp(level, 1, 5)
	local template = gokuFolder:FindFirstChild(names[idx])
	if not template then
		warn(string.format("[SuperWarrior] Aura template '%s' não encontrada em Chars/Goku_5.", names[idx]))
		warn(string.format("[SuperWarrior] Aura template '%s' não encontrada em Shared/Chars/Goku_5.", names[idx]))
		return
	end
	local container = Instance.new("Folder")
	container.Name = "GokuAuraContainer"
	container.Parent = character
	local clone = template:Clone()
	clone.Name = "GokuAuraInstance"
	clone.Parent = container
	if clone:IsA("Model") then
		local primary = clone.PrimaryPart or clone:FindFirstChild("HumanoidRootPart")
		if not primary then
			for _, d in ipairs(clone:GetDescendants()) do
				if d:IsA("BasePart") then primary = d break end
			end
			if primary then clone.PrimaryPart = primary end
		end
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then d.Anchored = false end
		end
		if primary then
			clone:PivotTo(hrp.CFrame)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = hrp
			weld.Part1 = primary
			weld.Parent = primary
		end
	elseif clone:IsA("BasePart") then
		clone.Anchored = false
		clone.CFrame = hrp.CFrame
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hrp
		weld.Part1 = clone
		weld.Parent = clone
	else
		clone.Parent = hrp
	end
end

function M.EquipAuraForLevel(player: Player, level: number)
	if player.Character then
		equipNow(player, level)
	else
		local conn
		conn = player.CharacterAdded:Connect(function()
			if conn then conn:Disconnect() end
			task.defer(function() equipNow(player, level) end)
		end)
	end
end

function M.Clear(player: Player)
	local char = player.Character
	if char then clearAura(char) end
end

-- Apply or level-up SuperWarrior.
-- Updated: grants percent bonuses relative to TOTAL stats, not just base.
-- Per level: +10% DamagePercent (multiplier), +10% AttackSpeed (as AttackSpeedPercent), +4% MoveSpeed (as MoveSpeedPercent).
-- Also equips the corresponding aura (levels 1..5).
function M.Apply(player: Player, def)
	def = def or {}
	if not player or not player.Parent then return end
	-- Track levels under RunTrack/GokuForms/Level (IntValue)
	local runTrack = ensureFolder(player, "RunTrack")
	local forms = ensureFolder(runTrack, "GokuForms")
	local levelNV = forms:FindFirstChild("Level")
	if not levelNV then
		levelNV = Instance.new("IntValue")
		levelNV.Name = "Level"
		levelNV.Value = 0
		levelNV.Parent = forms
	end
	local maxLevel = tonumber(def.maxLevel) or 5
	if levelNV.Value >= maxLevel then
		-- Already capped; just re-equip aura in case character respawned
		M.EquipAuraForLevel(player, levelNV.Value)
		return levelNV.Value
	end
	levelNV.Value = math.clamp(levelNV.Value + 1, 0, maxLevel)
	local current = levelNV.Value

	-- Upgrades folder for additive and percent stats
	local upgrades = ensureFolder(player, "Upgrades")
	local function addUpgrade(name: string, delta: number)
		if type(delta) ~= "number" or delta == 0 then return end
		local u = upgrades:FindFirstChild(name)
		if not u then
			u = Instance.new("NumberValue")
			u.Name = name
			u.Value = 0
			u.Parent = upgrades
		end
		u.Value += delta
		-- Mirror immediately into Stats if present
		local stats = player:FindFirstChild("Stats")
		if stats then
			local s = stats:FindFirstChild(name)
			if not s then
				s = Instance.new("NumberValue")
				s.Name = name
				s.Value = 0
				s.Parent = stats
			end
			s.Value += delta
		end
	end

	-- Apply per-level increments as percents relative to final totals
	addUpgrade("DamagePercent", 10)        -- +10% damage per level (percent units -> multiplicative in damage calc)
	addUpgrade("AttackSpeedPercent", 10)   -- +10% attack speed per level (percent of total)
	-- Movement speed: accumulate as MoveSpeedPercent (+4% per level) and let ApplyStats apply on total speed
	addUpgrade("MoveSpeedPercent", 4)      -- +4% move speed per level (percent of total)

	-- Equip aura for this level
	M.EquipAuraForLevel(player, current)

	-- Reapply full stats so Humanoid.MaxHealth/WalkSpeed reflect upgrades consistently
	pcall(function()
		local ApplyStats = require(ReplicatedStorage.Scripts.ApplyStats)
		local EquippedItems = require(ReplicatedStorage.Scripts.EquipedItems)
		local CharEquipped = require(ReplicatedStorage.Scripts.CharEquiped)
		local items = EquippedItems:GetEquipped(player)
		local chars = CharEquipped:GetEquipped(player)
		ApplyStats:Apply(player, items, chars)
	end)

	return current
end

return M
