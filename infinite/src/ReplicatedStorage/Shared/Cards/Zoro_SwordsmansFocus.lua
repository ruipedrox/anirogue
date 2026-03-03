-- Zoro - Swordsman's Focus
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local def = {
    Name = "Swordsman's Focus",
    Rarity = "Epic",
    Type = "Passive",
    MaxLevel = 5,
    Description = [[Each enemy killed grants +2% Base Damage. Maximum stacks increases with card level (level * 5).]],
}

def.maxLevel = def.MaxLevel
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

-- Helper: add/remove persistent run upgrade and mirror into Stats
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

function def.applyStacksToBase(player, stacks, myFolder)
    -- Each stack = +2% damage (percent units)
    local newPercent = (stacks or 0) * 2
    -- track previous applied percent in folder (NumberValue "AppliedPercent")
    local appliedNV = myFolder:FindFirstChild("AppliedPercent")
    if not appliedNV then
        appliedNV = Instance.new("NumberValue")
        appliedNV.Name = "AppliedPercent"
        appliedNV.Value = 0
        appliedNV.Parent = myFolder
    end
    local prev = appliedNV.Value or 0
    local delta = newPercent - prev
    if delta ~= 0 then
        addUpgrade(player, "DamagePercent", delta)
        appliedNV.Value = newPercent
    end
end

function def.OnEquip(player, level)
    level = math.clamp(level or 1, 1, def.MaxLevel)
    -- avoid double attach
    if Active[player] then def.OnUnequip(player) end

    local rt = safeFindRunTrack(player)
    local myFolder = rt:FindFirstChild(def.id) or Instance.new("Folder")
    myFolder.Name = def.id
    myFolder.Parent = rt

    local lvlNV = myFolder:FindFirstChild("Level") or Instance.new("IntValue")
    lvlNV.Name = "Level"
    lvlNV.Value = tonumber(level) or 1
    lvlNV.Parent = myFolder

    local stacksNV = myFolder:FindFirstChild("Stacks") or Instance.new("IntValue")
    stacksNV.Name = "Stacks"
    stacksNV.Value = stacksNV.Value or 0
    stacksNV.Parent = myFolder

    -- ensure RunTrack folder and local tracking values (Stacks/Level) created above

    local lastKills = 0
    local killsNV = rt:FindFirstChild("Kills")
    if killsNV and killsNV:IsA("IntValue") then
        lastKills = killsNV.Value
    end

    -- handler when Kill count increases
    local conn
    conn = nil
    local function onKillsChanged(new)
        local current = tonumber(new) or 0
        if current > lastKills then
            local gained = current - lastKills
            lastKills = current
            -- increment stacks per kill
            local lvl = lvlNV.Value or 1
            local maxStacks = lvl * 5
            local newStacks = math.min(maxStacks, (stacksNV.Value or 0) + gained)
            if newStacks ~= stacksNV.Value then
                stacksNV.Value = newStacks
                def.applyStacksToBase(player, newStacks, myFolder)
            end
        else
            lastKills = current
        end
    end

    if killsNV and killsNV:IsA("IntValue") then
        conn = killsNV.Changed:Connect(onKillsChanged)
    else
        -- watch for Kills IntValue to be created later
        conn = rt.ChildAdded:Connect(function(child)
            if child and child.Name == "Kills" and child:IsA("IntValue") then
                killsNV = child
                lastKills = killsNV.Value
                if conn then conn:Disconnect() end
                conn = killsNV.Changed:Connect(onKillsChanged)
            end
        end)
    end

    -- initialize AppliedPercent to current stacks (in case of pre-existing stacks)
    def.applyStacksToBase(player, stacksNV.Value or 0, myFolder)
    Active[player] = { conn = conn, folder = myFolder }
end

function def.OnUnequip(player)
    local data = Active[player]
    if not data then return end
    if data.conn then pcall(function() data.conn:Disconnect() end) end
    -- remove applied percent from Upgrades (if any)
    local appliedNV = data.folder and data.folder:FindFirstChild("AppliedPercent")
    local applied = appliedNV and appliedNV.Value or 0
    if applied ~= 0 then
        addUpgrade(player, "DamagePercent", -applied)
    end
    Active[player] = nil
end

function def.OnCardAdded(player, defTable, level)
    def.OnEquip(player, level or 1)
end

function def.OnLevelUp(player, newLevel)
    -- re-evaluate max stacks and current stacks
    local data = Active[player]
    if not data then return end
    local runTrack = player:FindFirstChild("RunTrack")
    if not runTrack then return end
    local myFolder = runTrack:FindFirstChild(def.id)
    if not myFolder then return end
    local lvlNV = myFolder:FindFirstChild("Level")
    local stacksNV = myFolder:FindFirstChild("Stacks")
    if lvlNV then lvlNV.Value = tonumber(newLevel) or lvlNV.Value end
    if stacksNV and lvlNV then
        local maxStacks = (lvlNV.Value or 1) * 5
        if stacksNV.Value > maxStacks then
            stacksNV.Value = maxStacks
            def.applyStacksToBase(player, stacksNV.Value, myFolder)
        end
    end
end

return def
