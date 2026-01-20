-- CharacterInventory.lua
-- Responsável por reconstruir (ou inicializar) inventário de personagens instanciados a partir de TeleportData
-- Estruturas criadas:
--   player.CharacterInstances/<InstanceId>/{ TemplateName:StringValue, Level:IntValue, XP:IntValue }
--   player.Equipped/Slot1..SlotN (StringValue.Value = InstanceId)
--   player.ChosenChars (retrocompat) -> ObjectValues apontando para ReplicatedStorage.Shared.Chars/<TemplateName>
--   player.ChosenChars (retrocompat) -> ObjectValues apontando para ReplicatedStorage.Shared.Chars/<TemplateName>
-- Uso: CharacterInventory.Rebuild(player)

local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharactersModule -- lazy require para evitar ciclos (apenas para DefaultEquippedNames)

local CharacterInventory = {}

local function getCharsFolder()
	local shared = ReplicatedStorage:FindFirstChild("Shared") or ReplicatedStorage:WaitForChild("Shared", 5)
	return shared and (shared:FindFirstChild("Chars") or shared:WaitForChild("Chars", 5))
end

local function createInstanceFolder(parent, instanceId, templateName, level, xp, tier)
	local f = Instance.new("Folder")
	f.Name = instanceId
	f.Parent = parent
	local tn = Instance.new("StringValue") tn.Name = "TemplateName" tn.Value = templateName tn.Parent = f
	local lv = Instance.new("IntValue") lv.Name = "Level" lv.Value = level or 1 lv.Parent = f
	local xpV = Instance.new("IntValue") xpV.Name = "XP" xpV.Value = xp or 0 xpV.Parent = f
	if tier and type(tier) == "string" and tier ~= "" then
		local tv = Instance.new("StringValue") tv.Name = "Tier" tv.Value = tier tv.Parent = f
	end
	return f
end

local function buildChosenChars(player, instancesFolder, equippedFolder)
	local chosen = player:FindFirstChild("ChosenChars")
	if chosen then chosen:ClearAllChildren() else
		chosen = Instance.new("Folder")
		chosen.Name = "ChosenChars"
		chosen.Parent = player
	end
	local charsRoot = getCharsFolder()
	if not charsRoot then return end
	-- sort SlotN values deterministically
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
			local templateFolder = templateNameVal and charsRoot:FindFirstChild(templateNameVal.Value)
			if templateFolder then
				local ov = Instance.new("ObjectValue")
				ov.Name = templateNameVal.Value
				ov.Value = templateFolder
				ov:SetAttribute("InstanceId", inst.Name)
				ov.Parent = chosen
			end
		end
	end
end

function CharacterInventory.Rebuild(player, teleportDataOverride)
	-- Accept an optional teleportDataOverride (provided by caller) and fall back to TeleportService:GetPlayerTeleportData
	local teleportData = teleportDataOverride
	if not teleportData then
		local ok, td = pcall(function()
			local fn = TeleportService.GetPlayerTeleportData
			if typeof(fn) == "function" then
				return TeleportService:GetPlayerTeleportData(player)
			end
			return nil
		end)
		if ok then teleportData = td end
	end

	local existingInstances = player:FindFirstChild("CharacterInstances")
	local existingEquipped = player:FindFirstChild("Equipped")

	local hasTeleportCharacters = teleportData and type(teleportData) == "table" and (
		type(teleportData.CharacterInstances) == "table" or type(teleportData.Equipped) == "table"
	)

	if not hasTeleportCharacters then
		-- No TeleportData provided: if structures already exist and have content, just mirror to ChosenChars
		if existingInstances and existingEquipped and #existingInstances:GetChildren() > 0 and #existingEquipped:GetChildren() > 0 then
			buildChosenChars(player, existingInstances, existingEquipped)
			return
		end
	end

	-- Rebuild from scratch either when TeleportData present (authoritative) or when empty state
	if existingInstances then existingInstances:Destroy() end
	if existingEquipped then existingEquipped:Destroy() end

	local instancesFolder = Instance.new("Folder")
	instancesFolder.Name = "CharacterInstances"
	instancesFolder.Parent = player

	local equippedFolder = Instance.new("Folder")
	equippedFolder.Name = "Equipped"
	equippedFolder.Parent = player

	local equippedIds = {}
	if hasTeleportCharacters then
		-- Populate from TeleportData
		local tdChars = teleportData.CharacterInstances
		if type(tdChars) == "table" then
			for instanceId, data in pairs(tdChars) do
				if type(data) == "table" and data.TemplateName then
					createInstanceFolder(instancesFolder, instanceId, data.TemplateName, tonumber(data.Level) or 1, tonumber(data.XP) or 0, data.Tier)
				end
			end
		end
		local tdEquipped = teleportData.Equipped
		if type(tdEquipped) == "table" then
			for _, instId in ipairs(tdEquipped) do
				if typeof(instId) == "string" and instancesFolder:FindFirstChild(instId) then
					equippedIds[#equippedIds+1] = instId
				end
			end
		end
	end

	if #instancesFolder:GetChildren() == 0 then
		-- default fallback only if no TeleportData provided anything
		CharactersModule = CharactersModule or require(ReplicatedStorage.Scripts.CharEquiped)
		for _, templateName in ipairs(CharactersModule.DefaultEquippedNames) do
			local newId = templateName .. "_" .. string.format("%d_%d", os.time()%100000, math.random(1000,9999))
			createInstanceFolder(instancesFolder, newId, templateName, 1, 0)
			equippedIds[#equippedIds+1] = newId
		end
	end

	for slotIndex, instId in ipairs(equippedIds) do
		local sv = Instance.new("StringValue")
		sv.Name = "Slot" .. slotIndex
		sv.Value = instId
		sv.Parent = equippedFolder
	end

	buildChosenChars(player, instancesFolder, equippedFolder)
end

return CharacterInventory
