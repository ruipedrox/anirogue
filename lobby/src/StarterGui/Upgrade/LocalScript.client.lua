-- Upgrade UI LocalScript: open the '1st' panel via server-triggered remotes (mirrors Summon/Chest pattern)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local openRemote = remotes:FindFirstChild("Open_Upgrade") or remotes:WaitForChild("Open_Upgrade")
local UpgradeClientReadyRE = remotes:FindFirstChild("UpgradeClientReady") or remotes:WaitForChild("UpgradeClientReady")
local openUpgradeFunction = remotes:FindFirstChild("OpenUpgradeFunction") or remotes:WaitForChild("OpenUpgradeFunction")

local root = script.Parent -- expected: ScreenGui 'Upgrade'
local isScreenGui = root and root:IsA("ScreenGui")

-- Light references to item registry to resolve icons/rarity like Equip
local Shared = ReplicatedStorage:FindFirstChild("Shared")
local ItemsShared = Shared and Shared:FindFirstChild("Items")
local ItemRegistry = ItemsShared and ItemsShared:FindFirstChild("Registry")
local ItemQualities = ItemsShared and ItemsShared:FindFirstChild("ItemQualities")
local ItemRegistryModule = ItemRegistry and require(ItemRegistry)
local ItemQualitiesModule = ItemQualities and require(ItemQualities)

-- Rarity mapping (match Equip semantics): comum < raro < epico < lendario < mitico
local RarityColors = {
	-- Requested mapping
	comum = Color3.fromRGB(90, 210, 120),   -- green
	raro = Color3.fromRGB(80, 170, 220),    -- blue
	epico = Color3.fromRGB(160, 100, 220),  -- purple
	lendario = Color3.fromRGB(255, 215, 80),-- gold
	-- Keep mythical as a distinct tone (can tweak later)
	mitico = Color3.fromRGB(255, 100, 100),
}

-- Quality colors (for the quality stat line in preview), matching Equip
local QualityLineColors = {
	rusty = Color3.fromRGB(130,130,130),
	worn = Color3.fromRGB(150,150,150),
	new = Color3.fromRGB(90,170,255),
	polished = Color3.fromRGB(70,200,90),
	perfect = Color3.fromRGB(255,190,40),
	artifact = Color3.fromRGB(255,90,220),
}

-- Helper: deep find by name
local function recursiveFind(obj, name)
	if not obj then return nil end
	local direct = obj:FindFirstChild(name)
	if direct then return direct end
	for _, d in ipairs(obj:GetDescendants()) do
		if d.Name == name then return d end
	end
	return nil
end

-- Panel refs (best-effort)
local panel1 = recursiveFind(root, "1st")
local panel2 = recursiveFind(root, "2nd")
local prevPanel = panel1 and panel1:FindFirstChild("Prev") or nil
-- Resolve preview icon image under: Prev/Frame/Icon_c/EQ_BG/Frame/Icon (with fallbacks)
local function getPrevIconImage()
	if not prevPanel then return nil end
	local panelFrame = prevPanel:FindFirstChild("Frame")
	local container
	if panelFrame then
		container = panelFrame:FindFirstChild("Icon_c") or recursiveFind(panelFrame, "Icon_c")
	end
	if not container then
		container = prevPanel:FindFirstChild("Icon_c") or recursiveFind(prevPanel, "Icon_c")
	end
	if not container then return nil end
	local eqbg = container:FindFirstChild("EQ_BG") or recursiveFind(container, "EQ_BG")
	if not eqbg then return nil end
	-- Prefer Icon inside Frame, fallback to any Icon under EQ_BG
	local innerFrame = eqbg:FindFirstChild("Frame") or recursiveFind(eqbg, "Frame")
	local icon
	if innerFrame then
		icon = innerFrame:FindFirstChild("Icon") or recursiveFind(innerFrame, "Icon")
	end
	icon = icon or eqbg:FindFirstChild("Icon") or recursiveFind(eqbg, "Icon")
	return icon
end

-- Get the StarGrad UIGradient under Prev/Icon_c/EQ_BG
local function getPrevStarGrad()
    if not prevPanel then return nil end
    local panelFrame = prevPanel:FindFirstChild("Frame")
    local container
    if panelFrame then
        container = panelFrame:FindFirstChild("Icon_c") or recursiveFind(panelFrame, "Icon_c")
    end
    if not container then
        container = prevPanel:FindFirstChild("Icon_c") or recursiveFind(prevPanel, "Icon_c")
    end
    if not container then return nil end
    local eqbg = container:FindFirstChild("EQ_BG") or recursiveFind(container, "EQ_BG")
    if not eqbg then return nil end
    local star = eqbg:FindFirstChild("StarGrad") or recursiveFind(eqbg, "StarGrad")
    return star
end

-- Resolve Prev stats area: Prev/Frame/ScrollingFrame and Stat_f under Prev/Frame
local function getPrevStatsArea()
	if not prevPanel then return nil, nil end
	local panelFrame = prevPanel:FindFirstChild("Frame")
	if not panelFrame then panelFrame = recursiveFind(prevPanel, "Frame") end
	if not panelFrame then return nil, nil end
	local scroll = panelFrame:FindFirstChild("ScrollingFrame") or recursiveFind(panelFrame, "ScrollingFrame")
	local statTemplate = panelFrame:FindFirstChild("Stat_f") or recursiveFind(panelFrame, "Stat_f")
	return scroll, statTemplate
end

