-- AutoAttackSFX.client.lua
-- Ajusta o volume dos sons 3D de combate criados pelo servidor,
-- com base na preferência SFXVolume de cada jogador.

local Players = game:GetService("Players")
local player  = Players.LocalPlayer

-- Ajusta o volume de todos os Sons 3D de combate criados pelo servidor
-- com base no SFXVolume do jogador local.
local function adjustSFXVolume(inst)
	if not inst:IsA("Sound") then return end
	if not inst:GetAttribute("GameSFX") then return end
	-- defer: garante que Volume já foi replicado antes de escalar
	task.defer(function()
		if not inst or not inst.Parent then return end
		local sfxAttr = player:GetAttribute("SFXVolume")
		local mult = (type(sfxAttr) == "number") and math.clamp(sfxAttr / 100, 0, 1) or 0.5
		inst.Volume = inst.Volume * mult
	end)
end

workspace.DescendantAdded:Connect(adjustSFXVolume)
