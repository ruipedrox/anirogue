local TweenService = game:GetService("TweenService")

local root = script.Parent
local frame = root:FindFirstChild("Frame") or root:FindFirstChild("Frame", true) or root:FindFirstChild("1st")
if not frame then
	warn("[InvUI] Frame não encontrado em Inv GUI")
	return
end

local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local hiddenPos = UDim2.new(frame.Position.X.Scale, frame.Position.X.Offset, 1.2, 0)
local shownPos = frame.Position
local function show()
	frame.Visible = true
	frame.Position = hiddenPos
	TweenService:Create(frame, tweenInfo, { Position = shownPos }):Play()
	isOpen = true
	pcall(function() script:SetAttribute("Show", true); script:SetAttribute("Hide", false) end)

	-- Debug: print current evolve drops when opening UI
	pcall(function()
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:WaitForChild("Remotes")
		local gp = Remotes and Remotes:FindFirstChild("GetProfile")
		if gp and gp:IsA("RemoteFunction") then
			local ok, res = pcall(function() return gp:InvokeServer() end)
			if ok and res and res.profile and type(res.profile.Drops) == "table" then
				local drops = res.profile.Drops.evolve or {}
				local parts = {}
				for id, q in pairs(drops) do
					table.insert(parts, string.format("%s=%d", tostring(id), tonumber(q) or 0))
				end
				print("[InvUI] Opening - evolve drops:", table.concat(parts, ", ") )
			else
				print("[InvUI] Opening - no evolve drops or profile missing")
			end
		end
	end)

	end

	local function hide()
	-- ensure preview is hidden when inventory closes
	pcall(hidePreview)
	-- Always animate/hide even if isOpen false but frame visible
	if not isOpen then
		if frame.Visible then
			TweenService:Create(frame, tweenInfo, { Position = hiddenPos }):Play()
			task.delay(tweenInfo.Time + 0.02, function()
				frame.Visible = false
				isOpen = false
				pcall(function() script:SetAttribute("Hide", true); script:SetAttribute("Show", false) end)
			end)
		else
			pcall(function() script:SetAttribute("Hide", true); script:SetAttribute("Show", false) end)
		end
		return
	end
	TweenService:Create(frame, tweenInfo, { Position = hiddenPos }):Play()
	task.delay(tweenInfo.Time + 0.02, function()
		frame.Visible = false
		isOpen = false
		pcall(function() script:SetAttribute("Hide", true); script:SetAttribute("Show", false) end)
	end)
end

-- Listen to attributes
local function onShowAttr()
	local v = script:GetAttribute("Show")
	if v then show() end
end
local function onHideAttr()
	local v = script:GetAttribute("Hide")
	if v then hide() end
end
script:GetAttributeChangedSignal("Show"):Connect(onShowAttr)
script:GetAttributeChangedSignal("Hide"):Connect(onHideAttr)

-- Also accept Show/Hide attributes set on the ScreenGui/root itself (some callers set attributes there)
if root.GetAttributeChangedSignal then
	root:GetAttributeChangedSignal("Show"):Connect(function()
		if root:GetAttribute("Show") then show() end
	end)
	root:GetAttributeChangedSignal("Hide"):Connect(function()
		if root:GetAttribute("Hide") then hide() end
	end)
end

-- Hook exit buttons inside frame
for _, desc in ipairs(frame:GetDescendants()) do
	if desc:IsA("GuiButton") then
		local name = (desc.Name or ""):lower()
		if name == "exit" or name == "exit_b" or name:find("exit") then
			desc.MouseButton1Click:Connect(function() hide() end)
			pcall(function() if desc.Activated then desc.Activated:Connect(hide) end end)
		end
	end
end

-- Start hidden
frame.Position = hiddenPos
frame.Visible = false
isOpen = false
pcall(function() script:SetAttribute("Show", false); script:SetAttribute("Hide", true) end)

