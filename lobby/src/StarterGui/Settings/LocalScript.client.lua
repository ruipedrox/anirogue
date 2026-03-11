-- Settings UI LocalScript
-- Sliders music/sfx: 0-100 em passos de 5

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player            = Players.LocalPlayer
local playerGui         = player:WaitForChild("PlayerGui")
local gui               = script.Parent

-- Remote para guardar volumes no DataStore via servidor
local SaveSettingsRE = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SaveSettings")

-- ── frame principal ──────────────────────────────────────────────
local firstFrame = gui:WaitForChild("1st")
local exitButton = firstFrame:FindFirstChild("Exit")
firstFrame.Visible = false

local shownPos  = firstFrame.Position
local hiddenPos = UDim2.new(shownPos.X.Scale, shownPos.X.Offset, -1.2, 0)
local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local isOpen    = false

local function show()
	if isOpen then return end
	isOpen = true
	firstFrame.Position = hiddenPos
	firstFrame.Visible  = true
	TweenService:Create(firstFrame, tweenInfo, { Position = shownPos }):Play()
	script:SetAttribute("Show", true)
	script:SetAttribute("Hide", false)
end

local function hide()
	if not isOpen then return end
	isOpen = false
	local tw = TweenService:Create(firstFrame, tweenInfo, { Position = hiddenPos })
	tw:Play()
	tw.Completed:Connect(function()
		if not isOpen then
			firstFrame.Position = shownPos
			firstFrame.Visible  = false
		end
	end)
	script:SetAttribute("Hide", true)
	script:SetAttribute("Show", false)
end

if exitButton and exitButton:IsA("GuiButton") then
	exitButton.MouseButton1Click:Connect(hide)
end

script:SetAttribute("Show", false)
script:SetAttribute("Hide", false)
script:GetAttributeChangedSignal("Show"):Connect(function()
	if script:GetAttribute("Show") then show() end
end)
script:GetAttributeChangedSignal("Hide"):Connect(function()
	if script:GetAttribute("Hide") then hide() end
end)

-- ── referências dos sliders ───────────────────────────────────────
local window     = firstFrame:WaitForChild("window")
local codeFrame  = window:WaitForChild("code_frame")

local sfxCanvas  = codeFrame:WaitForChild("sfx_canvas")
local sfxSlider  = sfxCanvas:WaitForChild("sfx_slider")    -- fill bar: muda Size.X

local musicCanvas = codeFrame:WaitForChild("music_canvas")
local musicSlider = musicCanvas:WaitForChild("music_slider") -- fill bar: muda Size.X

-- ── estado ────────────────────────────────────────────────────────
local STEP          = 5
local MUSIC_DEFAULT = 50
local SFX_DEFAULT   = 50

local function getAttr(name, default)
	local v = player:GetAttribute(name)
	return (type(v) == "number") and v or default
end

local musicVol = getAttr("MusicVolume", MUSIC_DEFAULT)
local sfxVol   = getAttr("SFXVolume",   SFX_DEFAULT)

-- ── aplicar volume ────────────────────────────────────────────────
local updateVisual  -- forward declaration (definida mais abaixo em "visuais do slider")
local settingsLoaded = false  -- evita guardar no DataStore durante o arranque

local function applyMusic(val)
	musicVol = math.clamp(val, 0, 100)
	player:SetAttribute("MusicVolume", musicVol)
	-- LobbyMusic.client.lua ouve GetAttributeChangedSignal("MusicVolume") e aplica BASE_VOLUME * pct
	if settingsLoaded then
		pcall(function() SaveSettingsRE:FireServer(musicVol, sfxVol) end)
	end
end

local function applySFX(val)
	sfxVol = math.clamp(val, 0, 100)
	player:SetAttribute("SFXVolume", sfxVol)
	-- PlaySounds.lua lê player:GetAttribute("SFXVolume") em runtime
	if settingsLoaded then
		pcall(function() SaveSettingsRE:FireServer(musicVol, sfxVol) end)
	end
