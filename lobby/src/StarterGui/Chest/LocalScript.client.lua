-- Chest UI LocalScript: robust handshake and open flow (mirrors Summon UI pattern)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local openRemote = remotes:WaitForChild("Open_Chest")
local ChestClientReadyRE = remotes:WaitForChild("ChestClientReady")
local openChestFunction = remotes:WaitForChild("OpenChestFunction")

-- Resolve root frame safely
local root = script.Parent
print("[ChestUI] LocalScript parent:", root, root and root.ClassName)
local frame = root:FindFirstChild("Frame") or root:FindFirstChild("Frame", true)
if not frame then
	local ok, res = pcall(function() return root:WaitForChild("Frame", 5) end)
	if ok and res then frame = res end
end
if not frame then
	warn("[ChestUI] Frame não encontrado! Parent:", tostring(root))
	return
end

-- Start hidden/off-screen
pcall(function()
	frame.Visible = false
	frame.Position = UDim2.new(0, 0, -1, 0)
end)

local isOpen = false
local receivedEvent = false

local function openChestUI()
	if isOpen then
		print("[ChestUI] UI já aberta.")
		return
	end
	isOpen = true
	frame.Visible = true
	frame.Position = UDim2.new(0, 0, -1, 0)

	-- Hide any confirm panels if they exist (optional layout)
	local confirm1 = frame:FindFirstChild("U_Sure_1") or frame:FindFirstChild("U_Sure_1", true)
	local confirm10 = frame:FindFirstChild("U_Sure_10") or frame:FindFirstChild("U_Sure_10", true)
	if confirm1 then confirm1.Visible = false end
	if confirm10 then confirm10.Visible = false end

	local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(frame, tweenInfo, { Position = UDim2.new(0, 0, 0, 0) }):Play()
	-- Wire summon buttons for item rolls (1 and 10)
	local okSummon, summonRoot = pcall(function() return frame:WaitForChild("Summon", 2) end)
	if okSummon and summonRoot then
		local buttons = summonRoot:FindFirstChild("Buttons")
		if buttons then
			local one = buttons:FindFirstChild("1_summon")
			local oneBtn = one and one:FindFirstChild("1_b")
			local ten = buttons:FindFirstChild("10_summon")
			local tenBtn = ten and ten:FindFirstChild("10_b")
			local inFlight = false
			-- Optional: detect a warning label placeholder to show errors (e.g., NotEnoughGold)
			local warnLabel = frame:FindFirstChild("S_warn") or frame:FindFirstChild("WarnLabel", true)
			local wiredAny = false
			-- Helpers to resolve item icon and stars from ReplicatedStorage.Shared.Items
			local function resolveStatsModule(itemType, templateName)
				local Shared = ReplicatedStorage:FindFirstChild("Shared")
				if not Shared then return nil end
				local ItemsFolder = Shared:FindFirstChild("Items")
				if not ItemsFolder then return nil end
				local categoryFolder = ItemsFolder:FindFirstChild(itemType)
				if not categoryFolder then return nil end
				local templateFolder = categoryFolder:FindFirstChild(templateName)
				if not templateFolder then return nil end
				local statsModule = templateFolder:FindFirstChild("Stats")
				if statsModule and statsModule:IsA("ModuleScript") then
					local ok, stats = pcall(require, statsModule)
					if ok then return stats end
				end
				return nil
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

			local function rarityToStars(rk)
				-- Map item rarity to a star-like scale used by Roll gradient
				if rk == "lendario" then return 5 end
				if rk == "epico" then return 4 end
				if rk == "raro" then return 3 end
				return 2 -- comum
			end

			local function resolveItemImageAndStars(category, templateName)
				local stats = resolveStatsModule(category, templateName)
				local img = (stats and (stats.iscon or stats.icon or stats.Icon)) or "rbxassetid://0"
				local stars = nil
				if stats then
					if stats.stars ~= nil then
						stars = tonumber(stats.stars)
					else
						local rk = nil
						if stats.rarity ~= nil then rk = mapRarityKey(stats.rarity)
						elseif stats.Rarity ~= nil then rk = mapRarityKey(stats.Rarity) end
						if rk then stars = rarityToStars(rk) end
					end
				end
				return { image = tostring(img), stars = stars }
			end

			local function playRollAnimationFor(granted)
				-- Find the Roll ScreenGui and its PlayRoll BindableFunction
				local pg = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui")
				local rollGui = pg:FindFirstChild("Roll")
				if not rollGui then
					-- Fallback: search any ScreenGui under PlayerGui that contains a BindableFunction named PlayRoll
					for _, g in ipairs(pg:GetChildren()) do
						if g:IsA("ScreenGui") then
							for _, d in ipairs(g:GetDescendants()) do
								if d:IsA("BindableFunction") and d.Name == "PlayRoll" then
									rollGui = g
									break
								end
							end
							if rollGui then break end
						end
					end
					if not rollGui then
						warn("[ChestUI] Roll UI não encontrado em PlayerGui; a animação de roll não será exibida.")
						return
					end
				end
				-- Guarantee the ScreenGui is enabled and the main frame is visible before invoking
				pcall(function() if rollGui:IsA("ScreenGui") then rollGui.Enabled = true end end)
				local rollFrame = rollGui:FindFirstChild("Frame") or rollGui:FindFirstChild("Frame", true)
				pcall(function() if rollFrame and rollFrame:IsA("GuiObject") then rollFrame.Visible = true end end)
				-- Ensure Roll is on top of Chest by bumping DisplayOrder temporarily
				pcall(function()
					if rollGui:IsA("ScreenGui") and root and root:IsA("ScreenGui") then
						rollGui.DisplayOrder = math.max(rollGui.DisplayOrder or 0, (root.DisplayOrder or 0) + 10)
					end
				end)
				local playFn = nil
				local deadline = os.clock() + 2.0
				while not playFn and os.clock() < deadline do
					for _, d in ipairs(rollGui:GetDescendants()) do
						if d:IsA("BindableFunction") and d.Name == "PlayRoll" then
							playFn = d; break
						end
					end
					if not playFn then task.wait(0.05) end
				end
				if not playFn then
					warn("[ChestUI] BindableFunction 'PlayRoll' não encontrado dentro do Roll UI.")
					return
				end
				local images = {}
				for _, g in ipairs(granted or {}) do
					local entry = resolveItemImageAndStars(g.category, g.template)
					table.insert(images, entry)
				end
				if #images == 0 then return end
				-- Hide Chest UI during roll to avoid layering issues; restore after animation returns
				local wasOpen = isOpen
				pcall(function()
					if frame and frame:IsA("GuiObject") then frame.Visible = false end
				end)
				local okInvoke, res = pcall(function() return playFn:Invoke(images) end)
				pcall(function()
					if wasOpen and frame and frame:IsA("GuiObject") then
						frame.Visible = true
						frame.Position = UDim2.new(0,0,0,0)
					end
				end)
				if not okInvoke then
					warn("[ChestUI] Falha ao invocar PlayRoll:", res)
				end
			end

			local function setButtonsEnabled(enabled)
				local function setBtn(b, en)
					if not b then return end
					pcall(function()
						b.Active = en
						b.AutoButtonColor = en
						b.ZIndex = en and (b.ZIndex) or (b.ZIndex)
						b.Modal = not en
					end)
				end
				setBtn(oneBtn, enabled)
				setBtn(tenBtn, enabled)
				setBtn(one, enabled)
				setBtn(ten, enabled)
			end

			local function showWarn(text)
				if not warnLabel or not warnLabel:IsA("GuiObject") then
					warn("[ChestUI] WARN:", text)
					return
				end
				pcall(function()
					warnLabel.Visible = true
					if warnLabel:IsA("TextLabel") then warnLabel.Text = tostring(text) end
				end)
				task.delay(2.0, function()
					pcall(function() warnLabel.Visible = false end)
				end)
			end

			local function doRoll(n)
				if inFlight then return end
				inFlight = true
				setButtonsEnabled(false)
				local remotes = ReplicatedStorage:WaitForChild("Remotes")
				local rf = remotes:FindFirstChild("RequestChestRoll")
				if not rf or not rf.InvokeServer then
					warn("[ChestUI] RequestChestRoll RF não encontrado")
					inFlight = false; setButtonsEnabled(true); return
				end
				print(string.format("[ChestUI] Pedindo roll de %d itens...", n))
				local ok, res = pcall(function() return rf:InvokeServer(n) end)
				inFlight = false; setButtonsEnabled(true)
				if not ok or not res then
					warn("[ChestUI] Roll falhou:", ok, res and res.error)
					return
				end
				if res.ok ~= true then
					if res.error == "not-enough-gold" then
						local need = tonumber(res.required) or 0
						local have = tonumber(res.coins) or 0
						showWarn(string.format("Gold insuficiente: precisa de %d (tens %d)", need, have))
					else
						showWarn("Falha no roll: " .. tostring(res.error))
					end
					return
				end
				print(string.format("[ChestUI] Roll %d OK. itens= %d (cost=%s coinsAfter=%s)", n, #(res.granted or {}), tostring(res.cost), tostring(res.coins)))
				-- Trigger the Roll animation UI with the granted items
				pcall(function() playRollAnimationFor(res.granted or {}) end)
			end
			local function connectClick(gui, n)
				if not gui then return end
				if gui:GetAttribute("_RollWired") then return end
				gui:SetAttribute("_RollWired", true)
				if gui.Activated then
					gui.Activated:Connect(function() doRoll(n) end)
					wiredAny = true; return
				end
				if gui.MouseButton1Click then
					gui.MouseButton1Click:Connect(function() doRoll(n) end)
					wiredAny = true; return
				end
				if gui.InputBegan then
					gui.InputBegan:Connect(function(input)
						local t = input.UserInputType
						if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
							doRoll(n)
						end
					end)
					wiredAny = true; return
				end
			end
			if oneBtn then connectClick(oneBtn, 1) end
			if tenBtn then connectClick(tenBtn, 10) end
			-- Fallback: also wire the container frames (useful if 10_b is an ImageLabel and clicks are on parent)
			if one and not one:GetAttribute("_RollWired") then
				one:SetAttribute("_RollWired", true)
				if one.InputBegan then
					one.InputBegan:Connect(function(input)
						local t = input.UserInputType
						if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
							doRoll(1)
						end
					end)
					wiredAny = true
					print("[ChestUI] Wired fallback on 1_summon frame")
				end
			end
			if ten and not ten:GetAttribute("_RollWired") then
				ten:SetAttribute("_RollWired", true)
				if ten.InputBegan then
					ten.InputBegan:Connect(function(input)
						local t = input.UserInputType
						if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
							doRoll(10)
						end
					end)
					wiredAny = true
					print("[ChestUI] Wired fallback on 10_summon frame")
				end
			end
			if not wiredAny then
				warn("[ChestUI] Nenhum botão de roll foi ligado (verifica se 1_b/10_b são ImageButton ou aceita InputBegan)")
			end
		end
	end
	print("[ChestUI] UI aberta!")
end

local function closeChestUI()
	if not isOpen then return end
	local tweenInfo = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tw = TweenService:Create(frame, tweenInfo, { Position = UDim2.new(0, 0, -1, 0) })
	tw:Play()
	tw.Completed:Connect(function()
		frame.Visible = false
		isOpen = false
		print("[ChestUI] UI fechada!")
	end)
end

-- Wire exit button with fixed path: Frame > Summon > Buttons > exit (simplified)
do
	local ok, summonFrame = pcall(function() return frame:WaitForChild("Summon", 2) end)
	local buttons = ok and summonFrame and summonFrame:FindFirstChild("Buttons")
	local exitBtn = summonFrame:FindFirstChild("exit")
	if exitBtn and (exitBtn:IsA("ImageButton") or exitBtn:IsA("TextButton")) then
		exitBtn.MouseButton1Click:Connect(closeChestUI)
		print("[ChestUI] Exit wired (Summon/Buttons/exit)")
	else
		-- Minimal fallback: try direct child named 'exit' under frame
		local fallback = frame:FindFirstChild("exit")
		if fallback and (fallback:IsA("ImageButton") or fallback:IsA("TextButton")) then
			fallback.MouseButton1Click:Connect(closeChestUI)
			print("[ChestUI] Exit wired (frame/exit)")
		else
			print("[ChestUI] Botão 'exit' não encontrado em Summon/Buttons nem em Frame.")
		end
	end
end

-- Readiness handshake loop (until first open event arrives)
local function keepSignalingReady()
	while not receivedEvent do
		ChestClientReadyRE:FireServer()
		print("[ChestUI] Cliente pronto (handshake tick).")
		task.wait(0.5)
	end
end
task.spawn(keepSignalingReady)

-- RemoteEvent path
openRemote.OnClientEvent:Connect(function(payload)
	print("[ChestUI] Open_Chest recebido:", payload)
	receivedEvent = true
	if payload == "Chest" then
		openChestUI()
	end
end)

-- RemoteFunction path (explicit ack)
openChestFunction.OnClientInvoke = function(payload)
	print("[ChestUI] OpenChestFunction OnClientInvoke:", payload)
	if payload == "Chest" then
		openChestUI()
		return true
	end
	return false
end

-- Initial ready signal
ChestClientReadyRE:FireServer()
print("[ChestUI] Ready sinalizado ao servidor.")