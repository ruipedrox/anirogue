-- LocalScript for Evolve UI
local screen = script.Parent
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local function findDescendantByName(root, name)
	for _, v in ipairs(root:GetDescendants()) do
		if v.Name == name then return v end
	end
	return nil
end

local frame2 = screen:FindFirstChild("2nd") or findDescendantByName(screen, "2nd")
if not frame2 then
	warn("[EvolveUI] Frame '2nd' not found")
	return
end

-- Currently selected main id for evolve (string or nil)
local evolveMainId = nil

-- Prepare common dependencies for resolving icons
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
local GetCharacterInventoryRF = Remotes and Remotes:FindFirstChild("GetCharacterInventory")
local GetProfileRF = Remotes and Remotes:FindFirstChild("GetProfile")
local CharacterCatalog = nil
pcall(function()
	local scripts = ReplicatedStorage:FindFirstChild("Scripts")
	if scripts then CharacterCatalog = require(scripts:FindFirstChild("CharacterCatalog")) end
end)

-- Top-level helper to set the 'After' icon given mainId/icon/template (mirror of Before)
local function setAfterIcon(mainIdInner, iconAssetInner, templateInner)
	local yup = frame2:FindFirstChild("yup")
	local after = yup and yup:FindFirstChild("After")
	if not after then return end
	local iconObj = after:FindFirstChild("Icon") or findDescendantByName(after, "Icon")
	if not iconObj then
		for _, d in ipairs(after:GetDescendants()) do
			if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and d.Name:lower():find("icon") then
				iconObj = d
				break
			end
		end
	end
	if not iconObj then return end

	pcall(function()
		print(string.format("[EvolveUI][DEBUG] setAfterIcon inputs -> mainId=%s template=%s iconAsset=%s", tostring(mainIdInner), tostring(templateInner), tostring(iconAssetInner)))
	end)

	-- Infer template from inventory if missing
	if (not templateInner or templateInner == "") and mainIdInner and GetCharacterInventoryRF then
		pcall(function()
			local ok, res = pcall(function() return GetCharacterInventoryRF:InvokeServer() end)
			if ok and res and res.inventory then
				local inv = res.inventory
				if inv.Instances then
					for _, entry in pairs(inv.Instances) do
						if entry and tostring(entry.Id) == tostring(mainIdInner) then
							if entry.TemplateName then templateInner = entry.TemplateName end
							if entry.Catalog and entry.Catalog.icon_id and (not iconAssetInner or iconAssetInner == "") then
								iconAssetInner = entry.Catalog.icon_id
							end
							break
						end
					end
				end
				if (not templateInner or templateInner == "") and inv.OrderedList then
					for _, e in ipairs(inv.OrderedList) do
						if e and tostring(e.Id) == tostring(mainIdInner) then
							if e.TemplateName then templateInner = e.TemplateName end
							if e.Catalog and e.Catalog.icon_id and (not iconAssetInner or iconAssetInner == "") then
								iconAssetInner = e.Catalog.icon_id
							end
							break
						end
					end
				end
			end
		end)
		pcall(function() print("[EvolveUI][DEBUG] setAfterIcon inferred templateInner=", tostring(templateInner), " iconAssetInner=", tostring(iconAssetInner)) end)
	end

	-- Determine next template via multiple sources
	local nextTemplate = nil
	if templateInner and type(templateInner) == "string" and CharacterCatalog and CharacterCatalog.Get then
		local ok, cat = pcall(function() return CharacterCatalog:Get(templateInner) end)
		if ok and cat and cat.evolve_to then nextTemplate = cat.evolve_to end
	end
	if not nextTemplate and templateInner and type(templateInner) == "string" then
		pcall(function()
			local shared = ReplicatedStorage:FindFirstChild("Shared")
			if shared then
				local chars = shared:FindFirstChild("Chars")
				if chars then
					local folder = chars:FindFirstChild(templateInner)
					if folder then
						local evolveModule = folder:FindFirstChild("Evolve")
						if evolveModule and evolveModule:IsA("ModuleScript") then
							local ok2, evo = pcall(require, evolveModule)
							if ok2 and evo and evo.evolve_to then nextTemplate = evo.evolve_to end
						end
					end
				end
			end
		end)
		pcall(function() print("[EvolveUI][DEBUG] setAfterIcon EvolveModule nextTemplate=", tostring(nextTemplate)) end)
	end
	if not nextTemplate then
		pcall(function()
			local scripts = ReplicatedStorage:FindFirstChild("Scripts")
			if scripts then
				local ok, Tiers = pcall(function() return require(scripts:FindFirstChild("CharacterTiers")) end)
				if ok and Tiers and Tiers.GetNextTier and templateInner then
					local s, nt = pcall(function() return Tiers:GetNextTier(templateInner) end)
					if s and nt then nextTemplate = nt end
				end
			end
		end)
		pcall(function() print("[EvolveUI][DEBUG] setAfterIcon after CharacterTiers nextTemplate=", tostring(nextTemplate)) end)
	end

	-- If explicit icon asset provided, set it
	if iconAssetInner and type(iconAssetInner) == "string" and iconAssetInner ~= "" then
		pcall(function() iconObj.Image = iconAssetInner end)
	end

	-- If nextTemplate resolved, use catalog data for After panel
	if nextTemplate and CharacterCatalog and CharacterCatalog.Get then
		local ok, cat = pcall(function() return CharacterCatalog:Get(nextTemplate) end)
		if ok and cat then
			pcall(function() if cat.icon_id then iconObj.Image = cat.icon_id end end)
			pcall(function() print("[EvolveUI][DEBUG] setAfterIcon catalog found for nextTemplate=", tostring(nextTemplate), " icon_id=", tostring(cat.icon_id), " stars=", tostring(cat.stars)) end)
			pcall(function()
				local afterFrame = after:FindFirstChild("Frame")
				local nameLabel = afterFrame and afterFrame:FindFirstChild("TextLabel")
				if nameLabel then nameLabel.Text = cat.displayName or cat.name or (cat.stats and cat.stats.name) or tostring(nextTemplate) end
			end)
			pcall(function()
				local stars = tonumber(cat.stars) or 1
				if stars < 1 then stars = 1 end
				if stars > 6 then stars = 6 end
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
				local grad = after:FindFirstChildOfClass("UIGradient")
				if not grad then
					grad = Instance.new("UIGradient")
					grad.Name = "StarGradient"
					grad.Parent = after
				end
				pcall(function() print("[EvolveUI][DEBUG] setAfterIcon gradient parent=", tostring(grad.Parent and grad.Parent.Name), " gradName=", tostring(grad.Name)) end)
				grad.Rotation = 90
				grad.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, lighter),
					ColorSequenceKeypoint.new(0.45, baseCol),
					ColorSequenceKeypoint.new(1, darker),
				})
				grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0) })
			end)
			return
		end
	end

	-- Fallback: resolve name/icon from template/catalog or inventory
	pcall(function()
		local afterFrame = after:FindFirstChild("Frame")
		local nameLabel = afterFrame and afterFrame:FindFirstChild("TextLabel")
		local resolvedName = nil
		if templateInner and type(templateInner) == "string" and CharacterCatalog and CharacterCatalog.Get then
			local ok, cat = pcall(function() return CharacterCatalog:Get(templateInner) end)
			if ok and cat then resolvedName = cat.displayName or cat.name or (cat.stats and cat.stats.name) end
		end
		if (not resolvedName or resolvedName == "") and mainIdInner and GetCharacterInventoryRF then
			local ok, res = pcall(function() return GetCharacterInventoryRF:InvokeServer() end)
			if ok and res and res.inventory then
				local inv = res.inventory
				if inv.Instances then
					for _, entry in pairs(inv.Instances) do
						if entry and tostring(entry.Id) == tostring(mainIdInner) then
							if entry.DisplayName then resolvedName = entry.DisplayName end
							if (not resolvedName or resolvedName == "") and entry.Catalog and entry.Catalog.displayName then resolvedName = entry.Catalog.displayName end
							if (not resolvedName or resolvedName == "") and entry.TemplateName and CharacterCatalog and CharacterCatalog.Get then
								local ok2, cat2 = pcall(function() return CharacterCatalog:Get(entry.TemplateName) end)
								if ok2 and cat2 then resolvedName = cat2.displayName or cat2.name or (cat2.stats and cat2.stats.name) end
							end
						end
					end
				end
				if (not resolvedName or resolvedName == "") and inv.OrderedList then
					for _, e in ipairs(inv.OrderedList) do
						if e and tostring(e.Id) == tostring(mainIdInner) then
							if e.DisplayName then resolvedName = e.DisplayName end
							if (not resolvedName or resolvedName == "") and e.Catalog and e.Catalog.displayName then resolvedName = e.Catalog.displayName end
							if (not resolvedName or resolvedName == "") and e.TemplateName and CharacterCatalog and CharacterCatalog.Get then
								local ok3, cat3 = pcall(function() return CharacterCatalog:Get(e.TemplateName) end)
								if ok3 and cat3 then resolvedName = cat3.displayName or cat3.name or (cat3.stats and cat3.stats.name) end
							end
						end
					end
				end
			end
		end
		if not resolvedName or resolvedName == "" then
			if templateInner and type(templateInner) == "string" then resolvedName = templateInner else resolvedName = "Nome" end
		end
		if nameLabel then pcall(function() nameLabel.Text = tostring(resolvedName) end) end
		pcall(function() print("[EvolveUI][DEBUG] setAfterIcon fallback resolvedName=", tostring(resolvedName), " nameLabelExists=", tostring(nameLabel ~= nil), " iconImage=", tostring(iconObj.Image)) end)
	end)
