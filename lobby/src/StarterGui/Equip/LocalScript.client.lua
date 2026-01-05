-- Equip Inventory UI (simplified)
-- Mostra itens Owned (Weapons/Armors/Rings) com gradiente por raridade.
-- Sem preview, sem equip logic (já existe noutra UI). Apenas lista.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Toggle to true during active debugging to see verbose client prints
local CLIENT_DEBUG = false

local function dprint(...)
	if CLIENT_DEBUG then
		print(...)
	end
end

-- Garantir que os Remotes existem antes de prosseguir (evita caso de abrir Equip antes de qualquer outro GUI)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GetProfileRF = Remotes:WaitForChild("GetProfile")
local ProfileUpdatedRE = Remotes:WaitForChild("ProfileUpdated")
-- Optional equip remotes (server adds these)
local EquipItemRE = Remotes:FindFirstChild("EquipItem")
local UnequipItemRE = Remotes:FindFirstChild("UnequipItem")

local rootGui = script.Parent -- ScreenGui Equip
local frame = rootGui:WaitForChild("Frame")
local exitButton = frame:WaitForChild("Exit") or frame:FindFirstChild("Exit_b")

-- Estrutura interna similar ao chars: Frame/Inv/Inv_frame/ScrollingFrame/inv_icon
local invContainer = frame:WaitForChild("Inv")
local invFrame = invContainer:WaitForChild("Inv_frame")
local scrolling = invFrame:WaitForChild("ScrollingFrame")
local template = scrolling:WaitForChild("inv_icon")
template.Visible = false

-- Layout and padding helpers for better scrolling behavior
local layout = scrolling:FindFirstChildOfClass("UIGridLayout") or scrolling:FindFirstChildOfClass("UIListLayout")
local EXTRA_BOTTOM_PADDING = 56 -- px of extra space so the last row isn't glued to the bottom
do
	-- Ensure a bottom padding exists so users can scroll past the last row
	local pad = scrolling:FindFirstChild("ExtraBottomPadding")
	if not pad then
		pad = Instance.new("UIPadding")
		pad.Name = "ExtraBottomPadding"
		pad.Parent = scrolling
	end
	pad.PaddingBottom = UDim.new(0, EXTRA_BOTTOM_PADDING)
	-- Let Roblox auto-compute CanvasSize from content + padding; we'll keep a manual fallback below
	pcall(function()
		scrolling.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scrolling.ScrollingDirection = Enum.ScrollingDirection.Y
	end)
end

-- Centralized updater to keep CanvasSize tall enough plus an extra bottom margin
local function updateCanvasFromLayout()
	-- If AutomaticCanvasSize is enabled, UIPadding should already allow extra scroll; still force one manual nudge if needed
	local contentY = 0
	if layout and layout.AbsoluteContentSize then
		contentY = layout.AbsoluteContentSize.Y
	else
		-- fallback: sum visible child heights (approx)
		for _, child in ipairs(scrolling:GetChildren()) do
			if child:IsA("Frame") and child.Visible and child ~= template then
				contentY += child.AbsoluteSize.Y
			end
		end
	end
	local needed = math.max(0, contentY + EXTRA_BOTTOM_PADDING)
	if scrolling.AutomaticCanvasSize == Enum.AutomaticSize.None then
		scrolling.CanvasSize = UDim2.new(0, 0, 0, needed)
	else
		-- Nudge CanvasSize minimally to ensure the bottom padding is respected on some Studio builds
		local current = scrolling.CanvasSize
		if current.Y.Offset < needed then
			scrolling.CanvasSize = UDim2.new(current.X.Scale, current.X.Offset, 0, needed)
		end
	end
end

if layout then
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvasFromLayout)
end

-- Lista atual de itens (precisa existir ANTES de rebuildEquippedSlots ser definido para evitar capturar global nil)
local currentItems = {}

-- Equipped slots container (Weapon/Armor/Ring)
local equippedSlotsContainer = frame:FindFirstChild("E_Slots")
local weaponSlot = equippedSlotsContainer and equippedSlotsContainer:FindFirstChild("Weapon_slot")
local armorSlot = equippedSlotsContainer and equippedSlotsContainer:FindFirstChild("Armor_slot")
local ringSlot = equippedSlotsContainer and equippedSlotsContainer:FindFirstChild("Ring_slot")

-- Preview (similar ao chars). Estrutura assumida (conforme screenshot): Frame/Prev -> dentro um container com EQ_BG/Frame/Level/Icon
local previewContainer = frame:FindFirstChild("Prev")
local previewIconFrame, previewIconImage, previewLevelLabel, previewCardButton
local previewEquipButton, previewUnequipButton, previewSellButton
local previewInitiallyHidden = false
local selectedItemId, selectedGroup
local previewActionPending = false

-- New: references for stats scroll (ScrollingFrame + Stat_f template)
local previewScroll, statTemplate

do
	if previewContainer then
		local function recursiveFind(root, name)
			for _, child in ipairs(root:GetDescendants()) do
				if child.Name == name then return child end
			end
			return nil
		end
	previewIconImage = recursiveFind(previewContainer, "Icon") or recursiveFind(previewContainer, "icon")
		if previewIconImage and not (previewIconImage:IsA("ImageLabel") or previewIconImage:IsA("ImageButton")) then
			previewIconImage = nil
		end
		previewLevelLabel = recursiveFind(previewContainer, "Level")
		if previewLevelLabel and not previewLevelLabel:IsA("TextLabel") then previewLevelLabel = nil end
		previewIconFrame = (previewIconImage and previewIconImage.Parent) or previewContainer

		-- capture defaults so we can restore them when closing the preview
		-- (prevents a leftover MainRarityGradient or RarityGradient from permanently tinting the UI)
		pcall(function()
			frameDefaultBgColor = frame and frame.BackgroundColor3 or Color3.fromRGB(255,255,255)
			frameDefaultBgTransparency = frame and frame.BackgroundTransparency or 1
			previewIconFrameDefaultBgColor = previewIconFrame and previewIconFrame.BackgroundColor3 or Color3.fromRGB(255,255,255)
			previewIconFrameDefaultBgTransparency = previewIconFrame and previewIconFrame.BackgroundTransparency or 1
		end)

		-- Card button inside preview (abre UI de cartas)
	previewCardButton = recursiveFind(previewContainer, "Card_b")
	-- Equip / Unequip buttons (may be named Equip_b / Equip or Unequip_b / Unequip)
	previewEquipButton = recursiveFind(previewContainer, "Equip_b") or recursiveFind(previewContainer, "Equip")
	previewUnequipButton = recursiveFind(previewContainer, "Unequip_b") or recursiveFind(previewContainer, "Unequip")
	-- Sell button in preview (optional)
	previewSellButton = recursiveFind(previewContainer, "Sell_b") or recursiveFind(previewContainer, "Sell")

		-- Stats area
		previewScroll = recursiveFind(previewContainer, "ScrollingFrame")
		statTemplate = recursiveFind(previewContainer, "Stat_f")
		if statTemplate and statTemplate:IsA("Frame") then
			statTemplate.Visible = false -- template stays hidden
		end
	end
end

-- Sell panel references (similar to Chars UI)
local sellPanel = frame:FindFirstChild("Sell") or rootGui:FindFirstChild("Sell")
local sellYesButton = sellPanel and sellPanel:FindFirstChild("Yes_b")
local sellNoButton = sellPanel and sellPanel:FindFirstChild("No_b")
local sellText1 = sellPanel and sellPanel:FindFirstChild("1st_text")
local sellText2 = sellPanel and sellPanel:FindFirstChild("2st_text") or sellPanel and sellPanel:FindFirstChild("2nd_text")
local sellAnimating = false
if sellPanel then sellPanel.Visible = false end

