-- Diagnostic: Print script.Parent and its class at startup

print("[SummonUI] LocalScript parent:", script.Parent, script.Parent and script.Parent.ClassName or "nil")
if not script.Parent then
    warn("[SummonUI] LocalScript parent is nil! Aborting.")
    return
end
-- Don't abort if the parent isn't specifically a ScreenGui/Frame (can be moved at runtime).
-- Instead, try to find the actual UI `Frame` recursively, with a short WaitForChild fallback.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = game.Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local HttpService = game:GetService("HttpService")
local CurrentBannerValue = ReplicatedStorage:WaitForChild("CurrentBanner")
local function getCurrentBannerJson()
    return CurrentBannerValue and CurrentBannerValue.Value or nil
end
CurrentBannerValue.Changed:Connect(function()
    print("[SummonUI] CurrentBannerValue changed! Atualizando ícones...")
    if updateBannerIcons then updateBannerIcons() end
end)

print("[SummonUI] LocalScript iniciado!")

local openRemote = remotes:WaitForChild("Open_Summon")
local SummonClientReadyRE = remotes:WaitForChild("SummonClientReady")
local TweenService = game:GetService("TweenService")
local openSummonFunction = remotes:WaitForChild("OpenSummonFunction")

print("[SummonUI] Registrando listener para Open_Summon...")

local frame = nil
-- Quick heuristic: direct child, then recursive find, then WaitForChild fallback
frame = script.Parent:FindFirstChild("Frame") or script.Parent:FindFirstChild("Frame", true)
if not frame then
    local ok, res = pcall(function() return script.Parent:WaitForChild("Frame", 5) end)
    if ok and res then frame = res end
end
if not frame then
    warn("[SummonUI] Frame não encontrado! Parent:", tostring(script.Parent))
    for _, child in ipairs(script.Parent:GetChildren()) do
        print("[SummonUI] Child:", child.Name, child.ClassName)
    end
    return
else
    print("[SummonUI] Frame encontrado:", frame.Name)
    -- Safe-guard property access in case the Frame isn't fully parented yet
    pcall(function()
        frame.Visible = false -- começa invisível
        frame.Position = UDim2.new(0, 0, -1, 0)
    end)
    print("[SummonUI] Inicialização: Frame invisível e fora da tela.")
    -- Preview frame começa invisivel (guarded)
    local previewFrame = frame:FindFirstChild("Preview") or frame:FindFirstChild("Preview", true)
    if previewFrame then
        pcall(function() previewFrame.Visible = false end)
    end

    -- ...existing code...
-- Referência ao botão de cartas no preview
local previewFrame = frame:FindFirstChild("Preview")
local cardBtn = previewFrame and previewFrame:FindFirstChild("Card_b")
local selectedCharId = nil

