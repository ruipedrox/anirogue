-- Tanjiro Breath Slash
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Damage = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("Damage"))
local DoT = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("DoT"))

local def = {
    Name = "Breath Slash",
    Rarity = "Epic",
    Type = "Active",
    MaxLevel = 5,
    Description = "Periodically slash the nearest enemy not affected by bleed; if all have bleed, slash nearest. Applies bleed and shows a water slash visual.",
}

def.maxLevel = def.MaxLevel
def.id = def.id or script.Name

local statsPerLevel = {
    [1] = { damagePercent = 0.6, cooldown = 6, range = 20, bleedPercent = 0.25, bleedTick = 0.5 },
    [2] = { damagePercent = 0.9, cooldown = 5.5, range = 22, bleedPercent = 0.30, bleedTick = 0.5 },
    [3] = { damagePercent = 1.2, cooldown = 5, range = 24, bleedPercent = 0.35, bleedTick = 0.5 },
    [4] = { damagePercent = 1.6, cooldown = 4.5, range = 26, bleedPercent = 0.40, bleedTick = 0.5 },
    [5] = { damagePercent = 2.0, cooldown = 4, range = 28, bleedPercent = 0.45, bleedTick = 0.5 },
}

local ActiveByUser = {}

local function findCharAsset(partName)
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    if not shared then return nil end
    local chars = shared:FindFirstChild("Chars")
    if not chars then return nil end
    local group = chars:FindFirstChild("Tanjiro_4")
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

local function makeNonBlockingAnchored(inst)
    if not inst then return end
    if inst:IsA("Model") then
        for _, d in ipairs(inst:GetDescendants()) do
            if d and d:IsA("BasePart") then
                d.CanCollide = false
                d.CanQuery = false
                d.CanTouch = false
                d.Anchored = true
            end
        end
    elseif inst:IsA("BasePart") then
        inst.CanCollide = false
        inst.CanQuery = false
        inst.CanTouch = false
        inst.Anchored = true
    end
end

local function hasBleedEffectOnModel(model)
    if not model then return false end
    local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if not hrp then return false end
    local attach = hrp:FindFirstChild("DoTEffectAttachment")
    if not attach then return false end
    for _, child in ipairs(attach:GetChildren()) do
        if child and child.Name and string.lower(child.Name):find("bleed") then
            return true
        end
    end
    return false
end

local function findNearestEnemyNotBleeding(originPos, maxRange)
    local nearestNotBleeding, nearestAll
    local bestDistNot = math.huge
    local bestDistAll = math.huge

    for _, model in pairs(CollectionService:GetTagged("Enemy")) do
        if model and model.PrimaryPart then
            local d = (model.PrimaryPart.Position - originPos).Magnitude
            if d <= (maxRange or 30) then
                if not hasBleedEffectOnModel(model) then
                    if d < bestDistNot then
                        bestDistNot = d
                        nearestNotBleeding = model
                    end
                end
                if d < bestDistAll then
                    bestDistAll = d
                    nearestAll = model
                end
            end
        end
    end

    return nearestNotBleeding or nearestAll
end

