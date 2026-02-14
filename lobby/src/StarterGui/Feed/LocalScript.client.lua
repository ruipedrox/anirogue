-- Feed LocalScript
-- Listens for a BindableEvent `SetMain` (preferred) or the `FeedMain` attribute (fallback)
-- When received, stores the main instance id and shows the feed Frame.

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local function findScreenGui()
	-- The script may be child of the ScreenGui or inside the Frame; search up for a ScreenGui
	local anc = script
	while anc and not anc:IsA("ScreenGui") do
		anc = anc.Parent
	end
	return anc
end

local screenGui = findScreenGui() or (player and player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("Feed"))
if not screenGui then
	warn("[Feed] ScreenGui 'Feed' not found as ancestor; script may be misplaced")
	return
end

-- Find the main Frame inside the ScreenGui
local frame = screenGui:FindFirstChild("Frame") or screenGui:FindFirstChildWhichIsA("Frame", true)
if frame and frame:IsA("GuiObject") then
	-- Ensure the feed UI starts hidden until explicitly opened
	frame.Visible = false
end

-- Ensure a BindableEvent exists for SetMain so other scripts can call it
local setMainEvent = screenGui:FindFirstChild("SetMain")
if not setMainEvent then
	setMainEvent = Instance.new("BindableEvent")
	setMainEvent.Name = "SetMain"
	setMainEvent.Parent = screenGui
end

local feedMainId = nil
local feedInitLevel = nil
local feedInitXP = 0
local selectedFeeders = {}

-- Remotes
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GetCharacterInventoryRF = Remotes:FindFirstChild("GetCharacterInventory")
local ProfileUpdatedRE = Remotes:FindFirstChild("ProfileUpdated")
local CharacterCatalog = nil
pcall(function() CharacterCatalog = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("CharacterCatalog")) end)

-- Star color palette (reuse same mapping as Chars UI)
local StarColors = {
	[1] = Color3.fromRGB(130,130,130),
	[2] = Color3.fromRGB(90,170,90),
	[3] = Color3.fromRGB(70,130,255),
	[4] = Color3.fromRGB(180,85,255),
	[5] = Color3.fromRGB(255,190,40),
	[6] = Color3.fromRGB(255,50,50),
}
local function colorForStars(stars)
	return StarColors[stars] or Color3.fromRGB(255,255,255)
end

local function ensureStarGradient(targetFrame, stars)
	if not targetFrame then return end
	stars = tonumber(stars) or 1
	if stars < 1 then stars = 1 end
	if stars > 6 then stars = 6 end
	-- Explicit gradient palette per star count (lighter, base, darker)
	local Pal = {
		[1] = { Color3.fromRGB(200,200,200), Color3.fromRGB(130,130,130), Color3.fromRGB(60,60,60) },
		[2] = { Color3.fromRGB(180,230,180), Color3.fromRGB(90,170,90), Color3.fromRGB(30,80,30) },
		[3] = { Color3.fromRGB(160,200,255), Color3.fromRGB(70,130,255), Color3.fromRGB(20,60,140) },
		[4] = { Color3.fromRGB(220,160,255), Color3.fromRGB(180,85,255), Color3.fromRGB(90,30,140) },
		[5] = { Color3.fromRGB(255,230,160), Color3.fromRGB(255,190,40), Color3.fromRGB(160,110,20) },
		[6] = { Color3.fromRGB(255,160,160), Color3.fromRGB(255,50,50), Color3.fromRGB(150,20,20) },
	}
	local trio = Pal[stars] or Pal[1]
	local lighter, baseCol, darker = trio[1], trio[2], trio[3]

	-- Find any UIGradient under targetFrame (descendants first) to update
	local grad = nil
	for _, d in ipairs(targetFrame:GetDescendants()) do
		if d:IsA("UIGradient") then
			grad = d
			break
		end
	end
	-- If not found in descendants, check direct children
	if not grad then
		for _, c in ipairs(targetFrame:GetChildren()) do
			if c:IsA("UIGradient") then
				grad = c
				break
			end
		end
	end
	if not grad then
		grad = Instance.new("UIGradient")
		grad.Name = "StarGradient"
		grad.Parent = targetFrame
	end
	grad.Rotation = 90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, lighter),
		ColorSequenceKeypoint.new(0.45, baseCol),
		ColorSequenceKeypoint.new(1, darker),
	})
	grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0) })
	-- Avoid forcing background color if the frame already uses visuals; do not override
	return grad
end

-- XP curve constants (mirror server)
local HARD_CAP = 80
local BASE_XP = 100
local GROWTH = 1.10
local function XPRequired(level)
	if (tonumber(level) or 0) >= HARD_CAP then return 0 end
	return math.floor(BASE_XP * (GROWTH ^ ((tonumber(level) or 1) - 1)) + 0.5)
end