-- Resolve Prev name label: Prev/Frame/Name
local function getPrevNameLabel()
	if not prevPanel then return nil end
	local panelFrame = prevPanel:FindFirstChild("Frame") or recursiveFind(prevPanel, "Frame")
	if not panelFrame then return nil end
	local nameLbl = panelFrame:FindFirstChild("Name") or recursiveFind(panelFrame, "Name")
	return nameLbl
end

local function clearPrevStats()
	local scroll, statTemplate = getPrevStatsArea()
	if not scroll then return end
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") and (not statTemplate or child ~= statTemplate) then
			child:Destroy()
		end
	end
end

local function addPrevStatLine(name, value)
	local scroll, statTemplate = getPrevStatsArea()
	if not scroll or not statTemplate or not statTemplate:IsA("Frame") then return end
	local clone = statTemplate:Clone()
	clone.Name = "Stat_" .. tostring(name)
	clone.Visible = true
	local label = clone:FindFirstChild("stat_text", true)
	if label and label:IsA("TextLabel") then
		if value == nil or value == "" then
			label.Text = tostring(name)
		else
			if typeof(value) == "number" then value = math.floor(value + 0.5) end
			label.Text = string.format("%s: %s", tostring(name), tostring(value))
		end
	end
	-- Apply gradient when this line represents the item's quality (same as Equip)
	local key = tostring(name):lower()
	local base = QualityLineColors[key]
	if base then
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
		-- If text ended as "name: ", reduce to just the name for quality-only line
		if label and label.Text then
			if label.Text:match("^"..tostring(name):gsub("%p","%%%0")..":%s*$") then
				label.Text = tostring(name)
			end
		end
	end
	clone.Parent = scroll
end

-- Capture authored goal position for panel1 (if present)
local panel1GoalPos = nil

-- Start hidden
pcall(function()
	if isScreenGui then root.Enabled = false end
	if panel1 and panel1:IsA("GuiObject") then
		panel1.Visible = false
		-- Preserve authored X/target, start off-screen at top
		panel1GoalPos = panel1.Position
		panel1.Position = UDim2.new(panel1GoalPos.X.Scale, panel1GoalPos.X.Offset, -1, 0)
	end
	if panel2 and panel2:IsA("GuiObject") then panel2.Visible = false end
	if prevPanel and prevPanel:IsA("GuiObject") then
		prevPanel.Visible = false
		-- Ensure Stat_f template is hidden
		local pf = prevPanel:FindFirstChild("Frame") or prevPanel
		local statTemplate = (pf and (pf:FindFirstChild("Stat_f") or (pf:FindFirstChild("ScrollingFrame") and pf.ScrollingFrame:FindFirstChild("Stat_f")))) or nil
		if not statTemplate then
			-- try recursive
			for _, d in ipairs(prevPanel:GetDescendants()) do
				if d.Name == "Stat_f" and d:IsA("Frame") then statTemplate = d break end
			end
		end
		if statTemplate and statTemplate:IsA("Frame") then statTemplate.Visible = false end
	end
end)

local isOpen = false
local receivedEvent = false

-- Inventory UI references (like Equip structure): 1st/Inv/Inv_frame/ScrollingFrame/inv_icon
local invContainer = panel1 and panel1:FindFirstChild("Inv")
local invFrame = invContainer and invContainer:FindFirstChild("Inv_frame")
local invScroll = invFrame and invFrame:FindFirstChild("ScrollingFrame")
local invTemplate = invScroll and invScroll:FindFirstChild("inv_icon")
if invTemplate and invTemplate:IsA("Frame") then invTemplate.Visible = false end

-- Layout and padding helpers to mirror Equip behavior
local layout = invScroll and (invScroll:FindFirstChildOfClass("UIGridLayout") or invScroll:FindFirstChildOfClass("UIListLayout"))
local EXTRA_BOTTOM_PADDING = 56
if invScroll then
	-- Ensure extra bottom padding so last row isn't glued to the bottom
	local pad = invScroll:FindFirstChild("ExtraBottomPadding")
	if not pad then
		pad = Instance.new("UIPadding")
		pad.Name = "ExtraBottomPadding"
		pad.Parent = invScroll
	end
	pad.PaddingBottom = UDim.new(0, EXTRA_BOTTOM_PADDING)
	-- Prefer automatic content sizing on Y like Equip
	pcall(function()
		invScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		invScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	end)
end

local function updateCanvasFromLayout()
	if not invScroll then return end
	local contentY = 0
	if layout and layout.AbsoluteContentSize then
		contentY = layout.AbsoluteContentSize.Y
	else
		for _, child in ipairs(invScroll:GetChildren()) do
			if child:IsA("Frame") and child ~= invTemplate and child.Visible then
				contentY += child.AbsoluteSize.Y
			end
		end
	end
	local needed = math.max(0, contentY + EXTRA_BOTTOM_PADDING)
	if invScroll.AutomaticCanvasSize == Enum.AutomaticSize.None then
		invScroll.CanvasSize = UDim2.new(0, 0, 0, needed)
	else
		local current = invScroll.CanvasSize
		if current.Y.Offset < needed then
			invScroll.CanvasSize = UDim2.new(current.X.Scale, current.X.Offset, 0, needed)
		end
	end
end

-- Forward declare selection so functions above can capture the same upvalue
local selectedItem = nil
-- Forward declare helpers used later inside showPanel2
local resolveStats
local resolveRarityKeyAndColor
local computeItemStatsAtLevel -- forward for preview to use level-aware stats

