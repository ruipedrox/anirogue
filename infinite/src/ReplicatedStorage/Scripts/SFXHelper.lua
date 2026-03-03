-- SFXHelper.lua
-- Cria Sons 3D no servidor, parented a uma Part âncora efémera em workspace,
-- garantindo que o som toca mesmo que a part original seja destruída.
-- Os clientes ajustam o volume individualmente via DescendantAdded (AutoAttackSFX.client.lua).

local Debris       = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local SFXHelper = {}

--[[
    SFXHelper.playAt(part, sfxId, volume, opts?)

    part        – BasePart onde o som deve ser criado (usada para ler a posição)
    sfxId       – número do asset (sem o prefixo rbxassetid://)
    volume      – volume base (será escalado pelo cliente via SFXVolume)
    opts        – tabela opcional:
        minDist       (default 15)   – RollOffMinDistance
        maxDist       (default 80)   – RollOffMaxDistance
        lifetime      (default 5)    – segundos até Debris destruir o Sound
        playbackSpeed (default nil)  – PlaybackSpeed (para pitch-stretch)
        fadeStart     (default nil)  – segundos até iniciar fade-out
        fadeDuration  (default 0.5)  – duração do fade-out em segundos
        follow        (default false) – se true, parent ao part original (segue o objeto);
                                        se false, cria âncora na posição atual (mais robusto)
]]
function SFXHelper.playAt(part, sfxId, volume, opts)
	if not part then return nil end
	opts = opts or {}

	-- Determinar onde parear o som
	local soundParent
	if opts.follow then
		-- Modo "seguir": parent direto à part (som move com ela)
		if not part.Parent then return nil end
		soundParent = part
	else
		-- Modo âncora (default): criar Part efémera na posição atual
		-- Isso garante que o som toca mesmo que a part original seja destruída
		local pos
		local ok, cf = pcall(function() return part.CFrame end)
		if ok and typeof(cf) == "CFrame" then
			pos = cf.Position
		else
			return nil -- parte completamente inválida
		end

		local anchor = Instance.new("Part")
		anchor.Name = "SFXAnchor"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.5, 0.5, 0.5)
		anchor.CFrame = CFrame.new(pos)
		anchor.Parent = workspace
		Debris:AddItem(anchor, opts.lifetime or 5)
		soundParent = anchor
	end

	local s = Instance.new("Sound")
	s.SoundId             = "rbxassetid://" .. tostring(sfxId)
	s.Volume              = volume or 0.8
	s.RollOffMinDistance  = opts.minDist or 100
	s.RollOffMaxDistance  = opts.maxDist or 1000
	s.RollOffMode         = Enum.RollOffMode.InverseTapered
	if opts.playbackSpeed then
		s.PlaybackSpeed = opts.playbackSpeed
	end
	if opts.loop then
		s.Looped = true
	end
	-- Marca o som para o cliente poder ajustar o volume individual
	s:SetAttribute("GameSFX", true)
	s.Parent = soundParent
	s:Play()

	if not opts.follow then
		-- Âncora já tem Debris; não adicionar Debris separado ao som
	else
		Debris:AddItem(s, opts.lifetime or 5)
	end

	-- Fade-out opcional (server-side via TweenService – replicado para todos)
	if opts.fadeStart and opts.fadeDuration then
		local fadeStart    = opts.fadeStart
		local fadeDuration = opts.fadeDuration
		task.delay(fadeStart, function()
			if s and s.Parent then
				local ti = TweenInfo.new(fadeDuration, Enum.EasingStyle.Linear)
				TweenService:Create(s, ti, { Volume = 0 }):Play()
			end
		end)
	end

	return s
end

return SFXHelper
