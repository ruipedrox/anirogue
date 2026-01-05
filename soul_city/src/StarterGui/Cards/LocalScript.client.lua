print("Hello world!")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Data modules
local CardPool = require(ReplicatedStorage.Scripts.CardPool)

local player = Players.LocalPlayer
local gui = script.Parent  -- ScreenGui Cards
local bg = gui:FindFirstChild("BG") -- novo container/overlay
local selectionLocked = false
local pendingServerCards = nil -- oferta enviada pelo servidor (se existir)
local isAnimating = false
local originalPositions = {}
local basePositions = {} -- posições fixas capturadas na primeira vez
local offscreenPositions = {} -- posições totalmente fora do ecrã para animação

-- Config: alternativa para animação off-screen usando Scale em vez de grande offset em pixels
local USE_SCALE_OFFSCREEN = true
local OFFSCREEN_MARGIN_SCALE = 0.3 -- quanto acima (valor adicional em Y.Scale) colocar o card antes de entrar
local ANIM_DEBUG = false
local overlayFrame = nil

-- Forward declarations (usados em showCards / animações antes da definição)
local offerCards
local connectClicks
local displayCards

-- Controlar visibilidade (caso seja Frame ou ScreenGui)
local function setGuiVisible(v)
    if gui:IsA("ScreenGui") then
        gui.Enabled = v
    elseif gui:IsA("GuiObject") then
        gui.Visible = v
    end
end

-- Cria (ou obtém) overlay de escurecimento
local function ensureOverlay()
    -- Se existir BG, usamos como overlay.
    if bg and bg:IsA("Frame") then
        overlayFrame = bg
        -- Garantir cor preta
        if (overlayFrame.BackgroundColor3.R + overlayFrame.BackgroundColor3.G + overlayFrame.BackgroundColor3.B) > 0 then
            overlayFrame.BackgroundColor3 = Color3.new(0,0,0)
        end
        return overlayFrame
    end
    -- fallback antigo
    if overlayFrame and overlayFrame.Parent == gui then return overlayFrame end
    overlayFrame = gui:FindFirstChild("_DarkOverlay")
    if not overlayFrame then
        overlayFrame = Instance.new("Frame")
        overlayFrame.Name = "_DarkOverlay"
        overlayFrame.BackgroundColor3 = Color3.new(0,0,0)
        overlayFrame.BackgroundTransparency = 1
        overlayFrame.Size = UDim2.fromScale(1,1)
        overlayFrame.Position = UDim2.fromScale(0,0)
        overlayFrame.ZIndex = 0
        overlayFrame.BorderSizePixel = 0
        overlayFrame.Active = false
        overlayFrame.Parent = gui
    end
    return overlayFrame
end

local function getCardFrames()
    local parent = bg or gui
    local c1 = parent:FindFirstChild("Card_1")
    local c2 = parent:FindFirstChild("Card_2")
    local c3 = parent:FindFirstChild("Card_3")
    return { c1, c2, c3 }
end

-- Se o card foi envolvido por um _ScaleWrap (para hover), animamos o wrap
local function getAnimObject(frame)
    if frame and frame.Parent and frame.Parent.Name == "_ScaleWrap" then
        return frame.Parent
    end
    return frame
end

local function prepareCardPositions(frames)
    table.clear(originalPositions)
    for _, f in ipairs(frames) do
        local animObj = getAnimObject(f)
        if animObj and animObj:IsA("GuiObject") then
            -- Centralizar anchor para animação previsível
            if animObj.AnchorPoint ~= Vector2.new(0.5,0.5) then
                local pos, size = animObj.Position, animObj.Size
                animObj.AnchorPoint = Vector2.new(0.5,0.5)
                animObj.Position = UDim2.new(
                    pos.X.Scale + size.X.Scale * 0.5,
                    pos.X.Offset + size.X.Offset * 0.5,
                    pos.Y.Scale + size.Y.Scale * 0.5,
                    pos.Y.Offset + size.Y.Offset * 0.5
                )
            end
            originalPositions[animObj] = animObj.Position
            if not basePositions[animObj] then
                basePositions[animObj] = animObj.Position
            end
            print(string.format("[CardsUI][PosCapture] %s -> %s", animObj.Name, tostring(animObj.Position)))
        end
    end
