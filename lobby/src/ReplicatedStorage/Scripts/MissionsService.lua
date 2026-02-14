-- MissionsService
-- Gerencia o progresso e recompensas das missões

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Scripts = ReplicatedStorage:WaitForChild("Scripts")

local MissionsCatalog = require(Scripts:WaitForChild("MissionsCatalog"))

local MissionsService = {}

-- =============================
-- Profile Migration/Init
-- =============================

-- Garante que o perfil tem a estrutura de Missions (migração de perfis antigos)
function MissionsService:EnsureMissionsStructure(profile)
	if not profile then return false end
	
	-- Se já tem a estrutura, retornar
	if profile.Missions and profile.Missions.Progress and profile.Missions.InfiniteTiersClaimed then
		return true
	end
	
	-- Criar estrutura de Missions se não existir
	profile.Missions = profile.Missions or {}
	profile.Missions.Progress = profile.Missions.Progress or {
		StoryLevelsCompleted = 0,
		TotalDamageDealt = 0,
		HighestInfiniteWave = 0,
		TotalEvolves = 0,
		TotalSummons = 0,
	}
	profile.Missions.InfiniteTiersClaimed = profile.Missions.InfiniteTiersClaimed or {}
	
	return true
end

-- =============================
-- Dynamic Mission Helpers
-- =============================

-- Ordem dos mapas de story (adiciona conforme crias novos mapas)
local STORY_MAP_ORDER = {
	"village",      -- 4 levels: 1, 2, 3, 4 (start here by design)
	"soul_city",    -- 4 levels
	"namek",        -- 4 levels
	"bleach_lvl",   -- 4 levels
	-- Adiciona novos mapas aqui conforme crias
}

-- Detecta o próximo story level que o player ainda não completou
function MissionsService:GetNextStoryLevel(profile)
	if not profile or not profile.Story then return nil end
	
	for _, mapID in ipairs(STORY_MAP_ORDER) do
		local mapData = profile.Story.Maps[mapID]
		
		if not mapData then
			-- Mapa nunca foi tocado - level 1 deste mapa
			return { MapID = mapID, Level = 1, MapName = mapID }
		end
		
		-- Verificar levels 1-4 (assumindo 4 levels por mapa)
		for level = 1, 4 do
			if not mapData.LevelsCompleted or not mapData.LevelsCompleted[level] then
				return { MapID = mapID, Level = level, MapName = mapID }
			end
		end
	end
	
	-- Todos os levels completados
	return nil
end

-- Detecta o próximo mapa que o player ainda não completou totalmente (todos os 4 levels)
function MissionsService:GetNextMapToComplete(profile)
	if not profile or not profile.Story then return nil end
	
	for _, mapID in ipairs(STORY_MAP_ORDER) do
		local mapData = profile.Story.Maps[mapID]
		
		if not mapData then
			-- Mapa nunca tocado
			return { MapID = mapID, MapName = mapID }
		end
		
		-- Verificar se todos os 4 levels foram completados
		local allLevelsComplete = true
		for level = 1, 4 do
			if not mapData.LevelsCompleted or not mapData.LevelsCompleted[level] then
				allLevelsComplete = false
				break
			end
		end
		
		if not allLevelsComplete then
			return { MapID = mapID, MapName = mapID }
		end
	end
	
	-- Todos os mapas completados
	return nil
end

-- =============================
-- Progress Tracking Functions
-- =============================

-- Marca um story level como completado (chamado quando player completa um level)
function MissionsService:CompleteStoryLevel(profile, mapID, level)
	if not self:EnsureMissionsStructure(profile) then return end
	if not profile.Story then return end
	
	-- Initializar mapa se não existe
	if not profile.Story.Maps[mapID] then
		profile.Story.Maps[mapID] = {
			MaxUnlockedLevel = 0,
			LevelsCompleted = {}
		}
	end
	
	-- Marcar level como completado
	profile.Story.Maps[mapID].LevelsCompleted[level] = true
    
	-- NOTE: Don't advance the claimed story-level counter here.
	-- The mission objective should only advance when the player claims the reward.
	print(string.format("[Missions] Story level completado (unclaimed): %s - Level %d", mapID, level))