local function getPanel2IconAndName()
	if not panel2 then return nil, nil end
	-- Estrutura confirmada: 2nd -> yup -> EQ_BG -> (Frame, Icon)
	-- Name está em: EQ_BG/Frame/Name (TextLabel)
	-- Icon está em: EQ_BG/Icon (ImageLabel)
	local container = panel2:FindFirstChild("yup")
	local eqbg = container and (container:FindFirstChild("EQ_BG") or recursiveFind(container, "EQ_BG"))
	local frame = eqbg and (eqbg:FindFirstChild("Frame") or recursiveFind(eqbg, "Frame"))
	local nameLbl = frame and frame:FindFirstChild("Name")
	local icon = eqbg and eqbg:FindFirstChild("Icon")
	-- Fallbacks if any is missing
	if not nameLbl then nameLbl = (eqbg and (eqbg:FindFirstChild("Name") or recursiveFind(eqbg, "Name"))) or recursiveFind(root, "Name") end
	if not icon then icon = (eqbg and (eqbg:FindFirstChild("Icon") or recursiveFind(eqbg, "Icon"))) or recursiveFind(root, "Icon") end
	-- Debug: print what we found
	local function fullName(inst)
		local ok, res = pcall(function() return inst and inst:GetFullName() end)
		return ok and (res or "nil") or "nil"
	end
	print("[UpgradeUI] 2nd lookup -> yup:", fullName(container), "EQ_BG:", fullName(eqbg), "Frame:", fullName(frame), "Name:", fullName(nameLbl), "Icon:", fullName(icon))
	return icon, nameLbl
end

-- Find the Upgrade button under 2nd/yup/Upgrade
local function getPanel2UpgradeButton()
	if not panel2 then return nil end
	local container = panel2:FindFirstChild("yup")
	if not container then return nil end
	local upg = container:FindFirstChild("Upgrade") or recursiveFind(container, "Upgrade")
	if upg and upg:IsA("GuiButton") then return upg end
	-- could be a Frame containing a button
	if upg then
		local btn = upg:FindFirstChildWhichIsA("GuiButton", true)
		if btn then return btn end
	end
	return nil
end

-- Find UIGradient 'StarGrad' inside 2nd/yup/EQ_BG
local function getPanel2StarGrad()
	if not panel2 then return nil end
	local container = panel2:FindFirstChild("yup")
	local eqbg = container and (container:FindFirstChild("EQ_BG") or recursiveFind(container, "EQ_BG"))
	if not eqbg then return nil end
	local star = eqbg:FindFirstChild("StarGrad") or recursiveFind(eqbg, "StarGrad")
	return star
end

-- Helpers for 2nd stats rendering (ini_stats = current, final_stats = next level)
local function getPanel2LevelLabels()
	if not panel2 then return nil, nil end
	local container = panel2:FindFirstChild("yup")
	if not container then return nil, nil end
	local cLbl = container:FindFirstChild("C_lvl") or recursiveFind(container, "C_lvl")
	local nLbl = container:FindFirstChild("N_lvl") or recursiveFind(container, "N_lvl")
	return cLbl, nLbl
end

-- Helpers for 2nd stats rendering (ini_stats = current, final_stats = next level)
local function getPanel2StatsAreas()
	if not panel2 then return nil,nil,nil,nil end
	local container = panel2:FindFirstChild("yup")
	if not container then return nil,nil,nil,nil end
	local ini = container:FindFirstChild("ini_stats") or recursiveFind(container, "ini_stats")
	local fin = container:FindFirstChild("final_stats") or recursiveFind(container, "final_stats")
	local iniTemplate = ini and (ini:FindFirstChild("Stat_f") or recursiveFind(ini, "Stat_f")) or nil
	local finTemplate = fin and (fin:FindFirstChild("Stat_f") or recursiveFind(fin, "Stat_f")) or nil
	return ini, iniTemplate, fin, finTemplate
end

-- Find the Cost TextLabel inside: 2nd -> yup -> Upgrade -> Frame -> Top -> Cost
local function getPanel2CostLabel()
	if not panel2 then return nil end
	local container = panel2:FindFirstChild("yup")
	if not container then return nil end
	local upg = container:FindFirstChild("Upgrade") or recursiveFind(container, "Upgrade")
	if not upg then return nil end
	local top = upg:FindFirstChild("Top") or recursiveFind(upg, "Top")
	if not top then return nil end
	local cost = top:FindFirstChild("Cost") or recursiveFind(top, "Cost")
	if cost and cost:IsA("TextLabel") then return cost end
	return nil
end

local function clearStatsIn(scroll, keepTemplate)
	if not scroll then return end
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") and child ~= keepTemplate then
			child:Destroy()
		end
	end
end

local function addStatLineGeneric(scroll, template, name, value)
	if not (scroll and template and template:IsA("Frame")) then return end
	local clone = template:Clone()
	clone.Name = "Stat_"..tostring(name)
	clone.Visible = true
	local label = clone:FindFirstChild("stat_text", true)
	if label and label:IsA("TextLabel") then
		if typeof(value) == "number" then value = math.floor(value + 0.5) end
		label.Text = string.format("%s: %s", tostring(name), tostring(value))
	end
	clone.Parent = scroll
end

-- Level scaling used for items (simple placeholder: +2% por nível acima de 1)
local function itemLevelMultiplier(level)
	level = tonumber(level) or 1
	if level <= 1 then return 1 end
	return 1 + (level - 1) * 0.02
end

