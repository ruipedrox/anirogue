-- Remotes.server.lua
-- Criação de remotes básicos para Profile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

-- Criar pasta Remotes imediatamente para evitar "Infinite yield" em clientes muito rápidos
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
end

-- LOG inicial
print("[Remotes] Pasta 'Remotes' pronta (server init)")

-- Toggle this to true while debugging snapshot quality issues to enable verbose dumps
local DEBUG_SNAPSHOT_DUMPS = false

local function dbg_snapshot_print(...)
	if DEBUG_SNAPSHOT_DUMPS then
		print(...)
	end
end

-- Requerimentos após garantir a pasta
local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")
local ProfileService = require(ScriptsFolder:WaitForChild("ProfileService"))
local AccountLeveling = require(ScriptsFolder:WaitForChild("AccountLeveling"))
local CharacterService = require(ScriptsFolder:WaitForChild("CharacterService"))
local RunService = require(ScriptsFolder:WaitForChild("RunService"))
local StatsPreview = require(ScriptsFolder:WaitForChild("StatsPreview"))
local HttpService = game:GetService("HttpService")
local CharacterInventory = require(ScriptsFolder:WaitForChild("CharacterInventory"))
local SaleAudit = require(ScriptsFolder:WaitForChild("SaleAudit"))
local SummonModule = require(ScriptsFolder:WaitForChild("SummonModule"))

local GetProfileRF = Instance.new("RemoteFunction")
GetProfileRF.Name = "GetProfile"
GetProfileRF.Parent = remotesFolder

local ProfileUpdatedRE = Instance.new("RemoteEvent")
ProfileUpdatedRE.Name = "ProfileUpdated"
ProfileUpdatedRE.Parent = remotesFolder

local DebugAddXP = Instance.new("RemoteEvent")
DebugAddXP.Name = "DebugAddXP"
DebugAddXP.Parent = remotesFolder

local AddCharacterRE = Instance.new("RemoteEvent")
AddCharacterRE.Name = "AddCharacter"
AddCharacterRE.Parent = remotesFolder

local EquipCharactersRE = Instance.new("RemoteEvent")
EquipCharactersRE.Name = "EquipCharacters"
EquipCharactersRE.Parent = remotesFolder

local EquipOneRE = Instance.new("RemoteEvent")
EquipOneRE.Name = "EquipOne"
EquipOneRE.Parent = remotesFolder

local UnequipOneRE = Instance.new("RemoteEvent")
UnequipOneRE.Name = "UnequipOne"
UnequipOneRE.Parent = remotesFolder

-- Remote events for equipping/unequipping items (client -> server)
local EquipItemRE = Instance.new("RemoteEvent")
EquipItemRE.Name = "EquipItem"
EquipItemRE.Parent = remotesFolder

local UnequipItemRE = Instance.new("RemoteEvent")
UnequipItemRE.Name = "UnequipItem"
UnequipItemRE.Parent = remotesFolder

local SellCharacterRE = Instance.new("RemoteEvent")
SellCharacterRE.Name = "SellCharacter"
SellCharacterRE.Parent = remotesFolder

-- Simple SellItem remote for equipment: fixed price by rarity (comum/raro/epico/lendario)
local SellItemRE = Instance.new("RemoteEvent")
SellItemRE.Name = "SellItem"
SellItemRE.Parent = remotesFolder

-- Upgrade an equipment item (deduct Coins, increase Level)
local RequestItemUpgradeRF = Instance.new("RemoteFunction")
RequestItemUpgradeRF.Name = "RequestItemUpgrade"
RequestItemUpgradeRF.Parent = remotesFolder

-- In-memory sell locks to prevent concurrent double-sell (instanceId -> player)
-- This is a lightweight mitigation against rapid double FireClient/OnServerEvent abuse.
local sellLocks = {}

local function acquireSellLock(player, id)
	if not id then return false end
	if sellLocks[id] then return false end
	sellLocks[id] = player
	return true
end

local function releaseSellLock(id)
	sellLocks[id] = nil
end

-- Novo: aumentar capacidade do inventário de personagens
local IncreaseCapacityRE = Instance.new("RemoteEvent")
IncreaseCapacityRE.Name = "IncreaseCapacity"
IncreaseCapacityRE.Parent = remotesFolder

local SetCharacterTierRE = Instance.new("RemoteEvent")
SetCharacterTierRE.Name = "SetCharacterTier"
SetCharacterTierRE.Parent = remotesFolder

local StartRunRE = Instance.new("RemoteEvent")
StartRunRE.Name = "StartRun"
StartRunRE.Parent = remotesFolder

local GetCharacterStatsRF = Instance.new("RemoteFunction")
GetCharacterStatsRF.Name = "GetCharacterStats"
GetCharacterStatsRF.Parent = remotesFolder

local GetCharacterInventoryRF = Instance.new("RemoteFunction")
GetCharacterInventoryRF.Name = "GetCharacterInventory"
GetCharacterInventoryRF.Parent = remotesFolder

-- Summon-related remotes (UI <-> Server)
local RequestSummonRE = Instance.new("RemoteEvent")
RequestSummonRE.Name = "RequestSummon"
RequestSummonRE.Parent = remotesFolder

local SummonGrantedRE = Instance.new("RemoteEvent")
SummonGrantedRE.Name = "SummonGranted"
SummonGrantedRE.Parent = remotesFolder

local OpenSummonRE = Instance.new("RemoteEvent")
OpenSummonRE.Name = "Open_Summon"
OpenSummonRE.Parent = remotesFolder

local BannerUpdatedRE = Instance.new("RemoteEvent")
BannerUpdatedRE.Name = "BannerUpdated"
BannerUpdatedRE.Parent = remotesFolder

-- Debug: grant gems/coins (Studio-only)
local DebugAddGemsRE = Instance.new("RemoteEvent")
DebugAddGemsRE.Name = "DebugAddGems"
DebugAddGemsRE.Parent = remotesFolder

