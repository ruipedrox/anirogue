-- CharactersModule
-- Stores equipped characters as references to ReplicatedStorage.Shared.Chars/<CharName>
-- Stores equipped characters as references to ReplicatedStorage.Shared.Chars/<CharName>

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharactersModule = {}

-- Default equipped character names (equip both for ability testing)
CharactersModule.DefaultEquippedNames = { "Sasuke_5", "Ichigo_5" }

-- Forward declaration to allow usage before definition inside Initialize
local collectEquippedInstances

local function getCharsFolder()
	-- Ensure the Chars folder is available; wait briefly if needed
	local shared = ReplicatedStorage:FindFirstChild("Shared") or ReplicatedStorage:WaitForChild("Shared", 5)
	return shared and (shared:FindFirstChild("Chars") or shared:WaitForChild("Chars", 5))
end

local function resolveCharFolderByName(name)
	local chars = getCharsFolder()
	if not chars then return nil end
	return chars:FindFirstChild(name)
end

-- Initialize equipped characters for a player by creating ObjectValues that point to char folders
function CharactersModule:Initialize(player)
	-- If instanced inventory and equipped slots exist, do NOT override with defaults.
	local instancesFolder = player:FindFirstChild("CharacterInstances")
	local equippedFolder = player:FindFirstChild("Equipped")
	local hasInstanced = instancesFolder and equippedFolder and #equippedFolder:GetChildren() > 0

	local function ensureChosenMatchesEquipped()
		local chosen = player:FindFirstChild("ChosenChars")
		if not chosen then
			chosen = Instance.new("Folder")
			chosen.Name = "ChosenChars"
			chosen.Parent = player
		else
			chosen:ClearAllChildren()
		end
		local charsRoot = getCharsFolder()
		if not charsRoot then return end
		local equipped = collectEquippedInstances(player)
		if equipped and #equipped > 0 then
			for _, info in ipairs(equipped) do
				local folder = charsRoot:FindFirstChild(info.TemplateName)
				if folder then
					local ov = Instance.new("ObjectValue")
					ov.Name = info.TemplateName
					ov.Value = folder
					ov:SetAttribute("InstanceId", info.InstanceId)
					ov.Parent = chosen
				end
			end
		end
	end

	if hasInstanced then
		-- Respect TeleportData/equipped instances; just make sure ChosenChars mirrors them
		ensureChosenMatchesEquipped()
		return
	end

	-- Legacy/default path: create ChosenChars with defaults when no instanced equip exists
	local charsFolder = player:FindFirstChild("ChosenChars")
	if not charsFolder then
		charsFolder = Instance.new("Folder")
		charsFolder.Name = "ChosenChars"
		charsFolder.Parent = player
	else
		charsFolder:ClearAllChildren()
	end

	local charsRoot = getCharsFolder()
	if not charsRoot then
		warn("[CharEquiped] ReplicatedStorage.Shared.Chars não encontrado; tentativa de equip falhou para", player and player.Name)
	end

	for _, name in ipairs(self.DefaultEquippedNames) do
		local charFolder = resolveCharFolderByName(name)
		if charFolder then
			local ov = Instance.new("ObjectValue")
			ov.Name = name
			ov.Value = charFolder -- store reference to character folder in ReplicatedStorage
			ov.Parent = charsFolder
		end
	end

	-- Se por algum motivo nenhum personagem foi adicionado, tentar equipar Goku_5 por defeito
	if #charsFolder:GetChildren() == 0 then
		local fallbackRoot = charsRoot or getCharsFolder()
		local fallback = fallbackRoot and fallbackRoot:FindFirstChild("Goku_5")
		if fallback then
			local ov = Instance.new("ObjectValue")
			ov.Name = "Goku_5"
			ov.Value = fallback
			ov.Parent = charsFolder
		else
			warn("[CharEquiped] Falha ao equipar fallback Goku_5; Chars root indisponível.")
		end
	end
end

-- Returns a list of character folders equipped by the player (Instances under ReplicatedStorage.Shared.Chars)
-- Returns a list of character folders equipped by the player (Instances under ReplicatedStorage.Shared.Chars)
function CharactersModule:GetEquippedFolders(player)
	-- Legacy path (ChosenChars) maintained for fallback / transitional systems
	local out = {}
	local chosen = player:FindFirstChild("ChosenChars")
	if not chosen then return out end
	for _, ov in ipairs(chosen:GetChildren()) do
		if ov:IsA("ObjectValue") and ov.Value and ov.Value.Parent == getCharsFolder() then
			table.insert(out, ov.Value)
		end
	end
	return out
end