end

-- Helper: build ordered list of story levels (linear index -> {MapID, Level})
local function buildOrderedStoryLevels()
	local ordered = {}
	for _, mapID in ipairs(STORY_MAP_ORDER) do
		for lvl = 1, 4 do
			table.insert(ordered, { MapID = mapID, Level = lvl, MapName = mapID })
		end
	end
	return ordered
end

-- Incrementa dano total causado
function MissionsService:AddDamageDealt(profile, damage)
	if not self:EnsureMissionsStructure(profile) then return end
	
	profile.Missions.Progress.TotalDamageDealt = (profile.Missions.Progress.TotalDamageDealt or 0) + damage
end

-- Atualiza highest wave no infinite mode
function MissionsService:UpdateInfiniteWave(profile, wave)
	if not self:EnsureMissionsStructure(profile) then return end
	
	local currentMax = profile.Missions.Progress.HighestInfiniteWave or 0
	profile.Missions.Progress.HighestInfiniteWave = math.max(currentMax, wave)
end

-- Incrementa total de evolves
function MissionsService:IncrementEvolves(profile)
	if not self:EnsureMissionsStructure(profile) then return end
	
	profile.Missions.Progress.TotalEvolves = (profile.Missions.Progress.TotalEvolves or 0) + 1
end

-- Incrementa total de summons
-- Incrementa total de summons (aceita amount opcional)
function MissionsService:IncrementSummons(profile, amount)
	if not self:EnsureMissionsStructure(profile) then return end
	amount = tonumber(amount) or 1
	if amount <= 0 then return end

	profile.Missions.Progress.TotalSummons = (profile.Missions.Progress.TotalSummons or 0) + amount
end

-- =============================
-- Reward Claiming
-- =============================

-- Resgata reward de uma missão
function MissionsService:ClaimMissionReward(profile, missionID)
	if not self:EnsureMissionsStructure(profile) then 
		return false, "Profile not ready"
	end
	
	local mission = MissionsCatalog:GetMission(missionID)
	if not mission then 
		return false, "Mission not found"
	end
	
	-- Missões infinitas têm lógica diferente
	if mission.IsInfinite then
		return self:ClaimInfiniteMissionReward(profile, missionID)
	end
	
	-- Missões dinâmicas (story/maps) são resgatadas sempre que o objetivo é completado
	if mission.IsDynamic then
		return self:ClaimDynamicMissionReward(profile, missionID)
	end
	
	return false, "Unknown mission type"
end

-- Resgata reward de missão dinâmica (story level / map completion)
function MissionsService:ClaimDynamicMissionReward(profile, missionID)
	local mission = MissionsCatalog:GetMission(missionID)
	if not mission or not mission.IsDynamic then
		return false, "Invalid dynamic mission"
	end
	
	if mission.Type == MissionsCatalog.MissionTypes.NEXT_STORY_LEVEL then
		-- Claiming should consume the next claimed-but-unredeemed story level.
		if not profile or not profile.Story then return false, "Profile missing story data" end

		local claimed = (profile.Missions and profile.Missions.Progress and profile.Missions.Progress.StoryLevelsCompleted) or 0
		local ordered = buildOrderedStoryLevels()
		local targetIndex = claimed + 1

		if targetIndex > #ordered then
			return false, "All story levels completed!"
		end

		local target = ordered[targetIndex]
		local mapData = profile.Story.Maps[target.MapID]
		if not mapData or not mapData.LevelsCompleted or not mapData.LevelsCompleted[target.Level] then
			return false, "That level hasn't been completed yet"
		end

		-- Give reward and advance the claimed counter
		profile.Account.Gems = (profile.Account.Gems or 0) + mission.Reward.Gems
		profile.Missions.Progress.StoryLevelsCompleted = claimed + 1

		-- Determine next objective for message
		local nextMsg = "All story levels completed!"
		if profile.Missions.Progress.StoryLevelsCompleted < #ordered then
			local nxt = ordered[profile.Missions.Progress.StoryLevelsCompleted + 1]
			nextMsg = string.format("Next: %s Level %d", nxt.MapID, nxt.Level)
		end

		return true, string.format("+%d Gems! %s", mission.Reward.Gems, nextMsg)
		
	elseif mission.Type == MissionsCatalog.MissionTypes.NEXT_MAP then
		local nextMap = self:GetNextMapToComplete(profile)
		
		if not nextMap then
			return false, "All maps completed!"
		end
		
		-- Dar reward pelo último mapa completado
		profile.Account.Gems = (profile.Account.Gems or 0) + mission.Reward.Gems
		
		return true, string.format("+%d Gems! Next: %s", mission.Reward.Gems, nextMap.MapName)
	end
	
	return false, "Unknown dynamic mission type"
