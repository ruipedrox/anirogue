-- Roll UI animator
-- Plays a per-character summon reveal: the 'Back' frame descends while
-- squashing on X to simulate a Z-axis flip, then hides and shows '1_Sum'
-- with the summoned character image. Supports a Skip button to reveal
-- immediately.

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")

local root = script.Parent
local frame = root:FindFirstChild("Frame") or root:WaitForChild("Frame")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Character catalog used to resolve template/id -> icon image
local CharacterCatalog
local okCat, cat = pcall(function()
	return require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("CharacterCatalog"))
end)
if okCat and cat then CharacterCatalog = cat end

local SummonGrantedRE = remotes:FindFirstChild("SummonGranted") or remotes:FindFirstChild("SummonGrantedRE")
local isPlaying = false

-- Helper to find descendant by class
local function findDescendantOfClass(parent, className)
	for _, v in ipairs(parent:GetDescendants()) do
		if v.ClassName == className then return v end
	end
	return nil
end

-- UI parts (guarded)
local part1 = frame:FindFirstChild("1st_part") or frame
local back = part1 and (part1:FindFirstChild("Back") or part1:FindFirstChild("back"))
local oneSum = part1:FindFirstChild("1_Sum")
local skipBtn = part1.Skip:FindFirstChild("Skip_b")
local part2 = frame:FindFirstChild("2nd_part")
-- Ensure the second part starts hidden (non-destructive): try to find it under frame and hide
if not back or not oneSum then
	warn("[Roll] Required UI parts (Back / 1_Sum) not found. Aborting roll animator.")
	return
end

-- Find image holders inside the frames
local function findImageLabel(container)
	if not container then return nil end
	if container:IsA("ImageLabel") or container:IsA("ImageButton") then return container end
	return findDescendantOfClass(container, "ImageLabel") or findDescendantOfClass(container, "ImageButton")
end

local backImg = findImageLabel(back)
local sumImg = oneSum.ImageLabel

-- Save original transforms so we can restore them
local origBackPos = back.Position
local origBackSize = back.Size
local origSumVisible = oneSum.Visible
local origSumSize = oneSum.Size

-- Control variables
local skipping = false

if skipBtn and (skipBtn:IsA("TextButton") or skipBtn:IsA("ImageButton")) then
	skipBtn.MouseButton1Click:Connect(function()
		skipping = true
	end)
end

-- Paleta por número de estrelas (usada para o StarGrad)
local StarColors = {
	[1] = Color3.fromRGB(130,130,130),
	[2] = Color3.fromRGB(90,170,90),
	[3] = Color3.fromRGB(70,130,255),
	[4] = Color3.fromRGB(180,85,255),
	[5] = Color3.fromRGB(255,190,40),
}
local function colorForStarsLocal(stars)
	if not stars then return Color3.fromRGB(255,255,255) end
	return StarColors[tonumber(stars)] or Color3.fromRGB(255,255,255)
end

-- Apply colors to the existing 'StarGrad' UIGradient inside oneSum (modifies Studio StarGrad)
local function applyStarGradForStars(stars)
	if not oneSum then return end
	local grad = oneSum:FindFirstChild("StarGrad")
	if not grad or not grad:IsA("UIGradient") then
		warn("[Roll] StarGrad not found in 1_Sum; cannot apply colors")
		return
	end
	local base = colorForStarsLocal(stars)
	local h,s,v = base:ToHSV()
	local lighter = Color3.fromHSV(h, math.clamp(s * 0.15, 0, 1), 1)
	local darker = Color3.fromHSV(h, s, math.max(v * 0.15, 0.05))
	grad.Rotation = 90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, lighter),
		ColorSequenceKeypoint.new(0.45, base),
		ColorSequenceKeypoint.new(1, darker),
	})
	grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0) })
	grad.Enabled = true
	-- Debug: print applied keypoints
	pcall(function()
		if grad.Color and grad.Color.Keypoints then
			for i,k in ipairs(grad.Color.Keypoints) do
				local c = k.Value
				print(string.format("[Roll][StarGrad] kp[%d] time=%.2f -> R=%.3f G=%.3f B=%.3f", i, k.Time, c.R, c.G, c.B))
			end
		end
	end)
	print(string.format("[Roll] StarGrad updated for stars=%s", tostring(stars)))
end

