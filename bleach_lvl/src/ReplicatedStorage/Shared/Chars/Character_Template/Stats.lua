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

return TemplateStats
