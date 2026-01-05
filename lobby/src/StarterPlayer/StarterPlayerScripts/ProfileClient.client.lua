-- ProfileClient.client.lua
-- Cliente: recebe snapshot inicial e escuta updates.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Espera pela pasta Remotes com timeout preventivo para evitar infinite yield warnings.
local function waitFor(childParent, name, timeout)
	timeout = timeout or 5
	local t0 = time()
	local obj = childParent:FindFirstChild(name)
	while not obj and (time() - t0) < timeout do
		childParent.ChildAdded:Wait()
		obj = childParent:FindFirstChild(name)
	end
	return obj
end

local Remotes = waitFor(ReplicatedStorage, "Remotes", 5)
if not Remotes then
	warn("[ProfileClient] Pasta Remotes não encontrada após timeout.")
	return
end

local function safeWait(remoteName)
	local r = waitFor(Remotes, remoteName, 5)
	if not r then warn("[ProfileClient] Remote faltando:", remoteName) end
	return r
end

local GetProfile = safeWait("GetProfile") :: RemoteFunction
local ProfileUpdated = safeWait("ProfileUpdated") :: RemoteEvent
local DebugAddXP = safeWait("DebugAddXP") :: RemoteEvent
local AddCharacter = Remotes:FindFirstChild("AddCharacter")
local EquipCharacters = Remotes:FindFirstChild("EquipCharacters")
local SetCharacterTier = Remotes:FindFirstChild("SetCharacterTier")
local StartRun = Remotes:FindFirstChild("StartRun")

local localPlayer = Players.LocalPlayer

local currentProfile -- snapshot simplificado recebido do servidor

local function deepMerge(dst, src)
	for k,v in pairs(src) do
		if type(v) == "table" and type(dst[k]) == "table" then
			deepMerge(dst[k], v)
		else
			dst[k] = v
		end
	end
end

local function printAccount(acc)
	print(string.format("[ProfileClient] Account: Lv %d (%.0f/%.0f) Slots=%d Coins=%d",
		acc.Level, acc.XP, acc.Required, acc.EquipSlots, currentProfile.Account and currentProfile.Account.Coins or 0))
end

local function applyFull(full)
	currentProfile = full
	print("[ProfileClient] Full profile recebido.")
	printAccount(full.Account)
end

local function rebuildInstancesList(instancesArray)
	if not currentProfile then return end
	currentProfile.Characters = currentProfile.Characters or {}
	currentProfile.Characters.Instances = instancesArray
end

ProfileUpdated.OnClientEvent:Connect(function(payload)
	if payload.full then
		applyFull(payload.full)
		return
	end
	if not currentProfile then return end
	if payload.account then
		deepMerge(currentProfile.Account, payload.account)
		printAccount(currentProfile.Account)
	end
	if payload.characters then
		local chars = payload.characters
		currentProfile.Characters = currentProfile.Characters or {}
		if chars.Instances then
			-- full replacement
			currentProfile.Characters.Instances = chars.Instances
		end
		if chars.EquippedOrder then
			currentProfile.Characters.EquippedOrder = chars.EquippedOrder
		end
		if chars.Updated and currentProfile.Characters.Instances then
			-- apply partial updates by Id
			local byId = {}
			for _, inst in ipairs(currentProfile.Characters.Instances) do
				byId[inst.Id] = inst
			end
			for _, upd in ipairs(chars.Updated) do
				local target = byId[upd.Id]
				if target then
					for k,v in pairs(upd) do
						if k ~= "Id" then target[k] = v end
					end
				end
			end
		end
		print("[ProfileClient] Characters update recebido.")
	end
end)

-- Fallback: caso primeiro evento chegue atrasado
if not currentProfile then
	local ok, result = pcall(function()
		return GetProfile:InvokeServer()
	end)
	if ok and result and result.profile then
		applyFull(result.profile)
	else
		warn("[ProfileClient] Falha ao obter profile inicial", result)
	end
end

-- DEBUG: tecla X adiciona 500 XP (remover depois)
local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.X then
		DebugAddXP:FireServer(50000)
	end
end)

-- DEBUG EXTRA (tecla C adiciona temp character Goku_3):
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.C and AddCharacter then
		AddCharacter:FireServer("Goku_5")
		AddCharacter:FireServer("Goku_4")
		AddCharacter:FireServer("Krillin_3")
		AddCharacter:FireServer("Kame_4")
	end
end)

-- DEBUG: tecla R inicia StartRun (apenas imprime payload no servidor)
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.R and StartRun then
		StartRun:FireServer()
		print("[Client] StartRun pedido.")
	end
end)