end

-- Top-level helper to set the 'Before' icon given mainId/icon/template
local function setBeforeIcon(mainIdInner, iconAssetInner, templateInner)
	-- exact path: 2nd -> yup -> Before (preferred per UI hierarchy)
	
	local yup = frame2:FindFirstChild("yup")
	local before = yup:FindFirstChild("Before")
	if not before then return end
	local iconObj = before:FindFirstChild("Icon") or findDescendantByName(before, "Icon")
	if not iconObj then
		for _, d in ipairs(before:GetDescendants()) do
			if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and d.Name:lower():find("icon") then
				iconObj = d
				break
			end
		end
	end
	if not iconObj then return end

	-- Diagnostic input log
	pcall(function()
		print(string.format("[EvolveUI][DEBUG] setBeforeIcon inputs -> mainId=%s template=%s iconAsset=%s", tostring(mainIdInner), tostring(templateInner), tostring(iconAssetInner)))
	end)

	-- If explicit asset provided, use it
	if iconAssetInner and type(iconAssetInner) == "string" and iconAssetInner ~= "" then
		pcall(function()
			iconObj.Image = iconAssetInner
			print("[EvolveUI][DEBUG] set icon from explicit asset", tostring(iconAssetInner))
		end)
		-- continue to resolve and set the name label
	end

	-- Attempt to set the name label under Before->Frame->TextLabel
	pcall(function()

		local beforeFrame = before:FindFirstChild("Frame")
		local nameLabel = beforeFrame:FindFirstChild("TextLabel")


		local resolvedName = nil
		-- Try template via CharacterCatalog
		if templateInner and type(templateInner) == "string" and CharacterCatalog and CharacterCatalog.Get then
			local ok, cat = pcall(function() return CharacterCatalog:Get(templateInner) end)
			if ok and cat then
				resolvedName = cat.displayName or cat.name or (cat.stats and cat.stats.name)
			end
		end
		-- Try inventory entry if still nil
		if (not resolvedName or resolvedName == "") and mainIdInner and GetCharacterInventoryRF then
			local ok, res = pcall(function() return GetCharacterInventoryRF:InvokeServer() end)
			if ok and res and res.inventory then
				local inv = res.inventory
				if inv.Instances then
					for _, entry in pairs(inv.Instances) do
						if entry and tostring(entry.Id) == tostring(mainIdInner) then
							if entry.DisplayName then resolvedName = entry.DisplayName end
							if (not resolvedName or resolvedName == "") and entry.Catalog and entry.Catalog.displayName then resolvedName = entry.Catalog.displayName end
							if (not resolvedName or resolvedName == "") and entry.TemplateName and CharacterCatalog and CharacterCatalog.Get then
								local ok2, cat2 = pcall(function() return CharacterCatalog:Get(entry.TemplateName) end)
								if ok2 and cat2 then resolvedName = cat2.displayName or cat2.name or (cat2.stats and cat2.stats.name) end
							end
						end
					end
				end
				if (not resolvedName or resolvedName == "") and inv.OrderedList then
					for _, e in ipairs(inv.OrderedList) do
						if e and tostring(e.Id) == tostring(mainIdInner) then
							if e.DisplayName then resolvedName = e.DisplayName end
							if (not resolvedName or resolvedName == "") and e.Catalog and e.Catalog.displayName then resolvedName = e.Catalog.displayName end
							if (not resolvedName or resolvedName == "") and e.TemplateName and CharacterCatalog and CharacterCatalog.Get then
								local ok3, cat3 = pcall(function() return CharacterCatalog:Get(e.TemplateName) end)
								if ok3 and cat3 then resolvedName = cat3.displayName or cat3.name or (cat3.stats and cat3.stats.name) end
							end
						end
					end
				end
			end
		end

		-- Final fallback: use templateInner or a generic label
			-- Try to infer template from id (e.g. 'XP3_1234' -> 'XP3') and lookup catalog
			if not resolvedName or resolvedName == "" then
				pcall(function()
					if type(mainIdInner) == "string" then
						local base = string.match(mainIdInner, "^(.-)_[^_]+$")
						if base and CharacterCatalog and CharacterCatalog.Get then
							local okb, catb = pcall(function() return CharacterCatalog:Get(base) end)
							if okb and catb then resolvedName = catb.displayName or catb.name or (catb.stats and catb.stats.name) end
						end
					end
				end)
			end
			if not resolvedName or resolvedName == "" then
				if templateInner and type(templateInner) == "string" then resolvedName = templateInner else resolvedName = "Nome" end
			end
		-- diagnostic: what name we will apply
		pcall(function() print("[EvolveUI][DEBUG] resolvedName=", tostring(resolvedName), " nameLabelExists=", tostring(nameLabel ~= nil)) end)
		-- apply
		pcall(function() nameLabel.Text = tostring(resolvedName) end)
	end)

	-- Apply rarity gradient based on stars (prefer Catalog.stars, then CharacterCatalog)
	pcall(function()
		local stars = nil
		-- try from template
		if templateInner and type(templateInner) == "string" and CharacterCatalog and CharacterCatalog.Get then
			local ok, cat = pcall(function() return CharacterCatalog:Get(templateInner) end)
			if ok and cat and cat.stars then stars = tonumber(cat.stars) end
		end
		-- try from inventory entry
		if (not stars) and mainIdInner and GetCharacterInventoryRF then
			local ok, res = pcall(function() return GetCharacterInventoryRF:InvokeServer() end)
			if ok and res and res.inventory then
				local inv = res.inventory
				if inv.Instances then
					for _, entry in pairs(inv.Instances) do
						if entry and tostring(entry.Id) == tostring(mainIdInner) then
							if entry.Catalog and entry.Catalog.stars then stars = tonumber(entry.Catalog.stars) end
							if (not stars) and entry.stars then stars = tonumber(entry.stars) end
						end
					end
				end
			end
		end
		if not stars then stars = 1 end

		-- palette per stars (1..6)
		local Pal = {
			[1] = { Color3.fromRGB(200,200,200), Color3.fromRGB(130,130,130), Color3.fromRGB(60,60,60) },
			[2] = { Color3.fromRGB(180,230,180), Color3.fromRGB(90,170,90), Color3.fromRGB(30,80,30) },
			[3] = { Color3.fromRGB(160,200,255), Color3.fromRGB(70,130,255), Color3.fromRGB(20,60,140) },
			[4] = { Color3.fromRGB(220,160,255), Color3.fromRGB(180,85,255), Color3.fromRGB(90,30,140) },
			[5] = { Color3.fromRGB(255,230,160), Color3.fromRGB(255,190,40), Color3.fromRGB(160,110,20) },
			[6] = { Color3.fromRGB(255,160,160), Color3.fromRGB(255,50,50), Color3.fromRGB(150,20,20) },
		}
		local s = stars
		if s < 1 then s = 1 end
		if s > 6 then s = 6 end
		local trio = Pal[s] or Pal[1]
		local lighter, baseCol, darker = trio[1], trio[2], trio[3]

		-- find or create UIGradient directly under Before (no fallback)
		local grad = before:FindFirstChildOfClass("UIGradient")
		if not grad then
			grad = Instance.new("UIGradient")
			grad.Name = "StarGradient"
			grad.Parent = before
		end
		grad.Rotation = 90
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, lighter),
			ColorSequenceKeypoint.new(0.45, baseCol),
			ColorSequenceKeypoint.new(1, darker),
		})
		grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0) })
	end)

	-- If template provided, try CharacterCatalog
	if templateInner and type(templateInner) == "string" and CharacterCatalog and CharacterCatalog.Get then
		local ok, cat = pcall(function() return CharacterCatalog:Get(templateInner) end)
		if ok and cat and cat.icon_id then pcall(function() iconObj.Image = cat.icon_id end) return end
	end

	-- Try to resolve mainId from player's inventory via remote
	if mainIdInner and GetCharacterInventoryRF then
		local ok, res = pcall(function() return GetCharacterInventoryRF:InvokeServer() end)
		if ok and res and res.inventory then
			local inv = res.inventory
			-- try Instances map first
			if inv.Instances then
				for _, entry in pairs(inv.Instances) do
					if entry and tostring(entry.Id) == tostring(mainIdInner) then
						-- use Catalog.icon_id if present
						if entry.Catalog and entry.Catalog.icon_id then pcall(function() iconObj.Image = entry.Catalog.icon_id end) return end
						-- else try CharacterCatalog with TemplateName
						if entry.TemplateName and CharacterCatalog and CharacterCatalog.Get then
							local ok2, cat2 = pcall(function() return CharacterCatalog:Get(entry.TemplateName) end)
							if ok2 and cat2 and cat2.icon_id then pcall(function() iconObj.Image = cat2.icon_id end) return end
						end
					end
				end
			end
			-- fallback: search OrderedList
			if inv.OrderedList then
				for _, e in ipairs(inv.OrderedList) do
					if e and tostring(e.Id) == tostring(mainIdInner) then
						if e.Catalog and e.Catalog.icon_id then pcall(function() iconObj.Image = e.Catalog.icon_id end) return end
						if e.TemplateName and CharacterCatalog and CharacterCatalog.Get then
							local ok3, cat3 = pcall(function() return CharacterCatalog:Get(e.TemplateName) end)
							if ok3 and cat3 and cat3.icon_id then pcall(function() iconObj.Image = cat3.icon_id end) return end
						end
					end
				end
			end
		end
	end
