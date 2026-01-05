-- Chars UI Client
-- Renderiza inventário de personagens, aplica cor por raridade (estrelas) e anima abrir/fechar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- Função de espera segura com timeout para evitar infinite yield warnings
local function waitFor(parent, name, timeout)
	timeout = timeout or 5
	local t0 = time()
	local obj = parent:FindFirstChild(name)
	while not obj and (time() - t0) < timeout do
		parent.ChildAdded:Wait()
		obj = parent:FindFirstChild(name)
	end
	return obj
end

local Remotes = waitFor(ReplicatedStorage, "Remotes", 5)
if not Remotes then
	warn("[CharsUI] Pasta Remotes não encontrada (timeout)")
	return
end
local GetCharacterInventoryRF = waitFor(Remotes, "GetCharacterInventory", 5)
if not GetCharacterInventoryRF then
	warn("[CharsUI] Remote GetCharacterInventory não encontrado (timeout)")
	return
end

-- IMPORTANT: declarar currentInventory ANTES de qualquer função que o feche em upvalue
-- para evitar criar um 'global' implícito e depois sombrear com um 'local' mais abaixo.
-- Este foi o motivo do contador ficar XX/YY (a função via sempre nil).
local currentInventory = nil

-- Referências UI (assumindo hierarquia mostrada na imagem):
local rootGui = script.Parent -- Pasta Chars dentro de StarterGui/Chars
local frame = rootGui:WaitForChild("Frame")
local exitButton = frame:WaitForChild("Exit_b")
local invContainer = frame:WaitForChild("Inv")
local invFrame = invContainer:WaitForChild("Inv_frame")
local invSpaceFrame = frame:WaitForChild("Inv_space")
-- Plus_space é irmão de Inv_space (não filho) segundo screenshot; procurar primeiro no frame raiz
local plusSpaceButton = frame:FindFirstChild("Plus_space") or invSpaceFrame:FindFirstChild("Plus_space")
if not plusSpaceButton then
	warn("[CharsUI] Plus_space não encontrado como filho direto de Frame ou dentro de Inv_space")
end
local invSpaceText = invSpaceFrame:FindFirstChild("Space_text", true) or invSpaceFrame:FindFirstChild("SpaceText", true) or invSpaceFrame:FindFirstChild("Space", true)
local scrolling = invFrame:WaitForChild("ScrollingFrame")
local template = scrolling:WaitForChild("inv_icon")

-- Preview UI referências
local preview = frame:WaitForChild("Prev")
local previewInner = preview:WaitForChild("Frame") -- contém UIGradient existente
local previewScroll = previewInner:WaitForChild("ScrollingFrame")
local statTemplate = previewScroll:FindFirstChild("Stat_f")
local previewIconContainer = previewInner:WaitForChild("Icon_c")
local previewIconImage = previewIconContainer:FindFirstChild("Icon", true)
local previewCharName = previewIconContainer:FindFirstChild("Char_Name", true)
local eqBg = previewIconContainer:WaitForChild("EQ_BG")
local equipButton = previewInner:FindFirstChild("Equip_b")
local unequipButton = previewInner:FindFirstChild("Unequip_b")
local cardButton = previewInner:FindFirstChild("Card_b") -- novo botão para abrir UI de cartas
local sellButton = previewInner:FindFirstChild("Sell_b") -- botão de vender

-- Painel de upgrade de espaço (Space_up)
local spacePanel = frame:FindFirstChild("Space_up") or rootGui:FindFirstChild("Space_up")
local spaceYesButton = spacePanel and spacePanel:FindFirstChild("Yes_b")
local spaceNoButton = spacePanel and spacePanel:FindFirstChild("No_b")
local spaceText1 = spacePanel and spacePanel:FindFirstChild("1st_text")
local spaceText2 = spacePanel and spacePanel:FindFirstChild("2st_text") or spacePanel and spacePanel:FindFirstChild("2nd_text")
local spaceAnimating = false
if spacePanel then spacePanel.Visible = false end

-- Painel de confirmação de venda (fora de Prev na hierarquia conforme screenshot)
local sellPanel = frame:FindFirstChild("Sell") or rootGui:FindFirstChild("Sell")
local sellYesButton = sellPanel and sellPanel:FindFirstChild("Yes_b")
local sellNoButton = sellPanel and sellPanel:FindFirstChild("No_b")
local sellText1 = sellPanel and sellPanel:FindFirstChild("1st_text")
local sellText2 = sellPanel and sellPanel:FindFirstChild("2st_text") or sellPanel and sellPanel:FindFirstChild("2nd_text")
local sellAnimating = false
if sellPanel then
	sellPanel.Visible = false
end

-- Helper para atualizar o texto de espaço (usado em vários pontos)
local function updateInvSpaceLabel()
	-- Re-detect frame
	if (not invSpaceFrame or not invSpaceFrame.Parent) then
		invSpaceFrame = frame:FindFirstChild("Inv_space", true)
	end
	-- Deep search por qualquer label potencial chamada Space_text / variações
	if (not invSpaceText or not invSpaceText.Parent) and invSpaceFrame then
		invSpaceText = invSpaceFrame:FindFirstChild("Space_text", true)
			or invSpaceFrame:FindFirstChild("SpaceText", true)
			or invSpaceFrame:FindFirstChild("Space", true)
	end
	if not invSpaceText then
		warn("[CharsUI][Space] Label não encontrado (Space_text / SpaceText / Space)")
	end
	if currentInventory then
		if not currentInventory.CurrentCount then
			local c = 0
			for _ in pairs(currentInventory.Instances or {}) do c += 1 end
			currentInventory.CurrentCount = c
		end
	end
	if invSpaceText and currentInventory then
		local used = currentInventory.CurrentCount or 0
		local cap = currentInventory.Capacity or 50
		local txt = string.format("%d/%d", used, cap)
		if invSpaceText.Text ~= txt then
			invSpaceText.Text = txt
			print(string.format("[CharsUI][Space] Atualizado -> %s", txt))
		else
			print(string.format("[CharsUI][Space] Sem mudança (%s)", txt))
		end
	end
end

-- Remotes de equip/unequip
local EquipOneRE = Remotes:FindFirstChild("EquipOne")
local UnequipOneRE = Remotes:FindFirstChild("UnequipOne")
local SellCharacterRE = Remotes:FindFirstChild("SellCharacter") -- iremos criar no servidor se não existir
local IncreaseCapacityRE = Remotes:FindFirstChild("IncreaseCapacity")

