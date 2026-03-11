-- MainServerScript
-- Sistema de run: somente progressão por instância (CharacterLeveling) para cada personagem equipado.
-- CharactersModule: mantém lista de objetos equipados em `ChosenChars` / retorno de GetEquipped.
-- Wave XP: acumula bruto em RunAccum/CharacterXP/<InstanceId> SEM dividir pelo número de personagens.
-- Ensure essential services and module references exist (fixes nil indexing on startup)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

-- Infinite mode: permanent death. Disable auto-respawn so the DeathMenu persists
-- and the player must choose Restart or Exit explicitly.
Players.CharacterAutoLoads = false

local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")
local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local EnemyStats
do
	local ok, mod = pcall(function() return require(ScriptsFolder:WaitForChild("EnemyStats")) end)
	if ok and type(mod) == "table" then EnemyStats = mod end
end

-- Ensure Remotes folder exists as early as possible so clients waiting on it don't hang
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

-- AutoAttack SFX remote
if not Remotes:FindFirstChild("AutoAttackSFX") then
	local re = Instance.new("RemoteEvent")
	re.Name = "AutoAttackSFX"
	re.Parent = Remotes
end

-- Crit SFX remote
if not Remotes:FindFirstChild("CritSFX") then
	local re = Instance.new("RemoteEvent")
	re.Name = "CritSFX"
	re.Parent = Remotes
end

-- Electric SFX remote
if not Remotes:FindFirstChild("ElectricSFX") then
	local re = Instance.new("RemoteEvent")
	re.Name = "ElectricSFX"
	re.Parent = Remotes
end

-- Bleed SFX remote
if not Remotes:FindFirstChild("BleedSFX") then
	local re = Instance.new("RemoteEvent")
	re.Name = "BleedSFX"
	re.Parent = Remotes
end

-- Burn SFX remote
if not Remotes:FindFirstChild("BurnSFX") then
	local re = Instance.new("RemoteEvent")
	re.Name = "BurnSFX"
	re.Parent = Remotes
end

-- Card ability SFX remote (carries card id so client picks the right sound)
if not Remotes:FindFirstChild("CardAbilitySFX") then
	local re = Instance.new("RemoteEvent")
	re.Name = "CardAbilitySFX"
	re.Parent = Remotes
end

-- Predeclare DataStores handle so functions defined earlier (e.g., endRun) can reference it reliably
local DS_GLOBAL = nil
-- Forward declare to allow earlier references (e.g., endRun) to call after it's defined
local buildAggregatedRunResult

-- Grace period (seconds) after all players are dead before triggering endRun
local DEFEAT_GRACE_SECONDS = 3

-- Infinite mode evolve drop configuration (probabilities are independent of XP drops)
-- Both drops have 40% independent chance every 10 waves
local INFINITE_EVOLVE_SHARD_CHANCE = 0.40
local INFINITE_EVOLVE_CORE_CHANCE = 0.40
-- Random quantity ranges
local INFINITE_EVOLVE_SHARD_MIN = 2
local INFINITE_EVOLVE_SHARD_MAX = 4
local INFINITE_EVOLVE_CORE_MIN = 1
local INFINITE_EVOLVE_CORE_MAX = 2

-- Mark a server script version for live verification (client-readable)
pcall(function()
	ReplicatedStorage:SetAttribute("RunServerVersion", "RSV-2025-11-04-02")
end)

local function safeRequire(modFolder, name)
	local ok, res = pcall(function() return require(modFolder:WaitForChild(name)) end)
	if ok then return res end
	warn("[safeRequire] failed to require", name, res)
	return nil
end

-- End-of-run handler: marks runEnded, sets replicated attributes, notifies clients (RunCompleted), and prepares run results
local runEnded = false
local function endRun(win)
	if runEnded then return end
	runEnded = true
	pcall(function()
		ReplicatedStorage:SetAttribute("RunEnded", true)
		ReplicatedStorage:SetAttribute("RunWin", win == true)
		ReplicatedStorage:SetAttribute("WavesCompleted", true)
	end)

	-- Build a simple summary for clients and pending serialization
	for _, plr in ipairs(Players:GetPlayers()) do
		-- mark players as awaiting choice so client VictoryMenu can auto-show
		pcall(function() plr:SetAttribute("AwaitingRunChoice", true) end)
		-- Fire RunCompleted remote with a minimal summary
		pcall(function()
			local ev = Remotes:FindFirstChild("RunCompleted")
			if ev and ev:IsA("RemoteEvent") then
				-- Build summary: Win flag and simple rewards (if LastRunResultJSON exists use it)
				local summary = { Win = win == true }
				local ra = plr:FindFirstChild("RunAccum")
				local lastJson = ra and ra:FindFirstChild("LastRunResultJSON")
				if lastJson and lastJson.Value and lastJson.Value ~= "" then
					local ok, t = pcall(function() return HttpService:JSONDecode(lastJson.Value) end)
					if ok and type(t) == "table" then
						summary = t
						summary.Win = summary.Win or (win == true)
					end
				end
				ev:FireClient(plr, summary)
			end
		end)
	end

	-- Optionally set a global timestamp for end-of-run
	pcall(function() ReplicatedStorage:SetAttribute("RunEndedAt", os.time()) end)

	-- Persist aggregated RunResult for all players immediately so disconnects during victory UI don't lose rewards
	pcall(function()
		if DS_GLOBAL and type(DS_GLOBAL.saveRunResult) == "function" then
			for _, plr in ipairs(Players:GetPlayers()) do
				local ok, aggregated
				ok, aggregated = pcall(function() return buildAggregatedRunResult(plr) end)
				if not ok then
					warn(string.format("[Script] endRun: buildAggregatedRunResult failed for %s: %s", tostring(plr.Name), tostring(aggregated)))
				end
				if ok and type(aggregated) == "table" then
					local runId = nil
					pcall(function()
						runId = HttpService:GenerateGUID(false)
						aggregated.RunId = runId
						-- Expose to client for live verification
						pcall(function()
							plr:SetAttribute("AttemptSaveRunId", tostring(runId))
							plr:SetAttribute("AttemptSaveAt", os.time())
						end)
						local sOk, sErr = DS_GLOBAL.saveRunResult(plr.UserId, runId, aggregated)
						if not sOk then
							warn(string.format("[Script] endRun: saveRunResult failed for %s: %s", tostring(plr.Name), tostring(sErr)))
						else
							print(string.format("[Script] endRun: saved RunResult for %s (RunId=%s)", tostring(plr.Name), tostring(runId)))
							-- Cache JSON for client-visible verification
							pcall(function()
								local ra = plr:FindFirstChild("RunAccum") or Instance.new("Folder")
								ra.Name = "RunAccum"; if not ra.Parent then ra.Parent = plr end
								local last = ra:FindFirstChild("LastRunResultJSON") or Instance.new("StringValue")
								last.Name = "LastRunResultJSON"; if not last.Parent then last.Parent = ra end
								last.Value = HttpService:JSONEncode(aggregated)
							end)
						end
					end)
				end
			end
		end
	end)

	-- Persist story progression for winners (do this AFTER saving RunResult so first-clear detection can grant correct rewards)
	if win == true then
		local okDS, DS = pcall(function() return require(ServerScriptService:FindFirstChild("DataStores") or ServerScriptService:WaitForChild("DataStores")) end)
		if okDS and type(DS) == "table" then
			for _, plr in ipairs(Players:GetPlayers()) do
				pcall(function()
					local mapId = ReplicatedStorage:GetAttribute("StoryMapId")
					local lvl = tonumber(ReplicatedStorage:GetAttribute("StoryLevel")) or nil
					if not mapId or not lvl then
						-- Try joinData fallback
						local jd = plr:GetJoinData()
						local td = jd and jd.TeleportData
						if td and td.Story then mapId = mapId or td.Story.MapId; lvl = lvl or tonumber(td.Story.Level) end
					end
					if mapId and lvl and plr.UserId then
						local ok, err = DS.markLevelCompleted(plr.UserId, tostring(mapId), tonumber(lvl))
						if not ok then warn(string.format("[DataStores] failed to save completion for %s: %s", tostring(plr.Name), tostring(err))) end
					end
				end)
			end
		end
	end
end

-- Also require DataStores globally for RunResult persistence
local DS_OK = false
do
	local ok, mod = pcall(function()
		return require(ServerScriptService:FindFirstChild("DataStores") or ServerScriptService:WaitForChild("DataStores"))
	end)
	DS_OK = ok
	if ok then
		DS_GLOBAL = mod
	else
		warn("[Script] DataStores module not available for run result persistence")
	end
end