-- New instanced system: resolve equipped instance data
collectEquippedInstances = function(player)
	local instancesFolder = player:FindFirstChild("CharacterInstances")
	local equippedFolder = player:FindFirstChild("Equipped")
	if not (instancesFolder and equippedFolder) then return nil end
	local result = {}
	-- Iterate slots in deterministic order
	local slots = {}
	for _, ch in ipairs(equippedFolder:GetChildren()) do
		if ch:IsA("StringValue") and ch.Name:match("^Slot%d+") then
			table.insert(slots, ch)
		end
	end
	table.sort(slots, function(a,b)
		local na = tonumber(a.Name:match("%d+")) or 0
		local nb = tonumber(b.Name:match("%d+")) or 0
		return na < nb
	end)
	for _, slotVal in ipairs(slots) do
		local inst = instancesFolder:FindFirstChild(slotVal.Value)
		if inst then
			local templateNameVal = inst:FindFirstChild("TemplateName")
			local levelVal = inst:FindFirstChild("Level")
			local xpVal = inst:FindFirstChild("XP")
			local tierVal = inst:FindFirstChild("Tier")
			if templateNameVal and templateNameVal:IsA("StringValue") then
				table.insert(result, {
					InstanceId = inst.Name,
					TemplateName = templateNameVal.Value,
					Level = levelVal and levelVal.Value or 1,
					XP = xpVal and xpVal.Value or 0,
					Tier = tierVal and tierVal:IsA("StringValue") and tierVal.Value or "B-",
				})
			end
		end
	end
	return result
end

-- Returns a list of tables with Name and Passives loaded from each character's Stats module
function CharactersModule:GetEquipped(player)
	local instanced = collectEquippedInstances(player)
	local result = {}
	if instanced and #instanced > 0 then
		local charsRoot = getCharsFolder()
		for _, info in ipairs(instanced) do
			local folder = charsRoot and charsRoot:FindFirstChild(info.TemplateName)
			local passives = {}
			if folder then
				local statsModule = folder:FindFirstChild("Stats")
				if statsModule and statsModule:IsA("ModuleScript") then
					local ok, mod = pcall(require, statsModule)
					if ok and type(mod) == "table" then
						passives = type(mod.Passives) == "table" and mod.Passives or {}
					end
				end
			end
			table.insert(result, {
				Name = info.TemplateName,
				InstanceId = info.InstanceId,
				Level = info.Level,
				XP = info.XP,
				Tier = info.Tier or "B-",
				Passives = passives,
			})
		end
		return result
	end
	-- Fallback legacy
	for _, folder in ipairs(self:GetEquippedFolders(player)) do
		local statsModule = folder:FindFirstChild("Stats")
		if statsModule and statsModule:IsA("ModuleScript") then
			local ok, mod = pcall(require, statsModule)
			if ok and type(mod) == "table" then
				table.insert(result, {
					Name = folder.Name,
					Passives = type(mod.Passives) == "table" and mod.Passives or {},
				})
			end
		end
	end
	return result
end

-- Public helper to change equipped slot at runtime (B)
function CharactersModule:EquipInstance(player, instanceId, slotIndex)
	local instancesFolder = player:FindFirstChild("CharacterInstances")
	local equippedFolder = player:FindFirstChild("Equipped")
	if not (instancesFolder and equippedFolder) then return false, "No inventory" end
	if not instancesFolder:FindFirstChild(instanceId) then return false, "Invalid instance" end
	local slotName = "Slot" .. tostring(slotIndex)
	local slot = equippedFolder:FindFirstChild(slotName)
	if not slot then
		slot = Instance.new("StringValue")
		slot.Name = slotName
		slot.Parent = equippedFolder
	end
	slot.Value = instanceId
	-- Atualizar ChosenChars retrocompat
	local chosen = player:FindFirstChild("ChosenChars")
	if chosen then
		chosen:ClearAllChildren()
		local chars = collectEquippedInstances(player)
		local charsRoot = getCharsFolder()
		if charsRoot and chars then
			for _, info in ipairs(chars) do
				local folder = charsRoot:FindFirstChild(info.TemplateName)
				if folder then
					local ov = Instance.new("ObjectValue")
					ov.Name = info.TemplateName
					ov.Value = folder
					ov:SetAttribute("InstanceId", info.InstanceId)
					ov.Parent = chosen
				end
			end
		end
	end
	return true
end

function CharactersModule:GetInstance(player, instanceId)
	local instancesFolder = player:FindFirstChild("CharacterInstances")
	if not instancesFolder then return nil end
	return instancesFolder:FindFirstChild(instanceId)
end

return CharactersModule