-- Preview canvas setup (open when clicking an item's ImageButton)
local previewRoot = root:FindFirstChild("Prev") or root:FindFirstChild("Prev", true)
local previewFrame = nil
local previewIsOpen = false
local previewHiddenPos, previewShownPos
if previewRoot then
	previewFrame = previewRoot:FindFirstChild("Frame", true) or previewRoot:FindFirstChildWhichIsA("Frame", true)
	if previewFrame then
		previewShownPos = previewFrame.Position
		previewHiddenPos = UDim2.new(previewShownPos.X.Scale, previewShownPos.X.Offset, 1.2, 0)
		previewFrame.Position = previewHiddenPos
		previewRoot.Visible = false
	end
end

local function hidePreview()
	if not previewFrame or not previewRoot then return end
	-- hide instantly (no animation)
	previewFrame.Position = previewHiddenPos
	previewRoot.Visible = false
	previewIsOpen = false
end

-- optional third argument `overrideSeq` lets caller pass a precomputed ColorSequence
local function showPreview(itemId, itemImage, overrideSeq)
	warn("[InvUI] showPreview called for", itemId)
	-- Ensure caches are populated early to avoid race where cache is nil at preview time
	pcall(function()
		if type(resolveItemIcon) == "function" then
			resolveItemIcon(itemId)
		end
	end)

	-- Diagnostics: print cache table reference and creation tick to understand why it might be nil
	pcall(function()
		warn("[InvUI] DEBUG in showPreview - dropDescriptionByIdCache ref:", tostring(dropDescriptionByIdCache), "script:", script and script:GetFullName())
		warn("[InvUI] DEBUG global cache created tick:", _G._InvUI_dropDesc_cache_created)
	end)
	-- Use the exact UI path: PlayerGui -> Inv (root) -> Frame -> Prev -> Frame -> Icon_i -> EQ_BG -> Icon
	-- Do not use recursive finds; navigate the chain explicitly.
	local invFrameNode = root:FindFirstChild("Frame")
	if not invFrameNode then warn("[InvUI] missing inv Frame") return end
	local prevNode = invFrameNode:FindFirstChild("Prev")
	local prevInner = prevNode:FindFirstChild("Frame")
	local iconI = prevInner:FindFirstChild("Icon_i")
	local eqBg = iconI:FindFirstChild("EQ_BG")
	local exactIcon = eqBg:FindFirstChild("Icon")
	if not prevNode then warn("[InvUI] missing Prev") return end
	if not prevInner then warn("[InvUI] missing Prev.Frame") return end
	if not iconI then warn("[InvUI] missing Icon_i") return end
	if not eqBg then warn("[InvUI] missing EQ_BG") return end
	if not exactIcon then warn("[InvUI] missing Icon under EQ_BG") return end
	-- show preview root/frame
	if previewRoot then previewRoot.Visible = true end
	if previewFrame then previewFrame.Position = previewShownPos end
	-- resolve item image and rarity
	local asset = itemImage
	if not asset and itemId and type(resolveItemIcon) == "function" then
		local ok, res = pcall(function() return resolveItemIcon(itemId) end)
		if ok and res then asset = res end
	end
	local rarity = nil
	if itemId and type(resolveItemRarity) == "function" then
		local ok2, res2 = pcall(function() return resolveItemRarity(itemId) end)
		warn("[InvUI] resolve pcall result:", ok2, res2)
		if ok2 and res2 then
			rarity = res2
		else
			-- fallback: try raw cache directly (diagnostic + resilience)
			pcall(function()
				local cached = nil
				if dropRarityByIdCache then
					cached = dropRarityByIdCache[itemId]
					if not cached then cached = dropRarityByIdCache[tostring(itemId)] end
					if not cached and tonumber(itemId) then cached = dropRarityByIdCache[tonumber(itemId)] end
					if not cached then
						local sid = tostring(itemId):lower()
						for k,v in pairs(dropRarityByIdCache) do
							if tostring(k):lower() == sid then
								cached = v
								warn("[InvUI] cached rarity matched via case-insensitive key", k)
								break
							end
						end
					end
				end
				warn("[InvUI] resolver returned nil; cached rarity for", itemId, "=", tostring(cached))
				if not rarity and cached then rarity = cached end
			end)
		end
	end
	local seq = overrideSeq
	-- if caller passed a ColorSequence, prefer it (this avoids cache/timing issues)
	if rarity and type(toKey) == "function" and rarityGradients then
		local key = nil
		local ok3, res3 = pcall(function() return toKey(rarity) end)
		if ok3 and res3 then key = res3 end
		if key then seq = rarityGradients[key] end
	end

	-- Prefer values from the already-rendered clone (icon image + gradient) to avoid resolver races
	pcall(function()
		if scrolling and itemId then
			local entry = scrolling:FindFirstChild("drop_" .. tostring(itemId))
			if entry then
				-- clone's icon image
				local ico = entry:FindFirstChild("Icon_img", true)
				if ico and (ico:IsA("ImageLabel") or ico:IsA("ImageButton")) then
					asset = asset or ico.Image
				end
				-- clone's gradient (prefer EQ_BG.UIGradient if present)
				local eqClone = entry:FindFirstChild("EQ_BG", true)
				local ugClone = nil
				if eqClone then
					ugClone = eqClone:FindFirstChild("UIGradient") or eqClone:FindFirstChildWhichIsA("UIGradient", true)
				end
				if (not ugClone) then
					ugClone = entry:FindFirstChildWhichIsA("UIGradient", true)
				end
				if ugClone and ugClone:IsA("UIGradient") then
					seq = seq or ugClone.Color
				end
			end
		end
	end)
	warn("[InvUI] resolved asset", asset, "rarity", tostring(rarity), "seq", tostring(seq))
	-- set the icon on the exact node
	if exactIcon and (exactIcon:IsA("ImageLabel") or exactIcon:IsA("ImageButton")) and asset then
		pcall(function() exactIcon.Image = asset end)
		pcall(function()
			exactIcon.BackgroundTransparency = 1
			exactIcon.ImageTransparency = 0
			if exactIcon:IsA("ImageButton") then
				pcall(function() exactIcon.AutoButtonColor = false end)
			end
			-- if the icon contains inner image children, ensure they are transparent too
			for _, c in ipairs(exactIcon:GetChildren()) do
				if c:IsA("ImageLabel") or c:IsA("ImageButton") then
					pcall(function() c.ImageTransparency = 0; c.BackgroundTransparency = 1 end)
				end
			end
		end)
	end
	-- update the existing UIGradient inside EQ_BG (do not create/destroy children)
	if seq then
		-- Set the UIGradient located at EQ_BG -> UIGradient (exact path)
		local ug = eqBg:FindFirstChild("UIGradient")
		if ug and ug:IsA("UIGradient") then
			pcall(function()
				-- debug log to help trace why gradient might not update
				warn("[InvUI] Applying gradient for item", itemId, "rarity:" , tostring(rarity))
				ug.Color = seq
				ug.Rotation = -90
				-- ensure EQ_BG is visible and its image doesn't block
				eqBg.BackgroundTransparency = 0
				if eqBg:IsA("ImageLabel") or eqBg:IsA("ImageButton") then
					eqBg.ImageTransparency = 1
				end
				-- do NOT modify EQ_BG.Frame or its children (preserve template)
			end)
		end
	end

	-- set display name and description inside the preview using clone values or cached resolvers
	pcall(function()
		local innerFrame = eqBg:FindFirstChild("Frame")
		if not (innerFrame and innerFrame:IsA("Frame")) then return end
		-- Name
		local nameLbl = innerFrame:FindFirstChild("Name")
		if nameLbl and (nameLbl:IsA("TextLabel") or nameLbl:IsA("TextButton")) then
			local display = nil
			pcall(function()
				if scrolling and itemId then
					local entry = scrolling:FindFirstChild("drop_" .. tostring(itemId))
					if entry then
						local nLbl = entry:FindFirstChild("Name", true)
						if nLbl and (nLbl:IsA("TextLabel") or nLbl:IsA("TextButton")) then
							display = nLbl.Text
						end
					end
				end
			end)
			if (not display or display == "") and type(resolveItemDisplayName) == "function" then
				local ok, res = pcall(function() return resolveItemDisplayName(itemId) end)
				if ok and res then display = res end
			end
			if (not display or display == "") then display = tostring(itemId) end
			nameLbl.Text = display
		end

		-- Description
		pcall(function()
			local prevDesc = nil
			local descLbl = nil
			-- find Desc container under preview
			if prevInner then
				prevDesc = prevInner:FindFirstChild("Desc")
			end
			warn("[InvUI] prevDesc found:", tostring(prevDesc ~= nil))
			descLbl = prevDesc and prevDesc:FindFirstChild("Desc_text")
			warn("[InvUI] descLbl class:", descLbl and descLbl.ClassName or "nil")
			local displayDesc = nil
			-- try clone-rendered desc first
			pcall(function()
				if scrolling and itemId then
					local entry = scrolling:FindFirstChild("drop_" .. tostring(itemId))
					if entry then
						local d = entry:FindFirstChild("Desc_text", true)
						if d and (d:IsA("TextLabel") or d:IsA("TextBox")) then
							displayDesc = d.Text
						end
					end
				end
			end)
			-- fallback to resolver cache
			if (not displayDesc or displayDesc == "") and type(resolveItemDescription) == "function" then
				local ok, res = pcall(function() return resolveItemDescription(itemId) end)
				if ok and res then displayDesc = res end
			end
			warn("[InvUI] displayDesc resolved:", tostring(displayDesc))
			-- if still missing, try direct cache lookup
			if (not displayDesc or displayDesc == "") then
				pcall(function()
					local cached = nil
					if dropDescriptionByIdCache then
						cached = dropDescriptionByIdCache[itemId]
						if not cached then cached = dropDescriptionByIdCache[tostring(itemId)] end
						if not cached and tonumber(itemId) then cached = dropDescriptionByIdCache[tonumber(itemId)] end
						if not cached then
							local sid = tostring(itemId):lower()
							for k,v in pairs(dropDescriptionByIdCache) do
								if tostring(k):lower() == sid then
									cached = v
									warn("[InvUI] direct cache match via case-insensitive key", k)
									break
								end
							end
						end
					end
					warn("[InvUI] direct cache lookup for desc:", tostring(cached))
					if cached and cached ~= "" then displayDesc = cached end
				end)
			end
			-- as a last resort, iterate Drops Items modules and populate cache then retry
			if (not displayDesc or displayDesc == "") then
				pcall(function()
					-- Diagnostics: print itemId types and cache state to help debug missing descriptions
					local okDesc, resDesc = pcall(function() return resolveItemDescription and resolveItemDescription(itemId) end)
					warn("[InvUI] DEBUG resolveItemDescription pcall:", okDesc, resDesc)
					warn("[InvUI] DEBUG itemId type:", type(itemId), " tostring:", tostring(itemId))
					if not dropDescriptionByIdCache then
						warn("[InvUI] DEBUG dropDescriptionByIdCache is nil")
					else
						local c = 0
						for k,_ in pairs(dropDescriptionByIdCache) do
							c = c + 1
							warn("[InvUI] DEBUG cache key:", tostring(k))
							if c >= 20 then break end
						end
						warn("[InvUI] DEBUG cache size:", c)
					end
					-- attempt to populate from module scripts using a safe local ReplicatedStorage reference
					local RS = game:GetService("ReplicatedStorage")
					local Shared = RS:FindFirstChild("Shared") or RS:WaitForChild("Shared")
					local Drops = Shared and Shared:FindFirstChild("Drops")
					if Drops then
						for _, cat in ipairs(Drops:GetChildren()) do
							local itemsMod = cat:FindFirstChild("Items")
							if itemsMod and itemsMod:IsA("ModuleScript") then
								local ok2, itemsTbl = pcall(require, itemsMod)
								if ok2 and type(itemsTbl) == "table" then
									local def = itemsTbl[itemId] or itemsTbl[tostring(itemId)]
									if not def then
										-- try case-insensitive lookup
										local sid = tostring(itemId):lower()
										for k,v in pairs(itemsTbl) do
											if tostring(k):lower() == sid then def = v; break end
										end
									end
									if def and type(def) == "table" then
										if type(def.Description) == "string" then
											dropDescriptionByIdCache[itemId] = def.Description
											displayDesc = def.Description
											warn("[InvUI] populated desc from module for", itemId, def.Description)
										elseif type(def.Desc) == "string" then
											dropDescriptionByIdCache[itemId] = def.Desc
											displayDesc = def.Desc
											warn("[InvUI] populated desc from module (Desc) for", itemId, def.Desc)
										end
									end
								end
							end
						end
					end
				end)
			end
			if descLbl then
				pcall(function()
					-- ensure label is visible and readable
					descLbl.Visible = true
					if descLbl:IsA("TextLabel") or descLbl:IsA("TextBox") then
						descLbl.TextTransparency = 0
						descLbl.TextWrapped = true
						descLbl.Text = displayDesc or ""
					end
				end)
			else
				warn("[InvUI] Desc_text not found under Prev.Frame.Desc — cannot set description")
			end
		end)
	end)

	previewIsOpen = true
end

-- Hook exit/close buttons inside preview
if previewRoot then
	for _, desc in ipairs(previewRoot:GetDescendants()) do
		if desc:IsA("GuiButton") then
			local name = (desc.Name or ""):lower()
			if name == "exit" or name == "close" or name:find("exit") or name:find("close") then
				desc.MouseButton1Click:Connect(hidePreview)
				pcall(function() if desc.Activated then desc.Activated:Connect(hidePreview) end end)
			end
		end
	end
end

-- Inventory renderer: populate Inv_frame/ScrollingFrame from profile.Drops.evolve
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ProfileUpdatedRE = Remotes:WaitForChild("ProfileUpdated")
local GetProfileRF = Remotes:WaitForChild("GetProfile")

local invContainer = frame:FindFirstChild("Inv")
local invFrame = invContainer and invContainer:FindFirstChild("Inv_frame")
local scrolling = invFrame and invFrame:FindFirstChild("ScrollingFrame")
local template = scrolling and scrolling:FindFirstChild("inv_icon")
if template and template:IsA("Frame") then
	template.Visible = false
end
if scrolling then
	pcall(function()
		scrolling.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scrolling.ScrollingDirection = Enum.ScrollingDirection.Y
	end)
end

local function clearOldDrops()
	if not scrolling then return end
	for _, ch in ipairs(scrolling:GetChildren()) do
		if ch:IsA("Frame") and ch ~= template then
			pcall(function() ch:Destroy() end)
		end
	end
end

-- Lazy cache for item icons / rarities from Shared/Drops/*/Items.lua
local dropIconByIdCache = nil
local dropRarityByIdCache = nil
local dropDisplayNameByIdCache = nil
local dropDescriptionByIdCache = nil
local function resolveItemIcon(itemId)
	if not itemId or itemId == "" then return "rbxassetid://0" end
	if not dropIconByIdCache then
		dropIconByIdCache = {}
		dropRarityByIdCache = {}
		dropDisplayNameByIdCache = {}
		dropDescriptionByIdCache = {}
		-- Diagnostics: record creation tick and script context
		pcall(function()
			warn("[InvUI] DEBUG created dropDescriptionByIdCache", tostring(dropDescriptionByIdCache), "script:", script and script:GetFullName())
			_G._InvUI_dropDesc_cache_created = tick()
		end)
		pcall(function()
			local Shared = ReplicatedStorage:WaitForChild("Shared")
			local Drops = Shared:FindFirstChild("Drops")
			if not Drops then return end
			for _, cat in ipairs(Drops:GetChildren()) do
				local itemsMod = cat:FindFirstChild("Items")
				if itemsMod and itemsMod:IsA("ModuleScript") then
					local ok2, itemsTbl = pcall(require, itemsMod)
					if ok2 and type(itemsTbl) == "table" then
						for id, def in pairs(itemsTbl) do
							if type(def) == "table" then
								if type(def.Icon) == "string" then
									dropIconByIdCache[id] = def.Icon
									warn("[InvUI] cached icon for", id, dropIconByIdCache[id])
								end
								if type(def.Rarity) == "string" then
									dropRarityByIdCache[id] = def.Rarity
									warn("[InvUI] cached rarity for", id, dropRarityByIdCache[id])
								end
								if type(def.DisplayName) == "string" then
									dropDisplayNameByIdCache[id] = def.DisplayName
									warn("[InvUI] cached displayName for", id, dropDisplayNameByIdCache[id])
								elseif type(def.Name) == "string" then
									dropDisplayNameByIdCache[id] = def.Name
									warn("[InvUI] cached displayName for", id, dropDisplayNameByIdCache[id])
								end
								-- Description / tooltip support
								if type(def.Description) == "string" then
									dropDescriptionByIdCache[id] = def.Description
									warn("[InvUI] cached description for", id, dropDescriptionByIdCache[id])
								elseif type(def.Desc) == "string" then
									dropDescriptionByIdCache[id] = def.Desc
									warn("[InvUI] cached description for", id, dropDescriptionByIdCache[id])
								end
							end
						end
					end
				end
			end
		end)
	end
	return dropIconByIdCache[itemId] or "rbxassetid://0"
end

local function resolveItemRarity(itemId)
	if not itemId or itemId == "" then return nil end
	if not dropRarityByIdCache then resolveItemIcon(itemId) end
	local v = dropRarityByIdCache and dropRarityByIdCache[itemId] or nil
	warn("[InvUI] resolveItemRarity for", itemId, "=>", tostring(v))
	return v
end

local function resolveItemDisplayName(itemId)
    if not itemId or itemId == "" then return nil end
    if not dropDisplayNameByIdCache then resolveItemIcon(itemId) end
    local v = dropDisplayNameByIdCache and dropDisplayNameByIdCache[itemId] or nil
    warn("[InvUI] resolveItemDisplayName for", itemId, "=>", tostring(v))
    return v
end

local function resolveItemDescription(itemId)
	if not itemId or itemId == "" then return nil end
	if not dropDescriptionByIdCache then resolveItemIcon(itemId) end
	local v = dropDescriptionByIdCache and dropDescriptionByIdCache[itemId] or nil
	warn("[InvUI] resolveItemDescription for", itemId, "=>", tostring(v))
	return v
end

-- Rarity -> gradient mapping
local rarityGradients = {
	-- Mapping requested by designer:
	-- comum = green, raro = dark blue, epico = purple, lendario = gold, mitico = red
	comum = ColorSequence.new(Color3.fromRGB(100,190,100), Color3.fromRGB(160,255,160)),
	raro = ColorSequence.new(Color3.fromRGB(50,80,160), Color3.fromRGB(90,140,220)),
	epico = ColorSequence.new(Color3.fromRGB(170,90,255), Color3.fromRGB(230,160,255)),
	lendario = ColorSequence.new(Color3.fromRGB(255,195,0), Color3.fromRGB(255,230,120)),
	mitico = ColorSequence.new(Color3.fromRGB(220,40,60), Color3.fromRGB(255,110,120)),
}

local function toKey(str)
	if type(str) ~= "string" then return nil end
	local s = string.lower(str)
	if s == "common" then return "comum" end
	if s == "rare" then return "raro" end
	if s == "epic" then return "epico" end
	if s == "legendary" then return "lendario" end
	if s == "mythic" then return "mitico" end
	return s
end

local function setGradientBG(bg, colorSeq)
	if not (bg and bg:IsA("GuiObject")) then return end
	pcall(function()
		-- hide any image on the container so gradient is visible
		if bg:IsA("ImageLabel") or bg:IsA("ImageButton") then
			bg.ImageTransparency = 1
		end
		-- try to reuse an existing UIGradient (so editor-set gradient is preserved)
		local existingGrad = nil
		for _, child in ipairs(bg:GetChildren()) do
			if child:IsA("UIGradient") then
				existingGrad = child
				break
			end
		end
		bg.BackgroundTransparency = 0
		if existingGrad then
			existingGrad.Rotation = -90
			existingGrad.Color = colorSeq
			existingGrad.Name = existingGrad.Name or "R_Grad"
		else
			local grad = Instance.new("UIGradient")
			grad.Name = "R_Grad"
			grad.Rotation = -90
			grad.Color = colorSeq
			grad.Parent = bg
		end
		-- Apply gradient to EQ_BG itself (do not modify EQ_BG.Frame)
		-- Ensure any existing UIGradient on bg is updated; do not touch inner Frame
		local existingBgGrad = nil
		for _, c in ipairs(bg:GetChildren()) do
			if c:IsA("UIGradient") then existingBgGrad = c; break end
		end
		bg.BackgroundTransparency = 0
		if existingBgGrad then
			pcall(function()
				existingBgGrad.Rotation = -90
				existingBgGrad.Color = colorSeq
			end)
		else
			pcall(function()
				local g = Instance.new("UIGradient")
				g.Name = "R_Grad"
				g.Rotation = -90
				g.Color = colorSeq
				g.Parent = bg
			end)
		end
		-- ensure bg image is hidden so gradient is visible
		if bg:IsA("ImageLabel") or bg:IsA("ImageButton") then
			pcall(function() bg.ImageTransparency = 1 end)
		end
		-- neutralize stroke color that may be present on template (avoids orange border)
		local stroke = bg:FindFirstChildOfClass("UIStroke") or bg:FindFirstChild("UIStroke")
		if stroke and stroke:IsA("UIStroke") then
			stroke.Color = Color3.fromRGB(90,90,90)
			stroke.Transparency = 0.4
		end
	end)
end

local function setQuantityLabel(itemFrame, qty)
	if not itemFrame then return end
	-- try direct child named Quantity first, else first TextLabel descendant
	local qLabel = itemFrame:FindFirstChild("Quantity", true)
	if not qLabel or not qLabel:IsA("TextLabel") then
		for _, d in ipairs(itemFrame:GetDescendants()) do
			if d:IsA("TextLabel") then
				qLabel = d
				break
			end
		end
	end
	if qLabel and qLabel:IsA("TextLabel") then
		qLabel.Text = tostring(qty or 0)
	end
end

local function renderDropsFromProfile(profile)
	if not scrolling or not template then return end
	local drops = (profile and profile.Drops and profile.Drops.evolve) or {}
	clearOldDrops()
	local order = 1
	for id, qty in pairs(drops) do
		local n = tonumber(qty) or 0
		if n > 0 then
			local clone = template:Clone()
			clone.Name = "drop_" .. tostring(id)
			clone.Visible = true
			clone.LayoutOrder = order
			order = order + 1
			setQuantityLabel(clone, n)
				-- set icon image from Drops registry
				local iconImg = clone:FindFirstChild("Icon_img", true)
				local iconAsset = resolveItemIcon(id)
				if iconImg and (iconImg:IsA("ImageLabel") or iconImg:IsA("ImageButton")) then
					pcall(function() iconImg.Image = iconAsset end)
					pcall(function()
						iconImg.BackgroundTransparency = 1
						iconImg.ImageTransparency = 0
					end)
					-- attach preview open on click if this is an ImageButton
					if iconImg:IsA("ImageButton") then
						pcall(function()
							-- capture the seq/color used for this clone so preview can reuse it
							local rarity_local = resolveItemRarity(id)
							local key_local = toKey(rarity_local)
							local seq_local = rarityGradients[key_local]
							iconImg.Activated:Connect(function()
								warn("[InvUI] icon click connected for", id)
								showPreview(id, iconAsset, seq_local)
							end)
						end)
					end
				end
				-- set background gradient based on rarity
				local rarity = resolveItemRarity(id)
				local key = toKey(rarity)
				local seq = rarityGradients[key]
				if seq then
					setGradientBG(clone, seq)
				end
				clone.Parent = scrolling
		end
	end
end

-- Initial population: fetch profile snapshot and render drops
pcall(function()
	local ok, res = pcall(function() return GetProfileRF:InvokeServer() end)
	if ok and res and res.profile then
		renderDropsFromProfile(res.profile)
	end
end)

-- Update on ProfileUpdated events (full snapshot preferred)
ProfileUpdatedRE.OnClientEvent:Connect(function(payload)
	if not payload then return end
	if payload.full and type(payload.full) == "table" then
		renderDropsFromProfile(payload.full)
		return
	end
	-- fallback: refetch snapshot to obtain drops when partial update occurs
	task.delay(0.05, function()
		pcall(function()
			local ok2, res2 = pcall(function() return GetProfileRF:InvokeServer() end)
			if ok2 and res2 and res2.profile then
				renderDropsFromProfile(res2.profile)
			end
		end)
	end)
end)