end

-- Format number with commas (e.g. 2500 -> 2,500)
local function formatWithCommas(n)
	local num = tonumber(n) or 0
	local s = tostring(math.floor(math.abs(num)))
	local result = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if result:sub(1,1) == "," then result = result:sub(2) end
	if num < 0 then result = "-" .. result end
	return result
end

-- Set the Upgrade->Top->TextLabel to the evolve cost (formatted). Attempts to load Evolve module.
local function setUpgradeCost(mainIdInner, templateInner)
	local yup = frame2:FindFirstChild("yup")
	if not yup then return end
	local upgrade = yup:FindFirstChild("Upgrade")
	if not upgrade then return end
	local top = upgrade:FindFirstChild("Top") or findDescendantByName(upgrade, "Top")
	local costLabel = top and (top:FindFirstChild("TextLabel") or findDescendantByName(top, "TextLabel"))

	-- try to infer template from inventory if missing
	if (not templateInner or templateInner == "") and mainIdInner and GetCharacterInventoryRF then
		pcall(function()
			local ok, res = pcall(function() return GetCharacterInventoryRF:InvokeServer() end)
			if ok and res and res.inventory then
				local inv = res.inventory
				if inv.Instances then
					for _, entry in pairs(inv.Instances) do
						if entry and tostring(entry.Id) == tostring(mainIdInner) then
							if entry.TemplateName then templateInner = entry.TemplateName end
							break
						end
					end
				end
				if (not templateInner or templateInner == "") and inv.OrderedList then
					for _, e in ipairs(inv.OrderedList) do
						if e and tostring(e.Id) == tostring(mainIdInner) then
							if e.TemplateName then templateInner = e.TemplateName end
							break
						end
					end
				end
			end
		end)
	end

	local costValue = nil
	if templateInner and type(templateInner) == "string" then
		pcall(function()
			local shared = ReplicatedStorage:FindFirstChild("Shared")
			if shared then
				local chars = shared:FindFirstChild("Chars")
				if chars then
					local folder = chars:FindFirstChild(templateInner)
					if folder then
						local evolveModule = folder:FindFirstChild("Evolve")
						if evolveModule and evolveModule:IsA("ModuleScript") then
							local ok, evo = pcall(require, evolveModule)
							if ok and evo and evo.cost then
								if type(evo.cost) == "table" then
									costValue = evo.cost.Gold or evo.cost["Gold"]
								end
							end
						end
					end
				end
			end
		end)
	end

	if costLabel then
		if costValue and tonumber(costValue) then
			costLabel.Text = formatWithCommas(costValue)
			pcall(function() print("[EvolveUI][DEBUG] setUpgradeCost applied ->", tostring(costLabel.Text)) end)
		else
			costLabel.Text = ""
			pcall(function() print("[EvolveUI][DEBUG] setUpgradeCost no cost found for", tostring(templateInner)) end)
		end
	end
