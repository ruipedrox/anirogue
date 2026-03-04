-- Settings UI LocalScript (Infinite mode)
-- Sliders music/sfx: 0-100 em passos de 5
-- Sem gravação no DataStore — valores chegam via TeleportData (ApplySettings.client.lua)

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService     = game:GetService("SoundService")
local Debris           = game:GetService("Debris")
local player           = Players.LocalPlayer
local gui              = script.Parent

-- ── Som de click ──────────────────────────────────────────────────
local UI_CLICK_ID = 87437544236708
local function playClick()
	local sfxAttr = player:GetAttribute("SFXVolume")
	local sfxMult = (type(sfxAttr) == "number") and math.clamp(sfxAttr / 100, 0, 1) or 0.5
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. tostring(UI_CLICK_ID)
	s.Volume  = 0.6 * sfxMult
	s.Parent  = SoundService
	s:Play()
	Debris:AddItem(s, 5)
end

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
	exitButton.MouseButton1Click:Connect(function()
		playClick()
		hide()
	end)
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
local STEP = 5

-- ApplySettings.client.lua já definiu os atributos a partir do TeleportData
local musicVol = math.clamp(tonumber(player:GetAttribute("MusicVolume")) or 50, 0, 100)
local sfxVol   = math.clamp(tonumber(player:GetAttribute("SFXVolume"))   or 50, 0, 100)

-- ── aplicar volume ────────────────────────────────────────────────
local updateVisual  -- forward declaration

local function applyMusic(val)
	musicVol = math.clamp(val, 0, 100)
	player:SetAttribute("MusicVolume", musicVol)
end

local function applySFX(val)
	sfxVol = math.clamp(val, 0, 100)
	player:SetAttribute("SFXVolume", sfxVol)
end

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
	local lastSnapped = -1  -- evita click sound repetido no mesmo step

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
		if val ~= lastSnapped then lastSnapped = val; playClick() end
	end)

	canvas.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
			lastSnapped = -1
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local val = posToVal(canvas, input.Position.X)
		applyVal(val)
		updateVisual(canvas, slider, val)
		if val ~= lastSnapped then lastSnapped = val; playClick() end
	end)
end

setupSlider(musicCanvas, musicSlider, function() return musicVol end, applyMusic)
setupSlider(sfxCanvas,   sfxSlider,   function() return sfxVol   end, applySFX)

-- Sincroniza slider visual se ApplySettings ainda não tiver corrido (race condition raro)
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

-- atualiza visuais cada vez que a UI é aberta
script:GetAttributeChangedSignal("Show"):Connect(function()
	if not script:GetAttribute("Show") then return end
	task.defer(function()
		updateVisual(musicCanvas, musicSlider, musicVol)
		updateVisual(sfxCanvas,   sfxSlider,   sfxVol)
	end)
end)