-- Play the reveal animation for a single image (imageId is string like "rbxassetid://123")
local function playSingleReveal(imageEntry)
    print(string.format("[Roll] playSingleReveal start -> entry type=%s", type(imageEntry)))
	-- Normalize entry: allow either string imageId or table {image, stars}
	local imageId = nil
	local stars = nil
	if type(imageEntry) == "table" then
		imageId = imageEntry.image
		stars = imageEntry.stars
	else
		imageId = tostring(imageEntry or "")
	end

	-- If skip requested, show immediately
	if skipping then
		if sumImg then
			pcall(function()
				-- ensure the StarGrad reflects this entry even when skipping
				pcall(function() applyStarGradForStars(stars) end)
				sumImg.Image = imageId or ""
				oneSum.Visible = true
				back.Visible = false
			end)
			-- small wait to allow UIGradient to update before the next quick reveal
			task.wait(0.04)
		end
		return
	end

	-- Prepare frames
	pcall(function()
		back.Visible = true
		oneSum.Visible = false
		-- start the back slightly above so it "descends" (keep X the same)
		local startPos = UDim2.new(origBackPos.X.Scale, origBackPos.X.Offset, -0.6, 0)
		back.Position = startPos
		-- ensure back image is full width initially
		if backImg and backImg:IsA("ImageLabel") then
			backImg.Size = UDim2.new(1, 0, 1, 0)
		end
	end)

	-- Tween back down while performing a flip-like squash on X
	-- Slower descent for a weightier feel; squash to near-zero X, swap image, then expand X back to 1
	local descentTime = 0.9
	local squashTime = descentTime * 0.55
	local unsquashTime = descentTime * 0.35

	local tweenPos = TweenService:Create(back, TweenInfo.new(descentTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = origBackPos })
	local tweenSquash = nil
	if backImg then
		-- shrink X to a very small value (avoid absolute 0 to prevent layout issues)
		tweenSquash = TweenService:Create(backImg, TweenInfo.new(squashTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(0.01, 0, backImg.Size.Y.Scale, backImg.Size.Y.Offset) })
	end

	-- Play descent and squash together
	if tweenSquash then tweenSquash:Play() end
	tweenPos:Play()

	-- Poll for skipping while waiting for the descent/squash to finish so Skip is responsive
	local elapsed = 0
	local pollStep = 0.02
	while elapsed < descentTime do
		if skipping then
			-- Immediately reveal the character and abort animations
			if sumImg then
				pcall(function()
					pcall(function() applyStarGradForStars(stars) end)
					sumImg.Image = imageId or ""
					oneSum.Visible = true
					back.Visible = false
				end)
				-- tiny yield to allow gradient to render
				task.wait(0.04)
			end
			return
		end
		task.wait(pollStep)
		elapsed = elapsed + pollStep
	end

	-- After descent finishes, perform the squash->unsquash swap phase
	if backImg then
		-- Ensure final squashed state (in case tween didn't finish exactly)
		pcall(function()
			backImg.Size = UDim2.new(0.01, 0, backImg.Size.Y.Scale, backImg.Size.Y.Offset)
		end)

		-- Swap the back image to the revealed character while X is near-zero
		pcall(function()
			if backImg and (backImg:IsA("ImageLabel") or backImg:IsA("ImageButton")) then
				backImg.Image = imageId or ""
			end
		end)

		-- Expand backImg X to full width while allowing Skip to interrupt
		local startUnsquash = 0
		while startUnsquash < unsquashTime do
			if skipping then
				if sumImg then
					pcall(function()
						pcall(function() applyStarGradForStars(stars) end)
						sumImg.Image = imageId or ""
						oneSum.Visible = true
						back.Visible = false
					end)
					-- tiny yield to allow gradient to render
					task.wait(0.04)
				end
				return
			end
			-- calculate intermediate scale (simple linear lerp)
			local t = math.clamp(startUnsquash / unsquashTime, 0, 1)
			local scaleX = 0.01 + (1 - 0.01) * t
			pcall(function()
				backImg.Size = UDim2.new(scaleX, 0, backImg.Size.Y.Scale, backImg.Size.Y.Offset)
			end)
			task.wait(pollStep)
			startUnsquash = startUnsquash + pollStep
		end
		-- ensure full final size
		pcall(function()
			backImg.Size = UDim2.new(1, 0, backImg.Size.Y.Scale, backImg.Size.Y.Offset)
		end)
	end

	if skipping then
		if sumImg then
			pcall(function()
				sumImg.Image = imageId or ""
				oneSum.Visible = true
				back.Visible = false
			end)
		end
		return
	end

	-- No runtime StarGrad manipulation: per request, we won't alter Studio-defined StarGrad or create runtime overlays here.

		-- Ensure the oneSum frame will show the gradient: if it's fully transparent, set a sensible BackgroundColor and make it visible
		pcall(function()
			-- keep existing oneSum background as-is; do not force color/transparency changes
		end)

	-- Transition to the 'oneSum' display with a small pop
	pcall(function()
		back.Visible = false
		if sumImg then
			-- Update the Studio StarGrad to match rarity before revealing
			pcall(function() applyStarGradForStars(stars) end)
			sumImg.Image = imageId or ""
			-- start small
			oneSum.Size = UDim2.new(origSumSize.X.Scale * 0.6, origSumSize.X.Offset, origSumSize.Y.Scale * 0.6, origSumSize.Y.Offset)
			oneSum.Visible = true
			local pop = TweenService:Create(oneSum, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = origSumSize })
			pop:Play()
			pop.Completed:Wait()
		else
			oneSum.Visible = true
		end
	end)

	-- Wait for either a click/touch or a short timeout so the player can advance early
	local function waitForClickOrTimeout(timeout)
		local clicked = false
		local conn
		conn = UserInputService.InputBegan:Connect(function(input, processed)
			if processed then return end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				clicked = true
				if conn and conn.Connected then
					conn:Disconnect()
				end
			end
		end)
		local elapsed = 0
		while elapsed < timeout and not clicked do
			if skipping then break end
			local dt = task.wait(0.03)
			elapsed = elapsed + dt
		end
		if conn and conn.Connected then pcall(function() conn:Disconnect() end) end
		return clicked
	end
	local revealHold = 0.65
	waitForClickOrTimeout(revealHold)