end

-- Resgata reward de missão infinita (por tiers)
function MissionsService:ClaimInfiniteMissionReward(profile, missionID)
	local mission = MissionsCatalog:GetMission(missionID)
	if not mission or not mission.IsInfinite then
		return false, "Invalid infinite mission"
	end
	
	-- Get current progress based on mission type
	local currentProgress = 0
	if mission.Type == MissionsCatalog.MissionTypes.TOTAL_DAMAGE then
		currentProgress = profile.Missions.Progress.TotalDamageDealt or 0
	elseif mission.Type == MissionsCatalog.MissionTypes.INFINITE_WAVES then
		currentProgress = profile.Missions.Progress.HighestInfiniteWave or 0
	elseif mission.Type == MissionsCatalog.MissionTypes.EVOLVES_DONE then
		currentProgress = profile.Missions.Progress.TotalEvolves or 0
	elseif mission.Type == MissionsCatalog.MissionTypes.SUMMONS_DONE then
		currentProgress = profile.Missions.Progress.TotalSummons or 0
	end
	
	-- Calcular tier/milestone com base no tipo de missão
	local currentTier
	if mission.HasScalingDifficulty then
		currentTier = MissionsCatalog:CalculateMilestoneFromDamage(mission, currentProgress)
	else
		currentTier = math.floor(currentProgress / mission.Requirement)
	end
	
	if currentTier <= 0 then
		return false, "No tier reached yet"
	end
	
	-- Verificar último tier resgatado
	local lastClaimedTier = profile.Missions.InfiniteTiersClaimed[missionID] or 0
	
	if currentTier <= lastClaimedTier then
		return false, "No new tiers to claim"
	end
	
	-- Calcular gems usando a função do catalog (suporta scaling)
	local gemsToGive = MissionsCatalog:CalculateInfiniteReward(missionID, currentProgress, lastClaimedTier)
	local tiersToReward = currentTier - lastClaimedTier
	
	-- Aplicar rewards
	profile.Account.Gems = (profile.Account.Gems or 0) + gemsToGive
	
	-- Atualizar último tier resgatado
	profile.Missions.InfiniteTiersClaimed[missionID] = currentTier
	
	local tierWord = mission.HasScalingDifficulty and "milestone" or "tier"
	return true, string.format("Claimed %d %s(s) - %d Gems!", tiersToReward, tierWord, gemsToGive)
end

-- =============================
-- Query Functions
-- =============================

-- Get all available missions with their status
function MissionsService:GetAllMissionsStatus(profile)
	if not self:EnsureMissionsStructure(profile) then 
		return {}
	end
	
	local result = {}
	
	for _, mission in ipairs(MissionsCatalog.Missions) do
		local status = {
			Mission = mission,
			CanClaim = false,
			CurrentTier = 0,
			Progress = 0,
			Requirement = mission.Requirement or 0,
		}
		
		-- Missões Dinâmicas (Story/Maps)
		if mission.IsDynamic then
			if mission.Type == MissionsCatalog.MissionTypes.NEXT_STORY_LEVEL then
				-- Use claimed-count sequencing so the objective doesn't advance until claimed
				local claimed = (profile.Missions and profile.Missions.Progress and profile.Missions.Progress.StoryLevelsCompleted) or 0
				local ordered = buildOrderedStoryLevels()
				local nextIndex = claimed + 1
				if nextIndex > #ordered then
					status.DynamicDescription = "All story levels completed!"
					status.CanClaim = false
					status.IsFullyCompleted = true
				else
					local obj = ordered[nextIndex]
					status.DynamicDescription = string.format("Complete %s - Level %d", obj.MapID, obj.Level)
					status.CurrentObjective = obj
					-- Can claim only if the actual level has been completed
					local mapData = profile.Story.Maps and profile.Story.Maps[obj.MapID]
					status.CanClaim = mapData and mapData.LevelsCompleted and mapData.LevelsCompleted[obj.Level] == true
				end
				
			elseif mission.Type == MissionsCatalog.MissionTypes.NEXT_MAP then
				local nextMap = self:GetNextMapToComplete(profile)
				if nextMap then
					status.DynamicDescription = string.format("Complete all levels of %s", nextMap.MapName)
					status.CanClaim = false
