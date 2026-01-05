local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Referências aos ModuleScripts (Instances) dos itens default
-- Mantemos a pasta Items/Rings como está (plural), mas o player equipa apenas 1 anel.
local DefaultWeaponModule = ReplicatedStorage.Shared.Items.Weapons.Kunai:WaitForChild("Stats")
local DefaultArmorModule = ReplicatedStorage.Shared.Items.Armors.ClothArmor:WaitForChild("Stats")
local DefaultRingModule = ReplicatedStorage.Shared.Items.Rings.IronRing:WaitForChild("Stats")
local ItemsRegistry = require(ReplicatedStorage.Shared.Items:WaitForChild("Registry"))

local EquippedItemsModule = {}

-- Helper: apply quality multiplier to numeric stats
local function applyQuality(statsTable, qualityName)
	if type(statsTable) ~= "table" or type(qualityName) ~= "string" or qualityName == "" then
		return statsTable
	end
	local ok, Qualities = pcall(function()
		return require(ReplicatedStorage.Shared.Items:WaitForChild("ItemQualities"))
	end)
	if not ok or type(Qualities) ~= "table" then
		return statsTable
	end
	local mult = Qualities[qualityName]
	if type(mult) ~= "number" then
		return statsTable
	end
	local out = {}
	for k, v in pairs(statsTable) do
		if type(v) == "number" then
			out[k] = v * (1 + mult)
		else
			out[k] = v
		end
	end
	return out
end

-- Cria a pasta para armazenar os itens equipados do jogador
function EquippedItemsModule:Initialize(player)
	local equippedFolder = player:FindFirstChild("EquippedItems")
	if not equippedFolder then
		equippedFolder = Instance.new("Folder")
		equippedFolder.Name = "EquippedItems"
		equippedFolder.Parent = player
	end

	-- If already equipped (e.g., set by TeleportData earlier), do not override
	local function hasEquipped()
		local w = equippedFolder:FindFirstChild("Weapon")
		local a = equippedFolder:FindFirstChild("Armor")
		local r = equippedFolder:FindFirstChild("Ring")
		return w and w.Value or a and a.Value or r and r.Value
	end
	if hasEquipped() then
		return
	end

	-- Ensure keys exist
	local function ensureSlot(name)
		local v = equippedFolder:FindFirstChild(name)
		if not v then
			v = Instance.new("ObjectValue")
			v.Name = name
			v.Parent = equippedFolder
		end
		return v
	end

	local weaponValue = ensureSlot("Weapon")
	local armorValue = ensureSlot("Armor")
	local ringValue = ensureSlot("Ring")

	-- Try to read TeleportData-equipped templates first
	local td
	pcall(function()
		local join = player:GetJoinData()
		td = join and join.TeleportData
	end)
	local items = td and td.Items
	local eqt = items and items.EquippedTemplates
	if type(eqt) == "table" then
		if eqt.Weapon then self:EquipItemById(player, "Weapon", eqt.Weapon) end
		if eqt.Armor then self:EquipItemById(player, "Armor", eqt.Armor) end
		if eqt.Ring then self:EquipItemById(player, "Ring", eqt.Ring) end
		-- If any slot still empty, fall back per-slot
		if not weaponValue.Value then weaponValue.Value = DefaultWeaponModule end
		if not armorValue.Value then armorValue.Value = DefaultArmorModule end
		if not ringValue.Value then ringValue.Value = DefaultRingModule end
		return
	end

	-- Fall back to defaults
	weaponValue.Value = DefaultWeaponModule
	armorValue.Value = DefaultArmorModule
	ringValue.Value = DefaultRingModule
end

-- Atualiza um item equipado
-- itemType = "Weapon", "Armor" ou "Ring"
-- itemModule deve ser um ModuleScript (Instance) com um retorno de tabela de stats
function EquippedItemsModule:EquipItem(player, itemType, itemModule)
	local equippedFolder = player:FindFirstChild("EquippedItems")
	if not equippedFolder then return end

	local itemValue = equippedFolder:FindFirstChild(itemType)
	if itemValue and typeof(itemModule) == "Instance" and itemModule:IsA("ModuleScript") then
		itemValue.Value = itemModule
	end
end

-- Atualiza por ID (ex.: EquipItemById(player, "Weapon", "Kunai"))
function EquippedItemsModule:EquipItemById(player, itemType, itemId)
	local module = ItemsRegistry:GetModule(itemType, itemId)
	if not module then
		pcall(function() print("[EquipItemById] Module not found for", itemType, itemId) end)
		return end
	pcall(function() print("[EquipItemById] Resolved module for", itemType, itemId, "->", tostring(module)) end)
	self:EquipItem(player, itemType, module)
end

-- Retorna todos os itens equipados (como tabelas de stats)
function EquippedItemsModule:GetEquipped(player)
	local equippedFolder = player:FindFirstChild("EquippedItems")
	if not equippedFolder then return nil end

	local function getStats(childName)
		local obj = equippedFolder:FindFirstChild(childName)
		if not obj or not obj.Value then return nil end
		if typeof(obj.Value) == "Instance" and obj.Value:IsA("ModuleScript") then
			local ok, result = pcall(require, obj.Value)
			if ok and type(result) == "table" then
				-- Aplicar sistema de níveis se existir
				local itemType
				if childName == "Weapon" then itemType = "Weapon"
				elseif childName == "Armor" then itemType = "Armor"
				elseif childName == "Ring" then itemType = "Ring" end
				if itemType then
					local okLevel, ItemLeveling = pcall(function()
						return require(game.ReplicatedStorage.Scripts:WaitForChild("ItemLeveling"))
					end)
					if okLevel and ItemLeveling then
						local leveled = ItemLeveling:BuildStatsFor(player, itemType, result)
						-- Apply quality multiplier if available for this slot
						local qf = player:FindFirstChild("EquippedItemQualities")
						local qv = qf and qf:FindFirstChild(childName)
						local quality = qv and qv:IsA("StringValue") and qv.Value or nil
						return applyQuality(leveled or result, quality)
					end
				end
				-- Apply quality even if no leveling module
				local qf = player:FindFirstChild("EquippedItemQualities")
				local qv = qf and qf:FindFirstChild(childName)
				local quality = qv and qv:IsA("StringValue") and qv.Value or nil
				return applyQuality(result, quality)
			end
		end
		return nil
	end

	return {
		weapon = getStats("Weapon"),
		armor = getStats("Armor"),
		ring = getStats("Ring"), -- único anel equipado (aplica nível)
	}
end

-- Serializa os itens equipados para IDs (para TeleportService/Datastore)
function EquippedItemsModule:Serialize(player)
	local equippedFolder = player:FindFirstChild("EquippedItems")
	if not equippedFolder then
		return { Weapon = nil, Armor = nil, Ring = nil }
	end
	local function getId(childName, itemType)
		local obj = equippedFolder:FindFirstChild(childName)
		if not obj or not obj.Value then return nil end
		return ItemsRegistry:GetIdForModule(obj.Value, itemType)
	end
	return {
		Weapon = getId("Weapon", "Weapon"),
		Armor = getId("Armor", "Armor"),
		Ring = getId("Ring", "Ring"),
	}
end

-- Desserializa IDs e equipa itens
function EquippedItemsModule:Deserialize(player, data)
	if not data or type(data) ~= "table" then return end
	if data.Weapon then self:EquipItemById(player, "Weapon", data.Weapon) end
	if data.Armor then self:EquipItemById(player, "Armor", data.Armor) end
	if data.Ring then self:EquipItemById(player, "Ring", data.Ring) end
end

return EquippedItemsModule