local DebugAddCoinsRE = Instance.new("RemoteEvent")
DebugAddCoinsRE.Name = "DebugAddCoins"
DebugAddCoinsRE.Parent = remotesFolder

-- SummonState removed: client now decides open/close locally. Keep single Open_Summon remote.

-- Story progression remotes
local GetStoryProgressRF = Instance.new("RemoteFunction")
GetStoryProgressRF.Name = "GetStoryProgress"
GetStoryProgressRF.Parent = remotesFolder

local StoryLevelCompletedRE = Instance.new("RemoteEvent")
StoryLevelCompletedRE.Name = "StoryLevelCompleted"
StoryLevelCompletedRE.Parent = remotesFolder

-- Start a Story run with selected map/level
local StartStoryRunRE = Instance.new("RemoteEvent")
StartStoryRunRE.Name = "StartStoryRun"
StartStoryRunRE.Parent = remotesFolder

-- Debug: Remote to grant three test items (Kunai, ClothArmor, IronRing)
local DebugGiveTestItemsRE = Instance.new("RemoteEvent")
DebugGiveTestItemsRE.Name = "DebugGiveTestItems"
DebugGiveTestItemsRE.Parent = remotesFolder

local function sendFullProfile(player)
	local profile = ProfileService:Get(player)
	if not profile then
		-- Race guard: if client asked before PlayerAdded handler created/sent, create/load now
		profile = ProfileService:CreateOrLoad(player)
	end
	if not profile then return nil end
	return {
		profile = ProfileService:BuildClientSnapshot(profile),
		serverTime = os.time(),
	}
end

-- Helper: inspect snapshot for any blank/nil qualities and then fire the ProfileUpdated event
local function inspectAndFireFullSnapshot(player, snapshot)
	if not snapshot or not snapshot.Items then
		ProfileUpdatedRE:FireClient(player, { full = snapshot })
		return
	end
	-- Inspect Categories if present
	local items = snapshot.Items
	if items.Categories and type(items.Categories) == "table" then
		for catName, catData in pairs(items.Categories) do
			if type(catData) == "table" and catData.List and type(catData.List) == "table" then
				for _, entry in ipairs(catData.List) do
					local q = entry.Quality
					if q == nil or (type(q) == "string" and q:match("^%s*$")) then
						warn(string.format("[Remotes] Snapshot: blank Quality in Categories -> category=%s id=%s Quality=%s (type=%s)", tostring(catName), tostring(entry.Id), tostring(q), type(q)))
						-- Verbose dump gated
						for _, e2 in ipairs(catData.List) do
							dbg_snapshot_print(string.format("[Remotes][DUMP] Categories.%s -> Id=%s Template=%s Quality=%s", tostring(catName), tostring(e2.Id), tostring(e2.Template), tostring(e2.Quality)))
						end
					end
				end
			end
		end
	end
	-- Inspect raw Owned structure for completeness
	if items.Owned and type(items.Owned) == "table" then
		for groupName, grp in pairs(items.Owned) do
			if type(grp) == "table" then
				if grp.Instances and type(grp.Instances) == "table" then
					for instId, instData in pairs(grp.Instances) do
						local q = instData and instData.Quality
						if q == nil or (type(q) == "string" and q:match("^%s*$")) then
							warn(string.format("[Remotes] Snapshot: blank Quality in Owned.Instances -> group=%s inst=%s Template=%s Quality=%s (type=%s)", tostring(groupName), tostring(instId), tostring(instData and instData.Template), tostring(q), type(q)))
							-- Verbose dumps are gated behind DEBUG_SNAPSHOT_DUMPS to avoid noisy logs in normal runs
							for iid, idata in pairs(grp.Instances) do
								dbg_snapshot_print(string.format("[Remotes][DUMP] Owned.%s.Instances -> Id=%s Template=%s Quality=%s", tostring(groupName), tostring(iid), tostring(idata and idata.Template), tostring(idata and idata.Quality)))
							end
						end
					end
				else
					for itemId, data in pairs(grp) do
						if type(data) == "table" then
							local q = data.Quality
							if q == nil or (type(q) == "string" and q:match("^%s*$")) then
								warn(string.format("[Remotes] Snapshot: blank Quality in Owned (legacy) -> group=%s id=%s Quality=%s (type=%s)", tostring(groupName), tostring(itemId), tostring(q), type(q)))
								for iid, idata in pairs(grp) do
									dbg_snapshot_print(string.format("[Remotes][DUMP] Owned.%s (legacy) -> Id=%s Template=%s Quality=%s", tostring(groupName), tostring(iid), tostring(idata and idata.Template), tostring(idata and idata.Quality)))
								end
							end
						end
					end
				end
			end
		end
	end

	-- Fire the snapshot after inspection
	ProfileUpdatedRE:FireClient(player, { full = snapshot })
end

GetProfileRF.OnServerInvoke = function(player)
	local ok, res = pcall(function()
		return sendFullProfile(player)
	end)
	if not ok then
		warn("[GetProfile] error:", res)
		-- Last-attempt fallback
		local prof = ProfileService:CreateOrLoad(player)
		if prof then
			return {
				profile = ProfileService:BuildClientSnapshot(prof),
				serverTime = os.time(),
			}
		end
		return nil
	end
	return res
end

-- Story progression snapshot
GetStoryProgressRF.OnServerInvoke = function(player)
	local ok, res = pcall(function()
		return ProfileService:GetStorySnapshot(player)
	end)
	if not ok then
		warn("[GetStoryProgress] error:", res)
		return { error = "ServerError" }
	end
	return res
end