end

-- Color mapping per star rarity
-- Base color per star rarity; we will derive lighter/darker tones for a 3-point gradient
-- ...existing code...

-- Public: play a sequence of images (one per summoned character)
local function playSequence(imageList)
	print(string.format("[Roll] playSequence starting with %d entries", #imageList))
	skipping = false
	for idx, img in ipairs(imageList) do
		local dumpImg = img
		local dumpImage = (type(dumpImg) == "table" and dumpImg.image) or tostring(dumpImg)
		local dumpStars = (type(dumpImg) == "table" and dumpImg.stars) or nil
		print(string.format("[Roll] playSequence idx=%d -> image=%s, stars=%s", idx, tostring(dumpImage), tostring(dumpStars)))
		if skipping then
			-- Fast-path: reveal remaining images quickly without animations
			for j = idx, #imageList do
				local iimg = imageList[j]
				local imageId = nil
				if type(iimg) == "table" then imageId = iimg.image else imageId = tostring(iimg) end
				if sumImg then
					pcall(function()
						-- attempt to apply gradient per quick reveal so tint matches each character
						local stars = (type(iimg) == "table" and iimg.stars) or nil
						pcall(function() applyStarGradForStars(stars) end)
						sumImg.Image = imageId
						oneSum.Visible = true
						back.Visible = false
					end)
				end
				-- tiny yield so the player can glimpse each result and so gradient has a frame to update
				task.wait(0.06)
			end
			break
		else
			playSingleReveal(img)
		end
		-- If user clicked skip during revealSequence, continue to next immediately
		if skipping then
			-- if skipping toggled during playSingleReveal, continue to next and let loop handle fast path
		else
			-- small gap between reveals, but allow immediate click to advance: we reuse Input detection
			local clicked = false
			local conn
			conn = UserInputService.InputBegan:Connect(function(input, processed)
				if processed then return end
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					clicked = true
					if conn and conn.Connected then conn:Disconnect() end
				end
			end)
			local elapsed = 0
			local gap = 0.12
			while elapsed < gap and not clicked do
				if skipping then break end
				local dt = task.wait(0.03)
				elapsed = elapsed + dt
			end
			if conn and conn.Connected then pcall(function() conn:Disconnect() end) end
		end
	end
	-- Sequence finished: if skipping then we already showed last frame; otherwise wait for a final click to close UI or auto-close after short timeout
	if not skipping then
		-- wait for click or small timeout (2s) to close
		local clicked = false
		local conn
		conn = UserInputService.InputBegan:Connect(function(input, processed)
			-- Accept clicks even if processed by other UI so clicking anywhere dismisses part2
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				clicked = true
				if conn and conn.Connected then conn:Disconnect() end
			end
		end)
		local elapsed = 0
		local timeoutClose = 2
		while elapsed < timeoutClose and not clicked do
			local dt = task.wait(0.03)
			elapsed = elapsed + dt
		end
		if conn and conn.Connected then pcall(function() conn:Disconnect() end) end
	end
	-- (Intentionally left blank) keep roll UI visible until showSecondPart handles dismissal

	-- After finishing the roll, show part 2 with all summoned characters and wait for a global click to dismiss
	local function showSecondPart(images)
		-- Try direct children first, then search descendants as a fallback
		local part2 = frame:FindFirstChild("2nd_part")
		if (not part2 or not part2:IsA("GuiObject")) then
			-- search descendants for likely names
			for _, d in ipairs(frame:GetDescendants()) do
				if d:IsA("GuiObject") then
					local n = d.Name or ""
					local nl = string.lower(n)
					if n == "2nd_part" or n == "2nd" or nl:match("2nd") or nl:match("^2[_%w]*") then
						part2 = d
						break
					end
				end
			end
		end
		if not part2 or not part2:IsA("GuiObject") then
			print("[Roll] No 2nd_part found under frame. Children:")
			for _,c in ipairs(frame:GetChildren()) do print(" -", c.Name, c.ClassName) end
			return
		end
		-- Try to find a slot template inside part2 called 'Slot_f' (or first child)
		local slotTemplate = part2:FindFirstChild("Slot_f")
		-- Determine the results container: if Slot_f is inside a ScrollingFrame or Frame, use that parent
		local resultsContainer = part2
		if slotTemplate then
			resultsContainer = slotTemplate.Parent or part2
		end
		-- If a designer-provided template exists, record its original Visible state.
		-- We intentionally DO NOT hide it yet so the layout remains stable while we clone.
		local slotTemplateOriginalVisible = nil
		if slotTemplate and slotTemplate:IsA("GuiObject") then
			local ok, vis = pcall(function() return slotTemplate.Visible end)
			if ok then slotTemplateOriginalVisible = vis end
		end
		-- Clear only previously-created dynamic slots so we don't remove designer visuals.
		for _, c in ipairs(resultsContainer:GetChildren()) do
			local ok, isLayout = pcall(function() return c:IsA("UIGridLayout") or c:IsA("UIPadding") end)
			if ok and isLayout then
				-- skip layout helpers
			else
				local name = tostring(c.Name or "")
				local isDynamicByName = name:match("^Slot_%d+") ~= nil
				local isDynamicByAttr = false
				if c.GetAttribute then
					local ok2, attr = pcall(function() return c:GetAttribute("RollDynamic") end)
					if ok2 and attr == true then isDynamicByAttr = true end
				end
				if isDynamicByName or isDynamicByAttr then
					pcall(function() c:Destroy() end)
				else
					-- preserve any designer-provided children (do not modify their visual properties)
				end
			end
		end
		-- Populate slots for each image
		for i, entry in ipairs(images) do
			local resolved = (type(entry) == "table") and entry or { image = tostring(entry), stars = nil }
			local imgId = resolved.image or resolveToImage(entry)
			local stars = resolved.stars
			local newSlot = nil
			if slotTemplate then
				newSlot = slotTemplate:Clone()
				newSlot.Name = "Slot_" .. tostring(i)
				-- mark as dynamically created so we can clear it later without touching designer children
				if newSlot.SetAttribute then
					pcall(function() newSlot:SetAttribute("RollDynamic", true) end)
				end
				-- try to set an ImageLabel inside slot
				local img = findImageLabel(newSlot)
				if img then
					pcall(function() img.Image = tostring(imgId) end)
				end
				-- set star grad if slot has one
				local sgrad = newSlot:FindFirstChild("StarGrad")
				if sgrad and sgrad:IsA("UIGradient") then
					pcall(function()
						local base = colorForStarsLocal(stars)
						local h,s,v = base:ToHSV()
						local lighter = Color3.fromHSV(h, math.clamp(s * 0.15, 0, 1), 1)
						local darker = Color3.fromHSV(h, s, math.max(v * 0.15, 0.05))
						sgrad.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, lighter), ColorSequenceKeypoint.new(0.45, base), ColorSequenceKeypoint.new(1, darker) })
					end)
				end
				newSlot.Parent = resultsContainer
				-- ensure cloned slot is visible
				if newSlot:IsA("GuiObject") then pcall(function() newSlot.Visible = true end) end
			else
				-- create a minimal slot Frame
				newSlot = Instance.new("Frame")
				newSlot.Name = "Slot_" .. tostring(i)
				if newSlot.SetAttribute then pcall(function() newSlot:SetAttribute("RollDynamic", true) end) end
				newSlot.Size = UDim2.new(0, 80, 0, 80)
				newSlot.BackgroundTransparency = 1
				local img = Instance.new("ImageLabel")
				img.Size = UDim2.new(1,0,1,0)
				img.BackgroundTransparency = 1
				img.Image = tostring(imgId)
				img.Parent = newSlot
				newSlot.Parent = resultsContainer
				if newSlot:IsA("GuiObject") then pcall(function() newSlot.Visible = true end) end
			end
		end

		-- Now hide the template so it doesn't appear as an extra empty slot in the results
		if slotTemplate and slotTemplate:IsA("GuiObject") then
			pcall(function() slotTemplate.Visible = false end)
		end
		-- hide part1 while showing the summary so only the second part is visible
		local part1OriginalVisible = nil
		if part1 and part1:IsA("GuiObject") then
			pcall(function() part1OriginalVisible = part1.Visible end)
			pcall(function() part1.Visible = false end)
		end
		-- show part2 GUI and wait for a click anywhere
		part2.Visible = true
		local clicked = false
		local conn
		conn = UserInputService.InputBegan:Connect(function(input, processed)
			if processed then return end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				clicked = true
				if conn and conn.Connected then conn:Disconnect() end
			end
		end)
		-- wait until clicked
		while not clicked do task.wait(0.03) end
		-- hide part2
		part2.Visible = false
		-- restore Slot_f template visibility so it's present for future summons
		if slotTemplate and slotTemplateOriginalVisible ~= nil then
			pcall(function() slotTemplate.Visible = slotTemplateOriginalVisible end)
		end
		-- restore part1 visibility to its original state
		if part1 and part1:IsA("GuiObject") and part1OriginalVisible ~= nil then
			pcall(function() part1.Visible = part1OriginalVisible end)
		end
		-- restore main frame visibility state
		if frame and frame.Parent and frame:IsA("GuiObject") then frame.Visible = false end
	end

	-- show the second part summary with all images
	pcall(function()
		showSecondPart(imageList)
	end)
