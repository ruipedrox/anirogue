-- ApplySettings.client.lua
-- Lê MusicVolume e SFXVolume do TeleportData enviado pelo lobby
-- e aplica-os como atributos do player (usados por SFX helpers e futura música).

local Players        = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer

local ok, td = pcall(function()
	return TeleportService:GetLocalPlayerTeleportData()
end)

if ok and type(td) == "table" and type(td.Settings) == "table" then
	local s = td.Settings
	local music = (type(s.MusicVolume) == "number") and math.clamp(s.MusicVolume, 0, 100) or 50
	local sfx   = (type(s.SFXVolume)   == "number") and math.clamp(s.SFXVolume,   0, 100) or 50
	player:SetAttribute("MusicVolume", music)
	player:SetAttribute("SFXVolume",   sfx)
	print(string.format("[ApplySettings] MusicVolume=%d SFXVolume=%d", music, sfx))
else
	-- sem TeleportData (teste direto no Studio): usa defaults
	player:SetAttribute("MusicVolume", 50)
	player:SetAttribute("SFXVolume",   50)
end