-- Retorna stats calculados para todas as instâncias do jogador (ou subset opcional de Ids)
GetCharacterStatsRF.OnServerInvoke = function(player, ids)
	local profile = ProfileService:Get(player)
	if not profile then return { error = "NoProfile" } end

	local instancesArray = {}
	if type(ids) == "table" and #ids > 0 then
		for _, id in ipairs(ids) do
			local inst = profile.Characters.Instances[id]
			if inst then
				instancesArray[#instancesArray+1] = { Id = id, Template = inst.TemplateName, Level = inst.Level or 1, Tier = inst.Tier or "B-" }
			end
		end
	else
		for id, inst in pairs(profile.Characters.Instances) do
			instancesArray[#instancesArray+1] = { Id = id, Template = inst.TemplateName, Level = inst.Level or 1, Tier = inst.Tier or "B-" }
		end
	end

	local previews = StatsPreview:BuildForInstances(instancesArray)
	return { list = previews, serverTime = os.time() }
end

-- Retorna inventário enriquecido (dados de catálogo + preview) para UI
GetCharacterInventoryRF.OnServerInvoke = function(player)
	local profile = ProfileService:Get(player)
	if not profile then return { error = "NoProfile" } end
	local inv = CharacterInventory.Build(profile)
	return { inventory = inv, serverTime = os.time() }
end

Players.PlayerAdded:Connect(function(player)
	local profile = ProfileService:CreateOrLoad(player)
	-- Enviar snapshot inicial via ProfileUpdated (ou cliente pode chamar GetProfile manualmente)
	inspectAndFireFullSnapshot(player, ProfileService:BuildClientSnapshot(profile))
end)

-- QA helper: allow opening Summon UI by chat command for quick testing
Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(msg)
		if not msg then return end
		local lower = tostring(msg):lower()
		if lower == "/summon" or lower == "/opensummon" then
			pcall(function() OpenSummonRE:FireClient(player, "Summon") end)
		end
	end)
end)

-- Start run (debug) apenas constrói payload e imprime no servidor
StartRunRE.OnServerEvent:Connect(function(player)
	local ok, err = RunService:StartRun(player)
	if not ok then
		warn("[StartRun] Falhou:", err)
	end
end)

-- Client informs server that a story level was completed; server updates unlocks
StoryLevelCompletedRE.OnServerEvent:Connect(function(player, mapId, level)
	local ok, snapshotOrErr = ProfileService:MarkStoryLevelCompleted(player, mapId, tonumber(level) or 0)
	if not ok then
		warn("[StoryLevelCompleted] Failed:", snapshotOrErr)
		return
	end
	-- Optionally push a lightweight message; client can also poll GetStoryProgress
	ProfileUpdatedRE:FireClient(player, { story = snapshotOrErr })
end)

-- Helper: find a Story map module by Id and return the table
local function loadStoryMapById(targetId)
	local RS = game:GetService("ReplicatedStorage")
	local Shared = RS:FindFirstChild("Shared")
	if not Shared then return nil end
	local Maps = Shared:FindFirstChild("Maps")
	if not Maps then return nil end
	local Story = Maps:FindFirstChild("Story")
	if not Story then return nil end
	for _, folder in ipairs(Story:GetChildren()) do
		if folder:IsA("Folder") then
			local mod = folder:FindFirstChild("Map")
			if mod and mod:IsA("ModuleScript") then
				local ok, map = pcall(function() return require(mod) end)
				if ok and type(map) == "table" then
					local id = tostring(map.Id or map.DisplayName or "")
					if id == tostring(targetId) then
						return map
					end
				end
			end
		end
	end
	return nil
end

-- Handle client Play -> teleport to the correct place with story payload
StartStoryRunRE.OnServerEvent:Connect(function(player, mapId, level)
	mapId = tostring(mapId or "")
	level = tonumber(level) or 0
	if mapId == "" or level < 1 or level > 3 then
		warn("[StartStoryRun] bad args from", player.Name, mapId, level)
		return
	end

	local okSnap, snapshot = pcall(function()
		return ProfileService:GetStorySnapshot(player)
	end)
	if not okSnap or type(snapshot) ~= "table" then
		warn("[StartStoryRun] snapshot fail for", player.Name)
		return
	end
	local entry = snapshot.Maps and snapshot.Maps[mapId]
	local maxU = entry and tonumber(entry.MaxUnlockedLevel) or 0
	if maxU < level then
		warn("[StartStoryRun] level locked for", player.Name, mapId, level)
		return
	end

	local mapTbl = loadStoryMapById(mapId)
	if not mapTbl then
		warn("[StartStoryRun] map not found:", mapId)
		return
	end
	local placeId = tonumber(mapTbl.PlaceId) or 0
	local lvl = mapTbl.Levels and mapTbl.Levels[level]
	local waveKey = lvl and lvl.WaveKey or nil
	if placeId <= 0 then
		warn("[StartStoryRun] PlaceId missing for map", mapId, "- printing payload only")
		-- Fallback to debug StartRun
		local ok, err = RunService:StartRun(player)
		if not ok then warn("[StartStoryRun] StartRun fallback failed:", err) end
		return
	end
	if not waveKey then
		warn("[StartStoryRun] WaveKey missing for", mapId, level)
		return
	end

	local payload = RunService:BuildTeleportPayload(player) or {}
	payload.Story = {
		MapId = mapId,
		Level = level,
		WaveKey = waveKey,
	}
	-- Provide a return place id so the run place can teleport the player back to the lobby with results
	payload.ReturnPlaceId = game.PlaceId
	payload.Account = payload.Account or {}
	payload.Account.Boosts = payload.Account.Boosts or (ProfileService:Get(player).Account and ProfileService:Get(player).Account.Boosts) or nil

	local options = Instance.new("TeleportOptions")
	-- Set TeleportData for the destination place
	pcall(function()
		options:SetTeleportData(payload)
	end)

	-- Persist profile just before teleport to avoid progress loss on place switch
	local savedOk, saveErr = ProfileService:Save(player)
	if not savedOk then
		warn("[StartStoryRun] Save before teleport failed:", saveErr)
	end

	local ok, terr = pcall(function()
		return TeleportService:TeleportAsync(placeId, { player }, options)
	end)
	if not ok then
		warn("[StartStoryRun] Teleport failed:", terr)
	else
		print(string.format("[StartStoryRun] Teleporting %s -> %s L%d (place=%d)", player.Name, mapId, level, placeId))
	end
end)