local function computeFinalLevel(initLevel, initXP, addedXP)
	initLevel = tonumber(initLevel) or 1
	initXP = tonumber(initXP) or 0
	addedXP = tonumber(addedXP) or 0
	local curLevel = initLevel
	local curXP = initXP + addedXP
	while curLevel < HARD_CAP do
		local need = XPRequired(curLevel)
		if curXP >= need then
			curXP = curXP - need
			curLevel = curLevel + 1
		else
			break
		end
	end
	return curLevel
end

local FEED_EFFECTIVENESS = 0.5

local function safeRequireCharStats(template)
	local Shared = ReplicatedStorage:FindFirstChild("Shared")
	if not Shared then return nil end
	local chars = Shared:FindFirstChild("Chars")
	if not chars then return nil end
	local folder = chars:FindFirstChild(template)
	if not folder then return nil end
	local statsModule = folder:FindFirstChild("Stats")
	if not statsModule or not statsModule:IsA("ModuleScript") then return nil end
	local ok, res = pcall(require, statsModule)
	if not ok or type(res) ~= "table" then return nil end
	return res
end

local function getFeedXPForInstance(inst)
	if not inst then return 0 end
	-- Preferred behavior: use current instance XP (half of it) plus the character's Stats.FeedXP
	local curXP = tonumber(inst.XP)
	local feedFromXP = 0
	if curXP and curXP > 0 then
		feedFromXP = math.floor(curXP * FEED_EFFECTIVENESS + 0.5)
	end
	local stats = nil
	pcall(function() stats = safeRequireCharStats(inst.TemplateName) end)
	local statFeed = 0
	if stats and type(stats.FeedXP) == "number" then
		statFeed = math.floor(stats.FeedXP)
	end
	if feedFromXP > 0 or statFeed > 0 then
		pcall(function()
			print("[Feed][DEBUG getFeedXPForInstance] id=", tostring(inst.Id or inst.id), "XP_half=", tostring(feedFromXP), "statFeed=", tostring(statFeed))
		end)
		return math.max(0, feedFromXP + statFeed)
	end

	-- Fallback: compute accumulated XP across previous levels (legacy behavior)
	local level = tonumber(inst.Level) or 1
	local total = 0
	for l = 1, (level - 1) do
		total = total + XPRequired(l)
	end
	total = total + (tonumber(inst.XP) or 0)
	pcall(function()
		print("[Feed][DEBUG getFeedXPForInstance] fallback accumulated total=", tostring(total))
	end)
	local value = math.floor(total * FEED_EFFECTIVENESS + 0.5)
	if value <= 0 then
		local cat = nil
		pcall(function() if CharacterCatalog then cat = CharacterCatalog:Get(inst.TemplateName) end end)
		if cat and cat.stars then value = cat.stars * 1000 end
	end
	return math.max(0, value)
end

local function applySelectionOverlayToIcon(iconFrame, enabled)
	if not iconFrame then return end
	local overlay = iconFrame:FindFirstChild("SelectOverlay")
	if enabled then
		if not overlay then
			overlay = Instance.new("Frame")
			overlay.Name = "SelectOverlay"
			overlay.AnchorPoint = Vector2.new(1,0)
			overlay.Size = UDim2.fromScale(0.28, 0.28)
			overlay.Position = UDim2.new(1, -2, 0, 2)
			overlay.BackgroundTransparency = 1
			overlay.ZIndex = 130
			local function createShadow(offsetX, offsetY)
				local s = Instance.new("TextLabel")
				s.Name = "S"
				s.AnchorPoint = Vector2.new(0.5,0.5)
				s.Position = UDim2.new(0.5, offsetX, 0.5, offsetY)
				s.Size = UDim2.fromScale(1,1)
				s.BackgroundTransparency = 1
				s.Text = "S"
				s.Font = Enum.Font.FredokaOne
				s.TextScaled = true
				s.TextColor3 = Color3.new(0,0,0)
				s.ZIndex = 131
				s.Parent = overlay
			end
			local offsets = { {-2,0},{2,0},{0,-2},{0,2},{-2,-2},{2,-2},{-2,2},{2,2} }
			for _, off in ipairs(offsets) do createShadow(off[1], off[2]) end
			local main = Instance.new("TextLabel")
			main.Name = "Main"
			main.AnchorPoint = Vector2.new(0.5,0.5)
			main.Position = UDim2.new(0.5,0,0.5,0)
			main.Size = UDim2.fromScale(1,1)
			main.BackgroundTransparency = 1
			main.Text = "S"
			main.Font = Enum.Font.FredokaOne
			main.TextScaled = true
			main.TextColor3 = Color3.fromRGB(40,180,255)
			main.ZIndex = 132
			main.Parent = overlay
			overlay.Parent = iconFrame
		end
		overlay.Visible = true
	else
		if overlay then overlay.Visible = false end
	end
end