-- (Mensagens flutuantes removidas temporariamente)

-- (declaração movida para o topo do ficheiro, acima das funções)

-- Guardar gradient original do preview para reutilizar

-- Garante que temos um template válido e oculto
if statTemplate then
    statTemplate.Visible = false -- template não deve aparecer diretamente
end

local function clearStats()
	if not statTemplate then return end
	for _, child in ipairs(previewScroll:GetChildren()) do
		if child:IsA("Frame") and child ~= statTemplate then
			child:Destroy()
		end
	end
end

local function addStatLine(statName, value)
	if not statTemplate then return end
	local clone = statTemplate:Clone()
	clone.Name = "Stat_" .. statName
	clone.Visible = true
	local textLabel = clone:FindFirstChild("stat_text", true)
	if textLabel and textLabel:IsA("TextLabel") then
		if type(value) == "number" then
			-- arredondar
			value = math.floor(value + 0.5)
		end
		local displayName = statName
		if statName == "potencial" then
			displayName = "Potencial" -- capital P
		elseif statName == "BaseDamage" then
			displayName = "Damage"
		end
		textLabel.Text = string.format("%s: %s", displayName, tostring(value))
	end
	-- Se for a linha de potencial, aplicar gradiente por tier
	if statName == "potencial" then
		local tierName = tostring(value)
		-- Map de cores por NOME de tier (exatos de CharacterTiers.TierOrder)
		local TierColorByName = {
			["B-"] = Color3.fromRGB(130,130,130),
			["B"]  = Color3.fromRGB(145,145,145),
			["B+"] = Color3.fromRGB(170,170,170),
			["A-"] = Color3.fromRGB(90,170,90),
			["A"]  = Color3.fromRGB(70,200,90),
			["A+"] = Color3.fromRGB(60,210,120),
			["S-"] = Color3.fromRGB(70,140,255),
			["S"]  = Color3.fromRGB(60,120,255),
			["S+"] = Color3.fromRGB(50,100,255),
			["SS"] = Color3.fromRGB(200,90,255),
			["SSS"] = Color3.fromRGB(255,180,60),
		}
		local base = TierColorByName[tierName] or Color3.fromRGB(255,255,255)
		local h,s,v = base:ToHSV()
		-- Mais contraste
		local lighter = Color3.fromHSV(h, math.clamp(s*0.2,0,1), 1)
		local darker = Color3.fromHSV(h, s, math.max(v*0.18, 0.05))
		local grad = clone:FindFirstChild("TierGradient")
		if not grad then
			grad = Instance.new("UIGradient")
			grad.Name = "TierGradient"
			grad.Rotation = 90 -- vertical como outros
			grad.Parent = clone
		end
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, lighter),
			ColorSequenceKeypoint.new(0.45, base),
			ColorSequenceKeypoint.new(1, darker),
		})
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 0),
		})
		clone.BackgroundColor3 = base
		clone.BackgroundTransparency = 0
	end
	clone.Parent = previewScroll
end

local selectedInstanceId = nil
local currentSelectedIcon = nil -- para destaque visual
local equippedSet = nil -- cache para lookup O(1)

-- Wrapper mais robusto que recalcula se necessário e faz fallback à lista
local function computeIsEquipped(id)
	if not id then return false end
	if not equippedSet then rebuildEquippedSet() end
	if equippedSet and equippedSet[id] then return true end
	-- fallback varre lista se set não tem
	if currentInventory and currentInventory.EquippedOrder then
		for _, eid in ipairs(currentInventory.EquippedOrder) do
			if eid == id then
				-- atualizar cache para futuras
				equippedSet = equippedSet or {}
				equippedSet[id] = true
				return true
			end
		end
	end
	return false
end

local function rebuildEquippedSet()
	equippedSet = {}
	if currentInventory and currentInventory.EquippedOrder then
		for i, eid in ipairs(currentInventory.EquippedOrder) do
			if type(eid) == "string" then
				equippedSet[eid] = true
			end
		end
	end
end

-- Util para verificar se instância está equipada
local function isInstanceEquipped(id)
	if not id then return false end
	if not equippedSet then rebuildEquippedSet() end
	return equippedSet[id] == true
end

-- Paleta por número de estrelas (mover para antes de updatePreview para evitar nil)
local StarColors = {
	[1] = Color3.fromRGB(130,130,130), -- Comum
	[2] = Color3.fromRGB(90,170,90),
	[3] = Color3.fromRGB(70,130,255), -- Azul
	[4] = Color3.fromRGB(180,85,255), -- Roxo
	[5] = Color3.fromRGB(255,190,40), -- Dourado
	[6] = Color3.fromRGB(255,50,50), -- Vermelho (6+)
}
local function colorForStars(stars)
	return StarColors[stars] or Color3.fromRGB(255,255,255)
end

-- Helper para aplicar (ou atualizar) um UIGradient de raridade num frame alvo
local function ensureStarGradient(targetFrame, baseColor)
	if not targetFrame or not baseColor then return end
	local grad = targetFrame:FindFirstChild("StarGradient")
	local h,s,v = baseColor:ToHSV()
	-- Contraste mais forte: topo bem claro, meio cor base, fundo bem escuro
	local lighter = Color3.fromHSV(h, math.clamp(s * 0.15, 0, 1), 1) -- força value máximo
	local darkerV = math.max(v * 0.15, 0.05)
	local darker = Color3.fromHSV(h, s, darkerV)
	if not grad then
		grad = Instance.new("UIGradient")
		grad.Name = "StarGradient"
		grad.Rotation = 0
		grad.Parent = targetFrame
	end
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, lighter),
		ColorSequenceKeypoint.new(0.45, baseColor),
		ColorSequenceKeypoint.new(1, darker),
	})
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 0),
	})
	-- Garantir que o frame mostra o gradiente (não totalmente transparente)
	if targetFrame:IsA("Frame") then
		targetFrame.BackgroundColor3 = baseColor
		targetFrame.BackgroundTransparency = 0
	end
	return grad
end

