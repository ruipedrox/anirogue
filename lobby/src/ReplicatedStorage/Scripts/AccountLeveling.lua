-- AccountLeveling.lua (Lobby Version)
-- Sistema de level persistente da conta (polinomial) adaptado para o lobby.
-- Fornece API pura baseada em tabelas (não cria Instâncias Roblox aqui).
-- Integração: ProfileService chama EnsureStructure(profile) no carregamento.

local AccountLeveling = {}

AccountLeveling.BasePoly = 2800
AccountLeveling.ScalePoly = 450
AccountLeveling.PowerPoly = 1.2
-- SLOT SYSTEM:
-- Agora existem até 5 slots de personagem equipáveis.
-- Os primeiros 2 estão SEMPRE desbloqueados (base fixa).
-- Cada valor em SlotUnlockLevels concede +1 slot adicional até ao máximo.
-- Exemplo com {10, 25, 40}: 2 base +1 (>=10) +1 (>=25) +1 (>=40) = 5.
AccountLeveling.SlotUnlockLevels = {10, 25, 40}

-- Calcula o XP requerido para o nível atual (para subir para o próximo)
function AccountLeveling:GetRequiredXP(level)
	level = math.max(1, tonumber(level) or 1)
	local n = level - 1
	local req = self.BasePoly + self.ScalePoly * (n ^ self.PowerPoly)
	return math.floor(req + 0.5)
end

function AccountLeveling:GetAllowedEquipSlots(level)
	-- 2 base sempre
	local slots = 2
	for _, thr in ipairs(self.SlotUnlockLevels) do
		if level >= thr then
			slots += 1
		end
	end
	if slots > 5 then slots = 5 end
	return slots
end

-- Garante campos coerentes no profile.Account
function AccountLeveling:EnsureStructure(profile)
	local acc = profile.Account
	acc.Level = math.max(1, tonumber(acc.Level) or 1)
	acc.XP = math.max(0, tonumber(acc.XP) or 0)
	return acc
end

-- Adiciona XP, aplica múltiplos level ups, retorna níveis ganhos e xp leftover final
function AccountLeveling:AddXP(profile, amount)
	amount = tonumber(amount) or 0
	if amount <= 0 then return 0 end
	local acc = self:EnsureStructure(profile)
	local gained = 0
	while amount > 0 do
		local req = self:GetRequiredXP(acc.Level)
		if acc.XP + amount < req then
			acc.XP += amount
			amount = 0
		else
			local need = req - acc.XP
			amount -= need
			acc.Level += 1
			acc.XP = 0
			gained += 1
		end
	end
	return gained
end

function AccountLeveling:GetSnapshot(profile)
	local acc = self:EnsureStructure(profile)
	local req = self:GetRequiredXP(acc.Level)
	local fraction = req > 0 and math.clamp(acc.XP / req, 0, 1) or 0
	return {
		Level = acc.Level,
		XP = acc.XP,
		Required = req,
		Fraction = fraction,
		EquipSlots = self:GetAllowedEquipSlots(acc.Level),
		Coins = acc.Coins or 0,
		Gems = acc.Gems or 0,
	}
end

return AccountLeveling