function computeItemStatsAtLevel(group, template, quality, level)
	local stats = resolveStats and resolveStats(group, template)
	if type(stats) ~= "table" then return {} end
	local out = {}
	local qMult = 0
	if ItemQualitiesModule and quality then
		local k = tostring(quality):lower()
		local m = ItemQualitiesModule[k]
		if typeof(m) == "number" then qMult = m end
	end
	-- Se o módulo tiver tabela Levels, usamos os valores explícitos do nível
	local levelsTbl = stats.Levels
	if type(levelsTbl) == "table" then
		-- Começa com números de topo (defaults) e sobrescreve com os do nível
		local merged = {}
		for k,v in pairs(stats) do
			if typeof(v) == "number" then merged[k] = v end
		end
		local lv = levelsTbl[level]
		if type(lv) == "table" then
			for k,v in pairs(lv) do
				if typeof(v) == "number" then merged[k] = v end
			end
		end
		for k,v in pairs(merged) do
			out[k] = v * (1 + qMult)
		end
		return out
	end
	-- Fallback: sem Levels -> aplica scaling genérico por nível
	local lvlMult = itemLevelMultiplier(level)
	for k,v in pairs(stats) do
		if typeof(v) == "number" then
			local val = v * (1 + qMult) * lvlMult
			out[k] = val
		end
	end
	return out
end

-- Minimal: show the '2nd' frame when requested
local function showPanel2()
	if not panel2 or not panel2:IsA("GuiObject") then
		warn("[UpgradeUI] Painel '2nd' não encontrado")
		return
	end
	if isScreenGui then root.Enabled = true end
	-- Hide 1st to switch context to 2nd
	pcall(function()
		if panel1 and panel1:IsA("GuiObject") then panel1.Visible = false end
	end)
	panel2.Visible = true

	-- Fill selected item info
	local icon2, nameLbl = getPanel2IconAndName()
	if selectedItem then
		-- Name
		local displayName
		if selectedItem.data and type(selectedItem.data)=="table" then
			displayName = selectedItem.data.DisplayName or selectedItem.data.Name
		end
		if not displayName then
			local stats = (resolveStats and resolveStats(selectedItem.group, selectedItem.template)) or nil
			if type(stats)=="table" then
				displayName = stats.DisplayName or stats.Name or stats.displayName or stats.name
			end
		end
		displayName = displayName or tostring(selectedItem.template or ""):gsub("_"," ")
		if nameLbl and (nameLbl:IsA("TextLabel") or nameLbl:IsA("TextButton")) then
			nameLbl.Text = displayName
			nameLbl.Visible = true
			pcall(function() nameLbl.TextTransparency = 0 end)
			print("[UpgradeUI] 2nd Name set:", displayName)
		end
		-- Icon
		local image = selectedItem.imageId
		if not image or image == "" or image == "rbxassetid://0" then
			local stats2 = (resolveStats and resolveStats(selectedItem.group, selectedItem.template)) or nil
			if type(stats2)=="table" then
				image = stats2.iscon or stats2.icon or stats2.Icon or image
			end
		end
		if icon2 and (icon2:IsA("ImageLabel") or icon2:IsA("ImageButton")) and image then
			icon2.Image = image
			icon2.ImageTransparency = 0
			icon2.Visible = true
			-- Garantir ZIndex acima do frame de fundo
			local targetZ = ((frame and frame.ZIndex) or 1) + 1
			if (icon2.ZIndex or 1) < targetZ then
				icon2.ZIndex = targetZ
			end
			print("[UpgradeUI] 2nd Icon set:", image)
		end
		-- Garantir que o nome fica por cima da imagem
		if nameLbl and icon2 then
			local iconZ = icon2.ZIndex or 1
			-- Empurra bem acima do ícone para evitar sobreposições futuras
			nameLbl.ZIndex = iconZ + 100000
		end

		-- Atualizar o gradiente StarGrad do 2nd conforme a raridade
		if selectedItem.group and selectedItem.template then
			local _, baseColor = resolveRarityKeyAndColor(selectedItem.group, selectedItem.template)
			if baseColor then
				local starGrad2 = getPanel2StarGrad()
				if starGrad2 and starGrad2:IsA("UIGradient") then
					local h,s,v = baseColor:ToHSV()
					local lighter = Color3.fromHSV(h, math.clamp(s*0.25,0,1), 1)
					local darker = Color3.fromHSV(h, s, math.clamp(v*0.25,0,1))
					starGrad2.Rotation = 90
					starGrad2.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, lighter),
						ColorSequenceKeypoint.new(0.5, baseColor),
						ColorSequenceKeypoint.new(1, darker),
					})
				end
			end
		end

		-- Renderizar stats atuais e do próximo nível nos dois ScrollingFrames do 2nd
		local iniScroll, iniTemplate, finScroll, finTemplate = getPanel2StatsAreas()
		if iniScroll and iniTemplate then iniTemplate.Visible = false end
		if finScroll and finTemplate then finTemplate.Visible = false end
		clearStatsIn(iniScroll, iniTemplate)
		clearStatsIn(finScroll, finTemplate)

		local curLevel = (selectedItem.data and tonumber(selectedItem.data.Level)) or 1
		local nextLevel = curLevel + 1
		-- Atualizar labels de nível C_lvl (atual) e N_lvl (próximo)
		local cLbl, nLbl = getPanel2LevelLabels()
		if cLbl and (cLbl:IsA("TextLabel") or cLbl:IsA("TextButton")) then
			cLbl.Text = string.format("Level %d", curLevel)
			cLbl.Visible = true
		end
		if nLbl and (nLbl:IsA("TextLabel") or nLbl:IsA("TextButton")) then
			nLbl.Text = string.format("Level %d", nextLevel)
			nLbl.Visible = true
		end
		local quality = selectedItem.data and selectedItem.data.Quality
		local curStats = computeItemStatsAtLevel(selectedItem.group, selectedItem.template, quality, curLevel)
		local nxtStats = computeItemStatsAtLevel(selectedItem.group, selectedItem.template, quality, nextLevel)
		local preferred = {"BaseDamage","Damage","AttackSpeed","CritChance","CritDamage","Defense","Health","Power"}
		local shown = {}
		for _, key in ipairs(preferred) do
			if curStats[key] ~= nil then
				addStatLineGeneric(iniScroll, iniTemplate, key, curStats[key])
				shown[key] = true
			end
			if nxtStats[key] ~= nil then
				addStatLineGeneric(finScroll, finTemplate, key, nxtStats[key])
			end
		end
		-- Extras alfabéticos
		for k,v in pairs(curStats) do
			if typeof(v) == "number" and not shown[k] then
				addStatLineGeneric(iniScroll, iniTemplate, k, v)
			end
		end
		for k,v in pairs(nxtStats) do
			if typeof(v) == "number" and not shown[k] then
				addStatLineGeneric(finScroll, finTemplate, k, v)
			end
		end

		-- Cost label: show only the upgrade cost for the current level -> next level
		local costLbl = getPanel2CostLabel()
		if costLbl then
			local ok, UpgradeCosts = pcall(function()
				return require(ReplicatedStorage.Shared.Items.UpgradeCosts)
			end)
			if ok and UpgradeCosts and selectedItem.group and selectedItem.template then
				local cost = UpgradeCosts:GetForItem(selectedItem.group, selectedItem.template, curLevel)
				if cost then
					costLbl.Text = tostring(cost)
					costLbl.Visible = true
				else
					-- Max level (no further upgrades)
					costLbl.Text = "Max"
					costLbl.Visible = true
				end
			else
				-- Fallback: unknown cost
				costLbl.Text = "-"
				costLbl.Visible = true
			end
		end
	end
