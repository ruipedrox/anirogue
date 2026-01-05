-- General UI Controller
-- Controla botões laterais (Left_gui) para abrir painéis específicos.

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local TweenService = game:GetService("TweenService")

local generalRoot = script.Parent
local leftGui = generalRoot:WaitForChild("Left_gui")
local btnChars = leftGui:WaitForChild("Chars")
local btnEquip = leftGui:FindFirstChild("Equip") or leftGui:WaitForChild("Equip")

-- Referências a contadores de moedas/gemas (estrutura mostrada na imagem)
local botGui = generalRoot:FindFirstChild("Bot_gui") or generalRoot:WaitForChild("Bot_gui")
local curFrame = botGui:FindFirstChild("Cur") or botGui:WaitForChild("Cur")
local gemsFrame = curFrame:FindFirstChild("Gems") or curFrame:WaitForChild("Gems")
local goldFrame = curFrame:FindFirstChild("Gold") or curFrame:WaitForChild("Gold")
local gemsLabel = gemsFrame:FindFirstChildWhichIsA("TextLabel")
local goldLabel = goldFrame:FindFirstChildWhichIsA("TextLabel")

-- Slots de personagens equipados (E_Char/Slot1..Slot5)
local eCharFolder = botGui:FindFirstChild("E_Char") or botGui:WaitForChild("E_Char")
local slotRefs = {}
for i = 1,5 do
    slotRefs[i] = eCharFolder:FindFirstChild("Slot"..i)
end

-- Simplified: only update existing Slot/Icon ImageLabels. No creation, no level text.
-- Cache da última tabela de instâncias recebida para quando vier só EquippedOrder
local _lastInstancesSnapshot = nil
local CharacterCatalog = nil -- lazy require para evitar custo se não precisar

-- Paleta de cores por número de estrelas (mesma lógica do inventário)
local StarColors = {
	[1] = Color3.fromRGB(130,130,130), -- Comum / cinza
	[2] = Color3.fromRGB(90,170,90),
	[3] = Color3.fromRGB(70,130,255), -- Azul
	[4] = Color3.fromRGB(180,85,255), -- Roxo
	[5] = Color3.fromRGB(255,190,40), -- Dourado
	[6] = Color3.fromRGB(255,50,50),  -- Vermelho (6+)
}

local function colorForStars(stars)
	return StarColors[stars] or Color3.fromRGB(255,255,255)
end

-- Garante (ou atualiza) um gradiente de raridade no slot
local function ensureStarGradient(targetFrame, baseColor)
	-- Coloca / atualiza gradiente; se houver sub-frame L_Frame usamos ele para não sujar layout externo
	if not targetFrame or not baseColor then return end
	local applyFrame = targetFrame
	local grad = applyFrame:FindFirstChild("StarGradient")
	local h,s,v = baseColor:ToHSV()
	local lighter = Color3.fromHSV(h, math.clamp(s * 0.38, 0, 1), 1)
	local darker = Color3.fromHSV(h, s, math.max(v * 0.22, 0.05))
	if not grad then
		grad = Instance.new("UIGradient")
		grad.Name = "StarGradient"
		grad.Rotation = 90
		grad.Parent = applyFrame
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
	if applyFrame:IsA("Frame") then
		applyFrame.BackgroundColor3 = baseColor
		applyFrame.BackgroundTransparency = 0
	end
	return grad
end

local function findIconLabel(slot)
	-- Agora aceita tanto ImageLabel quanto ImageButton.
	if not slot then return nil end
	local function isIconCandidate(obj)
		return obj and (obj:IsA("ImageLabel") or obj:IsA("ImageButton"))
	end
	local direct = slot:FindFirstChild("Icon")
	if isIconCandidate(direct) then return direct end
	local lframe = slot:FindFirstChild("L_Frame")
	if lframe then
		local nested = lframe:FindFirstChild("Icon")
		if isIconCandidate(nested) then return nested end
	end
	-- fallback: primeira ImageLabel / ImageButton descendente chamada Icon
	for _, ch in ipairs(slot:GetDescendants()) do
		if (ch:IsA("ImageLabel") or ch:IsA("ImageButton")) and ch.Name == "Icon" then
			return ch
		end
	end
	return nil