local function updatePredictedAttribute(screenGuiRoot)
	local total = 0
	if not feedMainId then
		screenGuiRoot:SetAttribute("PredictedAddedXP", 0)
		return
	end
	for id,_ in pairs(selectedFeeders) do
		-- find inst data in lastInventory cache
		local instData = nil
		-- prefer reliable map built from OrderedList
		if lastInventoryMap and lastInventoryMap[id] then
			instData = lastInventoryMap[id]
		end
		if lastInventory and lastInventory.Instances then
			-- debug: inspect Instances structure
			pcall(function()
				local count = 0
				for k,_ in pairs(lastInventory.Instances) do count = count + 1 end
				print("[Feed][DEBUG] Instances type=", type(lastInventory.Instances), "count=", count)
			end)
			-- preferred map lookup
			if not instData and lastInventory.Instances[id] then
				instData = lastInventory.Instances[id]
			elseif not instData then
				-- fallback: Instances might be array; search for matching Id field
				for _, v in pairs(lastInventory.Instances) do
					if v and (v.Id == id or v.id == id) then
						instData = v
						break
					end
				end
				pcall(function()
					if instData then
						print("[Feed][DEBUG] Found instData for id via array search ->", tostring(id))
					else
						print("[Feed][DEBUG] No instData found for id ->", tostring(id))
					end
				end)
			end
		end
		if instData then
			local v = getFeedXPForInstance(instData)
			pcall(function() print("[Feed][DEBUG] getFeedXPForInstance returned for id", tostring(id), "->", tostring(v)) end)
			total = total + v
		else
			-- fallback: try to infer template name from id (strip trailing unique suffix)
			local inferredTemplate = nil
			pcall(function()
				if type(id) == "string" then
					local base = string.match(id, "^(.-)_[^_]+$")
					if base and base ~= "" then inferredTemplate = base end
				end
			end)
			if inferredTemplate then
				pcall(function() print("[Feed][DEBUG] inferring template from id", tostring(id), "->", tostring(inferredTemplate)) end)
				-- create a synthetic instance that provides TemplateName for feed lookup
				local synth = { TemplateName = inferredTemplate, Level = 1, XP = 0, Id = inferredTemplate }
				local v = getFeedXPForInstance(synth)
				pcall(function() print("[Feed][DEBUG] getFeedXPForInstance (inferred) for", tostring(inferredTemplate), "->", tostring(v)) end)
				total = total + v
			else
				pcall(function() print("[Feed][DEBUG] skip id not found ->", tostring(id)) end)
			end
		end
	end
	-- debug: list selected ids and total feed XP
	pcall(function()
		local sel = {}
		for id,_ in pairs(selectedFeeders) do table.insert(sel, tostring(id)) end
		print("[Feed][DEBUG] updatePredictedAttribute selected=", table.concat(sel, ","), " total=", total)
		screenGuiRoot:SetAttribute("PredictedAddedXP", total)
		-- Show/hide `Feed_frame` when at least one feeder is selected
		pcall(function()
			local feedFrameObj = nil
			-- prefer direct child named Feed_frame
			if screenGuiRoot then
				feedFrameObj = screenGuiRoot:FindFirstChild("Feed_frame")
			end
			-- fallback: search descendants under the main frame or the ScreenGui
			if not feedFrameObj and frame then
				for _, d in ipairs(frame:GetDescendants()) do
					if d.Name == "Feed_frame" and d:IsA("GuiObject") then feedFrameObj = d break end
				end
			end
			if not feedFrameObj and screenGuiRoot then
				for _, d in ipairs(screenGuiRoot:GetDescendants()) do
					if d.Name == "Feed_frame" and d:IsA("GuiObject") then feedFrameObj = d break end
				end
			end
			if feedFrameObj and feedFrameObj:IsA("GuiObject") then
				feedFrameObj.Visible = (total > 0)
			end
		end)
	end)
end


-- cache last fetched inventory
local lastInventory = nil
local lastInventoryMap = nil -- map id -> instance built from OrderedList for reliable lookups