local function updatePreview(inst)
	if not inst then return end
	if not preview.Visible then
		preview.Visible = true
	end
	selectedInstanceId = inst.Id
	-- Tornar o id selecionado acessível a outras UIs (ex: Cards) via atributo
	script:SetAttribute("SelectedInstanceId", selectedInstanceId)
	local cat = inst.Catalog or {}
	local stars = cat.stars or 0
	local starColor = colorForStars(stars)

	-- Aplicar / atualizar gradient em EQ_BG (sem recriar sempre)
	if eqBg then
		ensureStarGradient(eqBg, starColor)
		print("[CharsUI] Gradient EQ_BG atualizado (stars=" .. tostring(stars) .. ")")
	else
		warn("[CharsUI] eqBg não encontrado para aplicar gradient")
	end

	-- Destaque do ícone selecionado no inventário
	local iconFrame = scrolling:FindFirstChild(inst.Id)
	if iconFrame then
		-- Auto scroll (refatorado): usar posição relativa + AbsoluteCanvasSize
		local canvasPos = scrolling.CanvasPosition
		local canvasSizeY
		-- Tentar obter tamanho real do canvas considerando escala/offset
		if scrolling.AbsoluteCanvasSize then
			canvasSizeY = scrolling.AbsoluteCanvasSize.Y
		else
			-- fallback aproximado
			canvasSizeY = (scrolling.CanvasSize.Y.Offset or 0)
		end
		local windowHeight = (scrolling.AbsoluteWindowSize and scrolling.AbsoluteWindowSize.Y) or scrolling.AbsoluteSize.Y
		-- Converter posição absoluta do item para coordenada dentro do canvas
		-- Fórmula: posiçãoRelativa = (iconTopAbs - scrollTopAbs) + canvasPos.Y
		local iconTopAbs = iconFrame.AbsolutePosition.Y
		local scrollTopAbs = scrolling.AbsolutePosition.Y
		local iconTopInCanvas = (iconTopAbs - scrollTopAbs) + canvasPos.Y
		local iconBottomInCanvas = iconTopInCanvas + iconFrame.AbsoluteSize.Y
		local margin = 6
		local targetY = canvasPos.Y
		local needsScroll = false
		if iconTopInCanvas < targetY + margin then
			-- mover para cima (mostrar topo do ícone - margem)
			targetY = iconTopInCanvas - margin
			needsScroll = true
		elseif iconBottomInCanvas > targetY + windowHeight - margin then
			-- mover para baixo (alinhar fundo menos margem)
			targetY = iconBottomInCanvas - windowHeight + margin
			needsScroll = true
		end
		if needsScroll then
			local maxY = math.max(0, canvasSizeY - windowHeight)
			-- Se o fundo do ícone já está dentro do limiar dos últimos 1.2 ícones, força até o final
			local iconHeight = iconFrame.AbsoluteSize.Y
			local threshold = (windowHeight * 0.5) -- fallback se não conseguir medir múltiplos ícones
			if iconHeight > 0 then
				threshold = iconHeight * 1.2
			end
			local distanceToEnd = (canvasSizeY - iconBottomInCanvas)
			if distanceToEnd <= threshold then
				-- Com padding garantido, podemos simplesmente alinhar topo ou ir ao máximo.
				local desiredTop = iconTopInCanvas - margin
				targetY = math.clamp(desiredTop, 0, maxY)
			else
				targetY = math.clamp(targetY, 0, maxY)
			end
			local tweenInfoScroll = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			pcall(function()
				TweenService:Create(scrolling, tweenInfoScroll, { CanvasPosition = Vector2.new(canvasPos.X, targetY) }):Play()
			end)
		end
		-- Reverter anterior
		if currentSelectedIcon and currentSelectedIcon ~= iconFrame then
			local prevStroke = currentSelectedIcon:FindFirstChildWhichIsA("UIStroke")
			if prevStroke and prevStroke:GetAttribute("OrigThickness") then
				prevStroke.Thickness = prevStroke:GetAttribute("OrigThickness")
			end
		end
		local stroke = iconFrame:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			if not stroke:GetAttribute("OrigThickness") then
				stroke:SetAttribute("OrigThickness", stroke.Thickness)
			end
			stroke.Thickness = (stroke:GetAttribute("OrigThickness") or stroke.Thickness) + 2
		else
			-- fallback: adicionar overlay simples se não houver stroke
			local overlay = iconFrame:FindFirstChild("SelectedOverlay")
			if not overlay then
				overlay = Instance.new("Frame")
				overlay.Name = "SelectedOverlay"
				overlay.BackgroundColor3 = Color3.new(1,1,1)
				overlay.BackgroundTransparency = 0.85
				overlay.BorderSizePixel = 0
				overlay.Size = UDim2.new(1,0,1,0)
				overlay.ZIndex = 50
				overlay.Parent = iconFrame
			end
		end
		currentSelectedIcon = iconFrame
	end
	if previewCharName and previewCharName:IsA("TextLabel") then
		previewCharName.Text = (cat.displayName or inst.TemplateName or "?") .. string.format(" [Lv %d]", inst.Level or 1)
	end
	if previewIconImage then
		if cat.icon_id and cat.icon_id ~= "rbxassetid://0" then
			previewIconImage.Image = cat.icon_id
		else
			previewIconImage.Image = "rbxassetid://0"
		end
	end
	-- Limpar linhas antigas e adicionar primeiro a linha de potencial como clone
	clearStats()
	local tierValue = inst.Tier or (inst.Preview and inst.Preview.Tier) or "?"
	-- Agora sem parênteses: Potencial: X
	addStatLine("potencial", tostring(tierValue))
	-- Apenas stats da tabela Stats (já processados em inst.Preview.Stats)
	local stats = (inst.Preview and inst.Preview.Stats) or {}
	for k,v in pairs(stats) do
		addStatLine(k, v)
	end

	-- Atualizar visibilidade dos botões Equip / Unequip usando util
	local isEquipped = computeIsEquipped(inst.Id)
	if equipButton then equipButton.Visible = not isEquipped end
	if unequipButton then unequipButton.Visible = isEquipped end
	if sellButton then
		-- não permitir vender se equipado
		sellButton.AutoButtonColor = not isEquipped
		sellButton.Active = not isEquipped
		sellButton.Selectable = not isEquipped
		if isEquipped then
			sellButton.ImageColor3 = Color3.fromRGB(120,120,120)
		else
			sellButton.ImageColor3 = Color3.fromRGB(255,255,255)
		end
	end
end

