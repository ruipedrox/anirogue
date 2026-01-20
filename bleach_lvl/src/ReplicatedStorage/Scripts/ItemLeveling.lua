-- ItemLeveling.lua
-- Sistema simples de níveis (1..MaxLevel) para itens equipados (Weapon/Armor/Ring).
-- Cada Stats.lua de item pode expor:
--   Levels = {
--      [1] = { BaseDamage = 25, AttackSpeed = 1.2 },
--      [2] = { BaseDamage = 30, AttackSpeed = 1.25 },
--      ...
--      [5] = { BaseDamage = 55, AttackSpeed = 1.4 },
--   }
-- Se Levels existir: usamos apenas a tabela do nível atual (merge com campos fora de Levels que não conflitam).
-- Se NÃO existir: comportamento antigo (usar todos os campos do módulo).
-- Armazenamento do nível:
--   Player/EquippedItemLevels/<ItemType> (IntValue)  ex.: Weapon=2, Armor=3, Ring=1
-- API pública:
--   ItemLeveling:Ensure(player) -> garante pasta e IntValues (default 1)
--   ItemLeveling:GetLevel(player, itemType)
--   ItemLeveling:SetLevel(player, itemType, newLevel)
--   ItemLeveling:BuildStatsFor(player, itemType, baseModuleTable) -> mergedStats

local ItemLeveling = {}

ItemLeveling.DefaultMaxLevel = 5
ItemLeveling.ValidTypes = { Weapon = true, Armor = true, Ring = true }

local function ensureFolder(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local function ensureInt(parent, name, default)
	local v = parent:FindFirstChild(name)
	if not v then
		v = Instance.new("IntValue")
		v.Name = name
		v.Value = default or 1
		v.Parent = parent
	end
	if v.Value < 1 then v.Value = 1 end
	return v
end

function ItemLeveling:Ensure(player)
	if not player then return end
	local root = ensureFolder(player, "EquippedItemLevels")
	for t,_ in pairs(self.ValidTypes) do
		ensureInt(root, t, 1)
	end
	return root
end

function ItemLeveling:GetLevel(player, itemType)
	if not (player and self.ValidTypes[itemType]) then return 1 end
	local root = player:FindFirstChild("EquippedItemLevels")
	if not root then return 1 end
	local iv = root:FindFirstChild(itemType)
	if not iv then return 1 end
	if iv.Value < 1 then iv.Value = 1 end
	return iv.Value
end

function ItemLeveling:SetLevel(player, itemType, newLevel)
	if not (player and self.ValidTypes[itemType]) then return false end
	local root = self:Ensure(player)
	local iv = root:FindFirstChild(itemType)
	if not iv then return false end
	if type(newLevel) ~= "number" then return false end
	newLevel = math.clamp(math.floor(newLevel), 1, self.DefaultMaxLevel)
	iv.Value = newLevel
	return true
end

-- Clona campos não-stat (ex: Rarity) e mescla stats do nível.
local function shallowCopy(tbl, dest)
	dest = dest or {}
	for k,v in pairs(tbl) do
		dest[k] = v
	end
	return dest
end

local function mergeLevel(baseModule, levelTable)
	local merged = {}
	-- Copiar tudo que NÃO está em Levels primeiro
	for k,v in pairs(baseModule) do
		if k ~= "Levels" then
			merged[k] = v
		end
	end
	-- Mesclar overrides do nível
	for k,v in pairs(levelTable or {}) do
		merged[k] = v
	end
	return merged
end

function ItemLeveling:BuildStatsFor(player, itemType, baseModuleTable)
	if type(baseModuleTable) ~= "table" then return nil end
	local levels = baseModuleTable.Levels
	if type(levels) ~= "table" then
		-- Sem tabela Levels: retorna original (cópia para segurança)
		return shallowCopy(baseModuleTable, {})
	end
	local level = self:GetLevel(player, itemType)
	local maxDefined = 1
	for k,_ in pairs(levels) do
		if type(k) == "number" and k > maxDefined then maxDefined = k end
	end
	if level > maxDefined then level = maxDefined end
	local levelStats = levels[level]
	if type(levelStats) ~= "table" then
		-- fallback seguro: usar nível 1
		levelStats = levels[1] or {}
	end
	return mergeLevel(baseModuleTable, levelStats)
end

return ItemLeveling
