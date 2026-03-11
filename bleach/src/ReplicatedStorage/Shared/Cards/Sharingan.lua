-- Sharingan.lua
-- Every `cooldown` seconds, activates a crit buff for `duration` seconds.
-- During the buff window, grants CritChancePercent and CritDamagePercent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")
local SFXHelper = require(ScriptsFolder:WaitForChild("SFXHelper"))
local SHARINGAN_SFX_ID = 74620269027862

local def = {
	Name = "Sharingan",
	Rarity = "Legendary",
	Type = "Passive",
	MaxLevel = 5,
	Description = "Periodically activates the Sharingan for a burst of critical power.\n\nLv1: +25% crit chance, +100% crit dmg for 5s every 15s\nLv2: +35% crit chance, +150% crit dmg for 6s every 13s\nLv3: +45% crit chance, +200% crit dmg for 7s every 11s\nLv4: +55% crit chance, +250% crit dmg for 8s every 9s\nLv5: +70% crit chance, +300% crit dmg for 10s every 7s"
}

local statsPerLevel = {
	[1] = { critChancePercent = 25, critDamagePercent = 100, duration = 5,  cooldown = 15 },
	[2] = { critChancePercent = 35, critDamagePercent = 150, duration = 6,  cooldown = 13 },
	[3] = { critChancePercent = 45, critDamagePercent = 200, duration = 7,  cooldown = 11 },
	[4] = { critChancePercent = 55, critDamagePercent = 250, duration = 8,  cooldown = 9  },
	[5] = { critChancePercent = 70, critDamagePercent = 300, duration = 10, cooldown = 7  },
}

local ActiveByUserId = {}

local function addUpgrade(player, name, delta)
	if type(delta) ~= "number" or delta == 0 then return end
	local upgrades = player:FindFirstChild("Upgrades")
	if not upgrades then
		upgrades = Instance.new("Folder")
		upgrades.Name = "Upgrades"
		upgrades.Parent = player
	end
	local u = upgrades:FindFirstChild(name)
	if not u then
		u = Instance.new("NumberValue")
		u.Name = name
		u.Value = 0
		u.Parent = upgrades
	end
	u.Value = u.Value + delta
	local stats = player:FindFirstChild("Stats")
	if stats then
		local s = stats:FindFirstChild(name)
		if not s then
			s = Instance.new("NumberValue")
			s.Name = name
			s.Value = 0
			s.Parent = stats
		end
		s.Value = s.Value + delta
	end
end

local function getDecalTexture()
	local tex = "rbxassetid://90261560441199" -- fallback: card image
	pcall(function()
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		local chars = shared and shared:FindFirstChild("Chars")
		local sasuke = chars and chars:FindFirstChild("Sasuke_5")
		local d = sasuke and sasuke:FindFirstChild("Sharingan")
		if d and d:IsA("Decal") then tex = d.Texture end
	end)
	return tex
end

local function showSharinganVisual(player, duration)
	local char = player.Character
	local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
	if not hrp then return end

	local texture = getDecalTexture()

	-- BillboardGui vira automaticamente para a câmara
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SharinganBillboard"
	billboard.Size = UDim2.new(0, 70, 0, 70)
	billboard.StudsOffset = Vector3.new(0, 5.5, 0)
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.Adornee = hrp
	billboard.Parent = hrp

	local img = Instance.new("ImageLabel")
	img.Size = UDim2.new(1, 0, 1, 0)
	img.Position = UDim2.new(0, 0, 0, 0)
	img.BackgroundTransparency = 1
	img.Image = texture
	img.Parent = billboard

	-- Animação de rotação no ImageLabel
	local rotAngle = 0
	local rotConn
	rotConn = RunService.Heartbeat:Connect(function(dt)
		if not billboard.Parent then rotConn:Disconnect() return end
		rotAngle = rotAngle + dt * 180 -- 180°/s
		img.Rotation = rotAngle % 360
	end)

	task.delay(duration, function()
		if rotConn then rotConn:Disconnect() end
		pcall(function() billboard:Destroy() end)
	end)
