-- DevProducts.server.lua
-- Handles Developer Product purchases (gems and gold packs).
--
-- SETUP: Create each product in the Roblox Creator Dashboard under
--   Monetization -> Developer Products, then replace the productId = 0
--   placeholders below with the real numeric IDs.
--
-- Gold in-game maps to profile.Account.Coins
-- Gems in-game maps to profile.Account.Gems

local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService   = game:GetService("DataStoreService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local ScriptsFolder      = ReplicatedStorage:WaitForChild("Scripts")
local ProfileService     = require(ScriptsFolder:WaitForChild("ProfileService"))
local AccountLeveling    = require(ScriptsFolder:WaitForChild("AccountLeveling"))

-- Remotes created by Remotes.server.lua — wait until they exist
local remotesFolder    = ReplicatedStorage:WaitForChild("Remotes")
local ProfileUpdatedRE = remotesFolder:WaitForChild("ProfileUpdated")

-- Separate DataStore used only to deduplicate receipts and prevent double-grants.
-- Keys: "r_<receiptId>" = 1
local ReceiptStore = DataStoreService:GetDataStore("DevProductReceipts_v1")

-- ────────────────────────────────────────────────────────────────────────────
-- PRODUCT CATALOG
-- Replace productId = 0 with the real Roblox Developer Product ID for each entry.
-- ────────────────────────────────────────────────────────────────────────────
local PRODUCT_CATALOG = {
	-- Gems Packs
	{ productId = 3550675126, sku = "gems_25",   type = "gems", amount = 100,    name = "Gems Pack - 100"    },  -- 25 R$
	{ productId = 3550675228, sku = "gems_100",  type = "gems", amount = 500,    name = "Gems Pack - 500"    },  -- 100 R$
	{ productId = 3550675310, sku = "gems_200",  type = "gems", amount = 1250,   name = "Gems Pack - 1,250"  },  -- 200 R$
	{ productId = 3550675468, sku = "gems_400",  type = "gems", amount = 3000,   name = "Gems Pack - 3,000"  },  -- 400 R$
	{ productId = 3550675595, sku = "gems_800",  type = "gems", amount = 7000,   name = "Gems Pack - 7,000"  },  -- 800 R$
	{ productId = 3550675697, sku = "gems_1600", type = "gems", amount = 15000,  name = "Gems Pack - 15,000" },  -- 1600 R$

	-- Gold Packs  (gold = profile.Account.Coins in-game)
	{ productId = 3550675827, sku = "gold_100",  type = "gold", amount = 10000,  name = "Gold Pack - 10,000"  },  -- 100 R$
	{ productId = 3550675943, sku = "gold_200",  type = "gold", amount = 25000,  name = "Gold Pack - 25,000"  },  -- 200 R$
	{ productId = 3550676017, sku = "gold_400",  type = "gold", amount = 70000,  name = "Gold Pack - 70,000"  },  -- 400 R$
	{ productId = 3550676072, sku = "gold_800",  type = "gold", amount = 200000, name = "Gold Pack - 200,000" },  -- 800 R$
	{ productId = 3550676148, sku = "gold_1600", type = "gold", amount = 500000, name = "Gold Pack - 500,000" },  -- 1600 R$
}

-- Build lookup table: productId -> catalog entry (skips entries left at 0)
local PRODUCTS = {}
for _, entry in ipairs(PRODUCT_CATALOG) do
	if entry.productId ~= 0 then
		PRODUCTS[entry.productId] = entry
	end
end

-- Revive (single token) for maps that support manual revive (village/bleach/namek)
table.insert(PRODUCT_CATALOG, { productId = 3553813106, sku = "revive_1", type = "revive", amount = 1, name = "Revive" })

-- ────────────────────────────────────────────────────────────────────────────
-- RECEIPT DEDUPLICATION
-- Uses UpdateAsync so the check-and-set is atomic — safe even under retries.
-- Returns true if this is the first time we see this receiptId.
-- ────────────────────────────────────────────────────────────────────────────
local function markReceiptUsed(receiptId)
	local key = "r_" .. tostring(receiptId)
	local alreadyProcessed = false
	local ok, err = pcall(function()
		ReceiptStore:UpdateAsync(key, function(existing)
			if existing == 1 then
				alreadyProcessed = true
				return nil  -- return nil = do not overwrite
			end
			return 1        -- mark as processed
		end)
	end)
	if not ok then
		warn("[DevProducts] ReceiptStore:UpdateAsync failed for", receiptId, err)
		-- Conservative: do NOT grant on DataStore error to avoid double-grants
		return false, "DataStoreError"
	end
	if alreadyProcessed then
		return false, "AlreadyProcessed"
	end
	return true
end

-- ────────────────────────────────────────────────────────────────────────────
-- GRANT REWARD
-- Mutates the in-memory profile directly then triggers a save + client update.
-- Returns true/false.
-- ────────────────────────────────────────────────────────────────────────────
local function grantReward(player, product)
	local profile = ProfileService:Get(player)
	if not profile then
		warn("[DevProducts] No profile for", player.Name)
		return false
	end

	local acc = profile.Account
	if product.type == "gems" then
		acc.Gems = (acc.Gems or 0) + product.amount
		print(string.format("[DevProducts] +%d Gems -> %s (sku=%s)", product.amount, player.Name, product.sku))
	elseif product.type == "gold" then
		acc.Coins = (acc.Coins or 0) + product.amount
		print(string.format("[DevProducts] +%d Gold -> %s (sku=%s)", product.amount, player.Name, product.sku))
	elseif product.type == "revive" then
		acc.Revives = (acc.Revives or 0) + (product.amount or 1)
		print(string.format("[DevProducts] +%d Revive(s) -> %s (sku=%s)", product.amount or 1, player.Name, product.sku))
	else
		warn("[DevProducts] Unknown product type:", product.type)
		return false
	end

	-- Persist to DataStore
	local saveOk, saveErr = ProfileService:Save(player)
	if not saveOk then
		warn("[DevProducts] Save failed after grant:", saveErr)
		-- Reward was applied in-memory; return true so Roblox marks receipt done
		-- and does not retry indefinitely. It will be lost if the server crashes
		-- before the next auto-save, which is an acceptable trade-off vs double-granting.
	end

	-- Push updated account snapshot to the client (full snapshot so XP bar doesn't reset)
	pcall(function()
		ProfileUpdatedRE:FireClient(player, {
			account = AccountLeveling:GetSnapshot(profile)
		})
	end)

	return true
end

-- ────────────────────────────────────────────────────────────────────────────
-- PROCESS RECEIPT  (must be assigned only once per server)
-- ────────────────────────────────────────────────────────────────────────────
MarketplaceService.ProcessReceipt = function(receiptInfo)
	local productId = receiptInfo.ProductId
	local playerId  = receiptInfo.PlayerId
	local receiptId = receiptInfo.PurchaseId

	-- Look up product
	local product = PRODUCTS[productId]
	if not product then
		-- Not one of our products; let Roblox mark it as handled so it doesn't retry forever
		warn("[DevProducts] Unknown productId:", productId)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Get player from userId (they might have left)
	local player = game:GetService("Players"):GetPlayerByUserId(playerId)
	if not player then
		-- Player left — return NotProcessedYet so Roblox retries when they rejoin
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Deduplicate
	local isNew, dedupeErr = markReceiptUsed(receiptId)
	if not isNew then
		if dedupeErr == "AlreadyProcessed" then
			-- Already granted; safe to acknowledge
			return Enum.ProductPurchaseDecision.PurchaseGranted
		else
			-- DataStore error — do not acknowledge; Roblox will retry later
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end

	-- Grant reward
	local ok = grantReward(player, product)
	if not ok then
		-- Rollback the receipt mark so Roblox retries
		pcall(function()
			ReceiptStore:RemoveAsync("r_" .. tostring(receiptId))
		end)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

print("[DevProducts] ProcessReceipt handler registered —", #PRODUCT_CATALOG, "products in catalog")