end

-- Handle clicking the Upgrade button in panel2
do
	local function wirePanel2Upgrade()
		local btn = getPanel2UpgradeButton()
		if not btn or btn:GetAttribute("_Upgrade2Wired") then return end
		btn:SetAttribute("_Upgrade2Wired", true)
		local function onClick()
			if not selectedItem or not selectedItem.id then return end
			local curLevel = (selectedItem.data and tonumber(selectedItem.data.Level)) or 1
			-- require cost to show feedback fast; server is authoritative
			local costVal = "-"
			local okUC, UpgradeCosts = pcall(function()
				return require(ReplicatedStorage.Shared.Items.UpgradeCosts)
			end)
			if okUC and UpgradeCosts then
				local c = UpgradeCosts:GetForItem(selectedItem.group, selectedItem.template, curLevel)
				if c then costVal = tostring(c) end
			end

			local req = ReplicatedStorage.Remotes:FindFirstChild("RequestItemUpgrade")
			if not req or not req:IsA("RemoteFunction") then
				warn("[UpgradeUI] RequestItemUpgrade RemoteFunction not found")
				return
			end
			local res
			local ok, err = pcall(function()
				res = req:InvokeServer(selectedItem.id)
			end)
			if not ok then
				warn("[UpgradeUI] Upgrade invoke error:", err)
				return
			end
			if not res or res.success ~= true then
				-- TODO: show error to player (NotEnoughCoins, MaxLevel, etc.)
				warn("[UpgradeUI] Upgrade failed:", res and res.reason)
				return
			end
			-- Update local model and refresh UI
			if selectedItem.data then
				selectedItem.data.Level = res.level
			end
			-- Re-run the panel population to update levels, stats and cost
			showPanel2()
		end
		if btn.Activated then
			btn.Activated:Connect(onClick)
		elseif btn.MouseButton1Click then
			btn.MouseButton1Click:Connect(onClick)
		else
			btn.InputBegan:Connect(function(input)
				local t = input.UserInputType
				if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
					onClick()
				end
			end)
		end
	end
	-- Wire after UI is likely built
	task.defer(wirePanel2Upgrade)
end

if layout and layout:GetPropertyChangedSignal("AbsoluteContentSize") then
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvasFromLayout)
end

-- Remotes for profile access
local GetProfileRF = remotes:FindFirstChild("GetProfile")
local ProfileUpdatedRE = remotes:FindFirstChild("ProfileUpdated")

-- Current flat items list
local currentItems = {}
-- Keep track of the currently selected item from preview (already forward-declared above)

-- Helpers: rarity and stats resolution (minimal subset)
resolveStats = function(itemType, templateName)
	if not ItemRegistryModule then return nil end
	local ok, mod = pcall(function() return ItemRegistryModule:GetModule(itemType, templateName) end)
	if not ok or not mod then return nil end
	local ok2, stats = pcall(function() return require(mod) end)
	if not ok2 then return nil end
	return stats
end

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

resolveRarityKeyAndColor = function(itemType, templateName)
	-- try stats.rarity / stats.Rarity / stats.stars
	local stats = resolveStats(itemType, templateName)
	if type(stats) == "table" then
		if stats.rarity ~= nil then
			local key = mapRarityKey(stats.rarity)
			return key, RarityColors[key]
		end
		if stats.Rarity ~= nil then
			local key = mapRarityKey(stats.Rarity)
			return key, RarityColors[key]
		end
		if stats.stars ~= nil then
			local key = mapRarityKey(stats.stars)
			return key, RarityColors[key]
		end
	end
	-- fallback: infer from template name keywords
	local lower = string.lower(templateName or "")
	local key
	if lower:find("legend") or lower:find("lend") then key = "lendario" end
	if not key and (lower:find("epic") or lower:find("épico") or lower:find("epico")) then key = "epico" end
	if not key and (lower:find("rare") or lower:find("raro")) then key = "raro" end
	if not key and (lower:find("myth") or lower:find("mit")) then key = "mitico" end
	key = key or "comum"
	return key, RarityColors[key]
