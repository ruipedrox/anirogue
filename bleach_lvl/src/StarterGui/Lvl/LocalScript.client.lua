local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- UI nodes (wait safely to avoid nils)
local gui = script.Parent
local lvlF = gui:FindFirstChild("lvlF") or gui:WaitForChild("lvlF", 5)
local label = lvlF and (lvlF:FindFirstChild("Text") or lvlF:WaitForChild("Text", 5))

local function safeSet(text)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function setLevelText(lv)
	safeSet("Level: " .. tostring(lv))
end

-- Robust bind with retries and event listeners
local levelValue -- current bound value
local function bindLevel(timeout)
	timeout = timeout or 10
	local t0 = os.clock()
	local stats = player:FindFirstChild("Stats")
	while (not stats) and (os.clock() - t0 < timeout) do
		task.wait(0.1)
		stats = player:FindFirstChild("Stats")
	end
	if not stats then
		setLevelText("?")
		warn("[LevelUI] Stats folder não apareceu a tempo.")
		return false
	end
	local t1 = os.clock()
	local lvl = stats:FindFirstChild("Level")
	while (not lvl) and (os.clock() - t1 < timeout) do
		task.wait(0.1)
		lvl = stats:FindFirstChild("Level")
	end
	if not lvl then
		setLevelText("?")
		warn("[LevelUI] Level value não apareceu a tempo.")
		return false
	end
	levelValue = lvl
	setLevelText(levelValue.Value)
	levelValue.Changed:Connect(function()
		setLevelText(levelValue.Value)
	end)

	-- Rebind if Stats/Level get recreated during restart
	stats.ChildAdded:Connect(function(child)
		if child.Name == "Level" then
			task.defer(function()
				bindLevel(2)
			end)
		end
	end)
	player.ChildAdded:Connect(function(child)
		if child.Name == "Stats" then
			task.defer(function()
				bindLevel(2)
			end)
		end
	end)
	return true
end

if not bindLevel(10) then
	-- keep placeholder; a later event will rebind
	safeSet("Level: ?")
end

-- (Opcional) Escuta RemoteEvent se quiseres animar ou fazer efeitos no level up
local ok, eventsFolder = pcall(function()
	return ReplicatedStorage:WaitForChild("R_Events", 5)
end)
if ok and eventsFolder then
	local ev = eventsFolder:FindFirstChild("Level_up")
	if ev and ev:IsA("RemoteEvent") then
		ev.OnClientEvent:Connect(function(newLevel)
			setLevelText(newLevel)
			-- Abrir ofertas de cartas no level up (se função global existir)
			local function tryShow()
				local ok2, fn = pcall(function() return _G.ShowCardOffers end)
				if ok2 and type(fn) == "function" then
					fn(true)
					return true
				end
				-- fallback BindableEvent
				local evs = ReplicatedStorage:FindFirstChild("R_Events")
				if evs then
					local be = evs:FindFirstChild("ShowCardOffers")
					if be and be:IsA("BindableEvent") then
						be:Fire(true)
						return true
					end
				end
				return false
			end
			-- Small delay to allow the server to send an authoritative card offer (Remotes.LevelUp)
			-- This is important after restart/next-level where timing can cause the client to open
			-- a local offer UI before PendingOffers exists on the server.
			task.wait(0.25)
			for _=1,5 do
				if tryShow() then break end
				task.wait(0.2)
			end
		end)
	end
end