-- Registra evento do botão Card_b para abrir UI de cartas
if cardBtn and cardBtn:IsA("ImageButton") then
    cardBtn.MouseButton1Click:Connect(function()
        -- Diagnostic: print current selectedCharId and preview info to help debug why resolution fails
        print(string.format("[SummonUI][Card_b] clicked. selectedCharId=%s", tostring(selectedCharId)))
        local _previewRootDbg = frame and frame:FindFirstChild("Preview")
        if _previewRootDbg and _previewRootDbg:IsA("Frame") then
            local _eq = _previewRootDbg:FindFirstChild("Icon_c") or _previewRootDbg:FindFirstChild("Frame")
            local _iconImgDbg = nil
            if _eq and _eq:IsA("Frame") then
                local _eq_bg = _eq:FindFirstChild("EQ_BG") or _eq
                local _iconLabel = _eq_bg and _eq_bg:FindFirstChild("Icon")
                if _iconLabel and _iconLabel:IsA("ImageLabel") then
                    _iconImgDbg = _iconLabel.Image
                end
            end
            local _charNameDbg = nil
            if _eq and _eq:IsA("Frame") then
                local _f = _eq:FindFirstChild("Frame")
                if _f then
                    local _cn = _f:FindFirstChild("Char_name")
                    if _cn and _cn:IsA("TextLabel") then _charNameDbg = _cn.Text end
                end
            end
            print(string.format("[SummonUI][Card_b] preview icon=%s char_name=%s", tostring(_iconImgDbg), tostring(_charNameDbg)))
        end
    -- Use the same robust method as Chars UI: find the Cards ScreenGui with heuristics,
        -- set the attribute inside a pcall and enable the GUI, with a short retry.
        local Players = game:GetService("Players")
        local localPlayer = Players.LocalPlayer
        if not localPlayer then
            warn("[SummonUI] LocalPlayer não disponível")
            return
        end
        local playerGui = localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui")

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
            warn("[SummonUI] ScreenGui 'Cards' não encontrado. PlayerGui children:", table.concat(names, ", "))
            return
        end

        -- Prefer the upvalue, but also check a persisted attribute in case the upvalue was reset
        local sourceId = selectedCharId
        if not sourceId then
            local attr = script:GetAttribute("SelectedCharId")
            if attr and type(attr) == "string" and #attr > 0 then
                sourceId = attr
                print("[SummonUI][Card_b] read selected id from script attribute ->", sourceId)
            end
        end
        -- If selectedCharId is missing, try to resolve it from the Preview UI (icon image or banner)
        if not sourceId then
            pcall(function()
                local previewRoot = frame:FindFirstChild("Preview")
                if previewRoot and previewRoot:IsA("Frame") then
                    local scrolling = previewRoot:FindFirstChild("ScrollingFrame")
                    local eq = previewRoot:FindFirstChild("Icon_c") or previewRoot:FindFirstChild("Frame")
                    local iconImg = nil
                    -- try to get the Icon image inside the preview EQ_BG
                    if eq and eq:IsA("Frame") then
                        local eq_bg = eq:FindFirstChild("EQ_BG") or eq
                        local iconLabel = eq_bg and eq_bg:FindFirstChild("Icon")
                        if iconLabel and iconLabel:IsA("ImageLabel") then
                            iconImg = iconLabel.Image
                        end
                    end
                    -- fallback: try to read char_name text and match via catalog displayName
                    local charNameLabel = nil
                    if eq and eq:IsA("Frame") then
                        local f = eq:FindFirstChild("Frame")
                        if f then charNameLabel = f:FindFirstChild("Char_name") end
                    end
                    -- Resolve using CharacterCatalog by icon_id first
                    if iconImg then
                        local ReplicatedStorage = game:GetService("ReplicatedStorage")
                        local CharacterCatalog = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("CharacterCatalog"))
                        local all = CharacterCatalog:GetAllMap()
                        for tpl, entry in pairs(all) do
                            if entry and entry.icon_id == iconImg then
                                sourceId = tpl
                                break
                            end
                        end
                    end
                    -- If still not found, try banner mapping
                    if not sourceId then
                        local bannerJson = getCurrentBannerJson()
                        if bannerJson and bannerJson ~= "" then
                            local ok, decoded = pcall(function() return HttpService:JSONDecode(bannerJson) end)
                            if ok and decoded and decoded.entries then
                                for _, entry in ipairs(decoded.entries) do
                                    if entry.icon_id == iconImg then
                                        sourceId = entry.id
                                        break
                                    end
                                end
                            end
                        end
                    end
                    -- Last resort: match by displayName text (slower, fuzzy)
                    if not sourceId and charNameLabel and charNameLabel:IsA("TextLabel") then
                        local nameText = charNameLabel.Text or ""
                        if nameText ~= "[ID não encontrado]" and #nameText > 0 then
                            local ReplicatedStorage = game:GetService("ReplicatedStorage")
                            local CharacterCatalog = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("CharacterCatalog"))
                            local all = CharacterCatalog:GetAllMap()
                            for tpl, entry in pairs(all) do
                                if entry and entry.displayName and entry.displayName == nameText then
                                    sourceId = tpl
                                    break
                                end
                            end
                        end
                    end
                    if sourceId then
                        print("[SummonUI] Card button fallback resolved sourceId=", sourceId)
                        selectedCharId = sourceId
                        -- Persist to script attribute so other handlers/readers can access it reliably
                        pcall(function() script:SetAttribute("SelectedCharId", sourceId) end)
                    end
                end
            end)
        end
        -- If we still don't have a resolved sourceId after fallbacks, abort
        if not sourceId then
            warn("[SummonUI] Nenhum personagem selecionado para mostrar cartas (não foi possível resolver via preview/banner/catalog).")
            return
        end

        local function enableAndShow(g)
            pcall(function() g:SetAttribute("ShowCharacterCards", sourceId) end)
            pcall(function() g.Enabled = true end)
            print(string.format("[SummonUI] Requested Cards UI on %s for sourceId=%s", tostring(g.Name), tostring(sourceId)))
            task.delay(0.07, function()
                if g and g.Parent then
                    pcall(function() g:SetAttribute("ShowCharacterCards", sourceId) end)
                end
            end)
        end

        enableAndShow(cardsGui)
    end)
end
end

local isSummonUIOpen = false -- Garante que começa como false
local receivedSummonEvent = false
-- Guard to avoid wiring the same button handlers multiple times (prevents duplicate FireServer)
local summonHandlersWired = false

