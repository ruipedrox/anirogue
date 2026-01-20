-- Complete rewrite: keep completed levels helpers and provide a clean, latest-only RunResult persistence API.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local CompletedDS = DataStoreService:GetDataStore("PlayerCompletedLevels_v1")
local RunResultsDS = DataStoreService:GetDataStore("PlayerRunResults_v1")

-- --------------
-- Completed Levels helpers
-- --------------
local function completedKey(userId)
    return "CompletedLevels:" .. tostring(userId)
end

local function loadCompleted(userId)
    local ok, res = pcall(function()
        return CompletedDS:GetAsync(completedKey(userId))
    end)
    if ok and type(res) == "table" then return res end
    return {}
end

local function updateCompleted(userId, updater)
    local key = completedKey(userId)
    local attempts, maxAttempts, waitBase = 0, 6, 0.2
    while attempts < maxAttempts do
        local ok, err = pcall(function()
            return CompletedDS:UpdateAsync(key, function(old)
                local cur = (type(old) == "table") and old or {}
                local new = updater(cur) or cur
                return new
            end)
        end)
        if ok then return true end
        attempts += 1
        task.wait(waitBase * (2 ^ (attempts - 1)))
    end
    return false, "max_retries"
end

local function markLevelCompleted(userId, mapId, levelNumber)
    if not userId or not mapId or not levelNumber then return false, "bad_args" end
    local uid = tonumber(userId)
    if not uid then return false, "bad_userid" end
    local ok, err = updateCompleted(uid, function(cur)
        cur.Maps = (type(cur.Maps) == "table") and cur.Maps or {}
        local prev = tonumber(cur.Maps[tostring(mapId)]) or 0
        if tonumber(levelNumber) > prev then
            cur.Maps[tostring(mapId)] = tonumber(levelNumber)
        end
        return cur
    end)
    if not ok then return false, err end
    return true
end

local function hasCompletedLevel(userId, mapId, levelNumber)
    local cur = loadCompleted(userId)
    local highest = (cur and cur.Maps and tonumber(cur.Maps[tostring(mapId)])) or 0
    return highest >= tonumber(levelNumber)
end

-- --------------
-- Run Results (latest-only)
-- --------------
local function saveRunResult(userId, runId, runResult)
    if not userId or not runId or type(runResult) ~= "table" then return false, "bad_args" end
    local record = { RunId = tostring(runId), RunResult = runResult }
    local key = "RunResults:" .. tostring(userId)
    local attempts, maxAttempts, waitBase = 0, 6, 0.2

    while attempts < maxAttempts do
        local ok, err = pcall(function()
            RunResultsDS:SetAsync(key, record)
            return true
        end)
        if ok then
            -- Write compact mirror and human-friendly summary
            pcall(function()
                local mirrorKey = string.format("RR:%s", tostring(userId))
                RunResultsDS:SetAsync(mirrorKey, runResult)

                local accXP = tonumber(runResult.AccountXP) or 0
                local charKeys, charTotal = 0, 0
                if type(runResult.CharacterXP) == "table" then
                    for _, v in pairs(runResult.CharacterXP) do
                        charKeys += 1
                        charTotal += (tonumber(v) or 0)
                    end
                end
                local rewards = runResult.Rewards or {}
                local itemsCount = 0
                if type(rewards.Items) == "table" then
                    for _, it in ipairs(rewards.Items) do
                        itemsCount += (tonumber(it and it.Quantity) or 0)
                    end
                end
                local summaryKey = "LastWriteSummary:" .. tostring(userId)
                RunResultsDS:SetAsync(summaryKey, {
                    RunId = record.RunId,
                    ShortId = string.gsub(record.RunId, "-", ""):sub(1, 8),
                    WroteAt = os.time(),
                    AccountXP = accXP,
                    CharacterXPKeys = charKeys,
                    CharacterXPTotal = charTotal,
                    Gold = tonumber(rewards.Gold) or 0,
                    Gems = tonumber(rewards.Gems) or 0,
                    ItemCount = itemsCount,
                })
            end)
            return true
        end
        attempts += 1
        task.wait(waitBase * (2 ^ (attempts - 1)))
    end
    return false, "max_retries"
end

return {
    -- story progression helpers
    markLevelCompleted = markLevelCompleted,
    hasCompletedLevel = hasCompletedLevel,
    loadCompleted = loadCompleted,
    -- run results persistence
    saveRunResult = saveRunResult,
}