end

local function applyGradient(frameObj, baseColor)
	if not frameObj then return end
	local h,s,v = baseColor:ToHSV()
	local lighter = Color3.fromHSV(h, math.clamp(s*0.25,0,1), 1)
	local darker = Color3.fromHSV(h, s, math.clamp(v*0.25,0,1))
	local grad = frameObj:FindFirstChild("UIGradient") or Instance.new("UIGradient")
	grad.Name = grad.Name ~= "UIGradient" and "UIGradient" or grad.Name
	grad.Rotation = 90 -- vertical gradient for better shading
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, lighter),
		ColorSequenceKeypoint.new(0.5, baseColor),
		ColorSequenceKeypoint.new(1, darker),
	})
	grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0), NumberSequenceKeypoint.new(1,0) })
	grad.Parent = frameObj
	frameObj.BackgroundColor3 = baseColor
	frameObj.BackgroundTransparency = 0
end

local function clearIcons()
	if not invScroll then return end
	for _, child in ipairs(invScroll:GetChildren()) do
		if child:IsA("Frame") and child ~= invTemplate then child:Destroy() end
	end
end

-- Minimal: open Prev and set its icon image (now also captures instance id)
local function showPrevWithImage(imageId, itemGroup, templateName, itemData, instanceId)
	if not prevPanel then return end
	prevPanel.Visible = true
	-- Cache selection for later use in '2nd'
	selectedItem = {
		imageId = imageId,
		group = itemGroup,
		template = templateName,
		data = itemData,
		id = instanceId,
	}
	-- Also expose selection as attributes for later server calls
	pcall(function()
		root:SetAttribute("UpgradeSelectedId", instanceId)
		root:SetAttribute("UpgradeSelectedGroup", itemGroup)
		root:SetAttribute("UpgradeSelectedTemplate", templateName)
	end)
	local imgLbl = getPrevIconImage()
	if imgLbl and (imgLbl:IsA("ImageLabel") or imgLbl:IsA("ImageButton")) then
		imgLbl.Image = imageId or "rbxassetid://0"
	end
	-- Update StarGrad color according to rarity
	if itemGroup and templateName then
		local _, baseColor = resolveRarityKeyAndColor(itemGroup, templateName)
		if baseColor then
			local starGrad = getPrevStarGrad()
			if starGrad and starGrad:IsA("UIGradient") then
				local h,s,v = baseColor:ToHSV()
				-- Match inventory gradient shaping (same factors and rotation)
				local lighter = Color3.fromHSV(h, math.clamp(s*0.25,0,1), 1)
				local darker = Color3.fromHSV(h, s, math.clamp(v*0.25,0,1))
				starGrad.Rotation = 90
				starGrad.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, lighter),
					ColorSequenceKeypoint.new(0.5, baseColor),
					ColorSequenceKeypoint.new(1, darker),
				})
			end
		end
	end

	-- Set equipment name in Prev (Frame/Name)
	local displayName = itemData and (itemData.DisplayName or itemData.Name)
	if not displayName and itemGroup and templateName then
		local stats = resolveStats and resolveStats(itemGroup, templateName)
		if type(stats) == "table" then
			displayName = stats.DisplayName or stats.Name or stats.displayName or stats.name
		end
	end
	displayName = displayName or tostring(templateName or ""):gsub("_"," ")
	local prevNameLbl = getPrevNameLabel()
	if prevNameLbl and (prevNameLbl:IsA("TextLabel") or prevNameLbl:IsA("TextButton")) then
		prevNameLbl.Text = displayName
		prevNameLbl.Visible = true
		pcall(function() prevNameLbl.TextTransparency = 0 end)
		-- keep above inner frame just in case
		local z = (prevNameLbl.ZIndex or 1)
		if z < 50 then prevNameLbl.ZIndex = 50 end
	end
	-- Build stat lines using current-level stats (not just base):
	clearPrevStats()
	local q = itemData and itemData.Quality
	if q and type(q) == "string" and q ~= "" then
		addPrevStatLine(q, "")
	end
	if itemGroup and templateName then
		local level = (itemData and tonumber(itemData.Level)) or 1
		local curStats = computeItemStatsAtLevel and computeItemStatsAtLevel(itemGroup, templateName, q, level) or nil
		if type(curStats) == "table" then
			local preferred = {"BaseDamage","Damage","AttackSpeed","CritChance","CritDamage","Defense","Health","Power"}
			local shown = {}
			for _, key in ipairs(preferred) do
				if curStats[key] ~= nil then
					addPrevStatLine(key, curStats[key])
					shown[key] = true
				end
			end
			local extra = {}
			for k,v in pairs(curStats) do
				if typeof(v) == "number" and not shown[k] then table.insert(extra, k) end
			end
			table.sort(extra)
			for _, k in ipairs(extra) do
				addPrevStatLine(k, curStats[k])
			end
		end
	end
end