end

-- Example: expose a quick test if run in Studio
if script:GetAttribute("AutoTest") then
	-- Example asset ids (replace with valid ones when testing)
	local sample = {
		"rbxassetid://0",
		"rbxassetid://0",
		"rbxassetid://0",
	}
	task.delay(0.4, function() playSequence(sample) end)
end

-- Expose function on script so other scripts can call it (e.g., after server returns summons)
-- Expose function via a BindableFunction child named 'PlayRoll' so other scripts
-- can invoke it safely without attempting to set arbitrary properties on the
-- LocalScript instance (which causes "not a valid member" errors).
do
	local existing = script:FindFirstChild("PlayRoll")
	if existing and existing:IsA("BindableFunction") then
		existing.OnInvoke = function(...)
			-- allow callers to pass an image list or nil
			local args = { ... }
			local list = args[1]
			if type(list) ~= "table" then return false end
			playSequence(list)
			return true
		end
	else
		local bf = Instance.new("BindableFunction")
		bf.Name = "PlayRoll"
		bf.OnInvoke = function(list)
			if type(list) ~= "table" then return false end
			playSequence(list)
			return true
		end
		bf.Parent = script
	end
end

print("[Roll] Animator ready")
if SummonGrantedRE then
	print("[Roll] Listening for SummonGranted events from Remotes folder")