-- Função para abrir a UI
local function openSummonUI()
    -- Debug: Print all frames and their children inside Summon > Chars
    -- Locate the Summon root frame robustly (direct child, recursive search, or WaitForChild fallback)
    local summonFrame = frame:FindFirstChild("Summon") or frame:FindFirstChild("Summon", true)
    if not summonFrame then
        local ok, res = pcall(function() return frame:WaitForChild("Summon", 5) end)
        if ok and res then summonFrame = res end
    end
    if not summonFrame then
        warn("[SummonUI] Frame.Summon não encontrado.")
        return
    end
    local charsFrame = summonFrame:FindFirstChild("Chars")
    if not charsFrame then
        warn("[SummonUI] Frame.Summon.Chars não encontrado.")
        return
    end
    print("[SummonUI] Frames dentro de Summon > Chars:")
    for _, unitFrame in ipairs(charsFrame:GetChildren()) do
        if unitFrame:IsA("Frame") then
            print("  Frame:", unitFrame.Name)
            for _, child in ipairs(unitFrame:GetChildren()) do
                print("    Child:", child.Name, child.ClassName)
            end
        end
    end
    if isSummonUIOpen then
        print("[SummonUI] UI já está aberta, animação ignorada.")
        return
    end
    isSummonUIOpen = true
    frame.Visible = true
    frame.Position = UDim2.new(0, 0, -1, 0)
    print("[SummonUI] UI de Summon aberta! Frame.Visible=", frame.Visible)
    -- Ensure confirmation dialogs are hidden when opening
    local open_u_sure_1 = frame:FindFirstChild("U_Sure_1") or summonFrame:FindFirstChild("U_Sure_1")
    local open_u_sure_10 = frame:FindFirstChild("U_Sure_10") or summonFrame:FindFirstChild("U_Sure_10")
    if open_u_sure_1 then open_u_sure_1.Visible = false end
    if open_u_sure_10 then open_u_sure_10.Visible = false end
    -- Declare persistent references so other blocks in this function can attach handlers
    local u_sure_1 = frame:FindFirstChild("U_Sure_1") or summonFrame:FindFirstChild("U_Sure_1")
    local u_sure_10 = frame:FindFirstChild("U_Sure_10") or summonFrame:FindFirstChild("U_Sure_10")
    

    -- Star color palette (same as inventory)
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

    -- Função para atualizar gradiente de acordo com as estrelas
    -- Refactored: Use same gradient logic as Chars_Inv
    local function setStarGradient(grad, baseColor)
        if not grad or not baseColor then return end
        local h,s,v = baseColor:ToHSV()
        -- Stronger contrast: top lighter, middle base, bottom darker
        local lighter = Color3.fromHSV(h, math.clamp(s * 0.35, 0, 1), math.min(1, v * 1.25))
        local darker = Color3.fromHSV(h, s, math.clamp(v * 0.35, 0, 1))
        grad.Rotation = 90 -- vertical
        grad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, lighter),
            ColorSequenceKeypoint.new(0.45, baseColor),
            ColorSequenceKeypoint.new(1, darker),
        })
        grad.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 0),
        })
        print("[SummonUI][Preview] StarGrad updated:", grad.Name, grad.ClassName)
        return grad
    end

    -- Função simples para abrir o preview com o ícone clicado
    local function openPreview(iconImage, stars)
        local previewFrameCurrent = frame:FindFirstChild("Preview")
        print("[SummonUI][Preview] Preview frame:", previewFrameCurrent and previewFrameCurrent.Name or "nil", previewFrameCurrent and previewFrameCurrent.ClassName or "nil")
        local icon_c = previewFrameCurrent and previewFrameCurrent:FindFirstChild("Icon_c")
        print("[SummonUI][Preview] Icon_c:", icon_c and icon_c.Name or "nil", icon_c and icon_c.ClassName or "nil")
        local eq_bg = icon_c and icon_c:FindFirstChild("EQ_BG")
        print("[SummonUI][Preview] EQ_BG:", eq_bg and eq_bg.Name or "nil", eq_bg and eq_bg.ClassName or "nil")
        local starGrad = eq_bg and eq_bg:FindFirstChild("StarGrad")
        print("[SummonUI][Preview] StarGrad:", starGrad and starGrad.Name or "nil", starGrad and starGrad.ClassName or "nil")
        local frameInEQ = eq_bg and eq_bg:FindFirstChild("Frame")
        local charNameLabel = frameInEQ and frameInEQ:FindFirstChild("Char_name")
        if eq_bg then
            print("[SummonUI][Preview] Children of EQ_BG:")
            for _, child in ipairs(eq_bg:GetChildren()) do
                print("    Child:", child.Name, child.ClassName)
            end
        end
        local previewIconCurrent = eq_bg and eq_bg:FindFirstChild("Icon")
        print("[SummonUI][Preview] Icon:", previewIconCurrent and previewIconCurrent.Name or "nil", previewIconCurrent and previewIconCurrent.ClassName or "nil")
        -- Set gradient color according to stars
        if starGrad and stars then
            local color = colorForStars(stars)
            setStarGradient(starGrad, color)
            print("[SummonUI][Preview] Gradient atualizado para estrelas em StarGrad:", stars)
        end
        -- Set character name in preview using CharacterCatalog
    if charNameLabel and charNameLabel:IsA("TextLabel") then
            local bannerJson = getCurrentBannerJson()
            local displayName = "?"
            local charId = nil
            -- Tenta obter o id diretamente do banner (entry.id) ou do catálogo
            if bannerJson and bannerJson ~= "" then
                local ok, decoded = pcall(function() return HttpService:JSONDecode(bannerJson) end)
                if ok and decoded and decoded.entries then
                    for _, entry in ipairs(decoded.entries) do
                        if entry.icon_id == iconImage then
                            charId = entry.id
                            break
                        end
                    end
                end
            end
            -- Se não encontrar, tenta pegar do catálogo pelo id do personagem (não pelo icon_id)
            if not charId then
                -- Se o preview já tem o nome/id do personagem, usa ele
                if charNameLabel and charNameLabel.Text and charNameLabel.Text ~= "[ID não encontrado]" then
                    -- Tenta extrair o id do texto se possível
                    local possibleId = charNameLabel.Text:match("%[(.-)%]")
                    if possibleId and #possibleId > 0 then
                        charId = possibleId
                    end
                end
            end
            selectedCharId = charId -- Atualiza personagem selecionado para Card_b
            local ReplicatedStorage = game:GetService("ReplicatedStorage")
            local CharacterCatalog = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("CharacterCatalog"))
            local catalogEntry = nil
            if charId then
                catalogEntry = CharacterCatalog:Get(charId)
                if catalogEntry and catalogEntry.displayName then
                    displayName = catalogEntry.displayName
                else
                    displayName = charId
                end
            else
                displayName = "[ID não encontrado]"
            end
            charNameLabel.Text = displayName
            print("[SummonUI][Preview] Char_name label set to:", displayName)

            -- Resolve um template id confiável para abrir as cartas (usar template name)
            local resolvedTemplate = nil
            if catalogEntry and catalogEntry.template then
                resolvedTemplate = catalogEntry.template
            end
            -- Se não tivemos catalogEntry válido, procurar pelo icon_id no catálogo
            if not resolvedTemplate then
                local all = CharacterCatalog:GetAllMap()
                for tpl, entry in pairs(all) do
                    if entry and entry.icon_id == iconImage then
                        resolvedTemplate = tpl
                        break
                    end
                end
            end
            -- Fallback: se banner forneceu um id que parece ser o template, usa-o
            if not resolvedTemplate and charId and type(charId) == "string" then
                resolvedTemplate = charId
            end
            selectedCharId = resolvedTemplate
            print("[SummonUI][Preview] selectedCharId resolved to:", selectedCharId)
            -- Persist resolved template id so other handlers (Card_b) can read it reliably
            pcall(function() script:SetAttribute("SelectedCharId", selectedCharId) end)

            -- Exibir stats no ScrollingFrame
            local previewFrameCurrent = frame:FindFirstChild("Preview")
            local scrollingFrame = previewFrameCurrent and previewFrameCurrent:FindFirstChild("ScrollingFrame")
            local statTemplate = nil
            if scrollingFrame then
                for _, child in ipairs(scrollingFrame:GetChildren()) do
                    if child.Name == "Stat_f" and child:IsA("Frame") then
                        statTemplate = child
                        break
                    end
                end
            end
            print("[SummonUI][Preview] Stat template:", statTemplate)
            print("[SummonUI][Preview] CatalogEntry stats:", catalogEntry and catalogEntry.stats)
            if not statTemplate then
                warn("[SummonUI][Preview] Stat_f template não encontrado no ScrollingFrame! Não é possível exibir stats.")
                -- continue: still allow icon/name to update even if stats can't be shown
            end
            if scrollingFrame and statTemplate and charId then
                -- Limpa todos os frames antigos do ScrollingFrame, exceto o template
                for _, child in ipairs(scrollingFrame:GetChildren()) do
                    if child:IsA("Frame") and child ~= statTemplate then
                        child:Destroy()
                    end
                end

                -- Buscar stats do módulo de cada char
                local ReplicatedStorage = game:GetService("ReplicatedStorage")
                local charsFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Chars")
                local charStatsModule = nil
                local okStats, statsMod = pcall(function()
                    local charFolder = charsFolder:FindFirstChild(charId)
                    if charFolder then
                        local statsScript = charFolder:FindFirstChild("Stats")
                        if statsScript then
                            return require(statsScript)
                        end
                    end
                    return nil
                end)
                if okStats and statsMod and type(statsMod) == "table" then
                    charStatsModule = statsMod
                end

                -- Clona Stat_f inteiro para cada stat e preenche corretamente o texto
                if charStatsModule and type(charStatsModule.Passives) == "table" then
                    for statName, statValue in pairs(charStatsModule.Passives) do
                        local clone = statTemplate:Clone()
                        clone.Name = "Stat_" .. statName
                        clone.Visible = true
                        clone.BackgroundTransparency = statTemplate.BackgroundTransparency
                        clone.BackgroundColor3 = statTemplate.BackgroundColor3
                        for _, comp in ipairs(statTemplate:GetChildren()) do
                            if not clone:FindFirstChild(comp.Name) then
                                comp:Clone().Parent = clone
                            end
                        end
                        local textLabel = clone:FindFirstChild("stat_text", true)
                        if textLabel and textLabel:IsA("TextLabel") then
                            if type(statValue) == "number" then
                                statValue = math.floor(statValue + 0.5)
                            end
                            local displayName = statName
                            if statName == "BaseDamage" then
                                displayName = "Damage"
                            end
                            textLabel.Text = string.format("%s: %s", displayName, tostring(statValue))
                            textLabel.Visible = true
                        else
                            warn("[SummonUI][Preview] stat_text não encontrado ou não é TextLabel no clone de Stat_f")
                        end
                        clone.Parent = scrollingFrame
                    end
                        -- Keep the template for future previews (make sure it's hidden)
                        statTemplate.Visible = false
                else
                    print("[SummonUI][Preview] Falha ao encontrar Passives para:", charId)
                end
            else
                warn("[SummonUI][Preview] Falha ao exibir stats: scrollingFrame=", scrollingFrame, "statTemplate=", statTemplate, "charId=", charId)
            end
        end
        if previewFrameCurrent and previewIconCurrent then
            previewFrameCurrent.Visible = true
            previewIconCurrent.Image = iconImage
            print("[SummonUI][Preview] Preview aberto! Icon atualizado para:", iconImage)
        else
            print("[SummonUI][Preview] Falha ao abrir preview: previewFrameCurrent=", tostring(previewFrameCurrent), "previewIconCurrent=", tostring(previewIconCurrent))
        end
    end

    -- Atualiza os ícones das unidades do banner conforme o catálogo e ordem do banner
    local function updateBannerIcons()
        local bannerJson = getCurrentBannerJson()
        print("[SummonUI] updateBannerIcons called. CurrentBanner:", bannerJson)
        -- Use SummonModule to compute per-slot chances so the client doesn't hardcode values
        local SummonModule = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("SummonModule"))
        local bannerTable = nil
        if bannerJson and bannerJson ~= "" then
            local ok, decoded = pcall(function() return HttpService:JSONDecode(bannerJson) end)
            if ok and decoded then bannerTable = decoded end
        end
        local perSlotChances, rarityCountsRaw = SummonModule.GetPerSlotChances(bannerTable)
        -- Convert numeric keys to strings for compatibility with existing code that indexes by tostring(rarity)
        local rarityChances = {}
        for k,v in pairs(perSlotChances or {}) do
            rarityChances[tostring(k)] = v
        end
        -- Build a string-keyed rarityCounts from the module result (if present)
        local rarityCounts = {}
        for k,v in pairs(rarityCountsRaw or {}) do
            rarityCounts[tostring(k)] = v
        end
        local charsFrame = summonFrame and summonFrame:FindFirstChild("Chars")
        if not charsFrame then
            warn("[SummonUI] Chars frame não encontrado.")
            return
        end
        print("[SummonUI] Frames dentro de Chars:")
        for _, unitFrame in ipairs(charsFrame:GetChildren()) do
            if unitFrame:IsA("Frame") then
                print("  Frame:", unitFrame.Name)
                for _, child in ipairs(unitFrame:GetChildren()) do
                    print("    Child:", child.Name, child.ClassName)
                end
            end
        end

        if not bannerJson or bannerJson == "" then
            warn("[SummonUI] CurrentBanner não encontrado em ReplicatedStorage. Mostrando ícones padrão.")
            -- Show default/fallback icons and print for each
            for _, unitFrame in ipairs(charsFrame:GetChildren()) do
                if unitFrame:IsA("Frame") then
                    local icon = unitFrame:FindFirstChild("Icon")
                    if icon and icon:IsA("ImageButton") then
                        icon.Image = "rbxassetid://0" -- fallback asset
                        print(string.format("[SummonUI] Fallback icon set for %s", unitFrame.Name))
                    else
                        print(string.format("[SummonUI] Fallback icon NOT set for %s (icon missing or wrong type)", unitFrame.Name))
                    end
                end
            end
            -- Show loading message
            local loadingLabel = summonFrame:FindFirstChild("LoadingLabel")
            if loadingLabel and loadingLabel:IsA("TextLabel") then
                loadingLabel.Visible = true
                loadingLabel.Text = "Carregando banner..."
                print("[SummonUI] LoadingLabel shown: Carregando banner...")
            end
            -- Retry until banner arrives
            delay(0.3, function()
                updateBannerIcons()
            end)
            return
        end
        local banner = nil
        local ok, decoded = pcall(function() return HttpService:JSONDecode(bannerJson) end)
        if ok and decoded and decoded.entries then
            banner = decoded
            print("[SummonUI] Banner entries:", HttpService:JSONEncode(banner.entries))
        else
            warn("[SummonUI] Falha ao decodificar CurrentBanner.")
            return
        end
        -- Map frames: handle single-slot (e.g., 5_Star) and multi-slot (e.g., 3_Star1, 3_Star2)
        local frameMap = {}
        for _, unitFrame in ipairs(charsFrame:GetChildren()) do
            if unitFrame:IsA("Frame") then
                local name = unitFrame.Name
                local rarity, idx = string.match(name, "^(%d+)_Star(%d+)$")
                if rarity and idx then
                    frameMap[rarity] = frameMap[rarity] or {}
                    frameMap[rarity][tonumber(idx)] = unitFrame
                    print(string.format("[SummonUI] Mapeado frame %s para rarity %s idx %d", name, rarity, tonumber(idx)))
                else
                    -- Handle single-slot rarity (e.g., 5_Star)
                    local singleRarity = string.match(name, "^(%d+)_Star$")
                    if singleRarity then
                        frameMap[singleRarity] = frameMap[singleRarity] or {}
                        frameMap[singleRarity][1] = unitFrame
                        print(string.format("[SummonUI] Mapeado frame %s para rarity %s idx 1", name, singleRarity))
                    end
                end
            end
        end

        -- For each entry, find the correct frame and set the icon
        local raritySeen = {}
        for _, entry in ipairs(banner.entries) do
            local rarity = tostring(entry.rarity)
            raritySeen[rarity] = (raritySeen[rarity] or 0) + 1
            local idx = raritySeen[rarity]
            local unitFrame = frameMap[rarity] and frameMap[rarity][idx]
            print(string.format("[SummonUI] Procurando frame para rarity %s idx %d", rarity, idx))
            if unitFrame then
                print(string.format("[SummonUI][BannerIcons] Children of %s:", unitFrame.Name))
                for _, child in ipairs(unitFrame:GetChildren()) do
                    print("    Child:", child.Name, child.ClassName)
                end
                local icon = unitFrame:FindFirstChild("Icon")
                print(string.format("[SummonUI] Frame %s, Icon: %s, Icon Type: %s, entry.icon_id: %s", unitFrame.Name, icon and icon.Name or "nil", icon and icon.ClassName or "nil", entry.icon_id or "nil"))
                if icon then
                    if icon:IsA("ImageButton") then
                        if entry.icon_id then
                            icon.Image = entry.icon_id
                            print(string.format("[SummonUI] Frame %s: Ícone de %s atualizado para %s", unitFrame.Name, entry.id, entry.icon_id))
                        else
                            icon.Image = "rbxassetid://0"
                            warn(string.format("[SummonUI] Frame %s: Não encontrado icon_id para: %s", unitFrame.Name, entry.id))
                        end
                        icon.MouseButton1Click:Connect(function()
                            print(string.format("[SummonUI] [DEBUG] Click detectado em %s (icon=%s)", unitFrame.Name, icon.Image))
                            openPreview(icon.Image, entry.rarity)
                        end)
                        print(string.format("[SummonUI] Evento de click conectado para %s", unitFrame.Name))
                    else
                        warn(string.format("[SummonUI] Frame %s: Icon existe mas não é ImageButton (tipo: %s)", unitFrame.Name, icon.ClassName))
                    end
                else
                    warn(string.format("[SummonUI] Frame %s: Icon não encontrado", unitFrame.Name))
                end
                -- Display chance in a TextLabel if present
                local chanceLabel = unitFrame:FindFirstChild("ChanceLabel")
                if chanceLabel and chanceLabel:IsA("TextLabel") then
                    -- perSlotChances already represents the per-slot percentage for that rarity
                    local charChance = rarityChances[rarity] or 0
                    chanceLabel.Text = string.format("Chance: %.2f%%", charChance)
                    chanceLabel.Visible = true
                    print(string.format("[SummonUI] Frame %s: Chance set to %.2f%%", unitFrame.Name, charChance))
                end
            else
                warn(string.format("[SummonUI] Não encontrado frame para rarity %s idx %d", rarity, idx))
            end
        end
    end

    -- Always call updateBannerIcons, even if banner is missing (it will show fallback)
    updateBannerIcons()

    -- Inventory helpers (used by both the summon buttons and the confirmation handlers)
    local GetCharacterInventoryRF = remotes:FindFirstChild("GetCharacterInventory")
    local GetProfileRF = remotes:FindFirstChild("GetProfile")
    local RequestSummonRE = remotes:FindFirstChild("RequestSummon")

    local function countTableEntries(t)
        if not t or type(t) ~= "table" then return 0 end
        local pairCount = 0
        local numericKeySeen = true
        local maxNumericKey = 0
        for k, v in pairs(t) do
            pairCount = pairCount + 1
            if type(k) ~= "number" then
                numericKeySeen = false
            else
                if k > maxNumericKey then maxNumericKey = k end
            end
        end
        if numericKeySeen and maxNumericKey <= pairCount then
            return #t
        end
        return pairCount
    end

    local function hasInventorySpace(required)
        required = required or 1
        -- Prefer using the player's profile snapshot if available via GetProfile (faster and canonical)
        if GetProfileRF then
            local ok, res = pcall(function() return GetProfileRF:InvokeServer() end)
            if ok and res then
                local profile = res.profile or res
                if profile and profile.Characters then
                    local chars = profile.Characters
                    local capacity = chars.Capacity or chars.capacity or 50
                    local instances = chars.Instances or {}
                    local currentCount = countTableEntries(instances)
                    print(string.format("[SummonUI] (Profile) capacity=%d current=%d required=%d", capacity, currentCount, required))
                    return (capacity - currentCount) >= required
                end
            else
                warn("[SummonUI] GetProfile invoke failed, falling back to GetCharacterInventory: ", tostring(res))
            end
        end

        -- Fallback: use GetCharacterInventory remote if GetProfile is not available or failed
        if not GetCharacterInventoryRF then
            warn("[SummonUI] GetCharacterInventory remote not found; assuming space available")
            return true
        end
        local ok, inv = pcall(function() return GetCharacterInventoryRF:InvokeServer() end)
        if not ok or not inv then
            warn("[SummonUI] Failed to fetch character inventory; assuming space available")
            return true
        end
        local capacity = inv.Capacity or inv.capacity or 50
        local currentCount = 0
        if inv.Instances and type(inv.Instances) == "table" then
            currentCount = countTableEntries(inv.Instances)
            print(string.format("[SummonUI] Detected inv.Instances with count=%d", currentCount))
        elseif inv.CurrentCount then
            currentCount = inv.CurrentCount
        elseif inv.Count then
            currentCount = inv.Count
        end
        print(string.format("[SummonUI] Inventory capacity=%d current=%d required=%d", capacity, currentCount, required))
        return (capacity - currentCount) >= required
    end

    -- Wire summon buttons (1_summon, 10_summon) and confirm dialogs ONCE to avoid duplicate handlers
    if not summonHandlersWired then
        do
            local buttonsRoot = summonFrame:FindFirstChild("Buttons")
            if buttonsRoot and buttonsRoot:IsA("Frame") then
                local btn1 = buttonsRoot:FindFirstChild("1_summon")
                local btn10 = buttonsRoot:FindFirstChild("10_summon")
                -- use the u_sure_1 / u_sure_10 declared above (do not redeclare locally)
                u_sure_1 = u_sure_1 or frame:FindFirstChild("U_Sure_1") or summonFrame:FindFirstChild("U_Sure_1")
                u_sure_10 = u_sure_10 or frame:FindFirstChild("U_Sure_10") or summonFrame:FindFirstChild("U_Sure_10")

                if btn1 and (btn1:IsA("Frame") or btn1:IsA("ImageButton")) then
                    local realBtn = btn1:FindFirstChild("Button") or btn1
                    if realBtn and (realBtn:IsA("ImageButton") or realBtn:IsA("TextButton")) then
                        realBtn.MouseButton1Click:Connect(function()
                            print("[SummonUI] 1_summon clicked -> showing U_Sure_1 (hiding U_Sure_10)")
                            -- Make mutually exclusive: hide the other dialog
                            if u_sure_10 then u_sure_10.Visible = false end
                            if u_sure_1 then u_sure_1.Visible = true end
                        end)
                    end
                end

                if btn10 and (btn10:IsA("Frame") or btn10:IsA("ImageButton")) then
                    local realBtn = btn10:FindFirstChild("Button") or btn10
                    if realBtn and (realBtn:IsA("ImageButton") or realBtn:IsA("TextButton")) then
                        realBtn.MouseButton1Click:Connect(function()
                            print("[SummonUI] 10_summon clicked -> showing U_Sure_10 (hiding U_Sure_1)")
                            -- Make mutually exclusive: hide the other dialog
                            if u_sure_1 then u_sure_1.Visible = false end
                            if u_sure_10 then u_sure_10.Visible = true end
                        end)
                    end
                end
            end
        end
        -- Wire Up confirm dialogs' Yes/No buttons to perform the actual summon action
        do
            if u_sure_1 then
                local yes = u_sure_1:FindFirstChild("Yes_b") or u_sure_1:FindFirstChild("Yes")
                local no = u_sure_1:FindFirstChild("No_b") or u_sure_1:FindFirstChild("No")
                if yes and (yes:IsA("ImageButton") or yes:IsA("TextButton")) then
                    yes.MouseButton1Click:Connect(function()
                        print("[SummonUI] U_Sure_1 Yes clicked -> checking inventory for 1 slot")
                        if not hasInventorySpace(1) then
                            print("[SummonUI] Not enough inventory space for 1 summon; showing warning")
                            -- Hide the confirmation dialog
                            if u_sure_1 then u_sure_1.Visible = false end
                            -- Show S_warn: slide in from top, stay 2s, slide out (preserve X position)
                            local s_warn = frame:FindFirstChild("S_warn") or summonFrame:FindFirstChild("S_warn")
                            if s_warn then
                                local xScale, xOffset = 0, 0
                                pcall(function()
                                    local curPos = s_warn.Position
                                    xScale = curPos.X.Scale
                                    xOffset = curPos.X.Offset
                                    s_warn.Position = UDim2.new(xScale, xOffset, -1, 0)
                                    s_warn.Visible = true
                                end)
                                local tweenIn = TweenService:Create(s_warn, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(xScale, xOffset, 0, 0) })
                                tweenIn:Play()
                                tweenIn.Completed:Connect(function()
                                    task.delay(2, function()
                                        local tweenOut = TweenService:Create(s_warn, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(xScale, xOffset, -1, 0) })
                                        tweenOut:Play()
                                        tweenOut.Completed:Connect(function()
                                            if s_warn then s_warn.Visible = false end
                                        end)
                                    end)
                                end)
                            end
                            return
                        end
                        if not RequestSummonRE then
                            warn("[SummonUI] RequestSummon remote not found; cannot perform summon")
                            return
                        end
                        local ok, err = pcall(function() RequestSummonRE:FireServer(1) end)
                        if not ok then
                            warn("[SummonUI] Failed to fire RequestSummon for 1: ", tostring(err))
                            return
                        end
                        if u_sure_1 then u_sure_1.Visible = false end
                    end)
                end
                if no and (no:IsA("ImageButton") or no:IsA("TextButton")) then
                    no.MouseButton1Click:Connect(function()
                        print("[SummonUI] U_Sure_1 No clicked -> hiding confirmation dialog")
                        if u_sure_1 then u_sure_1.Visible = false end
                    end)
                end
            end
            if u_sure_10 then
                local yes10 = u_sure_10:FindFirstChild("Yes_b") or u_sure_10:FindFirstChild("Yes")
                local no10 = u_sure_10:FindFirstChild("No_b") or u_sure_10:FindFirstChild("No")
                if yes10 and (yes10:IsA("ImageButton") or yes10:IsA("TextButton")) then
                    yes10.MouseButton1Click:Connect(function()
                        print("[SummonUI] U_Sure_10 Yes clicked -> checking inventory for 10 slots")
                        if not hasInventorySpace(10) then
                            print("[SummonUI] Not enough inventory space for 10 summons; showing warning")
                            if u_sure_10 then u_sure_10.Visible = false end
                            local s_warn = frame:FindFirstChild("S_warn") or summonFrame:FindFirstChild("S_warn")
                            if s_warn then
                                local xScale, xOffset = 0, 0
                                pcall(function()
                                    local curPos = s_warn.Position
                                    xScale = curPos.X.Scale
                                    xOffset = curPos.X.Offset
                                    s_warn.Position = UDim2.new(xScale, xOffset, -1, 0)
                                    s_warn.Visible = true
                                end)
                                local tweenIn = TweenService:Create(s_warn, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(xScale, xOffset, 0, 0) })
                                tweenIn:Play()
                                tweenIn.Completed:Connect(function()
                                    task.delay(2, function()
                                        local tweenOut = TweenService:Create(s_warn, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(xScale, xOffset, -1, 0) })
                                        tweenOut:Play()
                                        tweenOut.Completed:Connect(function()
                                            if s_warn then s_warn.Visible = false end
                                        end)
                                    end)
                                end)
                            end
                            return
                        end
                        if not RequestSummonRE then
                            warn("[SummonUI] RequestSummon remote not found; cannot perform summon")
                            return
                        end
                        local ok, err = pcall(function() RequestSummonRE:FireServer(10) end)
                        if not ok then
                            warn("[SummonUI] Failed to fire RequestSummon for 10: ", tostring(err))
                            return
                        end
                        if u_sure_10 then u_sure_10.Visible = false end
                    end)
                end
                if no10 and (no10:IsA("ImageButton") or no10:IsA("TextButton")) then
                    no10.MouseButton1Click:Connect(function()
                        print("[SummonUI] U_Sure_10 No clicked -> hiding confirmation dialog")
                        if u_sure_10 then u_sure_10.Visible = false end
                    end)
                end
            end
        end
        summonHandlersWired = true
    end

    -- Tween para deslizar de cima para a posição normal
    local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local goal = {
        Position = UDim2.new(0, 0, 0, 0) -- Posição final (ajuste conforme layout)
    }
    local tween = TweenService:Create(frame, tweenInfo, goal)
    tween:Play()