end

local function activateBuff(player, stats)
	addUpgrade(player, "CritChancePercent", stats.critChancePercent)
	addUpgrade(player, "CritDamagePercent", stats.critDamagePercent)

	-- SFX
	local char = player.Character
	local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
	if hrp then
		SFXHelper.playAt(hrp, SHARINGAN_SFX_ID, 0.9, { minDist = 15, maxDist = 80, lifetime = stats.duration + 0.5 })
	end

	-- Visual
	showSharinganVisual(player, stats.duration)

	task.delay(stats.duration, function()
		local data = ActiveByUserId[player.UserId]
		if data and data.buffActive then
			addUpgrade(player, "CritChancePercent", -stats.critChancePercent)
			addUpgrade(player, "CritDamagePercent", -stats.critDamagePercent)
			data.buffActive = false
		end
	end)
end

local function startLoop(player, level)
	local stats = statsPerLevel[level]
	if not stats then return end

	local data = { level = level, buffActive = false, cooldownAcc = 0, conn = nil }

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not player.Parent or not player.Character then
			conn:Disconnect()
			ActiveByUserId[player.UserId] = nil
			return
		end
		if ReplicatedStorage:GetAttribute("GamePaused") then return end

		local currentData = ActiveByUserId[player.UserId]
		if not currentData then conn:Disconnect() return end
		local currentStats = statsPerLevel[currentData.level] or stats

		if currentData.buffActive then return end

		currentData.cooldownAcc = currentData.cooldownAcc + dt
		if currentData.cooldownAcc >= currentStats.cooldown then
			currentData.cooldownAcc = 0
			currentData.buffActive = true
			activateBuff(player, currentStats)
		end
	end)

	data.conn = conn
	ActiveByUserId[player.UserId] = data

	-- Ativa imediatamente ao escolher a carta
	data.buffActive = true
	activateBuff(player, stats)
end

function def.OnCardAdded(player: Player, cardData, currentLevel: number)
	local maxLv = (type(cardData) == "table" and tonumber(cardData.maxLevel)) or def.MaxLevel
	local level = math.clamp(currentLevel or 1, 1, maxLv)

	-- Regista nível no RunTrack para que o CardPool saiba quando está no max level
	local cardId = (type(cardData) == "table" and cardData.id) or "Sasuke_Legendary_Sharingan"
	local runTrack = player:FindFirstChild("RunTrack")
	if not runTrack then
		runTrack = Instance.new("Folder")
		runTrack.Name = "RunTrack"
		runTrack.Parent = player
	end
	local myFolder = runTrack:FindFirstChild(cardId)
	if not myFolder then
		myFolder = Instance.new("Folder")
		myFolder.Name = cardId
		myFolder.Parent = runTrack
	end
	local lvlNV = myFolder:FindFirstChild("Level")
	if not lvlNV then
		lvlNV = Instance.new("IntValue")
		lvlNV.Name = "Level"
		lvlNV.Parent = myFolder
	end
	lvlNV.Value = level

	local existing = ActiveByUserId[player.UserId]
	if existing then
		existing.level = level
		return
	end
	startLoop(player, level)
	print(string.format("[Sharingan] Player %s started Sharingan loop Lv%d", player.Name, level))
end

function def.OnCardRemoved(player: Player, cardData)
	local data = ActiveByUserId[player.UserId]
	if not data then return end
	if data.conn then data.conn:Disconnect() end
	if data.buffActive then
		local stats = statsPerLevel[data.level]
		if stats then
			addUpgrade(player, "CritChancePercent", -stats.critChancePercent)
			addUpgrade(player, "CritDamagePercent", -stats.critDamagePercent)
		end
	end
	ActiveByUserId[player.UserId] = nil
	print(string.format("[Sharingan] Player %s deactivated Sharingan", player.Name))
end

game:GetService("Players").PlayerRemoving:Connect(function(player)
	local data = ActiveByUserId[player.UserId]
	if data and data.conn then data.conn:Disconnect() end
	ActiveByUserId[player.UserId] = nil
end)

return def