Players.PlayerRemoving:Connect(function(player)
	-- Save and remove profile on player exit
	pcall(function() ProfileService:Save(player) end)
	ProfileService:Remove(player)
end)

-- Debug: adicionar XP manual
DebugAddXP.OnServerEvent:Connect(function(player, amount)
	amount = tonumber(amount) or 0
	local profile = ProfileService:Get(player)
	if not profile or amount == 0 then return end
	local before = profile.Account.Level
	local gained = AccountLeveling:AddXP(profile, amount)
	local after = profile.Account.Level
	ProfileUpdatedRE:FireClient(player, { account = AccountLeveling:GetSnapshot(profile) })
	print(string.format("[DebugAddXP] %s +%d XP -> Levels +%d (Lv %d -> %d)", player.Name, amount, gained, before, after))
end)

-- Debug: give 3 test items to player for QA/testing
DebugGiveTestItemsRE.OnServerEvent:Connect(function(player)
	local profile = ProfileService:Get(player)
	if not profile then return end

	-- Briefly enable verbose snapshot dumps for this debug-give invocation so QA can inspect results
	local prevDebug = DEBUG_SNAPSHOT_DUMPS
	DEBUG_SNAPSHOT_DUMPS = true
	-- Give one of each category using ProfileService:AddItem
	local ps = ProfileService
	local id1, err1 = ps:AddItem(player, "Weapons", "Kunai", { Level = 1 })
	local id2, err2 = ps:AddItem(player, "Armors", "ClothArmor", { Level = 1 })
	local id3, err3 = ps:AddItem(player, "Rings", "IronRing", { Level = 1 })
	-- Send updated full snapshot to client for convenience
	local snapshot = ProfileService:BuildClientSnapshot(profile)
	inspectAndFireFullSnapshot(player, snapshot)
	print(string.format("[DebugGiveTestItems] %s -> %s, %s, %s", player.Name, tostring(id1), tostring(id2), tostring(id3)))

	-- restore previous debug setting
	DEBUG_SNAPSHOT_DUMPS = prevDebug
end)

-- Debug: adicionar novo personagem (templateName)
AddCharacterRE.OnServerEvent:Connect(function(player, templateName)
	local id, err = CharacterService:AddCharacter(player, templateName, { Level = 1, XP = 0 })
	if id then
		local profile = ProfileService:Get(player)
		if profile then
			local snap = ProfileService:BuildClientSnapshot(profile)
			ProfileUpdatedRE:FireClient(player, { characters = { Instances = snap.Characters.Instances, EquippedOrder = profile.Characters.EquippedOrder } })
		else
			warn("[AddCharacter] profile nil for", player.Name)
		end
		print("[AddCharacter]", player.Name, templateName, "->", id)
	else
		warn("[AddCharacter] Falhou:", err)
	end
end)

-- Equipar lista de personagens
EquipCharactersRE.OnServerEvent:Connect(function(player, orderedIds)
	local ok, err = CharacterService:EquipCharacters(player, orderedIds)
	if ok then
		local profile = ProfileService:Get(player)
		if profile then
			ProfileUpdatedRE:FireClient(player, { characters = { EquippedOrder = profile.Characters.EquippedOrder } })
		else
			warn("[EquipCharacters] profile nil for", player.Name)
		end
	else
		warn("[EquipCharacters] Falhou:", err)
	end
end)

-- Equipar uma única instância
EquipOneRE.OnServerEvent:Connect(function(player, instanceId)
	local ok, err = CharacterService:EquipOne(player, instanceId)
	local profile = ProfileService:Get(player)
	if ok and profile then
		ProfileUpdatedRE:FireClient(player, { characters = { EquippedOrder = profile.Characters.EquippedOrder } })
	else
		-- enviar erro específico se necessário
		ProfileUpdatedRE:FireClient(player, { msg = { type = "equip_fail", reason = err, id = instanceId } })
	end
end)

UnequipOneRE.OnServerEvent:Connect(function(player, instanceId)
	local ok, err = CharacterService:UnequipOne(player, instanceId)
	local profile = ProfileService:Get(player)
	if ok and profile then
		ProfileUpdatedRE:FireClient(player, { characters = { EquippedOrder = profile.Characters.EquippedOrder } })
	else
		ProfileUpdatedRE:FireClient(player, { msg = { type = "unequip_fail", reason = err, id = instanceId } })
	end
end)

-- New: Equip an item instance (client requests) -> server validates and updates profile
EquipItemRE.OnServerEvent:Connect(function(player, instanceId)
	local ok, err = ProfileService:EquipItem(player, instanceId)
	local profile = ProfileService:Get(player)
	if profile then
		-- Send updated equipped map / full snapshot for convenience
		inspectAndFireFullSnapshot(player, ProfileService:BuildClientSnapshot(profile))
	end
	if not ok then
		warn("[EquipItem] failed for", player.Name, tostring(instanceId), err)
	else
		print(string.format("[EquipItem] %s equipped %s", player.Name, tostring(instanceId)))
	end
end)

UnequipItemRE.OnServerEvent:Connect(function(player, slotName)
	local ok, err = ProfileService:UnequipItem(player, slotName)
	local profile = ProfileService:Get(player)
	if profile then
		inspectAndFireFullSnapshot(player, ProfileService:BuildClientSnapshot(profile))
	end
	if not ok then
		warn("[UnequipItem] failed for", player.Name, tostring(slotName), err)
	else
		print(string.format("[UnequipItem] %s unequipped %s", player.Name, tostring(slotName)))
	end
end)

