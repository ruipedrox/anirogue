-- SummonModule.lua
-- Provides summon helpers: SummonOnce and SummonBulk
-- Expects a catalog table (array) where each entry contains at least:
-- { id = "Goku_3", stars = 3, ... }
-- Default probabilities: totals chosen so per-slot chances are:
-- 5★ single slot = 2.01%, each 4★ slot = 8.00% (2 slots -> 16%),
-- each 3★ slot = 27.33% (3 slots -> 81.99%). Totals sum to 100%.

local SummonModule = {}

-- Default configuration
SummonModule.config = {
    -- Per-rarity totals (percent). Use decimals to precisely represent the desired per-slot chances.
    -- 5 -> 2.01; 4 -> 16.00 (8.00 per slot for 2 slots); 3 -> 81.99 (27.33 per slot for 3 slots)
    probs = { [5] = 2.01, [4] = 16.00, [3] = 81.99 }, -- percentages, must sum to ~100 (we normalize anyway)
}

-- Public helper: compute per-slot chance percentages for a banner
-- banner: optional table with field `entries` (array). Each entry may include .rarity or .stars.
-- Returns: chances, counts
--  - chances: table mapping rarity -> per-slot percentage (e.g. chances[3] = 30.0)
--  - counts: table mapping rarity -> number of slots for that rarity in the banner
-- If banner is nil or malformed, a sensible default composition is assumed (1x5, 2x4, 3x3).
local function normalizeProbs(probs)
    local sum = 0
    for k,v in pairs(probs) do sum = sum + v end
    if sum <= 0 then
        -- fallback to defaults
        return { [5]=2, [4]=8, [3]=90 }
    end
    local out = {}
    for k,v in pairs(probs) do out[k] = v / sum end
    return out
end

-- Public helper: compute per-slot chance percentages for a banner
-- banner: optional table with field `entries` (array). Each entry may include .rarity or .stars.
-- Returns: chances, counts
--  - chances: table mapping rarity -> per-slot percentage (e.g. chances[3] = 30.0)
--  - counts: table mapping rarity -> number of slots for that rarity in the banner
-- If banner is nil or malformed, a sensible default composition is assumed (1x5, 2x4, 3x3).
function SummonModule.GetPerSlotChances(banner)
    -- Use normalized probs (fractions summing to 1)
    local norm = normalizeProbs(SummonModule.config.probs)
    -- Count slots by rarity
    local counts = {}
    if banner and type(banner) == "table" and type(banner.entries) == "table" then
        for _, entry in ipairs(banner.entries) do
            local r = nil
            if type(entry.rarity) == "number" then
                r = entry.rarity
            elseif type(entry.stars) == "number" then
                r = entry.stars
            end
            r = r or 3
            counts[r] = (counts[r] or 0) + 1
        end
    else
        -- Default 6-entry banner: 1 x 5★, 2 x 4★, 3 x 3★
        counts = { [5] = 1, [4] = 2, [3] = 3 }
    end

    local chances = {}
    for rarity, cnt in pairs(counts) do
        local frac = norm[rarity] or 0
        if cnt and cnt > 0 then
            chances[rarity] = (frac * 100) / cnt
        else
            chances[rarity] = 0
        end
    end

    return chances, counts
end

local function normalizeProbs(probs)
    local sum = 0
    for k,v in pairs(probs) do sum = sum + v end
    if sum <= 0 then
        -- fallback to defaults
        return { [5]=2, [4]=8, [3]=90 }
    end
    local out = {}
    for k,v in pairs(probs) do out[k] = v / sum end
    return out
end

-- Build a weighted rarity table from config (returns sorted rarities and cumulative weights)
local function buildRarityWeights(probs)
    -- Build cumulative integer percentage thresholds (1..100)
    local sum = 0
    for _, v in pairs(probs or {}) do sum = sum + (v or 0) end
    if sum <= 0 then
        probs = { [5]=2, [4]=8, [3]=90 }
        sum = 100
    end
    local rarities = {3,4,5} -- deterministic order
    local cum = {}
    local total = 0
    for _, r in ipairs(rarities) do
        local raw = probs[r] or 0
        local pct = (raw / sum) * 100
        total = total + pct
        table.insert(cum, { rarity = r, cum = total })
    end
    -- Ensure last cum is exactly 100
    if #cum > 0 then cum[#cum].cum = 100 end
    return cum