end

local function tween(obj, info, props)
    local tw = TweenService:Create(obj, info, props)
    tw:Play()
    return tw
end

local RunService = game:GetService("RunService")

local function animateShow(regenerate)
    if isAnimating then return end
    isAnimating = true
    selectionLocked = true

    ensureOverlay()
    -- Reset overlay transparency each show cycle
    if overlayFrame then overlayFrame.BackgroundTransparency = 1 end

    -- 1) Gerar OU mostrar cartas que já vieram do servidor
    if regenerate then
        if not pendingServerCards then
            print("[CardsUI] animateShow -> gerar local (sem pendingServerCards)")
            offerCards() -- offerCards já chama displayCards
        else
            print("[CardsUI] animateShow -> usar pendingServerCards (regenerate=true)")
            if displayCards then
                displayCards(pendingServerCards)
            else
                warn("[CardsUI] displayCards nil (1)")
            end
        end
    else
        if pendingServerCards then
            print("[CardsUI] animateShow -> usar pendingServerCards (regenerate=false)")
            if displayCards then
                displayCards(pendingServerCards)
            else
                warn("[CardsUI] displayCards nil (2)")
            end
        else
            -- Sem cartas server e sem regenerate: gerar local como fallback
            print("[CardsUI] animateShow -> fallback gerar local (sem pendingServerCards & regenerate=false)")
            offerCards()
        end
    end

    -- 2) Conectar cliques DEPOIS de aplicar cartas (garante CardId definido)
    connectClicks()

    setGuiVisible(true)
    if bg then bg.Visible = true end
    -- Esperar 1 frame para layouts aplicarem posições finais
    RunService.Heartbeat:Wait()

    local frames = getCardFrames()
    -- Restaurar para base antes de recapturar (para evitar drift acumulado)
    for _, frame in ipairs(frames) do
        local animObj = getAnimObject(frame)
        if animObj and basePositions[animObj] then
            animObj.Position = basePositions[animObj]
        end
    end
    prepareCardPositions(frames)

    table.clear(offscreenPositions)
    if USE_SCALE_OFFSCREEN then
        for _, frame in ipairs(frames) do
            local animObj = getAnimObject(frame)
            if animObj and animObj:IsA("GuiObject") then
                local targetPos = originalPositions[animObj]
                if targetPos then
                    -- Guardar posição final
                    offscreenPositions[animObj] = targetPos
                    -- Colocar acima usando aumento de Y.Scale (mantendo offset alvo)
                    local offPos = UDim2.new(targetPos.X.Scale, targetPos.X.Offset, targetPos.Y.Scale - (1 + OFFSCREEN_MARGIN_SCALE), targetPos.Y.Offset)
                    animObj.Position = offPos
                    if ANIM_DEBUG then
                        print(string.format("[CardsUI][ScaleOffscreen] %s start=%s final=%s", animObj.Name, tostring(offPos), tostring(targetPos)))
                    end
                    if overlayFrame and animObj.ZIndex <= overlayFrame.ZIndex then
                        animObj.ZIndex = overlayFrame.ZIndex + 1
                    end
                end
            end
        end
    else
        -- Fallback: cálculo em pixels (viewport) como antes
        local viewportY = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y or 1080
        for _, frame in ipairs(frames) do
            local animObj = getAnimObject(frame)
            if animObj and animObj:IsA("GuiObject") then
                local targetPos = originalPositions[animObj]
                if targetPos then
                    local absSizeY = animObj.AbsoluteSize.Y
                    local margem = 30
                    local offY = targetPos.Y.Offset - (viewportY + absSizeY + margem)
                    local offPos = UDim2.new(targetPos.X.Scale, targetPos.X.Offset, targetPos.Y.Scale, offY)
                    offscreenPositions[animObj] = offPos
                    animObj.Position = offPos
                    if overlayFrame and animObj.ZIndex <= overlayFrame.ZIndex then
                        animObj.ZIndex = overlayFrame.ZIndex + 1
                    end
                end
            end
        end
    end

    if overlayFrame then
        tween(overlayFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.45 })
    end

    local delayPer = 0.12
    -- Ordem personalizada de entrada: 2,1,3
    local orderIn = { frames[2], frames[1], frames[3] }
    for i, frame in ipairs(orderIn) do
        local animObj = getAnimObject(frame)
        if animObj and animObj:IsA("GuiObject") then
            task.delay((i-1)*delayPer, function()
                local targetPos = originalPositions[animObj]
                if targetPos then
                    tween(animObj, TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = targetPos })
                end
            end)
        end
    end

    task.delay(#frames*delayPer + 0.40, function()
        selectionLocked = false
        isAnimating = false
    end)