local WaveManagerModule = safeRequire(ServerScriptService, "WaveManager")
local waveManager = nil -- lazily instantiated after TeleportData determines LevelName
-- Attach server callbacks to a WaveManager instance, preserving any pre-defined callbacks from WaveConfig
local function configureWaveManagerCallbacks(inst)
	if not inst then return end
	-- Preserve existing callbacks from loaded WaveConfig
	local prevStart = inst.OnWaveStarted
	local prevCleared = inst.OnWaveCleared
	local prevAll = inst.OnAllWavesCleared
	local prevDied = inst.OnEnemyDied

	-- Forward declares (implemented later in file)
	local function _server_OnWaveStarted(waveIndex) end
	local function _server_OnWaveCleared(waveIndex) end
	local function _server_OnAllWavesCleared() end
	local function _server_OnEnemyDied(info) end

	-- Resolve final implementations bound further below
	_server_OnWaveStarted = function(waveIndex)
		-- Update leaderstats and replicated attributes; identical to previous inline implementation
		for _, plr in ipairs(Players:GetPlayers()) do
			local function setPlayerNumberStat(player, name, value)
				if not player then return end
				pcall(function()
					local ls = player:FindFirstChild("leaderstats")
					if not ls then ls = Instance.new("Folder") ls.Name = "leaderstats" ls.Parent = player end
					local nv = ls:FindFirstChild(name)
					if not nv then nv = Instance.new("NumberValue") nv.Name = name nv.Parent = ls end
					if typeof(value) == "number" then
						nv.Value = value
					else
						local n = tonumber(value) or 0
						nv.Value = n
					end
				end)
			end
			setPlayerNumberStat(plr, "CurrentWave", waveIndex)
			pcall(function() ReplicatedStorage:SetAttribute("CurrentWave", waveIndex) end)
			if waveIndex == 1 then
				pcall(function()
					local runTrack = plr:FindFirstChild("RunTrack")
					if not runTrack then runTrack = Instance.new("Folder") runTrack.Name = "RunTrack" runTrack.Parent = plr end
					local rs = runTrack:FindFirstChild("RunStart") or Instance.new("NumberValue") rs.Name = "RunStart" rs.Parent = runTrack
					rs.Value = os.clock()
					local rt = runTrack:FindFirstChild("RunTime") or Instance.new("NumberValue") rt.Name = "RunTime" rt.Parent = runTrack
					rt.Value = 0
				end)
			end
		end
	end

	_server_OnWaveCleared = function(waveIndex)
		-- Grant wave XP to all players
		for _, plr in ipairs(Players:GetPlayers()) do
			pcall(function() grantWaveCharacterXP(plr, waveIndex) end)
		end
		
		-- INFINITE MODE: Milestone rewards every 10 waves
		if waveIndex % 10 == 0 then
			for _, plr in ipairs(Players:GetPlayers()) do
				pcall(function()
					local ra = plr:FindFirstChild("RunAccum")
					if not ra then return end
					
					local rew = ra:FindFirstChild("Rewards")
					if not rew then
						rew = Instance.new("Folder")
						rew.Name = "Rewards"
						rew.Parent = ra
					end
					
					-- Ensure Gold and Gems values exist
					local goldVal = rew:FindFirstChild("Gold")
					if not goldVal then
						goldVal = Instance.new("IntValue")
						goldVal.Name = "Gold"
						goldVal.Value = 0
						goldVal.Parent = rew
					end
					
					local gemsVal = rew:FindFirstChild("Gems")
					if not gemsVal then
						gemsVal = Instance.new("IntValue")
						gemsVal.Name = "Gems"
						gemsVal.Value = 0
						gemsVal.Parent = rew
					end
					
					-- Calculate milestone tier (10, 20, 30...)
					local wavesTier = waveIndex / 10
					
					-- Base rewards (scales with tier)
					local baseGold = 50 + (wavesTier * 30)
					local baseGems = 5 + math.floor(wavesTier * 0.5)
					-- Character/Account XP: starts lower than story, scales exponentially
					-- Formula: 30 + (tier^1.8 * 15)
					-- Wave 10: ~45 XP, Wave 20: ~82 XP, Wave 50: ~286 XP, Wave 100: ~975 XP
					local charXP = math.floor(30 + (math.pow(wavesTier, 1.8) * 15))
					
					-- Add base rewards
					goldVal.Value = goldVal.Value + baseGold
					gemsVal.Value = gemsVal.Value + baseGems
					
					-- Add XP character (70% XP3, 30% XP4)
					local charsVal = rew:FindFirstChild("Characters")
					if not charsVal then
						charsVal = Instance.new("StringValue")
						charsVal.Name = "Characters"
						charsVal.Value = "[]"
						charsVal.Parent = rew
					end
					
					local chars = {}
					pcall(function()
						chars = HttpService:JSONDecode(charsVal.Value)
						if type(chars) ~= "table" then chars = {} end
					end)
					
					-- 70% chance XP3 character, 30% chance XP4 character
					local xpChar = (math.random() <= 0.7) and "XP3" or "XP4"
					table.insert(chars, xpChar)
					
					charsVal.Value = HttpService:JSONEncode(chars)
					
					-- Grant Character XP to all equipped characters
					local equippedChars = CharactersModule:GetEquipped(plr)
					if equippedChars and #equippedChars > 0 then
						for _, charData in ipairs(equippedChars) do
							local instanceId = charData.InstanceId
							if instanceId then
								-- Track per-character XP in RunAccum/CharacterXP/<InstanceId>
								local charXPFolder = ra:FindFirstChild("CharacterXP")
								if not charXPFolder then
									charXPFolder = Instance.new("Folder")
									charXPFolder.Name = "CharacterXP"
									charXPFolder.Parent = ra
								end
								
								local instanceVal = charXPFolder:FindFirstChild(tostring(instanceId))
								if not instanceVal then
									instanceVal = Instance.new("IntValue")
									instanceVal.Name = tostring(instanceId)
									instanceVal.Value = 0
									instanceVal.Parent = charXPFolder
								end
								
								instanceVal.Value = instanceVal.Value + charXP
							end
						end
					end
					
					-- Grant Account XP (sum of all character XP)
					local accountXP = charXP * math.max(1, #equippedChars)
					local accXPVal = ra:FindFirstChild("AccountXP")
					if not accXPVal then
						accXPVal = Instance.new("IntValue")
						accXPVal.Name = "AccountXP"
						accXPVal.Value = 0
						accXPVal.Parent = ra
					end
					accXPVal.Value = accXPVal.Value + accountXP
					
					print(string.format("[Infinite] Wave %d milestone: %s received %d gold, %d gems, 1x %s char, %d char XP (%d chars), %d account XP", 
						waveIndex, plr.Name, baseGold, baseGems, xpChar, charXP, #equippedChars, accountXP))

					-- Independent evolve item drops every 10 waves (do not affect XP drops)
					local itemsFolder = rew:FindFirstChild("Items")
					if not itemsFolder then
						itemsFolder = Instance.new("Folder")
						itemsFolder.Name = "Items"
						itemsFolder.Parent = rew
					end

					local function addItem(id, qty)
						local iv = itemsFolder:FindFirstChild(id)
						if not iv then
							iv = Instance.new("IntValue")
							iv.Name = id
							iv.Value = 0
							iv.Parent = itemsFolder
						end
						iv.Value = iv.Value + (tonumber(qty) or 0)
					end

					-- Roll independently for shard and core
					if math.random() <= INFINITE_EVOLVE_SHARD_CHANCE then
						local qty = math.random(INFINITE_EVOLVE_SHARD_MIN, INFINITE_EVOLVE_SHARD_MAX)
						addItem("evolve_shard", qty)
						print(string.format("[Infinite] Wave %d: %s received %dx evolve_shard", waveIndex, plr.Name, qty))
					end

					if math.random() <= INFINITE_EVOLVE_CORE_CHANCE then
						local qty = math.random(INFINITE_EVOLVE_CORE_MIN, INFINITE_EVOLVE_CORE_MAX)
						addItem("evolve_core", qty)
						print(string.format("[Infinite] Wave %d: %s received %dx evolve_core", waveIndex, plr.Name, qty))
					end
					
					-- Check for first time bonus
					-- This needs to check player data - we'll track in Infinite.MilestonesReached
					-- For now, mark in a temporary attribute to handle in endRun/save
					local milestonesReached = plr:GetAttribute("InfiniteMilestonesReached") or ""
					local milestoneKey = tostring(waveIndex)
					
					if not string.find(milestonesReached, milestoneKey) then
						-- First time reaching this milestone!
						local bonusGold = 100 + (wavesTier * 50)
						local bonusGems = 5 + math.floor(wavesTier * 2)
						
						goldVal.Value = goldVal.Value + bonusGold
						gemsVal.Value = gemsVal.Value + bonusGems
						
						-- Mark milestone as reached
						if milestonesReached == "" then
							milestonesReached = milestoneKey
						else
							milestonesReached = milestonesReached .. "," .. milestoneKey
						end
						plr:SetAttribute("InfiniteMilestonesReached", milestonesReached)
						
						print(string.format("[Infinite] FIRST TIME BONUS! Wave %d: %s received +%d gold, +%d gems", 
							waveIndex, plr.Name, bonusGold, bonusGems))
					end
				end)
			end
		end
	end

	_server_OnAllWavesCleared = function()
		endRun(true)
	end

	_server_OnEnemyDied = function(info)
		-- Original OnEnemyDied body preserved further below; to avoid duplication, call the global handler if present
		if type(waveManager) == "table" then end -- no-op to quiet analyzer
		-- Reuse existing implementation by referencing the local handler defined later if available
		if type(Server_OnEnemyDied_Impl) == "function" then
			return Server_OnEnemyDied_Impl(info)
		end
	end

	inst.OnWaveStarted = function(waveIndex)
		if typeof(prevStart) == "function" then pcall(prevStart, waveIndex) end
		_server_OnWaveStarted(waveIndex)
	end
	inst.OnWaveCleared = function(waveIndex)
		if typeof(prevCleared) == "function" then pcall(prevCleared, waveIndex) end
		_server_OnWaveCleared(waveIndex)
	end
	inst.OnAllWavesCleared = function()
		if typeof(prevAll) == "function" then pcall(prevAll) end
		_server_OnAllWavesCleared()
	end
	inst.OnEnemyDied = function(info)
		if typeof(prevDied) == "function" then pcall(prevDied, info) end
		_server_OnEnemyDied(info)
	end
	
	-- Add enemy type label above each spawned enemy
	inst.OnEnemySpawned = function(info)
		if not info or not info.enemy or not info.type then return end
		
		pcall(function()
			local enemyModel = info.enemy
			local enemyType = info.type
			
			-- Determine color based on type
			local typeColors = {
				melee = Color3.fromRGB(255, 255, 255),  -- White
				ranged = Color3.fromRGB(255, 255, 0),   -- Yellow
				cloner = Color3.fromRGB(150, 0, 255),   -- Purple
				regen = Color3.fromRGB(0, 255, 0),      -- Green
			}
			
			local color = typeColors[enemyType] or Color3.fromRGB(200, 200, 200)
			
			-- Find the head or humanoid root part to attach the label
			local attachPart = enemyModel:FindFirstChild("Head") or enemyModel:FindFirstChild("HumanoidRootPart")
			if not attachPart then 
				print("[TypeLabel] No Head/HumanoidRootPart found on", enemyModel.Name)
				return 
			end
			
			-- Create billboard GUI
			local billboard = Instance.new("BillboardGui")
			billboard.Name = "TypeLabel"
			billboard.Size = UDim2.new(0, 60, 0, 20)
			billboard.StudsOffset = Vector3.new(0, 6, 0)  -- Higher offset to be above health bar
			billboard.AlwaysOnTop = true
			billboard.Adornee = attachPart
			billboard.Parent = attachPart
			
			-- Create text label
			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, 0, 1, 0)
			label.BackgroundTransparency = 1
			label.Text = string.upper(enemyType)
			label.TextColor3 = color
			label.TextStrokeTransparency = 0
			label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
			label.Font = Enum.Font.FredokaOne
			label.TextScaled = true
			label.Parent = billboard
			
			print(string.format("[TypeLabel] Created label for %s enemy at %s", enemyType, attachPart.Name))
		end)
	end
end

local function ensureWaveManager()
	if waveManager and type(waveManager.Start) == "function" then return waveManager end
	if not WaveManagerModule or type(WaveManagerModule.new) ~= "function" then
		warn("[Script] WaveManager module missing or has no .new() constructor")
		return nil
	end
	
	-- [Infinite Mode] Create procedural wave config instead of loading from file
	local infiniteWaveConfig = {
		InfiniteMode = true,
		RepeatWavesStart = 51,
		RepeatWavesEnd = 60,
		Waves = {},
		Rates = {},
		-- Generate waves 1-60 (base waves before infinite loop)
		GenerateWave = function(waveIndex)
			-- Enemy types: Melee (40%), Ranged (30%), Regen (15%), Cloner (15%)
			-- Cloners only appear from wave 10 onwards
			local totalEnemies = math.floor(5 + waveIndex * 0.5)
			
			-- Distribute enemies by type
			local meleeCount, rangedCount, regenCount, clonerCount
			
			if waveIndex < 10 then
				-- Before wave 10: no cloners, redistribute to other types
				meleeCount = math.floor(totalEnemies * 0.50)
				rangedCount = math.floor(totalEnemies * 0.35)
				regenCount = totalEnemies - meleeCount - rangedCount
				clonerCount = 0
			else
				-- Wave 10+: normal distribution with cloners
				meleeCount = math.floor(totalEnemies * 0.40)
				rangedCount = math.floor(totalEnemies * 0.30)
				regenCount = math.floor(totalEnemies * 0.15)
				clonerCount = totalEnemies - meleeCount - rangedCount - regenCount
			end
			
			-- Scale HP and Damage based on wave number (now using 20% compounded per wave)
			local hpScale = math.pow(1.2, waveIndex - 1)
			local dmgScale = math.pow(1.2, waveIndex - 1)
			-- XP scales moderately per wave (+8% per wave - slower than level requirement growth)
			local xpScale = 1 + (waveIndex - 1) * 0.08
			
			local enemies = {}
			
			-- Add Melee enemies (use EnemyStats base values, then apply per-wave scaling)
			if meleeCount > 0 then
				local meleeStats = EnemyStats.GetByType("melee") or {}
				local baseHealth = (meleeStats.Health and tonumber(meleeStats.Health)) or 50
				local baseDamageVal = (meleeStats.Damage and tonumber(meleeStats.Damage)) or 5
				table.insert(enemies, {
					type = "melee",
					count = meleeCount,
					baseHP = math.floor(baseHealth * hpScale),
					baseDamage = math.floor(baseDamageVal * dmgScale),
					xp = math.floor(15 * xpScale),
				})
			end
			
			-- Add Ranged enemies (use EnemyStats base values, then apply per-wave scaling)
			if rangedCount > 0 then
				local rangedStats = EnemyStats.GetByType("ranged") or {}
				local baseHealth = (rangedStats.Health and tonumber(rangedStats.Health)) or 40
				local baseDamageVal = (rangedStats.Damage and tonumber(rangedStats.Damage)) or 4
				table.insert(enemies, {
					type = "ranged",
					count = rangedCount,
					baseHP = math.floor(baseHealth * hpScale),
					baseDamage = math.floor(baseDamageVal * dmgScale),
					xp = math.floor(18 * xpScale),
				})
			end
			
			-- Add Regen enemies
				if regenCount > 0 then
					local regenStats = EnemyStats.GetByType("regen") or {}
					local baseHealth = (regenStats.Health and tonumber(regenStats.Health)) or 70
					local baseDamageVal = (regenStats.Damage and tonumber(regenStats.Damage)) or 6
					table.insert(enemies, {
						type = "regen",
						count = regenCount,
						baseHP = math.floor(baseHealth * hpScale),
						baseDamage = math.floor(baseDamageVal * dmgScale),
						xp = math.floor(24 * xpScale),
					})
				end
			
			-- Add Cloner enemies
			if clonerCount > 0 then
				local clonerStats = EnemyStats.GetByType("cloner") or {}
				local baseHealth = (clonerStats.Health and tonumber(clonerStats.Health)) or 60
				local baseDamageVal = (clonerStats.Damage and tonumber(clonerStats.Damage)) or 5
				table.insert(enemies, {
					type = "cloner",
					count = clonerCount,
					baseHP = math.floor(baseHealth * hpScale),
					baseDamage = math.floor(baseDamageVal * dmgScale),
					xp = math.floor(28 * xpScale),
				})
			end
			
			return { enemies = enemies }
		end
	}
	
	-- Generate initial 60 waves
	for i = 1, 60 do
		infiniteWaveConfig.Waves[i] = infiniteWaveConfig.GenerateWave(i)
	end
	
	local cfg = { 
		LevelName = "infinite",
		InfiniteMode = true,
		-- Inject the wave config directly so WaveManager uses it
		_InfiniteConfig = infiniteWaveConfig,
		-- Burst spawning configuration
		Burst = {
			StartWave = 3,
			Min = 4,
			Max = 8,
		},
		-- Spawn areas (infinite map)
		SpawnAreas = {
			{
				corners = {
					Vector3.new(89.99, 35.589, -129.819),
					Vector3.new(201.99, 35.589, -129.819),
					Vector3.new(201.99, 35.589, -17.819),
					Vector3.new(89.99, 35.589, -17.819),
				},
				Y = 35.589,
			}
		},
		-- Arena bounds for random target generation
		ArenaBounds = {
			min = Vector3.new(89.99, 35.589, -129.819),
			max = Vector3.new(201.99, 35.589, -17.819),
		},
	}
	local ok, inst = pcall(function() return WaveManagerModule.new(cfg) end)
	if ok and inst then
		-- Override WaveConfig with our procedural one
		inst.WaveConfig = infiniteWaveConfig
		inst.Waves = infiniteWaveConfig.Waves
		waveManager = inst
		configureWaveManagerCallbacks(inst)
		print(string.format("[WaveManager] Instantiated with InfiniteMode (TotalWaves=%d, will repeat 51-60 infinitely)", #(inst.Waves or {})))
		return inst
	else
		warn("[Script] Failed to instantiate WaveManager:", inst)
		return nil
	end
end
local EquippedItemsModule = safeRequire(ScriptsFolder, "EquipedItems")
local CharactersModule = safeRequire(ScriptsFolder, "CharEquiped")
local ApplyStatsModule = safeRequire(ScriptsFolder, "ApplyStats")
local ItemLeveling = safeRequire(ScriptsFolder, "ItemLeveling")
local Leveling = safeRequire(ScriptsFolder, "Leveling")
local CharacterLeveling = safeRequire(ScriptsFolder, "CharacterLeveling")
local PlayerStatsModule = safeRequire(ScriptsFolder, "PlayerStats")
local CardPool = safeRequire(ScriptsFolder, "CardPool")
local AccountLeveling = safeRequire(ScriptsFolder, "AccountLeveling")

-- prevHP map used by the regen/heal instrumentation. Use weak keys so Humanoid objects can be collected.
local prevHP = setmetatable({}, { __mode = "k" })

local function restartRun(force)
	-- Deprecated: old in-place restart removed in favor of teleport-to-reserved-server flow.
	warn("[restartRun] deprecated: use teleportToReservedServer() instead. This function is a no-op.")
	return
end



-- Helper: reserve a private server for placeId and teleport given players there with TeleportOptions containing teleportData.
-- Returns true on success, false and error message on failure.
local function serializePendingTotals(plr)
	local ra = plr:FindFirstChild("RunAccum")
	local pend = ra and ra:FindFirstChild("PendingTotals")
	if not pend then return nil end
	local out = { AccountXP = 0, CharacterXP = {}, Rewards = { Gold = 0, Gems = 0, Items = {} } }
	local acc = pend:FindFirstChild("AccountXP")
	if acc and acc:IsA("NumberValue") then out.AccountXP = tonumber(acc.Value) or 0 end
	local cxp = pend:FindFirstChild("CharacterXP")
	if cxp then
		for _, nv in ipairs(cxp:GetChildren()) do
			if nv:IsA("NumberValue") then out.CharacterXP[nv.Name] = tonumber(nv.Value) or 0 end
		end
	end
	local rew = pend:FindFirstChild("Rewards")
	if rew then
		local gold = rew:FindFirstChild("Gold")
		local gems = rew:FindFirstChild("Gems")
		out.Rewards.Gold = (gold and tonumber(gold.Value)) or 0
		out.Rewards.Gems = (gems and tonumber(gems.Value)) or 0
		local items = rew:FindFirstChild("Items")
		if items then
			for _, iv in ipairs(items:GetChildren()) do
				if iv:IsA("IntValue") and (tonumber(iv.Value) or 0) > 0 then
					table.insert(out.Rewards.Items, { Id = iv.Name, Quantity = tonumber(iv.Value) or 0 })
				end
			end
		end
	end
	return out
end

local function teleportToReservedServer(placeId, playersList, teleportData)
	if RunService:IsStudio() then
		-- In Studio, ReserveServer/TeleportToPrivateServer may not behave as on live servers. Fail fast to allow fallback.
		return false, "studio_fallback"
	end
	local ok, reserved = pcall(function()
		return TeleportService:ReserveServer(placeId)
	end)
	if not ok or not reserved then
		return false, (reserved or "reserve_failed")
	end
	-- Assemble payload with ReturnPlaceId and PendingTotals passthrough
	local payload = {}
	if type(teleportData) == "table" then
		for k,v in pairs(teleportData) do payload[k] = v end
	end
	-- Assume single-player flow; derive ReturnPlaceId and PendingTotals from the first player
	local p0 = playersList[1]
	if p0 then
		-- Carry forward ReturnPlaceId if missing
		local okJD, jd = pcall(function() return p0:GetJoinData() end)
		local td0 = okJD and jd and jd.TeleportData or nil
		if td0 and td0.ReturnPlaceId and payload.ReturnPlaceId == nil then
			payload.ReturnPlaceId = td0.ReturnPlaceId
		end
		-- Carry forward PendingTotals across chained runs
		local pending = serializePendingTotals(p0)
		if pending then
			payload.PendingTotals = pending
		end
	end
	-- TeleportToPrivateServer signature: (placeId, accessCode, players, spawnName?, teleportData?)
	-- Pass nil for spawnName and payload as teleportData (do NOT pass TeleportOptions here).
	local succ, err = pcall(function()
		TeleportService:TeleportToPrivateServer(placeId, reserved, playersList, nil, payload)
	end)
	if not succ then
		return false, (err or "teleport_failed")
	end
	return true
end
-- Helper: try to persist runResult for a single player before teleporting back to lobby
local function saveThenTeleportToReturnPlace(returnPlaceId, playerOrList, runResult)
	-- Resolve destination: prefer configured LobbyPlaceId, then provided returnPlaceId, then player's JoinData.ReturnPlaceId
	local resolvedPlaceId = nil
	pcall(function()
		local lp = tonumber(ReplicatedStorage:GetAttribute("LobbyPlaceId"))
		if lp and lp > 0 then resolvedPlaceId = lp end
	end)
	if (not resolvedPlaceId) or resolvedPlaceId <= 0 then
		if returnPlaceId and returnPlaceId > 0 then
			resolvedPlaceId = returnPlaceId
		else
			local p0 = (type(playerOrList) == "table" and #playerOrList > 0) and playerOrList[1] or playerOrList
			if p0 and typeof(p0) == "Instance" then
				pcall(function()
					local jd = p0:GetJoinData()
					local td = jd and jd.TeleportData
					local rp = td and tonumber(td.ReturnPlaceId)
					if rp and rp > 0 then resolvedPlaceId = rp end
				end)
			end
		end
	end
	if not resolvedPlaceId or resolvedPlaceId <= 0 then
		return false, "no_return"
	end
	local playersList = {}
	local singlePlayer = nil
	if type(playerOrList) == "table" and #playerOrList > 0 then
		playersList = playerOrList
		singlePlayer = playerOrList[1]
	else
		singlePlayer = playerOrList
		table.insert(playersList, singlePlayer)
	end
	local options = Instance.new("TeleportOptions")
	-- Ensure RunId
	runResult = runResult or {}
	if not runResult.RunId then
		runResult.RunId = HttpService:GenerateGUID(false)
	end
	-- Attempt to persist for each player (best-effort). Use DS_GLOBAL.saveRunResult which itself has retries.
	for _, pl in ipairs(playersList) do
		if DS_GLOBAL and type(DS_GLOBAL.saveRunResult) == "function" then
			local attempts = 0
			local maxAttempts = 3
			local saved = false
			while attempts < maxAttempts do
				local ok, err = pcall(function()
					return DS_GLOBAL.saveRunResult(pl.UserId, runResult.RunId, runResult)
				end)
				if ok then
					-- DS_GLOBAL.saveRunResult returns true/false per implementation
					if err == true or err == nil then
						print(string.format("[Script] saveRunResult confirmed for %s (RunId=%s)", tostring(pl.Name), tostring(runResult.RunId)))
						-- Expose to client
						pcall(function()
							pl:SetAttribute("AttemptSaveRunId", tostring(runResult.RunId))
							pl:SetAttribute("AttemptSaveAt", os.time())
						end)
						saved = true
						break
					else
						warn(string.format("[Script] saveRunResult attempt failed for %s: %s", tostring(pl.Name), tostring(err)))
					end
				else
					warn(string.format("[Script] saveRunResult pcall failed for %s: %s", tostring(pl.Name), tostring(err)))
				end
				attempts = attempts + 1
				task.wait(0.25 * (2 ^ (attempts - 1)))
			end
			if not saved then
				warn(string.format("[Script] saveRunResult exhausted retries for %s RunId=%s; proceeding with teleport (RunResult may be lost if TeleportData dropped)", tostring(pl.Name), tostring(runResult.RunId)))
			end
		end
	end
	-- Minimal telemetry before teleport
	pcall(function()
		local names = {}
		for _, p in ipairs(playersList) do table.insert(names, p.Name) end
		print(string.format("[Teleport] Return to %d with RunId=%s -> players=[%s]", tonumber(resolvedPlaceId) or -1, tostring(runResult.RunId), table.concat(names, ", ")))
	end)
	-- Prevent duplicate teleports per player (IsTeleporting)
	local filtered = {}
	for _, p in ipairs(playersList) do
		local already = p:GetAttribute("_IsTeleporting")
		if already then
			warn(string.format("[Teleport] Skipping duplicate teleport for %s (already teleporting)", p.Name))
		else
			p:SetAttribute("_IsTeleporting", true)
			table.insert(filtered, p)
		end
	end
	if #filtered == 0 then
		return false, "all_players_already_teleporting"
	end
	local ok, terr = pcall(function()
		return TeleportService:TeleportAsync(resolvedPlaceId, filtered, options)
	end)
	if not ok then
		warn("[Script] TeleportAsync failed:", terr)
		return false, terr
	end
	return true
end

-- [Infinite Mode] No wave config needed - waves are generated procedurally
print("[InfiniteMode] Ready - waves will be generated dynamically")
local CharacterInventory = require(ScriptsFolder:WaitForChild("CharacterInventory"))

-- Card system modules (needed for applying chosen cards)
local CardsFolder = sharedFolder:WaitForChild("Cards")
local CardDispatcher = require(CardsFolder:WaitForChild("CardDispatcher"))

-- Ensure remotes for card level-up flow
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
local LevelUpEvent = Remotes:FindFirstChild("LevelUp") or Instance.new("RemoteEvent")
LevelUpEvent.Name = "LevelUp"
LevelUpEvent.Parent = Remotes
local LevelUpChoice = Remotes:FindFirstChild("LevelUpChoice") or Instance.new("RemoteEvent")
LevelUpChoice.Name = "LevelUpChoice"
LevelUpChoice.Parent = Remotes
-- DeathMenu remotes
-- Revive removed: Infinite mode has permanent death for leaderboard integrity
local DeathMenuRestart = Remotes:FindFirstChild("DeathMenuRestart") or Instance.new("RemoteEvent")
DeathMenuRestart.Name = "DeathMenuRestart"
DeathMenuRestart.Parent = Remotes
-- Early exit (abort) remote: player asks to leave run now and still receive accumulated XP (no bonus)
local AbortRunRE = Remotes:FindFirstChild("AbortRun") or Instance.new("RemoteEvent")
AbortRunRE.Name = "AbortRun"
AbortRunRE.Parent = Remotes
-- End-of-run choice: let player replay or return to lobby later
local RunReturnToLobbyRE = Remotes:FindFirstChild("RunReturnToLobby") or Instance.new("RemoteEvent")
RunReturnToLobbyRE.Name = "RunReturnToLobby"
RunReturnToLobbyRE.Parent = Remotes
local RunPlayAgainRE = Remotes:FindFirstChild("RunPlayAgain") or Instance.new("RemoteEvent")
RunPlayAgainRE.Name = "RunPlayAgain"
RunPlayAgainRE.Parent = Remotes
-- Feedback event for client to surface success/failure messages when requesting play again
local RunPlayAgainResult = Remotes:FindFirstChild("RunPlayAgainResult") or Instance.new("RemoteEvent")
RunPlayAgainResult.Name = "RunPlayAgainResult"
RunPlayAgainResult.Parent = Remotes

-- RunCompleted remote: server notifies clients run has ended and provides summary
local RunCompletedRE = Remotes:FindFirstChild("RunCompleted") or Instance.new("RemoteEvent")
RunCompletedRE.Name = "RunCompleted"
RunCompletedRE.Parent = Remotes

-- Remote event for sending init debug info to the client (developer-only)
local DebugInitRE = Remotes:FindFirstChild("DebugInit") or Instance.new("RemoteEvent")
DebugInitRE.Name = "DebugInit"
DebugInitRE.Parent = Remotes

-- Global game pause attribute (true while any player is choosing a card)
ReplicatedStorage:SetAttribute("GamePaused", false)

-- (removed duplicate; helper is defined earlier)

-- Recompute global pause based on any player PausedForCard
local function recomputeGlobalPause()
	local anyPaused = false
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if char and char:GetAttribute("PausedForCard") then
			anyPaused = true
			break
		end
	end
	ReplicatedStorage:SetAttribute("GamePaused", anyPaused)
end

-- Small helper to set a numeric stat on a player's leaderstats safely
local function setPlayerNumberStat(player, name, value)
	if not player then return end
	pcall(function()
		local ls = player:FindFirstChild("leaderstats")
		if not ls then ls = Instance.new("Folder") ls.Name = "leaderstats" ls.Parent = player end
		local nv = ls:FindFirstChild(name)
		if not nv then nv = Instance.new("NumberValue") nv.Name = name nv.Parent = ls end
		if typeof(value) == "number" then
			nv.Value = value
		else
			-- try to coerce
			local n = tonumber(value) or 0
			nv.Value = n
		end
	end)
end

-- Leaderstat sync helpers: small, safe implementation so references to hookRunTrackToLeaderstats don't fail.
local leaderstatConnections = {}

local function cleanupLeaderConns(player)
	if not player then return end
	local conns = leaderstatConnections[player]
	if conns then
		for _, c in ipairs(conns) do
			pcall(function() c:Disconnect() end)
		end
	end
	leaderstatConnections[player] = nil
end
local function hookRunTrackToLeaderstats(player)
	if not player then return end
	if type(player.IsA) ~= "function" then return end
	if not player:IsA("Player") then return end
	-- Ensure we don't leak connections
	cleanupLeaderConns(player)
	leaderstatConnections[player] = {}

	local function attach()
		local runTrack = player:FindFirstChild("RunTrack")
		local ls = player:FindFirstChild("leaderstats")
		if not runTrack or not ls then return end

		local function watchName(name)
			local val = runTrack:FindFirstChild(name)
			if not val then return end
			local lsVal = ls:FindFirstChild(name)
			if not lsVal then
				-- Mirror type: prefer IntValue for integer-like names
				lsVal = Instance.new(val.ClassName)
				lsVal.Name = name
				lsVal.Parent = ls
			end
			-- Set initial
			pcall(function() lsVal.Value = val.Value end)
			-- Track changes
			local conn = val:GetPropertyChangedSignal("Value"):Connect(function()
				pcall(function() lsVal.Value = val.Value end)
			end)
			table.insert(leaderstatConnections[player], conn)
		end

		watchName("Kills")
		watchName("Damage")
		watchName("Healing")
		watchName("RunTime")
	end

	-- Attempt immediate attach and also watch for future creation of RunTrack/leaderstats
	pcall(attach)
	local childConn = player.ChildAdded:Connect(function(child)
		if child and (child.Name == "RunTrack" or child.Name == "leaderstats") then
			pcall(attach)
		end
	end)
	table.insert(leaderstatConnections[player], childConn)
end

-- Callbacks (attached on WaveManager instantiation)
local function server_OnWaveStarted(waveIndex)
	for _, plr in ipairs(Players:GetPlayers()) do
		setPlayerNumberStat(plr, "CurrentWave", waveIndex)
		pcall(function() ReplicatedStorage:SetAttribute("CurrentWave", waveIndex) end)
		if waveIndex == 1 then
			pcall(function()
				local runTrack = plr:FindFirstChild("RunTrack")
				if not runTrack then runTrack = Instance.new("Folder") runTrack.Name = "RunTrack" runTrack.Parent = plr end
				local rs = runTrack:FindFirstChild("RunStart") or Instance.new("NumberValue") rs.Name = "RunStart" rs.Parent = runTrack
				rs.Value = os.clock()
				local rt = runTrack:FindFirstChild("RunTime") or Instance.new("NumberValue") rt.Name = "RunTime" rt.Parent = runTrack
				rt.Value = 0
			end)
		end
	end
end

-- XP por wave: acumula valor FULL por instância em RunAccum/CharacterXP
grantWaveCharacterXP = function(player, waveIndex)
	if runEnded then return end
	local cfg = wavesConfig and wavesConfig.CharacterXP
	if not cfg then return end
	local base = cfg.BasePerWave or 0
	local growth = cfg.GrowthPerWave or 0
	local amount = math.floor(base + growth * (waveIndex - 1))
	if amount <= 0 then return end
	-- Recuperar instâncias equipadas via CharacterInventory + CharactersModule fallback
	local equipped = CharactersModule:GetEquipped(player)
	if not equipped or #equipped == 0 then return end
	local runAccum = player:FindFirstChild("RunAccum") or Instance.new("Folder")
	runAccum.Name = "RunAccum"
	runAccum.Parent = player
	local cxp = runAccum:FindFirstChild("CharacterXP") or Instance.new("Folder")
	cxp.Name = "CharacterXP"
	cxp.Parent = runAccum
	for _, info in ipairs(equipped) do
		-- Usa InstanceId se existir (fluxo instanciado); caso contrário fallback para Name
		local key = info.InstanceId or info.Name
		local nv = cxp:FindFirstChild(key) or Instance.new("NumberValue")
		nv.Name = key
		nv.Parent = cxp
		nv.Value += amount -- FULL XP por personagem equipado (não dividido)
	end
	-- AccountXP: somar todos os ganhos de personagens desta wave (equipped * amount)
	local axp = runAccum:FindFirstChild("AccountXP")
	if not axp then
		axp = Instance.new("NumberValue")
		axp.Name = "AccountXP"
		axp.Value = 0
		axp.Parent = runAccum
	end
	axp.Value += amount * #equipped
end

-- Converte XP acumulado (RunAccum/CharacterXP) em CharacterLeveling e limpa acumulador
applyAccumulatedCharacterXP = function(player, applyBonus)
	local runAccum = player:FindFirstChild("RunAccum")
	if not runAccum then return end
	local cxp = runAccum:FindFirstChild("CharacterXP")
	if not cxp then return end
	local instancesFolder = player:FindFirstChild("CharacterInstances")
	local equippedList = CharactersModule:GetEquipped(player)
	if not equippedList or #equippedList == 0 then return end
	-- Build lookup de InstanceId -> instFolder
	local instanceLookup = {}
	if instancesFolder then
		for _, inst in ipairs(instancesFolder:GetChildren()) do
			instanceLookup[inst.Name] = inst
		end
	end
	local bonusMultiplier = 1
	if typeof(applyBonus) == "number" and applyBonus > 0 then
		bonusMultiplier = 1 + applyBonus / 100
	end
	for _, info in ipairs(equippedList) do
		local key = info.InstanceId or info.Name
		local nv = cxp:FindFirstChild(key)
		if nv and nv:IsA("NumberValue") and nv.Value > 0 then
			local totalXP = math.floor(nv.Value * bonusMultiplier + 0.5)
			-- Aplicar apenas se a instância existir
			local instFolder = instanceLookup[key]
			if instFolder then
				CharacterLeveling.AddXPInstance(instFolder, totalXP)
			end
		end
	end
	-- Limpa acumulado
	cxp:ClearAllChildren()
end

-- Converte XP acumulado de conta (RunAccum/AccountXP) em AccountLeveling e zera acumulador
applyAccumulatedAccountXP = function(player, applyBonus)
	local runAccum = player:FindFirstChild("RunAccum")
	if not runAccum then return end
	local axp = runAccum:FindFirstChild("AccountXP")
	if not axp or not axp:IsA("NumberValue") then return end
	if axp.Value <= 0 then return end
	local bonusMultiplier = 1
	if typeof(applyBonus) == "number" and applyBonus > 0 then
		bonusMultiplier = 1 + applyBonus / 100
	end
	local total = math.floor(axp.Value * bonusMultiplier + 0.5)
	AccountLeveling:AddXP(player, total)
	axp.Value = 0
end

-- Quando uma wave é limpa (WaveManager deve disparar OnWaveCleared se suportado)
-- Will be attached via configureWaveManagerCallbacks when WaveManager is created

-- Forward declare to allow usage before definition
local offerCardsToPlayer

-- Store the exact meta for the currently displayed offer per player to avoid rescanning entire pool on selection.
-- PendingOffers[player] = { [cardId] = metaTable }
local PendingOffers: { [Player]: { [string]: any } } = {}

-- Track pending level ups for each player (for multi-level gains)
local PendingLevelUps: { [Player]: number } = {}

-- Expose a named implementation so configureWaveManagerCallbacks can call it
function Server_OnEnemyDied_Impl(info)
	local humanoid = info.enemy:FindFirstChildOfClass("Humanoid")
	local killer
	if humanoid then
		local creatorTag = humanoid:FindFirstChild("creator")
		killer = creatorTag and creatorTag.Value
	end
	-- Always increment kills for the creator player when possible (once per enemy)
	if killer and killer:IsA("Player") then
		pcall(function()
			local enemy = info and info.enemy
			if enemy and enemy:GetAttribute("KillCounted") then
				-- already counted
			else
				if enemy then enemy:SetAttribute("KillCounted", true) end
				local rt = killer:FindFirstChild("RunTrack")
				if not rt then rt = Instance.new("Folder") rt.Name = "RunTrack" rt.Parent = killer end
				local kv = rt:FindFirstChild("Kills") or Instance.new("IntValue") kv.Name = "Kills" kv.Parent = rt
				kv.Value = (kv.Value or 0) + 1
				-- Debug: log kill increments for telemetry verification
				pcall(function()
					print(string.format("[OnEnemyDied] Kill credited to %s -> Kills=%d (wave=%s)", tostring(killer.Name), tonumber(kv.Value) or 0, tostring(info and info.waveIndex)))
				end)
			end
		end)
	end

	if killer and killer:IsA("Player") and info.drops and info.drops.XP then
		-- Capture death position before model is destroyed
		local deathPos
		do
			local ok, cf = pcall(function() return info.enemy:GetPivot() end)
			if ok and typeof(cf) == "CFrame" then
				deathPos = cf.Position
			else
				local pp = info.enemy.PrimaryPart or info.enemy:FindFirstChild("HumanoidRootPart")
				deathPos = pp and pp.Position or nil
			end
		end
		
		print(string.format("[XP Debug] Enemy %s dropped %d XP (type: %s, wave: %s)", 
			info.enemy.Name, info.drops.XP, tostring(info.type), tostring(info.waveIndex)))
		
		local gained = Leveling:AddXP(killer, info.drops.XP)
		if gained > 0 then
			print(string.format("%s gained %d level(s), now level %d", killer.Name, gained, (killer:FindFirstChild("Stats") and killer.Stats.Level.Value or "?")))
			
			-- Accumulate pending level ups
			PendingLevelUps[killer] = (PendingLevelUps[killer] or 0) + gained
			
			-- Offer cards on level up (will show UI for first level, queue the rest)
			if offerCardsToPlayer then
				offerCardsToPlayer(killer)
			end
		end
		-- Also log kill attribution for telemetry verification
		pcall(function()
			local rt = killer:FindFirstChild("RunTrack")
			local kv = rt and rt:FindFirstChild("Kills")
			if kv then
				print(string.format("[OnEnemyDied] (early) Kill credited to %s -> Kills=%d (wave=%s)", tostring(killer.Name), tonumber(kv.Value) or 0, tostring(info and info.waveIndex)))
			end
		end)

		-- Mid-run coin rewards removed: do not accumulate or grant Gold on kill

		-- Shadow Clone on-kill effect: 5% chance if the player has the card
		do
			local upgrades = killer:FindFirstChild("Upgrades")
			local onKill = upgrades and upgrades:FindFirstChild("OnKill")
			local cloneCfg = onKill and onKill:FindFirstChild("ShadowClone")
			if cloneCfg and deathPos then
				local chanceNV = cloneCfg:FindFirstChild("Chance")
				local durationNV = cloneCfg:FindFirstChild("Duration")
				local chance = tonumber(chanceNV and chanceNV.Value) or 0
				local duration = tonumber(durationNV and durationNV.Value) or 5
				if chance > 0 and math.random() < chance then
					-- Debug: log spawn location vs player location to diagnose mis-spawn
					local khrp = killer.Character and killer.Character:FindFirstChild("HumanoidRootPart")
					local kpos = khrp and khrp.Position or nil
					pcall(function()
						print(string.format("[ShadowClone] Spawn at deathPos (%.1f, %.1f, %.1f); player at %s",
							deathPos.X, deathPos.Y, deathPos.Z,
							kpos and string.format("(%.1f, %.1f, %.1f)", kpos.X, kpos.Y, kpos.Z) or "(nil)"
						))
					end)
					-- Carregamento lazy: obter módulo só se necessário
					local shadowMod = CardDispatcher.GetModule("ShadowClone")
					if shadowMod and type(shadowMod.Spawn) == "function" then
						shadowMod.Spawn(killer, deathPos, duration)
					end
				end
			end
		end
	end
end

-- WaveManager is started after PlayerAdded once TeleportData determines the LevelName

-- Initialize player (somente progressão persistente; sem CharacterInstances runtime)
local function InitializePlayer(player)
	-- Ensure RunAccum structure exists early so other flows (restart/return) don't fail
	pcall(function()
		local ra = player:FindFirstChild("RunAccum")
		if not ra then ra = Instance.new("Folder") ra.Name = "RunAccum" ra.Parent = player end
		local cxp = ra:FindFirstChild("CharacterXP") or Instance.new("Folder") cxp.Name = "CharacterXP" cxp.Parent = ra
		local axp = ra:FindFirstChild("AccountXP") or Instance.new("NumberValue") axp.Name = "AccountXP" axp.Value = axp.Value or 0 axp.Parent = ra
		local last = ra:FindFirstChild("LastRunResultJSON") or Instance.new("StringValue") last.Name = "LastRunResultJSON" last.Value = last.Value or "" last.Parent = ra
	end)

	EquippedItemsModule:Initialize(player)
	-- Garantir estrutura de níveis de itens (Weapon/Armor/Ring) default = 1
	pcall(function()
		ItemLeveling:Ensure(player)
	end)
	-- Prefer rebuild from JoinData.TeleportData when available (ensures lobby-provided characters/equipment are used)
	pcall(function()
		local joinData = player:GetJoinData()
		local td = joinData and joinData.TeleportData
		CharacterInventory.Rebuild(player, td)
	end)
	-- Equipar personagens padrão diretamente (ChosenChars) via CharactersModule
	CharactersModule:Initialize(player)
	-- Deserialize equipped items from TeleportData (template names provided by lobby)
	pcall(function()
		local joinData = player:GetJoinData()
		local td = joinData and joinData.TeleportData
		-- Restore PendingTotals accumulation across chained runs
		if td and type(td.PendingTotals) == "table" then
			local pt = td.PendingTotals
			local rr = {
				AccountXP = tonumber(pt.AccountXP) or 0,
				CharacterXP = (type(pt.CharacterXP) == "table") and pt.CharacterXP or nil,
				Rewards = {
					Gold = (pt.Rewards and tonumber(pt.Rewards.Gold)) or 0,
					Gems = (pt.Rewards and tonumber(pt.Rewards.Gems)) or 0,
					Items = (pt.Rewards and type(pt.Rewards.Items) == "table") and pt.Rewards.Items or {},
				},
			}
			addToPending(player, rr)
			local cxpKeys = 0
			if type(rr.CharacterXP) == "table" then for _ in pairs(rr.CharacterXP) do cxpKeys += 1 end end
			print(string.format("[Init] Restored PendingTotals via TeleportData (AXP=%d, CXPkeys=%d, Gold=%d, Gems=%d)", rr.AccountXP or 0, cxpKeys, rr.Rewards.Gold or 0, rr.Rewards.Gems or 0))
		end
		local items = td and td.Items
		local eqt = items and items.EquippedTemplates
		if type(eqt) == "table" then
			local ser = {
				Weapon = eqt.Weapon,
				Armor = eqt.Armor,
				Ring = eqt.Ring,
			}
			local eqMod = require(ReplicatedStorage.Scripts.EquipedItems)
			-- Reuse module's EquipItemById path
			if ser.Weapon then eqMod:EquipItemById(player, "Weapon", ser.Weapon) end
			if ser.Armor then eqMod:EquipItemById(player, "Armor", ser.Armor) end
			if ser.Ring then eqMod:EquipItemById(player, "Ring", ser.Ring) end
			-- Also set equipped item levels if provided
			local levels = items and items.EquippedItemLevels
			if type(levels) == "table" then
				pcall(function()
					local il = require(ReplicatedStorage.Scripts.ItemLeveling)
					il:Ensure(player)
					if tonumber(levels.Weapon) then il:SetLevel(player, "Weapon", levels.Weapon) end
					if tonumber(levels.Armor) then il:SetLevel(player, "Armor", levels.Armor) end
					if tonumber(levels.Ring) then il:SetLevel(player, "Ring", levels.Ring) end
				end)
			end
			-- And store qualities for later multiplier application
			local quals = items and items.EquippedItemQualities
			if type(quals) == "table" then
				local qf = player:FindFirstChild("EquippedItemQualities")
				if not qf then qf = Instance.new("Folder") qf.Name = "EquippedItemQualities" qf.Parent = player end
				local function setStr(name, val)
					if type(val) ~= "string" or val == "" then return end
					local sv = qf:FindFirstChild(name)
					if not sv then sv = Instance.new("StringValue") sv.Name = name sv.Parent = qf end
					sv.Value = val
				end
				setStr("Weapon", quals.Weapon)
				setStr("Armor", quals.Armor)
				setStr("Ring", quals.Ring)
			end
		end
	end)
	local equippedItems = EquippedItemsModule:GetEquipped(player)
	local chars = CharactersModule:GetEquipped(player)
	ApplyStatsModule:Apply(player, equippedItems, chars)
	-- Desativar regen default do Roblox assim que character existir
	if player.Character then
		local hum = player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			-- Roblox default regen utiliza script Health em Character; já removemos acima. Garantir sem regen extra.
			-- Caso algum script reintroduza, removemos novamente.
			hum:SetAttribute("_CustomRegen", true)
		end
	end
	-- Player run leveling base
	Leveling:EnsureStats(player, 1)
	-- Ensure RunTrack folder and basic counters (Kills, Damage, RunStart, RunTime)
	pcall(function()
		local runTrack = player:FindFirstChild("RunTrack")
		if not runTrack then runTrack = Instance.new("Folder") runTrack.Name = "RunTrack" runTrack.Parent = player end
		local kv = runTrack:FindFirstChild("Kills") or Instance.new("IntValue") kv.Name = "Kills" kv.Value = kv.Value or 0 kv.Parent = runTrack
		local dv = runTrack:FindFirstChild("Damage") or Instance.new("NumberValue") dv.Name = "Damage" dv.Value = dv.Value or 0 dv.Parent = runTrack
		local hv = runTrack:FindFirstChild("Healing") or Instance.new("NumberValue") hv.Name = "Healing" hv.Value = hv.Value or 0 hv.Parent = runTrack
		local rs = runTrack:FindFirstChild("RunStart") or Instance.new("NumberValue") rs.Name = "RunStart" rs.Value = 0 rs.Parent = runTrack
		local rt = runTrack:FindFirstChild("RunTime") or Instance.new("NumberValue") rt.Name = "RunTime" rt.Value = rt.Value or 0 rt.Parent = runTrack
	end)
	-- Wave metadata (if waveManager / wavesConfig already defined)
	pcall(function()
		if wavesConfig and wavesConfig.Waves then
			setPlayerNumberStat(player, "TotalWaves", #wavesConfig.Waves)
			setPlayerNumberStat(player, "CurrentWave", waveManager:GetWaveIndex())
		end
	end)
end

-- Global cleanup for any Enemy-tagged models (covers enemies spawned outside WaveManager)
do
	local function disableCollisions(container)
		for _, d in ipairs(container:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanTouch = false
		-- DEBUG: log join payload, equipped templates/stats, characters and computed Health
		pcall(function()
			local js = "[InitDebug]"
			local join = player:GetJoinData()
			local jtd = join and join.TeleportData
			if jtd then
				local s = jtd.Story
				print(js, "Join TeleportData present for", player.Name, "Story=", s and tostring(s.MapId) or "nil", "Level=", s and tostring(s.Level) or "nil", "WaveKey=", s and tostring(s.WaveKey) or "nil")
			else
				print(js, "No Join TeleportData for", player.Name)
			end
			local eqt = jtd and jtd.Items and jtd.Items.EquippedTemplates
			if eqt then
				print(js, "Teleport EquippedTemplates -> Weapon:", tostring(eqt.Weapon), "Armor:", tostring(eqt.Armor), "Ring:", tostring(eqt.Ring))
			end
			-- Serializado atual dos itens equipados no jogador
			local ser = EquippedItemsModule:Serialize(player)
			print(js, "Equipped Serialize:", ser and (ser.Weapon or "nil") , ser and (ser.Armor or "nil"), ser and (ser.Ring or "nil"))
			-- Resolved stats tables
			local equipStats = EquippedItemsModule:GetEquipped(player) or {}
			local function dumpEquip(es)
				local w = es.weapon and (es.weapon.Health or es.weapon.HealthPercent or es.weapon.BaseHealth) or nil
				local a = es.armor and (es.armor.Health or es.armor.HealthPercent or es.armor.BaseHealth) or nil
				local r = es.ring and (es.ring.Health or es.ring.HealthPercent or es.ring.BaseHealth) or nil
				return w,a,r
			end
			local w,a,r = dumpEquip(equipStats)
			print(js, "Resolved equip stats Health -> Weapon:", tostring(w), "Armor:", tostring(a), "Ring:", tostring(r))
			local charsList = CharactersModule:GetEquipped(player) or {}
			for i,c in ipairs(charsList) do
				local ph = c and c.Passives and (c.Passives.Health or c.Passives.HealthPercent) or nil
				print(js, string.format("Char[%d]=%s Level=%s Tier=%s PassiveHealth=%s", i, tostring(c.Name), tostring(c.Level), tostring(c.Tier), tostring(ph)))
			end
			-- Compute final stats via PlayerStatsModule for inspection
			local ok, PlayerStatsModule = pcall(function() return require(ReplicatedStorage.Scripts:WaitForChild("PlayerStats")) end)
			if ok and type(PlayerStatsModule) == "table" then
				local final = PlayerStatsModule:Calculate(equipStats, charsList) or {}
				print(js, "PlayerStats.Calculate Health=", tostring(final.Health))
			end
			-- ReplicatedStorage / wave state
			print(js, "Replicated Storage StoryMapId=", ReplicatedStorage:GetAttribute("StoryMapId"), "StoryLevel=", ReplicatedStorage:GetAttribute("StoryLevel"), "LevelName=", ReplicatedStorage:GetAttribute("LevelName"))
			if waveManager and type(waveManager.IsRunning) == "function" then
				local ok, run = pcall(function() return waveManager:IsRunning() end)
				print(js, "waveManager.IsRunning=", ok and tostring(run) or "unknown")
			else
				print(js, "waveManager.IsRunning=unknown (waveManager not ready)")
			end

			-- Also fire client debug event for the joining player (if they are allowed)
			pcall(function()
				local ev = Remotes:FindFirstChild("DebugInit")
				if ev and ev:IsA("RemoteEvent") then
					local payload = {
						StoryMapId = ReplicatedStorage:GetAttribute("StoryMapId"),
						StoryLevel = ReplicatedStorage:GetAttribute("StoryLevel"),
						LevelName = ReplicatedStorage:GetAttribute("LevelName"),
						Player = player.Name,
						EquippedSerialize = ser,
						EquipResolved = equipStats,
						Chars = charsList,
						PlayerStatsHealth = (final and final.Health) or nil,
					}
					ev:FireClient(player, payload)
				end
			end)

			end)
				d.CanQuery = true
				d.Massless = true
			end
		end
	end
	local function safeDespawn(enemy)
		if not enemy or not enemy.Parent then return end
		pcall(disableCollisions, enemy)
		pcall(function() enemy:Destroy() end)
	end
	local function attachCleanup(m)
		if not m or not m.Parent then return end
		local hum = m:FindFirstChildOfClass("Humanoid")
		if not hum then
			m.AncestryChanged:Connect(function(_, parent)
				if not parent then return end
			end)
			return
		end
		if hum.Health <= 0 then
			task.defer(function() safeDespawn(m) end)
			return
		end
		hum.Died:Connect(function()
			task.defer(function() safeDespawn(m) end)
		end)
		hum.HealthChanged:Connect(function(h)
			if h <= 0 then
				task.defer(function() safeDespawn(m) end)
			end
		end)
	end
	pcall(function()
		for _, inst in ipairs(CollectionService:GetTagged("Enemy")) do
			attachCleanup(inst)
		end
	end)
	pcall(function()
		CollectionService:GetInstanceAddedSignal("Enemy"):Connect(function(inst)
			attachCleanup(inst)
		end)
	end)
	task.spawn(function()
		while true do
			task.wait(2)
			local ok, list = pcall(function() return CollectionService:GetTagged("Enemy") end)
			if ok and list then
				for _, e in ipairs(list) do
					if e and e.Parent then
						local hum = e:FindFirstChildOfClass("Humanoid")
						if hum and hum.Health <= 0 then
							safeDespawn(e)
						end
					end
				end
			end
		end
	end)

	-- Optional debug: compare TeleportData equipped count with reconstructed slot count
	pcall(function()
		if ReplicatedStorage:GetAttribute("DebugEquip") then
			local tdCount = -1
			local ok, tdp = pcall(function()
				local fn = TeleportService.GetPlayerTeleportData
				if typeof(fn) == "function" then
					return TeleportService:GetPlayerTeleportData(player)
				end
				return nil
			end)
			if ok and tdp and type(tdp.Equipped) == "table" then tdCount = #tdp.Equipped end
			local equippedFolder = player:FindFirstChild("Equipped")
			local slotCount = 0
			if equippedFolder then
				for _, ch in ipairs(equippedFolder:GetChildren()) do
					if ch:IsA("StringValue") and ch.Name:match("^Slot%d+") then slotCount += 1 end
				end
			end
			print(string.format("[InitializePlayer][%s] TeleportData Equipped=%d | Slots Rebuilt=%d", player.Name, tdCount, slotCount))
		end
	end)
end

--[[
-- CARD SYSTEM HOOK (COMMENTED OUT)
-- When you're ready to show 3 cards on level up, you can enable the RemoteEvent below
-- and use it to notify the client. The Leveling:AddXP already checks for Remotes.LevelUp
-- and will fire it if present.

-- -- Ensure Remotes/LevelUp exists (uncomment to enable)
-- local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
-- if not Remotes then
-- 	Remotes = Instance.new("Folder")
-- 	Remotes.Name = "Remotes"
-- 	Remotes.Parent = ReplicatedStorage
-- end
-- local LevelUpEvent = Remotes:FindFirstChild("LevelUp")
-- if not LevelUpEvent then
-- 	LevelUpEvent = Instance.new("RemoteEvent")
-- 	LevelUpEvent.Name = "LevelUp"
-- 	LevelUpEvent.Parent = Remotes
-- end

-- -- Optional: build server-side suggested card pool based on equipped characters
-- -- local CharactersModule = require(ScriptsFolder:WaitForChild("CharEquiped"))
-- -- local function getCardPoolForPlayer(player)
-- -- 	local pool = {}
-- -- 	-- Example: read equipped chars to filter pool
-- -- 	-- for _, char in ipairs(CharactersModule:GetEquipped(player)) do
-- -- 	-- 	-- add char-specific cards into pool
-- -- 	-- end
-- -- 	return pool
-- -- end

-- -- On level up, you could server-pick 3 cards and send to client:
-- -- LevelUpEvent:FireClient(player, {
-- -- 	{ id = "Card_AtkUp", name = "+20% Damage" },
-- -- 	{ id = "Card_Crit", name = "+10% Crit Chance" },
-- -- 	{ id = "Card_Lifesteal", name = "+3% Lifesteal" },
-- -- })
--]]

-- Se/quando quiseres ativar chars, basta requerer e inicializar:
-- local CharactersModule = require(ScriptsFolder:WaitForChild("CharEquiped"))

-- (duplicate legacy InitializePlayer removed; using new version after waveManager:Start)

-- Quando o jogador entra no jogo
Players.PlayerAdded:Connect(function(player)
	-- Conectar antes de LoadCharacter para garantir reapply imediato quando o humanoid existir
	player.CharacterAdded:Connect(function(char)
		task.defer(function()
			local items = EquippedItemsModule:GetEquipped(player)
			local chars = CharactersModule:GetEquipped(player)
			pcall(function() ApplyStatsModule:Apply(player, items, chars) end)
		end)
		-- Reapply 0.2s depois (race safeguard se ChosenChars / EquippedItems ainda a construir)
		task.delay(0.2, function()
			local items2 = EquippedItemsModule:GetEquipped(player)
			local chars2 = CharactersModule:GetEquipped(player)
			pcall(function() ApplyStatsModule:Apply(player, items2, chars2) end)
		end)
	end)
	InitializePlayer(player)
	
	-- [Infinite Mode] Auto-start waveManager when first player joins
	pcall(function()
		local inst = ensureWaveManager()
		if inst and type(inst.IsRunning) == "function" and not inst:IsRunning() then
			print("[InfiniteMode] Starting WaveManager for first player...")
			task.delay(0.5, function()
				pcall(function() inst:Start() end)
			end)
		end
	end)
	-- Ensure initial spawn happens once (revive remains manual after death)
	if not player.Character then
		pcall(function() player:LoadCharacter() end)
	end
	-- Reaplicar stats no respawn (revive / restart)
	-- (Aplicação primária movida para antes de LoadCharacter; mantida redundância acima)
	-- Server-side safeguard: remove default CoreScripts Health script if inserted
	local function scrubHealth(char: Model)
		-- Remove any default Health LocalScript placed under the character
		for _, child in ipairs(char:GetChildren()) do
			if child:IsA("LocalScript") and child.Name == "Health" then
				pcall(function() child:Destroy() end)
			end
		end
		-- Also monitor for future insertions and destroy immediately
		char.ChildAdded:Connect(function(child)
			if child:IsA("LocalScript") and child.Name == "Health" then
				pcall(function() child:Destroy() end)
			end
		end)
	end
	if player.Character then scrubHealth(player.Character) end
	player.CharacterAdded:Connect(scrubHealth)

	-- Hook leaderstats to RunTrack
	hookRunTrackToLeaderstats(player)
end)

-- Studio quick play: initialize any players already present
for _, plr in ipairs(Players:GetPlayers()) do
	task.spawn(InitializePlayer, plr)
	-- Instrumenta Humanoid.Health para logar qualquer alteração e blinda contra regen automática
	local function attachHealthLogger(char)
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			-- Desativa explicitamente a regen padrão do Roblox
			-- ...existing code...
		end
	end
	if plr.Character then attachHealthLogger(plr.Character) end
	plr.CharacterAdded:Connect(attachHealthLogger)
end

-- Hook existing players' leaderstats
for _, plr in ipairs(Players:GetPlayers()) do
    pcall(function() hookRunTrackToLeaderstats(plr) end)
end

-- Cleanup: ensure periodic card loops are stopped on leave
Players.PlayerRemoving:Connect(function(player)
	-- Para qualquer loop/aura de cartas com método Stop
	pcall(function() CardDispatcher.StopAllForPlayer(player) end)
	CardDispatcher.ClearPlayer(player)
	-- Persist aggregated RunResult on disconnect so lobby can apply rewards even if player leaves mid-run
	pcall(function()
		if DS_GLOBAL and type(DS_GLOBAL.saveRunResult) == "function" then
			local ok, aggregated = pcall(function() return buildAggregatedRunResult(player) end)
			if ok and type(aggregated) == "table" then
				-- Determine if there's anything worth saving (avoid empty writes)
				local hasAccount = (tonumber(aggregated.AccountXP) or 0) > 0
				local hasChar = (type(aggregated.CharacterXP) == "table" and next(aggregated.CharacterXP) ~= nil)
				local rew = aggregated.Rewards or {}
				local itemsCount = (type(rew.Items) == "table") and #rew.Items or 0
				local hasCharRewards = (type(rew.Characters) == "table" and #rew.Characters > 0)
				local hasDamage = (tonumber(aggregated.TotalDamage) or 0) > 0
				local hasRewards = (tonumber(rew.Gold) or 0) > 0 or (tonumber(rew.Gems) or 0) > 0 or itemsCount > 0 or hasCharRewards
				local shouldSave = hasAccount or hasChar or hasRewards or hasDamage or (aggregated.Win == true)
				if shouldSave then
					pcall(function()
						local runId = HttpService:GenerateGUID(false)
						aggregated.RunId = runId
						local sOk, sErr = DS_GLOBAL.saveRunResult(player.UserId, runId, aggregated)
						if not sOk then
							warn(string.format("[Script][PlayerRemoving] saveRunResult failed for %s: %s", tostring(player.Name), tostring(sErr)))
						else
							print(string.format("[Script][PlayerRemoving] saved RunResult for %s (RunId=%s)", tostring(player.Name), tostring(runId)))
						end
					end)
				end
			end
		end
	end)
	-- Aplicar XP acumulado (sem bônus final) se sair antes do fim
	pcall(function()
		if not runEnded then
			applyAccumulatedCharacterXP(player, 0)
			if applyAccumulatedAccountXP then
				applyAccumulatedAccountXP(player, 0)
			end
			local items = EquippedItemsModule:GetEquipped(player)
			local charsNow = CharactersModule:GetEquipped(player)
			ApplyStatsModule:Apply(player, items, charsNow)
		end
	end)

		-- Cleanup leaderstat connections
		cleanupLeaderConns(player)
end)

-- Derrota: todos os jogadores vivos? Monitor simples: se nenhum Player.Character com Humanoid.Health>0 enquanto waves ainda decorrem.
task.spawn(function()
	local myToken = {}
	defeatMonitorThread = myToken
	while not runEnded and defeatMonitorThread == myToken do
		task.wait(1)
		-- Guard against nil waveManager during early server init
		if not waveManager or type(waveManager.IsRunning) ~= "function" then break end
		if not waveManager:IsRunning() then break end
		local anyAlive = false
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then anyAlive = true break end
		end
		if anyAlive then
			lastAliveTimestamp = os.clock()
		else
			if not lastAliveTimestamp then
				lastAliveTimestamp = os.clock()
			else
				if os.clock() - lastAliveTimestamp >= DEFEAT_GRACE_SECONDS then
					endRun(false)
					break
				end
			end
		end
	end
end)

-- Custom HP regeneration loop (uses Stats.HPRegenPerSecond). Default regen script removed.
do
	local lastUpdate = os.clock()
	RunService.Heartbeat:Connect(function(dt)
		-- Process regen roughly each 0.25s for performance (accumulate dt)
		local now = os.clock()
		if now - lastUpdate < 0.25 then return end
		local elapsed = now - lastUpdate
		lastUpdate = now
		local debugRegen = ReplicatedStorage:GetAttribute("DebugRegen")
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and hum.Health < hum.MaxHealth then
				local stats = plr:FindFirstChild("Stats")
				if stats then
					local regen = stats:FindFirstChild("HPRegenPerSecond")
					local rate = regen and regen:IsA("NumberValue") and regen.Value or 0
					if rate ~= 0 then
						local add = rate * elapsed
						if add ~= 0 then
							local newHealth = math.clamp(hum.Health + add, 0, hum.MaxHealth)
							hum.Health = newHealth
							if debugRegen then
								print(string.format("[DebugRegen] %s: HP +%.2f (rate=%.2f, elapsed=%.2f) -> %.2f/%.2f", plr.Name, add, rate, elapsed, newHealth, hum.MaxHealth))
							end
						end
					elseif debugRegen then
						print(string.format("[DebugRegen] %s: NO REGEN (rate=%.2f, HP=%.2f/%.2f)", plr.Name, rate, hum.Health, hum.MaxHealth))
					end
				elseif debugRegen then
					print(string.format("[DebugRegen] %s: NO Stats folder", plr.Name))
				end
			elseif debugRegen and hum then
				print(string.format("[DebugRegen] %s: Not eligible (HP=%.2f/%.2f)", plr.Name, hum.Health, hum.MaxHealth))
			end
		end
	end)
end

-- Helper to record healing into RunTrack (callable by other server modules)
function AddRunHealing(player, amount)
	if not player or typeof(amount) ~= "number" or amount <= 0 then return end
	pcall(function()
		local runTrack = player:FindFirstChild("RunTrack")
		if not runTrack then
			runTrack = Instance.new("Folder") runTrack.Name = "RunTrack" runTrack.Parent = player
		end
		local hv = runTrack:FindFirstChild("Healing") or Instance.new("NumberValue")
		hv.Name = "Healing"
		if not hv.Parent then hv.Parent = runTrack end
		hv.Value = (hv.Value or 0) + amount
		-- Also update leaderstats if present
		local ls = player:FindFirstChild("leaderstats")
		if ls and ls:FindFirstChild("Healing") then
			local lhv = ls:FindFirstChild("Healing")
			lhv.Value = math.floor(hv.Value)
		end
	end)
end

-- Instrument regen loop to credit healing amounts (only when regen adds HP)
do
	RunService.Heartbeat:Connect(function(dt)
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then
				local cur = hum.Health
				local last = prevHP[hum] or cur
				if cur > last then
					local healAmt = cur - last
					-- Record healing only when positive (regen, lifesteal, etc.)
					AddRunHealing(plr, healAmt)
				end
				prevHP[hum] = cur
			end
		end
	end)
end

-- Revive handler removed: Infinite mode uses permanent death for leaderboard integrity

DeathMenuRestart.OnServerEvent:Connect(function(player)
	-- Bloquear se já venceu (WavesCompleted=true)
	if ReplicatedStorage:GetAttribute("WavesCompleted") then return end
	-- If the requester is dead, respawn so client camera rebinds to new character
	pcall(function()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if (not hum) or hum.Health <= 0 then
			player:LoadCharacter()
		end
	end)
	-- Try teleport to a reserved server for a clean restart (carry Story + ReturnPlaceId + PendingTotals via helper)
	local currentPlace = tonumber(game.PlaceId)
	local sid = ReplicatedStorage:GetAttribute("StoryMapId")
	local lvl = tonumber(ReplicatedStorage:GetAttribute("StoryLevel")) or 1
	local payload = { RestartFromDeath = true }
	if sid then payload.Story = { MapId = tostring(sid), Level = lvl } end
	local ok, err = teleportToReservedServer(currentPlace, { player }, payload)
	if not ok then
		print("[DeathMenuRestart] teleport reserved server failed:", tostring(err))
		-- Fallback in Studio: reload character so client can rebind; notify client that restart couldn't create a private server
		player:LoadCharacter()
		local ev = Remotes:FindFirstChild("RunPlayAgainResult")
		if ev and ev:IsA("RemoteEvent") then
			ev:FireClient(player, { success = false, reason = "teleport_failed", message = "Não foi possível criar servidor privado. Recarreguei o personagem." })
		end
	end
end)

-- Opcional: quando o jogador muda equipamentos/personagens, chamar novamente Apply

-- Pause helpers for card selection
local function setPaused(player: Player, paused: boolean)
	-- Freeze character movement and stop auto-attack loop by setting an attribute the loop can read
	if player and player.Character then
		local hum = player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			if paused then
				-- Force halt movement; set WalkSpeed and JumpPower to zero during pause
				hum.WalkSpeed = 0
				hum.JumpPower = 0
				hum:ChangeState(Enum.HumanoidStateType.Physics)
			else
				-- Restore defaults; actual desired values will be set by gameplay code naturally
				hum.WalkSpeed = 16
				hum.JumpPower = 50
				hum:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
				hum:ChangeState(Enum.HumanoidStateType.Running)
			end
		end
		player.Character:SetAttribute("PausedForCard", paused)
	end
	recomputeGlobalPause()
end

-- SuperWarriorCard agora carregado dinamicamente apenas se/quando necessário

-- Basic server-side card selection flow
offerCardsToPlayer = function(player: Player)
	if not player then return end
	
	-- Skip if player already has a pending offer (avoid showing multiple card UIs at once)
	if PendingOffers[player] then
		print(string.format("[Cards] Player %s already has pending offer, skipping", player.Name))
		return
	end
	
	-- Check if player has pending level ups
	local pending = PendingLevelUps[player] or 0
	if pending <= 0 then
		print(string.format("[Cards] No pending level ups for %s", player.Name))
		return
	end
	
	-- Debug: inspect pool sources and sizes
	local function listEquippedNames()
		local chosen = player:FindFirstChild("ChosenChars")
		local names = {}
		if chosen then
			for _, ov in ipairs(chosen:GetChildren()) do
				if ov:IsA("ObjectValue") and ov.Value then table.insert(names, ov.Name .. "->" .. ov.Value.Name) end
			end
		end
		return names
	end
	local debugPool = CardPool:GetCardsForPlayer(player)
	if not debugPool or #debugPool == 0 then
		local names = listEquippedNames()
		warn(string.format("[Cards][Debug] Pool empty for %s. ChosenChars: %s", player.Name, table.concat(names, ", ")))
		-- Tentar reinicializar personagens equipadas (ex.: garantir Naruto_5 por defeito)
		CharactersModule:Initialize(player)
		debugPool = CardPool:GetCardsForPlayer(player)
		if not debugPool or #debugPool == 0 then
			local names2 = listEquippedNames()
			warn(string.format("[Cards][Debug] Após reinicializar, pool ainda vazia para %s. ChosenChars: %s", player.Name, table.concat(names2, ", ")))
		else
			print(string.format("[Cards][Debug] Pool reapareceu após reinicializar (%d cartas).", #debugPool))
		end
	end
	local cards = CardPool:OfferByRarity(player, 3, { Common = 60, Rare = 25, Epic = 15, Legendary = 5 })
	if cards and #cards > 0 then
		setPaused(player, true)
		-- Build quick lookup map for this specific offer
		local map = {}
		for _, meta in ipairs(cards) do
			map[meta.id] = meta
		end
		PendingOffers[player] = map
		-- Debug: log offered ids for this player
		local offeredIds = {}
		for k,_ in pairs(map) do table.insert(offeredIds, k) end
		print(string.format("[Cards][Debug] Offered to %s (%d pending levels): %s", player.Name, pending, table.concat(offeredIds, ", ")))
		LevelUpEvent:FireClient(player, { cards = cards })
	else
		warn("[Cards] No cards available to offer for", player.Name)
		-- Se não há cartas mas há levels pendentes, decrementa mesmo assim
		PendingLevelUps[player] = math.max(0, pending - 1)
	end
end

LevelUpChoice.OnServerEvent:Connect(function(player, choice)
	setPaused(player, false)
	if not choice or type(choice) ~= "table" then return end
	local id = choice.id
	local offerMap = PendingOffers[player]
	-- Debug: inspect pending offers at selection time
	if offerMap then
		local keys = {}
		for k,_ in pairs(offerMap) do table.insert(keys, k) end
		print(string.format("[Cards][Debug] %s selected %s; pending offers: %s", player.Name, tostring(id), table.concat(keys, ", ")))
	else
		print(string.format("[Cards][Debug] %s selected %s; pending offers: nil", player.Name, tostring(id)))
	end
	if not (offerMap and offerMap[id]) then
		warn("[Cards] Selected id not in pending offer for", player.Name, id)
		return
	end
	local chosenMeta = offerMap[id]
	-- Clear pending offers for this player (one-time use)
	-- Debug: log clearing pending offers
	print(string.format("[Cards][Debug] Clearing pending offers for %s (chosen %s)", player.Name, id))
	PendingOffers[player] = nil
	
	-- Decrement pending level ups
	local pending = PendingLevelUps[player] or 0
	if pending > 0 then
		PendingLevelUps[player] = pending - 1
		print(string.format("[Cards] %s has %d more level up(s) pending", player.Name, PendingLevelUps[player]))
	end
	-- Record chosen card id (unique tracking) so pool filtering works
	local runTrack = player:FindFirstChild("RunTrack") or Instance.new("Folder")
	runTrack.Name = "RunTrack"
	runTrack.Parent = player
	local chosenIds = runTrack:FindFirstChild("ChosenCards") or Instance.new("Folder")
	chosenIds.Name = "ChosenCards"
	chosenIds.Parent = runTrack
	local chosenTag = chosenIds:FindFirstChild(id) or Instance.new("BoolValue")
	chosenTag.Name = id
	chosenTag.Value = true
	chosenTag.Parent = chosenIds

	-- Legendary per-run tracking (only using already selected meta)
	if chosenMeta.rarity == "Legendary" then
		local chosenLegendary = runTrack:FindFirstChild("ChosenLegendary") or Instance.new("IntValue")
		chosenLegendary.Name = "ChosenLegendary"
		chosenLegendary.Parent = runTrack
		chosenLegendary.Value = (chosenLegendary.Value or 0) + 1
		local perCharFolder = runTrack:FindFirstChild("LegendaryPerChar") or Instance.new("Folder")
		perCharFolder.Name = "LegendaryPerChar"
		perCharFolder.Parent = runTrack
		local tag = perCharFolder:FindFirstChild(chosenMeta.sourceChar) or Instance.new("BoolValue")
		tag.Name = chosenMeta.sourceChar
		tag.Parent = perCharFolder
		tag.Value = true
	end

	-- Determine if this card is an existing card being leveled and pass the new level
	local runTrack = player:FindFirstChild("RunTrack") or Instance.new("Folder")
	runTrack.Name = "RunTrack"
	runTrack.Parent = player
	local existingFolder = runTrack:FindFirstChild(chosenMeta.id)
	local currentLevelParam = nil
	if existingFolder then
		local lvlNV = existingFolder:FindFirstChild("Level")
		if lvlNV and lvlNV:IsA("IntValue") then
			-- intent: when choosing a card that already exists, apply as level-up to (existing + 1)
			currentLevelParam = lvlNV.Value + 1
		end
	end
	-- Apply the chosen card effects (pass currentLevel when leveling existing card)
	if currentLevelParam then
		CardDispatcher.ApplyCard(player, chosenMeta, currentLevelParam)
	else
		CardDispatcher.ApplyCard(player, chosenMeta)
	end

	-- Reaplicar stats após aplicar carta (caso aumente Health / HealthPercent etc.)
	local items = EquippedItemsModule:GetEquipped(player)
	local chars = CharactersModule:GetEquipped(player)
	-- Reapply imediatamente
	pcall(function() ApplyStatsModule:Apply(player, items, chars) end)
	-- Reapply pequeno delay para assegurar NumberValues criadas pela carta já existem
	task.defer(function()
		local items2 = EquippedItemsModule:GetEquipped(player)
		local chars2 = CharactersModule:GetEquipped(player)
		pcall(function() ApplyStatsModule:Apply(player, items2, chars2) end)
	end)
	
	-- Check if there are more pending level ups and offer next card
	if (PendingLevelUps[player] or 0) > 0 then
		task.delay(0.5, function()
			if player and player:IsDescendantOf(game.Players) then
				offerCardsToPlayer(player)
			end
		end)
	end
end)

-- Allow a single player to exit early and receive accumulated XP (no bonus/rewards)
AbortRunRE.OnServerEvent:Connect(function(player)
	if not player or not player:IsDescendantOf(game.Players) then return end
	-- Do not end the whole run; compute a per-player RunResult and teleport back if ReturnPlaceId is present
	local function buildRunResultFor(plr)
		local runResult = { Win = false }
		local bonusMultiplier = 1 -- no bonus on abort
		local runAccum = plr:FindFirstChild("RunAccum")
		local cxp = runAccum and runAccum:FindFirstChild("CharacterXP")
		local axp = runAccum and runAccum:FindFirstChild("AccountXP")
		-- Validate instance ids
		local validInstances = {}
		local instancesFolder = plr:FindFirstChild("CharacterInstances")
		if instancesFolder then
			for _, inst in ipairs(instancesFolder:GetChildren()) do
				validInstances[inst.Name] = true
			end
		end
		local charXPMap = {}
		if cxp then
			for _, nv in ipairs(cxp:GetChildren()) do
				if nv:IsA("NumberValue") then
					local key = nv.Name
					if validInstances[key] then
						local total = math.floor((nv.Value or 0) * bonusMultiplier + 0.5)
						if total > 0 then charXPMap[key] = total end
					end
				end
			end
		end
		runResult.CharacterXP = next(charXPMap) and charXPMap or nil
		local totalAccountXP = 0
		if axp and axp:IsA("NumberValue") and axp.Value > 0 then
			totalAccountXP = math.floor(axp.Value * bonusMultiplier + 0.5)
		end
		runResult.AccountXP = totalAccountXP
		-- Rewards are zero on abort
		runResult.Rewards = { Gold = 0, Gems = 0, Items = {} }
		-- Story context (if available)
		local storyMapId = ReplicatedStorage:GetAttribute("StoryMapId")
		local storyLevel = tonumber(ReplicatedStorage:GetAttribute("StoryLevel")) or nil
		if storyMapId and storyLevel then
			runResult.Story = { MapId = storyMapId, Level = storyLevel }
		end
		return runResult
	end
	local runResult = buildRunResultFor(player)
	-- Cache JSON so client can inspect in Victory/Abort UI
	pcall(function()
		local ra = player:FindFirstChild("RunAccum") or Instance.new("Folder")
		ra.Name = "RunAccum"; if not ra.Parent then ra.Parent = player end
		local last = ra:FindFirstChild("LastRunResultJSON") or Instance.new("StringValue")
		last.Name = "LastRunResultJSON"; if not last.Parent then last.Parent = ra end
		last.Value = HttpService:JSONEncode(runResult)
	end)
	-- Teleport back to lobby using ReturnPlaceId from join TeleportData
	local returnPlaceId
	pcall(function()
		local joinData = player:GetJoinData()
		local td = joinData and joinData.TeleportData
		returnPlaceId = td and tonumber(td.ReturnPlaceId) or nil
	end)
	if returnPlaceId and returnPlaceId > 0 then
		-- Use helper that attempts to save before teleporting
		local ok, err = pcall(function()
			return saveThenTeleportToReturnPlace(returnPlaceId, player, runResult)
		end)
		if not ok or not err then
			warn("[AbortRun] saveThenTeleportToReturnPlace failed:", err)
		end
	else
		warn("[AbortRun] No ReturnPlaceId for", player.Name, "- cannot teleport back; XP will not persist")
	end
end)

-- =============================
-- Post-run choice: play again or return to lobby
-- =============================
local function getOrCreatePending(plr)
	local ra = plr:FindFirstChild("RunAccum")
	if not ra then ra = Instance.new("Folder") ra.Name = "RunAccum" ra.Parent = plr end
	local pend = ra:FindFirstChild("PendingTotals")
	if not pend then pend = Instance.new("Folder") pend.Name = "PendingTotals" pend.Parent = ra end
	local acc = pend:FindFirstChild("AccountXP") or Instance.new("NumberValue"); acc.Name = "AccountXP"; acc.Parent = pend
	local cxp = pend:FindFirstChild("CharacterXP") or Instance.new("Folder"); cxp.Name = "CharacterXP"; cxp.Parent = pend
	local rew = pend:FindFirstChild("Rewards") or Instance.new("Folder"); rew.Name = "Rewards"; rew.Parent = pend
	local gold = rew:FindFirstChild("Gold") or Instance.new("NumberValue"); gold.Name = "Gold"; gold.Parent = rew
	local gems = rew:FindFirstChild("Gems") or Instance.new("NumberValue"); gems.Name = "Gems"; gems.Parent = rew
	local items = rew:FindFirstChild("Items") or Instance.new("Folder"); items.Name = "Items"; items.Parent = rew
	return pend
end

addToPending = function(plr, runResult)
	if type(runResult) ~= "table" then return end
	local pend = getOrCreatePending(plr)
	local acc = pend:FindFirstChild("AccountXP"); acc.Value = acc.Value + (tonumber(runResult.AccountXP) or 0)
	local cxp = pend:FindFirstChild("CharacterXP")
	if type(runResult.CharacterXP) == "table" then
		for id, amt in pairs(runResult.CharacterXP) do
			local nv = cxp:FindFirstChild(id) or Instance.new("NumberValue"); nv.Name = tostring(id); nv.Parent = cxp; nv.Value = (nv.Value or 0) + (tonumber(amt) or 0)
		end
	end
	local rew = pend:FindFirstChild("Rewards")
	rew.Gold.Value = rew.Gold.Value + (tonumber(runResult.Rewards and runResult.Rewards.Gold) or 0)
	rew.Gems.Value = rew.Gems.Value + (tonumber(runResult.Rewards and runResult.Rewards.Gems) or 0)
	local items = rew:FindFirstChild("Items")
	if runResult.Rewards and type(runResult.Rewards.Items) == "table" then
		for _, it in ipairs(runResult.Rewards.Items) do
			local id = tostring(it.Id or ""); local q = tonumber(it.Quantity) or 0
			if id ~= "" and q > 0 then
				local iv = items:FindFirstChild(id) or Instance.new("IntValue"); iv.Name = id; iv.Parent = items; iv.Value = (iv.Value or 0) + q
			end
		end
	end
	return pend
end

buildAggregatedRunResult = function(plr)
	local ra = plr:FindFirstChild("RunAccum")
	local lastJson = ra and ra:FindFirstChild("LastRunResultJSON")
	local last = nil
	if lastJson and lastJson.Value ~= "" then
		local ok, t = pcall(function() return HttpService:JSONDecode(lastJson.Value) end)
		if ok and type(t) == "table" then last = t end
	end
	local pend = getOrCreatePending(plr)
	-- Start with zeros; prefer Win flag from global attribute if available
	local attrWin = nil
	pcall(function()
		local w = ReplicatedStorage:GetAttribute("RunWin")
		if type(w) == "boolean" then attrWin = w end
	end)
	local result = { Win = (attrWin ~= nil) and attrWin or (last and last.Win or false), AccountXP = 0, CharacterXP = {}, Rewards = { Gold = 0, Gems = 0, Items = {} } }

	-- 0) Merge live accumulated values from RunAccum (AccountXP, CharacterXP, and Rewards) so a single run return applies XP and milestone rewards
	do
		local axp = ra and ra:FindFirstChild("AccountXP")
		if axp and axp:IsA("NumberValue") and (tonumber(axp.Value) or 0) > 0 then
			result.AccountXP = result.AccountXP + (tonumber(axp.Value) or 0)
		end
		local cxp = ra and ra:FindFirstChild("CharacterXP")
		if cxp then
			-- Only include keys that map to existing CharacterInstances when possible; otherwise include as-is
			local validInstances = {}
			local instFolder = plr:FindFirstChild("CharacterInstances")
			if instFolder then
				for _, inst in ipairs(instFolder:GetChildren()) do validInstances[inst.Name] = true end
			end
			for _, nv in ipairs(cxp:GetChildren()) do
				if nv:IsA("NumberValue") and (tonumber(nv.Value) or 0) > 0 then
					local key = nv.Name
					-- include regardless; lobby will fallback by template if needed
					result.CharacterXP[key] = (result.CharacterXP[key] or 0) + (tonumber(nv.Value) or 0)
				end
			end
		end
		-- Merge infinite mode milestone rewards stored directly in RunAccum/Rewards
		local runRew = ra and ra:FindFirstChild("Rewards")
		if runRew then
			local g = runRew:FindFirstChild("Gold")
			if g then result.Rewards.Gold = result.Rewards.Gold + (tonumber(g.Value) or 0) end
			local ge = runRew:FindFirstChild("Gems")
			if ge then result.Rewards.Gems = result.Rewards.Gems + (tonumber(ge.Value) or 0) end
			local itemsFolder = runRew:FindFirstChild("Items")
			if itemsFolder then
				for _, iv in ipairs(itemsFolder:GetChildren()) do
					local id = tostring(iv.Name); local q = tonumber(iv.Value) or 0
					if id ~= "" and q > 0 then
						table.insert(result.Rewards.Items, { Id = id, Quantity = q })
					end
				end
			end
			-- Also merge Characters (XP chars) from RunAccum/Rewards/Characters if present
			-- These go into result.Rewards.Characters (separate from Items) so lobby calls CharacterService:AddCharacter
			local charsVal = runRew:FindFirstChild("Characters")
			if charsVal and charsVal:IsA("StringValue") and charsVal.Value ~= "" then
				local okC, chars = pcall(function() return HttpService:JSONDecode(charsVal.Value) end)
				if okC and type(chars) == "table" and #chars > 0 then
					result.Rewards.Characters = result.Rewards.Characters or {}
					for _, charId in ipairs(chars) do
						table.insert(result.Rewards.Characters, tostring(charId))
					end
				end
			end
		end
	end

	-- 0.25) Fallback: if no CharacterXP/AccountXP captured live, derive from wavesConfig.CharacterXP and waves completed
	-- Reason: some maps may not fire OnWaveCleared consistently; in that case we still grant XP based on waves reached
	if (not result.CharacterXP) or (type(result.CharacterXP) == "table" and next(result.CharacterXP) == nil) then
		local cfg = wavesConfig and wavesConfig.CharacterXP
		if cfg and (tonumber(cfg.BasePerWave) or 0) > 0 then
			-- Determine waves completed: if win, use total waves; else use ReplicatedStorage.CurrentWave
			local wavesDone = 0
			pcall(function()
				local total = (wavesConfig and wavesConfig.Waves and #wavesConfig.Waves) or 0
				local current = tonumber(ReplicatedStorage:GetAttribute("CurrentWave")) or 0
				if result.Win == true and total > 0 then wavesDone = total else wavesDone = math.max(0, math.min(current, total)) end
			end)
			if wavesDone > 0 then
				local perWaveBase = tonumber(cfg.BasePerWave) or 0
				local perWaveGrowth = tonumber(cfg.GrowthPerWave) or 0
				local perChar = 0
				for i = 1, wavesDone do
					perChar += math.floor(perWaveBase + perWaveGrowth * (i - 1))
				end
				if perChar > 0 then
					-- Grant to all equipped instances (from CharacterInstances/Equipped slots)
					local equipped = CharactersModule:GetEquipped(plr) or {}
					result.CharacterXP = result.CharacterXP or {}
					for _, info in ipairs(equipped) do
						local key = info.InstanceId or info.Name
						if key then
							result.CharacterXP[key] = (result.CharacterXP[key] or 0) + perChar
						end
					end
					-- AccountXP equals perChar times number of equipped
					result.AccountXP = result.AccountXP + (perChar * #equipped)
				end
			end
		end
		-- Normalize empty back to nil if still empty (guard type)
		if type(result.CharacterXP) == "table" and next(result.CharacterXP) == nil then
			result.CharacterXP = nil
		end
	end

	-- 0.5) Compute rewards from Map.lua config (Drops.FirstClear / Drops.Repeat / GuaranteedItemsPerRun)
	do
		-- Helper to load current story map config by Id
		local function getMapConfigById(mapId)
			local RS = game:GetService("ReplicatedStorage")
			local Shared = RS:FindFirstChild("Shared")
			local Maps = Shared and Shared:FindFirstChild("Maps")
			local Story = Maps and Maps:FindFirstChild("Story")
			if not Story then return nil end
			for _, folder in ipairs(Story:GetChildren()) do
				if folder:IsA("Folder") then
					local mod = folder:FindFirstChild("Map")
					if mod and mod:IsA("ModuleScript") then
						local ok, mapTbl = pcall(function() return require(mod) end)
						if ok and type(mapTbl) == "table" and tostring(mapTbl.Id) == tostring(mapId) then
							return mapTbl
						end
					end
				end
			end
			return nil
		end

		-- Always grant guaranteed items if configured
		local sid = ReplicatedStorage:GetAttribute("StoryMapId")
		local lvl = tonumber(ReplicatedStorage:GetAttribute("StoryLevel")) or nil
		local mapCfg = sid and getMapConfigById(sid) or nil
		if mapCfg and type(mapCfg.Drops) == "table" then
			local drops = mapCfg.Drops
			-- Guaranteed items every run
			if type(drops.GuaranteedItemsPerRun) == "table" then
				for _, it in ipairs(drops.GuaranteedItemsPerRun) do
					local id = tostring(it.Id or "")
					local q = tonumber(it.Quantity) or 0
					if id ~= "" and q > 0 then
						table.insert(result.Rewards.Items, { Id = id, Quantity = q })
					end
				end
			end
			-- Only compute FirstClear/Repeat on win
			if result.Win == true then
				local gaveFirst = false
				local canCheckFirst = DS_GLOBAL and type(DS_GLOBAL.hasCompletedLevel) == "function" and sid and lvl
				if canCheckFirst then
					local ok, already = pcall(function()
						return DS_GLOBAL.hasCompletedLevel(plr.UserId, tostring(sid), tonumber(lvl))
					end)
					local isFirst = (ok and not already) or false
					if isFirst and type(drops.FirstClear) == "table" then
						result.Rewards.Gold = (tonumber(result.Rewards.Gold) or 0) + (tonumber(drops.FirstClear.Gold) or 0)
						result.Rewards.Gems = (tonumber(result.Rewards.Gems) or 0) + (tonumber(drops.FirstClear.Gems) or 0)
						gaveFirst = true
					end
				end
				if (not gaveFirst) and type(drops.Repeat) == "table" then
					result.Rewards.Gold = (tonumber(result.Rewards.Gold) or 0) + (tonumber(drops.Repeat.Gold) or 0)
					result.Rewards.Gems = (tonumber(result.Rewards.Gems) or 0) + (tonumber(drops.Repeat.Gems) or 0)
				end
			end
			-- Minimal telemetry: print reward summary once per aggregation
			local g = tonumber(result.Rewards.Gold) or 0
			local ge = tonumber(result.Rewards.Gems) or 0
			local ic = (type(result.Rewards.Items) == "table") and #result.Rewards.Items or 0
			print(string.format("[Rewards] Map=%s L=%s Win=%s -> Gold=%d Gems=%d Items=%d", tostring(sid), tostring(lvl), tostring(result.Win), g, ge, ic))
		end
	end
	-- 1) Merge pending totals (from Play Again / Next Level accumulation)
	do
		-- Ensure table exists even if earlier fallback normalized it to nil
		result.CharacterXP = result.CharacterXP or {}
		local acc = pend:FindFirstChild("AccountXP"); result.AccountXP = result.AccountXP + (acc and acc.Value or 0)
		local cxp = pend:FindFirstChild("CharacterXP")
		if cxp then for _, nv in ipairs(cxp:GetChildren()) do result.CharacterXP[nv.Name] = (result.CharacterXP[nv.Name] or 0) + nv.Value end end
		local rew = pend:FindFirstChild("Rewards")
		if rew then
			result.Rewards.Gold = result.Rewards.Gold + ((rew:FindFirstChild("Gold") and rew.Gold.Value) or 0)
			result.Rewards.Gems = result.Rewards.Gems + ((rew:FindFirstChild("Gems") and rew.Gems.Value) or 0)
			local items = rew:FindFirstChild("Items")
			if items then
				for _, iv in ipairs(items:GetChildren()) do
					result.Rewards.Items[#result.Rewards.Items+1] = { Id = iv.Name, Quantity = iv.Value }
				end
			end
		end
	end

	-- 2) Merge last run JSON snapshot on top (if any persisted previously)
	if last then
		-- Ensure CharacterXP table exists before merging
		result.CharacterXP = result.CharacterXP or {}
		result.AccountXP = result.AccountXP + (tonumber(last.AccountXP) or 0)
		if type(last.CharacterXP) == "table" then
			for id, amt in pairs(last.CharacterXP) do
				result.CharacterXP[id] = (result.CharacterXP[id] or 0) + (tonumber(amt) or 0)
			end
		end
		if last.Rewards then
			result.Rewards.Gold = result.Rewards.Gold + (tonumber(last.Rewards.Gold) or 0)
			result.Rewards.Gems = result.Rewards.Gems + (tonumber(last.Rewards.Gems) or 0)
			if type(last.Rewards.Items) == "table" then
				-- Merge into existing list by id
				local idx = {}
				for i, entry in ipairs(result.Rewards.Items) do idx[entry.Id] = i end
				for _, it in ipairs(last.Rewards.Items) do
					local id = tostring(it.Id or ""); local q = tonumber(it.Quantity) or 0
					if id ~= "" and q > 0 then
						local i = idx[id]
						if i then result.Rewards.Items[i].Quantity = result.Rewards.Items[i].Quantity + q
						else result.Rewards.Items[#result.Rewards.Items+1] = { Id = id, Quantity = q }; idx[id] = #result.Rewards.Items end
					end
				end
			end
		end
		if last.Story then result.Story = last.Story end
		result.Win = (last.Win or result.Win)
	end

	-- 3) If Story context wasn't set yet, try to source from attributes captured on join
	if not result.Story then
		pcall(function()
			local sid = ReplicatedStorage:GetAttribute("StoryMapId")
			local lvl = tonumber(ReplicatedStorage:GetAttribute("StoryLevel")) or nil
			if sid and lvl then
				result.Story = { MapId = tostring(sid), Level = lvl }
			end
		end)
	end

	-- 3.5) Victory bonus: apply 1.5x multiplier to XP when Win=true
	if result.Win == true then
		local function mulRound(n, f)
			return math.floor((tonumber(n) or 0) * f + 0.5)
		end
		result.AccountXP = mulRound(result.AccountXP, 1.5)
		if type(result.CharacterXP) == "table" then
			for k, v in pairs(result.CharacterXP) do
				result.CharacterXP[k] = mulRound(v, 1.5)
			end
		end
	end
	
	-- 3.6) INFINITE MODE: Add infinite mode data
	pcall(function()
		local currentWave = tonumber(ReplicatedStorage:GetAttribute("CurrentWave")) or 0
		if currentWave > 0 then
			result.Infinite = result.Infinite or {}
			result.Infinite.HighestWave = currentWave
			
			-- Get milestones reached from player attribute
			local milestonesStr = plr:GetAttribute("InfiniteMilestonesReached") or ""
			if milestonesStr ~= "" then
				local milestones = {}
				for num in string.gmatch(milestonesStr, "%d+") do
					table.insert(milestones, tonumber(num))
				end
				result.Infinite.MilestonesReached = milestones
			end
		end
	end)

	-- 4) Add TotalDamage from RunTrack for missions tracking
	local runTrack = plr:FindFirstChild("RunTrack")
	if runTrack then
		local dmgVal = runTrack:FindFirstChild("Damage")
		if dmgVal and (dmgVal:IsA("NumberValue") or dmgVal:IsA("IntValue")) then
			result.TotalDamage = tonumber(dmgVal.Value) or 0
		end
	end

	-- Normalize empty maps to nil (guard when CharacterXP is nil)
	if type(result.CharacterXP) == "table" then
		if next(result.CharacterXP) == nil then
			result.CharacterXP = nil
		end
	end
	if #result.Rewards.Items == 0 then result.Rewards.Items = {} end
	return result
end

local function clearPending(plr)
	local ra = plr:FindFirstChild("RunAccum"); if not ra then return end
	local pend = ra:FindFirstChild("PendingTotals"); if pend then pend:Destroy() end
	local last = ra:FindFirstChild("LastRunResultJSON"); if last then last.Value = "" end
end

RunPlayAgainRE.OnServerEvent:Connect(function(player)
	if not player then return end
	local ra = player:FindFirstChild("RunAccum"); if not ra then
		pcall(function()
			local ev = Remotes:FindFirstChild("RunPlayAgainResult")
			if ev and ev:IsA("RemoteEvent") then ev:FireClient(player, { success = false, reason = "no_runaccum", message = "RunAccum not found on server." }) end
		end)
		return
	end
	print(string.format("[RunPlayAgain] request from %s (runEnded=%s)", tostring(player and player.Name), tostring(runEnded)))
	-- Aggregate last run result into pending (if present), but don't require it.
	local consumed = false
	do
		local lastJson = ra and ra:FindFirstChild("LastRunResultJSON")
		if lastJson and lastJson.Value ~= "" then
			local ok, last = pcall(function() return HttpService:JSONDecode(lastJson.Value) end)
			if ok and type(last) == "table" then addToPending(player, last) end
			lastJson.Value = "" -- consumed
			consumed = true
		end
		player:SetAttribute("AwaitingRunChoice", false)
	end
	-- Provide immediate feedback to client about the request
	pcall(function()
		local ev = Remotes:FindFirstChild("RunPlayAgainResult")
		if ev and ev:IsA("RemoteEvent") then
			ev:FireClient(player, { success = (runEnded == true), consumed = consumed, runEnded = runEnded, message = runEnded and "A reiniciar o run..." or "Run ainda não terminou." })
		end
	end)
	if runEnded then
		-- Try to create a fresh private server for the new run so players join a clean instance.
		local currentPlace = tonumber(game.PlaceId)
		local sid = ReplicatedStorage:GetAttribute("StoryMapId")
		local lvl = tonumber(ReplicatedStorage:GetAttribute("StoryLevel")) or 1
		local payload = { RunAgain = true }
		if sid then payload.Story = { MapId = tostring(sid), Level = lvl } end
		local ok, err = teleportToReservedServer(currentPlace, { player }, payload)
		if not ok then
			print("[RunPlayAgain] teleport reserved server failed:", tostring(err))
			local ev = Remotes:FindFirstChild("RunPlayAgainResult")
			if ev and ev:IsA("RemoteEvent") then
				ev:FireClient(player, { success = false, reason = "teleport_failed", message = "Não foi possível criar servidor privado. Tenta novamente." })
			end
		end
	end
end)

RunReturnToLobbyRE.OnServerEvent:Connect(function(player)
	if not player then return end
	-- Ensure run is marked ended (idempotent — endRun guards against double-call)
	if not runEnded then endRun(false) end
	local aggregated = buildAggregatedRunResult(player)
	-- Cache JSON for client-visible verification prior to teleport
	pcall(function()
		local ra = player:FindFirstChild("RunAccum") or Instance.new("Folder")
		ra.Name = "RunAccum"; if not ra.Parent then ra.Parent = player end
		local last = ra:FindFirstChild("LastRunResultJSON") or Instance.new("StringValue")
		last.Name = "LastRunResultJSON"; if not last.Parent then last.Parent = ra end
		last.Value = HttpService:JSONEncode(aggregated)
	end)
	-- Use helper with auto-resolved lobby place id; no need to rely on TeleportData
	do
		-- Use helper that attempts to save before teleporting
		local ok, err = pcall(function()
			return saveThenTeleportToReturnPlace(nil, player, aggregated)
		end)
		if not ok or not err then
			warn("[RunReturnToLobby] saveThenTeleportToReturnPlace failed:", err)
		end
		clearPending(player)
	end
end)

-- =============================
-- Next Level removed: Infinite mode is endless, no level progression
-- =============================

-- =============================
-- Next Level removed: Infinite mode is endless, no level progression
-- =============================

-- Fallback: if no choice is made within 20s after endRun, auto-teleport back with aggregated result
task.spawn(function()
	while true do
		task.wait(1)
		if runEnded then
			task.wait(20)
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr:GetAttribute("AwaitingRunChoice") then
					local aggregated = buildAggregatedRunResult(plr)
					do
						local ok, err = pcall(function()
							return saveThenTeleportToReturnPlace(nil, plr, aggregated)
						end)
						if not ok or not err then
							warn("[Script][auto-teleport] saveThenTeleportToReturnPlace failed:", err)
						end
						clearPending(plr)
					end
				end
			end
			break
		end
	end
end)
-- Hook to Leveling: when levels are gained, offer cards (for now call manually on AddXP response)
-- You can integrate this into Leveling:AddXP returns >0
-- Example (already printed on level up): in OnEnemyDied, after gained>0, call offerCardsToPlayer(killer)