-- Conectar Card_b para abrir a UI de Cards (replicar comportamento de Chars_Inv)
if previewCardButton then
	if previewCardButton.Activated then
		previewCardButton.Activated:Connect(function()
			local sourceId = script:GetAttribute("SelectedEquipSource")
			if not sourceId or sourceId == "" then
				warn("[EquipUI] Card_b clicado sem item selecionado")
				return
			end
			local Players = game:GetService("Players")
			local localPlayer = Players.LocalPlayer
			if not localPlayer then return end
			local playerGui = localPlayer:FindFirstChild("PlayerGui")
			if not playerGui then return end
			local cardsGui = playerGui:FindFirstChild("Cards")
			if not cardsGui then
				warn("[EquipUI] ScreenGui 'Cards' não encontrado no PlayerGui")
				return
			end
			cardsGui:SetAttribute("ShowCharacterCards", sourceId)
			cardsGui.Enabled = true
			dprint(string.format("[EquipUI] Solicitando UI de cartas para sourceId=%s", tostring(sourceId)))
		end)
	else
		previewCardButton.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				local sourceId = script:GetAttribute("SelectedEquipSource")
				if not sourceId or sourceId == "" then
					warn("[EquipUI] Card_b clicado sem item selecionado")
					return
				end
				local Players = game:GetService("Players")
				local localPlayer = Players.LocalPlayer
				if not localPlayer then return end
				local playerGui = localPlayer:FindFirstChild("PlayerGui")
				if not playerGui then return end
				local cardsGui = playerGui:FindFirstChild("Cards")
				if not cardsGui then
					warn("[EquipUI] ScreenGui 'Cards' não encontrado no PlayerGui")
					return
				end
				cardsGui:SetAttribute("ShowCharacterCards", sourceId)
				cardsGui.Enabled = true
				dprint(string.format("[EquipUI] Solicitando UI de cartas para sourceId=%s", tostring(sourceId)))
			end
		end)
	end
end

-- Helpers to manage stat lines (mirrors Chars inventory style, simplified)
local function clearStats()
	if not previewScroll or not statTemplate then return end
	for _, child in ipairs(previewScroll:GetChildren()) do
		if child:IsA("Frame") and child ~= statTemplate then
			child:Destroy()
		end
	end
end

-- Fully hide and clear preview visuals (gradients, images, stats) and clear selection attributes
local function closePreview()
	-- clear selection state
	selectedItemId = nil
	selectedGroup = nil
	pcall(function() script:SetAttribute("SelectedEquipSource", nil) end)

	-- hide container
	if previewContainer then
		previewContainer.Visible = false
	end

	-- remove preview-related gradients inside previewContainer and frame
	local function removeGradients(root)
		if not root then return end
		for _, desc in ipairs(root:GetDescendants()) do
			if desc:IsA("UIGradient") then
				local n = desc.Name
				if n == "PreviewGradient" or n == "RarityGradient" or n == "MainRarityGradient" or n == "RarityPlaceholder" then
					pcall(function() desc:Destroy() end)
				end
			end
		end
	end
	pcall(removeGradients, previewContainer)
	pcall(removeGradients, frame)
	-- Remove the overlay frame if it exists (created by applyMainGradient)
	pcall(function()
		local overlay = frame and frame:FindFirstChild("MainRarityOverlay")
		if overlay and overlay:IsA("Frame") then overlay:Destroy() end
	end)

	-- clear preview icon and stat lines
	if previewIconImage and (previewIconImage:IsA("ImageLabel") or previewIconImage:IsA("ImageButton")) then
		pcall(function() previewIconImage.Image = "rbxassetid://0" end)
	end
	pcall(clearStats)
end

local function addStatLine(statName, value)
	if not previewScroll or not statTemplate then return end
	-- Defensive: ensure statName is a non-empty string (avoid empty stat rows)
	if statName == nil or (type(statName) == "string" and statName:match("^%s*$")) then
		dprint(string.format("[EquipUI][addStatLine] blank statName detected, defaulting to 'rusty' (value=%s)", tostring(value)))
		statName = "rusty"
	end
	local clone = statTemplate:Clone()
	clone.Name = "Stat_" .. statName
	clone.Visible = true
	local label = clone:FindFirstChild("stat_text", true)
	if label and label:IsA("TextLabel") then
		if typeof(value) == "number" then
			value = math.floor(value + 0.5)
		end
		label.Text = string.format("%s: %s", statName, tostring(value))
	end

	-- Gradient especial se esta linha for uma qualidade (nome do stat == quality string e value vazio)
	local qualityColorMap = {
		rusty = Color3.fromRGB(130,130,130),
		worn = Color3.fromRGB(150,150,150),
		new = Color3.fromRGB(90,170,255),
		polished = Color3.fromRGB(70,200,90),
		perfect = Color3.fromRGB(255,190,40),
		artifact = Color3.fromRGB(255,90,220),
	}
	local base = qualityColorMap[statName]
	if base then
		-- Remover eventual background existente para garantir contraste
		local h,s,v = base:ToHSV()
		local lighter = Color3.fromHSV(h, math.clamp(s*0.25,0,1), 1)
		local darker = Color3.fromHSV(h, s, math.max(v*0.18, 0.05))
		local grad = clone:FindFirstChild("QualityGradient")
		if not grad then
			grad = Instance.new("UIGradient")
			grad.Name = "QualityGradient"
			grad.Rotation = 90
			grad.Parent = clone
		end
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, lighter),
			ColorSequenceKeypoint.new(0.45, base),
			ColorSequenceKeypoint.new(1, darker),
		})
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0,0),
			NumberSequenceKeypoint.new(1,0),
		})
		clone.BackgroundColor3 = base
		clone.BackgroundTransparency = 0
		-- Se o value for vazio (""), remover os dois pontos do texto
		if label and label.Text and label.Text:sub(-2) == ": " then
			label.Text = statName -- só a palavra
		elseif label and label.Text:match("^"..statName..":%s*$") then
			label.Text = statName
		end
	end
	clone.Parent = previewScroll
end

-- Forward declaration; real body defined after helper functions so we capture locals instead of globals
local updatePreview
-- Forward declare stats resolver so updatePreview captures the LOCAL (not global)
local resolveStatsModule
-- Forward declare closeSellConfirm so outer scopes (hide) can call it safely
local closeSellConfirm

