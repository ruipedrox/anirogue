-- RunRewards.lua
-- Scaffold para retorno de XP por instância de personagem.
-- Futuro: calcular XP ganho real (ex.: waves limpas, multiplicadores, performance) antes de construir payload.
-- Por agora: apenas lê CharacterInstances e devolve Level/XP atuais (sem alterar).

local RunRewards = {}

-- BuildCharacterXP(player [, context]) -> table
-- Retorna estrutura preparada para TeleportData de saída:
-- {
--   CharacterInstances = {
--       [InstanceId] = { TemplateName = "Goku_5", Level = 10, XP = 1234 },
--       ...
--   }
-- }
-- Não aplica ganhos (placeholder). Quando triggers de fim de run forem implementados,
-- adicionar cálculo e atualizar Level/XP antes de montar retorno.
function RunRewards.BuildCharacterXP(player, context)
	-- Se/quando adicionares ganhos de XP por run: descomenta as duas linhas abaixo
	-- local CharacterLeveling = require(game.ReplicatedStorage.Scripts:WaitForChild("CharacterLeveling"))
	-- CharacterLeveling.ApplyPending(player) -- aplica e faz level up antes de snapshot

	local payload = { CharacterInstances = {} }
	local instancesFolder = player:FindFirstChild("CharacterInstances")
	if not instancesFolder then return payload end
	for _, inst in ipairs(instancesFolder:GetChildren()) do
		if inst:IsA("Folder") then
			local templateNameVal = inst:FindFirstChild("TemplateName")
			local levelVal = inst:FindFirstChild("Level")
			local xpVal = inst:FindFirstChild("XP")
			if templateNameVal and levelVal and xpVal then
				payload.CharacterInstances[inst.Name] = {
					TemplateName = templateNameVal.Value,
					Level = levelVal.Value,
					XP = xpVal.Value,
				}
			end
		end
	end
	return payload
end

return RunRewards
