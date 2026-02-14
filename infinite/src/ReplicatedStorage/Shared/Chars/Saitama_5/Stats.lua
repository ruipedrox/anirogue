local SaitamaStats = {}

-- Display metadata
SaitamaStats.name = "Bald Hero" -- Saitama, 5-star
SaitamaStats.stars = 5
SaitamaStats.icon = 0 -- Substitui com o ID do ícone quando tiveres
-- NOTA: Stats base baixos porque a carta "Serious Training" dá scaling massivo durante a run
SaitamaStats.Passives = {
	BaseDamage = 50,   -- Baixo de propósito - escala com Serious Training
	Health = 60,      -- Reduzido - escala com treino
}

-- XP dado quando consumido no Feed (5 = 50000)
SaitamaStats.FeedXP = 50000

return SaitamaStats
