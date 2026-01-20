-- CharacterLeveling.lua
-- Lógica de XP e Level para personagens instanciadas (CharacterInstances)
-- Curva: exponencial suave base 100, growth 1.10 (ajustado de 1.12 -> 1.10 para ritmo mais moderado).
-- API:
--   CharacterLeveling.XPRequired(level) -> xpNeeded (para passar desse level para o próximo)
--   CharacterLeveling.TryLevelUp(instanceFolder)
--   CharacterLeveling.AddXPInstance(instanceFolder, amount) -- adiciona XP e tenta subir
--   CharacterLeveling.ApplyPending(player) -- aplica ganhos acumulados em player.RunAccum.CharacterXP
--
-- NOTA: Max level atual segue o cap global (80). Se quiser dinamizar (ex: cartas +MaxLevel),
-- podes ler um IntValue extra dentro da instância (ex: MaxLevel) e usar no lugar de HARDCAP.

local CharacterLeveling = {}

local HARD_CAP = 80
local BASE_XP = 100
local GROWTH = 1.10 -- (antes: 1.12)

function CharacterLeveling.XPRequired(level: number): number
	if level >= HARD_CAP then
		return 0
	end
	-- XP para ir de level -> level+1
	local required = BASE_XP * (GROWTH ^ (level - 1))
	return math.floor(required + 0.5)
end

function CharacterLeveling.TryLevelUp(instanceFolder: Folder)
	local levelVal = instanceFolder:FindFirstChild("Level")
	local xpVal = instanceFolder:FindFirstChild("XP")
	if not (levelVal and xpVal) then return end
	while true do
		local need = CharacterLeveling.XPRequired(levelVal.Value)
		if need == 0 or xpVal.Value < need then
			break
		end
		xpVal.Value -= need
		levelVal.Value += 1
		-- Hook: opcional emitir evento de subida
	end
end

function CharacterLeveling.AddXPInstance(instanceFolder: Folder, amount: number)
	if type(amount) ~= "number" or amount <= 0 then return end
	local xpVal = instanceFolder:FindFirstChild("XP")
	if not xpVal then return end
	xpVal.Value += amount
	CharacterLeveling.TryLevelUp(instanceFolder)
end

-- Aplica ganhos acumulados (NumberValues) em RunAccum/CharacterXP/<InstanceId>
function CharacterLeveling.ApplyPending(player: Player)
	local accum = player:FindFirstChild("RunAccum")
	if not accum then return end
	local gains = accum:FindFirstChild("CharacterXP")
	if not gains then return end
	local instances = player:FindFirstChild("CharacterInstances")
	if not instances then return end
	for _, inst in ipairs(instances:GetChildren()) do
		local nv = gains:FindFirstChild(inst.Name)
		if nv and nv:IsA("NumberValue") and nv.Value > 0 then
			CharacterLeveling.AddXPInstance(inst, nv.Value)
		end
	end
end

return CharacterLeveling