end

-- Sincroniza valores quando o servidor define os atributos ao carregar o perfil guardado
-- (os atributos do servidor replicam para o cliente)
player:GetAttributeChangedSignal("MusicVolume"):Connect(function()
	local v = player:GetAttribute("MusicVolume")
	if type(v) == "number" and v ~= musicVol then
		musicVol = v
		pcall(function() updateVisual(musicCanvas, musicSlider, musicVol) end)
	end
end)
player:GetAttributeChangedSignal("SFXVolume"):Connect(function()
	local v = player:GetAttribute("SFXVolume")
	if type(v) == "number" and v ~= sfxVol then
		sfxVol = v
		pcall(function() updateVisual(sfxCanvas, sfxSlider, sfxVol) end)
	end
end)

-- ── visuais do slider ─────────────────────────────────────────────
-- slider é o frame fill bar: muda Size.X de 0 até à largura do canvas (escala 0-1)
updateVisual = function(canvas, slider, val)
	local t = math.clamp(val / 100, 0, 1)
	slider.Size = UDim2.new(t, 0, slider.Size.Y.Scale, slider.Size.Y.Offset)
end

-- converte posição X absoluta do rato em valor 0-100 snapped a STEP
local function posToVal(canvas, absX)
	local canvasW = canvas.AbsoluteSize.X
	if canvasW == 0 then return 0 end
	local rel = math.clamp(absX - canvas.AbsolutePosition.X, 0, canvasW)
	local raw = (rel / canvasW) * 100
	return math.clamp(math.round(raw / STEP) * STEP, 0, 100)
end

-- ── setup genérico ────────────────────────────────────────────────
local function setupSlider(canvas, slider, getVal, applyVal)
	local dragging = false

	task.defer(function()
		updateVisual(canvas, slider, getVal())
	end)

	canvas.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		dragging = true
		local val = posToVal(canvas, input.Position.X)
		applyVal(val)
		updateVisual(canvas, slider, val)
	end)

	canvas.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local val = posToVal(canvas, input.Position.X)
		applyVal(val)
		updateVisual(canvas, slider, val)
	end)
end

setupSlider(musicCanvas, musicSlider, function() return musicVol end, applyMusic)
setupSlider(sfxCanvas,   sfxSlider,   function() return sfxVol   end, applySFX)

-- Aguarda o servidor replicar os atributos guardados antes de ativar gravação
-- (evita o race condition: startup aplicaria 50 e sobrescrevia o valor real)
task.spawn(function()
	-- O servidor define os atributos em PlayerAdded; espera até chegar (máx 5s)
	local elapsed = 0
	while player:GetAttribute("MusicVolume") == nil and elapsed < 5 do
		task.wait(0.05)
		elapsed += 0.05
	end
	-- Lê os valores sincronizados pelo servidor
	local m = player:GetAttribute("MusicVolume")
	local s = player:GetAttribute("SFXVolume")
	if type(m) == "number" then
		musicVol = m
		updateVisual(musicCanvas, musicSlider, musicVol)
	end
	if type(s) == "number" then
		sfxVol = s
		updateVisual(sfxCanvas, sfxSlider, sfxVol)
	end
	-- Atualiza volumes de áudio com os valores corretos
	player:SetAttribute("MusicVolume", musicVol)
	player:SetAttribute("SFXVolume",   sfxVol)
	settingsLoaded = true  -- só agora passa a gravar mudanças no DataStore
end)

-- atualiza visuais e volumes cada vez que a UI é aberta (sem re-gravar)
script:GetAttributeChangedSignal("Show"):Connect(function()
	if not script:GetAttribute("Show") then return end
	task.defer(function()
		updateVisual(musicCanvas, musicSlider, musicVol)
		updateVisual(sfxCanvas,   sfxSlider,   sfxVol)
	end)
end)