-- Vender personagem (remove instância e adiciona gold; gold depende apenas das estrelas)
SellCharacterRE.OnServerEvent:Connect(function(player, instanceId)
	-- Acquire lock to prevent concurrent sells of the same instance
	if not instanceId then return end
	if not acquireSellLock(player, instanceId) then
		ProfileUpdatedRE:FireClient(player, { msg = { type = "sell_fail", reason = "Busy", id = instanceId } })
		return
	end

	local stars, gold
	local auditId
	local ok, err = pcall(function()
		local profile = ProfileService:Get(player)
		if not profile then return end
		local inst = profile.Characters.Instances[instanceId]
		if not inst then
			ProfileUpdatedRE:FireClient(player, { msg = { type = "sell_fail", reason = "NotFound", id = instanceId } })
			return
		end
		-- Impedir vender se estiver equipado
		for _, eid in ipairs(profile.Characters.EquippedOrder) do
			if eid == instanceId then
				ProfileUpdatedRE:FireClient(player, { msg = { type = "sell_fail", reason = "Equipped", id = instanceId } })
				return
			end
		end
		-- Determinar estrelas (usar catálogo para enriquecer se necessário)
		local function resolveStars()
			-- 1) Se profile tiver catálogo enriquecido (não deve aqui) usar
			if inst.Catalog and inst.Catalog.stars then
				return inst.Catalog.stars
			end
			-- 2) Tentar via CharacterCatalog pelo TemplateName
			local templateName = inst.TemplateName
			local starsFromTemplate = nil
			if templateName then
				local RS = game:GetService("ReplicatedStorage")
				local Scripts = RS:FindFirstChild("Scripts")
				local okCat, CharacterCatalog = pcall(function()
					return require(Scripts:FindFirstChild("CharacterCatalog"))
				end)
				if okCat and CharacterCatalog and CharacterCatalog.Get then
					local entry = CharacterCatalog:Get(templateName)
					if entry and entry.stars then
						starsFromTemplate = entry.stars
					end
				end
				-- 3) Parse do sufixo _<n> se ainda não encontrado (ex: Goku_5 -> 5)
				if not starsFromTemplate then
					local suffix = templateName:match("_(%d+)$")
					if suffix then starsFromTemplate = tonumber(suffix) end
				end
			end
			return starsFromTemplate or 1
		end
		stars = resolveStars()
		if type(stars) ~= "number" or stars < 1 then stars = 1 end
		if stars > 6 then stars = 6 end
		local starValues = {100,500,1000,2000,5000,10000}
		gold = starValues[stars] or 0
		-- Attempt to persist an audit entry BEFORE applying the mutation
		if SaleAudit then
			local entry = {
				type = "character",
				instanceId = instanceId,
				template = inst.TemplateName,
				stars = stars,
				coins = gold,
			}
			local id, aerr = SaleAudit:LogSale(player.UserId, entry)
			if not id then
				ProfileUpdatedRE:FireClient(player, { msg = { type = "sell_fail", reason = "AuditFail", id = instanceId } })
				return
			end
			auditId = id
		end

		-- Adicionar moedas (Coins) - campo correto conforme ProfileTemplate / AccountLeveling
		profile.Account.Coins = (profile.Account.Coins or 0) + gold
		-- Remover instância
		profile.Characters.Instances[instanceId] = nil
		-- Enviar snapshot completo para evitar sobrescrever outros campos (ex: Gems) no cliente
		local clientSnapshot = ProfileService:BuildClientSnapshot(profile)
		inspectAndFireFullSnapshot(player, clientSnapshot)
	end)

	if not ok then
		warn("[SellCharacter] error while processing sell:", err)
		ProfileUpdatedRE:FireClient(player, { msg = { type = "sell_fail", reason = "Error", id = instanceId } })
	else
		-- Only print if we have meaningful numeric values to avoid format errors
		if type(stars) == "number" and type(gold) == "number" then
			print(string.format("[SellCharacter] %s vendeu %s stars=%d gold=%d", player.Name, tostring(instanceId), stars, gold))
		else
			print(string.format("[SellCharacter] %s vendeu %s", player.Name, tostring(instanceId)))
		end
		-- Mark audit complete if we have an audit id
		if auditId and SaleAudit then
			local okMark, merr = pcall(function()
				return SaleAudit:MarkComplete(player.UserId, auditId)
			end)
			if not okMark then
				warn("[SellCharacter] failed to mark audit complete for", player.UserId, auditId, merr)
			end
		end
	end
	-- release lock
	releaseSellLock(instanceId)
end)