end

-- Populate Req_list (Req_f clones) with requirements from Evolve module (exclude Gold)
local function setReqList(mainIdInner, templateInner)
	local yup = frame2:FindFirstChild("yup")
	if not yup then return end
	local req_list = yup:FindFirstChild("Req_list") or findDescendantByName(yup, "Req_list")
	if not req_list then return end

	-- find template entry to clone
	local template = req_list:FindFirstChild("Req_f") or findDescendantByName(req_list, "Req_f")
	if not template then
		for _,c in ipairs(req_list:GetChildren()) do if c:IsA("Frame") then template = c; break end end
	end
	if not template then return end
	template.Visible = false

	-- infer templateInner from inventory if missing
	if (not templateInner or templateInner == "") and mainIdInner and GetCharacterInventoryRF then
		pcall(function()
			local ok,res = pcall(function() return GetCharacterInventoryRF:InvokeServer() end)
			if ok and res and res.inventory then
				local inv = res.inventory
				if inv.Instances then for _,e in pairs(inv.Instances) do if e and tostring(e.Id) == tostring(mainIdInner) and e.TemplateName then templateInner = e.TemplateName; break end end end
				if (not templateInner or templateInner == "") and inv.OrderedList then for _,e in ipairs(inv.OrderedList) do if e and tostring(e.Id) == tostring(mainIdInner) and e.TemplateName then templateInner = e.TemplateName; break end end end
			end
		end)
	end

	-- load evolve rules and build requirements list
	local requirements = {}
	pcall(function()
		if templateInner and type(templateInner) == "string" then
			local shared = ReplicatedStorage:FindFirstChild("Shared")
			if shared and shared:FindFirstChild("Chars") then
				local folder = shared.Chars:FindFirstChild(templateInner)
				if folder then
					local m = folder:FindFirstChild("Evolve")
					if m and m:IsA("ModuleScript") then
						local ok,e = pcall(require, m)
						if ok and e then
							for _,mreq in ipairs(e.materials_req or {}) do if mreq and mreq.template and tostring(mreq.template):lower() ~= "gold" then table.insert(requirements, { template = mreq.template, count = tonumber(mreq.count) or 1 }) end end
							for _,creq in ipairs(e.copies_req or {}) do if creq and creq.template and tostring(creq.template):lower() ~= "gold" then table.insert(requirements, { template = creq.template, count = tonumber(creq.count) or 1 }) end end
						end
					end
				end
			end
		end
	end)

	-- fetch profile/inventory once for counting
	local invRes, profRes
	pcall(function()
		if GetCharacterInventoryRF then
			invRes = GetCharacterInventoryRF:InvokeServer()
		end
	end)
	pcall(function()
		if GetProfileRF then
			profRes = GetProfileRF:InvokeServer()
		end
	end)
	local profileDrops = (profRes and profRes.profile and profRes.profile.Drops and profRes.profile.Drops.evolve) or nil

	-- remove previous generated entries
	for _,c in ipairs(req_list:GetChildren()) do
		if c ~= template then
			local ok, gen = pcall(function()
				if c.GetAttribute then
					return c:GetAttribute("_ReqGenerated")
				end
				return false
			end)
			local isGen = false
			if type(c.Name) == "string" and c.Name:sub(1,10) == "Req_f_gen_" then isGen = true end
			if gen or isGen then
				pcall(function() c:Destroy() end)
			end
		end
	end

	-- helper: normalize
	local function normKey(s) if not s then return "" end return tostring(s):lower():gsub("[%s_%-]","") end
	-- helper: detect drop table
	local function isDropTemplate(idStr)
		if not idStr then return false end
		local ok, res = pcall(function()
			local shared = ReplicatedStorage:FindFirstChild("Shared")
			if not shared then return false end
			local drops = shared:FindFirstChild("Drops")
			if not drops then return false end
			local evo = drops:FindFirstChild("Evolve")
			if not evo then return false end
			local mod = evo:FindFirstChild("Items")
			if not mod or not mod:IsA("ModuleScript") then return false end
			local ok2, tbl = pcall(require, mod)
			if not ok2 or type(tbl) ~= "table" then return false end
			local want = normKey(idStr)
			for k,_ in pairs(tbl) do if normKey(k) == want then return true end end
			return false
		end)
		return ok and res
	end

	-- merge requirements
	local merged = {}
	for _,r in ipairs(requirements) do merged[tostring(r.template)] = (merged[tostring(r.template)] or 0) + (tonumber(r.count) or 1) end

	-- render each merged requirement
	for tpl, cnt in pairs(merged) do
		local clone = template:Clone()
		clone.Name = "Req_f_gen_" .. tpl
		clone.Parent = req_list
		clone.Visible = true
		-- resolve display/icon/meta
		local displayName, icon, meta = tostring(tpl), nil, {}
		-- resolve display/icon/meta using a clear function (avoid complex inline pcall)
		local function _resolveDisplayIconMeta(t)
			if CharacterCatalog and CharacterCatalog.Get then
				local ok, c = pcall(function() return CharacterCatalog:Get(t) end)
				if ok and c then
					return c.displayName or c.name or t, c.icon_id, { stars = tonumber(c.stars) }
				end
			end
			-- inventory
			if invRes and invRes.inventory then
				local inv = invRes.inventory
				if inv.Instances then
					for _, e in pairs(inv.Instances) do
						if e and tostring(e.TemplateName) == tostring(t) then
							return e.DisplayName or t, (e.Catalog and e.Catalog.icon_id) or nil, { stars = (e.Catalog and tonumber(e.Catalog.stars)) }
						end
					end
				end
				if inv.OrderedList then
					for _, e in ipairs(inv.OrderedList) do
						if e and tostring(e.TemplateName) == tostring(t) then
							return e.DisplayName or t, (e.Catalog and e.Catalog.icon_id) or nil, { stars = (e.Catalog and tonumber(e.Catalog.stars)) }
						end
					end
				end
			end
			-- shared drops/items modules
			local shared = ReplicatedStorage:FindFirstChild("Shared")
			if shared then
				local drops = shared:FindFirstChild("Drops")
				if drops and drops:FindFirstChild("Evolve") then
					local evo = drops:FindFirstChild("Evolve")
					local mod = evo and evo:FindFirstChild("Items")
					if mod and mod:IsA("ModuleScript") then
						local ok2, tbl = pcall(require, mod)
						if ok2 and type(tbl) == "table" then
							for k, v in pairs(tbl) do
								if normKey(k) == normKey(t) and type(v) == "table" then
									return (v.DisplayName or v.displayName or t), (v.Icon or v.icon or nil), (v.Rarity and { rarity = v.Rarity } or {})
								end
							end
						end
					end
				end
			end
			return t, nil, {}
		end
		local okr, dn, ic, md = pcall(_resolveDisplayIconMeta, tpl)
		if okr then displayName, icon, meta = dn, ic, md end

		local img = clone:FindFirstChild("ImageLabel") or clone:FindFirstChild("Icon") or findDescendantByName(clone, "ImageLabel") or findDescendantByName(clone, "Icon")
		if img and icon and type(icon) == "string" then pcall(function() img.Image = icon end) end
		local primary = clone:FindFirstChild("TextLabel") or findDescendantByName(clone, "TextLabel")
		local countLabel = nil
		for _,d in ipairs(clone:GetDescendants()) do if d:IsA("TextLabel") and d ~= primary and (d.Name:lower():find("count") or d.Name:lower():find("amount") or d.Name:lower():find("num")) then countLabel = d; break end end

		-- compute owned
		local owned = 0
		if isDropTemplate(tpl) then
			if profileDrops then for id,q in pairs(profileDrops) do if normKey(id) == normKey(tpl) or normKey(id) == normKey(displayName) then owned = owned + (tonumber(q) or 0) end end end
			if invRes and invRes.inventory then local inv = invRes.inventory if inv.Items then for _,it in pairs(inv.Items) do local id = tostring(it.TemplateName or it.Template or it.Id or it.ItemId or it.Name) if id and (id == tostring(tpl) or id:lower() == tostring(tpl):lower()) then owned = owned + (tonumber(it.Count or it.Quantity or it.Qty) or 1) end end end if inv.Materials then for _,m in pairs(inv.Materials) do local id = tostring(m.Template or m.TemplateName or m.Id or m.Name or m.Item) if id and (id == tostring(tpl) or id:lower() == tostring(tpl):lower()) then owned = owned + (tonumber(m.Count or m.Amount) or 1) end end end end
		else
			if profRes and profRes.profile and profRes.profile.Characters then local pchars = profRes.profile.Characters if pchars.Instances then if #pchars.Instances > 0 then for _,inst in ipairs(pchars.Instances) do local entryTpl = tostring(inst.Template or inst.TemplateName or inst.template) if entryTpl ~= "" and (entryTpl == tostring(tpl) or entryTpl:lower() == tostring(tpl):lower()) then owned = owned + 1 end end else for id,inst in pairs(pchars.Instances) do local entryTpl = tostring(inst.TemplateName or inst.Template or inst.template) if entryTpl ~= "" and (entryTpl == tostring(tpl) or entryTpl:lower() == tostring(tpl):lower()) then owned = owned + 1 end end end end if pchars.OrderedList and type(pchars.OrderedList) == "table" then for _,inst in ipairs(pchars.OrderedList) do local entryTpl = tostring(inst.Template or inst.TemplateName or inst.template) if entryTpl ~= "" and (entryTpl == tostring(tpl) or entryTpl:lower() == tostring(tpl):lower()) then owned = owned + 1 end end end end
			if owned == 0 and invRes and invRes.inventory then local inv = invRes.inventory if inv.Instances then for _,entry in pairs(inv.Instances) do if entry and tostring(entry.TemplateName) == tostring(tpl) then owned = owned + 1 end end end if inv.OrderedList then for _,e in ipairs(inv.OrderedList) do if e and tostring(e.TemplateName) == tostring(tpl) then owned = owned + 1 end end end end
		end

		-- set display/count
		pcall(function()
			if primary and primary:IsA("TextLabel") then
				if countLabel and countLabel:IsA("TextLabel") then
					primary.Text = tostring(displayName or tpl)
					countLabel.Text = tostring(owned) .. "/" .. tostring(cnt)
				else
					primary.Text = tostring(owned) .. "/" .. tostring(cnt)
				end
			else
				if countLabel and countLabel:IsA("TextLabel") then countLabel.Text = tostring(owned) .. "/" .. tostring(cnt) end
			end
		end)

		-- apply rarity gradient
		local s = tonumber(meta.stars) or 1
		if s < 1 then s = 1 end
		if s > 6 then s = 6 end
		local Pal = {
			[1] = { Color3.fromRGB(200,200,200), Color3.fromRGB(130,130,130), Color3.fromRGB(60,60,60) },
			[2] = { Color3.fromRGB(180,230,180), Color3.fromRGB(90,170,90), Color3.fromRGB(30,80,30) },
			[3] = { Color3.fromRGB(160,200,255), Color3.fromRGB(70,130,255), Color3.fromRGB(20,60,140) },
			[4] = { Color3.fromRGB(220,160,255), Color3.fromRGB(180,85,255), Color3.fromRGB(90,30,140) },
			[5] = { Color3.fromRGB(255,230,160), Color3.fromRGB(255,190,40), Color3.fromRGB(160,110,20) },
			[6] = { Color3.fromRGB(255,160,160), Color3.fromRGB(255,50,50), Color3.fromRGB(150,20,20) },
		}
		local baseColor = (Pal[s] and Pal[s][2]) or Pal[1][2]
		if not baseColor and CharacterCatalog and CharacterCatalog.Get then local okc, catc = pcall(function() return CharacterCatalog:Get(tpl) end) if okc and catc and catc.stars then local ss = tonumber(catc.stars) or 1 local map = { [1]=Color3.fromRGB(200,200,200), [2]=Color3.fromRGB(180,230,180), [3]=Color3.fromRGB(160,200,255), [4]=Color3.fromRGB(220,160,255), [5]=Color3.fromRGB(255,230,160), [6]=Color3.fromRGB(255,160,160) } baseColor = map[ss] or map[1] end end
		if not baseColor then baseColor = Color3.fromRGB(200,200,200) end
		if meta and meta.rarity and type(meta.rarity) == "string" then local rkey = tostring(meta.rarity):lower() local rarityMap = { comum = Color3.fromRGB(160,255,160), raro = Color3.fromRGB(90,140,220), epico = Color3.fromRGB(230,160,255), lendario = Color3.fromRGB(255,230,120), mitico = Color3.fromRGB(255,110,120) } if rarityMap[rkey] then baseColor = rarityMap[rkey] end end
		local grad = clone:FindFirstChildOfClass("UIGradient") or clone:FindFirstChild("UIGradient") if not grad then grad = Instance.new("UIGradient") grad.Name = "ReqRarity" grad.Parent = clone end
		local h2,s2,v2 = baseColor:ToHSV() local lighter = Color3.fromHSV(h2, math.clamp(s2*0.25,0,1), 1) local darker = Color3.fromHSV(h2, s2, math.clamp(v2*0.25,0,1)) grad.Rotation = 90 grad.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, lighter), ColorSequenceKeypoint.new(0.45, baseColor), ColorSequenceKeypoint.new(1, darker) }) grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0), NumberSequenceKeypoint.new(1,0) })

		pcall(function() if clone.SetAttribute then clone:SetAttribute("_ReqGenerated", true) end end)
	end