-- Raridades suportadas
local RarityColors = {
	comum    = Color3.fromRGB(60,190,90),   -- verde (#3CBE5A)
	raro     = Color3.fromRGB(70,130,255),  -- azul (#4682FF)
	epico    = Color3.fromRGB(180,85,255),  -- roxo (#B455FF)
	lendario = Color3.fromRGB(255,190,40),  -- dourado (#FFBE28)
	mitico   = Color3.fromRGB(255,50,50),   -- vermelho (#FF3232)
}

-- Map external rarity labels (English/Portuguese, case-insensitive) to our keys
local function mapRarityKey(raw)
	if raw == nil then return "comum" end
	local t = typeof(raw)
	if t == "number" then
		local n = math.floor(raw)
		if n <= 1 then return "comum" end
		if n == 2 then return "raro" end
		if n == 3 then return "epico" end
		if n >= 4 then return "lendario" end
	end
	local s = tostring(raw):lower()
	if s:find("legend") or s:find("lend") then return "lendario" end
	if s:find("epic") or s:find("épico") or s:find("epico") then return "epico" end
	if s:find("rare") or s:find("raro") then return "raro" end
	if s:find("myth") or s:find("mit") then return "mitico" end
	if s:find("common") or s:find("comum") then return "comum" end
	return "comum"
end

-- Try to resolve rarity from item stats module first, then template keywords
local function resolveRarity(itemType, templateName, preloadedStats)
	local stats = preloadedStats
	if not stats then
		local ok, mod = pcall(function() return resolveStatsModule(itemType, templateName) end)
		if ok then stats = mod end
	end
	if type(stats) == "table" then
		-- accept fields: rarity/Rarity or stars
		if stats.rarity ~= nil then return mapRarityKey(stats.rarity), RarityColors[mapRarityKey(stats.rarity)] end
		if stats.Rarity ~= nil then return mapRarityKey(stats.Rarity), RarityColors[mapRarityKey(stats.Rarity)] end
		if stats.stars ~= nil then return mapRarityKey(stats.stars), RarityColors[mapRarityKey(stats.stars)] end
	end
	-- Fallback: template name keywords
	local lower = string.lower(templateName or "")
	local key
	if lower:find("legend") or lower:find("lend") then key = "lendario" end
	if not key and (lower:find("epic") or lower:find("épico") or lower:find("epico")) then key = "epico" end
	if not key and (lower:find("rare") or lower:find("raro")) then key = "raro" end
	if not key and (lower:find("myth") or lower:find("mit")) then key = "mitico" end
	key = key or "comum"
	return key, RarityColors[key]
end

-- Qualidade dos itens (multiplicadores) replicado do ItemQualities
local ItemQualitiesModule = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("Items") and ReplicatedStorage.Shared.Items:FindFirstChild("ItemQualities")
local QualityMultipliers = {
	rusty = 0, worn = 0.03, new = 0.06, polished = 0.09, perfect = 0.12, artifact = 0.15,
}
do
	if ItemQualitiesModule and ItemQualitiesModule:IsA("ModuleScript") then
		local ok, qm = pcall(require, ItemQualitiesModule)
		if ok and type(qm) == "table" then
			for k,v in pairs(qm) do
				if type(v) == "number" then QualityMultipliers[k] = v end
			end
		end
	end
end

-- Helper: generic per-level multiplier when Stats.Levels is not defined
local function itemLevelMultiplier(level)
	level = tonumber(level) or 1
	if level <= 1 then return 1 end
	-- Fallback model: +2% per level over base
	return 1 + 0.02 * (level - 1)
end

-- Compute stats for a given item at a specific level and quality.
-- Uses Stats.Levels[level] when present; falls back to generic +2%/level scaling.
-- Returns a flat table of numeric statName -> value at that level (quality-applied), and the raw stats module.
local function computeItemStatsAtLevel(itemType, templateName, quality, level)
	local stats = resolveStatsModule and resolveStatsModule(itemType, templateName)
	if not stats or type(stats) ~= "table" then
		return {}, nil
	end
	level = tonumber(level) or 1
	local qMult = 1 + (QualityMultipliers[quality] or 0)

	-- Collect base numeric stats from top-level, excluding known non-stat keys
	local base = {}
	for k, v in pairs(stats) do
		if typeof(v) == "number" then
			base[k] = v
		end
	end

	-- If Levels table exists and contains this level, merge/override with that level
	local levelsTbl = stats.Levels
	local merged = {}
	if type(levelsTbl) == "table" and levelsTbl[level] and type(levelsTbl[level]) == "table" then
		-- start with base defaults, then override with level-specific entries
		for k, v in pairs(base) do merged[k] = v end
		for k, v in pairs(levelsTbl[level]) do
			if typeof(v) == "number" then
				merged[k] = v
			end
		end
	else
		-- No per-level stats; apply generic scaling to base
		local mult = itemLevelMultiplier(level)
		for k, v in pairs(base) do
			merged[k] = v * mult
		end
	end

	-- Apply quality multiplier
	for k, v in pairs(merged) do
		merged[k] = v * qMult
	end

	return merged, stats
end

-- Função para criar (ou atualizar) gradiente num frame baseado em cor base
local function applyRarityGradient(frameObj, baseColor)
	if not frameObj or not baseColor then return end
	local grad = frameObj:FindFirstChild("RarityGradient")
	local h,s,v = baseColor:ToHSV()
	local lighter = Color3.fromHSV(h, math.clamp(s*0.25,0,1), 1)
	local darker = Color3.fromHSV(h, s, math.clamp(v*0.25,0,1))
	if not grad then
		grad = Instance.new("UIGradient")
		grad.Name = "RarityGradient"
		grad.Rotation = 90
		grad.Parent = frameObj
	end
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, lighter),
		ColorSequenceKeypoint.new(0.45, baseColor),
		ColorSequenceKeypoint.new(1, darker),
	})
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,0),
		NumberSequenceKeypoint.new(1,0),
	})
	frameObj.BackgroundColor3 = baseColor
	frameObj.BackgroundTransparency = 0
end

-- Versão usada apenas no PREVIEW para imitar animação/estilo do Chars (gradient horizontal, mais suave)
local function ensurePreviewGradient(frameObj, baseColor)
	if not frameObj or not baseColor then return end
	local grad = frameObj:FindFirstChild("PreviewGradient")
	local h,s,v = baseColor:ToHSV()
	local lighter = Color3.fromHSV(h, math.clamp(s * 0.15, 0, 1), 1)
	local darkerV = math.max(v * 0.15, 0.05)
	local darker = Color3.fromHSV(h, s, darkerV)
	if not grad then
		grad = Instance.new("UIGradient")
		grad.Name = "PreviewGradient"
		grad.Rotation = 0 -- horizontal como em Chars
		grad.Parent = frameObj
	end
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, lighter),
		ColorSequenceKeypoint.new(0.45, baseColor),
		ColorSequenceKeypoint.new(1, darker),
	})
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,0),
		NumberSequenceKeypoint.new(1,0),
	})
	if frameObj:IsA("Frame") then
		frameObj.BackgroundColor3 = baseColor
		frameObj.BackgroundTransparency = 0
	end
end

-- Obter raridade de um item. (Placeholder: inferir por nome; depois pode vir de Stats Module)
local function inferRarity(itemId)
	local lower = string.lower(itemId or "")
	if lower:find("myth") or lower:find("mit") then return "mitico" end
	if lower:find("legend") or lower:find("lend") then return "lendario" end
	if lower:find("epic") or lower:find("epic") then return "epico" end
	if lower:find("rare") or lower:find("raro") then return "raro" end
	return "comum"
end

-- Gradiente principal do fundo (Frame raiz) baseado na raridade selecionada
local function applyMainGradient(baseColor)
	if not frame or not baseColor then return end
	-- Use an overlay Frame to apply the main rarity gradient so we don't clobber the
	-- designer's root Frame background (prevents a persistent solid rectangle).
	local overlay = frame:FindFirstChild("MainRarityOverlay")
	local h,s,v = baseColor:ToHSV()
	local lighter = Color3.fromHSV(h, math.clamp(s * 0.18,0,1), 1)
	local mid = baseColor
	local darker = Color3.fromHSV(h, s, math.max(v*0.12, 0.05))
	if not overlay then
		overlay = Instance.new("Frame")
		overlay.Name = "MainRarityOverlay"
		overlay.Size = UDim2.new(1,0,1,0)
		overlay.Position = UDim2.new(0,0,0,0)
		overlay.AnchorPoint = Vector2.new(0,0)
		overlay.BackgroundTransparency = 1
		overlay.ZIndex = (frame.ZIndex or 1) - 1 -- keep behind content
		overlay.Parent = frame
	end
	local grad = overlay:FindFirstChild("MainRarityGradient")
	if not grad then
		grad = Instance.new("UIGradient")
		grad.Name = "MainRarityGradient"
		grad.Rotation = 90
		grad.Parent = overlay
	end
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, lighter),
		ColorSequenceKeypoint.new(0.55, mid),
		ColorSequenceKeypoint.new(1, darker),
	})
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,0),
		NumberSequenceKeypoint.new(1,0),
	})
end

