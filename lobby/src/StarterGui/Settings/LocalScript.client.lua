-- Settings UI LocalScript
-- Slider music (0-100, step 5) e sfx (0-100, step 5)

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local player           = Players.LocalPlayer
local playerGui        = player:WaitForChild("PlayerGui")
local gui              = script.Parent

-- frame principal
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

-- sliders
local window    = firstFrame:WaitForChild("window")
local codeFrame = window:WaitForChild("code_frame")

local sfxCanvas   = codeFrame:WaitForChild("sfx_canvas")
local sfxKnob     = sfxCanvas:WaitForChild("sfx_slider")
local sfxFill     = sfxCanvas:WaitForChild("sfx_back")

local musicCanvas = codeFrame:WaitForChild("music_canvas")
local musicKnob   = musicCanvas:WaitForChild("music_slider")
local musicFill   = musicCanvas:WaitForChild("music_back")

-- valores default (0-100)
local MUSIC_DEFAULT = 30
local SFX_DEFAULT   = 60
local STEP          = 5

local function getAttr(name, default)
	local v = player:GetAttribute(name)
	return (type(v) == "number") and v or default
end

local musicVol = getAttr("MusicVolume", MUSIC_DEFAULT)
local sfxVol   = getAttr("SFXVolume",   SFX_DEFAULT)

-- aplica volume
local function applyMusic(val)
	musicVol = val
	player:SetAttribute("MusicVolume", val)
	local snd = playerGui:FindFirstChild("LobbyMusic")
	if snd and snd:IsA("Sound") then
		snd.Volume = val / 100
	end
end

local function applySFX(val)
	sfxVol = val
	player:SetAttribute("SFXVolume", val)
end

-- logica de slider
local function updateSliderVisual(canvas, knob, fill, val)
	local canvasW = canvas.AbsoluteSize.X
	local knobW   = knob.AbsoluteSize.X
	if canvasW == 0 then return end
	local t       = math.clamp(val / 100, 0, 1)
	local travel  = canvasW - knobW
	local xOffset = t * travel
	knob.Position = UDim2.new(0, xOffset, knob.Position.Y.Scale, knob.Position.Y.Offset)
	fill.Size     = UDim2.new(0, xOffset + knobW / 2, fill.Size.Y.Scale, fill.Size.Y.Offset)
end

local function posToValue(canvas, knob, absX)
	local canvasW = canvas.AbsoluteSize.X
	local knobW   = knob.AbsoluteSize.X
	if canvasW == 0 then return 0 end
	local travel  = canvasW - knobW
	local rel     = math.clamp(absX - canvas.AbsolutePosition.X - knobW / 2, 0, travel)
	local raw     = (rel / travel) * 100
	return math.clamp(math.round(raw / STEP) * STEP, 0, 100)
end

local function setupSlider(canvas, knob, fill, getVal, applyVal)
	local dragging = false

	task.defer(function()
		updateSliderVisual(canvas, knob, fill, getVal())
	end)

	canvas.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
		\tand input.UserInputType ~= Enum.UserInputType.Touch then return end
		dragging = true
		local val = posToValue(canvas, knob, input.Position.X)
		applyVal(val)
		updateSliderVisual(canvas, knob, fill, val)
	end)

	canvas.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
		\tor input.UserInputType == Enum.UserInputType.Touch then
		\tdragging = false
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
		\tand input.UserInputType ~= Enum.UserInputType.Touch then return end
		local val = posToValue(canvas, knob, input.Position.X)
		applyVal(val)
		updateSliderVisual(canvas, knob, fill, val)
	end)
end

setupSlider(musicCanvas, musicKnob, musicFill,
	function() return musicVol end,
	applyMusic)

setupSlider(sfxCanvas, sfxKnob, sfxFill,
	function() return sfxVol end,
	applySFX)

-- atualiza visuais quando a UI abre
script:GetAttributeChangedSignal("Show"):Connect(function()
	if script:GetAttribute("Show") then
	\ttask.defer(function()
	\t\tapplyMusic(musicVol)
	\t\tapplySFX(sfxVol)
	\t\tupdateSliderVisual(musicCanvas, musicKnob, musicFill, musicVol)
	\t\tupdateSliderVisual(sfxCanvas, sfxKnob, sfxFill, sfxVol)
	\tend)
	end
end)