-- Sell an equipment item for fixed coins by rarity
SellItemRE.OnServerEvent:Connect(function(player, instanceId)
	if not instanceId then return end
	if not acquireSellLock(player, instanceId) then
		ProfileUpdatedRE:FireClient(player, { msg = { type = "sell_fail", reason = "Busy", id = instanceId } })
		return
	end

	local rarity, coins
	local profile
	local auditId
	local ok, err = pcall(function()
		profile = ProfileService:Get(player)
		if not profile then return end

	-- Helper to find item in Categories.List or legacy Owned
	local function findItem()
		if profile.Items and profile.Items.Categories then
			for catName, catData in pairs(profile.Items.Categories) do
				if type(catData) == "table" and type(catData.List) == "table" then
					for idx, entry in ipairs(catData.List) do
						if entry and entry.Id == instanceId then
							return entry, catName, idx
						end
					end
				end
			end
		end
		if profile.Items and profile.Items.Owned then
			for grpName, grp in pairs(profile.Items.Owned) do
				if type(grp) == "table" then
					if grp.Instances then
						for id, inst in pairs(grp.Instances) do
							if id == instanceId then return inst, grpName, id end
						end
					else
						for id, inst in pairs(grp) do
							if id == instanceId then return inst, grpName, id end
						end
					end
				end
			end
		end
		return nil
	end

	local item, groupName, key = findItem()
	if not item then
		ProfileUpdatedRE:FireClient(player, { msg = { type = "sell_fail", reason = "NotFound", id = instanceId } })
		return
	end

	-- Prevent selling equipped items
	if (item.Equipped == true) or (item.data and item.data.Equipped == true) then
		ProfileUpdatedRE:FireClient(player, { msg = { type = "sell_fail", reason = "Equipped", id = instanceId } })
		return
	end

	-- Determine rarity from item stats/catalog (use stars) instead of Quality
	local function resolveStarsForItem(entry)
		-- 1) If the item already has a Catalog.stars field (enriched snapshot), use it
		if entry.Catalog and entry.Catalog.stars then
			return entry.Catalog.stars
		end
		-- 2) Try to resolve via CharacterCatalog (by template name)
		local template = entry.Template or (entry.data and entry.data.Template) or entry.Id
		local starsFromTemplate = nil
		if template then
			local RS = game:GetService("ReplicatedStorage")
			local Scripts = RS:FindFirstChild("Scripts")
			local okCat, CharacterCatalog = pcall(function()
				return require(Scripts:FindFirstChild("CharacterCatalog"))
			end)
			if okCat and CharacterCatalog and CharacterCatalog.Get then
				local catEntry = CharacterCatalog:Get(template)
				if catEntry and catEntry.stars then
					starsFromTemplate = catEntry.stars
				end
			end
			-- 3) Fallback: parse suffix like _5 from template names
			if not starsFromTemplate then
				local suffix = template:match("_(%d+)$")
				if suffix then starsFromTemplate = tonumber(suffix) end
			end
		end
		return starsFromTemplate or 1
	end

	local function starsToRarity(s)
		s = tonumber(s) or 1
		if s <= 1 then return "comum" end
		if s == 2 then return "raro" end
		if s == 3 then return "epico" end
		return "lendario"
	end

	local stars = resolveStarsForItem(item)
	if type(stars) ~= "number" or stars < 1 then stars = 1 end
	if stars > 6 then stars = 6 end
	local rarity = starsToRarity(stars)

	-- Fixed price mapping requested by user
	local priceByRarity = {
		comum = 100,
		raro = 500,
		epico = 1000,
		lendario = 2500,
	}
	local coins = priceByRarity[rarity] or priceByRarity["comum"]

	-- Attempt to persist an audit entry BEFORE mutating the profile
	if SaleAudit then
		local templateName = item.Template or (item.data and item.data.Template) or item.Id
		local entry = {
			type = "item",
			instanceId = instanceId,
			template = templateName,
			rarity = rarity,
			stars = stars,
			coins = coins,
		}
		local id, aerr = SaleAudit:LogSale(player.UserId, entry)
		if not id then
			ProfileUpdatedRE:FireClient(player, { msg = { type = "sell_fail", reason = "AuditFail", id = instanceId } })
			return
		end
		auditId = id
	end

	-- Apply coins and remove the item
	profile.Account.Coins = (profile.Account.Coins or 0) + coins

	-- Remove from data structures
	if profile.Items and profile.Items.Categories and groupName and profile.Items.Categories[groupName] and type(profile.Items.Categories[groupName].List) == "table" then
		local list = profile.Items.Categories[groupName].List
		for i = #list, 1, -1 do
			if list[i] and list[i].Id == instanceId then
				table.remove(list, i)
				break
			end
		end
	elseif profile.Items and profile.Items.Owned and groupName then
		local grp = profile.Items.Owned[groupName]
		if grp then
			if grp.Instances and grp.Instances[key] then
				grp.Instances[key] = nil
			else
				grp[key] = nil
			end
		end
	end

	end)

	if not ok then
		warn("[SellItem] error while processing sell:", err)
		ProfileUpdatedRE:FireClient(player, { msg = { type = "sell_fail", reason = "Error", id = instanceId } })
	else
		if profile then
			local snapshot = ProfileService:BuildClientSnapshot(profile)
			inspectAndFireFullSnapshot(player, snapshot)
		end
		if type(coins) == "number" then
			print(string.format("[SellItem] %s sold %s (rarity=%s) -> coins=%d", player.Name, tostring(instanceId), tostring(rarity), coins))
		else
			print(string.format("[SellItem] %s sold %s (rarity=%s)", player.Name, tostring(instanceId), tostring(rarity)))
		end
		-- Mark audit complete if we have an audit id
		if auditId and SaleAudit then
			local okMark, merr = pcall(function()
				return SaleAudit:MarkComplete(player.UserId, auditId)
			end)
			if not okMark then
				warn("[SellItem] failed to mark audit complete for", player.UserId, auditId, merr)
			end
		end
	end
	releaseSellLock(instanceId)
end)

-- Aumentar capacidade do inventário: custa 100 Gems e adiciona +25 capacidade
IncreaseCapacityRE.OnServerEvent:Connect(function(player)
	local profile = ProfileService:Get(player)
	if not profile then return end
	profile.Characters.Capacity = profile.Characters.Capacity or 50
	profile.Account.Gems = profile.Account.Gems or 0
	local cost = 100
	local gain = 25
	if profile.Account.Gems < cost then
		-- poderia enviar msg de erro específica
		ProfileUpdatedRE:FireClient(player, { msg = { type = "capacity_fail", reason = "NotEnoughGems" } })
		return
	end
	profile.Account.Gems -= cost
	profile.Characters.Capacity += gain
	local snapshot = ProfileService:BuildClientSnapshot(profile)
	inspectAndFireFullSnapshot(player, snapshot)
	print(string.format("[IncreaseCapacity] %s +%d capacity (now %d) -%d Gems (remaining %d)", player.Name, gain, profile.Characters.Capacity, cost, profile.Account.Gems))
end)

