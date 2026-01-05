-- Lobby Client Core (simplificado)
-- Responsável por sincronizar profile e permitir debug de stats.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local GetProfileRF = remotes:WaitForChild("GetProfile")
local ProfileUpdatedRE = remotes:WaitForChild("ProfileUpdated")
local DebugAddXP = remotes:WaitForChild("DebugAddXP")
local AddCharacterRE = remotes:WaitForChild("AddCharacter")
local EquipCharactersRE = remotes:WaitForChild("EquipCharacters")
local SetCharacterTierRE = remotes:WaitForChild("SetCharacterTier")
local StartRunRE = remotes:WaitForChild("StartRun")
local GetCharacterStatsRF = remotes:WaitForChild("GetCharacterStats")
local DebugGiveTestItems = remotes:WaitForChild("DebugGiveTestItems")

local cachedProfile
local _debugGiveCooldown = false

local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k,v in pairs(t) do
		out[k] = deepCopy(v)
	end
	return out
end

local function applyDelta(base, delta)
	for k,v in pairs(delta) do
		if type(v) == "table" and type(base[k]) == "table" then
			applyDelta(base[k], v)
		else
			base[k] = v
		end
	end
end

local function pretty(o, indent)
	indent = indent or 0
	local pad = string.rep(" ", indent)
	if type(o) == "table" then
		local parts = {"{"}
		for k,v in pairs(o) do
			table.insert(parts, string.format("%s  %s = %s", pad, tostring(k), pretty(v, indent + 2)))
		end
		table.insert(parts, pad.."}")
		return table.concat(parts, "\n")
	else
		return tostring(o)
	end
end

local function rebuildInstancesArray(instancesMap)
	local arr = {}
	for id, inst in pairs(instancesMap) do
		local copy = deepCopy(inst)
		copy.Id = id
		table.insert(arr, copy)
	end
	table.sort(arr, function(a,b) return a.Id < b.Id end)
	return arr
end

local function processFull(full)
	cachedProfile = full
	-- construir array Instances a partir do mapa
	cachedProfile.Characters.Instances = rebuildInstancesArray(cachedProfile.Characters.Instances)
	print("[Profile] Full snapshot recebido")
end

local function upsertInstances(updatedList)
	local map = {}
	for _, inst in ipairs(cachedProfile.Characters.Instances) do
		map[inst.Id] = inst
	end
	for _, u in ipairs(updatedList) do
		local existing = map[u.Id]
		if existing then
			for k,v in pairs(u) do
				existing[k] = v
			end
		else
			map[u.Id] = u
		end
	end
	cachedProfile.Characters.Instances = rebuildInstancesArray(map)
end

ProfileUpdatedRE.OnClientEvent:Connect(function(payload)
	if payload.full then
		processFull(payload.full)
		return
	end
	if not cachedProfile then return end
	if payload.account then
		applyDelta(cachedProfile.Account, payload.account)
	end
	if payload.characters then
		local cDelta = payload.characters
		if cDelta.Instances then
			-- substitui totalmente a lista (servidor enviou snapshot completo das instâncias)
			cachedProfile.Characters.Instances = {}
			for _, inst in ipairs(cDelta.Instances) do
				table.insert(cachedProfile.Characters.Instances, inst)
			end
		end
		if cDelta.EquippedOrder then
			cachedProfile.Characters.EquippedOrder = cDelta.EquippedOrder
		end
		if cDelta.Updated then
			upsertInstances(cDelta.Updated)
		end
	end
end)

-- Inicial: obter snapshot completo
local ok, result = pcall(function()
	return GetProfileRF:InvokeServer()
end)
if ok and result and result.profile then
	processFull(result.profile)
else
	warn("[Profile] Falhou GetProfile", result and result.error)
end

-- Debug hotkeys:
-- X -> +100 XP conta
-- C -> AddCharacter (Goku_3)
-- R -> StartRun
-- V -> GetCharacterStats e imprimir

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.X then
		DebugAddXP:FireServer(100)
	elseif input.KeyCode == Enum.KeyCode.C then
		AddCharacterRE:FireServer("Goku_3")
	elseif input.KeyCode == Enum.KeyCode.R then
		StartRunRE:FireServer()
	elseif input.KeyCode == Enum.KeyCode.V then
		if not cachedProfile then return end
		local stats = GetCharacterStatsRF:InvokeServer()
		print("[StatsPreview] =>", pretty(stats))
	elseif input.KeyCode == Enum.KeyCode.T then
		-- Debug: request server to give three test items (Kunai, ClothArmor, IronRing)
		if _debugGiveCooldown then return end
		_debugGiveCooldown = true
		if DebugGiveTestItems then
			DebugGiveTestItems:FireServer()
			print("[DebugGiveTestItems] request sent to server")
		else
			warn("[DebugGiveTestItems] Remote not found")
		end
		-- short debounce
		task.delay(0.5, function() _debugGiveCooldown = false end)
	end
end)

-- Função pública (exemplo) para UI futura
function GetEquippedInstances()
	if not cachedProfile then return {} end
	local set = {}
	local order = cachedProfile.Characters.EquippedOrder or {}
	local map = {}
	for _, inst in ipairs(cachedProfile.Characters.Instances) do
		map[inst.Id] = inst
	end
	for _, id in ipairs(order) do
		local inst = map[id]
		if inst then
			table.insert(set, inst)
		end
	end
	return set
end

-- Export via _G (temporário para debugging rápido)
_G.GetEquippedInstances = GetEquippedInstances

print("[LobbyClient] Inicializado. Hotkeys: X(+XP), C(AddChar), R(StartRun), V(StatsPreview)")