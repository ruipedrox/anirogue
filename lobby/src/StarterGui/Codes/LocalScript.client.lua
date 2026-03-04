-- Codes UI Client Script
-- Adapted to work with existing GUI structure

print("[Codes] Script iniciando...")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local gui = script.Parent

print("[Codes] GUI parent:", gui:GetFullName(), "Enabled:", gui.Enabled)

-- Wait for remotes with timeout
local success, Remotes = pcall(function()
	return ReplicatedStorage:WaitForChild("Remotes", 10)
end)

if not success or not Remotes then
	warn("[Codes] ERRO: Pasta Remotes não encontrada!")
	return
end

print("[Codes] Remotes encontrado, procurando RedeemCode...")

local RedeemCodeRE = Remotes:FindFirstChild("RedeemCode")
local RedeemCodeResultRE = Remotes:FindFirstChild("RedeemCodeResult")

-- SFX helper
local _ss = game:GetService("SoundService")
local _db = game:GetService("Debris")
local function playCodeSFX(id)
	if not id or id == 0 then return end
	local sfxMult = math.clamp((player:GetAttribute("SFXVolume") or 50) / 100, 0, 1)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. tostring(id)
	s.Volume = 0.7 * sfxMult
	s.Parent = _ss
	s:Play()
	_db:AddItem(s, 5)
end
local SFX_ACCEPT = 86070307558627
local SFX_REJECT = 110870343804166
local DebugResetCodesRE = Remotes:FindFirstChild("DebugResetCodes")

if not RedeemCodeRE then
	warn("[Codes] RedeemCode RemoteEvent não encontrado, mas continuando...")
end
if not RedeemCodeResultRE then
	warn("[Codes] RedeemCodeResult RemoteEvent não encontrado, mas continuando...")
end

print("[Codes] Procurando elementos da UI...")

-- UI Elements (adjusted to match your existing structure)
local firstFrame = gui:FindFirstChild("1st")
if not firstFrame then
	warn("[Codes] ERRO: Frame '1st' não encontrado!")
	return
end
print("[Codes] 1st encontrado")

local window = firstFrame:FindFirstChild("window")
if not window then
	warn("[Codes] ERRO: window não encontrado!")
	return
end
print("[Codes] window encontrado")

local exitButton = firstFrame:FindFirstChild("Exit")
print("[Codes] Exit button:", exitButton and exitButton:GetFullName() or "NÃO ENCONTRADO")

local codeFrame = window:FindFirstChild("code_frame")
if not codeFrame then
	warn("[Codes] AVISO: code_frame não encontrado, procurando alternativas...")
	codeFrame = window
end

local code = codeFrame:FindFirstChild("code") or codeFrame

-- insert_code é o TextBox onde se escreve o código
local codeInput = code:FindFirstChild("insert_code")
if not codeInput then
	codeInput = codeFrame:FindFirstChild("insert_code")
end
if not codeInput then
	-- Try searching for any TextBox
	codeInput = code:FindFirstChildWhichIsA("TextBox", true)
end

print("[Codes] TextBox encontrado:", codeInput and codeInput.ClassName or "NÃO ENCONTRADO")

if not codeInput then
	warn("[Codes] ERRO: Nenhum TextBox encontrado para código!")
	return
end

-- Use the social text label for status messages
local statusLabel = firstFrame:FindFirstChild("Socials")
if statusLabel then
	statusLabel = statusLabel:FindFirstChildWhichIsA("TextLabel") or statusLabel:FindFirstChildWhichIsA("TextButton")
end
if not statusLabel then
	-- Fallback: search in window
	statusLabel = window:FindFirstChild("social_text") or window:FindFirstChildWhichIsA("TextLabel", true)
end
if not statusLabel then
	warn("[Codes] No status label found, creating one")
	statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Parent = window
	statusLabel.Size = UDim2.new(1, -20, 0, 30)
	statusLabel.Position = UDim2.new(0, 10, 1, -40)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	statusLabel.Text = "Follow us on X @YourAccount and join our Discord server"
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 14
	statusLabel.TextWrapped = true
end

-- Save the default text to restore later
local defaultText = statusLabel.Text
local defaultColor = statusLabel.TextColor3

-- State
local isProcessing = false