-- Agora que RarityColors / applyRarityGradient / inferRarity existem, definimos updatePreview corretamente
updatePreview = function(itemEntry)
	if not previewContainer or not itemEntry then return end
	-- Ensure the preview container is visible whenever we update the preview
	-- (previously we only made it visible on first update via previewInitiallyHidden;
	--  that prevents reopening after closePreview() when a sale happens)
	if previewContainer then
		previewContainer.Visible = true
		previewInitiallyHidden = false
	end
	-- Prefer the live entry from currentItems so visibility reflects latest state
	if itemEntry.id and itemEntry.group then
		local foundMatch = false
		if currentItems and type(currentItems) == "table" then
			for _, e in ipairs(currentItems) do
				if e.id == itemEntry.id and e.group == itemEntry.group then
					itemEntry = e
					foundMatch = true
					break
				end
			end
		end
		-- If we had an id/group but didn't find it in currentItems, it may have been removed
		if not foundMatch then
			-- log but fall back to the passed itemEntry so preview can still open
			print(string.format("[EquipUI][preview] clicked item %s/%s not found in currentItems (possible timing after sell). Using passed entry for preview.", tostring(itemEntry.group), tostring(itemEntry.id)))
		end
	end

	local templateName = (itemEntry.data and itemEntry.data.Template) or itemEntry.id
	local rarityKey, baseColor = resolveRarity(itemEntry.group, templateName)
	if not baseColor then
		warn(string.format("[EquipUI][preview] RarityColors['%s'] nil -> usando branco", tostring(rarityKey)))
		baseColor = Color3.fromRGB(255,255,255)
	end
	-- Apply rarity gradient only to the preview icon area to avoid tinting the entire panel
	local iconTarget = nil
	if previewIconImage and (previewIconImage:IsA("ImageLabel") or previewIconImage:IsA("ImageButton")) then
		iconTarget = previewIconImage.Parent or previewIconImage
	elseif previewIconFrame then
		iconTarget = previewIconFrame
	end
	if iconTarget then
		local ok, err = pcall(function()
			applyRarityGradient(iconTarget, baseColor)
		end)
		if not ok then warn("[EquipUI][preview] applyRarityGradient erro: "..tostring(err)) end
	end
	-- Update main background with a subtle neutralization instead of full tint to keep preview readable
	-- Only change the main background if it's currently fully transparent to avoid clobbering designer intent
	local currentMainGrad = frame:FindFirstChild("MainRarityGradient")
	if not currentMainGrad then
		-- create a very subtle overlay to hint rarity without dominating the whole panel
		local subtle = Color3.fromRGB(20,20,20)
		applyMainGradient(subtle)
	end
	local stats = nil -- keep reference for later (icon + stat lines)
	if previewIconImage then
		stats = resolveStatsModule and resolveStatsModule(itemEntry.group, templateName)
		local img = (stats and (stats.iscon or stats.icon or stats.Icon)) or ""
		-- Fallback: tenta copiar a imagem do ícone na lista se existir
		if img == "" or img == nil then
			local listIcon = nil
			local cloneName = string.format("%s_%s", itemEntry.group, itemEntry.id)
			local cloneFrame = scrolling:FindFirstChild(cloneName)
			if cloneFrame then
				listIcon = cloneFrame:FindFirstChild("icon") or cloneFrame:FindFirstChild("Icon") or cloneFrame:FindFirstChild("ImageLabel")
			end
			if listIcon and (listIcon:IsA("ImageLabel") or listIcon:IsA("ImageButton")) and listIcon.Image ~= "" then
				img = listIcon.Image
			end
		end
		if img == "" or img == nil then
			img = "rbxassetid://0"
		end
		if (previewIconImage:IsA("ImageLabel") or previewIconImage:IsA("ImageButton")) then
			previewIconImage.Image = img
			dprint(string.format("[EquipUI][previewIcon] Icon aplicado '%s' (stats=%s) para %s/%s", img, stats and "ok" or "nil", tostring(itemEntry.group), tostring(templateName)))
		end
	end
	if previewLevelLabel then
		previewLevelLabel.Text = templateName
	end
	-- STAT LINES --------------------------------------
	if previewScroll and statTemplate then
		clearStats()
		-- Defensive: sanitize Quality (nil, empty, whitespace -> default)
		local q = (itemEntry.data and itemEntry.data.Quality)
		if q == nil or (type(q) == "string" and q:match("^%s*$")) then
			if q ~= nil then
				dprint(string.format("[EquipUI][preview] blank Quality detected for %s/%s -> defaulting to 'rusty'", tostring(itemEntry.group), tostring(itemEntry.id)))
			end
			q = "rusty"
			if itemEntry.data then itemEntry.data.Quality = q end
		end

		-- Always show the quality header line
		addStatLine(q, "")

		-- Determine the current level of the item (default 1)
		local curLevel = (itemEntry.data and tonumber(itemEntry.data.Level)) or 1
		local computed, rawStats = computeItemStatsAtLevel(itemEntry.group, templateName, q, curLevel)
		if not rawStats then
			addStatLine("info", "no stats module")
		else
			-- Preferred order list; any remaining numeric keys appended alphabetically
			local preferred = {"BaseDamage","Damage","AttackSpeed","CritChance","CritDamage","Defense","Health","Power"}
			local shown = {}
			for _, key in ipairs(preferred) do
				local v = computed[key]
				if typeof(v) == "number" then
					addStatLine(key, v)
					shown[key] = true
				end
			end
			local extra = {}
			for k, v in pairs(computed) do
				if typeof(v) == "number" and not shown[k] then
					table.insert(extra, k)
				end
			end
			table.sort(extra)
			for _, k in ipairs(extra) do
				addStatLine(k, computed[k])
			end
		end
	end
	---------------------------------------------------
	selectedItemId = itemEntry.id
	selectedGroup = itemEntry.group
	-- Tornar sourceId disponível para a UI de cartas (mesma key usada em Chars: ShowCharacterCards)
	local sourceId = (itemEntry.data and itemEntry.data.Template) or itemEntry.id
	script:SetAttribute("SelectedEquipSource", sourceId)
	dprint(string.format("[EquipUI][preview] Selecionado %s/%s (raridade=%s nome=%s)", tostring(selectedGroup), tostring(selectedItemId), tostring(rarityKey), tostring(templateName)))

	-- Update Equip / Unequip button visibility based on current equipped flag
	local isEquipped = itemEntry.data and itemEntry.data.Equipped
	if previewEquipButton and previewEquipButton:IsA("GuiButton") then
		previewEquipButton.Visible = not isEquipped
	end
	if previewUnequipButton and previewUnequipButton:IsA("GuiButton") then
		previewUnequipButton.Visible = isEquipped
	end

	-- Diagnostic: ensure at least one stat line exists for quality; if missing, dump previewScroll children for debugging
	if previewScroll then
		local foundQualityLine = false
		for _, child in ipairs(previewScroll:GetChildren()) do
			if child:IsA("Frame") and child.Name:sub(1,5) == "Stat_" then
				local lbl = child:FindFirstChild("stat_text", true)
				if lbl and lbl:IsA("TextLabel") then
					local text = lbl.Text or ""
					for qual, _ in pairs(QualityMultipliers) do
						if text:lower():find(qual) then foundQualityLine = true break end
					end
				end
			end
		end
		if not foundQualityLine then
			print(string.format("[EquipUI][DIAG] No quality stat found for preview %s/%s - dumping children:", tostring(itemEntry.group), tostring(itemEntry.id)))
			for _, child in ipairs(previewScroll:GetChildren()) do
				if child:IsA("Frame") then
					local lbl = child:FindFirstChild("stat_text", true)
					local text = lbl and lbl:IsA("TextLabel") and lbl.Text or "<no-label>"
					print(string.format("  child='%s' Name='%s' Visible=%s Text='%s'", tostring(child.ClassName), tostring(child.Name), tostring(child.Visible), tostring(text)))
				else
					print(string.format("  child='%s' Name='%s' Visible=%s", tostring(child.ClassName), tostring(child.Name), tostring(child.Visible)))
				end
			end
			-- Inject fallback quality stat so UI never shows an empty Colors header
			addStatLine("rusty", "")
			if itemEntry.data then itemEntry.data.Quality = "rusty" end
			print(string.format("[EquipUI][DIAG] Injected fallback Quality 'rusty' for preview %s/%s", tostring(itemEntry.group), tostring(itemEntry.id)))
		end
	end
end

-- (currentItems já declarado no topo; manter referência única)

local function clearIcons()
	for _, child in ipairs(scrolling:GetChildren()) do
		if child:IsA("Frame") and child ~= template then
			child:Destroy()
		end
	end
end

function resolveStatsModule(itemType, templateName)
	-- Navegar em ReplicatedStorage.Shared.Items.<CategoryPlural>.<Template>.Stats
	local Shared = ReplicatedStorage:FindFirstChild("Shared")
	if not Shared then
		print(string.format("[EquipUI][iconImage] Shared ausente (itemType=%s, template=%s)", tostring(itemType), tostring(templateName)))
		return nil
	end
	local ItemsFolder = Shared:FindFirstChild("Items")
	if not ItemsFolder then
		print(string.format("[EquipUI][iconImage] Items folder ausente (itemType=%s, template=%s)", tostring(itemType), tostring(templateName)))
		return nil
	end
	local categoryFolder = ItemsFolder:FindFirstChild(itemType)
	if not categoryFolder then
		print(string.format("[EquipUI][iconImage] Category folder '%s' não encontrado", tostring(itemType)))
		return nil
	end
	local templateFolder = categoryFolder:FindFirstChild(templateName)
	if not templateFolder then
		print(string.format("[EquipUI][iconImage] Template folder '%s' não encontrado em %s", tostring(templateName), tostring(itemType)))
		return nil
	end
	local statsModule = templateFolder:FindFirstChild("Stats")
	if statsModule and statsModule:IsA("ModuleScript") then
		local ok, stats = pcall(require, statsModule)
		if ok then
			return stats
		else
			print(string.format("[EquipUI][iconImage] require falhou para %s/%s: %s", tostring(itemType), tostring(templateName), tostring(stats)))
		end
	else
		print(string.format("[EquipUI][iconImage] Stats module ausente para %s/%s", tostring(itemType), tostring(templateName)))
	end
	return nil