-- Ligações dos botões Equip / Unequip
if equipButton and equipButton:IsA("ImageButton") and EquipOneRE then
	equipButton.MouseButton1Click:Connect(function()
		if not selectedInstanceId then
			warn("[CharsUI] Nenhum personagem selecionado para equipar")
			return
		end
		print("[CharsUI] Pedido EquipOne ->", selectedInstanceId)
		EquipOneRE:FireServer(selectedInstanceId)
	end)
end

if unequipButton and unequipButton:IsA("ImageButton") and UnequipOneRE then
	unequipButton.MouseButton1Click:Connect(function()
		if not selectedInstanceId then
			warn("[CharsUI] Nenhum personagem selecionado para desequipar")
			return
		end
		print("[CharsUI] Pedido UnequipOne ->", selectedInstanceId)
		UnequipOneRE:FireServer(selectedInstanceId)
	end)
end

-- Configuração de venda
local function goldForStars(stars)
	-- Use fixed rarity mapping requested by the user:
	-- comum = 100, raro = 500, epico = 1000, lendario = 2500
	-- Map stars -> rarity: 1 -> comum, 2 -> raro, 3 -> epico, 4+ -> lendario
	local t = {100, 500, 1000, 2500, 5000, 10000}
	if not stars or type(stars) ~= "number" then return 0 end
	local idx = math.floor(stars)
	if idx < 1 then return 0 end
	if idx > #t then idx = #t end
	return t[idx]
end

local pendingSellId = nil
local function openSellConfirm(inst)
	if not sellPanel or not inst then return end
	if sellAnimating then return end
	local cat = inst.Catalog or {}
	local stars = cat.stars or 0
	-- Derive final display string from stars using the fixed mapping
	local function displayForStars(starsVal)
		local t = {
			[1] = "comum 100coins",
			[2] = "raro 500",
			[3] = "epico 1000",
			[4] = "lendario 2500",
			[5] = "lendario 5000",
			[6] = "lendario 10000",
		}
		local s = (type(starsVal) == "number") and math.max(1, math.floor(starsVal)) or 1
		if s > 6 then s = 6 end
		return t[s]
	end
	local goldDisplay = displayForStars(stars)
	pendingSellId = inst.Id
	sellPanel.Visible = true
	-- Animação: começar fora do ecrã (acima), deslizar para posição atual
	local finalPos = sellPanel.Position
	local absY = sellPanel.AbsoluteSize.Y
	if absY == 0 then
		task.wait() -- esperar layout
		absY = sellPanel.AbsoluteSize.Y
	end
	if absY == 0 then absY = 300 end
	local startPos = UDim2.new(finalPos.X.Scale, finalPos.X.Offset, -1, -absY)
	sellPanel.Position = startPos
	sellAnimating = true
	pcall(function()
		TweenService:Create(sellPanel, TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = finalPos }):Play()
	end)
	task.delay(0.32, function()
		sellAnimating = false
	end)
	-- Texto 1: Nome personagem
	if sellText1 and sellText1:IsA("TextLabel") then
		local name = (cat.displayName or inst.TemplateName or "Personagem")
		sellText1.Text = string.format("Do you want to sell %s for", name)
	end
	-- Texto 2: Valor em gold
	if sellText2 and sellText2:IsA("TextLabel") then
		sellText2.Text = goldDisplay
	end
end

-- ==== Space Upgrade Panel (similar animações ao Sell) ====
local function openSpacePanel()
	if not spacePanel then return end
	if spaceAnimating then return end
	spacePanel.Visible = true
	local finalPos = spacePanel.Position
	local absY = spacePanel.AbsoluteSize.Y
	if absY == 0 then task.wait() absY = spacePanel.AbsoluteSize.Y end
	if absY == 0 then absY = 300 end
	local startPos = UDim2.new(finalPos.X.Scale, finalPos.X.Offset, -1, -absY)
	spacePanel.Position = startPos
	spaceAnimating = true
	pcall(function()
		TweenService:Create(spacePanel, TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = finalPos }):Play()
	end)
	task.delay(0.32, function() spaceAnimating = false end)
end

local function closeSpacePanel()
	if not spacePanel or not spacePanel.Visible or spaceAnimating then return end
	local finalPos = spacePanel.Position
	local absY = spacePanel.AbsoluteSize.Y
	if absY == 0 then absY = 300 end
	local offPos = UDim2.new(finalPos.X.Scale, finalPos.X.Offset, -1, -absY)
	spaceAnimating = true
	pcall(function()
		local tw = TweenService:Create(spacePanel, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = offPos })
		tw:Play()
		tw.Completed:Connect(function()
			spacePanel.Visible = false
			spacePanel.Position = finalPos
			spaceAnimating = false
		end)
	end)
end

local function closeSellConfirm()
	if not sellPanel or not sellPanel.Visible or sellAnimating then return end
	local finalPos = sellPanel.Position
	local absY = sellPanel.AbsoluteSize.Y
	if absY == 0 then absY = 300 end
	local offPos = UDim2.new(finalPos.X.Scale, finalPos.X.Offset, -1, -absY)
	sellAnimating = true
	pcall(function()
		local tw = TweenService:Create(sellPanel, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = offPos })
		tw:Play()
		tw.Completed:Connect(function()
			sellPanel.Visible = false
			sellPanel.Position = finalPos
			sellAnimating = false
		end)
	end)
	pendingSellId = nil
end

if sellButton and sellButton:IsA("ImageButton") then
	sellButton.MouseButton1Click:Connect(function()
		if not selectedInstanceId or not currentInventory or not currentInventory.Instances then
			warn("[CharsUI] Sell clicado sem seleção ou inventário.")
			return
		end
		local inst = currentInventory.Instances[selectedInstanceId]
		if not inst then return end
		if computeIsEquipped(inst.Id) then
			warn("[CharsUI] Não podes vender um personagem equipado")
			return
		end
		openSellConfirm(inst)
	end)
end

if sellNoButton and sellNoButton:IsA("ImageButton") then
	sellNoButton.MouseButton1Click:Connect(function()
		closeSellConfirm()
	end)
end