status.CurrentObjective = nextMap
				else
					status.DynamicDescription = "All maps completed!"
					status.CanClaim = false
					status.IsFullyCompleted = true
				end
			end
			
		-- Missões Infinitas
		elseif mission.IsInfinite then
			if mission.Type == MissionsCatalog.MissionTypes.TOTAL_DAMAGE then
				status.Progress = profile.Missions.Progress.TotalDamageDealt or 0
			elseif mission.Type == MissionsCatalog.MissionTypes.INFINITE_WAVES then
				status.Progress = profile.Missions.Progress.HighestInfiniteWave or 0
			elseif mission.Type == MissionsCatalog.MissionTypes.EVOLVES_DONE then
				status.Progress = profile.Missions.Progress.TotalEvolves or 0
			elseif mission.Type == MissionsCatalog.MissionTypes.SUMMONS_DONE then
				status.Progress = profile.Missions.Progress.TotalSummons or 0
			end
			
			local lastClaimedTier = profile.Missions.InfiniteTiersClaimed[mission.ID] or 0
			
			-- Missões com dificuldade crescente (milestones)
			if mission.HasScalingDifficulty then
				local currentMilestone = MissionsCatalog:CalculateMilestoneFromDamage(mission, status.Progress)
				local damageForCurrentMilestone = MissionsCatalog:GetDamageForMilestone(mission, currentMilestone)
				local damageForNextMilestone = MissionsCatalog:GetDamageForMilestone(mission, currentMilestone + 1)
				
				status.CurrentTier = currentMilestone
				status.LastClaimedTier = lastClaimedTier
				status.CanClaim = currentMilestone > lastClaimedTier
				status.TiersAvailable = currentMilestone - lastClaimedTier
				status.ProgressToNextTier = status.Progress - damageForCurrentMilestone
				status.RequirementForNextTier = damageForNextMilestone - damageForCurrentMilestone
				
				-- Se tem rewards escaláveis, mostrar quanto gems daria o próximo claim
				if mission.HasScalingRewards then
					status.CurrentRewardPerMilestone = MissionsCatalog:GetRewardForDamageAmount(mission, status.Progress)
					status.NextRewardPerMilestone = MissionsCatalog:GetRewardForDamageAmount(mission, damageForNextMilestone)
				end
				
			-- Missões normais baseadas em tiers fixos
			else
				local currentTier = math.floor(status.Progress / mission.Requirement)
				status.CurrentTier = currentTier
				status.LastClaimedTier = lastClaimedTier
				status.TiersAvailable = currentTier - lastClaimedTier
				status.CanClaim = currentTier > lastClaimedTier
				-- For non-scaling infinite missions we want to show the TOTAL progress vs the NEXT milestone threshold
				-- e.g., before claim: 60/50; after claiming first 50 (claim advances LastClaimedTier) show 50/100
				status.ProgressToNextTier = status.Progress -- client falls back to using this as current value
				status.RequirementForNextTier = (lastClaimedTier + 1) * mission.Requirement
			end
		end
		
		table.insert(result, status)
	end
	
	-- Sort by order
	table.sort(result, function(a, b)
		return a.Mission.Order < b.Mission.Order
	end)
	
	return result
end

-- Get claimable missions count
function MissionsService:GetClaimableCount(profile)
	local allStatus = self:GetAllMissionsStatus(profile)
	local count = 0
	
	for _, status in ipairs(allStatus) do
		if status.CanClaim then
			count = count + 1
		end
	end
	
	return count
end

return MissionsService