-- Conectar TextBox: redeem quando dar Enter
codeInput.FocusLost:Connect(function(enterPressed)
	if not enterPressed then return end -- Só funciona com Enter
	if isProcessing then return end

	local code = codeInput.Text
	if code == "" or #code < 3 then
		playCodeSFX(SFX_REJECT)
		statusLabel.Text = "Invalid Code"
		statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		task.delay(5, function()
			statusLabel.Text = defaultText
			statusLabel.TextColor3 = defaultColor
		end)
		return
	end

	isProcessing = true
	codeInput.TextEditable = false
	statusLabel.Text = "Validating code..."
	statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)

	-- Enviar para o servidor
	if RedeemCodeRE then
		RedeemCodeRE:FireServer(code)
		print("[Codes] Código enviado:", code)
	else
		warn("[Codes] RedeemCodeRE not found!")
		isProcessing = false
		codeInput.TextEditable = true
		statusLabel.Text = "Error: Remote not found"
		statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
	end
end)
print("[Codes] TextBox configurado (Enter para resgatar)")

-- Receber resultado do servidor
if RedeemCodeResultRE then
	RedeemCodeResultRE.OnClientEvent:Connect(function(success, message)
		isProcessing = false
		codeInput.TextEditable = true

		if success then
			playCodeSFX(SFX_ACCEPT)
			statusLabel.Text = message or "Code Redeemed!"
			statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
			codeInput.Text = "" -- Limpa a TextBox
			task.delay(5, function()
				statusLabel.Text = defaultText
				statusLabel.TextColor3 = defaultColor
			end)
		else
			playCodeSFX(SFX_REJECT)
			statusLabel.Text = message or "Invalid Code"
			statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
			task.delay(5, function()
				statusLabel.Text = defaultText
				statusLabel.TextColor3 = defaultColor
			end)
		end
	end)
	print("[Codes] Result handler configurado")
else
	warn("[Codes] RedeemCodeResultRE not found")
end

-- Animações de abrir/fechar
local isOpen = false
local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local hiddenPos = UDim2.new(firstFrame.Position.X.Scale, firstFrame.Position.X.Offset, -1.2, 0) -- fora da tela em cima
local shownPos = firstFrame.Position -- posição original

local function show()
	print("[Codes] show() chamado - firstFrame.Visible=", firstFrame.Visible)
	firstFrame.Visible = true
	firstFrame.Position = hiddenPos
	print("[Codes] Iniciando tween de", hiddenPos, "para", shownPos)
	TweenService:Create(firstFrame, tweenInfo, { Position = shownPos }):Play()
	isOpen = true
	script:SetAttribute("Show", true)
	script:SetAttribute("Hide", false)
	print("[Codes] Show anim completo")
end

local function hide()
	if not isOpen then 
		print("[Codes] hide() ignorado - já está fechado")
		return 
	end
	isOpen = false
	print("[Codes] hide() - iniciando animação")
	local tw = TweenService:Create(firstFrame, tweenInfo, { Position = hiddenPos })
	tw:Play()
	tw.Completed:Connect(function()
		if not isOpen then
			firstFrame.Position = shownPos -- reset
			firstFrame.Visible = false
			print("[Codes] Hide completo - firstFrame invisível")
		end
	end)
	script:SetAttribute("Hide", true)
	script:SetAttribute("Show", false)
	print("[Codes] Hide anim iniciado")
end

-- Exit button com animação
exitButton.MouseButton1Click:Connect(function()
	hide()
end)

-- API para controle externo via atributos
script:SetAttribute("Show", false)
script:SetAttribute("Hide", false)
print("[Codes] Configurando listeners de atributos...")
script:GetAttributeChangedSignal("Show"):Connect(function()
	local showValue = script:GetAttribute("Show")
	print("[Codes] Atributo Show mudou para:", showValue)
	if showValue then show() end
end)
script:GetAttributeChangedSignal("Hide"):Connect(function()
	local hideValue = script:GetAttribute("Hide")
	print("[Codes] Atributo Hide mudou para:", hideValue)
	if hideValue then hide() end
end)

-- Start hidden - GUI enabled mas 1st invisível
firstFrame.Visible = false

print("[Codes] UI initialized - gui.Enabled=", gui.Enabled, "firstFrame.Visible=", firstFrame.Visible)

-- Debug: Pressionar 'ç' para resetar códigos (só em Studio)
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

if RunService:IsStudio() and DebugResetCodesRE then
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.Semicolon then -- 'ç' é detectado como Semicolon em alguns teclados
			DebugResetCodesRE:FireServer()
			if statusLabel then
				local oldText = statusLabel.Text
				local oldColor = statusLabel.TextColor3
				statusLabel.Text = "CÓDIGOS RESETADOS!"
				statusLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
				task.wait(2)
				statusLabel.Text = oldText
				statusLabel.TextColor3 = oldColor
			end
			print("[Codes] Códigos resetados via tecla 'ç'")
		end
	end)
	print("[Codes] Debug reset ativado - pressiona 'ç' para resetar códigos")
end