local function spawnWaterSlashOnModel(targetModel)
    if not targetModel or not targetModel.PrimaryPart then return end
    local asset = findCharAsset("water_slash") or findCharAsset("water_slash")
    local model
    if asset then
        local ok, clone = pcall(function() return asset:Clone() end)
        if not ok or not clone then asset = nil else model = clone end
    end

    if not model then
        model = Instance.new("Model")
        local p = Instance.new("Part")
        p.Size = Vector3.new(1,1,1)
        p.Name = "WaterSlash"
        p.Anchored = true
        p.CanCollide = false
        p.Material = Enum.Material.Neon
        p.Color = Color3.fromRGB(100,170,255)
        p.Parent = model
        model.PrimaryPart = p
    end

    makeNonBlockingAnchored(model)

    -- ensure PrimaryPart
    if not model.PrimaryPart then
        for _, d in ipairs(model:GetDescendants()) do
            if d and d:IsA("BasePart") then
                model.PrimaryPart = d
                break
            end
        end
    end

    -- position
    local cf = targetModel.PrimaryPart.CFrame
    model:SetPrimaryPartCFrame(cf)
    model.Parent = workspace

    -- collect parts/textures
    local visuals = {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Transparency = 1
            table.insert(visuals, d)
        elseif d:IsA("Decal") or d:IsA("Texture") then
            d.Transparency = 1
            table.insert(visuals, d)
        end
    end

    -- fade in -> wait -> fade out (total ~0.2s)
    local fadeIn = 0.05
    local hold = 0.1
    local fadeOut = 0.05
    local ok1, tweenIn
    pcall(function()
        local ti = TweenInfo.new(fadeIn, Enum.EasingStyle.Linear)
        for _, v in ipairs(visuals) do
            TweenService:Create(v, ti, {Transparency = 0}):Play()
        end
    end)

    task.delay(fadeIn + hold, function()
        pcall(function()
            local to = TweenInfo.new(fadeOut, Enum.EasingStyle.Linear)
            for _, v in ipairs(visuals) do
                TweenService:Create(v, to, {Transparency = 1}):Play()
            end
        end)
    end)

    Debris:AddItem(model, fadeIn + hold + fadeOut + 0.05)
    return model
end

local function performSlashOnTarget(player, stats, target)
    if not player or not target or not target.PrimaryPart then return end
    local pst = player:FindFirstChild("Stats")
    local baseDamage = 30
    if pst then
        local bd = pst:FindFirstChild("BaseDamage")
        if bd and bd:IsA("NumberValue") then baseDamage = bd.Value end
    end

    local totalDamage = baseDamage * (stats.damagePercent or 1)
    local bleedDamage = baseDamage * (stats.bleedPercent or 0.3)

    local hum = target:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health > 0 then
        pcall(function() Damage.Apply(hum, totalDamage) end)
        pcall(function() DoT.Apply(hum, { dotType = "bleed", playerDamage = bleedDamage, tick = stats.bleedTick or 0.5, player = player }) end)
        -- visual
        pcall(function() spawnWaterSlashOnModel(target) end)
    end
end

function def.OnEquip(player, level)
    level = math.clamp(level or 1, 1, def.MaxLevel)
    local userId = player.UserId
    if ActiveByUser[userId] then def.OnUnequip(player) end

    local stats = statsPerLevel[level]
    local last = 0

    -- Ensure RunTrack entry and record current level so CardPool can see it and stop offering at max
    local runTrack = player:FindFirstChild("RunTrack") or Instance.new("Folder")
    runTrack.Name = "RunTrack"
    runTrack.Parent = player
    local myFolder = runTrack:FindFirstChild(def.id) or Instance.new("Folder")
    myFolder.Name = def.id
    myFolder.Parent = runTrack
    local lvlNV = myFolder:FindFirstChild("Level") or Instance.new("IntValue")
    lvlNV.Name = "Level"
    lvlNV.Value = tonumber(level) or 1
    lvlNV.Parent = myFolder

    local conn = RunService.Heartbeat:Connect(function()
        if not player.Parent or not player.Character then
            def.OnUnequip(player)
            return
        end
        local now = os.clock()
        if now - last >= stats.cooldown then
            last = now
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")
            local origin = hrp and hrp.Position or player:GetPivot().Position
            local target = findNearestEnemyNotBleeding(origin, stats.range)
            if target then
                task.spawn(function() performSlashOnTarget(player, stats, target) end)
            end
        end
    end)

    ActiveByUser[userId] = { connection = conn, level = level }
end

function def.OnLevelUp(player, newLevel)
    if ActiveByUser[player.UserId] then
        -- update RunTrack folder level if present and re-equip to apply new stats
        local runTrack = player and player:FindFirstChild("RunTrack")
        local myFolder = runTrack and runTrack:FindFirstChild(def.id)
        if myFolder then
            local lvlNV = myFolder:FindFirstChild("Level") or Instance.new("IntValue")
            lvlNV.Name = "Level"
            lvlNV.Value = tonumber(newLevel) or lvlNV.Value
            lvlNV.Parent = myFolder
        end
        def.OnEquip(player, newLevel)
    end
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
    def.OnEquip(player, level or 1)
end

def.Stats = statsPerLevel

return def