local function createIcon(group, instId, data)
	if not invScroll or not invTemplate then return end
	local clone = invTemplate:Clone()
	clone.Name = string.format("%s_%s", tostring(group), tostring(instId))
	clone.Visible = true
	clone.Parent = invScroll
	-- Rarity look
	local templateName = (data and data.Template) or instId
	local _, baseColor = resolveRarityKeyAndColor(group, templateName)
	if not baseColor and ItemQualitiesModule and data and data.Quality and ItemQualitiesModule.Colors then
		local qKey = tostring(data.Quality):lower()
		baseColor = ItemQualitiesModule.Colors[qKey]
	end
	applyGradient(clone, baseColor or Color3.fromRGB(255,255,255))
	-- Icon image
	local icon = clone:FindFirstChild("Icon")
	if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
		local stats = resolveStats(group, templateName)
		local img = stats and (stats.iscon or stats.icon or stats.Icon) or "rbxassetid://0"
		icon.Image = (img and img ~= "") and img or "rbxassetid://0"
		-- Click handlers to open preview with the same icon
		if icon:IsA("ImageButton") and icon.MouseButton1Click then
			icon.MouseButton1Click:Connect(function()
				showPrevWithImage(icon.Image, group, templateName, data, instId)
			end)
		elseif icon.InputBegan then
			icon.InputBegan:Connect(function(input)
				local t = input.UserInputType
				if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
					showPrevWithImage(icon.Image, group, templateName, data, instId)
				end
			end)
		end
	end
	-- Also allow clicking the whole slot frame
	if clone.InputBegan then
		clone.InputBegan:Connect(function(input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				local ic = icon or clone:FindFirstChild("Icon")
				local img = (ic and ic:IsA("ImageLabel")) and ic.Image or (ic and ic:IsA("ImageButton") and ic.Image) or "rbxassetid://0"
				showPrevWithImage(img, group, templateName, data, instId)
			end
		end)
	end
	-- Level label (if present)
	local levelLabel = clone:FindFirstChild("Level")
	if levelLabel and levelLabel:IsA("TextLabel") then
		local lvl = (data and tonumber(data.Level)) or 1
		levelLabel.Text = string.format("Level %d", lvl)
	end
	-- Remove any previous badge (defensive when re-rendering)
	local oldBadge = clone:FindFirstChild("EquipBadge")
	if oldBadge then oldBadge:Destroy() end
	-- Optional: equipped badge like Equip (if server sets Equipped flag in data)
	if data and data.Equipped then
		local badge = Instance.new("Frame")
		badge.Name = "EquipBadge"
		badge.AnchorPoint = Vector2.new(1,0)
		badge.Size = UDim2.fromScale(0.34, 0.34)
		badge.Position = UDim2.new(1, -4, 0, 4)
		badge.BackgroundTransparency = 1 -- no background as requested
		local topZ = math.max(clone.ZIndex or 1, (icon and icon.ZIndex) or 1, (levelLabel and levelLabel.ZIndex) or 1)
		badge.ZIndex = topZ + 50
		badge.Parent = clone
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
		-- add black stroke around the letter for contrast
		main.TextStrokeColor3 = Color3.new(0,0,0)
		main.TextStrokeTransparency = 0
		main.ZIndex = (badge.ZIndex or 1) + 1
		main.Parent = badge
	end
end

local function buildListFromProfile(profile)
	currentItems = {}
	if not profile or not profile.Items then return end
	local categories = profile.Items.Categories
	if categories and type(categories) == "table" then
		for catName, catData in pairs(categories) do
			local list = catData.List
			local equippedId = (catData and (catData.Equipped or catData.equipped))
			if type(list) == "table" then
				for _, entry in ipairs(list) do
					local isEquipped = false
					if equippedId ~= nil then
						isEquipped = tostring(entry.Id) == tostring(equippedId)
					elseif entry.Equipped ~= nil then
						isEquipped = entry.Equipped and true or false
					end
					currentItems[#currentItems+1] = {
						group = catName,
						id = entry.Id,
						data = {
							Level = entry.Level,
							Template = entry.Template,
							Quality = entry.Quality,
							Equipped = isEquipped,
						}
					}
				end
			end
		end
	elseif profile.Items.Owned then
		for groupName, groupTable in pairs(profile.Items.Owned) do
			if type(groupTable) == "table" then
				local groupEquipped = groupTable.Equipped or groupTable.equipped
				if groupTable.Instances then
					for instId, instData in pairs(groupTable.Instances) do
						if type(instData) == "table" then
							if instData.Equipped == nil then
								instData.Equipped = (groupEquipped ~= nil and tostring(instId) == tostring(groupEquipped)) and true or false
							end
						end
						currentItems[#currentItems+1] = { group = groupName, id = instId, data = instData }
					end
				else
					for itemId, data in pairs(groupTable) do
						if type(data)=="table" then
							if data.Equipped == nil then
								data.Equipped = (groupEquipped ~= nil and tostring(itemId) == tostring(groupEquipped)) and true or false
							end
							currentItems[#currentItems+1] = { group = groupName, id = itemId, data = data }
						end
					end
				end
			end
		end
	end
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
	updateCanvasFromLayout()
end

local function fetchProfile()
	if not GetProfileRF then return end
	local ok, res = pcall(function()
		return GetProfileRF:InvokeServer()
	end)
	if ok and res and res.profile then
		buildListFromProfile(res.profile)
		render()
	end
end

local function showPanel1()
	-- Do not reopen if already visible or if 2nd is currently open
	if panel1 and panel1:IsA("GuiObject") and panel1.Visible then return end
	if panel2 and panel2:IsA("GuiObject") and panel2.Visible then return end
	if not panel1 or not panel1:IsA("GuiObject") then
		warn("[UpgradeUI] Painel '1st' não encontrado")
		return
	end
	if isScreenGui then root.Enabled = true end
	if panel2 and panel2:IsA("GuiObject") then panel2.Visible = false end
	-- Always animate the '1st' frame itself
	local goalPos = panel1GoalPos or panel1.Position
	panel1.Visible = true
	pcall(function()
		panel1.Position = UDim2.new(goalPos.X.Scale, goalPos.X.Offset, -1, 0)
	end)
	local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(panel1, tweenInfo, { Position = goalPos }):Play()
	isOpen = true
	-- Populate inventory when opening if empty
	if #currentItems == 0 then
		fetchProfile()
	else
		render()
	end
end

local function closeUI()
	if not isOpen then return end
	-- Slide out upwards on the '1st' frame itself
	if panel1 and panel1:IsA("GuiObject") then
		local xS, xO = 0, 0
		pcall(function()
			xS = panel1.Position.X.Scale
			xO = panel1.Position.X.Offset
		end)
		local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local tw = TweenService:Create(panel1, tweenInfo, { Position = UDim2.new(xS, xO, -1, 0) })
		tw:Play()
		tw.Completed:Connect(function()
			pcall(function()
				panel1.Visible = false
				if isScreenGui then root.Enabled = false end
			end)
			isOpen = false
		end)
	else
		-- Fallback: just hide
		pcall(function()
			if isScreenGui then root.Enabled = false end
		end)
		isOpen = false
	end
end

-- Wire exit button if present (inside '1st'), case-insensitive, supports ImageLabel via InputBegan
do
	local function findExit()
		if panel1 then
			local direct = panel1:FindFirstChild("Exit") or panel1:FindFirstChild("exit")
			if direct then return direct end
			for _, d in ipairs(panel1:GetDescendants()) do
				if tostring(d.Name):lower() == "exit" then return d end
			end
		end
		-- Fallback: search in root to be safe
		local rdirect = root:FindFirstChild("Exit") or root:FindFirstChild("exit")
		if rdirect then return rdirect end
		for _, d in ipairs(root:GetDescendants()) do
			if tostring(d.Name):lower() == "exit" then return d end
		end
		return nil
	end
	local exitBtn = findExit()
	if exitBtn and exitBtn:IsA("GuiObject") and not exitBtn:GetAttribute("_UpgradeExitWired") then
		exitBtn:SetAttribute("_UpgradeExitWired", true)
		if exitBtn:IsA("ImageButton") or exitBtn:IsA("TextButton") then
			exitBtn.MouseButton1Click:Connect(closeUI)
		elseif exitBtn.InputBegan then
			exitBtn.InputBegan:Connect(function(input)
				local t = input.UserInputType
				if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
					closeUI()
				end
			end)
		end
	elseif not exitBtn then
		warn("[UpgradeUI] Botão 'Exit' não encontrado dentro de '1st'.")
	end
end

-- Wire the Upgrade button inside preview to open '2nd'
do
	local function findPrevUpgradeButton()
		if not prevPanel then return nil end
		local pf = prevPanel:FindFirstChild("Frame") or prevPanel
		if not pf then return nil end
		return pf:FindFirstChild("Upgrade") or recursiveFind(pf, "Upgrade")
	end
	local upgBtn = findPrevUpgradeButton()
	if upgBtn and upgBtn:IsA("GuiObject") and not upgBtn:GetAttribute("_PrevUpgradeWired") then
		upgBtn:SetAttribute("_PrevUpgradeWired", true)
		if upgBtn.Activated then
			upgBtn.Activated:Connect(showPanel2)
		elseif upgBtn.MouseButton1Click then
			upgBtn.MouseButton1Click:Connect(showPanel2)
		elseif upgBtn.InputBegan then
			upgBtn.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					showPanel2()
				end
			end)
		end
	end
end

-- Wire Exit button inside '2nd' to go back to '1st'
do
	local function backToPanel1()
		if panel2 and panel2:IsA("GuiObject") then panel2.Visible = false end
		showPanel1()
	end
	local function findPanel2Exit()
		if not panel2 then return nil end
		local btn = panel2:FindFirstChild("Exit") or recursiveFind(panel2, "Exit")
		return btn
	end
	local exit2 = findPanel2Exit()
	if exit2 and exit2:IsA("GuiObject") and not exit2:GetAttribute("_Panel2ExitWired") then
		exit2:SetAttribute("_Panel2ExitWired", true)
		if exit2.Activated then
			exit2.Activated:Connect(backToPanel1)
		elseif exit2.MouseButton1Click then
			exit2.MouseButton1Click:Connect(backToPanel1)
		elseif exit2.InputBegan then
			exit2.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					backToPanel1()
				end
			end)
		end
	end
end

-- Readiness handshake
local function keepAlive()
	while not receivedEvent do
		UpgradeClientReadyRE:FireServer()
		task.wait(0.5)
	end
end
task.spawn(keepAlive)

-- RemoteEvent open path
openRemote.OnClientEvent:Connect(function(payload)
	receivedEvent = true
	if payload == "Upgrade:1st" or payload == "Upgrade" then
		showPanel1()
	else
		warn("[UpgradeUI] Payload inesperado:", tostring(payload))
	end
end)

-- RemoteFunction open path
openUpgradeFunction.OnClientInvoke = function(payload)
	if payload == "Upgrade:1st" or payload == "Upgrade" then
		showPanel1()
		return true
	end
	return false
end

-- Initial ready signal
UpgradeClientReadyRE:FireServer()
print("[UpgradeUI] Ready sinalizado ao servidor.")

-- Listen to profile updates to keep list in sync
if ProfileUpdatedRE and ProfileUpdatedRE:IsA("RemoteEvent") then
	ProfileUpdatedRE.OnClientEvent:Connect(function(payload)
		if not payload then return end
		if payload.full and payload.full.Items then
			buildListFromProfile(payload.full)
			if isOpen then render() end
			return
		end
		if payload.items or (payload.Items and payload.Items.Owned) then
			fetchProfile()
		end
	end)
end