else
	warn("[Roll] SummonGranted remote not found in ReplicatedStorage.Remotes")
end

-- Helper: resolve a summoned result entry to an image id using CharacterCatalog if possible
local function resolveToImage(entry)
	-- entry may be a string id (template) or a table with id/icon_id
	if not entry then return "" end
	if type(entry) == "string" then
		-- try catalog
		if CharacterCatalog then
			local ok, c = pcall(function() return CharacterCatalog:Get(entry) end)
			if ok and c and c.icon_id then return c.icon_id end
		end
		return entry
	elseif type(entry) == "table" then
		-- common explicit image field
		if entry.icon_id then return entry.icon_id end
		-- try common template fields (server may send Template / TemplateName / template)
		local template = entry.Template or entry.TemplateName or entry.template or entry.templateName
		if template and CharacterCatalog then
			local ok, c = pcall(function() return CharacterCatalog:Get(template) end)
			if ok and c and c.icon_id then return c.icon_id end
		end
		-- some server payloads include lowercase 'id' which might be a template; try that too
		local maybeTemplate = entry.id or entry.Id
		if maybeTemplate and CharacterCatalog then
			local ok2, c2 = pcall(function() return CharacterCatalog:Get(maybeTemplate) end)
			if ok2 and c2 and c2.icon_id then return c2.icon_id end
		end
		-- fallback: prefer Template/TemplateName or Id as string if present
		local fallback = entry.icon_id or entry.Template or entry.TemplateName or entry.template or entry.templateName or entry.Id or entry.id
		if fallback then return tostring(fallback) end
		-- last resort: cannot resolve
		warn("[Roll] Unable to resolve summon entry to an image:", entry)
		return ""
	end
	return ""
