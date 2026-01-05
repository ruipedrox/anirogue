--[[
README_CharacterInventory.lua

Módulo: CharacterInventory
Objetivo: Produzir estrutura já enriquecida para UI a partir do profile.

Exemplo servidor (ou cliente com snapshot completo):
  local ProfileService = require(ServerScriptService.ProfileService)
  local CharacterInventory = require(ReplicatedStorage.Scripts.CharacterInventory)
  local profile = ProfileService:Get(player)
  local inv = CharacterInventory.Build(profile)

Estrutura retornada:
  inv = {
    EquippedOrder = { instanceId1, instanceId2, ... },
    Instances = {
       [instanceId] = {
          Id, TemplateName, Level, XP, Tier,
          Catalog = { template, displayName, stars, lvl1_stats, ... },
          Preview = { Template, Level, Tier, Stats = { BaseDamage, Health, ... }, TierMultiplier },
       }
    },
    OrderedList = { <cada enriched instance, ordenada por estrelas desc + nome> }
  }

RemoteFunction adicionada: Remotes:GetCharacterInventory
  InvokeServer() -> { inventory = inv, serverTime = os.time() }

Fluxo de UI recomendado:
  1. Chamar GetCharacterInventory na abertura do painel.
  2. Guardar inv.OrderedList para geração de botões/cards.
  3. Usar inst.Preview.Stats para exibir valores com multiplicadores aplicados.
  4. Escutar RemoteEvent ProfileUpdated para atualizações incrementais (TODO: podes depois regenerar apenas instâncias alteradas).

Futuras melhorias possíveis:
  * Calcular progressão de XP (percentual para próximo nível) dentro do enriched instance.
  * Cache e diff incremental (para não reconstruir tudo a cada update).
  * Incluir metadata de desbloqueio (ex: locked vs owned) usando CharacterCatalog:GetOrdered() para mostrar silhouettes.
]]