end


-- Try to find an Exit button inside the frame
local exitBtn = frame2:FindFirstChild("Exit") or findDescendantByName(frame2, "Exit")
if exitBtn and (exitBtn:IsA("TextButton") or exitBtn:IsA("ImageButton")) then
	exitBtn.MouseButton1Click:Connect(function()
		-- Hide evolve UI
		frame2.Visible = false
		-- Clear attribute if present
		pcall(function() screen:SetAttribute("EvolveMain", nil) end)
		evolveMainId = nil
	end)
else
	-- fallback: listen to any descendant named 'Exit' that is clickable
	for _, d in ipairs(frame2:GetDescendants()) do
		if (d:IsA("TextButton") or d:IsA("ImageButton")) and d.Name:lower():find("exit") then
			d.MouseButton1Click:Connect(function()
				frame2.Visible = false
				pcall(function() screen:SetAttribute("EvolveMain", nil) end)
				evolveMainId = nil
			end)
			break
		end
	end
end

-- Support SetMain BindableEvent (others call this)
local setMain = screen:FindFirstChild("SetMain")
if setMain and setMain:IsA("BindableEvent") then
	setMain.Event:Connect(function(mainId, iconAsset, templateName)
		frame2.Visible = true
		-- store selected main id for later confirm
		evolveMainId = mainId
		pcall(function()
			setBeforeIcon(mainId, iconAsset, templateName)
				-- call setAfterIcon to populate the After panel as well
				pcall(function() setAfterIcon(mainId, iconAsset, templateName) end)
			pcall(function() setUpgradeCost(mainId, templateName) end)
			pcall(function() setReqList(mainId, templateName) end)
		end)
	end)
