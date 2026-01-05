-- Cards UI Client
-- Mostra as cartas disponíveis para um personagem (sourceId) quando atributo ShowCharacterCards é definido.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService") -- usado para esperar layout antes da animação de entrada
local player = Players.LocalPlayer
local CardCatalog = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("CardCatalog"))

local gui = script.Parent -- ScreenGui Cards
-- Começar invisível (só é ativado quando Card_b é clicado na UI de personagens)
gui.Enabled = false
-- Garantir que aparece por cima da UI de inventário (Chars) ajustando DisplayOrder dinamicamente
task.defer(function()
	local playerGui = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui")
	local charsGui = playerGui and playerGui:FindFirstChild("Chars")
	if charsGui and charsGui:IsA("ScreenGui") then
		local base = charsGui.DisplayOrder or 0
		if (gui.DisplayOrder or 0) <= base then
			gui.DisplayOrder = base + 5 -- margem para futuras overlays
		end
	end
end)
local root = gui:WaitForChild("2nd")
local frame = root:WaitForChild("yup")
local scrolling = frame:WaitForChild("ScrollingFrame")
local template = scrolling:FindFirstChild("Frame") -- item template
local exitButton = frame:FindFirstChild("Exit")

if template then
	template.Visible = false
end

local function clear()
	for _, child in ipairs(scrolling:GetChildren()) do
		if child:IsA("Frame") and child ~= template then
			child:Destroy()
		end
	end
end

local RarityColors = {
	Common = Color3.fromRGB(130,130,130),
	Rare = Color3.fromRGB(70,130,255),
	Epic = Color3.fromRGB(180,85,255),
	Legendary = Color3.fromRGB(255,190,40),
	Mythic = Color3.fromRGB(255,70,70),
}

local function gradient(frameObj, base)
	if not frameObj or not base then return end
	local h,s,v = base:ToHSV()
	local lighter = Color3.fromHSV(h, math.clamp(s*0.25,0,1), 1)
	local darker = Color3.fromHSV(h, s, math.max(v*0.25,0.05))
	local grad = frameObj:FindFirstChild("UIGradient") or Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, lighter),
		ColorSequenceKeypoint.new(0.5, base),
		ColorSequenceKeypoint.new(1, darker),
	})
	grad.Rotation = 90
	grad.Parent = frameObj
end

local isAnimating = false
local function animateClose()
	if isAnimating then return end
	isAnimating = true
	-- Guardar posição final (onde deve retornar para próxima abertura)
	local finalPos = frame.Position
	local absY = frame.AbsoluteSize.Y
	if absY == 0 then absY = 400 end
	local offPos = UDim2.new(finalPos.X.Scale, finalPos.X.Offset, -1, -absY)
	-- Preparar fade dos filhos (texto / imagens)
	local fadeTargets = {}
	for _, f in ipairs(scrolling:GetChildren()) do
		if f:IsA("Frame") and f.Visible and f ~= template then
			for _, d in ipairs(f:GetDescendants()) do
				if d:IsA("TextLabel") or d:IsA("ImageLabel") then
					table.insert(fadeTargets, d)
				end
			end
		end
	end
	-- Tween principal (subir para fora)
	local twMain = TweenService:Create(frame, TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = offPos })
	twMain:Play()
	-- Fade simultâneo
	for _, obj in ipairs(fadeTargets) do
		local prop = obj:IsA("TextLabel") and "TextTransparency" or "ImageTransparency"
		pcall(function()
			TweenService:Create(obj, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { [prop] = 1 }):Play()
		end)
	end
	twMain.Completed:Connect(function()
		gui.Enabled = false
		-- Reset posição para próxima abertura
		frame.Position = finalPos
		isAnimating = false
		-- Restaurar transparências para 0 (para próxima entrada)
		for _, obj in ipairs(fadeTargets) do
			if obj:IsA("TextLabel") then
				obj.TextTransparency = 0
			elseif obj:IsA("ImageLabel") then
				obj.ImageTransparency = 0
			end
		end
	end)
end