local function renderFeedInventory()
	if not GetCharacterInventoryRF then return end
	local ok, res = pcall(function() return GetCharacterInventoryRF:InvokeServer() end)
	if not ok or not res or not res.inventory then
		warn("[Feed] failed to fetch inventory for feed UI", res)
		return
	end
	lastInventory = res.inventory
	local inv = lastInventory
	-- locate scrolling container (where icons should be parented) and the template item
	local scrolling = nil
	-- prefer a ScrollingFrame descendant under the main frame
	if frame then
		scrolling = frame:FindFirstChildWhichIsA("ScrollingFrame", true)
	end
	if not scrolling then
		-- fallback: search the whole ScreenGui
		scrolling = screenGui:FindFirstChildWhichIsA("ScrollingFrame", true)
	end
	-- find a reasonable template under scrolling (or frame) named like inv_icon / Template / tmpl
	local tmpl = nil
	local function looksLikeTemplate(c)
		if not c then return false end
		if not (c:IsA("Frame") or c:IsA("ImageLabel") or c:IsA("ImageButton")) then return false end
		if c:FindFirstChild("Icon") or c:FindFirstChild("Icon_inv") or c:FindFirstChild("Level") or c:FindFirstChildWhichIsA("UIGridLayout", true) then
			return true
		end
		return false
	end
	if scrolling then
		for _, c in ipairs(scrolling:GetChildren()) do
			if looksLikeTemplate(c) then tmpl = c break end
		end
	end
	if not tmpl and frame then
		for _, c in ipairs(frame:GetDescendants()) do
			if looksLikeTemplate(c) then tmpl = c break end
		end
	end
	if not tmpl then
		-- try common names directly on ScreenGui
		tmpl = screenGui:FindFirstChild("inv_icon") or screenGui:FindFirstChild("Template") or screenGui:FindFirstChild("tmpl")
	end
	if not tmpl then
		warn("[Feed] renderFeedInventory: could not find template item (tmpl) or scrolling container; aborting population")
		return
	end
	-- build a reliable id->instance map from OrderedList (client-side cache)
	lastInventoryMap = {}
	if inv and inv.OrderedList then
		for _, item in ipairs(inv.OrderedList) do
			if item and (item.Id or item.id) then
				lastInventoryMap[tostring(item.Id or item.id)] = item
			end
		end
	end
	-- debug: show sample keys from Instances and OrderedList ids
	pcall(function()
		local keys = {}
		local n = 0
		if inv.Instances then
			for k,_ in pairs(inv.Instances) do
				n = n + 1
				if n <= 10 then table.insert(keys, tostring(k)) end
				if n > 20 then break end
			end
		end
		local orderedIds = {}
		for i = 1, math.min(10, #(inv.OrderedList or {})) do
			table.insert(orderedIds, tostring((inv.OrderedList or {})[i].Id))
		end
		print("[Feed][DEBUG] Instances keys sample=", table.concat(keys, ","))
		print("[Feed][DEBUG] OrderedList ids sample=", table.concat(orderedIds, ","))
	end)
	-- hide the template (it should be cloned, not shown)
	pcall(function() tmpl.Visible = false end)
	selectedFeeders = {}
	updatePredictedAttribute(screenGui)

	-- Clean up previous populated clones (keep tmpl)
	if scrolling then
		pcall(function()
			for _, child in ipairs(scrolling:GetChildren()) do
				if child ~= tmpl and looksLikeTemplate(child) then
					child:Destroy()
				end
			end
		end)
	end
	-- populate
	for _, inst in ipairs(inv.OrderedList or {}) do
		-- normalize ids to strings for reliable comparisons
		local instIdStr = tostring((inst and (inst.Id or inst.id)) or "")
		local mainIdStr = tostring(feedMainId or "")
		-- check equipped using string equality (defensive for mixed key types)
		local isEq = false
		if inv.EquippedOrder then
			for _, eid in ipairs(inv.EquippedOrder) do
				if tostring(eid) == instIdStr then isEq = true break end
			end
		end
		if inst and inst.Id and not isEq and instIdStr ~= mainIdStr then
			local curInst = inst
			local clone = tmpl:Clone()
			clone.Name = curInst.Id
			clone.Visible = true
			-- set level label
			local levelLabel = clone:FindFirstChild("Level", true)
			if levelLabel and levelLabel:IsA("TextLabel") then
				levelLabel.Text = string.format("Lv %d", curInst.Level or 1)
			end
			-- set icon image: prefer ImageButton named 'Icon_inv', then 'Icon', then any ImageLabel/ImageButton
			local iconImage = clone:FindFirstChild("Icon_inv") or clone:FindFirstChild("Icon") or clone:FindFirstChildWhichIsA("ImageLabel", true) or clone:FindFirstChildWhichIsA("ImageButton", true)
			if not iconImage then
				for _, d in ipairs(clone:GetDescendants()) do
					if (d:IsA("ImageButton") or d:IsA("ImageLabel")) and (d.Name == "Icon_inv" or d.Name == "Icon") then
						iconImage = d
						break
					end
				end
			end
			-- determine icon id (prefer instance.Catalog.icon_id, fallback to CharacterCatalog by template)
			local iconId = nil
			if curInst.Catalog and curInst.Catalog.icon_id then
				iconId = curInst.Catalog.icon_id
			elseif CharacterCatalog and CharacterCatalog.Get and curInst.TemplateName then
				local ok, cat = pcall(function() return CharacterCatalog:Get(curInst.TemplateName) end)
				if ok and cat and cat.icon_id then iconId = cat.icon_id end
			end
			if iconImage and iconId then
				pcall(function() iconImage.Image = iconId end)
			end

			-- Apply rarity gradient based on stars (prefers inst.Catalog.stars, then CharacterCatalog)
			local stars = nil
			if curInst.Catalog and curInst.Catalog.stars then
				stars = tonumber(curInst.Catalog.stars)
			elseif CharacterCatalog and CharacterCatalog.Get and curInst.TemplateName then
				local ok2, cat2 = pcall(function() return CharacterCatalog:Get(curInst.TemplateName) end)
				if ok2 and cat2 and cat2.stars then stars = tonumber(cat2.stars) end
			end
			if not stars then stars = 1 end
			pcall(function() ensureStarGradient(clone, stars) end)
			-- click toggles selection: prefer ImageButton named 'Icon_img' then 'Icon_inv' then 'Icon'
			local iconBtn = clone:FindFirstChild("Icon_img") or clone:FindFirstChild("Icon_inv") or clone:FindFirstChild("Icon") or clone:FindFirstChildWhichIsA("ImageButton", true) or clone:FindFirstChildWhichIsA("ImageLabel", true)
			if not iconBtn then
				for _, d in ipairs(clone:GetDescendants()) do
					if (d:IsA("ImageButton") or d:IsA("ImageLabel")) and (d.Name == "Icon_img" or d.Name == "Icon_inv" or d.Name == "Icon") then
						iconBtn = d
						break
					end
				end
			end
			local clickTarget = iconBtn or clone
			if clickTarget then
				clickTarget.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						-- Deselect always allowed
						if selectedFeeders[curInst.Id] then
							selectedFeeders[curInst.Id] = nil
							applySelectionOverlayToIcon(iconBtn or clone, false)
							updatePredictedAttribute(screenGui)
							return
						end
						-- Block selecting if main is already at hard cap
						if tonumber(feedInitLevel) and tonumber(feedInitLevel) >= HARD_CAP then
							print("[Feed][DEBUG] cannot select - main already at HARD_CAP")
							return
						end
						-- compute this feeder's feed value
						local feederValue = 0
						local instData = nil
						if lastInventoryMap and lastInventoryMap[curInst.Id] then instData = lastInventoryMap[curInst.Id] end
						if not instData and lastInventory and lastInventory.Instances and lastInventory.Instances[curInst.Id] then instData = lastInventory.Instances[curInst.Id] end
						if not instData then instData = curInst end
						feederValue = getFeedXPForInstance(instData)
						local currentPred = 0
						pcall(function() currentPred = tonumber(screenGui:GetAttribute("PredictedAddedXP")) or 0 end)
						local newTotal = (currentPred or 0) + (feederValue or 0)
						local finalLvl = computeFinalLevel(feedInitLevel, feedInitXP, newTotal)
						if finalLvl >= HARD_CAP then
							print("[Feed][DEBUG] selection blocked: selecting this feeder would reach HARD_CAP ->", finalLvl)
							return
						end
						-- otherwise allow selection
						selectedFeeders[curInst.Id] = true
						applySelectionOverlayToIcon(iconBtn or clone, true)
						updatePredictedAttribute(screenGui)
					end
				end)
			end
			clone.Parent = scrolling
		end
	end
	print("[Feed] renderFeedInventory done; items=", #inv.OrderedList)
end

local function applyMain(id, iconAsset, stars, level, xp)
	feedMainId = id
	feedInitLevel = tonumber(level) or 1
	feedInitXP = tonumber(xp) or 0
	pcall(function()
		local cur = nil
		if screenGui.GetAttribute then
			cur = screenGui:GetAttribute("FeedMain")
		end
		if cur ~= id then
			screenGui:SetAttribute("FeedMain", id)
		end
	end)
	if frame and frame:IsA("GuiObject") then
		frame.Visible = true
		-- Try to set the character icon if provided
		if iconAsset then
			local charIcon = frame:FindFirstChild("Char_icon", true)
			if charIcon and charIcon:IsA("ImageLabel") then
				pcall(function() charIcon.Image = iconAsset end)
			end
		end
		-- Apply rarity gradient in Frame -> Top -> Icon_f
		local top = frame:FindFirstChild("Top")
		local iconF = nil
		if top and top:IsA("GuiObject") then
			iconF = top:FindFirstChild("Icon_f") or top:FindFirstChildWhichIsA("Frame", true)
		end
		if not iconF then
			iconF = frame:FindFirstChild("Icon_f", true)
		end
		if iconF and iconF:IsA("GuiObject") then
			ensureStarGradient(iconF, stars)
		end
		-- Update level texts inside Top -> Level
		local function updateLevelTexts()
			local levelFrame = frame:FindFirstChild("Level", true) or top:FindFirstChild("Level", true)
			if levelFrame then
				local ini = levelFrame:FindFirstChild("Ini_Lvl", true)
				local fin = levelFrame:FindFirstChild("Final_Lvl", true)
				local displayIni = "Level " .. tostring(feedInitLevel or 0)
				if ini and (ini:IsA("TextLabel") or ini:IsA("TextButton") or ini:IsA("TextBox")) then
					pcall(function() ini.Text = displayIni end)
				end
				-- Final level: read predicted added XP attribute
				local predictedAdded = 0
				pcall(function()
					if screenGui.GetAttribute then
						predictedAdded = tonumber(screenGui:GetAttribute("PredictedAddedXP")) or 0
					end
				end)
				local finalLevel = computeFinalLevel(feedInitLevel, feedInitXP, predictedAdded)
				local displayFin = "Level " .. tostring(finalLevel or feedInitLevel or 0)
				if fin and (fin:IsA("TextLabel") or fin:IsA("TextButton") or fin:IsA("TextBox")) then
					pcall(function() fin.Text = displayFin end)
				end

				-- Update XP text (current or predicted after feeding) / required for next level
				local xpLabel = nil
				-- Prefer explicit path: Top -> Frame -> Xp_lvl, otherwise search for descendant named Xp_lvl
				if top then
					local topFrame = top:FindFirstChild("Frame") or top:FindFirstChildWhichIsA("Frame", true)
					if topFrame then xpLabel = topFrame:FindFirstChild("Xp_lvl") or topFrame:FindFirstChildWhichIsA("TextLabel", true) end
				end
				if not xpLabel then
					for _, d in ipairs(frame:GetDescendants()) do
						if d.Name == "Xp_lvl" and d:IsA("TextLabel") then xpLabel = d break end
					end
				end
				local curXP = tonumber(feedInitXP) or 0
				local added = tonumber(predictedAdded) or 0
				-- simulate post-feed leveling to get final level, remaining XP towards next level, and that requirement
				local function simulateProgress(level, xp, add)
					level = tonumber(level) or 1
					xp = tonumber(xp) or 0
					add = tonumber(add) or 0
					xp = xp + add
					local curLevel = level
					while curLevel < HARD_CAP do
						local need = XPRequired(curLevel)
						if need <= 0 then break end
						if xp >= need then
							xp = xp - need
							curLevel = curLevel + 1
						else
							break
						end
					end
					local nextReq = XPRequired(curLevel)
					return curLevel, xp, nextReq
				end
				local finalLevel, remainingXP, nextReq = simulateProgress(feedInitLevel, curXP, added)
				-- Update XP label to show remainingXP/nextReq (predicted post-feed)
				if xpLabel and xpLabel:IsA("TextLabel") then
					pcall(function()
						xpLabel.Text = string.format("%d/%d", remainingXP, nextReq > 0 and nextReq or 0)
					end)
				end

				-- Update progress bars (Bot and xp_bar) to match fraction after feed
				local fraction = 1
				if nextReq and nextReq > 0 then
					fraction = math.clamp(remainingXP / nextReq, 0, 1)
				else
					fraction = 1
				end
				print("[Feed][DEBUG] simulate -> initLvl=", tostring(feedInitLevel), " initXP=", tostring(feedInitXP), " predAdded=", tostring(predictedAdded), " finalLvl=", tostring(finalLevel), " remaining=", tostring(remainingXP), " nextReq=", tostring(nextReq), " fraction=", tostring(fraction))
				-- Find xp_bar and Bot frames under Top -> Frame
				local xpBar = nil
				local botBar = nil
				if top then
					local topFrame = top:FindFirstChild("Frame") or top:FindFirstChildWhichIsA("Frame", true)
					if topFrame then
						xpBar = topFrame:FindFirstChild("xp_bar") or topFrame:FindFirstChildWhichIsA("Frame", true)
						botBar = topFrame:FindFirstChild("Bot") or topFrame:FindFirstChildWhichIsA("Frame", true)
					end
				end
				-- More robust fallback: search descendants named xp_bar / Bot
				if not xpBar then
					for _, d in ipairs(frame:GetDescendants()) do
						if d.Name == "xp_bar" and d:IsA("Frame") then xpBar = d break end
					end
				end
				if not botBar then
					for _, d in ipairs(frame:GetDescendants()) do
						if d.Name == "Bot" and d:IsA("Frame") then botBar = d break end
					end
				end
				-- Apply size (keep Y size unchanged)
				if xpBar and xpBar:IsA("Frame") then
					local yScale = xpBar.Size.Y.Scale
					local yOffset = xpBar.Size.Y.Offset
					xpBar.Size = UDim2.new(fraction, 0, yScale, yOffset)
				end
				if botBar and botBar:IsA("Frame") then
					local yScale = botBar.Size.Y.Scale
					local yOffset = botBar.Size.Y.Offset
					botBar.Size = UDim2.new(fraction, 0, yScale, yOffset)
				end
			end
		end
		updateLevelTexts()
		-- populate feed inventory when opening
		repeat
			-- small delay to ensure UI hierarchy is ready
			local ok, err = pcall(renderFeedInventory)
			if not ok then warn("[Feed] renderFeedInventory error:", err) end
			break
		until true
		-- Listen for PredictedAddedXP changes to update Final_Lvl dynamically
		if screenGui.GetAttributeChangedSignal then
			screenGui:GetAttributeChangedSignal("PredictedAddedXP"):Connect(function()
					local val = nil
					pcall(function() val = tonumber(screenGui:GetAttribute("PredictedAddedXP")) end)
					print("[Feed][DEBUG] PredictedAddedXP changed ->", val)
					if feedMainId then
						pcall(function()
							print("[Feed][DEBUG] calling updateLevelTexts")
							updateLevelTexts()
						end)
					end
				end)
		end
	end
	print("[Feed] Set main id ->", tostring(id), "icon=", tostring(iconAsset), "stars=", tostring(stars))
end

setMainEvent.Event:Connect(function(id, iconAsset, stars, level)
	if not id then return end
	applyMain(id, iconAsset, stars, level)
end)

-- Fallback: listen to attribute changes so older callers that set FeedMain attribute still work
if screenGui.GetAttributeChangedSignal then
	screenGui:GetAttributeChangedSignal("FeedMain"):Connect(function()
		local id = screenGui:GetAttribute("FeedMain")
		-- Ignore attribute notifications that match the already-applied main id
		if id and id ~= feedMainId then
			applyMain(id)
		end
	end)
end

-- Optional: react to explicit Show/Hide attributes
if screenGui.GetAttributeChangedSignal then
	screenGui:GetAttributeChangedSignal("Show"):Connect(function()
		if screenGui:GetAttribute("Show") and frame and frame:IsA("GuiObject") then
			frame.Visible = true
		end
	end)
	screenGui:GetAttributeChangedSignal("Hide"):Connect(function()
		if screenGui:GetAttribute("Hide") and frame and frame:IsA("GuiObject") then
			frame.Visible = false
		end
	end)
end

-- Hook Exit/Close button inside the feed Frame so clicking it closes the UI
pcall(function()
	if frame and frame:IsA("GuiObject") then
		local exitBtn = frame:FindFirstChild("Exit") or frame:FindFirstChild("Exit_b")
		if not exitBtn then
			for _, c in ipairs(frame:GetDescendants()) do
				if c:IsA("GuiButton") then
					local name = (c.Name or ""):lower()
					if string.find(name, "exit") or string.find(name, "close") then
						exitBtn = c
						break
					end
				end
			end
		end
		if exitBtn and exitBtn:IsA("GuiButton") then
			exitBtn.MouseButton1Click:Connect(function()
				if frame and frame:IsA("GuiObject") then
					frame.Visible = false
				end
				feedMainId = nil
				pcall(function()
					if screenGui and screenGui.SetAttribute then
						screenGui:SetAttribute("Hide", true)
						screenGui:SetAttribute("Show", false)
					end
					if script and script.SetAttribute then
						script:SetAttribute("Hide", true)
						script:SetAttribute("Show", false)
					end
				end)
				print("[Feed] Exit clicked - feed UI hidden")
			end)
		end
	end
end)

print("[Feed] LocalScript initialized")

-- Wire up RequestFeed remote and the Feed_confirm button
pcall(function()
	local RequestFeedRE = Remotes:FindFirstChild("RequestFeed")
	local FeedResultRE = Remotes:FindFirstChild("FeedResult")
	if not RequestFeedRE or not FeedResultRE then
		print("[Feed][WARN] RequestFeed or FeedResult remotes not found")
		return
	end
	-- (no snapshot-wait handshake — apply authoritative snapshots when received)

	-- Handle ProfileUpdated full snapshot to apply authoritative data
	if ProfileUpdatedRE and ProfileUpdatedRE:IsA("RemoteEvent") then
		ProfileUpdatedRE.OnClientEvent:Connect(function(payload)
			-- payload.full is the server snapshot (ProfileService:BuildClientSnapshot)
			if not payload or not payload.full then return end
			pcall(function() print("[Feed][DEBUG] ProfileUpdated(full) received") end)
			-- Preserve current main id and update its level/xp from snapshot
			if feedMainId and type(feedMainId) == "string" then
				local snap = payload.full
				if snap and snap.Characters and snap.Characters.Instances then
					for _, entry in ipairs(snap.Characters.Instances) do
						if entry and tostring(entry.Id) == tostring(feedMainId) then
							-- Update local main level/xp
							feedInitLevel = tonumber(entry.Level) or feedInitLevel
							feedInitXP = tonumber(entry.XP) or feedInitXP
							-- Apply main visuals (icon/stars unknown here)
							pcall(function() applyMain(feedMainId, nil, nil, feedInitLevel, feedInitXP) end)
							break
						end
					end
				end
			end

			-- Clear selection and predicted XP, repopulate inventory from server
			selectedFeeders = {}
			pcall(function() if screenGui and screenGui.SetAttribute then screenGui:SetAttribute("PredictedAddedXP", 0) end end)
			pcall(function() renderFeedInventory() end)

			-- Ask Chars UI to refresh (set attribute on player's Chars ScreenGui)
			pcall(function()
				local pg = player and player:FindFirstChild("PlayerGui") or Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
				if pg then
					local charsGui = pg:FindFirstChild("Chars") or pg:FindFirstChildWhichIsA("ScreenGui", true)
					if charsGui and charsGui.SetAttribute then
						charsGui:SetAttribute("Refresh", true)
						print("[Feed][DEBUG] Requested Chars refresh via attribute (from ProfileUpdated)")
					end
				end
			end)

			-- finished applying authoritative snapshot
		end)
	end

	-- Ensure we only connect once to FeedResult
	if not script:GetAttribute("FeedResultConnected") then
		FeedResultRE.OnClientEvent:Connect(function(result)
			pcall(function()
				print("[Feed][DEBUG] FeedResult received ->", tostring(result and result.Success), tostring(result and result.Message))
			end)
			if not result then return end
			-- Proceed to handle FeedResult immediately
			if result.Success then
				-- Update main info and refresh inventory
				if result.Main and result.Main.Id then
					-- update applied main level/xp
					feedInitLevel = tonumber(result.Main.Level) or feedInitLevel
					feedInitXP = tonumber(result.Main.XP) or feedInitXP
					-- call applyMain to refresh UI visuals (pass level/xp to avoid resetting)
					pcall(function()
						applyMain(result.Main.Id, nil, nil, result.Main.Level, result.Main.XP)
					end)
					-- ensure the feed Frame stays hidden after server response
					pcall(function()
						if frame and frame:IsA("GuiObject") then frame.Visible = false end
						local f2 = screenGui:FindFirstChild("Feed_frame") or (frame and frame:FindFirstChild("Feed_frame", true))
						if f2 and f2:IsA("GuiObject") then f2.Visible = false end
					end)
				end
				-- Clear selection and predicted XP
				selectedFeeders = {}
				pcall(function() if screenGui and screenGui.SetAttribute then screenGui:SetAttribute("PredictedAddedXP", 0) end end)
				-- Refresh inventory UI
				pcall(function() renderFeedInventory() end)
				-- Ask Chars UI to refresh (set attribute on player's Chars ScreenGui)
				pcall(function()
					local pg = player and player:FindFirstChild("PlayerGui") or Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
					if pg then
						local charsGui = pg:FindFirstChild("Chars") or pg:FindFirstChildWhichIsA("ScreenGui", true)
						if charsGui and charsGui.SetAttribute then
							charsGui:SetAttribute("Refresh", true)
							print("[Feed][DEBUG] Requested Chars refresh via attribute")
						end
					end
				end)
				-- Hide Feed_frame (confirmation done)
				pcall(function()
					local f = screenGui:FindFirstChild("Feed_frame") or (frame and frame:FindFirstChild("Feed_frame", true))
					if f and f:IsA("GuiObject") then f.Visible = false end
				end)
			else
				warn("[Feed] server rejected feed request ->", tostring(result.Message))
			end
		end)
		script:SetAttribute("FeedResultConnected", true)
	end

	-- Find confirm button and wire click
	local confirmBtn = nil
	confirmBtn = screenGui:FindFirstChild("Feed_frame") and screenGui.Feed_frame:FindFirstChild("Feed_confirm")
	if not confirmBtn and frame then
		confirmBtn = frame:FindFirstChild("Feed_confirm", true)
	end
	if not confirmBtn then
		-- search descendants as last resort
		for _, d in ipairs(screenGui:GetDescendants()) do
			if d.Name == "Feed_confirm" and d:IsA("GuiButton") then confirmBtn = d break end
		end
	end
	if confirmBtn and confirmBtn:IsA("GuiButton") then
		confirmBtn.MouseButton1Click:Connect(function()
				-- resolve and validate selected feeders against latest inventory before sending
				local feeders = {}
				local missing = {}
				for id,_ in pairs(selectedFeeders) do
					local resolved = nil
					-- prefer lastInventoryMap (built from OrderedList)
					if lastInventoryMap and lastInventoryMap[id] then
						resolved = lastInventoryMap[id]
					end
					-- fallback to Instances map
					if not resolved and lastInventory and lastInventory.Instances then
						resolved = lastInventory.Instances[id] or nil
						if not resolved then
							-- maybe Instances is an array; search by Id field
							for _, v in pairs(lastInventory.Instances) do
								if v and (v.Id == id or v.id == id) then resolved = v break end
							end
						end
					end
					if resolved and (resolved.Id or resolved.id) then
						table.insert(feeders, tostring(resolved.Id or resolved.id))
					else
						table.insert(missing, tostring(id))
					end
				end
				if #feeders == 0 then
					print("[Feed] No feeders selected or none resolved in inventory")
					-- refresh to recover
					pcall(function() renderFeedInventory() end)
					return
				end
				if #missing > 0 then
					warn("[Feed] Some selected feeders could not be resolved: ", table.concat(missing, ","))
					-- refresh inventory to reflect server state and abort
					pcall(function() renderFeedInventory() end)
					return
				end
				if not feedMainId then
					warn("[Feed] No main selected for feeding")
					return
				end
				-- fire request
				pcall(function()
					print("[Feed] Requesting feed -> main=", tostring(feedMainId), "count=", #feeders)
					RequestFeedRE:FireServer(feedMainId, feeders)
				end)
				-- hide feed UI frame to indicate action taken (do not disable ScreenGui)
				pcall(function()
					if frame and frame:IsA("GuiObject") then frame.Visible = false end
					local f = screenGui:FindFirstChild("Feed_frame") or (frame and frame:FindFirstChild("Feed_frame", true))
					if f and f:IsA("GuiObject") then f.Visible = false end
				end)
		end)
	else
		print("[Feed][WARN] Feed_confirm button not found for hookup")
	end
end)