-- Ajustar tier de uma instância
SetCharacterTierRE.OnServerEvent:Connect(function(player, instanceId, newTier)
	local ok, err = CharacterService:SetTier(player, instanceId, newTier)
	if ok then
		local profile = ProfileService:Get(player)
		if profile then
			-- reenviar apenas a instância alterada
			local inst = profile.Characters and profile.Characters.Instances and profile.Characters.Instances[instanceId]
			if inst then
				ProfileUpdatedRE:FireClient(player, { characters = { Updated = { { Id = instanceId, Tier = inst.Tier } } } })
			else
				warn("[SetCharacterTier] instance not found after SetTier:", instanceId)
			end
		else
			warn("[SetCharacterTier] profile nil for", player.Name)
		end
	else
		warn("[SetCharacterTier] Falhou:", err)
	end
end)

-- Handle summon requests from clients: validate capacity, create characters, update snapshot and notify client
-- Add per-player lock to prevent concurrent requests from the same player causing double deductions
local activeSummons = activeSummons or {}
RequestSummonRE.OnServerEvent:Connect(function(player, qty)
	qty = tonumber(qty) or 1
	print("[RequestSummon] from", player.Name, "qty=", qty)

	-- Basic qty validation (only allow 1 or 10 for now)
	if qty ~= 1 and qty ~= 10 then
		warn("[RequestSummon] invalid qty from", player.Name, qty)
		SummonGrantedRE:FireClient(player, { success = false, reason = "InvalidQty" })
		return
	end

	-- Prevent concurrent summons from the same player
	if activeSummons[player.UserId] then
		warn("[RequestSummon] player already performing summon:", player.Name)
		SummonGrantedRE:FireClient(player, { success = false, reason = "Busy" })
		return
	end
	activeSummons[player.UserId] = true

	local ok, perr = pcall(function()
		local profile = ProfileService:Get(player)
		if not profile then
			warn("[RequestSummon] no profile for", player.Name)
			SummonGrantedRE:FireClient(player, { success = false, reason = "NoProfile" })
			return
		end

		-- Check capacity: server must enforce space for the requested quantity
		local cap = (profile.Characters and profile.Characters.Capacity) or 50
		local used = 0
		if profile.Characters and profile.Characters.Instances then
			for _ in pairs(profile.Characters.Instances) do used = used + 1 end
		end
		local free = cap - used
		if free < qty then
			SummonGrantedRE:FireClient(player, { success = false, reason = "NoSpace", free = free })
			return
		end

		-- Resolve current banner from ReplicatedStorage
		local bannerValue = ReplicatedStorage:FindFirstChild("CurrentBanner")
		local banner = nil
		if bannerValue and type(bannerValue.Value) == "string" and bannerValue.Value ~= "" then
			local jok, decoded = pcall(function() return HttpService:JSONDecode(bannerValue.Value) end)
			if jok and decoded and type(decoded) == "table" and type(decoded.entries) == "table" then
				banner = decoded
			end
		end
		if not banner then
			SummonGrantedRE:FireClient(player, { success = false, reason = "NoBanner" })
			return
		end

		-- Cost mapping (server-side authoritative)
		local costMap = { [1] = 50, [10] = 450 }
		local cost = costMap[qty] or (50 * qty)
		profile.Account.Gems = profile.Account.Gems or 0
		if profile.Account.Gems < cost then
			SummonGrantedRE:FireClient(player, { success = false, reason = "NotEnoughGems", gems = profile.Account.Gems, required = cost })
			return
		end

		-- Deduct gems (server authoritative) only after all checks passed
		profile.Account.Gems = profile.Account.Gems - cost

		-- Perform the summons using SummonModule (server-side picks)
		local created = {}
		for i = 1, qty do
			local picked, rarity = nil, nil
			local wok, werr = pcall(function()
				picked, rarity = SummonModule.SummonFromBanner(banner)
			end)
			if not wok then
				warn("[RequestSummon] SummonModule error:", werr)
			end
			if not picked or not picked.id then
				warn("[RequestSummon] no pick from banner for iteration", i)
			else
				local templateToAdd = picked.id
				local id, err = CharacterService:AddCharacter(player, templateToAdd, { Level = 1, XP = 0 })
				if id then
					table.insert(created, { Id = id, Template = templateToAdd })
				else
					warn("[RequestSummon] failed to add character:", err)
				end
			end
		end

		-- Send updated full snapshot to client (includes updated Gems and new characters)
		local snap = ProfileService:BuildClientSnapshot(profile)
		inspectAndFireFullSnapshot(player, snap)
		-- Debug: log summary of created items for easier diagnosis
		local createdCount = #created
		local templateList = {}
		for _, c in ipairs(created) do
			table.insert(templateList, tostring(c.Template or c.template or c.TemplateName or c.Id or c.id))
		end
		print(string.format("[RequestSummon] %s performed summon qty=%d cost=%d created=%d remainingGems=%d", player.Name, qty, cost, createdCount, profile.Account.Gems or 0))
		if createdCount > 0 then
			print("[RequestSummon] created templates:", table.concat(templateList, ", "))
		else
			warn(string.format("[RequestSummon] No characters were created for %s (requested=%d). Check CharacterService:AddCharacter failures above.", player.Name, qty))
		end
		-- Notify client which summons succeeded and remaining gems
		SummonGrantedRE:FireClient(player, { success = true, created = created, requested = qty, cost = cost, gemsRemaining = profile.Account.Gems })
	end)

	-- Clear lock and handle any error from the pcall
	activeSummons[player.UserId] = nil
	if not ok then
		warn("[RequestSummon] error processing summon for", player.Name, perr)
		-- Inform client of server error
		SummonGrantedRE:FireClient(player, { success = false, reason = "ServerError" })
	end
end)

print("[Remotes] Loaded")