end

local function createIcon(itemType, itemId, data)
	local clone = template:Clone()
	clone.Name = itemType .. "_" .. itemId
	clone.Visible = true
	dprint(string.format("[EquipUI][createIcon] %s id=%s level=%s", itemType, itemId, tostring(data and data.Level)))
	local templateName = (data and data.Template) or itemId
	local _, baseColor = resolveRarity(itemType, templateName)
	baseColor = baseColor or Color3.fromRGB(255,255,255)
	-- Reusar UIGradient existente se houver (em vez de criar RarityGradient novo)
	local existingGrad = clone:FindFirstChild("UIGradient") or clone:FindFirstChild("RarityGradient")
	if existingGrad and existingGrad:IsA("UIGradient") then
		local h,s,v = baseColor:ToHSV()
		local lighter = Color3.fromHSV(h, math.clamp(s*0.25,0,1), 1)
		local darker = Color3.fromHSV(h, s, math.clamp(v*0.25,0,1))
		existingGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, lighter),
			ColorSequenceKeypoint.new(0.45, baseColor),
			ColorSequenceKeypoint.new(1, darker),
		})
		existingGrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0,0),
			NumberSequenceKeypoint.new(1,0),
		})
		-- garantir rotação vertical (caso queira fixo)
		existingGrad.Rotation = existingGrad.Rotation or 90
		clone.BackgroundColor3 = baseColor
		clone.BackgroundTransparency = 0
	else
		applyRarityGradient(clone, baseColor)
	end
	-- Level label fallback
	local levelLabel = clone:FindFirstChild("Level", true)
	if levelLabel and levelLabel:IsA("TextLabel") then
		levelLabel.Text = string.format("Lv %d", (data and data.Level) or 1)
	end
	-- Icon image fallback (assume ImageLabel child)
	local iconImage = clone:FindFirstChild("icon") or clone:FindFirstChild("Icon") or clone:FindFirstChild("ImageLabel")
	if iconImage and (iconImage:IsA("ImageLabel") or iconImage:IsA("ImageButton")) then
		local stats = resolveStatsModule(itemType, templateName)
		local img = (stats and (stats.iscon or stats.icon or stats.Icon)) or "rbxassetid://0"
		if img == "" then img = "rbxassetid://0" end
	iconImage.Image = img
	dprint(string.format("[EquipUI][iconImage] Aplicado img=%s para %s/%s stats=%s", img, tostring(itemType), tostring(templateName), stats and "ok" or "nil"))
		-- Garantir ordem: imagem abaixo, Level acima
		iconImage.ZIndex = 1
		local lvl = clone:FindFirstChild("Level", true)
		if lvl and lvl:IsA("TextLabel") then
			lvl.ZIndex = 2
		end
		if data and data.Equipped then
			-- simples overlay para item equipado (ex: borda mais opaca)
			clone.BorderSizePixel = 2
			clone.BorderColor3 = Color3.fromRGB(255,255,255)
		end
	else
		dprint(string.format("[EquipUI][iconImage] Nenhum ImageLabel/Button válido encontrado em clone %s", clone.Name))
	end
	local rarityKey = select(1, resolveRarity(itemType, templateName))
	clone:SetAttribute("Rarity", rarityKey)
	clone:SetAttribute("ItemType", itemType)
	clone:SetAttribute("ItemId", itemId)
	clone.Parent = scrolling

	-- Equip badge (similar ao chars). Usa data.Equipped flag
	local function ensureEquipBadge(parent)
		if not parent then return end
		local existing = parent:FindFirstChild("EquipBadge")
		if existing then return existing end
		local b = Instance.new("Frame")
		b.Name = "EquipBadge"
		b.AnchorPoint = Vector2.new(1,0)
		b.Size = UDim2.fromScale(0.30, 0.30)
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
		return b
	end

	if data and data.Equipped then
		ensureEquipBadge(clone)
	end

	-- Click para atualizar preview
	local btn = clone:FindFirstChild("icon") or clone:FindFirstChild("Icon") or clone
	if btn and (btn:IsA("ImageButton") or btn:IsA("ImageLabel") or btn:IsA("GuiObject")) then
		if btn.Activated then
			btn.Activated:Connect(function()
				updatePreview({ group = itemType, id = itemId, data = data })
			end)
		else
			btn.InputBegan:Connect(function(input)
				if input.UserInputType.Name == "MouseButton1" or input.UserInputType.Name == "Touch" then
					updatePreview({ group = itemType, id = itemId, data = data })
				end
			end)
		end
	end

	-- Double-click to equip quickly (client request to server)
	if btn and EquipItemRE then
		local lastClick = 0
		btn.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				local now = tick()
				if now - lastClick < 0.35 then
					-- Determine slot from category and fire server equip
					local slot = nil
					if itemType == "Weapons" then slot = "Weapon" end
					if itemType == "Armors" then slot = "Armor" end
					if itemType == "Rings" then slot = "Ring" end
					if slot then
						EquipItemRE:FireServer(itemId)
						print(string.format("[EquipUI] Requested equip %s (slot=%s)", tostring(itemId), slot))
					end
				end
				lastClick = now
			end
		end)
	end
end

-- Helper to apply rarity gradient + icon inside a slot frame (moved after helper definitions)
local function populateSlot(slotFrame, itemEntry)
	if not slotFrame then return end
	for _, child in ipairs(slotFrame:GetChildren()) do
		if child:IsA("ImageLabel") or child:IsA("ImageButton") then
			child:Destroy()
		end
	end
	-- If no item equipped for this slot, render a dark gray gradient placeholder
	if not itemEntry then
		-- remove any existing gradient instances that reflect rarity
		for _, g in ipairs(slotFrame:GetChildren()) do
			if g:IsA("UIGradient") and (g.Name == "RarityGradient" or g.Name == "PreviewGradient" or g.Name == "RarityPlaceholder") then
				g:Destroy()
			end
		end
		-- Apply dark gray placeholder gradient
		local baseColor = Color3.fromRGB(32,32,32) -- dark gray
		local grad = slotFrame:FindFirstChild("RarityPlaceholder")
		if not grad then
			grad = Instance.new("UIGradient")
			grad.Name = "RarityPlaceholder"
			grad.Rotation = 90
			grad.Parent = slotFrame
		end
		local h,s,v = baseColor:ToHSV()
		local lighter = Color3.fromHSV(h, 0, math.clamp(v * 1.15, 0, 1))
		local darker = Color3.fromHSV(h, 0, math.clamp(v * 0.6, 0, 1))
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, lighter),
			ColorSequenceKeypoint.new(0.5, baseColor),
			ColorSequenceKeypoint.new(1, darker),
		})
		grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0), NumberSequenceKeypoint.new(1,0) })
		slotFrame.BackgroundColor3 = baseColor
		slotFrame.BackgroundTransparency = 0
		-- Add subtle placeholder icon/text
		local placeholder = Instance.new("ImageLabel")
		placeholder.Name = "EmptyIcon"
		placeholder.BackgroundTransparency = 1
		placeholder.Size = UDim2.fromScale(0.6, 0.6)
		placeholder.Position = UDim2.fromScale(0.2, 0.2)
		placeholder.ZIndex = (slotFrame.ZIndex or 1) + 1
		-- Use a simple default blank image (rbxassetid 0) - designers can replace with a specific asset
		placeholder.Image = "rbxassetid://0"
		placeholder.ImageColor3 = Color3.fromRGB(180,180,180)
		placeholder.Parent = slotFrame
		return
	end
	local templateName = (itemEntry.data and itemEntry.data.Template) or itemEntry.id
	local _, baseColor = resolveRarity(itemEntry.group, templateName)
	baseColor = baseColor or Color3.fromRGB(255,255,255)
	-- Atualizar gradiente existente no slot (UIGradient) se houver
	local existingGrad = slotFrame:FindFirstChild("UIGradient") or slotFrame:FindFirstChild("RarityGradient")
	if existingGrad and existingGrad:IsA("UIGradient") then
		local h,s,v = baseColor:ToHSV()
		local lighter = Color3.fromHSV(h, math.clamp(s*0.25,0,1), 1)
		local darker = Color3.fromHSV(h, s, math.clamp(v*0.25,0,1))
		existingGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, lighter),
			ColorSequenceKeypoint.new(0.45, baseColor),
			ColorSequenceKeypoint.new(1, darker),
		})
		existingGrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0,0),
			NumberSequenceKeypoint.new(1,0),
		})
		-- manter rotação atual do slot
		slotFrame.BackgroundColor3 = baseColor
		slotFrame.BackgroundTransparency = 0
	else
		applyRarityGradient(slotFrame, baseColor)
	end
	local stats = resolveStatsModule and resolveStatsModule(itemEntry.group, templateName)
	local img = (stats and (stats.iscon or stats.icon or stats.Icon)) or "rbxassetid://0"
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(1,1)
	icon.ZIndex = (slotFrame.ZIndex or 1) + 1
	icon.Image = img ~= "" and img or "rbxassetid://0"
	icon.Parent = slotFrame
	icon.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			updatePreview(itemEntry)
		end
	end)
	slotFrame:SetAttribute("ItemName", templateName)