end

local function pickRarity(cumWeights)
    -- Use integer random in 1..100 to avoid ambiguity with math.random() float/integer behavior
    local r = math.random(1, 100)
    for _, entry in ipairs(cumWeights) do
        if r <= entry.cum then
            return entry.rarity
        end
    end
    return cumWeights[#cumWeights].rarity
end

-- Given a catalog (array of items with .stars), return a map rarity->list
local function groupByRarity(catalog)
    local map = {}
    for _, item in ipairs(catalog or {}) do
        local s = item.stars or 3
        map[s] = map[s] or {}
        table.insert(map[s], item)
    end
    return map
end

-- Check if any item defines an explicit per-item probability/weight (.prob or .weight)
local function hasItemWeights(catalog)
    for _, item in ipairs(catalog or {}) do
        if type(item.prob) == "number" and item.prob > 0 then return true end
        if type(item.weight) == "number" and item.weight > 0 then return true end
    end
    return false
end

-- Pick an item from catalog using per-item weights (item.prob or item.weight)
local function pickWeightedItem(catalog)
    local total = 0
    local weights = {}
    for i, item in ipairs(catalog or {}) do
        local w = 0
        if type(item.prob) == "number" then
            w = item.prob
        elseif type(item.weight) == "number" then
            w = item.weight
        end
        weights[i] = w
        total = total + w
    end
    -- If total == 0, fallback to uniform random
    if total <= 0 then
        if #catalog == 0 then return nil end
        return catalog[ math.random(1, #catalog) ]
    end
    local r = math.random() * total
    local acc = 0
    for i, w in ipairs(weights) do
        acc = acc + w
        if r <= acc then
            return catalog[i]
        end
    end
    return catalog[#catalog]
end

-- Summon one item from the catalog according to config probabilities
-- catalog: array of items with .stars
-- opts: optional table to override config { probs = { [5]=2, [4]=8, [3]=90 } }
function SummonModule.SummonOnce(catalog, opts)
    assert(type(catalog) == "table", "catalog must be an array-like table")
    opts = opts or {}
    -- If catalog items contain explicit per-item probabilities (prob or weight),
    -- pick directly from those weights across the entire catalog.
    if hasItemWeights(catalog) then
        local picked = pickWeightedItem(catalog)
        local rarity = picked and (picked.stars or picked.rarity or 3) or nil
        return picked, rarity
    end

    local probs = opts.probs or SummonModule.config.probs
    local cumWeights = buildRarityWeights(probs)
    local rarity = pickRarity(cumWeights)

    local grouped = groupByRarity(catalog)
    local pool = grouped[rarity]
    -- If no items in chosen rarity, fallback to nearest available rarity (4 then 3 then 5)
    if not pool or #pool == 0 then
        if grouped[4] and #grouped[4] > 0 then
            pool = grouped[4]
            rarity = 4
        elseif grouped[3] and #grouped[3] > 0 then
            pool = grouped[3]
            rarity = 3
        else
            -- last fallback: try any available
            for _, list in pairs(grouped) do
                if #list > 0 then
                    pool = list
                    break
                end
            end
        end
    end
    if not pool or #pool == 0 then
        return nil -- nothing to summon
    end
    local idx = math.random(1, #pool)
    local picked = pool[idx]
    return picked, rarity
end

-- Helper: summon once and grant via a RemoteEvent if provided
-- grantRemote: RemoteEvent instance (client should pass the RemoteEvent to FireServer; server can pass it to FireClient)
-- player: required when called on server to FireClient(player, id)
function SummonModule.SummonAndGrantOnce(catalog, grantRemote, player, opts)
    local picked, rarity = SummonModule.SummonOnce(catalog, opts)
    if picked and grantRemote then
        -- decide whether we're on server or client
        local RunService = game:GetService("RunService")
        pcall(function()
            if RunService:IsServer() then
                -- server: send to specific player
                if player and grantRemote.FireClient then
                    grantRemote:FireClient(player, picked.id)
                end
            else
                -- client: request server to grant
                if grantRemote.FireServer then
                    grantRemote:FireServer(picked.id)
                end
            end
        end)
    end
    return picked, rarity
end

function SummonModule.SummonBulkAndGrant(catalog, n, grantRemote, player, opts)
    n = math.max(0, n or 1)
    local results = {}
    for i=1,n do
        local item, rarity = SummonModule.SummonAndGrantOnce(catalog, grantRemote, player, opts)
        table.insert(results, { item = item, rarity = rarity })
    end
    return results
end

-- Validate a banner composition against expected counts (optional)
-- spec: table mapping stars -> expected count, e.g. { [5]=1, [4]=2, [3]=3 }
function SummonModule.ValidateBanner(banner, spec)
    if type(banner) ~= "table" then return false, "banner must be a table" end
    if type(spec) ~= "table" then return true end -- nothing to validate
    local counts = {}
    for _, entry in ipairs(banner) do
        local s = entry.stars or 3
        counts[s] = (counts[s] or 0) + 1
    end
    for star, expected in pairs(spec) do
        if (counts[star] or 0) ~= expected then
            return false, string.format("banner mismatch for %d★: expected %d got %d", star, expected, counts[star] or 0)
        end
    end
    return true
end

-- Summon from a banner (array of entries) and grant via RemoteEvent if provided.
-- Banner entries may include .prob/.weight to set per-item probabilities.
function SummonModule.SummonBannerAndGrant(banner, grantRemote, player, opts)
    -- optional simple validation for the banner composition (not enforced)
    -- call SummonAndGrantOnce which already supports per-item weights
    return SummonModule.SummonAndGrantOnce(banner, grantRemote, player, opts)
end

function SummonModule.SummonBannerBulkAndGrant(banner, n, grantRemote, player, opts)
    return SummonModule.SummonBulkAndGrant(banner, n, grantRemote, player, opts)
end

-- New: deterministic banner mapping using fixed 1..100 ranges to specific banner entries.
-- Expected banner.entries ordering (by BannerManager.GenerateRandomBannerFromCatalog):
-- [1] = single 5★, [2] = first 4★, [3] = second 4★, [4] = first 3★, [5] = second 3★, [6] = third 3★
-- Ranges (inclusive): 1-2 -> entry1, 3-10 -> entry2, 11-18 -> entry3, 19-45 -> entry4, 46-72 -> entry5, 73-100 -> entry6
function SummonModule.SummonFromBanner(banner, opts)
    if type(banner) ~= "table" or type(banner.entries) ~= "table" then
        return nil, nil
    end
    local entries = banner.entries
    -- if we have at least 6 ordered entries, use fixed ranges mapping
    if #entries >= 6 then
        local r = math.random(1, 100)
        local idx = 6
        if r <= 2 then
            idx = 1
        elseif r <= 10 then
            idx = 2
        elseif r <= 18 then
            idx = 3
        elseif r <= 45 then
            idx = 4
        elseif r <= 72 then
            idx = 5
        else
            idx = 6
        end
        local picked = entries[idx]
        local rarity = (picked and (picked.stars or picked.rarity)) or nil
        return picked, rarity
    end

    -- Fallback: treat banner.entries as a catalog and use existing SummonOnce behavior
    return SummonModule.SummonOnce(entries, opts)
end

function SummonModule.SummonFromBannerBulk(banner, n, opts)
    n = math.max(0, n or 1)
    local results = {}
    for i=1,n do
        local item, rarity = SummonModule.SummonFromBanner(banner, opts)
        table.insert(results, { item = item, rarity = rarity })
    end
    return results
end

-- Summon multiple times
function SummonModule.SummonBulk(catalog, n, opts)
    n = math.max(0, n or 1)
    local results = {}
    for i=1,n do
        local item, rarity = SummonModule.SummonOnce(catalog, opts)
        table.insert(results, { item = item, rarity = rarity })
    end
    return results
end

return SummonModule
