local Leveling = {}

-- XP curve configuration (baseline). Real per-player values are taken from player.Stats:
--  * LevelGrowth (multiplicador de crescimento por nível)
--  * MaxLevel (limite por run)
-- Estes defaults só são usados se o jogador ainda não tiver Stats criados.
Leveling.BaseXP = 100            -- XP required baseline for level 1 -> 2
Leveling.DefaultGrowth = 1.2     -- Fallback growth if no per-player LevelGrowth yet
Leveling.DefaultMaxLevel = 15    -- Fallback max if no per-player MaxLevel yet (kept for backward compatibility)

local function ensureStatsFolder(player)
    local stats = player:FindFirstChild("Stats")
    if not stats then
        stats = Instance.new("Folder")
        stats.Name = "Stats"
        stats.Parent = player
    end
    return stats
end

local function ensureNumber(statsFolder, name, default)
    local nv = statsFolder:FindFirstChild(name)
    if not nv then
        nv = Instance.new("NumberValue")
        nv.Name = name
        nv.Value = default or 0
        nv.Parent = statsFolder
    end
    return nv
end

function Leveling:GetRequiredXPFor(level, growth)
    level = math.max(1, tonumber(level) or 1)
    growth = tonumber(growth) or self.DefaultGrowth
    return math.floor(self.BaseXP * (growth ^ (level - 1)) + 0.5)
end

-- Backwards compatibility name (old callers may still use GetRequiredXP)
function Leveling:GetRequiredXP(level)
    return self:GetRequiredXPFor(level, self.DefaultGrowth)
end

function Leveling:EnsureStats(player, initialLevel)
    local stats = ensureStatsFolder(player)
    local lvl = ensureNumber(stats, "Level", initialLevel or 1)
    if initialLevel and lvl.Value ~= initialLevel then
        lvl.Value = initialLevel
    elseif lvl.Value <= 0 then
        lvl.Value = 1
    end
    local xp = ensureNumber(stats, "XP", 0)
    local growthNV = ensureNumber(stats, "LevelGrowth", self.DefaultGrowth)
    local maxLvl = ensureNumber(stats, "MaxLevel", self.DefaultMaxLevel)
    local req = ensureNumber(stats, "XPRequired", self:GetRequiredXPFor(lvl.Value, growthNV.Value))
    req.Value = self:GetRequiredXPFor(lvl.Value, growthNV.Value)

    -- Attach a single listener to keep XPRequired consistent if some other script adjusts Level directly.
    -- Note: We no longer enforce a per-run MaxLevel cap here; Level can increase without being clamped.
    if not lvl:GetAttribute("_ReqHooked") then
        lvl.Changed:Connect(function()
            local growth = growthNV and growthNV.Value or self.DefaultGrowth
            if lvl.Value <= 0 then lvl.Value = 1 end
            -- Do NOT clamp lvl.Value to MaxLevel; MaxLevel is deprecated for run cap
            req.Value = self:GetRequiredXPFor(lvl.Value, growth)
        end)
        lvl:SetAttribute("_ReqHooked", true)
    end

    if not growthNV:GetAttribute("_GrowthHooked") then
        growthNV.Changed:Connect(function()
            -- Recalculate requirement for current level with new growth
            req.Value = self:GetRequiredXPFor(lvl.Value, growthNV.Value)
        end)
        growthNV:SetAttribute("_GrowthHooked", true)
    end

    return lvl, xp, req, maxLvl, growthNV
end

-- Adds XP and handles multi-level ups; returns number of levels gained
function Leveling:AddXP(player, amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then return 0 end
    local stats = ensureStatsFolder(player)
    local lvl = ensureNumber(stats, "Level", 1)
    local xp = ensureNumber(stats, "XP", 0)
    local growthNV = ensureNumber(stats, "LevelGrowth", self.DefaultGrowth)
    local maxLvl = ensureNumber(stats, "MaxLevel", self.DefaultMaxLevel)
    local req = ensureNumber(stats, "XPRequired", self:GetRequiredXPFor(lvl.Value, growthNV.Value))
    -- Apply per-player XP gain multiplier
    do
        local rate = stats:FindFirstChild("xpgainrate")
        local mul = (rate and rate:IsA("NumberValue") and rate.Value) or 1
        amount = amount * mul
    end

    local gainedLevels = 0
    -- Add XP and allow leveling without a hard cap per run (MaxLevel is not enforced here)
    xp.Value += amount
    while xp.Value >= req.Value do
        xp.Value -= req.Value
        lvl.Value += 1
        gainedLevels += 1
        req.Value = self:GetRequiredXPFor(lvl.Value, growthNV.Value)
    end
    req.Value = self:GetRequiredXPFor(lvl.Value, growthNV.Value)
    return gainedLevels
end

-- Convenience: returns table {level = n, xp = currentXP, required = requiredForThisLevel, fraction = xp/required}
function Leveling:GetXPData(player)
    if not player then return nil end
    local stats = ensureStatsFolder(player)
    local lvl = ensureNumber(stats, "Level", 1)
    local xp = ensureNumber(stats, "XP", 0)
    local growthNV = ensureNumber(stats, "LevelGrowth", self.DefaultGrowth)
    local req = ensureNumber(stats, "XPRequired", self:GetRequiredXPFor(lvl.Value, growthNV.Value))
    req.Value = self:GetRequiredXPFor(lvl.Value, growthNV.Value)
    local required = req.Value <= 0 and 1 or req.Value
    return {
        level = lvl.Value,
        xp = xp.Value,
        required = required,
        fraction = math.clamp(xp.Value / required, 0, 1)
    }
end

return Leveling