end

-- Build a quick lookup of equipped per category after currentItems built
local function rebuildEquippedSlots()
	if not equippedSlotsContainer then return end
	if not currentItems or type(currentItems) ~= "table" then
		warn("[EquipUI][E_Slots] currentItems nil ou inválido no momento do rebuild")
		return
	end
	local equipped = { Weapon=nil, Armor=nil, Ring=nil }
	local singularMap = { Weapons = "Weapon", Armors = "Armor", Rings = "Ring" }
	for _, entry in ipairs(currentItems) do
		local g = singularMap[entry.group] or entry.group
		if entry.data and entry.data.Equipped and equipped[g] == nil then
			equipped[g] = entry
		end
	end
	for _, entry in ipairs(currentItems) do
		local g = singularMap[entry.group] or entry.group
		if equipped[g] == nil and entry._equippedFromCategory and entry._equippedFromCategory == entry.id then
			equipped[g] = entry
		end
	end
	print(string.format("[EquipUI][E_Slots] Weapon=%s Armor=%s Ring=%s",
		equipped.Weapon and equipped.Weapon.id or "nil",
		equipped.Armor and equipped.Armor.id or "nil",
		equipped.Ring and equipped.Ring.id or "nil"))
	populateSlot(weaponSlot, equipped.Weapon)
	populateSlot(armorSlot, equipped.Armor)
	populateSlot(ringSlot, equipped.Ring)
end