local function populateForSource(sourceId)
	clear()
	if not sourceId then return end

	-- Animação de entrada do frame principal (desce a partir de cima ligeiro)
	local finalFramePos = frame.Position
	-- Ensure UI root/frame/scrolling are visible immediately as a fallback
	if root and root:IsA("Frame") then root.Visible = true end
	frame.Visible = true
	scrolling.Visible = true
	gui.Enabled = true
	-- Calcular uma posição inicial completamente fora do ecrã por cima.
	-- Usamos Y.Scale = -1 e offset negativo igual à altura do frame para garantir que fica fora.
	local absY = frame.AbsoluteSize.Y
	if absY == 0 then
		-- Se ainda não tiver layout resolvido, esperar um frame para obter tamanho real
		RunService.Heartbeat:Wait()
		absY = frame.AbsoluteSize.Y
	end
	if absY == 0 then
		absY = 400 -- fallback seguro
	end
	local startPos = UDim2.new(finalFramePos.X.Scale, finalFramePos.X.Offset, -1, -absY)
	frame.Position = startPos
	pcall(function()
		TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = finalFramePos }):Play()
	end)
	local list = CardCatalog:GetBySource(sourceId)
	if #list == 0 then
		-- Sem cartas: não mostra nada (lista vazia, nem frame de referência)
		return
	end
	table.sort(list, function(a,b)
		if a.rarityGroup == b.rarityGroup then
			return a.name < b.name
		end
		return tostring(a.rarityGroup) < tostring(b.rarityGroup)
	end)
	local created = 0
	for _, entry in ipairs(list) do
		local clone = template:Clone()
		clone.Name = entry.id
		clone.Visible = true
		local nameLabel = clone:FindFirstChild("Name", true)
		local descLabel = clone:FindFirstChild("Desc", true)
		local icon = clone:FindFirstChild("Icon", true)
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = entry.name
		end
		if descLabel and descLabel:IsA("TextLabel") then
			descLabel.Text = entry.description or ""
		end
		if icon and icon:IsA("ImageLabel") then
			icon.Image = entry.image or "rbxassetid://0"
		end
		local color = RarityColors[entry.rarityGroup] or Color3.fromRGB(255,255,255)
		clone.BackgroundColor3 = color
		clone.BackgroundTransparency = 0
		gradient(clone, color)
		-- Preparar estado inicial para animação (posição deslocada e transparente)
		local finalPos = clone.Position
		clone.Position = finalPos - UDim2.new(0,0,0,30)
		-- Set immediate visible fallback (in case tweens/layout don't run)
		clone.BackgroundTransparency = 0
		local fadeTargets = {}
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("TextLabel") then
				d.TextTransparency = 0
				table.insert(fadeTargets, d)
			elseif d:IsA("ImageLabel") then
				d.ImageTransparency = 0
				table.insert(fadeTargets, d)
			end
		end
		clone.Parent = scrolling
		created = created + 1
		-- Stagger baseado no índice atual (#children após parent) reduzido em 1 para começar em 0
		local orderIndex = #scrolling:GetChildren() - 1 -- template não conta porque está oculto
		local delay = (orderIndex - 1) * 0.05 -- 50ms de intervalo
		task.delay(delay, function()
			-- Tween de posição + background
			pcall(function()
				TweenService:Create(clone, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = finalPos,
					BackgroundTransparency = 0
				}):Play()
			end)
			-- Tween de transparência de texto/imagem
			for _, obj in ipairs(fadeTargets) do
				pcall(function()
					if obj:IsA("TextLabel") then
						TweenService:Create(obj, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
					elseif obj:IsA("ImageLabel") then
						TweenService:Create(obj, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { ImageTransparency = 0 }):Play()
					end
				end)
			end
		end)
	end
	print(string.format("[CardsUI] populateForSource created %d entries for %s", created, tostring(sourceId)))
end

-- Exit button fecha UI
if exitButton and exitButton:IsA("ImageButton") then
	exitButton.MouseButton1Click:Connect(function()
		animateClose()
	end)
end

-- Listener de atributo definido pelo Chars UI: ShowCharacterCards = sourceId
gui:GetAttributeChangedSignal("ShowCharacterCards"):Connect(function()
	local sourceId = gui:GetAttribute("ShowCharacterCards")
	print(string.format("[CardsUI] Attribute ShowCharacterCards changed -> %s", tostring(sourceId)))
	-- Ensure GUI is enabled so animations and frame sizing proceed
	if not gui.Enabled then
		print("[CardsUI] Enabling Cards ScreenGui on attribute change")
		gui.Enabled = true
	end
	if type(sourceId) == "string" and #sourceId > 0 then
		-- debug: template and frame sizes
		local hasTemplate = (template ~= nil)
		print(string.format("[CardsUI] populateForSource requested for %s; template=%s; frameAbsSize=%s; scrollingChildren=%d",
			tostring(sourceId), tostring(hasTemplate), tostring(frame and tostring(frame.AbsoluteSize) or "nil"), #scrolling:GetChildren()))
		populateForSource(sourceId)
	else
		print("[CardsUI] ShowCharacterCards attribute empty or not string")
	end
end)

-- Se GUI for ativada manualmente e já tiver atributo
if gui:GetAttribute("ShowCharacterCards") then
	local v = gui:GetAttribute("ShowCharacterCards")
	print(string.format("[CardsUI] Found existing ShowCharacterCards on startup -> %s", tostring(v)))
	if not gui.Enabled then gui.Enabled = true end
	populateForSource(v)
end

print("[CardsUI] Pronto. Aguardando atributo ShowCharacterCards.")