end

-- Wire Evo button to perform evolve request
pcall(function()
	local yup = frame2:FindFirstChild("yup") or findDescendantByName(frame2, "yup")
	if not yup then return end
	local evoNode = yup:FindFirstChild("Evo") or findDescendantByName(yup, "Evo")
	if not evoNode then
		-- try to find a clickable descendant named Evo
		for _,d in ipairs(yup:GetDescendants()) do
			if (d:IsA("ImageButton") or d:IsA("TextButton")) and d.Name:lower():find("evo") then evoNode = d; break end
		end
	end
	if not evoNode then return end
	local evoBtn = evoNode
	-- helper: infer template name for a given mainId
	local function inferTemplateForMain(mainId)
		if not mainId then return nil end
		if GetCharacterInventoryRF then
			local ok, res = pcall(function() return GetCharacterInventoryRF:InvokeServer() end)
			if ok and res and res.inventory then
				local inv = res.inventory
				if inv.Instances then
					for _,entry in pairs(inv.Instances) do
						if entry and tostring(entry.Id) == tostring(mainId) then
							return entry.TemplateName or entry.Template
						end
					end
				end
				if inv.OrderedList then
					for _,e in ipairs(inv.OrderedList) do
						if e and tostring(e.Id) == tostring(mainId) then
							return e.TemplateName or e.Template
						end
					end
				end
			end
		end
		-- fallback: maybe evolveMainId is already a template
		if CharacterCatalog and type(mainId) == "string" then
			local ok, cat = pcall(function() return CharacterCatalog:Get(mainId) end)
			if ok and cat then return mainId end
		end
		return nil
	end

	local RequestEvolve = Remotes and Remotes:FindFirstChild("RequestEvolve")
	local EvolveResult = Remotes and Remotes:FindFirstChild("EvolveResult")

	local busy = false
	local function performEvolve()
		if busy then return end
		if not RequestEvolve then warn("[EvolveUI] RequestEvolve remote missing") return end
		local mainId = evolveMainId
		if not mainId or mainId == "" then warn("[EvolveUI] No main selected for evolve") return end
		busy = true
		pcall(function() if evoBtn.SetAttribute then evoBtn:SetAttribute("Busy", true) end end)

		-- infer template and load evolve rules
		local tpl = inferTemplateForMain(mainId)
		if not tpl then warn("[EvolveUI] cannot infer template for mainId", tostring(mainId)); busy = false; pcall(function() evoBtn:SetAttribute("Busy", false) end); return end
		local evoRules = nil
		pcall(function()
			local shared = ReplicatedStorage:FindFirstChild("Shared")
			if shared and shared:FindFirstChild("Chars") then
				local f = shared.Chars:FindFirstChild(tpl)
				if f then
					local m = f:FindFirstChild("Evolve")
					if m and m:IsA("ModuleScript") then
						local ok, e = pcall(require, m)
						if ok and e then evoRules = e end
					end
				end
			end
		end)
		if not evoRules then warn("[EvolveUI] evolve rules not found for", tostring(tpl)); busy = false; pcall(function() evoBtn:SetAttribute("Busy", false) end); return end

		-- build sacrificeIds by scanning profile or inventory
		local needed = {}
		for _,cr in ipairs(evoRules.copies_req or {}) do
			local wantTpl = tostring(cr.template or "")
			local cnt = tonumber(cr.count) or 0
			if cnt > 0 then
				needed[wantTpl] = (needed[wantTpl] or 0) + cnt
			end
		end
		local sacrificeIds = {}
		-- prefer profile snapshot
		local profile = nil
		pcall(function()
			if GetProfileRF then
				local ok, pres = pcall(function() return GetProfileRF:InvokeServer() end)
				if ok and pres and pres.profile then profile = pres.profile end
			end
		end)
		-- Build a flat candidate list from profile or inventory.
		-- Each candidate: { Id=..., TemplateName=..., Level=number, Equipped=bool }
		local candidates = {}
		local function pushCandidate(id, inst, equipped)
			if not id or not inst then return end
			if tostring(id) == tostring(mainId) then return end
			local tpl = tostring(inst.TemplateName or inst.Template or inst.template or inst.Template)
			local lvl = tonumber(inst.Level) or tonumber(inst.Level) or 1
			table.insert(candidates, { Id = tostring(id), TemplateName = tpl, Level = lvl, Equipped = (equipped == true) })
		end

		local eqSet = {}
		if profile and profile.Characters and profile.Characters.EquippedOrder then
			for _, id in ipairs(profile.Characters.EquippedOrder) do eqSet[tostring(id)] = true end
		end

		-- helpers to consume either map or array shapes
		local function gatherFromInstancesShape(instances)
			if not instances then return end
			-- If instances is an array of objects (BuildClientSnapshot style)
			if type(instances) == "table" then
				local isArray = true
				local cnt = 0
				for k,v in pairs(instances) do
					cnt = cnt + 1
					if type(k) ~= "number" then isArray = false end
				end
				if isArray then
					for _, v in ipairs(instances) do
						if v and v.Id then
							pushCandidate(v.Id, v, eqSet[tostring(v.Id)])
						end
					end
					return
				end
			end
			-- Fallback: assume map (id -> inst)
			for id, inst in pairs(instances) do
				pushCandidate(id, inst, eqSet[tostring(id)])
			end
		end

		if profile and profile.Characters then
			gatherFromInstancesShape(profile.Characters.Instances or {})
			if profile.Characters.OrderedList and type(profile.Characters.OrderedList) == "table" then
				for _, inst in ipairs(profile.Characters.OrderedList) do
					if inst and inst.Id then pushCandidate(inst.Id, inst, eqSet[tostring(inst.Id)]) end
				end
			end
		else
			-- fallback: fetch inventory map/snapshot
			if GetCharacterInventoryRF then
				local ok, res = pcall(function() return GetCharacterInventoryRF:InvokeServer() end)
				if ok and res and res.inventory then
					gatherFromInstancesShape(res.inventory.Instances or {})
					if res.inventory.OrderedList then
						for _, inst in ipairs(res.inventory.OrderedList) do
							if inst and inst.Id then pushCandidate(inst.Id, inst, eqSet[tostring(inst.Id)]) end
						end
					end
				end
			end
		end

		-- Sort candidates: prefer unequipped first, then lower level
		table.sort(candidates, function(a,b)
			if (a.Equipped and not b.Equipped) then return false end
			if (b.Equipped and not a.Equipped) then return true end
			if (a.Level ~= b.Level) then return a.Level < b.Level end
			return a.Id < b.Id
		end)

		-- Pick required sacrifices per template from sorted candidates
		for tpl, needCount in pairs(needed) do
			local want = tpl
			for i = 1, #candidates do
				if needCount <= 0 then break end
				local c = candidates[i]
				if c and tostring(c.TemplateName) == tostring(want) then
					table.insert(sacrificeIds, tostring(c.Id))
					needCount = needCount - 1
					needed[tpl] = needed[tpl] - 1
					-- mark candidate consumed so we don't reuse it
					candidates[i] = nil
				end
			end
		end

		-- check all requirements satisfied
		for k,v in pairs(needed) do
			if v > 0 then
				warn("[EvolveUI] Not enough copies available for", k)
				busy = false
				pcall(function() evoBtn:SetAttribute("Busy", false) end)
				return
			end
		end

		-- fire server
		pcall(function()
			RequestEvolve:FireServer(mainId, sacrificeIds)
		end)
	end

	-- connect click
	if evoBtn and (evoBtn:IsA("ImageButton") or evoBtn:IsA("TextButton")) then
		evoBtn.Activated:Connect(performEvolve)
		pcall(function() evoBtn.MouseButton1Click:Connect(performEvolve) end)
	else
		-- if not a button, try to find ImageButton child
		local btnChild = evoNode:FindFirstChildWhichIsA("ImageButton") or evoNode:FindFirstChildWhichIsA("TextButton")
		if btnChild then
			btnChild.Activated:Connect(performEvolve)
			pcall(function() btnChild.MouseButton1Click:Connect(performEvolve) end)
		end
	end

	-- listen for server result to refresh UI and unblock
	if EvolveResult then
		EvolveResult.OnClientEvent:Connect(function(res)
			pcall(function() evoBtn:SetAttribute("Busy", false) end)
			busy = false
			if res and res.Success then
				-- refresh UI: re-fetch profile/drops and req list
				pcall(function()
					if GetProfileRF then
						local ok,res2 = pcall(function() return GetProfileRF:InvokeServer() end)
						if ok and res2 and res2.profile then
							setReqList(evolveMainId, nil)
						end
					end
				end)
				-- Close the Evolve UI on success and clear selection
				pcall(function() frame2.Visible = false end)
				pcall(function() screen:SetAttribute("EvolveMain", nil) end)
				evolveMainId = nil
			else
				warn("[EvolveUI] Evolve failed: ", (res and res.Message) or "unknown")
			end
		end)
	end
end)

