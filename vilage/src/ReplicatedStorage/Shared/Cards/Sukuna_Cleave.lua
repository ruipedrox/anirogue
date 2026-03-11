-- Sukuna Cleave
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Damage = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("Damage"))
local SFXHelper = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("SFXHelper"))

local CLEAVE_SFX_ID = 130094147730039

local def = {
    Name = "Cleave",
    Rarity = "Legendary",
    Type = "Active",
    MaxLevel = 5,
    Description = "Automatically cleaves the nearest enemy in short range, dealing heavy damage over 1s and showing a cleave model.",
}

local statsPerLevel = {
    -- singleTargetMultiplier increases total damage because Cleave here targets a single enemy
    [1] = { damagePercent = 1.2, range = 10, cooldown = 7, singleTargetMultiplier = 3 },
    [2] = { damagePercent = 1.45, range = 12.5, cooldown = 6.5, singleTargetMultiplier = 3.2 },
    [3] = { damagePercent = 1.7, range = 15, cooldown = 6, singleTargetMultiplier = 3.5 },
    [4] = { damagePercent = 1.95, range = 17.5, cooldown = 5.5, singleTargetMultiplier = 3.8 },
    [5] = { damagePercent = 2.2, range = 20, cooldown = 5, singleTargetMultiplier = 4.2 },
}

local ActiveByUser = {}

local function findCharAsset(partName)
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    if not shared then return nil end
    local chars = shared:FindFirstChild("Chars")
    if not chars then return nil end
    local group = chars:FindFirstChild("Sukuna_5")
    if group then
        return group:FindFirstChild(partName) or group:FindFirstChild(partName:lower()) or group:FindFirstChild(partName:upper())
    end
    for _, g in ipairs(chars:GetChildren()) do
        if g and (g:IsA("Folder") or g:IsA("Model")) then
            local candidate = g:FindFirstChild(partName)
            if candidate then return candidate end
        end
    end
    return nil
end

local function findNearestEnemyWithin(origin, maxRange)
    local best, bestDist = nil, math.huge
    for _, model in pairs(CollectionService:GetTagged("Enemy")) do
        if model and model.PrimaryPart then
            local d = (model.PrimaryPart.Position - origin).Magnitude
            if d <= maxRange and d < bestDist then
                bestDist = d
                best = model
            end
        end
    end
    return best
end

local function createCleaveVisual(targetModel)
    if not targetModel or not targetModel.PrimaryPart then return nil end
    local asset = findCharAsset("Cleave") or findCharAsset("cleave")
    if asset then
        local ok, clone = pcall(function() return asset:Clone() end)
        if ok and clone then
            -- sanitize
            local visualParts = {}
            for _, d in ipairs(clone:GetDescendants()) do
                if d:IsA("BasePart") then
                    d.CanCollide = false
                    d.CanTouch = false
                    d.Anchored = true
                    d.Transparency = d.Transparency or 0
                    table.insert(visualParts, d)
                elseif d:IsA("Decal") or d:IsA("Texture") then
                    d.Transparency = d.Transparency or 0
                    table.insert(visualParts, d)
                end
            end
            if not clone.PrimaryPart then
                clone.PrimaryPart = clone:FindFirstChildWhichIsA("BasePart")
            end
            if clone.PrimaryPart then
                clone:SetPrimaryPartCFrame(targetModel.PrimaryPart.CFrame)
            end
            clone.Parent = workspace
            -- schedule fade out to match Debris lifetime
            local waitBefore = 0.5
            local fadeTime = 0.6
            task.delay(waitBefore, function()
                local tweenInfo = TweenInfo.new(fadeTime, Enum.EasingStyle.Linear)
                for _, p in ipairs(visualParts) do
                    local ok2, tween = pcall(function()
                        return TweenService:Create(p, tweenInfo, {Transparency = 1})
                    end)
                    if ok2 and tween then
                        tween:Play()
                    end
                end
            end)
            Debris:AddItem(clone, waitBefore + fadeTime)
            return clone
        end
    end
    return nil
end

local function performCleave(player, stats)
    if not player or not player.Character then return end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local target = findNearestEnemyWithin(hrp.Position, stats.range or 8)
    if not target then return end

    local pst = player:FindFirstChild("Stats")
    local baseDamage = 50
    if pst then
        local bd = pst:FindFirstChild("BaseDamage")
        if bd and bd:IsA("NumberValue") then baseDamage = bd.Value end
    end

    local multiplier = stats.singleTargetMultiplier or 1
    local totalDamage = baseDamage * (stats.damagePercent or 1) * multiplier
    local ticks = 5
    local perTick = totalDamage / ticks

    -- show cleave visual on target
    createCleaveVisual(target)

    if target.PrimaryPart then
        SFXHelper.playAt(target.PrimaryPart, CLEAVE_SFX_ID, 0.9, {
            minDist = 10, maxDist = 70, lifetime = 2,
        })
    end

    for i=1,ticks do
        if not target.Parent then break end
        local hum = target:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            -- avoid damaging owner if somehow owner is the same model
            if not (player.Character and target == player.Character) then
                pcall(function() Damage.Apply(hum, perTick) end)
            end
        end
        task.wait(1 / ticks)
    end
end

function def.OnEquip(player, level, maxLevel)
    level = math.clamp(level or 1, 1, maxLevel or def.MaxLevel)
    local userId = player.UserId
    if ActiveByUser[userId] then def.OnUnequip(player) end

    local stats = statsPerLevel[level]
    local last = 0
    local running = true

    -- Ensure RunTrack entry exists and reflect equipped level so CardPool can exclude when at max
    local runTrack = player:FindFirstChild("RunTrack") or Instance.new("Folder")
    runTrack.Name = "RunTrack"
    runTrack.Parent = player
    local myFolder = runTrack:FindFirstChild(def.id or script.Name) or Instance.new("Folder")
    myFolder.Name = def.id or script.Name
    myFolder.Parent = runTrack
    local lvlNV = myFolder:FindFirstChild("Level") or Instance.new("IntValue")
    lvlNV.Name = "Level"
    lvlNV.Value = tonumber(level) or (def.MaxLevel or def.maxLevel or 1)
    lvlNV.Parent = myFolder

    local conn = RunService.Heartbeat:Connect(function()
        if not player.Parent or not player.Character then
            def.OnUnequip(player)
            return
        end
        local now = os.clock()
        if now - last >= stats.cooldown then
            -- only consume cooldown if there is a valid target in range
            local hrp_now = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if hrp_now then
                local potential = findNearestEnemyWithin(hrp_now.Position, stats.range)
                if potential then
                    last = now
                    task.spawn(function() performCleave(player, stats) end)
                end
            end
        end
    end)

    ActiveByUser[userId] = { connection = conn, level = level }
end

function def.OnUnequip(player)
    local data = ActiveByUser[player.UserId]
    if data then
        if data.connection then data.connection:Disconnect() end
        ActiveByUser[player.UserId] = nil
    end
end

function def.OnLevelUp(player, newLevel)
    if ActiveByUser[player.UserId] then def.OnEquip(player, newLevel) end
end

function def.OnCardAdded(player, defTable, level)
    def.OnEquip(player, level or 1, defTable and tonumber(defTable.maxLevel))
end

def.Stats = statsPerLevel

return def
