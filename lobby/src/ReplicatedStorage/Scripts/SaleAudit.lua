-- SaleAudit.lua
-- Minimal audit logger for sales using DataStore UpdateAsync

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local SaleAudit = {}

-- In-memory fallback store used in Studio or when DataStore calls fail
local inMemoryStore = {}

local function makeAuditId()
    return tostring(os.time()) .. "_" .. tostring(math.random(100000,999999))
end

local function useDataStore()
    -- If running in Studio, DataStore API may be disabled. Prefer in-memory in that case.
    if RunService:IsStudio() then
        return false
    end
    return true
end

-- Try to get the real DataStore; nil if not available or in Studio
local function tryGetStore()
    if not useDataStore() then return nil end
    local ok, ds = pcall(function()
        return DataStoreService:GetDataStore("SaleAudit")
    end)
    if ok then return ds end
    return nil
end

-- Append an audit entry to the player's audit list atomically
-- entry is a table with at least: id, type, instanceId, coins, timestamp, status
function SaleAudit:LogSale(userId, entry)
    if not userId or not entry then return nil, "BadArgs" end
    entry.id = entry.id or makeAuditId()
    entry.timestamp = entry.timestamp or os.time()
    entry.status = entry.status or "pending"

    local ds = tryGetStore()
    if not ds then
        -- fallback to in-memory store for Studio/testing
        local key = "audit_" .. tostring(userId)
        inMemoryStore[key] = inMemoryStore[key] or {}
        table.insert(inMemoryStore[key], entry)
        return entry.id
    end

    local key = "audit_" .. tostring(userId)
    local attempts = 3
    for i = 1, attempts do
        local ok, res = pcall(function()
            return ds:UpdateAsync(key, function(old)
                local arr = old or {}
                table.insert(arr, entry)
                return arr
            end)
        end)
        if ok then
            return entry.id
        else
            warn("[SaleAudit] LogSale attempt failed (", i, "):", res)
            wait(0.2)
        end
    end
    return nil, "UpdateFailed"
end

-- Mark an audit entry complete by id
function SaleAudit:MarkComplete(userId, auditId)
    if not userId or not auditId then return false, "BadArgs" end
    local ds = tryGetStore()
    local key = "audit_" .. tostring(userId)
    if not ds then
        -- mark in the in-memory fallback if present
        local arr = inMemoryStore[key]
        if arr then
            for idx, e in ipairs(arr) do
                if e and e.id == auditId then
                    e.status = "done"
                    e.completedTimestamp = os.time()
                    arr[idx] = e
                    return true
                end
            end
        end
        return false, "NotFound"
    end

    local attempts = 3
    for i = 1, attempts do
        local ok, res = pcall(function()
            return ds:UpdateAsync(key, function(old)
                local arr = old or {}
                for idx, e in ipairs(arr) do
                    if e and e.id == auditId then
                        e.status = "done"
                        e.completedTimestamp = os.time()
                        arr[idx] = e
                        break
                    end
                end
                return arr
            end)
        end)
        if ok then
            return true
        else
            warn("[SaleAudit] MarkComplete attempt failed (", i, "):", res)
            wait(0.2)
        end
    end
    return false, "UpdateFailed"
end

return SaleAudit