end

-- Opcional: função para fechar a UI e resetar a flag com animação de saída
local function closeSummonUI()
    if not isSummonUIOpen then return end
    print("[SummonUI] Iniciando animação de saída...")
    -- Hide preview frame if open
    if hidePreview then hidePreview() end
    local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    local goal = {
        Position = UDim2.new(0, 0, -1, 0) -- Move para cima, fora da tela
    }
    local tween = TweenService:Create(frame, tweenInfo, goal)
    tween:Play()
    tween.Completed:Connect(function()
        frame.Visible = false
        isSummonUIOpen = false -- Reset flag ao fechar
        print("[SummonUI] UI de Summon fechada!")
    end)
end

-- Escuta o RemoteEvent do servidor
print("[SummonUI] LocalScript rodando em:", tostring(script.Parent))
print("[SummonUI] openRemote:", openRemote, "Type:", typeof(openRemote))
print("[SummonUI] player:", player, "Name:", player and player.Name)

-- Função para sinalizar pronto em intervalos até receber o evento
local function keepSignalingReady()
    while not receivedSummonEvent do
        SummonClientReadyRE:FireServer()
        wait(0.5)
    end
end

-- Inicia o handshake em paralelo
spawn(keepSignalingReady)

openRemote.OnClientEvent:Connect(function(payload)
    print("[SummonUI] RemoteEvent recebido! Payload:", payload, "openRemote:", openRemote, "player:", player)
    receivedSummonEvent = true -- Para o handshake
    if payload == "Summon" then
        openSummonUI()
    else
        print("[SummonUI] Payload inesperado:", payload)
    end
end)

-- Sinaliza ao servidor que o cliente está pronto para receber o evento de Summon
SummonClientReadyRE:FireServer()
print("[SummonUI] Cliente sinalizou pronto para Summon ao servidor.")

-- Registra handler OnClientInvoke para abrir a UI e retornar confirmação ao servidor
openSummonFunction.OnClientInvoke = function(payload)
    print("[SummonUI] RemoteFunction OnClientInvoke chamado! Payload:", payload)
    if payload == "Summon" then
        openSummonUI()
        print("[SummonUI] UI aberta via RemoteFunction!")
        return true
    end
    return false
end

-- Conecta o botão de exit para fechar a UI
local summonFrame = frame:FindFirstChild("Summon")
if summonFrame then
    local exitBtn = summonFrame:FindFirstChild("exit")
    if exitBtn and exitBtn:IsA("ImageButton") or exitBtn:IsA("TextButton") then
        exitBtn.MouseButton1Click:Connect(function()
            print("[SummonUI] Botão exit clicado, fechando UI.")
            closeSummonUI()
        end)
    else
        warn("[SummonUI] Botão exit não encontrado ou não é um botão.")
    end
else
    warn("[SummonUI] Frame.Summon não encontrado.")
end
