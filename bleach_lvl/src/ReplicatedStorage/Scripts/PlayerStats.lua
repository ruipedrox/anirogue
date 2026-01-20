local PlayerStatsModule = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CharacterTiers
pcall(function()
	CharacterTiers = require(ReplicatedStorage.Scripts:WaitForChild("CharacterTiers"))
end)

function PlayerStatsModule:Calculate(equipment, chars)
	local finalStats = {}

	-- Stats base do jogador
	finalStats.Health = 0
	-- Regeneração de vida por segundo (custom). Roblox default regen será desativado e substituído por este valor.
	finalStats.HPRegenPerSecond = 0
	finalStats.Lifesteal = 0
	finalStats.HealEffectiveness = 1
	finalStats.InvTime = 0.2
	-- XP gain multiplier (1 = 100%)
	finalStats.xpgainrate = 1
	-- Legendary cards limit (can be increased by passives/cards)
	finalStats.LegendaryLimit = 2
	-- NEW: Per-player maximum level and XP growth factor (instead of global constants in Leveling)
	-- Cards / personagens futuras podem aumentar estes valores durante a run.
	finalStats.MaxLevel = 15
	finalStats.LevelGrowth = 1.2

	-- Função auxiliar para somar stats
	local function addStats(sourceStats)
		for stat, value in pairs(sourceStats) do
			if type(value) == "number" then
				if finalStats[stat] then
					finalStats[stat] = finalStats[stat] + value
				else
					finalStats[stat] = value
				end
			elseif type(value) == "boolean" then
				finalStats[stat] = finalStats[stat] or value -- true tem prioridade
			end
		end
	end

	-- Stats de equipamento
	if equipment then
		if equipment.weapon then
			addStats(equipment.weapon)
		end
		if equipment.armor then
			addStats(equipment.armor)
		end
		-- Suporta 1 anel equipado (ring)
		if equipment.ring then
			addStats(equipment.ring)
		end
		-- Caso no futuro tenhas uma lista `rings`, mantemos compatibilidade:
		if equipment.rings then
			for _, ringStats in ipairs(equipment.rings) do
				addStats(ringStats)
			end
		end
	end

	-- Stats dos personagens de suporte
	if chars then
		for _, char in ipairs(chars) do
			if char.Passives then
				local toAdd = char.Passives
				-- Aplicar multiplicador de Tier antes de somar (se módulo disponível)
				if CharacterTiers and type(char.Tier) == "string" then
					local scaled = {}
					local mult = CharacterTiers:GetMultiplier(char.Tier)
					for k, v in pairs(char.Passives) do
						if type(v) == "number" then
							scaled[k] = v * mult
						else
							scaled[k] = v
						end
					end
					toAdd = scaled
				end
				addStats(toAdd)
			end
		end
	end

	-- Temporary Buffs applied as Player attributes (e.g., from cards)
	-- This module doesn't know the player, but Apply can read attributes and add them as needed.
	-- To keep it simple, we let ApplyStats append Buff_ values to Stats folder separately.

	return finalStats
end

return PlayerStatsModule
