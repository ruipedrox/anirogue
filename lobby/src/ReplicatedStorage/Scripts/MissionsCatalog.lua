-- Missions Catalog
-- Define todas as missões disponíveis e suas recompensas

local MissionsCatalog = {}

-- Tipos de missões
MissionsCatalog.MissionTypes = {
	NEXT_STORY_LEVEL = "NextStoryLevel",   -- Completar o próximo level de story (dinâmica)
	NEXT_MAP = "NextMap",                  -- Completar o próximo mapa (dinâmica)
	TOTAL_DAMAGE = "TotalDamage",          -- Causar X dano total (infinita)
	INFINITE_WAVES = "InfiniteWaves",      -- Alcançar wave X no infinite mode (infinita)
	EVOLVES_DONE = "EvolvesDone",          -- Fazer X evolves (infinita)
	SUMMONS_DONE = "SummonsDone",          -- Fazer X summons (infinita)
}

-- Lista de todas as missões
MissionsCatalog.Missions = {
	-- Missão Dinâmica: Próximo Story Level
	{
		ID = "next_story_level",
		Type = MissionsCatalog.MissionTypes.NEXT_STORY_LEVEL,
		Name = "Story Progress",
		Description = "Complete the next story level",
		Reward = { Gems = 25 }, -- Reward por cada level
		Order = 1,
		IsDynamic = true, -- Missão que muda de objetivo
	},
	
	-- Missão Dinâmica: Próximo Mapa
	{
		ID = "next_map",
		Type = MissionsCatalog.MissionTypes.NEXT_MAP,
		Name = "Map Explorer",
		Description = "Complete the next map",
		Reward = { Gems = 100 }, -- Reward por cada mapa
		Order = 2,
		IsDynamic = true,
	},
	
	-- Total Damage (infinita com dificuldade crescente e rewards escaláveis)
	{
		ID = "total_damage",
		Type = MissionsCatalog.MissionTypes.TOTAL_DAMAGE,
		Name = "Damage Dealer",
		Description = "Deal damage to earn Gems (rewards increase with progress)",
		Requirement = 2500, -- Base inicial: 2.5k dano
		DifficultyMultiplier = 1.006, -- Cada milestone precisa de 0.6% mais dano TOTAL que a anterior
		-- Rewards aumentam conforme dano total acumulado (escalamento agressivo)
		RewardTiers = {
			{ TotalDamage = 0,            Gems = 15 },   -- 0+: 15 gems
			{ TotalDamage = 10000000,     Gems = 25 },   -- 10M+: 25 gems
			{ TotalDamage = 100000000,    Gems = 35 },   -- 100M+: 35 gems
			{ TotalDamage = 1000000000,   Gems = 50 },   -- 1B+: 50 gems
		},
		Order = 3,
		IsInfinite = true,
		HasScalingDifficulty = true,
		HasScalingRewards = true, -- Rewards aumentam com progresso
	},
	
	-- Infinite Waves (a cada 10 waves)
	{
		ID = "infinite_waves",
		Type = MissionsCatalog.MissionTypes.INFINITE_WAVES,
		Name = "Wave Warrior",
		Description = "Reach high waves in Infinite Mode",
		Requirement = 10, -- A cada 10 waves
		Reward = { GemsPerTier = 25 }, -- 25 gems a cada 10 waves
		Order = 4,
		IsInfinite = true,
	},
	
	-- Evolves (infinita - a cada 5 evolves, gems aumentam)
	{
		ID = "evolves_infinite",
		Type = MissionsCatalog.MissionTypes.EVOLVES_DONE,
		Name = "Evolution Path",
		Description = "Evolve characters to earn Gems",
		Requirement = 5, -- A cada 5 evolves
		Reward = { BaseTierGems = 50, GemIncreasePerTier = 10 }, -- Tier 1: 50, Tier 2: 60, Tier 3: 70...
		Order = 5,
		IsInfinite = true,
	},
	
	-- Summons (infinita - a cada 50 summons)
	{
		ID = "summons_infinite",
		Type = MissionsCatalog.MissionTypes.SUMMONS_DONE,
		Name = "Summoner's Journey",
		Description = "Perform summons to earn Gems",
		Requirement = 50, -- A cada 50 summons
		Reward = { BaseTierGems = 100, GemIncreasePerTier = 0 }, -- Tier 1: 100, Tier 2: 120, Tier 3: 140...
		Order = 6,
		IsInfinite = true,
	},
}

-- Get mission by ID
function MissionsCatalog:GetMission(missionID)
	for _, mission in ipairs(self.Missions) do
		if mission.ID == missionID then
			return mission
		end
	end
	return nil
end

-- Get all missions of a specific type
function MissionsCatalog:GetMissionsByType(missionType)
	local result = {}
	for _, mission in ipairs(self.Missions) do
		if mission.Type == missionType then
			table.insert(result, mission)
		end
	end
	return result
end

-- Check if a mission is completed based on progress
function MissionsCatalog:IsMissionCompleted(missionID, currentProgress)
	local mission = self:GetMission(missionID)
	if not mission then return false end
	
	-- Missões infinitas nunca são "completadas" totalmente
	if mission.IsInfinite then
		return false -- Player pode sempre ganhar mais rewards
	end
	
	return currentProgress >= mission.Requirement
end

