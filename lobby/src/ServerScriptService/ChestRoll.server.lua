-- Chest item roll server logic: grants random items on request
-- Creates Remotes.RequestChestRoll (RemoteFunction)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Ensure Remotes folder exists
local remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local RequestChestRollRF = remotes:FindFirstChild("RequestChestRoll")
if not RequestChestRollRF then
	RequestChestRollRF = Instance.new("RemoteFunction")
	RequestChestRollRF.Name = "RequestChestRoll"
	RequestChestRollRF.Parent = remotes
end

-- Lazy requires to avoid errors on studio reload ordering
local function getProfileService()
	local scriptsFolder = ReplicatedStorage:FindFirstChild("Scripts")
	if not scriptsFolder then return nil end
	local mod = scriptsFolder:FindFirstChild("ProfileService")
	if not mod then return nil end
	local ok, svc = pcall(require, mod)
	if ok then return svc end
	return nil
end

local function collectItemPools()
	-- Basic lists by category (names only). We'll also build an index by rarity below.
	local pools = {
		Weapons = {},
		Armors = {},
		Rings = {},
	}
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local items = shared and shared:FindFirstChild("Items")
	if not items then return pools end
	for catName, list in pairs(pools) do
		local catFolder = items:FindFirstChild(catName)
		if catFolder then
			for _, child in ipairs(catFolder:GetChildren()) do
				if child:IsA("Folder") then
					table.insert(list, child.Name)
				end
			end
		end
	end
	return pools
end

local poolsCache = nil
local rarityIndexCache = nil -- { all = {rarity = { {cat=..., name=...}, ...}}, byCategory = { [cat] = { rarity = { ... }}} }
local function getPools()
	if not poolsCache then
		poolsCache = collectItemPools()
	end
	return poolsCache
end

local lastRollAt = {} -- anti-spam per user
local COOLDOWN = 0.5

-- Costs (Coins) for chest item summons
local SINGLE_ROLL_COST = 1000
local TEN_ROLL_COST = 9000

local function randChoice(t)
	local n = #t
	if n == 0 then return nil end
	return t[math.random(1, n)]
end

-- Map rarity labels/numbers to internal keys and weights
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
	-- Mythic must be excluded from drops entirely; map to special key
	if s:find("myth") or s:find("miti") or s:find("mít") then return "mitico" end
	if s:find("legend") or s:find("lend") then return "lendario" end
	if s:find("epic") or s:find("épico") or s:find("epico") then return "epico" end
	if s:find("rare") or s:find("raro") then return "raro" end
	if s:find("common") or s:find("comum") then return "comum" end
	return "comum"
end

-- Fixed rarity probabilities per roll (mythic excluded)
local FIXED_RARITY_PROBS = {
	lendario = 0.02,
	epico = 0.08,
	raro = 0.30,
	comum = 0.60,
}

-- Inspect a template's Stats to resolve its rarity key
local function getTemplateRarity(catName, templateName)
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local items = shared and shared:FindFirstChild("Items")
	local catFolder = items and items:FindFirstChild(catName)
	local tplFolder = catFolder and catFolder:FindFirstChild(templateName)
	local statsModule = tplFolder and tplFolder:FindFirstChild("Stats")
	local stats = nil
	if statsModule and statsModule:IsA("ModuleScript") then
		local ok, mod = pcall(require, statsModule)
		if ok and type(mod) == "table" then stats = mod end
	end
	if stats then
		if stats.rarity ~= nil then return mapRarityKey(stats.rarity) end
		if stats.Rarity ~= nil then return mapRarityKey(stats.Rarity) end
		if stats.stars ~= nil then return mapRarityKey(stats.stars) end
	end
	return mapRarityKey(templateName)
end

-- Build and cache an index of templates per rarity across all categories
local function buildRarityIndex()
	if rarityIndexCache then return rarityIndexCache end
	local pools = getPools()
	local index = { all = { comum = {}, raro = {}, epico = {}, lendario = {} }, byCategory = {} }
	for catName, list in pairs(pools) do
		index.byCategory[catName] = { comum = {}, raro = {}, epico = {}, lendario = {} }
		for _, tpl in ipairs(list) do
			local rk = getTemplateRarity(catName, tpl)
			-- Completely skip mythic templates for RNG drops
			if rk == "mitico" or rk == "mythic" or rk == "exclude" then
				rk = nil
			end
			if rk and index.all[rk] then
				table.insert(index.all[rk], { cat = catName, name = tpl })
				table.insert(index.byCategory[catName][rk], tpl)
			else
				-- unknown rarity -> treat as common
				if rk ~= nil then
					table.insert(index.all.comum, { cat = catName, name = tpl })
					table.insert(index.byCategory[catName].comum, tpl)
				end
			end
		end
	end
	rarityIndexCache = index
	return index
end

local function chooseRarityByProbs()
	local r = math.random()
	local acc = 0
	for _, key in ipairs({"lendario","epico","raro","comum"}) do
		acc += FIXED_RARITY_PROBS[key] or 0
		if r <= acc then return key end
	end
	return "comum"
end

