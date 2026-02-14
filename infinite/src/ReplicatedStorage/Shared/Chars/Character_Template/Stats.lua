local TemplateStats = {}

-- Metadata de exibição
TemplateStats.name = "Character Template"
TemplateStats.stars = 3
TemplateStats.icon = 1234567890

-- Passivos base que este personagem deve conceder quando equipado
-- Ajuste os valores conforme a raridade/nivel desejado
TemplateStats.Passives = {
    BaseDamage = 10,
    Health = 200,
    -- Exemplo de outros valores que podem ser adicionados:
    -- CritChance = 5,
    -- DamagePercent = 0,
}

-- XP dado quando este personagem é consumido no Feed
-- Escala: 3★=5000, 4★=15000, 5★=50000, XP chars são muito mais valiosos
TemplateStats.FeedXP = 5000

return TemplateStats