-- Calculate reward for infinite missions with scaling
function MissionsCatalog:CalculateInfiniteReward(missionID, currentProgress, lastClaimedTier)
	local mission = self:GetMission(missionID)
	if not mission or not mission.IsInfinite then return 0 end
	
	-- Missões com dificuldade crescente (scaling difficulty)
	if mission.HasScalingDifficulty then
		local currentMilestone = self:CalculateMilestoneFromDamage(mission, currentProgress)
		local lastClaimedMilestone = lastClaimedTier or 0
		
		if currentMilestone <= lastClaimedMilestone then
			return 0
		end
		
		-- Se tem rewards escaláveis, calcular gems por milestone baseado no dano total
		if mission.HasScalingRewards then
			local totalGems = 0
			
			-- Para cada milestone a resgatar, calcular o reward baseado no dano total naquele momento
			for milestone = lastClaimedMilestone + 1, currentMilestone do
				local damageAtMilestone = self:GetTotalDamageForMilestone(mission, milestone)
				local gemsForMilestone = self:GetRewardForDamageAmount(mission, damageAtMilestone)
				totalGems = totalGems + gemsForMilestone
			end
			
			return totalGems
		else
			-- Reward fixo por milestone
			local milestonesToReward = currentMilestone - lastClaimedMilestone
			return milestonesToReward * (mission.Reward.GemsPerMilestone or 0)
		end
	end
	
	-- Missões normais baseadas em tiers
	local currentTier = math.floor(currentProgress / mission.Requirement)
	local tiersToReward = currentTier - (lastClaimedTier or 0)
	
	if tiersToReward <= 0 then return 0 end
	
	-- Check if has scaling gems (BaseTierGems + increment)
	if mission.Reward.BaseTierGems and mission.Reward.GemIncreasePerTier then
		local totalGems = 0
		local startTier = (lastClaimedTier or 0) + 1
		
		for tier = startTier, currentTier do
			local gemsForTier = mission.Reward.BaseTierGems + (mission.Reward.GemIncreasePerTier * (tier - 1))
			totalGems = totalGems + gemsForTier
		end
		
		return totalGems
	else
		-- Fixed gems per tier
		return tiersToReward * (mission.Reward.GemsPerTier or 0)
	end
end

-- Retorna quantas gems dar baseado no dano total acumulado (para rewards escaláveis)
function MissionsCatalog:GetRewardForDamageAmount(mission, totalDamage)
	if not mission.HasScalingRewards or not mission.RewardTiers then
		return mission.Reward and mission.Reward.GemsPerMilestone or 10
	end
	
	-- Encontrar o tier apropriado baseado no dano total
	local currentReward = 10 -- Default
	
	for i = #mission.RewardTiers, 1, -1 do
		local tier = mission.RewardTiers[i]
		if totalDamage >= tier.TotalDamage then
			currentReward = tier.Gems
			break
		end
	end
	
	return currentReward
end

-- Calcula qual milestone o player atingiu baseado no dano total
-- Milestone N requer: Base × (Multiplier ^ N) de dano TOTAL acumulado
function MissionsCatalog:CalculateMilestoneFromDamage(mission, totalDamage)
	if not mission.HasScalingDifficulty then
		return math.floor(totalDamage / mission.Requirement)
	end
	
	local baseDamage = mission.Requirement
	local multiplier = mission.DifficultyMultiplier or 1.45
	
	-- Se dano total é menor que o base, ainda não completou milestone 0
	if totalDamage < baseDamage then
		return 0
	end
	
	-- Calcular milestone usando logaritmo (mais eficiente que iterar)
	-- totalDamage = base × (multiplier ^ milestone)
	-- milestone = log(totalDamage / base) / log(multiplier)
	local milestone = math.floor(math.log(totalDamage / baseDamage) / math.log(multiplier))
	
	return milestone
end

-- Calcula quanto dano TOTAL é necessário para atingir um milestone específico
function MissionsCatalog:GetDamageForMilestone(mission, milestone)
	if not mission.HasScalingDifficulty then
		return milestone * mission.Requirement
	end
	
	local baseDamage = mission.Requirement
	local multiplier = mission.DifficultyMultiplier or 1.45
	
	return baseDamage * math.pow(multiplier, milestone)
end

-- Calcula quanto dano é necessário para o próximo milestone (diferença)
function MissionsCatalog:GetDamageForNextMilestone(mission, currentMilestone)
	if not mission.HasScalingDifficulty then
		return mission.Requirement
	end
	
	local currentThreshold = self:GetDamageForMilestone(mission, currentMilestone)
	local nextThreshold = self:GetDamageForMilestone(mission, currentMilestone + 1)
	
	return nextThreshold - currentThreshold
end

-- DEPRECATED: Use GetDamageForMilestone
function MissionsCatalog:GetTotalDamageForMilestone(mission, milestone)
	return self:GetDamageForMilestone(mission, milestone)
end

-- Get next tier for infinite mission
function MissionsCatalog:GetNextTier(missionID, currentProgress)
	local mission = self:GetMission(missionID)
	if not mission or not mission.IsInfinite then return 0 end
	
	local currentTier = math.floor(currentProgress / mission.Requirement)
	return currentTier + 1
end

-- Get progress to next tier (0-1)
function MissionsCatalog:GetProgressToNextTier(missionID, currentProgress)
	local mission = self:GetMission(missionID)
	if not mission then return 0 end
	
	if mission.IsInfinite then
		local progressInCurrentTier = currentProgress % mission.Requirement
		return progressInCurrentTier / mission.Requirement
	else
		return math.min(currentProgress / mission.Requirement, 1)
	end
end

return MissionsCatalog
