-- Client: Open the Story UI when the server signals (mirrors Summon behavior)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local openRemote = remotes:FindFirstChild("Open_Story") or remotes:WaitForChild("Open_Story")
local StoryClientReadyRE = remotes:FindFirstChild("StoryClientReady") or remotes:WaitForChild("StoryClientReady")
local openStoryFunction = remotes:FindFirstChild("OpenStoryFunction") or remotes:WaitForChild("OpenStoryFunction")

-- Find the main Story container (be lenient: "All", "Main", or any Frame)
local root = script.Parent -- ScreenGui
local container = root:FindFirstChild("All") or root:FindFirstChild("All", true)
container = container or root:FindFirstChild("Main") or root:FindFirstChild("Main", true)
container = container or root:FindFirstChild("Frame") or root:FindFirstChild("Frame", true)
if not container then
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Frame") then
			container = d
			break
		end
	end
end

-- Start hidden
local screenGuiFallback = false
if container then
	pcall(function()
		container.Visible = false
		if container:IsA("Frame") then
			container.Position = UDim2.new(0, 0, -1, 0)
		end
	end)
else
	-- No container found: use ScreenGui Enabled as fallback
	screenGuiFallback = true
	pcall(function()
		if root:IsA("ScreenGui") then
			root.Enabled = false
		end
	end)
	warn("[StoryUI] Container (Frame) não encontrado; usando fallback de ScreenGui.Enabled")
end

local isOpen = false
local isAnimating = false
local T_POS = 0.45
local T_FADE = 0.25
local T_SCALE = 0.30

-- Icons for currency
local GEM_ICON = "rbxassetid://101285032767311"
local COIN_ICON = "rbxassetid://84965857011165"