end

local function animateHide()
    if isAnimating then return end
    isAnimating = true
    selectionLocked = true
    local frames = getCardFrames()
    -- Garantir posições alvo (caso algo tenha mudado)
    if next(originalPositions) == nil then
        prepareCardPositions(frames)
    end
    local delayPer = 0.10
    -- Se ainda não temos offscreenPositions (primeira vez), construir rapidamente
    if next(offscreenPositions) == nil then
        -- Se por algum motivo não calculou (ex: falha antes), reconstruir com fallback pixel
        local viewportY = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y or 1080
        for _, frame in ipairs(frames) do
            local animObj = getAnimObject(frame)
            local targetPos = originalPositions[animObj]
            if animObj and targetPos then
                if USE_SCALE_OFFSCREEN then
                    offscreenPositions[animObj] = targetPos
                else
                    local absSizeY = animObj.AbsoluteSize.Y
                    local margem = 30
                    local offY = targetPos.Y.Offset - (viewportY + absSizeY + margem)
                    offscreenPositions[animObj] = UDim2.new(targetPos.X.Scale, targetPos.X.Offset, targetPos.Y.Scale, offY)
                end
            end
        end
    end
    -- Ordem personalizada de saída (inversa lógica): 3,1,2
    local orderOut = { frames[3], frames[1], frames[2] }
    for idx, f in ipairs(orderOut) do
        local animObj = getAnimObject(f)
        if animObj and animObj:IsA("GuiObject") then
            local offPos = offscreenPositions[animObj]
            if offPos then
                task.delay((idx-1)*delayPer, function()
                    if USE_SCALE_OFFSCREEN then
                        -- Em modo scale offscreen, mover para mesma X/offset mas reduzindo Y.Scale
                        local targetPos = originalPositions[animObj]
                        local hidePos = UDim2.new(targetPos.X.Scale, targetPos.X.Offset, targetPos.Y.Scale - (1 + OFFSCREEN_MARGIN_SCALE), targetPos.Y.Offset)
                        tween(animObj, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Position = hidePos })
                    else
                        tween(animObj, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Position = offPos })
                    end
                end)
            end
        end
    end
    -- Fade overlay depois que animações das cartas começaram
    local ov = ensureOverlay()
    if ov then
        tween(ov, TweenInfo.new(#frames*delayPer + 0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
    end
    -- Desligar GUI ao final
    task.delay(#frames*delayPer + 0.28, function()
        setGuiVisible(false)
        if bg then bg.BackgroundTransparency = 1 end
        selectionLocked = false
        isAnimating = false
    end)
end

local function hideCards()
    animateHide()
end

local function showCards(regenerate)
    print("[CardsUI] showCards chamado. regenerate=", regenerate)
    animateShow(regenerate ~= false)
end

-- Expect 3 frames named Card_1, Card_2, Card_3 each with Frame/Icon (ImageLabel), Frame/C_Name (TextLabel), Frame/Desc (TextLabel)
-- Adjust these paths if your hierarchy is different.

-- Obtém imagem diretamente da definição (def.image ou def.imageLevels) propagada via CardPool
local CARD_IMG_DEBUG = true

local function getImageFor(card)
    if not card then return nil end
    -- Generic multi-level image selection:
    -- If card.imageLevels exists, attempt to read current level from RunTrack using metadata in card._def.levelTracker.
    -- levelTracker fields:
    --   folder (string) -> child of RunTrack
    --   valueName (string, default 'Level') -> IntValue name
    --   showNextLevel (bool) -> if true, preview next level image (current+1) clamped
    -- Fallbacks: if can't resolve, use first imageLevels[1]; if no imageLevels, card.image.
    local imgLevels = card.imageLevels
    if type(imgLevels) == "table" and #imgLevels > 0 then
        local def = card._def
        local tracker = def and def.levelTracker
        local currentLevel = 0
        local showNext = false
        local maxLevels = #imgLevels
        if type(tracker) == "table" then
            local folderName = tracker.folder
            local valueName = tracker.valueName or "Level"
            showNext = tracker.showNextLevel == true
            local runTrack = player:FindFirstChild("RunTrack")
            local folder = runTrack and folderName and runTrack:FindFirstChild(folderName)
            local levelNV = folder and folder:FindFirstChild(valueName)
            if levelNV and levelNV:IsA("IntValue") then
                currentLevel = levelNV.Value
            end
        end
        local displayLevel = currentLevel
        if showNext then
            displayLevel = displayLevel + 1
        end
        displayLevel = math.clamp(displayLevel, 1, maxLevels)
        local chosen = imgLevels[displayLevel] or card.image or nil
        if CARD_IMG_DEBUG then
            print(string.format("[CardsUI][ImgSelect] id=%s current=%d showNext=%s display=%d chosen=%s", tostring(card.id), currentLevel, tostring(showNext), displayLevel, tostring(chosen)))
        end
        return chosen
    end
    return card.image or nil
end

-- Cores por raridade (UIStroke/Frame)
local RARITY_COLORS = {
    Legendary = Color3.fromRGB(255, 230, 0),    -- amarelo
    Epic      = Color3.fromRGB(170, 0, 255),    -- roxo
    Rare      = Color3.fromRGB(0, 140, 255),    -- azul
    Common    = Color3.fromRGB(0, 190, 60),     -- verde
}

local function styleFrame(card, frame)
    if not frame or not card then return end
    local contentFrame = frame:FindFirstChild("Frame") or frame
    local stroke = contentFrame:FindFirstChildOfClass("UIStroke")
    local rarity = card.rarity or "Common"
    local color = RARITY_COLORS[rarity] or RARITY_COLORS.Common
    -- NÃO alterar a cor do UIStroke (outline). Mantém a cor original definida no Studio.
    -- (Se no futuro quiseres reativar, basta descomentar a linha abaixo)
    -- if stroke then stroke.Color = color end
    -- Pintar o fundo conforme raridade (pedido: Legendary=amarelo, Epic=roxo, Rare=azul, Common=verde)
    if contentFrame:IsA("Frame") then
        contentFrame.BackgroundColor3 = color
        -- Shadow frame "FFF" (escurecido) – se existir dentro do contentFrame ou do cardFrame
            local shadow = contentFrame:FindFirstChild("FFF") or frame:FindFirstChild("FFF")
            if shadow and shadow:IsA("Frame") then
                -- Escurecer a cor multiplicando por fator (<1)
                local factor = 0.55
                local c = color
                shadow.BackgroundColor3 = Color3.new(c.R * factor, c.G * factor, c.B * factor)
                shadow.BackgroundTransparency = contentFrame.BackgroundTransparency
                -- Nota: o shadow (FFF) herda a escala porque está dentro da hierarquia que recebe UIScale (_HoverScale)
                -- Se algum card tiver FFF fora, mover para dentro do mesmo container que Icon/C_Name/Desc.
                local scaleHost = frame:FindFirstChild("_ScaleWrap") or frame
                if not shadow:IsDescendantOf(scaleHost) then
                    shadow.Parent = scaleHost
                end
                -- Converter para anchor central (0.5,0.5) preservando posição visual
                if shadow.AnchorPoint ~= Vector2.new(0.5,0.5) then
                    local pos, size = shadow.Position, shadow.Size
                    shadow.AnchorPoint = Vector2.new(0.5,0.5)
                    shadow.Position = UDim2.new(
                        pos.X.Scale + size.X.Scale * 0.5,
                        pos.X.Offset + size.X.Offset * 0.5,
                        pos.Y.Scale + size.Y.Scale * 0.5,
                        pos.Y.Offset + size.Y.Offset * 0.5
                    )
                end
        end
    end
end

local function wipeCardFrame(cardFrame)
    local frame = cardFrame:FindFirstChild("Frame") or cardFrame
    local icon = frame:FindFirstChild("Icon")
    local nameLabel = frame:FindFirstChild("C_Name")
    local descLabel = frame:FindFirstChild("Desc")
    if icon and icon:IsA("ImageLabel") then icon.Image = "" end
    if nameLabel and nameLabel:IsA("TextLabel") then nameLabel.Text = "" end
    if descLabel and descLabel:IsA("TextLabel") then descLabel.Text = "" end
end

local function applyCardToFrame(card, cardFrame)
    if not card or not cardFrame then return end
    local frame = cardFrame:FindFirstChild("Frame") or cardFrame
    local icon = frame:FindFirstChild("Icon")
    local nameLabel = frame:FindFirstChild("C_Name")
    local descLabel = frame:FindFirstChild("Desc")
    if icon and icon:IsA("ImageLabel") then
        local img = getImageFor(card)
        icon.Image = img or ""
        -- Garantir fundo transparente e modo de escala correto
        icon.BackgroundTransparency = 1
        if icon.ScaleType ~= Enum.ScaleType.Fit then
            icon.ScaleType = Enum.ScaleType.Fit
        end
    end
    if nameLabel and nameLabel:IsA("TextLabel") then
        nameLabel.Text = card.name or card.id or "?"
    end
    if descLabel and descLabel:IsA("TextLabel") then
        descLabel.Text = card.description or "Sem descrição"
    end
    -- Store card id for later click handling
    cardFrame:SetAttribute("CardId", card.id)
    -- Estilizar por raridade
    styleFrame(card, cardFrame)
end

-- Mostrar lista de cartas arbitrária (server-defined ou local)
displayCards = function(list)
    local frames = getCardFrames()
    for _, f in ipairs(frames) do if f then wipeCardFrame(f) end end
    for i, card in ipairs(list) do
        local frame = frames[i]
        if frame then applyCardToFrame(card, frame) end
    end
end

offerCards = function()
    -- Ask CardPool for all cards then locally pick 3 (client side). In production you may want the server to choose.
    local cards = CardPool:GetCardsForPlayer(player)
    if #cards == 0 then
        warn("[CardsUI] Nenhuma carta disponível")
        return
    end
    -- Shuffle simple
    for i = #cards, 2, -1 do
        local j = math.random(i)
        cards[i], cards[j] = cards[j], cards[i]
    end
    local offer = {}
    for i = 1, math.min(3, #cards) do offer[i] = cards[i] end

    displayCards(offer)
end

-- Hook up click events so selecting a card can be sent to server later
-- (TweenService declarado no topo)

local function attachHover(cardFrame)
    local frame = cardFrame:FindFirstChild("Frame") or cardFrame
    if not frame:IsA("GuiObject") then return end
    if frame:GetAttribute("_HoverBound") then return end
    frame:SetAttribute("_HoverBound", true)

    -- Escolher host para scaling: se o parent tiver UIListLayout, criamos um wrapper para não quebrar o layout.
    local parentHasList = cardFrame.Parent:FindFirstChildWhichIsA("UIListLayout") ~= nil
    local scaleHost = frame
    if parentHasList then
        if not cardFrame:FindFirstChild("_ScaleWrap") then
            local wrap = Instance.new("Frame")
            wrap.Name = "_ScaleWrap"
            wrap.BackgroundTransparency = 1
            wrap.BorderSizePixel = 0
            wrap.ClipsDescendants = false
            wrap.Size = cardFrame.Size
            wrap.Position = cardFrame.Position
            wrap.AnchorPoint = cardFrame.AnchorPoint
            wrap.ZIndex = cardFrame.ZIndex
            wrap.LayoutOrder = cardFrame.LayoutOrder
            wrap.Parent = cardFrame.Parent
            cardFrame.Parent = wrap
            -- Se estivermos a usar o frame interno (content), centralizá-lo
            if frame ~= cardFrame then
                frame.AnchorPoint = Vector2.new(0.5, 0.5)
                frame.Position = UDim2.fromScale(0.5, 0.5)
                frame.Size = UDim2.fromScale(1, 1)
            else
                -- Se estamos a escalar o próprio cardFrame movido para wrap, criar um content container
                local inner = Instance.new("Frame")
                inner.Name = "Content"
                inner.BackgroundTransparency = frame.BackgroundTransparency
                inner.BackgroundColor3 = frame.BackgroundColor3
                inner.Size = UDim2.fromScale(1,1)
                inner.AnchorPoint = Vector2.new(0.5,0.5)
                inner.Position = UDim2.fromScale(0.5,0.5)
                inner.ZIndex = frame.ZIndex
                -- Mover children
                local toMove = {}
                for _, ch in ipairs(frame:GetChildren()) do table.insert(toMove, ch) end
                for _, ch in ipairs(toMove) do ch.Parent = inner end
                inner.Parent = frame
                scaleHost = frame
            end
            scaleHost = wrap
        else
            scaleHost = cardFrame:FindFirstChild("_ScaleWrap")
        end
    else
        -- Converter anchor para centro para crescimento uniforme
        if frame.AnchorPoint ~= Vector2.new(0.5,0.5) then
            local oldPos, oldSize = frame.Position, frame.Size
            frame.AnchorPoint = Vector2.new(0.5,0.5)
            frame.Position = UDim2.new(
                oldPos.X.Scale + oldSize.X.Scale * 0.5,
                oldPos.X.Offset + oldSize.X.Offset * 0.5,
                oldPos.Y.Scale + oldSize.Y.Scale * 0.5,
                oldPos.Y.Offset + oldSize.Y.Offset * 0.5
            )
        end
        scaleHost = frame
    end

    -- Garantir UIScale no host escolhido
    local scale = scaleHost:FindFirstChild("_HoverScale")
    if not scale then
        scale = Instance.new("UIScale")
        scale.Name = "_HoverScale"
        scale.Scale = 1
        scale.Parent = scaleHost
    end

    -- Sombra FFF (versão revertida): mirror simples de scale para manter offset/origem original
    local shadow = frame:FindFirstChild("FFF") or cardFrame:FindFirstChild("FFF")
    local shadowScale
    if shadow and shadow:IsA("GuiObject") then
        -- Se já estiver dentro do scaleHost herda automaticamente; se não, espelhar scale
        if not shadow:IsDescendantOf(scaleHost) then
            shadowScale = shadow:FindFirstChild("_HoverScaleShadow")
            if not shadowScale then
                shadowScale = Instance.new("UIScale")
                shadowScale.Name = "_HoverScaleShadow"
                shadowScale.Scale = 1
                shadowScale.Parent = shadow
            end
            if not shadow:GetAttribute("_MirrorConn") then
                scale:GetPropertyChangedSignal("Scale"):Connect(function()
                    shadowScale.Scale = scale.Scale
                end)
                shadow:SetAttribute("_MirrorConn", true)
            end
        end
        if shadow.ZIndex >= frame.ZIndex then
            shadow.ZIndex = frame.ZIndex - 1
        end
    end

    local hoverScale = 1.07
    local tweenInInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tweenOutInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    local currentTween
    local function playTween(info, target)
        if currentTween then currentTween:Cancel() end
        currentTween = TweenService:Create(scale, info, { Scale = target })
        currentTween:Play()
    end

    frame.MouseEnter:Connect(function()
        playTween(tweenInInfo, hoverScale)
    end)
    frame.MouseLeave:Connect(function()
        playTween(tweenOutInfo, 1)
    end)
    -- Segurança: ao inputBegan touch/mouse down, dá um pequeno "tap" (opcional)
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            playTween(TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), hoverScale * 0.97)
        end
    end)
    frame.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            playTween(TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), hoverScale)
        end
    end)