if sellYesButton and sellYesButton:IsA("ImageButton") then
    sellYesButton.MouseButton1Click:Connect(function()
        if not pendingSellId then return end
        if not SellCharacterRE then
            warn("[CharsUI] Remote SellCharacter não encontrado")
            closeSellConfirm()
            return
        end
        local sellingId = pendingSellId -- guardar antes de fechar (closeSellConfirm zera)
        print("[CharsUI] Pedido venda personagem ->", sellingId)
        SellCharacterRE:FireServer(sellingId)
        closeSellConfirm()
        -- Optimistic UI update segura usando sellingId
		if currentInventory and currentInventory.Instances and currentInventory.Instances[sellingId] then
            currentInventory.Instances[sellingId] = nil
            if currentInventory.OrderedList then
                for i = #currentInventory.OrderedList, 1, -1 do
                    local inst = currentInventory.OrderedList[i]
                    if inst and inst.Id == sellingId then
                        table.remove(currentInventory.OrderedList, i)
                        break
                    end
                end
            end
            if currentInventory.CurrentCount and currentInventory.CurrentCount > 0 then
                currentInventory.CurrentCount -= 1
            else
                local c = 0
                for _ in pairs(currentInventory.Instances) do c += 1 end
                currentInventory.CurrentCount = c
            end
            local iconFrame = scrolling:FindFirstChild(sellingId)
            if iconFrame then iconFrame:Destroy() end
            updateInvSpaceLabel()
        end
		updateInvSpaceLabel() -- garantir mesmo que não encontrou inst
        if selectedInstanceId == sellingId then
            selectedInstanceId = nil
            if preview then preview.Visible = false end
        end
    end)
end

-- Botão para abrir a UI de cartas deste personagem
if cardButton and cardButton:IsA("ImageButton") then
	cardButton.MouseButton1Click:Connect(function()
		if not selectedInstanceId then
			warn("[CharsUI] Card_b clicado sem personagem selecionado")
			return
		end
		if not currentInventory or not currentInventory.Instances then
			warn("[CharsUI] Inventory ainda não disponível para abrir cartas")
			return
		end
		local inst = currentInventory.Instances[selectedInstanceId]
		if not inst then
			warn("[CharsUI] Instância selecionada não encontrada no inventário")
			return
		end
		local sourceId = inst.TemplateName or (inst.Catalog and inst.Catalog.templateName) or inst.Id
		local Players = game:GetService("Players")
		local localPlayer = Players.LocalPlayer
		if not localPlayer then return end
		local playerGui = localPlayer:FindFirstChild("PlayerGui")
		if not playerGui then return end

		-- Robust finder for the Cards ScreenGui: prefer exact name, otherwise search heuristics
		local function findCardsScreenGui()
			-- 1) direct by name
			local cg = playerGui:FindFirstChild("Cards")
			if cg and cg:IsA("ScreenGui") then return cg end
			-- 2) any ScreenGui that contains the common Cards root '2nd' or 'yup'
			for _, g in ipairs(playerGui:GetChildren()) do
				if g and g:IsA("ScreenGui") then
					if g:FindFirstChild("2nd", true) or g:FindFirstChild("yup", true) then
						return g
					end
				end
			end
			-- 3) any ScreenGui whose name looks like cards (case-insensitive)
			for _, g in ipairs(playerGui:GetChildren()) do
				if g and g:IsA("ScreenGui") then
					local lname = tostring(g.Name):lower()
					if string.find(lname, "card") then return g end
				end
			end
			return nil
		end

		local cardsGui = findCardsScreenGui()
		if not cardsGui then
			-- debug: list PlayerGui children to assist diagnosis
			local names = {}
			for _, c in ipairs(playerGui:GetChildren()) do table.insert(names, tostring(c.Name) .. "/" .. tostring(c.ClassName)) end
			warn("[CharsUI] ScreenGui 'Cards' não encontrado. PlayerGui children:", table.concat(names, ", "))
			return
		end

		-- Set the attribute and enable the GUI; use a small retry if the child root is created shortly after enable
		local function enableAndShow(g)
			pcall(function() g:SetAttribute("ShowCharacterCards", sourceId) end)
			pcall(function() g.Enabled = true end)
			print(string.format("[CharsUI] Requested Cards UI on %s for sourceId=%s", tostring(g.Name), tostring(sourceId)))
			-- If the Cards script hasn't processed the attribute yet (e.g., waits for children), try again shortly
			task.delay(0.07, function()
				if g and g.Parent then
					pcall(function() g:SetAttribute("ShowCharacterCards", sourceId) end)
				end
			end)
		end

		enableAndShow(cardsGui)
	end)
end

-- (currentInventory já declarado em topo antes das funções)
local didInitialFetch = false
local profileUpdatedEvent

local function clearIcons()
	for _, child in ipairs(scrolling:GetChildren()) do
		if child:IsA("Frame") and child ~= template then
			child:Destroy()
		end
	end
end

local function createIcon(inst)
	if not inst then
		warn("[CharsUI] createIcon recebeu inst nil")
		return
	end
	local cat = inst.Catalog or {}
	local clone = template:Clone()
	clone.Name = inst.Id or (inst.TemplateName .. "_?" )
	clone.Visible = true
	local stars = cat.stars or 0
	local starColor = colorForStars(stars)
	clone.BackgroundColor3 = starColor

	-- NÃO alterar a cor do stroke (pedido do utilizador) – apenas deixamos como está.

	-- Aplicar / recriar um gradient de fundo baseado na cor das estrelas
	local existingGrad = clone:FindFirstChild("StarGradient")
	if existingGrad then
		existingGrad:Destroy()
	end
	local grad = Instance.new("UIGradient")
	grad.Name = "StarGradient"
	grad.Rotation = 90 -- vertical
	-- Derivar variantes (mais clara e mais escura) a partir da cor base
	local h,s,v = starColor:ToHSV()
	local lighter = Color3.fromHSV(h, math.clamp(s * 0.35, 0, 1), math.min(1, v * 1.25))
	local darker = Color3.fromHSV(h, s, math.clamp(v * 0.35, 0, 1))
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, lighter),
		ColorSequenceKeypoint.new(0.45, starColor),
		ColorSequenceKeypoint.new(1, darker),
	})
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 0),
	})
	grad.Parent = clone
	local levelLabel = clone:FindFirstChild("Level", true)
	if levelLabel and levelLabel:IsA("TextLabel") then
		levelLabel.Text = string.format("Lv %d", inst.Level or 1)
	end
	-- Ícone: procurar um ImageLabel (prioriza filho direto chamado Icon ou ImageLabel)
	local iconImage = clone:FindFirstChild("Icon") or clone:FindFirstChild("ImageLabel")
	if not iconImage then
		-- fallback: primeira ImageLabel em descendentes
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("ImageLabel") then iconImage = d break end
		end
	end
	if iconImage and cat.icon_id and cat.icon_id ~= "rbxassetid://0" then
		iconImage.Image = cat.icon_id
	elseif iconImage then
		iconImage.Image = "rbxassetid://0" -- placeholder (podes mudar para outro id padrão)
	end

	-- Clique para selecionar: usar Icon_b (ImageButton) dentro do inv_icon
	local clickTarget = clone:FindFirstChild("Icon_b")
	if clickTarget and clickTarget:IsA("ImageButton") then
		clickTarget.MouseButton1Click:Connect(function()
			updatePreview(inst)
		end)
	else
		-- fallback: se não existir Icon_b mas temos o frame, podemos ligar no próprio clone
		clone.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				updatePreview(inst)
			end
		end)
	end
	clone:SetAttribute("DisplayName", cat.displayName or inst.TemplateName or "?")
	clone:SetAttribute("Stars", stars)
	clone.Parent = scrolling
	print(string.format("[CharsUI] Icon criado -> id=%s name=%s stars=%d level=%s", tostring(inst.Id), tostring(cat.displayName or inst.TemplateName), stars, tostring(inst.Level)))
