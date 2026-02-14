-- Missions UI Controller
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- Attempt to require MissionsCatalog from ReplicatedStorage.Scripts (if present)
local MissionsCatalog = nil
pcall(function()
	local scriptsFolder = ReplicatedStorage:FindFirstChild("Scripts")
	if scriptsFolder and scriptsFolder:FindFirstChild("MissionsCatalog") then
		local ok, mod = pcall(require, scriptsFolder:FindFirstChild("MissionsCatalog"))
		if ok and type(mod) == "table" then
			MissionsCatalog = mod
			print("[Missions] MissionsCatalog loaded on client")
		end
	end
end)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local missionsGui = script.Parent
local firstFrame = missionsGui:WaitForChild("1st")
local closeButton = firstFrame:WaitForChild("Exit")

-- Remotes (para obter lista de missões)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local GetMissionsStatusRF = remotes:FindFirstChild("GetMissionsStatus") or remotes:WaitForChild("GetMissionsStatus")
local ClaimMissionRewardRE = remotes:FindFirstChild("ClaimMissionReward") or remotes:WaitForChild("ClaimMissionReward")
local MissionProgressUpdatedRE = remotes:FindFirstChild("MissionProgressUpdated") or remotes:WaitForChild("MissionProgressUpdated")
local MissionProgressUpdatedRE = remotes:FindFirstChild("MissionProgressUpdated")

-- Estado
local originalPosition = firstFrame.Position -- Guardar posição original do preview
firstFrame.Visible = false
local isAnimating = false

-- Formatar números grandes (curto)
local function formatNumber(n)
	n = tonumber(n) or 0
	if n >= 1e12 then return string.format("%.2fT", n / 1e12)
	elseif n >= 1e9 then return string.format("%.2fB", n / 1e9)
	elseif n >= 1e6 then return string.format("%.2fM", n / 1e6)
	elseif n >= 1e3 then return string.format("%.2fk", n / 1e3)
	else return tostring(math.floor(n)) end
end

-- Animações
local function slideIn()
	if isAnimating then return end
	isAnimating = true
	firstFrame.Position = UDim2.new(originalPosition.X.Scale, originalPosition.X.Offset, -0.6, 0)
	firstFrame.Visible = true
	local tween = TweenService:Create(firstFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = originalPosition
	})
	tween:Play()
	tween.Completed:Wait()
	isAnimating = false
end

-- Elements for mission list (template inside ScrollingFrame)
local function findMissionsContainer()
	local inv = firstFrame:FindFirstChild("Inv") or firstFrame:FindFirstChild("Inv", true)
	if not inv then return nil end
	local invFrame = inv:FindFirstChild("Inv_frame") or inv:FindFirstChild("Inv_frame", true)
	if not invFrame then return nil end
	local container = invFrame:FindFirstChild("ScrollingFrame") or invFrame:FindFirstChild("ScrollingFrame", true)
	return container
end

-- Procura o módulo Map por id e retorna o módulo (para DisplayName)
local function findMapModuleById(mapId)
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	if not shared then return nil end
	local mapsRoot = shared:FindFirstChild("Maps")
	if not mapsRoot then return nil end

	for _, category in ipairs(mapsRoot:GetChildren()) do
		if category and category:IsA("Folder") then
			for _, mapFolder in ipairs(category:GetChildren()) do
				if mapFolder and mapFolder:IsA("Folder") then
					local mapModule = mapFolder:FindFirstChild("Map")
					if mapModule and mapModule:IsA("ModuleScript") then
						local ok, mod = pcall(require, mapModule)
						if ok and type(mod) == "table" then
							local mid = tostring(mod.Id or mapFolder.Name):lower()
							if mid == tostring(mapId):lower() or tostring(mapFolder.Name):lower() == tostring(mapId):lower() then
								return mod
							end
						end
					end
				end
			end
		end
	end
	return nil
end