end

-- Integracao com RemoteEvents do servidor
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
local LevelUpEvent = Remotes and Remotes:FindFirstChild("LevelUp")
local LevelUpChoice = Remotes and Remotes:FindFirstChild("LevelUpChoice")

if LevelUpEvent then
    LevelUpEvent.OnClientEvent:Connect(function(payload)
        if typeof(payload) == "table" and typeof(payload.cards) == "table" then
            print("[CardsUI] Oferta recebida do servidor (" .. tostring(#payload.cards) .. ")")
            pendingServerCards = payload.cards
            -- Mostra usando animação (não regenera porque já recebemos a lista)
            showCards(false)
        else
            warn("[CardsUI] Payload LevelUp inesperado")
        end
    end)
else
    warn("[CardsUI] RemoteEvent Remotes.LevelUp não encontrado (uso local apenas)")
end

connectClicks = function()
    local frames = getCardFrames()
    for _, cardFrame in ipairs(frames) do
        if cardFrame and not cardFrame:GetAttribute("_ClickBound") then
            cardFrame:SetAttribute("_ClickBound", true)
            local button = cardFrame:FindFirstChild("Frame") or cardFrame
            if button:IsA("GuiObject") then
                attachHover(cardFrame)
                button.InputBegan:Connect(function(input)
                    if input.UserInputType.Name == "MouseButton1" then
                        if selectionLocked then return end
                        selectionLocked = true
                        local chosenId = cardFrame:GetAttribute("CardId")
                        if chosenId then
                            print("[CardsUI] Escolheu carta:", chosenId)
                            if LevelUpChoice then
                                print("[CardsUI] Enviando escolha ao servidor ...")
                                pcall(function()
                                    LevelUpChoice:FireServer({ id = chosenId })
                                end)
                            end
                            pendingServerCards = nil
                            hideCards()
                        end
                    end
                end)
            end
        end
        if cardFrame then
            -- Garante hover mesmo se já tinha _ClickBound (ex: script recarregado)
            attachHover(cardFrame)
        end
    end
end

-- Public refresh (can be called externally if you expose it)
-- Iniciar escondido; só aparece quando showCards() for chamado externamente
setGuiVisible(false)

-- Opcional: expor função global para abrir a oferta de cartas
-- No server podes usar um RemoteEvent para pedir ao cliente abrir.
-- Suporte legado via _G (pode falhar dependendo da ordem de carregamento)
_G.ShowCardOffers = function(regenerate)
    print("[CardsUI] _G.ShowCardOffers invocado")
    showCards(regenerate ~= false) -- por omissão regenera
end

-- Alternativa mais robusta: BindableEvent compartilhado entre LocalScripts
local eventsFolderOk, eventsFolder = pcall(function()
    return ReplicatedStorage:WaitForChild("R_Events", 3)
end)
if eventsFolderOk and eventsFolder then
    local be = eventsFolder:FindFirstChild("ShowCardOffers")
    if not be then
        be = Instance.new("BindableEvent")
        be.Name = "ShowCardOffers"
        be.Parent = eventsFolder
    end
    be.Event:Connect(function(regenerate)
        print("[CardsUI] BindableEvent ShowCardOffers recebido")
        showCards(regenerate ~= false)
    end)
else
    warn("[CardsUI] Nao consegui aceder a R_Events para criar BindableEvent ShowCardOffers")
end

-- Example: refresh when player levels up (if a Level IntValue exists)
local stats = player:WaitForChild("Stats", 5)
if stats then
    local level = stats:FindFirstChild("Level")
    if level and level:IsA("NumberValue") then
        level.Changed:Connect(function()
            if not LevelUpEvent then -- se o servidor não controla, ainda podemos regenerar localmente
                offerCards()
            end
        end)
    end
end