end

local function renderInventory()
	if not currentInventory then
		print("[CharsUI] renderInventory chamado sem currentInventory")
		return
	end
	local list = currentInventory.OrderedList or {}
	clearIcons()
	for i, inst in ipairs(list) do
		createIcon(inst)
	end
	print("[CharsUI] renderInventory concluiu. Total=", #list)

	-- Overscroll padding: garantir espaço extra depois da última linha
	-- Para garantir cálculo correto após Roblox definir AbsolutePosition/Size, fazer passes assíncronos.
	local function recomputePadding(pass)
		local maxBottom = 0
		for _, child in ipairs(scrolling:GetChildren()) do
			if child:IsA("Frame") and child ~= template and child.Visible then
				local bottom = child.AbsolutePosition.Y + child.AbsoluteSize.Y
				if bottom > maxBottom then maxBottom = bottom end
			end
		end
		if maxBottom > 0 then
			local scrollTop = scrolling.AbsolutePosition.Y
			local contentHeight = (maxBottom - scrollTop)
			local windowHeight = (scrolling.AbsoluteWindowSize and scrolling.AbsoluteWindowSize.Y) or scrolling.AbsoluteSize.Y
			-- Novo critério: garantir pelo menos 1 janela extra completa de espaço vazio abaixo
			local desiredSpare = windowHeight -- 1x janela
			local extra = math.max(desiredSpare, math.floor(windowHeight * 0.30))
			local finalHeight = contentHeight + extra
			-- Se finalHeight < contentHeight + windowHeight, força para content + windowHeight
			if finalHeight < contentHeight + windowHeight then
				finalHeight = contentHeight + windowHeight
			end
			local currentCanvasX = scrolling.CanvasSize.X
			local scaleY = scrolling.CanvasSize.Y.Scale
			local newCanvasSize = UDim2.new(currentCanvasX.Scale, currentCanvasX.Offset, scaleY, finalHeight)
			if finalHeight > windowHeight and (finalHeight > scrolling.CanvasSize.Y.Offset) then
				scrolling.CanvasSize = newCanvasSize
				if pass == 1 then
					print(string.format("[CharsUI] Overscroll pass1 aplicado: final=%d window=%d", finalHeight, windowHeight))
				else
					print(string.format("[CharsUI] Overscroll pass%d refine: final=%d", pass, finalHeight))
				end
			end
		end
	end
	-- Passo imediato (pode ainda não ter sizes finais)
	recomputePadding(1)
	-- Próximo frame (Heartbeat) para garantir layout resolvido
	RunService.Heartbeat:Wait()
	recomputePadding(2)
	-- Defer extra pequena para casos de latência
	task.delay(0.05, function() recomputePadding(3) end)
	-- Atualizar badges após reconstruir
	if currentInventory and currentInventory.EquippedOrder then
		for _, id in ipairs(currentInventory.EquippedOrder) do
			local iconFrame = scrolling:FindFirstChild(id)
			if iconFrame then
				-- reaplicar (a função foi definida dentro de createIcon; se quisermos reutilizar fora, recriamos mini lógica aqui)
				local badge = iconFrame:FindFirstChild("EquipBadge")
				if not badge then
					-- replicar criação rápida (sem duplicar sombras se já existir)
					-- para evitar duplicar código grande, apenas chama createIcon se quisermos, mas isso recriaria tudo
					-- então simplificamos: se não existe badge e está equipado, vamos gerar minimal badge via função local inline
					local function createBadge(parent)
						local b = Instance.new("Frame")
						b.Name = "EquipBadge"
						b.AnchorPoint = Vector2.new(1,0)
						b.Size = UDim2.fromScale(0.28, 0.28)
						b.Position = UDim2.new(1, -2, 0, 2)
						b.BackgroundTransparency = 1
						b.ZIndex = 120
						b.Parent = parent
						local function createShadow(offsetX, offsetY)
							local s = Instance.new("TextLabel")
							s.Name = "S"
							s.AnchorPoint = Vector2.new(0.5,0.5)
							s.Position = UDim2.new(0.5, offsetX, 0.5, offsetY)
							s.Size = UDim2.fromScale(1,1)
							s.BackgroundTransparency = 1
							s.Text = "E"
							s.Font = Enum.Font.FredokaOne
							s.TextScaled = true
							s.TextColor3 = Color3.new(0,0,0)
							s.ZIndex = 121
							s.Parent = b
						end
						local offsets = { {-2,0},{2,0},{0,-2},{0,2},{-2,-2},{2,-2},{-2,2},{2,2} }
						for _, off in ipairs(offsets) do createShadow(off[1], off[2]) end
						local main = Instance.new("TextLabel")
						main.Name = "Main"
						main.AnchorPoint = Vector2.new(0.5,0.5)
						main.Position = UDim2.new(0.5,0,0.5,0)
						main.Size = UDim2.fromScale(1,1)
						main.BackgroundTransparency = 1
						main.Text = "E"
						main.Font = Enum.Font.FredokaOne
						main.TextScaled = true
						main.TextColor3 = Color3.fromRGB(255,40,40)
						main.ZIndex = 122
						main.Parent = b
					end
					createBadge(iconFrame)
				end
			end
		end
	end

	-- Atualizar indicador de espaço (occupied/total)
	updateInvSpaceLabel()
end

local function fetchInventory()
	print("[CharsUI] fetchInventory iniciando...")
	local ok, res = pcall(function()
		return GetCharacterInventoryRF:InvokeServer()
	end)
	if not ok then
		warn("[CharsUI] Falha a obter inventário:", res)
		return
	end
	if res and res.inventory then
		currentInventory = res.inventory
		-- Garantir que Capacity e CurrentCount existem (retrocompatibilidade)
		if not currentInventory.Capacity then currentInventory.Capacity = (res.inventory.Capacity or 50) end
		if not currentInventory.CurrentCount then
			local c = 0
			for _ in pairs(currentInventory.Instances or {}) do c += 1 end
			currentInventory.CurrentCount = c
		end
		rebuildEquippedSet()
		if currentInventory and currentInventory.EquippedOrder then
			local dbg = table.concat(currentInventory.EquippedOrder, ",")
			print("[CharsUI] EquippedOrder (fetch) =", dbg)
		end
		local ordered = (currentInventory and currentInventory.OrderedList) or {}
		print("[CharsUI] Inventário recebido. OrderedList tamanho=", #ordered)
		renderInventory()
		updateInvSpaceLabel() -- garantir label logo após render
		-- Se já havia uma seleção (raro em fetch inicial, mas para consistência)
		if selectedInstanceId and currentInventory and currentInventory.Instances then
			local inst = currentInventory.Instances[selectedInstanceId]
			if inst then
				updatePreview(inst)
			end
		end
	else
		print("[CharsUI] Resposta de inventário vazia ou sem campo 'inventory'")
	end
	didInitialFetch = true
end

-- Atualização incremental via ProfileUpdated (recebe Instances completos ou Updated diffs)
local function onProfileUpdated(payload)
	if not didInitialFetch then return end -- só depois do primeiro fetch
	if not payload then return end
	-- Novo: snapshot completo (ex: após venda) -> refetch para reconstruir inventário + espaço
	if payload.full then
		fetchInventory()
		return
	end
	if not payload.characters then return end
	local chars = payload.characters

	-- Atualizar EquippedOrder local se veio no payload
	if chars.EquippedOrder then
		currentInventory = currentInventory or {}
		currentInventory.EquippedOrder = chars.EquippedOrder
		rebuildEquippedSet()
		print("[CharsUI] EquippedOrder atualizado:", table.concat(chars.EquippedOrder, ","))
		-- Atualizar badges para refletir novos estados
		for _, child in ipairs(scrolling:GetChildren()) do
			if child:IsA("Frame") and child ~= template then
				local id = child.Name
				local was = child:FindFirstChild("EquipBadge") ~= nil
				local now = computeIsEquipped(id)
				if now and not was then
					-- criar badge simples
					local b = Instance.new("Frame")
					b.Name = "EquipBadge"
					b.AnchorPoint = Vector2.new(1,0)
					b.Size = UDim2.fromScale(0.28, 0.28)
					b.Position = UDim2.new(1, -2, 0, 2)
					b.BackgroundTransparency = 1
					b.ZIndex = 120
					b.Parent = child
					local function createShadow(offsetX, offsetY)
						local s = Instance.new("TextLabel")
						s.Name = "S"
						s.AnchorPoint = Vector2.new(0.5,0.5)
						s.Position = UDim2.new(0.5, offsetX, 0.5, offsetY)
						s.Size = UDim2.fromScale(1,1)
						s.BackgroundTransparency = 1
						s.Text = "E"
						s.Font = Enum.Font.FredokaOne
						s.TextScaled = true
						s.TextColor3 = Color3.new(0,0,0)
						s.ZIndex = 121
						s.Parent = b
					end
					local offsets = { {-2,0},{2,0},{0,-2},{0,2},{-2,-2},{2,-2},{-2,2},{2,2} }
					for _, off in ipairs(offsets) do createShadow(off[1], off[2]) end
					local main = Instance.new("TextLabel")
					main.Name = "Main"
					main.AnchorPoint = Vector2.new(0.5,0.5)
					main.Position = UDim2.new(0.5,0,0.5,0)
					main.Size = UDim2.fromScale(1,1)
					main.BackgroundTransparency = 1
					main.Text = "E"
					main.Font = Enum.Font.FredokaOne
					main.TextScaled = true
					main.TextColor3 = Color3.fromRGB(255,40,40)
					main.ZIndex = 122
					main.Parent = b
				elseif was and not now then
					child.EquipBadge:Destroy()
				end
			end
		end
	end

	-- Mensagens específicas (ex: erros de venda / equip)
	if payload.msg and payload.msg.type == "sell_fail" then
		warn("[CharsUI] Falha ao vender personagem:", payload.msg.reason)
	end
	if chars.Instances then
		-- servidor mandou lista completa -> refazer tudo local
		if currentInventory and currentInventory.OrderedList then
			-- reconstruir map por Id para preservar ordem antiga se quiser (por agora substitui)
		end
		-- Força refetch para integrar dados de catálogo (Catalog / Stars) que este script espera
		fetchInventory()
		return
	end
	if chars.Updated then
		-- Temos atualizações parciais (ex: tier). Atualizar labels se existirem.
		for _, upd in ipairs(chars.Updated) do
			local frameIcon = scrolling:FindFirstChild(upd.Id)
			if frameIcon then
				if upd.Level and frameIcon:FindFirstChild("Level", true) then
					frameIcon.Level.Text = string.format("Lv %d", upd.Level)
				end
				-- Tier não altera cor por enquanto (cores baseadas em estrelas do catálogo)
			end
		end
	end

	-- Reavaliar botões caso EquippedOrder tenha mudado
	if selectedInstanceId then
		local equipped = computeIsEquipped(selectedInstanceId)
		if equipButton then equipButton.Visible = not equipped end
		if unequipButton then unequipButton.Visible = equipped end
		print(string.format("[CharsUI] Estado selecionado %s equipado=%s (setSize=%d)", selectedInstanceId, tostring(equipped), (currentInventory and currentInventory.EquippedOrder and #currentInventory.EquippedOrder) or -1))
		if equipped and not equippedSet[selectedInstanceId] then
			print("[CharsUI][WARN] equipped=true mas não consta no equippedSet -> reconstruindo...")
			rebuildEquippedSet()
			-- reforçar
			local eq2 = computeIsEquipped(selectedInstanceId)
			print("[CharsUI] Recheck após rebuild ->", eq2)
		end
	end
end

-- Animações de abrir/fechar
-- UI começa fechada/inativa
local isOpen = false
local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local hiddenPos = UDim2.new(frame.Position.X.Scale, frame.Position.X.Offset, 1.2, 0) -- fora da tela em baixo
local shownPos = frame.Position -- posição original

local function show()
	if not didInitialFetch then
		fetchInventory()
	end
	frame.Visible = true
	frame.Position = hiddenPos
	TweenService:Create(frame, tweenInfo, { Position = shownPos }):Play()
	isOpen = true
	script:SetAttribute("Show", true)
	script:SetAttribute("Hide", false)
	print("[CharsUI] Show anim")
	updateInvSpaceLabel() -- tentar já mostrar contador ao abrir
	-- Seleção pendente vinda de General (clique em slot equipado)
	local pending = script:GetAttribute("PendingSelectInstanceId")
	if pending and type(pending) == "string" and pending ~= "" then
		local function trySelect()
			if currentInventory then
				-- Garantir que Instances é map; se for array, converter
				if currentInventory.Instances and #currentInventory.Instances > 0 then
					local map = {}
					for _, inst in ipairs(currentInventory.Instances) do
						if inst and inst.Id then map[inst.Id] = inst end
					end
					currentInventory.Instances = map
				end
				if currentInventory.Instances and currentInventory.Instances[pending] then
					updatePreview(currentInventory.Instances[pending])
					return true
				end
			end
			return false
		end
		-- Tentativas escalonadas
		if not trySelect() then
			for i, delaySecs in ipairs({0.15,0.3,0.6,1.0}) do
				task.delay(delaySecs, function()
					if trySelect() then
						script:SetAttribute("PendingSelectInstanceId", nil)
					end
				end)
			end
			-- Limpa de qualquer modo depois de 1.2s para não ficar preso
			task.delay(1.25, function()
				if script:GetAttribute("PendingSelectInstanceId") == pending then
					-- última tentativa: refetch rápido e tentar uma vez
					fetchInventory()
					task.delay(0.15, function()
						if currentInventory and currentInventory.Instances and currentInventory.Instances[pending] then
							updatePreview(currentInventory.Instances[pending])
						end
						script:SetAttribute("PendingSelectInstanceId", nil)
					end)
				end
			end)
		else
			script:SetAttribute("PendingSelectInstanceId", nil)
		end
	end
end

local function hide()
	if not isOpen then return end
	isOpen = false
	local tw = TweenService:Create(frame, tweenInfo, { Position = hiddenPos })
	tw:Play()
	tw.Completed:Connect(function()
		if not isOpen then
			frame.Visible = false
			frame.Position = shownPos -- reset
		end
	end)
	script:SetAttribute("Hide", true)
	script:SetAttribute("Show", false)
	print("[CharsUI] Hide anim")
end

exitButton.MouseButton1Click:Connect(function()
	print("[CharsUI] Exit button pressed")
	hide()
	closeSellConfirm()
	closeSpacePanel()
end)

-- API simples para reabrir via outro script futuramente
script:SetAttribute("Show", false)
script:SetAttribute("Hide", false)
script:GetAttributeChangedSignal("Show"):Connect(function()
	if script:GetAttribute("Show") then show() end
end)
script:GetAttributeChangedSignal("Hide"):Connect(function()
	if script:GetAttribute("Hide") then hide() end
end)

-- Clique no frame Inv_space abre painel de upgrade (ou podes trocar para botão dedicado)
-- Agora o trigger é o botão Plus_space
if plusSpaceButton then
	if plusSpaceButton:IsA("ImageButton") then
		plusSpaceButton.MouseButton1Click:Connect(function()
			print("[CharsUI] Plus_space click -> abrir painel de espaço")
			openSpacePanel()
		end)
	else
		-- fallback para ImageLabel ou Frame
		plusSpaceButton.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				print("[CharsUI] Plus_space InputBegan -> abrir painel de espaço")
				openSpacePanel()
			end
		end)
	end
end

if spaceNoButton and spaceNoButton:IsA("ImageButton") then
	spaceNoButton.MouseButton1Click:Connect(function()
		closeSpacePanel()
	end)
end

if spaceYesButton and spaceYesButton:IsA("ImageButton") then
	spaceYesButton.MouseButton1Click:Connect(function()
		if not IncreaseCapacityRE then
			warn("[CharsUI] Remote IncreaseCapacity não encontrado")
			closeSpacePanel()
			return
		end
		-- Optimistic: aumentar capacidade local antes do server responder
		if currentInventory then
			currentInventory.Capacity = (currentInventory.Capacity or 50) + 25
			updateInvSpaceLabel()
		end
		IncreaseCapacityRE:FireServer()
		closeSpacePanel()
	end)
end

-- Inicializar
template.Visible = false -- garantir que template não aparece
preview.Visible = false -- ocultar preview até o jogador clicar num personagem
frame.Visible = false -- permanece oculto até algum script/setAttribute acionar Show
print("[CharsUI] Script inicializado. Aguardando Show...")

-- Listener para seleção pendente definida após abertura
script:GetAttributeChangedSignal("PendingSelectInstanceId"):Connect(function()
	local pending = script:GetAttribute("PendingSelectInstanceId")
	if pending and type(pending) == "string" and pending ~= "" then
		if currentInventory then
			if currentInventory.Instances and #currentInventory.Instances > 0 then
				local map = {}
				for _, inst in ipairs(currentInventory.Instances) do
					if inst and inst.Id then map[inst.Id] = inst end
				end
				currentInventory.Instances = map
			end
			if currentInventory.Instances and currentInventory.Instances[pending] then
				updatePreview(currentInventory.Instances[pending])
				script:SetAttribute("PendingSelectInstanceId", nil)
			end
		end
	end
end)

-- Conectar ProfileUpdated para updates incrementais
profileUpdatedEvent = Remotes:FindFirstChild("ProfileUpdated")
if profileUpdatedEvent and profileUpdatedEvent:IsA("RemoteEvent") then
	profileUpdatedEvent.OnClientEvent:Connect(onProfileUpdated)
	print("[CharsUI] Conectado a ProfileUpdated para updates incrementais.")
end

-- FUTURO: escutar ProfileUpdated para atualizar apenas diferenças