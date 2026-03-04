-- Zoro - Santoryu (5★ exclusive)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local def = {
    Name = "Santoryu",
    Rarity = "Legendary",
    Type = "Passive",
    MaxLevel = 5,
    Description = "Base attack fires additional projectiles; +1 projectile per card level.",
}

def.id = def.id or script.Name

local Active = {}

local function safeFindRunTrack(player)
    local rt = player:FindFirstChild("RunTrack")
    if not rt then
        rt = Instance.new("Folder")
        rt.Name = "RunTrack"
        rt.Parent = player
    end
    return rt
end

-- Helper: add/remove persistent run upgrade and mirror into Stats (same pattern used elsewhere)
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
    -- Mirror into Stats folder for immediate ApplyStats folding
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

-- Apply this card's projectile contribution safely (idempotent)
-- 'bonus' should be number of extra projectiles (card level); total projectiles = 1 + bonus
local function applyProjectileContribution(player, myFolder, bonus)
    bonus = tonumber(bonus) or 0
    -- ensure RunTrack folder exists
    if not myFolder then return end
    local appliedNV = myFolder:FindFirstChild("AppliedProjectiles")
    local prev = appliedNV and (appliedNV.Value or 0) or 0

    -- ensure upgrades container
    local upgrades = player:FindFirstChild("Upgrades")
    if not upgrades then
        upgrades = Instance.new("Folder")
        upgrades.Name = "Upgrades"
        upgrades.Parent = player
    end
    local u = upgrades:FindFirstChild("ProjectileBonus")
    if not u then
        u = Instance.new("NumberValue")
        u.Name = "ProjectileBonus"
        u.Value = 0
        u.Parent = upgrades
    end

    -- Compute new upgrade value by removing our previous contribution and adding the new bonus
    local newVal = (u.Value - prev) + bonus
    u.Value = newVal

    -- Mirror into Stats folder: overwrite/adjust to match the upgrade bonus
    local stats = player:FindFirstChild("Stats")
    if stats then
        local s = stats:FindFirstChild("ProjectileBonus")
        if not s then
            s = Instance.new("NumberValue")
            s.Name = "ProjectileBonus"
            s.Value = 0
            s.Parent = stats
        end
        s.Value = newVal
    end

    -- Also expose total ProjectileCount (base 1 + bonus*2 so total is always odd) as a Stats NumberValue for consumers
    if stats then
        local tc = stats:FindFirstChild("ProjectileCount")
        if not tc then
            tc = Instance.new("NumberValue")
            tc.Name = "ProjectileCount"
            tc.Value = 1
            tc.Parent = stats
        end
        tc.Value = 1 + (newVal * 2)
    end

    if appliedNV then appliedNV.Value = bonus end
    -- debug trace (enabled)
    if true then
        local upgVal = (player:FindFirstChild("Upgrades") and player.Upgrades:FindFirstChild("ProjectileBonus") and player.Upgrades.ProjectileBonus.Value) or nil
        local statsVal = (player:FindFirstChild("Stats") and player.Stats:FindFirstChild("ProjectileCount") and player.Stats.ProjectileCount.Value) or nil
        print(string.format("[Zoro_Santoryu] apply %s prevApplied=%s bonus=%s upg=%s statsCount=%s", tostring(player and player.Name), tostring(prev), tostring(bonus), tostring(upgVal), tostring(statsVal)))
    end
end

function def.OnEquip(player, level, maxLevel)
    -- allow level 0 (some systems treat card levels as 0-based)
    level = math.clamp((level ~= nil) and level or 0, 0, maxLevel or def.MaxLevel)
    -- avoid double attach
    if Active[player] then def.OnUnequip(player) end

    local rt = safeFindRunTrack(player)
    local myFolder = rt:FindFirstChild(def.id) or Instance.new("Folder")
    myFolder.Name = def.id
    myFolder.Parent = rt

    local lvlNV = myFolder:FindFirstChild("Level") or Instance.new("IntValue")
    lvlNV.Name = "Level"
    lvlNV.Value = tonumber(level) or 0
    lvlNV.Parent = myFolder

    -- Track applied projectile total so we can remove on unequip
    local appliedNV = myFolder:FindFirstChild("AppliedProjectiles") or Instance.new("NumberValue")
    appliedNV.Name = "AppliedProjectiles"
    appliedNV.Value = appliedNV.Value or 0
    appliedNV.Parent = myFolder

    -- Compute desired bonus (extra projectiles = card level) and apply idempotently
    local bonus = lvlNV.Value
    applyProjectileContribution(player, myFolder, bonus)

    Active[player] = { folder = myFolder }
end

function def.OnUnequip(player)
    local data = Active[player]
    if not data then return end
    local appliedNV = data.folder and data.folder:FindFirstChild("AppliedProjectiles")
    local applied = appliedNV and appliedNV.Value or 0
    if applied ~= 0 then
        -- remove our contribution by subtracting applied from the upgrade value
        local upgrades = player:FindFirstChild("Upgrades")
        if upgrades then
            local u = upgrades:FindFirstChild("ProjectileBonus")
            if u and u:IsA("NumberValue") then
                u.Value = math.max(0, u.Value - applied)
                -- mirror to Stats if present
                local stats = player:FindFirstChild("Stats")
                if stats then
                    local s = stats:FindFirstChild("ProjectileBonus")
                    if s and s:IsA("NumberValue") then
                        s.Value = math.max(0, s.Value - applied)
                    end
                end
            end
        end
    end
    -- Clear our RunTrack record so subsequent OnEquip won't double-remove
    if appliedNV then
        appliedNV.Value = 0
    end
    Active[player] = nil
end

function def.OnCardAdded(player, defTable, level)
    def.OnEquip(player, level or 1, defTable and tonumber(defTable.maxLevel))
end

function def.OnLevelUp(player, newLevel)
    local data = Active[player]
    if not data then return end
    local myFolder = data.folder
    if not myFolder then return end
    local lvlNV = myFolder:FindFirstChild("Level")
    if lvlNV then lvlNV.Value = tonumber(newLevel) or lvlNV.Value end
    -- recompute bonus (card level) and apply idempotently
    local bonus = (lvlNV and lvlNV.Value) or 0
    applyProjectileContribution(player, myFolder, bonus)
end

return def