RequestChestRollRF.OnServerInvoke = function(player, count)
	count = tonumber(count) or 1
	if count < 1 then count = 1 end
	if count > 10 then count = 10 end
	-- cooldown
	local now = os.clock()
	local prev = lastRollAt[player.UserId] or 0
	if now - prev < COOLDOWN then
		return { ok = false, error = "cooldown", wait = COOLDOWN - (now - prev) }
	end
	lastRollAt[player.UserId] = now

	local svc = getProfileService()
	if not svc or type(svc.AddItem) ~= "function" then
		warn("[ChestRoll] ProfileService not available or missing AddItem")
		return { ok = false, error = "no-profile-service" }
	end

	-- Validate and deduct Coins cost (server-authoritative)
	local profile = svc:Get(player) or svc:CreateOrLoad(player)
	local cost = (count == 10) and TEN_ROLL_COST or (SINGLE_ROLL_COST * count)
	local coins = profile and profile.Account and tonumber(profile.Account.Coins) or 0
	if coins < cost then
		return { ok = false, error = "not-enough-gold", required = cost, coins = coins }
	end
	-- Deduct coins up-front
	pcall(function()
		svc:ApplyAccountDelta(player, { Coins = -cost })
	end)

	local pools = getPools()
	local w = #(pools.Weapons or {})
	local a = #(pools.Armors or {})
	local rg = #(pools.Rings or {})
	if (w + a + rg) == 0 then
		warn("[ChestRoll] Nenhum template de item encontrado em Shared/Items (Weapons/Armors/Rings).")
		return { ok = false, error = "no-item-templates" }
	end
	print(string.format("[ChestRoll] Pools -> Weapons=%d Armors=%d Rings=%d", w, a, rg))
	local rarityIndex = buildRarityIndex()
	-- For visibility, we can log counts per rarity once per invocation
	local cC = #(rarityIndex.all.comum)
	local cR = #(rarityIndex.all.raro)
	local cE = #(rarityIndex.all.epico)
	local cL = #(rarityIndex.all.lendario)
	print(string.format("[ChestRoll] RarityIndex -> comum=%d raro=%d epico=%d lendario=%d", cC, cR, cE, cL))
	local granted = {}
	for i = 1, count do
		-- Choose rarity first by fixed probabilities
		local wantRarity = chooseRarityByProbs()
		local pickEntry = nil
		-- Try desired rarity; if no template exists, degrade to next lower rarity
		local order = { wantRarity }
		if wantRarity == "lendario" then table.insert(order, "epico"); table.insert(order, "raro"); table.insert(order, "comum")
		elseif wantRarity == "epico" then table.insert(order, "raro"); table.insert(order, "comum")
		elseif wantRarity == "raro" then table.insert(order, "comum") end
		for _, rk in ipairs(order) do
			local list = rarityIndex.all[rk]
			if list and #list > 0 then
				pickEntry = list[math.random(1, #list)]
				break
			end
		end
		-- As final fallback, pick anything available
		if not pickEntry then
			local any = rarityIndex.all.comum
			if any and #any > 0 then pickEntry = any[math.random(1, #any)] end
		end
		local cat, tpl = "Weapons", "Unknown"
		if pickEntry then
			cat = pickEntry.cat; tpl = pickEntry.name
		else
			-- fallback to any from pools
			local fallbackCats = { "Weapons", "Armors", "Rings" }
			for _ = 1, 6 do
				local try = fallbackCats[math.random(1, #fallbackCats)]
				if pools[try] and #pools[try] > 0 then
					cat = try; tpl = pools[try][math.random(1, #pools[try])]
					break
				end
			end
		end
		local okAdd, res = pcall(function()
			-- opts: Level defaults to 1; let service decide Quality
			return svc:AddItem(player, cat, tpl, { Level = 1 })
		end)
		local instId = okAdd and res or nil
		if not instId then
			warn(string.format("[ChestRoll] AddItem falhou para %s/%s (ok=%s, res=%s)", tostring(cat), tostring(tpl), tostring(okAdd), tostring(res)))
		end
		table.insert(granted, { category = cat, template = tpl, instanceId = instId })
	end
	print(string.format("[ChestRoll] Granted %d items to %s (cost=%d)", #granted, player.Name, cost))
	-- Fire a ProfileUpdated with a fresh snapshot so client UIs (Equip, HUD) refresh
	local profileUpdated = remotes:FindFirstChild("ProfileUpdated")
	if profileUpdated and typeof(profileUpdated.FireClient) == "function" then
		local okSnap, snap = pcall(function()
			local profile = svc:Get(player) or svc:CreateOrLoad(player)
			return svc:BuildClientSnapshot(profile)
		end)
		if okSnap and snap then
			profileUpdated:FireClient(player, { full = snap })
		else
			warn("[ChestRoll] BuildClientSnapshot falhou; UI pode não atualizar até próximo GetProfile")
		end
	end
	-- Include simple cost/coins info in response for client-side UX if needed
	local coinsAfter = (svc:Get(player) and svc:Get(player).Account and svc:Get(player).Account.Coins) or nil
	return { ok = true, granted = granted, cost = cost, coins = coinsAfter }
end