end

-- Resolve an entry to both an image id and star count (if available).
local function resolveToImageAndStars(entry)
	if not entry then return { image = "", stars = nil } end
	-- If it's a simple string, try catalog for stars too
	if type(entry) == "string" then
		if CharacterCatalog then
			local ok, c = pcall(function() return CharacterCatalog:Get(entry) end)
			if ok and c then
				return { image = (c.icon_id or entry), stars = c.stars }
			end
		end
		return { image = entry, stars = nil }
	end
	-- If it's a table, prefer explicit icon_id and star fields
	if type(entry) == "table" then
		local img = entry.icon_id or entry.icon or entry.image
		local stars = entry.stars or entry.star or entry.rarity
		if img then
			print(string.format("[Roll][resolve] explicit table -> image=%s, stars=%s", tostring(img), tostring(stars)))
			return { image = tostring(img), stars = stars }
		end
		-- fallback to template lookup
		local template = entry.Template or entry.TemplateName or entry.template or entry.templateName or entry.Id or entry.id
		if template and CharacterCatalog then
			local ok2, c2 = pcall(function() return CharacterCatalog:Get(template) end)
			if ok2 and c2 then
				print(string.format("[Roll][resolve] template lookup -> template=%s, image=%s, stars=%s", tostring(template), tostring(c2.icon_id), tostring(c2.stars)))
				return { image = (c2.icon_id or tostring(template)), stars = c2.stars }
			end
		end
		-- last resort: try to resolve image alone
		local single = resolveToImage(entry)
		return { image = single or "", stars = stars }
	end
	return { image = "", stars = nil }
end

-- Color mapping per star rarity
-- Base color per star rarity; we will derive lighter/darker tones for a 3-point gradient
-- No gradient helpers: per user's request, this script will not alter Studio-defined StarGrad.

-- Listen to SummonGranted remote from server and play the roll animation
if SummonGrantedRE then
	SummonGrantedRE.OnClientEvent:Connect(function(payload)
		-- payload may be a table with .created array or a plain array of results
		if isPlaying then
			warn("[Roll] Received SummonGranted but already playing; ignoring payload")
			return
		end
		-- debug: print basic payload info
		local ptype = type(payload)
		print(string.format("[Roll] SummonGranted payload type=%s", tostring(ptype)))
		local images = {}
		local entries = nil
		if type(payload) == "table" then
			if payload.created and type(payload.created) == "table" then entries = payload.created end
			-- some server implementations might send a flat array
			if not entries and #payload > 0 then entries = payload end
		end
		-- if payload is just a string (single id), wrap it
		if not entries and type(payload) == "string" then entries = { payload } end
		if not entries then
			-- If server signalled failure, print reason for debugging
			if type(payload) == "table" and payload.success == false then
				warn("[Roll] Summon failed on server. Reason:", payload.reason or "(unknown)", "extra:", payload)
			else
				warn("[Roll] SummonGranted payload contained no entries; payload:", payload)
			end
			return
		end

		for _, e in ipairs(entries) do
			local resolved = resolveToImageAndStars(e)
			-- insert the resolved table so we keep both image and stars for gradient tinting
			table.insert(images, resolved or { image = "", stars = nil })
		end
		-- Debug: list resolved entries
		for i,v in ipairs(images) do
			pcall(function()
				print(string.format("[Roll][SummonGranted] entry %d -> image=%s, stars=%s", i, tostring(v.image), tostring(v.stars)))
			end)
		end

		if #images == 0 then return end

		-- show roll UI and play
		isPlaying = true
		pcall(function() frame.Visible = true end)
		skipping = false
		print(string.format("[Roll] Calling playSequence with %d images", #images))
		playSequence(images)
		skipping = false
		isPlaying = false
	end)
end