-- Save all profiles on shutdown
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		pcall(function() ProfileService:Save(player) end)
	end
end)

-- =============================
-- Debug grants (Studio only)
-- =============================
do
	local function isStudio()
		local ok, RunService = pcall(function() return game:GetService("RunService") end)
		return ok and RunService and RunService:IsStudio()
	end

	local function pushSnapshot(player)
		local profile = ProfileService:Get(player)
		if profile then
			local snap = ProfileService:BuildClientSnapshot(profile)
			inspectAndFireFullSnapshot(player, snap)
		end
	end

	DebugAddGemsRE.OnServerEvent:Connect(function(player, amount)
		if not isStudio() then return end
		local profile = ProfileService:Get(player)
		if not profile then return end
		amount = tonumber(amount) or 10000
		profile.Account.Gems = (profile.Account.Gems or 0) + amount
		pushSnapshot(player)
		print(string.format("[DebugAddGems] %s +%d (now %d)", player.Name, amount, profile.Account.Gems or 0))
	end)

	DebugAddCoinsRE.OnServerEvent:Connect(function(player, amount)
		if not isStudio() then return end
		local profile = ProfileService:Get(player)
		if not profile then return end
		amount = tonumber(amount) or 10000
		profile.Account.Coins = (profile.Account.Coins or 0) + amount
		pushSnapshot(player)
		print(string.format("[DebugAddCoins] %s +%d (now %d)", player.Name, amount, profile.Account.Coins or 0))
	end)
end

-- =============================
-- Upgrade Item implementation
-- =============================
do
	local upgradeLocks = {}

	local function acquireUpgradeLock(id)
		if not id then return false end
		if upgradeLocks[id] then return false end
		upgradeLocks[id] = true
		return true
	end
	local function releaseUpgradeLock(id)
		upgradeLocks[id] = nil
	end

	-- Helper to find an item reference (entry + container info) by instanceId
	local function findItemRef(profile, instanceId)
		if not profile or not instanceId then return nil end
		-- Try Categories.List first
		if profile.Items and profile.Items.Categories then
			for catName, catData in pairs(profile.Items.Categories) do
				if type(catData) == "table" and type(catData.List) == "table" then
					for idx, entry in ipairs(catData.List) do
						if entry and entry.Id == instanceId then
							return {
								where = "Categories",
								group = catName,
								listIndex = idx,
								entry = entry,
							}
						end
					end
				end
			end
		end
		-- Fallback: legacy Owned
		if profile.Items and profile.Items.Owned then
			for grpName, grp in pairs(profile.Items.Owned) do
				if type(grp) == "table" then
					if grp.Instances and grp.Instances[instanceId] then
						return {
							where = "Owned.Instances",
							group = grpName,
							key = instanceId,
							entry = grp.Instances[instanceId],
						}
					else
						for id, inst in pairs(grp) do
							if id == instanceId then
								return {
									where = "Owned",
									group = grpName,
									key = id,
									entry = inst,
								}
							end
						end
					end
				end
			end
		end
		return nil
	end

	local function resolveTemplateName(entry)
		if not entry then return nil end
		return entry.Template or (entry.data and entry.data.Template) or entry.TemplateName or entry.Id
	end

	RequestItemUpgradeRF.OnServerInvoke = function(player, instanceId)
		if not instanceId then
			return { success = false, reason = "BadArgs" }
		end
		if not acquireUpgradeLock(instanceId) then
			return { success = false, reason = "Busy" }
		end

		local result
		local ok, err = pcall(function()
			local profile = ProfileService:Get(player)
			if not profile then
				result = { success = false, reason = "NoProfile" }
				return
			end

			local ref = findItemRef(profile, instanceId)
			if not ref or not ref.entry then
				result = { success = false, reason = "NotFound" }
				return
			end

			-- Determine group and template for pricing
			local groupName = ref.group or "Misc"
			local templateName = resolveTemplateName(ref.entry)
			local level = tonumber(ref.entry.Level) or 1

			-- Load UpgradeCosts and compute cost
			local RS = game:GetService("ReplicatedStorage")
			local okCost, UpgradeCosts = pcall(function()
				return require(RS.Shared.Items.UpgradeCosts)
			end)
			if not okCost or not UpgradeCosts then
				result = { success = false, reason = "CostModule" }
				return
			end
			if level >= (UpgradeCosts.MaxLevel or 5) then
				result = { success = false, reason = "MaxLevel", level = level }
				return
			end
			local cost = UpgradeCosts:GetForItem(groupName, templateName, level)
			cost = tonumber(cost) or 0
			if cost <= 0 then
				result = { success = false, reason = "NoCost" }
				return
			end

			-- Check coins
			profile.Account.Coins = profile.Account.Coins or 0
			if profile.Account.Coins < cost then
				result = { success = false, reason = "NotEnoughCoins", coins = profile.Account.Coins, required = cost }
				return
			end

			-- Deduct and level up
			profile.Account.Coins -= cost
			local newLevel = (tonumber(ref.entry.Level) or 1) + 1
			ref.entry.Level = newLevel

			-- Persist back if needed (for Owned paths we mutated the table directly)
			if ref.where == "Categories" then
				-- Array entry is a table; mutation above suffices
			elseif ref.where == "Owned.Instances" then
				-- direct table ref already mutated
			elseif ref.where == "Owned" then
				-- direct table ref already mutated
			end

			-- Send full snapshot so client updates coins/inventory
			local snapshot = ProfileService:BuildClientSnapshot(profile)
			inspectAndFireFullSnapshot(player, snapshot)

			result = { success = true, id = instanceId, level = newLevel, cost = cost, coins = profile.Account.Coins }
		end)

		if not ok then
			warn("[RequestItemUpgrade] error:", err)
			result = { success = false, reason = "ServerError" }
		end

		releaseUpgradeLock(instanceId)
		return result
	end
end
