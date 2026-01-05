--[[
README_Catalogs.lua (documentação)

Objetivo:
  Centralizar a forma de aceder a Personagens, Itens e Cartas no Lobby e noutros mapas.
  Estas estruturas são de-para dos conteúdos em Shared/ para UI (summon, inventário, loja, etc.)

Módulos principais:
  CharacterCatalog
    :Get(templateName) -> entry
    :GetOrdered() -> array ordenada por estrelas desc + nome
    entry campos:
      template, displayName, stars, lvl1_stats, cards (Definitions), cardCount, icon_id, source="Character"

  ItemCatalog
    :Get(id) -> entry
    :GetByType("Weapon"|"Armor"|"Ring") -> map id->entry
    :GetOrdered() -> todos itens ordenados por raridade + tipo + id
    entry campos:
      id, itemType, rarity, lvl1_stats, levels, cards, cardCount, icon_id, source="Item", rawStats

  CardCatalog
    :Get(cardId) -> entry
    :GetAll() -> lista de todas cartas
    :GetByRarity(rarityGroup) -> cartas de um grupo (ex: "Common")
    :GetBySource(sourceId) -> todas cartas originadas de um personagem ou item específico
    entry campos:
      id, name, description, rarityGroup, source (Character|Item), sourceId, sourceType, def (tabela original), image

Uso típico na UI:
  local CharacterCatalog = require(ReplicatedStorage.Scripts.CharacterCatalog)
  for _, c in ipairs(CharacterCatalog:GetOrdered()) do
      -- construir botão de seleção / summon
  end

  local ItemCatalog = require(ReplicatedStorage.Scripts.ItemCatalog)
  for w in ItemCatalog:Iter("Weapon") do
      -- listar armas
  end

  local CardCatalog = require(ReplicatedStorage.Scripts.CardCatalog)
  local commons = CardCatalog:GetByRarity("Common")

Validação:
  Cada catálogo possui :Validate() para imprimir avisos sobre dados ausentes.

Notas futuras:
  * Substituir icon_id placeholder pelos assets corretos.
  * Adicionar cache/refresh caso futuras edições dinâmicas sejam necessárias.
  * Integrar raridades de cartas numa enum central se expandires.
]]