-- ADAPTACAO: agora suporta novo formato Items.Categories[Category].List (Id,Template,Level)
-- com fallback para formato antigo raw Owned.
local function buildListFromProfile(profile)
	currentItems = {}
	if not profile then
		warn("[EquipUI] buildListFromProfile: profile nil")
		return
	end
	if not profile.Items then
		warn("[EquipUI] buildListFromProfile: profile.Items ausente")
		return
	end

	-- Novo formato preferencial: profile.Items.Categories
	local categories = profile.Items.Categories
	if categories and type(categories) == "table" then
		local catCount = 0
		for catName, catData in pairs(categories) do
			catCount += 1
			local list = catData.List
			local equippedId = catData.Equipped
			local perCat = 0
			if type(list) == "table" then
				for _, entry in ipairs(list) do
					-- entry: {Id, Template, Level}
					local q = entry.Quality
					if q == nil or (type(q) == "string" and q:match("^%s*$")) then
						if q ~= nil then
							dprint(string.format("[EquipUI] buildListFromProfile: blank Quality in Categories for %s/%s -> defaulting to 'rusty'", tostring(catName), tostring(entry.Id)))
						end
						q = "rusty"
					end
					currentItems[#currentItems+1] = { group = catName, id = entry.Id, data = { Level = entry.Level, Template = entry.Template, Equipped = (entry.Id == equippedId), Quality = q }, _equippedFromCategory = equippedId }
					perCat += 1
				end
			end
			dprint(string.format("[EquipUI] Categoria %s -> %d instâncias (equipped=%s)", catName, perCat, tostring(equippedId)))
		end
	dprint(string.format("[EquipUI] buildListFromProfile (novo formato): total=%d categorias=%d", #currentItems, catCount))
	else
		-- Fallback antigo: Items.Owned simples
		if not profile.Items.Owned then
			warn("[EquipUI] buildListFromProfile: profile.Items.Owned ausente (snapshot incompleto?)")
			return
		end
		local groupsCount = 0
		for groupName, groupTable in pairs(profile.Items.Owned) do
			if type(groupTable) == "table" then
				groupsCount += 1
				local groupCount = 0
				-- Caso já tenha Instances (depois da migração mas sem Categories por algum motivo)
				if groupTable.Instances then
					for instId, instData in pairs(groupTable.Instances) do
						if instData and (instData.Quality == nil or (type(instData.Quality) == "string" and instData.Quality:match("^%s*$"))) then
							dprint(string.format("[EquipUI] buildListFromProfile: fixing blank Quality for inst=%s template=%s", tostring(instId), tostring(instData and instData.Template)))
							instData.Quality = "rusty"
						end
						currentItems[#currentItems+1] = { group = groupName, id = instId, data = instData }
						groupCount += 1
					end
				else
					for itemId, data in pairs(groupTable) do
						if type(data)=="table" and (data.Quality == nil or (type(data.Quality) == "string" and data.Quality:match("^%s*$"))) then
							dprint(string.format("[EquipUI] buildListFromProfile: fixing blank Quality for legacy item %s in group %s", tostring(itemId), tostring(groupName)))
							data.Quality = "rusty"
						end
						currentItems[#currentItems+1] = { group = groupName, id = itemId, data = data }
						groupCount += 1
					end
				end
				dprint(string.format("[EquipUI] Grupo %s -> %d itens", groupName, groupCount))
			end
		end
		dprint(string.format("[EquipUI] buildListFromProfile (fallback): %d itens flatten (groups=%d)", #currentItems, groupsCount))
		if #currentItems == 0 then
			dprint("[EquipUI][WARN] Nenhum item flatten - verificar ProfileTemplate.Items.Owned")
		end
	end

	-- Ordenação: categoria depois Id
	table.sort(currentItems, function(a,b)
		if a.group == b.group then return a.id < b.id end
		return a.group < b.group
	end)
end

local function render()
	clearIcons()
	for _, entry in ipairs(currentItems) do
		createIcon(entry.group, entry.id, entry.data)
	end
	rebuildEquippedSlots()
	-- Defensive: if the currently previewed item was removed from currentItems, close the preview
	if selectedItemId and selectedGroup then
		local found = false
		for _, e in ipairs(currentItems) do
			if e.id == selectedItemId and e.group == selectedGroup then found = true break end
		end
		if not found then
			dprint(string.format("[EquipUI][render] previewed item %s/%s missing -> leaving preview state intact (reverted)", tostring(selectedGroup), tostring(selectedItemId)))
		end
	end
	-- Reaplicar badges pós-render (caso flags mudem)
	for _, entry in ipairs(currentItems) do
		local name = entry.group .. "_" .. entry.id
		local iconFrame = scrolling:FindFirstChild(name)
		if iconFrame then
			local equipped = entry.data and entry.data.Equipped
			local badge = iconFrame:FindFirstChild("EquipBadge")
			if equipped and not badge then
				-- criar badge rápido (reuse lógica simplificada)
				local b = Instance.new("Frame")
				b.Name = "EquipBadge"
				b.AnchorPoint = Vector2.new(1,0)
				b.Size = UDim2.fromScale(0.30, 0.30)
				b.Position = UDim2.new(1, -2, 0, 2)
				b.BackgroundTransparency = 1
				b.ZIndex = 120
				b.Parent = iconFrame
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
			elseif (not equipped) and badge then
				badge:Destroy()
			end
		end
	end
	-- Auto select primeiro item se nenhum selecionado
	-- Removido auto-select: preview só aparece após clique do utilizador
	-- Ajustar CanvasSize se estiver em 0 (assumindo GridLayout ou AutomaticSize não está ativo)
	local total = 0
	for _, child in ipairs(scrolling:GetChildren()) do
		if child:IsA("Frame") and child ~= template and child.Visible then
			total += 1
		end
	end
	-- Heurística simples: se layout for grid 5 colunas (exemplo) ou fluxo vertical? Sem saber, pelo menos logamos tamanhos
	dprint(string.format("[EquipUI] render: exibidos %d itens (framesVisiveis=%d CanvasSizeY=%d)", #currentItems, total, scrolling.CanvasSize.Y.Offset))
	for _, child in ipairs(scrolling:GetChildren()) do
		if child:IsA("Frame") and child ~= template then
			dprint(string.format("  icon '%s' AbsSize=(%d,%d) Visible=%s BgTrans=%.2f", child.Name, child.AbsoluteSize.X, child.AbsoluteSize.Y, tostring(child.Visible), child.BackgroundTransparency))
		end
	end
	-- Verificar cadeia de ancestors para garantir que nenhum está invisível ou Disabled
	local function chainVisibility(obj)
		local chain = {}
		local cur = obj
		while cur and cur ~= game do
			local segment = cur.Name
			local extra = {}
			if cur:IsA("GuiObject") then
				extra[#extra+1] = "Vis="..tostring(cur.Visible)
			end
			if cur:IsA("LayerCollector") then
				extra[#extra+1] = "Enabled="..tostring(cur.Enabled)
			end
			chain[#chain+1] = segment.."("..table.concat(extra, ",")..")"
			cur = cur.Parent
		end
		return table.concat(chain, " <- ")
	end
	dprint("[EquipUI] Ancestor chain Frame: " .. chainVisibility(frame))
	dprint("[EquipUI] Ancestor chain ScrollingFrame: " .. chainVisibility(scrolling))
	-- Always update CanvasSize based on content (handles both AutomaticCanvasSize and manual modes)
	updateCanvasFromLayout()
end

local function fetchProfile()
	if not GetProfileRF then return end
	local ok, res = pcall(function()
		return GetProfileRF:InvokeServer()
	end)
	if ok and res and res.profile then
	dprint("[EquipUI] fetchProfile: snapshot recebido")
		if res.profile.Items and res.profile.Items.Owned then
			for grp, tbl in pairs(res.profile.Items.Owned) do
				local cnt=0 for _ in pairs(tbl) do cnt+=1 end
				dprint(string.format("  Grupo %s: %d itens", grp, cnt))
			end
		else
			print("[EquipUI] fetchProfile: Items.Owned ausente")
		end
		buildListFromProfile(res.profile)
		render()
		-- Ensure Canvas reflects current content immediately after first render
		updateCanvasFromLayout()
	dprint(string.format("[EquipUI] fetchProfile completo: totalItems=%d isOpen=%s", #currentItems, tostring(isOpen)))
	end
end

local function onProfileUpdated(payload)
	if not payload then return end
	if payload.full and payload.full.Items then
	dprint("[EquipUI] onProfileUpdated: full.Items recebido")
		buildListFromProfile(payload.full)
		render()
	dprint(string.format("[EquipUI] onProfileUpdated(full) completo: totalItems=%d isOpen=%s", #currentItems, tostring(isOpen)))
		return
	end
	if payload.items or (payload.Items and payload.Items.Owned) then
		print("[EquipUI] onProfileUpdated: update parcial de items -> refetch")
		-- placeholder incremental update: refetch tudo (itens são poucos)
		fetchProfile()
		rebuildEquippedSlots()
	end
end

-- Show / Hide simples com tween vertical
local isOpen = false
print("[EquipUI][InitPhase] Script carregado, preparando show/hide handlers")
local hiddenPos = UDim2.new(frame.Position.X.Scale, frame.Position.X.Offset, 1.2, 0)
local shownPos = frame.Position
local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function show()
	if isOpen then return end
	print("[EquipUI][show] solicitada. currentItems=", #currentItems)
	if #currentItems == 0 then
		print("[EquipUI][show] Nenhum item carregado ainda -> fetchProfile()")
		fetchProfile()
	end
	frame.Visible = true
	rootGui.Enabled = true
	frame.Position = hiddenPos
	local tw = TweenService:Create(frame, tweenInfo, { Position = shownPos })
	tw:Play()
	isOpen = true
	script:SetAttribute("Show", true)
	script:SetAttribute("Hide", false)
	print(string.format("[EquipUI][show] concluído: Visible=%s Enabled=%s", tostring(frame.Visible), tostring(rootGui.Enabled)))
end

local function hide()
	if not isOpen then return end
	isOpen = false
	-- Ensure any open Sell panel is closed when hiding the inventory
	pcall(function()
		if typeof(closeSellConfirm) == "function" then
			closeSellConfirm()
		end
	end)
	local tw = TweenService:Create(frame, tweenInfo, { Position = hiddenPos })
	tw:Play()
	tw.Completed:Connect(function()
		if not isOpen then
			frame.Visible = false
			frame.Position = shownPos
		end
	end)
	script:SetAttribute("Hide", true)
	script:SetAttribute("Show", false)
	
end

exitButton.MouseButton1Click:Connect(hide)

-- Não sobrescrever se já estiverem definidos (por outro script antes deste terminar de carregar)
if script:GetAttribute("Show") == nil then script:SetAttribute("Show", false) end
if script:GetAttribute("Hide") == nil then script:SetAttribute("Hide", false) end
script:GetAttributeChangedSignal("Show"):Connect(function()
	local val = script:GetAttribute("Show")
	print("[EquipUI][AttrChange] Show=", tostring(val), " isOpen=", isOpen)
	if val and not isOpen then
		local ok, err = pcall(show)
		if not ok then warn("[EquipUI][AttrChange] show erro: "..tostring(err)) end
	end
end)
script:GetAttributeChangedSignal("Hide"):Connect(function()
	if script:GetAttribute("Hide") then hide() end
end)

if ProfileUpdatedRE and ProfileUpdatedRE:IsA("RemoteEvent") then
	ProfileUpdatedRE.OnClientEvent:Connect(onProfileUpdated)
end

local function getRemote(name)
	if not Remotes then return nil end
	local ok, r = pcall(function() return Remotes:FindFirstChild(name) end)
	if ok and r then return r end
	return nil
end

-- Wire preview equip/unequip buttons (debounced, optimistic)
do
	local function connectClick(guiObj, fn)
		if not guiObj then return end
		-- Prefer Activated (works for many button types), then MouseButton1Click, then InputBegan fallback
		local ok, _ = pcall(function()
			if guiObj.Activated and type(guiObj.Activated.Connect) == "function" then
				guiObj.Activated:Connect(fn)
				return true
			end
			if guiObj.MouseButton1Click and type(guiObj.MouseButton1Click.Connect) == "function" then
				guiObj.MouseButton1Click:Connect(fn)
				return true
			end
			if guiObj.InputBegan and type(guiObj.InputBegan.Connect) == "function" then
				guiObj.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						fn()
					end
				end)
				return true
			end
		end)
		if not ok then
			-- Last resort: try to connect using pcall on MouseButton1Click
			pcall(function()
				if guiObj.MouseButton1Click then guiObj.MouseButton1Click:Connect(fn) end
			end)
		end
	end

	local function doEquip()
		if previewActionPending then return end
		if not selectedItemId or not selectedGroup then warn("[EquipUI] Equip clicked but no selection") return end
		previewActionPending = true
		task.delay(0.6, function() previewActionPending = false end)
		-- optimistic: mark this item equipped locally and hide equip button
		-- Only clear Equipped flag for items in the SAME category (avoid touching other categories)
		local found = nil
		for _, e in ipairs(currentItems) do
			if e.group == selectedGroup then
				if e.id == selectedItemId then
					e.data = e.data or {}
					e.data.Equipped = true
					found = e
				else
					if e.data then e.data.Equipped = false end
				end
			end
		end
		rebuildEquippedSlots()
		if found then pcall(updatePreview, found) end
		-- call server remote safely
		local equipRE = getRemote("EquipItem") or EquipItemRE
		if equipRE and equipRE:IsA("RemoteEvent") and type(equipRE.FireServer) == "function" then
			local ok, err = pcall(function() equipRE:FireServer(selectedItemId) end)
			if not ok then warn("[EquipUI] Equip remote failed:", err) end
		else
			warn("[EquipUI] Equip remote not found; UI updated optimistically only")
		end
	end

	local function doUnequip()
		if previewActionPending then return end
		-- Unequip: if we don't have selectedItemId, try to find the currently equipped item in this category
		if not selectedGroup then warn("[EquipUI] Unequip clicked but no selectedGroup") return end
		local slot = nil
		if selectedGroup == "Weapons" then slot = "Weapon" end
		if selectedGroup == "Armors" then slot = "Armor" end
		if selectedGroup == "Rings" then slot = "Ring" end
		-- find selectedItemId if missing by scanning currentItems for equipped in this group
		if not selectedItemId then
			for _, e in ipairs(currentItems) do
				if e.group == selectedGroup and e.data and e.data.Equipped then
					selectedItemId = e.id
					break
				end
			end
		end
		previewActionPending = true
		task.delay(0.6, function() previewActionPending = false end)
		-- optimistic: mark unequipped locally
		local found = nil
		for _, e in ipairs(currentItems) do
			if e.id == selectedItemId and e.group == selectedGroup then
				e.data = e.data or {}
				e.data.Equipped = false
				found = e
			end
		end
		rebuildEquippedSlots()
		if found then pcall(updatePreview, found) end
		local unequipRE = getRemote("UnequipItem") or UnequipItemRE
		if unequipRE and unequipRE:IsA("RemoteEvent") and type(unequipRE.FireServer) == "function" then
			if slot then
				local ok, err = pcall(function() unequipRE:FireServer(slot) end)
				if not ok then warn("[EquipUI] Unequip remote failed:", err) end
			else
				warn("[EquipUI] Cannot determine slot for group", selectedGroup)
			end
		else
			warn("[EquipUI] Unequip remote not found; UI updated optimistically only")
		end
	end

	connectClick(previewEquipButton, doEquip)
	connectClick(previewUnequipButton, doUnequip)
	-- Wire preview Sell button (if present) and Sell panel actions
	local pendingSellId = nil
	local function openSellConfirm(itemEntry)
		if not sellPanel or not itemEntry then return end
		if sellAnimating then return end
		local templateName = (itemEntry.data and itemEntry.data.Template) or itemEntry.id
		-- Determine rarity from stars/catalog (use same method as preview backgrounds/server)
		local function resolveStarsForEntry(entry)
			-- 1) if an enriched Catalog is present on the entry, use it
			if entry.Catalog and entry.Catalog.stars then return entry.Catalog.stars end
			-- 2) try resolveStatsModule (local stats module) which may contain stars
			local template = (entry.data and entry.data.Template) or entry.id
			local ok, stats = pcall(function() return resolveStatsModule(entry.group, template) end)
			if ok and stats and stats.stars then return stats.stars end
			-- 3) fallback: parse suffix _N on template name
			if template then
				local suf = template:match("_(%d+)$")
				if suf then return tonumber(suf) end
			end
			-- default to 1 star (comum)
			return 1
		end
		local function starsToRarity(s)
			s = tonumber(s) or 1
			if s <= 1 then return "comum" end
			if s == 2 then return "raro" end
			if s == 3 then return "epico" end
			return "lendario"
		end
		local stars = resolveStarsForEntry(itemEntry)
		local rarity = starsToRarity(stars)
		local displayMap = {
			comum = "100",
			raro = "500",
			epico = "1000",
			lendario = "2500",
		}
		local displayText = displayMap[rarity] or "100"
		pendingSellId = itemEntry.id
		sellPanel.Visible = true
		local finalPos = sellPanel.Position
		local absY = sellPanel.AbsoluteSize.Y
		if absY == 0 then task.wait() absY = sellPanel.AbsoluteSize.Y end
		if absY == 0 then absY = 200 end
		local startPos = UDim2.new(finalPos.X.Scale, finalPos.X.Offset, -1, -absY)
		sellPanel.Position = startPos
		sellAnimating = true
		pcall(function() TweenService:Create(sellPanel, TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = finalPos }):Play() end)
		task.delay(0.34, function() sellAnimating = false end)
		if sellText1 and sellText1:IsA("TextLabel") then
			sellText1.Text = string.format("Do you want to sell %s for", tostring(templateName))
		end
		if sellText2 and sellText2:IsA("TextLabel") then
			sellText2.Text = displayText
		end
	end

	closeSellConfirm = function()
		if not sellPanel or not sellPanel.Visible or sellAnimating then return end
		local finalPos = sellPanel.Position
		local absY = sellPanel.AbsoluteSize.Y
		if absY == 0 then absY = 200 end
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

	if previewSellButton then
		if previewSellButton:IsA("ImageButton") then
			previewSellButton.MouseButton1Click:Connect(function()
				if not selectedItemId or not selectedGroup then
					warn("[EquipUI] Sell clicado sem seleção")
					return
				end
				-- find the current selected entry
				local found = nil
				for _, e in ipairs(currentItems) do
					if e.group == selectedGroup and e.id == selectedItemId then found = e break end
				end
				if not found then warn("[EquipUI] Sell: selected item not found in currentItems") return end
				-- prevent selling equipped items
				if found.data and found.data.Equipped then
					warn("[EquipUI] Não podes vender um item equipado")
					return
				end
				openSellConfirm(found)
			end)
		end
	end

	if sellNoButton and sellNoButton:IsA("ImageButton") then
		sellNoButton.MouseButton1Click:Connect(function()
			closeSellConfirm()
		end)
	end

	if sellYesButton and sellYesButton:IsA("ImageButton") then
		sellYesButton.MouseButton1Click:Connect(function()
			if not pendingSellId then return end
			local sellRE = getRemote("SellItem") or Remotes:FindFirstChild("SellItem")
			if not sellRE then
				-- fallback: optimistic local removal and close
				for i = #currentItems, 1, -1 do
					if currentItems[i] and currentItems[i].id == pendingSellId then
						table.remove(currentItems, i)
						break
					end
				end
				rebuildEquippedSlots()
				render()
				-- If the sold item was the one currently previewed, clear selection and hide preview
				if selectedItemId and selectedItemId == pendingSellId then
					pcall(function() closePreview() end)
				end
				closeSellConfirm()
				print(string.format("[EquipUI] Sold item locally (no remote) -> %s", tostring(pendingSellId)))
				pendingSellId = nil
				return
			end
			-- Call remote safely
			local ok, err = pcall(function() sellRE:FireServer(pendingSellId) end)
			if not ok then warn("[EquipUI] Sell remote failed:", err) end
			-- optimistic removal
			for i = #currentItems, 1, -1 do
				if currentItems[i] and currentItems[i].id == pendingSellId then
					table.remove(currentItems, i)
					break
				end
			end
			rebuildEquippedSlots()
			render()
			-- If the sold item was the one currently previewed, clear selection and hide preview
			if selectedItemId and selectedItemId == pendingSellId then
				pcall(function() closePreview() end)
			end
			closeSellConfirm()
			pendingSellId = nil
		end)
	end
end

dprint("[EquipUI] Inicializado. Aguardando Show... (Show=", tostring(script:GetAttribute("Show")), ")")

if previewContainer then
	-- Start preview hidden on init: keep the preview invisible until the user clicks an item.
	-- Also call closePreview() defensively to remove any leftover gradients/images from designer artifacts.
	previewInitiallyHidden = true
	pcall(function() closePreview() end)
end

-- Começar invisível / fechado
frame.Visible = false

-- Se algum outro controlador já marcou Show=true antes deste ponto, abrir imediatamente
if script:GetAttribute("Show") then
	dprint("[EquipUI][PostInit] Show já true ao carregar -> abrir")
	local ok, err = pcall(show)
	if not ok then warn("[EquipUI][PostInit] show erro: "..tostring(err)) end
end

-- Extra fallback: clique em qualquer parte do frame tenta abrir se Show attr estiver true
frame.InputBegan:Connect(function()
	if script:GetAttribute("Show") and not isOpen then
		dprint("[EquipUI][FallbackClick] Frame clicado com Show=true mas isOpen=false -> tentar show()")
		local ok, err = pcall(show)
		if not ok then warn("[EquipUI][FallbackClick] show erro: "..tostring(err)) end
	end
end)

-- Fallback: tentar obter profile alguns segundos depois caso o utilizador abra Equip antes de qualquer outro
task.delay(2, function()
	if #currentItems == 0 then
	dprint("[EquipUI] Fallback fetch após delay inicial")
		fetchProfile()
	end
end)