local function refreshMissions()
	local container = findMissionsContainer()
	if not container then
		warn("[Missions] ScrollingFrame not found")
		return
	end

	local template = container:FindFirstChild("Mission_f")
	if not template then
		warn("[Missions] Mission_f template not found")
		return
	end
	template.Visible = false

	-- Invoke server
	if not GetMissionsStatusRF then
		warn("[Missions] GetMissionsStatus RemoteFunction not available")
		return
	end

	local ok, response = pcall(function() return GetMissionsStatusRF:InvokeServer() end)
	if not ok or not response then
		warn("[Missions] failed to get missions status", response)
		return
	end

	local statusList = response.missions or response
	if not statusList then
		warn("[Missions] no missions data returned")
		return
	end

	-- Ensure claimable missions are shown first
	if type(statusList) == "table" then
		table.sort(statusList, function(a, b)
			if (a.CanClaim and not b.CanClaim) then
				return true
			elseif (b.CanClaim and not a.CanClaim) then
				return false
			end
			local ao = (a.Mission and a.Mission.Order) or 0
			local bo = (b.Mission and b.Mission.Order) or 0
			return ao < bo
		end)
	end

	-- Clear previous clones
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "Mission_f" then
			child:Destroy()
		end
	end

	-- Create entry for each mission; keep it simple: show objective in mission_text
	for i, missionData in ipairs(statusList) do
		local clone = template:Clone()
		clone.Name = "mission_" .. tostring(i)
		clone.Visible = true

		-- mission object reference (useful for deriving mission id)
		local missionObj = missionData.Mission or missionData

		-- Show claim frame if mission is claimable
		pcall(function()
			local claimFrame = clone:FindFirstChild("claim_frame", true) or clone:FindFirstChild("claim_frame")
			if claimFrame and claimFrame:IsA("Frame") then
				-- preserve original size; only toggle visibility
				local _origSize = claimFrame.Size
				claimFrame.Visible = (missionData.CanClaim == true)
				claimFrame.Size = _origSize
				-- find a clickable button inside claimFrame (TextButton/ImageButton)
				local btn = nil
				for _, d in ipairs(claimFrame:GetDescendants()) do
					if d:IsA("TextButton") or d:IsA("ImageButton") then
						btn = d
						break
					end
				end
				if btn and ClaimMissionRewardRE then
					btn.MouseButton1Click:Connect(function()
						-- determine mission id from missionObj or missionData
						local missionId = nil
						if missionObj and type(missionObj) == "table" then
							missionId = missionObj.ID or missionObj.Id or missionObj.id or missionObj.Name or missionObj.name
						end
						if not missionId then missionId = missionData.ID or missionData.Id or missionData.id or missionData.MissionId end
						if missionId then
							-- disable button briefly to avoid double-click
							pcall(function() btn.Active = false end)
							pcall(function()
								ClaimMissionRewardRE:FireServer(missionId)
							end)
							-- refresh UI shortly after claiming; server will also send update event
							delay(0.25, function()
								pcall(refreshMissions)
							end)
						else
							warn("[Missions] could not determine mission id to claim")
						end
					end)
				end
			end
		end)

		local missionObj = missionData.Mission or missionData
		local missionText = clone:FindFirstChild("mission_text") or clone:FindFirstChildWhichIsA("TextLabel", true)
		if missionText then
			local progressText = ""

			-- Damage mission: show total damage / next milestone threshold
			if missionObj and (missionObj.Type == "TotalDamage" or missionObj.ID == "total_damage") then
				local total = missionData.Progress or 0
				local progInto = missionData.ProgressToNextTier or 0
				local reqForNext = missionData.RequirementForNextTier or missionObj.Requirement or 0
				local nextThreshold = (total - progInto) + reqForNext
				progressText = string.format("Deal %s / %s", formatNumber(total), formatNumber(nextThreshold))

			-- Infinite waves: show current wave / next milestone wave
			elseif missionObj and (missionObj.Type == "InfiniteWaves" or missionObj.ID == "infinite_waves") then
				local current = missionData.Progress or 0
				local progInto = missionData.ProgressToNextTier or (current % (missionObj.Requirement or 1))
				local req = missionData.RequirementForNextTier or missionObj.Requirement or 0
				local nextThreshold = (current - progInto) + req
				progressText = string.format("Reach wave %d / %d", current, nextThreshold)

			-- Evolves: show current evolves in this tier / units needed
			elseif missionObj and (missionObj.Type == "EvolvesDone" or missionObj.ID == "evolves_infinite") then
				local cur = missionData.ProgressToNextTier or (missionData.Progress or 0) % (missionObj.Requirement or 1)
				local need = missionData.RequirementForNextTier or missionObj.Requirement or 0
				progressText = string.format("Evolve %d / %d units", cur, need)

			-- Summons: show current summons in this tier / times needed
			elseif missionObj and (missionObj.Type == "SummonsDone" or missionObj.ID == "summons_infinite") then
				local cur = missionData.ProgressToNextTier or (missionData.Progress or 0) % (missionObj.Requirement or 1)
				local need = missionData.RequirementForNextTier or missionObj.Requirement or 0
				progressText = string.format("Summon %d / %d times", cur, need)

			-- Next map (dynamic): prefer map DisplayName when available
			elseif missionObj and (missionObj.Type == "NextMap" or missionObj.ID == "next_map") then
				local obj = missionData.CurrentObjective
				if type(obj) == "table" and obj.MapID then
					local mod = findMapModuleById(obj.MapID)
					local display = obj.MapName or obj.MapID
					if mod and mod.DisplayName then display = mod.DisplayName end
					progressText = string.format("Complete all levels of %s", display)
				else
					progressText = missionData.DynamicDescription or (missionObj and missionObj.Description) or (missionObj and missionObj.Name) or "Mission"
				end

			-- Next story level: prefer map DisplayName and include level number
			elseif missionObj and (missionObj.Type == "NextStoryLevel" or missionObj.ID == "next_story_level") then
				local obj = missionData.CurrentObjective
				if type(obj) == "table" and obj.MapID and obj.Level then
					local mod = findMapModuleById(obj.MapID)
					local display = obj.MapName or obj.MapID
					if mod and mod.DisplayName then display = mod.DisplayName end
					progressText = string.format("Complete %s - Level %d", display, obj.Level)
				else
					progressText = missionData.DynamicDescription or (missionObj and missionObj.Description) or (missionObj and missionObj.Name) or "Mission"
				end

			else
				-- Fallback: show dynamic description or generic
				progressText = missionData.DynamicDescription or (missionObj and missionObj.Description) or (missionObj and missionObj.Name) or "Mission"
			end

			missionText.Text = progressText
		end

			-- Populate rewards area (clone Reward_icon for each reward)
			pcall(function()
				local rewardsRoot = clone:FindFirstChild("All_rewards")
				if not rewardsRoot then
					print("[Missions][Rewards] No All_rewards found in clone")
					return
				end
				print("[Missions][Rewards] Found All_rewards for mission", clone.Name)
				local iconTemplate = rewardsRoot:FindFirstChild("Reward_icon")
				if iconTemplate then
					print("[Missions][Rewards] Reward_icon template found")
					iconTemplate.Visible = false
				else
					print("[Missions][Rewards] Reward_icon template NOT found")
				end
					-- Determine rewards list from common fields (server may or may not include)
					local rewardsList = nil
					if missionData.Rewards then rewardsList = missionData.Rewards
					elseif missionData.rewards then rewardsList = missionData.rewards
					elseif missionData.Reward then rewardsList = missionData.Reward
					elseif missionData.reward then rewardsList = missionData.reward
					end
					-- Fallback: if no rewards in response, try to get from local MissionsCatalog
					if (not rewardsList or (type(rewardsList) == "table" and #rewardsList == 0)) and MissionsCatalog then
						local missionId = nil
						-- try common id fields
						if missionObj and (type(missionObj) == "table") then
							missionId = missionObj.ID or missionObj.Id or missionObj.id or missionObj.Name or missionObj.name
						end
						if not missionId then missionId = missionData.ID or missionData.Id or missionData.id or missionData.MissionId end
						local catMission = nil
						pcall(function() if missionId then catMission = MissionsCatalog:GetMission(tostring(missionId)) end end)
						if catMission then
							print("[Missions][Rewards] Using MissionsCatalog for mission", tostring(missionId))
							-- Build a simple rewardsList from catalog fields
							local built = {}
							local seenTypes = {}
							-- If Reward is a table, map its keys (Gems, Gold, etc.) to entries
							if catMission.Reward and type(catMission.Reward) == "table" then
								for k, v in pairs(catMission.Reward) do
									local key = tostring(k)
									local amount = tonumber(v)
									if amount and amount > 0 then
										local lower = key:lower()
										local entryType = nil
										if string.find(lower, "gem") or string.find(lower, "diamond") then
											entryType = "Gems"
										elseif string.find(lower, "gold") or string.find(lower, "coin") or string.find(lower, "coins") then
											entryType = "Gold"
										else
											entryType = key
										end
										if not seenTypes[entryType] then
											table.insert(built, { Type = entryType, Amount = amount })
											seenTypes[entryType] = true
										end
									end
								end
							end
							-- If mission has RewardTiers and MissionsCatalog available, compute appropriate gems
							if catMission.RewardTiers and type(catMission.RewardTiers) == "table" and MissionsCatalog then
								local progress = tonumber(missionData.Progress) or 0
								local gems = MissionsCatalog:GetRewardForDamageAmount(catMission, progress)
								if gems and gems > 0 and not seenTypes["Gems"] then
									table.insert(built, { Type = "Gems", Amount = gems })
									seenTypes["Gems"] = true
								end
							end
							if #built > 0 then rewardsList = built end
						end
					end
				if not rewardsList or (type(rewardsList) == "table" and #rewardsList == 0) then
					print("[Missions][Rewards] No rewards data for mission", clone.Name)
					return
				end
				-- If single reward object supplied, wrap into list
				if rewardsList and type(rewardsList) ~= "table" then
					rewardsList = { rewardsList }
				end
				if rewardsList and #rewardsList > 0 and iconTemplate then
					-- DEBUG: log rewardsList contents
					for li, vv in ipairs(rewardsList) do
						if type(vv) == "table" then
							print(string.format("[Missions][Rewards][DEBUG] rewardsList[%d] Type=%s Amount=%s", li, tostring(vv.Type or vv.type), tostring(vv.Amount or vv.amount or vv.Count or vv.count)))
						else
							print(string.format("[Missions][Rewards][DEBUG] rewardsList[%d] val=%s", li, tostring(vv)))
						end
					end
					-- remove previous reward clones (keep template)
					for _, existing in ipairs(rewardsRoot:GetChildren()) do
						if existing:IsA("Frame") and existing.Name:sub(1,7) == "reward_" then
							existing:Destroy()
						end
					end
					local created = 0
					for idx, r in ipairs(rewardsList) do
						local entry = r
						local typ = nil
						local amt = nil
						if type(entry) == "table" then
							typ = entry.Type or entry.type or entry.Id or entry.id or entry.Name or entry.name
							amt = entry.Amount or entry.Count or entry.amount or entry.count or entry.Value or entry.value or entry.qty or entry.Qty
							if not amt and entry[2] then amt = entry[2] end
							if not typ and entry[1] then typ = entry[1] end
						elseif type(entry) == "string" then
							typ = entry
						elseif type(entry) == "number" then
							amt = entry
						end
						amt = tonumber(amt) or 0
						local bgColor = Color3.fromRGB(200,200,200)
						local lower = (typ and tostring(typ):lower()) or ""
						if string.find(lower, "gem") or string.find(lower, "diamond") or string.find(lower, "gems") then
							bgColor = Color3.fromRGB(60,150,255)
						elseif string.find(lower, "gold") or string.find(lower, "coins") or string.find(lower, "coin") then
							bgColor = Color3.fromRGB(255,200,60)
						end
						local ico = iconTemplate:Clone()
						ico.Name = "reward_" .. tostring(idx)
						ico.Visible = true
						-- ensure visible and sized
						pcall(function()
							ico.BackgroundTransparency = 0
							ico.BackgroundColor3 = bgColor
							if ico.Size and ico.Size.Y and ico.Size.Y.Offset == 0 and ico.Size.Y.Scale == 0 then
								ico.Size = UDim2.new(0, 40, 0, 40)
							end
							-- set quantity text
							local qtyLabel = ico:FindFirstChild("Level", true) or ico:FindFirstChildWhichIsA("TextLabel", true)
							if qtyLabel and qtyLabel:IsA("TextLabel") then
								qtyLabel.Text = tostring(amt)
							end
							-- set image asset for known reward types (gems / gold)
							local imgLabel = ico:FindFirstChildWhichIsA("ImageLabel", true)
							if imgLabel then
								local imgAsset = nil
								if string.find(lower, "gem") or string.find(lower, "diamond") or string.find(lower, "gems") then
									imgAsset = "rbxassetid://101285032767311"
								elseif string.find(lower, "gold") or string.find(lower, "coins") or string.find(lower, "coin") then
									imgAsset = "rbxassetid://84965857011165"
								end
								if imgAsset then
									pcall(function()
										imgLabel.Image = imgAsset
										imgLabel.Visible = true
									end)
								end
							end
							ico.LayoutOrder = idx
							ico.Parent = rewardsRoot
							created = created + 1
							print(string.format("[Missions][Rewards] Created reward icon idx=%d typ=%s amt=%s", idx, tostring(typ), tostring(amt)))
						end)
						print(string.format("[Missions][Rewards] Total created for %s = %d", tostring(clone.Name), created))
						-- DEBUG: list final children under All_rewards
						local cnt = 0
						for _, c in ipairs(rewardsRoot:GetChildren()) do
							if c:IsA("Frame") then
								cnt = cnt + 1
								print(string.format("[Missions][Rewards][DEBUG] child[%d] name=%s Visible=%s Size=%s", cnt, tostring(c.Name), tostring(c.Visible), tostring(c.Size)))
							end
						end
						print(string.format("[Missions][Rewards][DEBUG] children_count=%d (frames)", cnt))
					end
				else
					print("[Missions][Rewards] No rewardsList or iconTemplate missing for", clone.Name)
				end
			end)

			clone.Parent = container
	end
end

-- Listen for server confirmation of mission claim/progress updates
if MissionProgressUpdatedRE then
	MissionProgressUpdatedRE.OnClientEvent:Connect(function(data)
		-- data: { success = bool, message = str, missionID = id }
		if data and data.missionID then
			print("[Missions] MissionProgressUpdated received for", data.missionID, "success=", tostring(data.success))
			-- Refresh missions list to reflect updated tiers/claimable state
			pcall(refreshMissions)
		end
	end)
end

local function slideOut()
	if isAnimating then return end
	isAnimating = true
	local tween = TweenService:Create(firstFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(originalPosition.X.Scale, originalPosition.X.Offset, 1.2, 0)
	})
	tween:Play()
	tween.Completed:Wait()
	firstFrame.Visible = false
	firstFrame.Position = originalPosition -- Restaurar posição original
	isAnimating = false
end

-- Toggle via atributos
script:GetAttributeChangedSignal("Show"):Connect(function()
	if script:GetAttribute("Show") == true then
		slideIn()
		-- Atualizar lista de missões quando abrir
		pcall(refreshMissions)
		script:SetAttribute("Show", false)
	end
end)

script:GetAttributeChangedSignal("Hide"):Connect(function()
	if script:GetAttribute("Hide") == true then
		slideOut()
		script:SetAttribute("Hide", false)
	end
end)

-- Botão fechar
closeButton.MouseButton1Click:Connect(function()
	slideOut()
end)

print("[Missions] UI loaded")