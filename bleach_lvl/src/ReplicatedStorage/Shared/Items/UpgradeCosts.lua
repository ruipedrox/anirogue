-- UpgradeCosts.lua
-- Tabela e utilitários para calcular o custo de upgrade por raridade e nível
-- Apenas custos (não realiza o upgrade). Máximo nível = 5.
-- Níveis considerados aqui são os níveis atuais do item (custo é para subir para o próximo):
-- 1 -> 2, 2 -> 3, 3 -> 4, 4 -> 5. Para nível 5 não há custo (já é o máximo).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Opcional: tentar resolver raridade a partir do módulo de stats do item
local Shared = ReplicatedStorage:FindFirstChild("Shared")
local ItemsShared = Shared and Shared:FindFirstChild("Items")
local ItemRegistry = ItemsShared and ItemsShared:FindFirstChild("Registry")
local ItemRegistryModule = ItemRegistry and require(ItemRegistry)

local M = {}

M.MaxLevel = 5 -- nível máximo permitido

-- Conversão de entrada de raridade (strings pt/en e números/estrelas) para chaves internas
local function mapRarityKey(raw)
	if raw == nil then return "comum" end
	local t = typeof(raw)
	if t == "number" then
		local n = math.floor(raw)
		if n <= 1 then return "comum" end
		if n == 2 then return "raro" end
		if n == 3 then return "epico" end
		if n >= 4 then return "lendario" end
	end
	local s = tostring(raw):lower()
	if s:find("legend") or s:find("lend") then return "lendario" end
	if s:find("epic") or s:find("épico") or s:find("epico") then return "epico" end
	if s:find("rare") or s:find("raro") then return "raro" end
	if s:find("myth") or s:find("mit") then return "mitico" end
	if s:find("common") or s:find("comum") then return "comum" end
	return "comum"
end

-- Base por nível (custo para subir do nível N para N+1)
-- Ajusta aqui conforme o balance deseado.
-- Tabelas explícitas por raridade (custos por salto de nível: 1->2, 2->3, 3->4, 4->5)
-- Mantêm a filosofia: iniciais baratos e último salto caro (late-game)
M.Table = {
	comum = {
		[1] = 50,
		[2] = 200,
		[3] = 500,
		[4] = 2500,
	},
	raro = {
		[1] = 100,   -- 50*1.75 arredondado
		[2] = 350,  -- 200*1.75
		[3] = 875,  -- 500*1.75
		[4] = 4375, -- 2500*1.75
	},
	epico = {
		[1] = 150,  -- 50*3.0
		[2] = 600,  -- 200*3.0
		[3] = 1500, -- 500*3.0
		[4] = 7500, -- 2500*3.0
	},
	lendario = {
		[1] = 250,   -- 50*5.0
		[2] = 1000,  -- 200*5.0
		[3] = 2500,  -- 500*5.0
		[4] = 12500, -- 2500*5.0
	},
	mitico = {
		[1] = 300,   -- 50*6.0
		[2] = 1200,  -- 200*6.0
		[3] = 3000,  -- 500*6.0
		[4] = 15000, -- 2500*6.0
	},
}

-- Obtém custo diretamente por raridade (string/numero) e nível atual.
-- Retorna nil se nível já for >= MaxLevel.
function M:GetByRarity(rarity, currentLevel)
	currentLevel = tonumber(currentLevel) or 1
	if currentLevel >= self.MaxLevel then return nil end
	local key = mapRarityKey(rarity)
	local tier = self.Table[key] or self.Table.comum
	return tier[currentLevel]
end

-- Tenta resolver raridade a partir do módulo de stats do item (group/template) e retorna custo
-- Se não encontrar raridade, assume comum.
function M:GetForItem(itemGroup, templateName, currentLevel)
	currentLevel = tonumber(currentLevel) or 1
	if currentLevel >= self.MaxLevel then return nil end
	local rarity = "comum"
	if ItemRegistryModule then
		local ok, mod = pcall(function()
			return ItemRegistryModule:GetModule(itemGroup, templateName)
		end)
		if ok and mod then
			local ok2, stats = pcall(function() return require(mod) end)
			if ok2 and type(stats) == "table" then
				rarity = stats.Rarity or stats.rarity or stats.stars or rarity
			end
		end
	end
	return self:GetByRarity(rarity, currentLevel)
end

-- Opcional: custo total para ir de nível A até B (exclusivo de B, i.e. somando os saltos A->A+1->...->B)
function M:GetTotalByRarity(rarity, fromLevel, toLevel)
	fromLevel = tonumber(fromLevel) or 1
	toLevel = tonumber(toLevel) or self.MaxLevel
	if toLevel <= fromLevel then return 0 end
	local total = 0
	for lvl = fromLevel, math.min(toLevel - 1, self.MaxLevel - 1) do
		total += self:GetByRarity(rarity, lvl) or 0
	end
	return total
end

return M