end

local function applyEquippedSlots(characters)
	if not characters then return end
	local equippedOrder = characters.EquippedOrder or characters.equippedOrder
	local instances = characters.Instances or characters.instances
	if instances then
		_lastInstancesSnapshot = instances
	else
		instances = _lastInstancesSnapshot -- tentar usar cache anterior
	end
	if not (equippedOrder and instances) then return end

	-- Construir lookup: pode ser array (list) ou map; queremos idxPorId[id] = instData
	local byId = nil
	if type(instances) == "table" then
		local isArray = (#instances > 0) -- heurística simples
		if isArray then
			byId = {}
			for _, inst in ipairs(instances) do
				if inst and (inst.Id or inst.id) then
					byId[inst.Id or inst.id] = inst
				end
			end
		else
			byId = instances
		end
	end

	-- Lazy require CharacterCatalog só se precisarmos fallback (quando inst sem Catalog.icon_id)
	local function getIconForInstance(inst)
		if not inst then return "rbxassetid://0" end
		local cat = inst.Catalog or inst.catalog
		if not cat then
			-- tentar via template
			local templateName = inst.TemplateName or inst.Template
			if templateName then
				if not CharacterCatalog then
					local RS = game:GetService("ReplicatedStorage")
					local Scripts = RS:FindFirstChild("Scripts")
					if Scripts then
						local ok, mod = pcall(require, Scripts:FindFirstChild("CharacterCatalog"))
						if ok then CharacterCatalog = mod end
					end
				end
				if CharacterCatalog and CharacterCatalog.Get then
					cat = CharacterCatalog:Get(templateName)
				end
			end
		end
		if cat and cat.icon_id and cat.icon_id ~= "rbxassetid://0" then
			return cat.icon_id
		end
		return "rbxassetid://0"
	end
	for i = 1,5 do
		local slot = slotRefs[i]
		if slot then
			local iconLabel = findIconLabel(slot)
			local lvlLabel = nil
			local lframe = slot:FindFirstChild("L_Frame")
			if lframe then
				-- Garantir ZIndex acima do ícone
				lframe.ZIndex = 5
				lvlLabel = lframe:FindFirstChild("U_l") or lframe:FindFirstChild("Lvl")
				if lvlLabel then lvlLabel.ZIndex = 6 end
			end
			if iconLabel then
				-- Ícone abaixo
				iconLabel.ZIndex = math.min((iconLabel.ZIndex or 1), 4)
				local instId = equippedOrder[i]
				if instId and instId ~= "_EMPTY_" and instId ~= "" then
					local instData = byId and byId[instId]
					iconLabel.Image = getIconForInstance(instData)
					-- Gradiente por estrelas (carrega Catalog se necessário para stars)
					local cat = instData and (instData.Catalog or instData.catalog)
					if (not cat or not cat.stars) and instData then
						local templateName = instData.TemplateName or instData.Template
						if templateName then
							if not CharacterCatalog then
								local RS = game:GetService("ReplicatedStorage")
								local Scripts = RS:FindFirstChild("Scripts")
								if Scripts then
									local okMod, mod = pcall(require, Scripts:FindFirstChild("CharacterCatalog"))
									if okMod then CharacterCatalog = mod end
								end
							end
							if CharacterCatalog and CharacterCatalog.Get then
								local fetched = CharacterCatalog:Get(templateName)
								if fetched then cat = fetched end
							end
						end
					end
					local stars = (cat and cat.stars) or 0
					ensureStarGradient(slot, colorForStars(stars))
					if lvlLabel and instData and (instData.Level or instData.level) then
						lvlLabel.Text = string.format("Lv %d", instData.Level or instData.level)
					elseif lvlLabel then
						lvlLabel.Text = "Lv ?"
					end
				else
					iconLabel.Image = "rbxassetid://0"
					-- Remover gradiente se slot vazio
					local oldGrad = slot:FindFirstChild("StarGradient")
					if oldGrad then oldGrad:Destroy() end
					-- Estilo desejado para slot vazio: cor 40,40,40 com transparência 0.3
					slot.BackgroundColor3 = Color3.fromRGB(40,40,40)
					slot.BackgroundTransparency = 0.3
					if lvlLabel then lvlLabel.Text = "" end
				end
			end
		end
	end
end

-- XP / Level UI
local xpBg = botGui:FindFirstChild("Xp_Bg") or botGui:WaitForChild("Xp_Bg")
local barUnder = xpBg:FindFirstChild("Under") or xpBg:WaitForChild("Under")
local barFill = xpBg:FindFirstChild("XP_bar") or xpBg:WaitForChild("XP_bar")
local lvlLabel = xpBg:FindFirstChild("Lvl") or xpBg:WaitForChild("Lvl")
local lastLevel = nil
local lastFraction = 0
local activeTweenFill, activeTweenUnder
local lastEquipSlots = nil -- para controlar locks

-- AccountLeveling para saber quantos slots são permitidos (para mostrar locks nos extras)
local AccountLeveling = nil
do
	local RS = game:GetService("ReplicatedStorage")
	local Scripts = RS:FindFirstChild("Scripts")
	if Scripts then
		local ok, mod = pcall(require, Scripts:FindFirstChild("AccountLeveling"))
		if ok then
			AccountLeveling = mod
		end
	end
end

local function updateSlotLocks(equipSlotsAllowed)
	-- Slots base 1-2 nunca têm lock. Locks aplicados aos slots 3,4,5 conforme ainda não desbloqueados.
	lastEquipSlots = equipSlotsAllowed
	for idx = 3,5 do
		local slot = slotRefs[idx]
		if slot then
			local lockLabel = slot:FindFirstChild("lock") or slot:FindFirstChild("Lock") or slot:FindFirstChild("LOCK")
			local lockImage = slot:FindFirstChild("Lock_i") or slot:FindFirstChild("lock_i")
			if lockLabel and lockLabel:IsA("TextLabel") then
				-- Se número de slots permitidos >= idx, este slot está desbloqueado => esconder lock
				local unlocked = equipSlotsAllowed and equipSlotsAllowed >= idx
				lockLabel.Visible = not unlocked
				-- Se bloqueado, garantir estilo sobre o gradiente / fundo e acima da imagem
				if not unlocked then
					lockLabel.ZIndex = 12
				end
			end
			if lockImage and lockImage:IsA("ImageLabel") then
				local unlocked = equipSlotsAllowed and equipSlotsAllowed >= idx
				lockImage.Visible = not unlocked
				if not unlocked then
					lockImage.ZIndex = 11 -- imagem fica abaixo do texto (texto=12)
				end
			end
		end
	end
end

-- Remotes para obter profile e updates
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
local GetProfileRF, ProfileUpdatedRE
if Remotes then
	GetProfileRF = Remotes:FindFirstChild("GetProfile")
	ProfileUpdatedRE = Remotes:FindFirstChild("ProfileUpdated")
    DebugAddXP = Remotes:FindFirstChild("DebugAddXP")
end

-- Formata número com vírgulas a cada 3 dígitos (2500 -> 2,500)
local function formatNumber(n)
	n = tonumber(n) or 0
	local sign = ""
	if n < 0 then
		sign = "-"
		n = -n
	end
	local s = tostring(math.floor(n + 0.00001))
	local len = #s
	if len <= 3 then return sign .. s end
	local firstLen = len % 3
	if firstLen == 0 then firstLen = 3 end
	local parts = { s:sub(1, firstLen) }
	local i = firstLen + 1
	while i <= len do
		parts[#parts+1] = s:sub(i, i+2)
		i = i + 3
	end
	return sign .. table.concat(parts, ",")
end

local function applyCurrencySnapshot(acc)
	if not acc then return end
	if goldLabel then goldLabel.Text = formatNumber(acc.Coins or 0) end
	if gemsLabel then gemsLabel.Text = formatNumber(acc.Gems or 0) end
end

local function setBarInstant(fraction)
	fraction = math.clamp(fraction or 0, 0, 1)
	if barFill then
		barFill.Size = UDim2.new(fraction, 0, barFill.Size.Y.Scale, barFill.Size.Y.Offset)
	end
	if barUnder then
		barUnder.Size = UDim2.new(fraction, 0, barUnder.Size.Y.Scale, barUnder.Size.Y.Offset)
	end
end

local function animateXP(level, fraction, xp, required)
	if not (barFill and barUnder and lvlLabel) then return end
	fraction = math.clamp(fraction or 0, 0, 1)
	-- Atualiza texto de nível + XP atual
		if lvlLabel then
			lvlLabel.Text = string.format("Lv %d (%d/%d)", level or 1, xp or 0, required or 0)
	end

	-- Atualizar locks conforme slots permitidos (se tivermos AccountLeveling ou se já vier no acc snapshot)
	if AccountLeveling and level then
		local allowed = AccountLeveling:GetAllowedEquipSlots(level)
		updateSlotLocks(allowed)
	end
	-- Cancelar tweens antigos
	if activeTweenFill then activeTweenFill:Cancel() end
	if activeTweenUnder then activeTweenUnder:Cancel() end

	local sameLevel = (lastLevel == level)
	local fromFraction = sameLevel and lastFraction or 0

	-- Se mudou de nível e existia progresso anterior, opcionalmente fazer flash cheio antes de reset
	if (not sameLevel) and lastLevel ~= nil then
		-- Preenche até 1 rapidamente, depois anima do 0 ao novo fraction
		setBarInstant(0)
		fromFraction = 0
	end

	if math.abs(fraction - fromFraction) < 0.0001 then
		setBarInstant(fraction)
		lastFraction = fraction
		lastLevel = level
		return
	end

	local tweenInfo = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	barFill.Size = UDim2.new(fromFraction, 0, barFill.Size.Y.Scale, barFill.Size.Y.Offset)
	barUnder.Size = UDim2.new(fromFraction, 0, barUnder.Size.Y.Scale, barUnder.Size.Y.Offset)
	activeTweenFill = TweenService:Create(barFill, tweenInfo, { Size = UDim2.new(fraction, 0, barFill.Size.Y.Scale, barFill.Size.Y.Offset) })
	activeTweenUnder = TweenService:Create(barUnder, tweenInfo, { Size = UDim2.new(fraction, 0, barUnder.Size.Y.Scale, barUnder.Size.Y.Offset) })
	activeTweenFill:Play()
	activeTweenUnder:Play()
	activeTweenFill.Completed:Connect(function()
		if lastFraction ~= fraction then
			lastFraction = fraction
			lastLevel = level
		end
	end)
end
-- Snapshot inicial
task.spawn(function()
	if GetProfileRF then
		local ok, result = pcall(function() return GetProfileRF:InvokeServer() end)
		if ok and result and result.profile and result.profile.Account then
			local acc = result.profile.Account
			applyCurrencySnapshot(acc)
			animateXP(acc.Level, acc.Fraction, acc.XP, acc.Required)
			-- Locks: tentar usar campo EquipSlots se existir; se não, recalcular
			local equipSlots = acc.EquipSlots
			if not equipSlots and AccountLeveling and acc.Level then
				equipSlots = AccountLeveling:GetAllowedEquipSlots(acc.Level)
			end
			if equipSlots then updateSlotLocks(equipSlots) end
            if result.profile.characters then
                applyEquippedSlots(result.profile.characters)
            elseif result.profile.Characters then
                applyEquippedSlots(result.profile.Characters)
            end
		end
	end
end)

-- Listener de updates
if ProfileUpdatedRE then
	ProfileUpdatedRE.OnClientEvent:Connect(function(payload)
		if payload.full and payload.full.Account then
			local acc = payload.full.Account
			applyCurrencySnapshot(acc)
			animateXP(acc.Level, acc.Fraction, acc.XP, acc.Required)
			local equipSlots = acc.EquipSlots
			if not equipSlots and AccountLeveling and acc.Level then
				equipSlots = AccountLeveling:GetAllowedEquipSlots(acc.Level)
			end
			if equipSlots then updateSlotLocks(equipSlots) end
            if payload.full.characters then
                applyEquippedSlots(payload.full.characters)
            elseif payload.full.Characters then
                applyEquippedSlots(payload.full.Characters)
            end
		elseif payload.account then
			local acc = payload.account
			applyCurrencySnapshot(acc)
			animateXP(acc.Level, acc.Fraction, acc.XP, acc.Required)
			local equipSlots = acc.EquipSlots
			if not equipSlots and AccountLeveling and acc.Level then
				equipSlots = AccountLeveling:GetAllowedEquipSlots(acc.Level)
			end
			if equipSlots then updateSlotLocks(equipSlots) end
        end
        -- Atualizações parciais só de characters (lista completa nova)
        if payload.characters and payload.characters.EquippedOrder then
            applyEquippedSlots(payload.characters)
        elseif payload.Characters and payload.Characters.EquippedOrder then
            applyEquippedSlots(payload.Characters)
        end
		-- Ignoramos diffs parciais individuais para slots (apenas snapshots completos)
	end)
end

-- Referência ao GUI de personagens (StarterGui/Chars)
local function getCharsGui()
	-- Agora a ScreenGui/folder chama-se 'Chars' (parent deste script controla botões).
	return playerGui:FindFirstChild("Chars") or playerGui:FindFirstChild("Chars", true)
end

-- Toggle inventário de personagens usando atributos Show/Hide definidos no LocalScript desse GUI.
local function toggleChars()
	local charsGui = getCharsGui()
	if not charsGui then
		warn("[GeneralUI] Chars GUI não encontrado")
		return
	end
	-- O script real chama-se agora 'Chars_Inv.client.lua'
	local localScript = charsGui:FindFirstChild("Chars_Inv.client") or charsGui:FindFirstChild("Chars_Inv.client.lua") or charsGui:FindFirstChild("Chars_Inv.client", true) or charsGui:FindFirstChild("Chars_Inv.client.lua", true)
	if not localScript then
		-- fallback: tentar qualquer Script cujo nome contenha 'Chars_Inv'
		for _, child in ipairs(charsGui:GetChildren()) do
			if child:IsA("LocalScript") and child.Name:find("Chars_Inv") then
				localScript = child
				break
			end
		end
	end
	if not localScript then
		warn("[GeneralUI] LocalScript de Chars não encontrado (esperado algo com 'Chars_Inv')")
		return
	end
	local frame = charsGui:FindFirstChild("Frame")
	local isVisible = frame and frame.Visible
	if isVisible then
		localScript:SetAttribute("Hide", true)
		localScript:SetAttribute("Show", false)
		print("[GeneralUI] Fechando Chars")
	else
		-- Fechar Equip se estiver aberto
		local equipGui = playerGui:FindFirstChild("Equip")
		if equipGui then
			for _, ls in ipairs(equipGui:GetChildren()) do
				if ls:IsA("LocalScript") then
					ls:SetAttribute("Hide", true)
					ls:SetAttribute("Show", false)
				end
			end
		end
		localScript:SetAttribute("Show", true)
		localScript:SetAttribute("Hide", false)
		print("[GeneralUI] Abrindo Chars")
	end
end

btnChars.MouseButton1Click:Connect(toggleChars)

-- ===== Equip UI Toggle =====
local function getEquipGui()
	return playerGui:FindFirstChild("Equip")
end

local function findEquipScript(equipGui)
	if not equipGui then return nil end
	for _, child in ipairs(equipGui:GetChildren()) do
		if child:IsA("LocalScript") then return child end
	end
	for _, d in ipairs(equipGui:GetDescendants()) do
		if d:IsA("LocalScript") then return d end
	end
	return nil
end

local function toggleEquip()
	local equipGui = getEquipGui()
	if not equipGui then
		warn("[GeneralUI] toggleEquip: Equip GUI não encontrado")
		return
	end
	local scriptLS = findEquipScript(equipGui)
	if not scriptLS then
		warn("[GeneralUI] toggleEquip: LocalScript do Equip não encontrado")
		return
	end
	local frame = equipGui:FindFirstChild("Frame")
	local isVisible = frame and frame.Visible
	print(string.format("[GeneralUI] toggleEquip: isVisible=%s ShowAttr=%s HideAttr=%s", tostring(isVisible), tostring(scriptLS:GetAttribute("Show")), tostring(scriptLS:GetAttribute("Hide"))))
	if isVisible then
		scriptLS:SetAttribute("Hide", true)
		scriptLS:SetAttribute("Show", false)
		print("[GeneralUI] Fechando Equip")
	else
		-- Fechar Chars se estiver aberto
		local charsGui = getCharsGui()
		if charsGui then
			for _, ls in ipairs(charsGui:GetChildren()) do
				if ls:IsA("LocalScript") then
					ls:SetAttribute("Hide", true)
					ls:SetAttribute("Show", false)
				end
			end
		end
		scriptLS:SetAttribute("Show", true)
		scriptLS:SetAttribute("Hide", false)
		print("[GeneralUI] Abrindo Equip (atributos definidos)")
	end
end

if btnEquip and btnEquip:IsA("ImageButton") then
	btnEquip.MouseButton1Click:Connect(toggleEquip)
end

-- Permitir clicar em um slot equipado para abrir inventário já focado naquele personagem
local function setupSlotClickHandlers() end -- placeholder redefinido depois

-- Guardar EquippedOrder atual para suportar clique
local _lastEquippedOrder = nil
-- Ajustar applyEquippedSlots para atualizar _lastEquippedOrder e reconfigurar handlers
local _origApplyEquippedSlots = applyEquippedSlots
applyEquippedSlots = function(characters)
	if characters and (characters.EquippedOrder or characters.equippedOrder) then
		_lastEquippedOrder = characters.EquippedOrder or characters.equippedOrder
	end
	_origApplyEquippedSlots(characters)
	setupSlotClickHandlers()
end

-- Função para abrir inventário e marcar seleção pendente
local function openInventoryAndSelect(instId)
	if not instId then return end
	local charsGui = getCharsGui()
	if not charsGui then return end
	local function findCharsScript()
		local direct = charsGui:FindFirstChild("Chars_Inv.client") or charsGui:FindFirstChild("Chars_Inv.client.lua")
		if direct then return direct end
		for _, d in ipairs(charsGui:GetDescendants()) do
			if d:IsA("LocalScript") and d.Name:find("Chars_Inv") then
				return d
			end
		end
		return nil
	end
	local charsScript = findCharsScript()
	if not charsScript then return end
	charsScript:SetAttribute("PendingSelectInstanceId", instId)
	-- Ver se já está aberto
	local frame = charsGui:FindFirstChild("Frame")
	local alreadyOpen = frame and frame.Visible
	if not alreadyOpen then
		charsScript:SetAttribute("Show", true)
		charsScript:SetAttribute("Hide", false)
	end
end

-- Reconfigurar clique handler para cada slot (substituindo placeholder anterior) - definindo apenas dentro do applyEquippedSlots patch
-- Sobrescrever setupSlotClickHandlers com lógica que resolve instId e chama openInventoryAndSelect
function setupSlotClickHandlers()
    for idx, slot in ipairs(slotRefs) do
        if slot then
            local icon = findIconLabel(slot)
            if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
                if not icon:GetAttribute("ClickHooked2") then
                    icon:SetAttribute("ClickHooked2", true)
                    icon.InputBegan:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1 then
                            local order = _lastEquippedOrder or {}
                            local instId = order[idx]
                            if instId and instId ~= "" and instId ~= "_EMPTY_" then
                                openInventoryAndSelect(instId)
                            end
                        end
                    end)
                end
            end
        end
    end
end