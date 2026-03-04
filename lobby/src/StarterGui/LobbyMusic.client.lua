-- LobbyMusic.client.lua
-- Simple client-side background music for the lobby.

local Players = game:GetService("Players")
local player = Players.LocalPlayer
if not player then return end

local AUDIO_ID     = 114567915893133
local BASE_VOLUME  = 1     -- 100% slider = volume 1; 50% slider = 0.5

local function getVolume()
	local attr = player:GetAttribute("MusicVolume")
	-- slider 0-100; default 50 → 50% de BASE_VOLUME
	local pct = (type(attr) == "number") and math.clamp(attr / 100, 0, 1) or 0.5
	return BASE_VOLUME * pct
end

local function ensureAndPlay()
	local gui = player:WaitForChild("PlayerGui")

	-- evita duplicados
	local existing = gui:FindFirstChild("LobbyMusic")
	if existing and existing:IsA("Sound") then
		if existing.SoundId ~= ("rbxassetid://" .. tostring(AUDIO_ID)) then
			existing:Destroy()
		else
			existing.Volume = getVolume()
			if not existing.IsPlaying then pcall(function() existing:Play() end) end
			return existing
		end
	end

	local sound = Instance.new("Sound")
	sound.Name    = "LobbyMusic"
	sound.SoundId = "rbxassetid://" .. tostring(AUDIO_ID)
	sound.Looped  = true
	sound.Volume  = getVolume()
	sound.Parent  = gui
	pcall(function() sound:Play() end)
	return sound
end

local sound = nil

local ok, result = pcall(ensureAndPlay)
if ok then sound = result end

-- listener direto no atributo — atualiza o Volume imediatamente ao mover o slider
player:GetAttributeChangedSignal("MusicVolume"):Connect(function()
	if sound and sound.Parent then
		sound.Volume = getVolume()
	else
		-- re-procura caso o Sound tenha sido recriado
		local snd = player.PlayerGui and player.PlayerGui:FindFirstChild("LobbyMusic")
		if snd and snd:IsA("Sound") then
			sound = snd
			sound.Volume = getVolume()
		end
	end
end)

return nil