-- Support attribute 'EvolveMain' being set by other UIs
if screen.GetAttributeChangedSignal then
	screen:GetAttributeChangedSignal("EvolveMain"):Connect(function()
		local v = screen:GetAttribute("EvolveMain")
		if v and v ~= "" then
			frame2.Visible = true
			pcall(function()
				-- if attribute is a template name, try to use it directly; otherwise pass as mainId
				local ReplicatedStorage = game:GetService("ReplicatedStorage")
				local scripts = ReplicatedStorage:FindFirstChild("Scripts")
				local CharacterCatalog = nil
				pcall(function() if scripts then CharacterCatalog = require(scripts:FindFirstChild("CharacterCatalog")) end end)
				local isTemplate = false
				if CharacterCatalog and type(v) == "string" then
					local ok, cat = pcall(function() return CharacterCatalog:Get(v) end)
					if ok and cat then isTemplate = true end
				end
				if isTemplate then
					local setAttrIcon = screen:GetAttribute("EvolveMainIcon")
					-- template provided; clear numeric id
					evolveMainId = nil
					pcall(function()
						setBeforeIcon(nil, setAttrIcon, v)
						pcall(function() setAfterIcon(nil, setAttrIcon, v) end)
					end)
					pcall(function() setUpgradeCost(nil, v) end)
					pcall(function() setReqList(nil, v) end)
				else
					local iconAttr = screen:GetAttribute("EvolveMainIcon")
					-- treat attribute as mainId
					evolveMainId = v
					pcall(function()
						setBeforeIcon(v, iconAttr, nil)
						pcall(function() setAfterIcon(v, iconAttr, nil) end)
					end)
					pcall(function() setUpgradeCost(v, nil) end)
					pcall(function() setReqList(v, nil) end)
				end
			end)
		end
	end)
end

-- If attribute already set before this script ran, apply it now
pcall(function()
	if screen.GetAttribute then
		local cur = screen:GetAttribute("EvolveMain")
		if cur and cur ~= "" then
			-- behave like attribute changed
			local iconAttr = screen:GetAttribute("EvolveMainIcon")
			-- try to detect if cur is a template or id
			local isTemplateGuess = false
			if CharacterCatalog and type(cur) == "string" then
				local ok, c = pcall(function() return CharacterCatalog:Get(cur) end)
				if ok and c then isTemplateGuess = true end
			end
			if isTemplateGuess then
				evolveMainId = nil
				setBeforeIcon(nil, iconAttr, cur)
				pcall(function() setAfterIcon(nil, iconAttr, cur) end)
				pcall(function() setUpgradeCost(nil, cur) end)
				pcall(function() setReqList(nil, cur) end)
			else
				evolveMainId = cur
				setBeforeIcon(cur, iconAttr, nil)
				pcall(function() setAfterIcon(cur, iconAttr, nil) end)
				pcall(function() setUpgradeCost(cur, nil) end)
				pcall(function() setReqList(cur, nil) end)
			end
			frame2.Visible = true
		end
	end
end)

-- Initialize hidden
frame2.Visible = false