-- Lazy cache for item icons from Shared/Drops/*/Items.lua
local dropIconByIdCache = nil
local dropRarityByIdCache = nil
local function resolveItemIcon(itemId)
	if not itemId or itemId == "" then return "rbxassetid://0" end
	if not dropIconByIdCache then
		dropIconByIdCache = {}
		dropRarityByIdCache = {}
		local ok = pcall(function()
			local Shared = ReplicatedStorage:WaitForChild("Shared")
			local Drops = Shared:FindFirstChild("Drops")
			if Drops then
				for _, cat in ipairs(Drops:GetChildren()) do
					local itemsMod = cat:FindFirstChild("Items")
					if itemsMod and itemsMod:IsA("ModuleScript") then
						local ok2, itemsTbl = pcall(require, itemsMod)
						if ok2 and type(itemsTbl) == "table" then
							for id, def in pairs(itemsTbl) do
								if type(def) == "table" and type(def.Icon) == "string" then
									dropIconByIdCache[id] = def.Icon
									dropRarityByIdCache[id] = (type(def.Rarity) == "string" and def.Rarity) or nil
								end
							end
						end
					end
				end
			end
		end)
		if not ok then
			-- ignore errors, leave cache possibly partial
		end
	end
	return dropIconByIdCache[itemId] or "rbxassetid://0"
end

local function resolveItemRarity(itemId)
	if not itemId or itemId == "" then return nil end
	if not dropRarityByIdCache then
		-- ensure cache built via resolveItemIcon
		resolveItemIcon(itemId)
	end
	return dropRarityByIdCache and dropRarityByIdCache[itemId] or nil
end

-- Rarity -> gradient mapping (Portuguese keys supported)
local rarityGradients = {
	comum = ColorSequence.new(Color3.fromRGB(200,200,200), Color3.fromRGB(240,240,240)),
	raro = ColorSequence.new(Color3.fromRGB(70,140,255), Color3.fromRGB(150,200,255)),
	epico = ColorSequence.new(Color3.fromRGB(170,90,255), Color3.fromRGB(230,160,255)),
	lendario = ColorSequence.new(Color3.fromRGB(255,185,55), Color3.fromRGB(255,225,130)),
	mitico = ColorSequence.new(Color3.fromRGB(255,65,90), Color3.fromRGB(255,150,170)),
}

local function toKey(str)
	if type(str) ~= "string" then return nil end
	local s = string.lower(str)
	-- also map english if used somewhere
	if s == "common" then return "comum" end
	if s == "rare" then return "raro" end
	if s == "epic" then return "epico" end
	if s == "legendary" then return "lendario" end
	if s == "mythic" then return "mitico" end
	return s
end

local GOLD_COLOR = Color3.fromRGB(255, 208, 77)
local BLUE_COLOR = Color3.fromRGB(80, 150, 255)

local function setSolidBG(bg: Instance, color: Color3)
	if not (bg and bg:IsA("GuiObject")) then return end
	-- Remove/disable gradient if present
	local grad = bg:FindFirstChildOfClass("UIGradient")
	if grad then grad:Destroy() end
	-- Make sure background is visible and tint applied
	pcall(function()
		if bg:IsA("ImageLabel") or bg:IsA("ImageButton") then
			-- Hide the image to avoid it overriding the solid color
			bg.ImageTransparency = 1
		end
		bg.BackgroundColor3 = color
		bg.BackgroundTransparency = 0
	end)
end

local function setGradientBG(bg: Instance, colorSeq: ColorSequence)
	if not (bg and bg:IsA("GuiObject")) then return end
	pcall(function()
		if bg:IsA("ImageLabel") or bg:IsA("ImageButton") then
			bg.ImageTransparency = 1
		end
		bg.BackgroundTransparency = 0
		local grad = bg:FindFirstChild("R_Grad")
		if not (grad and grad:IsA("UIGradient")) then
			grad = bg:FindFirstChildOfClass("UIGradient")
		end
		if not grad then
			grad = Instance.new("UIGradient")
			grad.Name = "R_Grad"
			grad.Parent = bg
		end
		grad.Rotation = -90
		grad.Color = colorSeq
	end)
end

local function resolveBGFrame(cellFrame: Instance)
	if not cellFrame or not cellFrame:IsA("GuiObject") then return nil end
	-- If there's a child UIGradient (possibly named R_Grad), use its parent as the target frame
	local grad = cellFrame:FindFirstChild("R_Grad")
	if grad and grad:IsA("UIGradient") then return cellFrame end
	local anyGrad = cellFrame:FindFirstChildOfClass("UIGradient")
	if anyGrad then return cellFrame end
	-- If there is a child named R_Grad that is itself a Frame/Image, use that
	local rg = cellFrame:FindFirstChild("R_Grad")
	if rg and rg:IsA("GuiObject") then return rg end
	return cellFrame
end

-- Optional visual helpers
local canvasGroup = nil
if container then
	canvasGroup = container:FindFirstChildOfClass("CanvasGroup") or container:FindFirstChild("CanvasGroup", true)
	if canvasGroup and typeof(canvasGroup.GroupTransparency) == "number" then
		pcall(function() canvasGroup.GroupTransparency = 1 end) -- start hidden
	end
	if not container:FindFirstChildOfClass("UIScale") then
		local uiScale = Instance.new("UIScale")
		uiScale.Scale = 0.98
		uiScale.Parent = container
	end
end

local function openStoryUI()
	if isOpen or isAnimating then return end
	isAnimating = true
	isOpen = true
	if screenGuiFallback then
		pcall(function()
			if root:IsA("ScreenGui") then root.Enabled = true end
		end)
		return
	end
	if not container then return end
	pcall(function()
		container.Visible = true

		-- Build map list into the ScrollingFrame
		local function populateStoryMaps()
			local ok, err = pcall(function()
				local stagesRoot = container:FindFirstChild("Stages", true) or container:FindFirstChild("Levels", true)
				if not stagesRoot then return end
				local scrolling = stagesRoot:FindFirstChild("ScrollingFrame") or stagesRoot:FindFirstChildWhichIsA("ScrollingFrame")
				if not scrolling then return end

				-- Find a template frame (prefer one named 'Slots')
				local template = scrolling:FindFirstChild("Slots")
				if not template then
					for _, ch in ipairs(scrolling:GetChildren()) do
						if ch:IsA("Frame") then template = ch break end
					end
				end
				if not template or not template:IsA("Frame") then return end

				-- Clear previous generated entries (keep the template)
				for _, ch in ipairs(scrolling:GetChildren()) do
					if ch:IsA("Frame") and ch ~= template then ch:Destroy() end
				end

				-- Ensure template stays hidden
				template.Visible = false

				-- Load all maps from Shared/Maps/Story
				local Shared = ReplicatedStorage:WaitForChild("Shared")
				local Maps = Shared:WaitForChild("Maps")
				local Story = Maps:WaitForChild("Story")
				local mapsList = {}
				for _, folder in ipairs(Story:GetChildren()) do
					if folder:IsA("Folder") then
						local mod = folder:FindFirstChild("Map")
						if mod and mod:IsA("ModuleScript") then
							local okMap, map = pcall(function() return require(mod) end)
							if okMap and type(map) == "table" then
								table.insert(mapsList, map)
							end
						end
					end
				end

				-- Sort by SortOrder (if provided), then by DisplayName/Id
				table.sort(mapsList, function(a,b)
					local ao = tonumber(a.SortOrder) or math.huge
					local bo = tonumber(b.SortOrder) or math.huge
					if ao ~= bo then return ao < bo end
					local ad = tostring(a.DisplayName or a.Id or "")
					local bd = tostring(b.DisplayName or b.Id or "")
					return ad:lower() < bd:lower()
				end)

				-- Ask server for Story progress to decide what is unlocked
				local progress = nil
				local getRF = remotes:FindFirstChild("GetStoryProgress")
				if getRF and getRF.InvokeServer then
					local pok, pres = pcall(function()
						return getRF:InvokeServer()
					end)
					if pok and type(pres) == "table" then
						progress = pres
					end
				end
				local firstId = mapsList[1] and (mapsList[1].Id or mapsList[1].DisplayName)
				local function isMapUnlocked(map)
					local id = tostring(map.Id or map.DisplayName or "")
					if progress and progress.Maps and progress.Maps[id] then
						local maxU = tonumber(progress.Maps[id].MaxUnlockedLevel) or 0
						return maxU >= 1, maxU
					end
					if progress and progress.FirstMapId and tostring(progress.FirstMapId) == id then
						return true, 1
					end
					-- Fallback if no progress yet: treat the very first map as unlocked level 1
					if not progress and firstId and id == firstId then
						return true, 1
					end
					return false, 0
				end

				-- Before creating entries: ensure 'Levels/Selected' starts hidden
				do
					local levelsRoot = container:FindFirstChild("Levels", true)
					if levelsRoot and levelsRoot:IsA("Frame") then
						local selected = levelsRoot:FindFirstChild("Selected")
						if selected and selected:IsA("Frame") then
							selected.Visible = false
							-- Also ensure drops start hidden until a level is selected
							local drops = selected:FindFirstChild("drops")
							if drops and drops:IsA("GuiObject") then
								drops.Visible = false
							end
						end
					end
				end

				-- Create entries (only for unlocked maps)
				for _, map in ipairs(mapsList) do
					local unlocked, maxUnlocked = isMapUnlocked(map)
					if not unlocked then
						-- Skip locked maps entirely
						continue
					end
					local item = template:Clone()
					item.Name = "Slot_" .. tostring(map.Id or map.DisplayName or "map")
					item.Visible = true
					-- Fill visuals
					local thumb = item:FindFirstChild("Stage_Mini", true)
					if thumb and (thumb:IsA("ImageLabel") or thumb:IsA("ImageButton")) then
						thumb.Image = tostring(map.PreviewImage or "rbxassetid://0")
						-- On click, show only Levels.Selected (not the whole Levels) and update Stage_image
						if thumb:IsA("ImageButton") then
							thumb.MouseButton1Click:Connect(function()
								local levelsRoot = container:FindFirstChild("Levels", true)
								if not levelsRoot then return end
								local selected = levelsRoot:FindFirstChild("Selected")
								if selected and selected:IsA("Frame") then
									selected.Visible = true
									-- Hide drops until a level is selected
									local drops = selected:FindFirstChild("drops")
									if drops and drops:IsA("GuiObject") then
										drops.Visible = false
									end
									-- Also hide Play until a level is selected
									local playFrame = selected:FindFirstChild("Play")
									if playFrame and playFrame:IsA("GuiObject") then
										playFrame.Visible = false
									end
								end
								-- Update Stage_image (prefer inside Selected; fallback to Levels)
								local stageImg = (selected and selected:FindFirstChild("Stage_image", true)) or levelsRoot:FindFirstChild("Stage_image", true)
								if stageImg and stageImg:IsA("ImageLabel") then
									stageImg.Image = tostring(map.PreviewImage or "rbxassetid://0")
								end

								-- Bind the Selected frame to this map id (used by level handlers to ignore stale events)
								local mapIdKey_local = tostring(map.Id or map.DisplayName or "")
								if selected and selected.SetAttribute then
									selected:SetAttribute("__BindMapId", mapIdKey_local)
								end

								-- Show only unlocked levels (Lvl1..LvlN)
								local maxU = tonumber(maxUnlocked) or 0
								if selected and selected:IsA("Frame") then
									-- Rebind level buttons fresh to avoid stale handlers from previous selections
									for i = 1, 3 do
										local node = selected:FindFirstChild("Lvl" .. i)
										if node and node:IsA("GuiObject") then
											-- Remove old clickable children (if any) by cloning a fresh node
											local parent = node.Parent
											local newNode = node:Clone()
											newNode.Name = node.Name
											-- Preserve visibility based on unlock
											newNode.Visible = (i <= maxU)
											-- Replace old node with new clone to drop old connections
											node:Destroy()
											newNode.Parent = parent
											-- small optimization: prevent redundant hooks for hidden nodes
										end
									end
									-- Bind clicks on the inner ImageButton/TextButton inside each visible Lvl frame to reveal drops
									local function findClickable(n)
										if not n then return nil end
										return n:FindFirstChildWhichIsA("ImageButton", true) or n:FindFirstChildWhichIsA("TextButton", true)
									end
									local function populateDrops(selectedFrame, mapTbl, levelIdx, storyProgress)
										if not selectedFrame then return end
										local dropsRoot = selectedFrame:FindFirstChild("drops")
										if not (dropsRoot and dropsRoot:IsA("Frame")) then
											return
										end
										-- find a template frame (child with DropIcon & Amount)
										local template
										for _, ch in ipairs(dropsRoot:GetChildren()) do
											if ch:IsA("Frame") then
												local hasIcon = ch:FindFirstChild("DropIcon", true)
												local hasAmt = ch:FindFirstChild("Amount", true)
												if hasIcon and hasAmt then
													template = ch
													break
												end
											end
										end
										if not template then
											return
										end
										-- clear previous clones, keep grid/padding and template
										for _, ch in ipairs(dropsRoot:GetChildren()) do
											if ch ~= template and ch:IsA("Frame") then
												ch:Destroy()
											end
										end
										template.Visible = false

										local function pushEntry(list, kind, amount, meta)
											if not amount or amount <= 0 then return end
											list[#list+1] = { kind = kind, amount = amount, meta = meta }
										end

										local entries = {}
										local drops = mapTbl and mapTbl.Drops or nil
										if drops then
											local rep = drops.Repeat or {}
											local fc = drops.FirstClear or {}
											-- determine if first-clear rewards should apply for this selection
											local firstApplies = false
											local mapId = tostring(mapTbl.Id or mapTbl.DisplayName or "")
											local prog = storyProgress and storyProgress.Maps and storyProgress.Maps[mapId]
											local lvCompleted = (prog and prog.LevelsCompleted) or {}
											local anyCompleted = false
											for k, v in pairs(lvCompleted) do if v == true then anyCompleted = true break end end
											if fc.PerLevel == true then
												firstApplies = not (lvCompleted[levelIdx] == true)
											else
												firstApplies = not anyCompleted
											end

											local gemsAmt = tonumber((firstApplies and fc.Gems) or rep.Gems) or 0
											local goldAmt = tonumber((firstApplies and (fc.Gold or fc.Coins)) or (rep.Gold or rep.Coins)) or 0
											-- order rule: gems then coins, then others
											pushEntry(entries, "gems", gemsAmt)
											pushEntry(entries, "coins", goldAmt)
											local items = drops.GuaranteedItemsPerRun or {}
											for _, it in ipairs(items) do
												local qty = tonumber(it.Quantity) or 0
												pushEntry(entries, "item", qty, { id = tostring(it.Id or "") })
											end
										end

										-- create frames for entries
										for _, e in ipairs(entries) do
											local f = template:Clone()
											f.Visible = true
											local icon = f:FindFirstChild("DropIcon", true)
											local amountLabel = f:FindFirstChild("Amount", true)
											local bg = resolveBGFrame(f)
											if icon and icon:IsA("ImageLabel") then
												if e.kind == "gems" then
													icon.Image = GEM_ICON
													-- solid blue background
													setSolidBG(bg, BLUE_COLOR)
												elseif e.kind == "coins" then
													icon.Image = COIN_ICON
													-- solid gold background
													setSolidBG(bg, GOLD_COLOR)
												else
													icon.Image = resolveItemIcon(e.meta and e.meta.id)
													-- gradient by rarity
													local rarity = toKey(resolveItemRarity(e.meta and e.meta.id) or "comum")
													local seq = rarityGradients[rarity] or rarityGradients["comum"]
													setGradientBG(bg, seq)
												end
											end
											if amountLabel and amountLabel:IsA("TextLabel") then
												amountLabel.Text = tostring(e.amount)
											end
											f.Parent = dropsRoot
										end
										-- toggle visibility only if we have entries
										dropsRoot.Visible = (#entries > 0)
									end
									local mapIdKey = tostring(map.Id or map.DisplayName or "")
									for i = 1, maxU do
										local lvlFrame = selected:FindFirstChild("Lvl" .. i)
										if lvlFrame then
											local btn = findClickable(lvlFrame)
											if btn then
												btn.MouseButton1Click:Connect(function()
													-- Only proceed if this Selected frame is still bound to this map (avoid stale handlers)
													if selected and selected.GetAttribute then
														local bound = selected:GetAttribute("__BindMapId")
														if tostring(bound) ~= tostring(mapIdKey) then return end
													end
													local d = selected:FindFirstChild("drops")
													if d and d:IsA("GuiObject") then
														d.Visible = true
														populateDrops(selected, map, i, progress)
													end
													-- Store current selection on Selected attributes
													if selected and selected.SetAttribute then
														selected:SetAttribute("MapId", mapIdKey)
														selected:SetAttribute("Level", i)
													end
													-- Reveal Play frame now that a level is selected
													local playFrame2 = selected:FindFirstChild("Play")
													if playFrame2 and playFrame2:IsA("GuiObject") then
														playFrame2.Visible = true
														-- Hook Play button once (inner ImageButton/TextButton if present)
														local playBtn = playFrame2:FindFirstChildWhichIsA("ImageButton", true) or playFrame2:FindFirstChildWhichIsA("TextButton", true)
														if playBtn and not playBtn:GetAttribute("__Hooked") then
															playBtn:SetAttribute("__Hooked", true)
															playBtn.MouseButton1Click:Connect(function()
																local sid = selected:GetAttribute("MapId")
																local lvl = selected:GetAttribute("Level")
																if not sid or not lvl then return end
																local startRE = remotes:FindFirstChild("StartStoryRun")
																if startRE and startRE.FireServer then
																	startRE:FireServer(sid, tonumber(lvl))
																end
															end)
														end
													end
												end)
											end
										end
									end
								end
							end)
						end
					end
					local nameLabel = item:FindFirstChild("Stage_Name", true)
					if nameLabel and nameLabel:IsA("TextLabel") then
						nameLabel.Text = tostring(map.DisplayName or map.Id or "?")
					end
					item.Parent = scrolling
				end
			end)
			if not ok then
				warn("[StoryUI] populateStoryMaps error:", tostring(err))
			end
		end
		populateStoryMaps()

		if container:IsA("Frame") then
			container.Position = UDim2.new(0, 0, -1, 0)
			local uiScale = container:FindFirstChildOfClass("UIScale")
			if uiScale then uiScale.Scale = 0.98 end
			if canvasGroup and typeof(canvasGroup.GroupTransparency) == "number" then
				canvasGroup.GroupTransparency = 1
				TweenService:Create(canvasGroup, TweenInfo.new(T_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 0 }):Play()
			end
			local posTween = TweenService:Create(container, TweenInfo.new(T_POS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(0, 0, 0, 0) })
			posTween:Play()
			if uiScale then
				TweenService:Create(uiScale, TweenInfo.new(T_SCALE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
			posTween.Completed:Connect(function()
				isAnimating = false
			end)
		end
	end)
end

local function closeStoryUI()
	if not isOpen or isAnimating then return end
	isAnimating = true
	if screenGuiFallback then
		pcall(function()
			if root:IsA("ScreenGui") then root.Enabled = false end
		end)
		isOpen = false
		isAnimating = false
		return
	end
	if not container then return end
	local posTween = TweenService:Create(container, TweenInfo.new(T_POS, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0, 0, -1, 0) })
	local fadeTween = nil
	if canvasGroup and typeof(canvasGroup.GroupTransparency) == "number" then
		fadeTween = TweenService:Create(canvasGroup, TweenInfo.new(T_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { GroupTransparency = 1 })
	end
	local scaleTween = nil
	local uiScale = container:FindFirstChildOfClass("UIScale")
	if uiScale then
		scaleTween = TweenService:Create(uiScale, TweenInfo.new(T_SCALE, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.98 })
	end
	if fadeTween then fadeTween:Play() end
	if scaleTween then scaleTween:Play() end
	posTween:Play()
	posTween.Completed:Connect(function()
		pcall(function() container.Visible = false end)
		isOpen = false
		isAnimating = false
	end)
end

-- Hook an exit button if present (case-insensitive, any depth)
local function hookExitButtons()
	if not container then return end
	-- Try common names directly first
	local candidates = {
		container:FindFirstChild("Exit", true),
		container:FindFirstChild("exit", true),
		container:FindFirstChild("Close", true),
		container:FindFirstChild("close", true),
	}
	-- Also scan descendants for any button whose name contains "exit" or "close"
	for _, d in ipairs(container:GetDescendants()) do
		if d and (d:IsA("ImageButton") or d:IsA("TextButton")) then
			local lname = string.lower(d.Name or "")
			if string.find(lname, "exit") or string.find(lname, "close") then
				table.insert(candidates, d)
			end
		end
	end
	local connected = 0
	for _, btn in ipairs(candidates) do
		if btn and (btn:IsA("ImageButton") or btn:IsA("TextButton")) then
			btn.MouseButton1Click:Connect(closeStoryUI)
			connected += 1
		end
	end
	if connected == 0 then
		-- Fallback: try to wrap an ImageLabel or Frame named Exit/Close with a transparent clickable overlay
		local anchor = container:FindFirstChild("Exit", true) or container:FindFirstChild("exit", true)
			or container:FindFirstChild("Close", true) or container:FindFirstChild("close", true)
		if anchor and (anchor:IsA("ImageLabel") or anchor:IsA("Frame")) then
			local overlay = Instance.new("TextButton")
			overlay.Name = "__ExitOverlay"
			overlay.BackgroundTransparency = 1
			overlay.Text = ""
			overlay.Size = UDim2.new(1, 0, 1, 0)
			overlay.Position = UDim2.new(0, 0, 0, 0)
			overlay.ZIndex = (anchor.ZIndex or 1) + 1
			overlay.Parent = anchor
			overlay.MouseButton1Click:Connect(closeStoryUI)
			connected = 1
			print("[StoryUI] Exit overlay criado sobre:", anchor:GetFullName())
		else
			warn("[StoryUI] Nenhum botão de Exit/Close encontrado para conectar.")
		end
	end
end
hookExitButtons()

-- Handshake: client signals ready; server will fire when touching Portal
local receivedEvent = false
local function keepReady()
	while not receivedEvent do
		StoryClientReadyRE:FireServer()
		task.wait(0.5)
	end
end
task.spawn(keepReady)

openRemote.OnClientEvent:Connect(function(payload)
	if payload == "Story" then
		receivedEvent = true
		openStoryUI()
	end
end)

openStoryFunction.OnClientInvoke = function(payload)
	if payload == "Story" then
		openStoryUI()
		return true
	end
	return false
end

