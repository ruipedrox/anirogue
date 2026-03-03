-- Sukuna World Cutting Slash
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Damage = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("Damage"))
local DoT = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("DoT"))
local SFXHelper = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("SFXHelper"))

local WORLD_SLASH_SFX_ID = 123290246899495

local def = {
    Name = "World Cutting Slash",
    Rarity = "Mythic",
    Type = "Active",
    MaxLevel = 1,
    Description = "A massive 180° slash centered on the nearest enemy, then a fast visual projectile. Applies bleed to affected enemies.",
}

-- Mirror legacy lowercase maxLevel for CardPool checks
def.maxLevel = def.MaxLevel
def.id = def.id or script.Name

local stats = {
    damagePercent = 4.0, -- large immediate damage multiplier
    cooldown = 15,
    halfAngle = 90, -- degrees (180° cone)
    bleedPercent = 0.35, -- portion of base damage applied as bleed over time
    bleedTick = 0.5,
    projectileSpeed = 100,
    projectileDistance = 150,
    projectileSize = 3,
}

local ActiveByUser = {}

local function findNearestEnemyHRP(position)
    local best, bestDist = nil, math.huge
    for _, model in pairs(CollectionService:GetTagged("Enemy")) do
        if model and model.PrimaryPart then
            local d = (model.PrimaryPart.Position - position).Magnitude
            if d < bestDist then
                bestDist = d
                best = model.PrimaryPart
            end
        end
    end
    return best
end

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

local function makeNonBlockingAnchored(inst)
    if not inst then return end
    if inst:IsA("Model") then
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("BasePart") then
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

local function spawnProjectileVisual(originCFrame, direction)
    local asset = findCharAsset("World_cutting_slash") or findCharAsset("World cutting slash")
    local model
    if asset then
        model = asset:Clone()
        if model:IsA("BasePart") then
            local wrapper = Instance.new("Model")
            model.Parent = wrapper
            wrapper.PrimaryPart = model
            model = wrapper
        end
        -- ensure PrimaryPart exists and sanitize
        if not model.PrimaryPart then
            for _, c in ipairs(model:GetDescendants()) do
                if c and c:IsA("BasePart") then
                    model.PrimaryPart = c
                    break
                end
            end
        end
        makeNonBlockingAnchored(model)
        print("[WorldCuttingSlash] using asset:", asset.Name)
    else
        model = Instance.new("Model")
        local p = Instance.new("Part")
        p.Size = Vector3.new(1,1,stats.projectileSize)
        p.Name = "SlashVisual"
        p.Anchored = true
        p.CanCollide = false
        p.Material = Enum.Material.Neon
        p.Color = Color3.fromRGB(200,200,255)
        p.Parent = model
        model.PrimaryPart = p
    end

    -- position at origin and orient along direction
    if model.PrimaryPart then
        local cf = CFrame.new(originCFrame.Position, originCFrame.Position + direction)
        model:SetPrimaryPartCFrame(cf)
        -- don't alter authored asset size: spawn asset as-is from ReplicatedStorage
        -- (keep fallback primitive sizing behavior intact)
    end
    model.Parent = workspace

    -- move it forward quickly and fade
    local distance = stats.projectileDistance or 200
    local speed = stats.projectileSpeed or 800
    local lifetime = distance / speed
    local targetCFrame = model.PrimaryPart.CFrame * CFrame.new(0,0, -distance)

    -- fade tween
    local visualParts = {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
            if d:IsA("BasePart") then d.Transparency = d.Transparency or 0 end
            if d:IsA("Decal") or d:IsA("Texture") then d.Transparency = d.Transparency or 0 end
            table.insert(visualParts, d)
        end
    end

    -- Tween movement
    local ok, tween = pcall(function()
        return TweenService:Create(model.PrimaryPart, TweenInfo.new(lifetime, Enum.EasingStyle.Linear), {CFrame = targetCFrame})
    end)
    if ok and tween then tween:Play() end

    -- Fade after small delay
    task.delay(math.max(0, lifetime*0.2), function()
        local ti = TweenInfo.new(math.max(0.1, lifetime*0.8), Enum.EasingStyle.Linear)
        for _, p in ipairs(visualParts) do
            pcall(function()
                if p:IsA("BasePart") then
                    TweenService:Create(p, ti, {Transparency = 1}):Play()
                else
                    TweenService:Create(p, ti, {Transparency = 1}):Play()
                end
            end)
        end
    end)

    Debris:AddItem(model, lifetime + 0.2)
    return model
end

local function performWorldSlash(player)
    if not player or not player.Character then return end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local targetHRP = findNearestEnemyHRP(hrp.Position)
    if not targetHRP then return end

    local pst = player:FindFirstChild("Stats")
    local baseDamage = 50
    if pst then
        local bd = pst:FindFirstChild("BaseDamage")
        if bd and bd:IsA("NumberValue") then baseDamage = bd.Value end
    end

    local totalDamage = baseDamage * (stats.damagePercent or 1)
    local immediateDamage = totalDamage
    local bleedDamage = totalDamage * (stats.bleedPercent or 0.3)

    local axis = (targetHRP.Position - hrp.Position)
    if axis.Magnitude <= 0 then return end
    local axisUnit = axis.Unit

    local halfAngle = stats.halfAngle or 90
    local cosThreshold = math.cos(math.rad(halfAngle))

    -- gather affected enemies
    local affected = {}
    for _, model in pairs(CollectionService:GetTagged("Enemy")) do
        if model and model.PrimaryPart then
            local v = (model.PrimaryPart.Position - hrp.Position)
            if v.Magnitude > 0 then
                local dot = axisUnit:Dot(v.Unit)
                if dot >= cosThreshold then
                    table.insert(affected, model)
                end
            end
        end
    end

    -- apply damage and bleed
    for _, mdl in ipairs(affected) do
        if mdl and mdl.Parent then
            local hum = mdl:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                pcall(function() Damage.Apply(hum, immediateDamage) end)
                pcall(function() DoT.Apply(hum, { dotType = "bleed", playerDamage = bleedDamage, tick = stats.bleedTick or 0.5, player = player }) end)
            end
        end
    end

    -- spawn fast projectile visual from player towards target
    local originCf = hrp.CFrame
    local direction = axisUnit
    spawnProjectileVisual(originCf, direction)

    SFXHelper.playAt(hrp, WORLD_SLASH_SFX_ID, 1.0, {
        minDist = 15, maxDist = 100, lifetime = 3,
    })
end

function def.disableCards(player)
    local runTrack = player:FindFirstChild("RunTrack") or Instance.new("Folder")
    runTrack.Name = "RunTrack"
    runTrack.Parent = player
    local disabled = runTrack:FindFirstChild("DisabledCards") or Instance.new("Folder")
    disabled.Name = "DisabledCards"
    disabled.Parent = runTrack
    local function setDisabled(id)
        if not id or id == "" then return end
        local v = disabled:FindFirstChild(id) or Instance.new("BoolValue")
        v.Name = id
        v.Value = true
        v.Parent = disabled
    end
    setDisabled("Sukuna_Cleave")
    setDisabled("Sukuna_Dismantle")

    -- disable cards that reference this module
    local function disableCardsReferencingModule(moduleName)
        local shared = ReplicatedStorage:FindFirstChild("Shared")
        if not shared then return end
        local chars = shared:FindFirstChild("Chars")
        if not chars then return end
        for _, char in ipairs(chars:GetChildren()) do
            local cardsModule = char:FindFirstChild("Cards")
            if cardsModule and cardsModule:IsA("ModuleScript") then
                local ok, defs = pcall(require, cardsModule)
                if ok and type(defs) == "table" and type(defs.Definitions) == "table" then
                    for _, list in pairs(defs.Definitions) do
                        if type(list) == "table" then
                            for _, cardDef in ipairs(list) do
                                if type(cardDef) == "table" and cardDef.id and (cardDef.module == moduleName or cardDef.module == script.Name) then
                                    setDisabled(cardDef.id)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    disableCardsReferencingModule(script.Name)
    setDisabled(def.id or script.Name)
end

function def.OnEquip(player, level)
    local userId = player.UserId
    if ActiveByUser[userId] then def.OnUnequip(player) end

    -- disable cleave/dismantle when this is equipped
    def.disableCards(player)

    -- Ensure a RunTrack entry for this card exists and set its Level
    local runTrack = player:FindFirstChild("RunTrack") or Instance.new("Folder")
    runTrack.Name = "RunTrack"
    runTrack.Parent = player
    local myFolder = runTrack:FindFirstChild(def.id) or Instance.new("Folder")
    myFolder.Name = def.id
    myFolder.Parent = runTrack
    local lvlNV = myFolder:FindFirstChild("Level") or Instance.new("IntValue")
    lvlNV.Name = "Level"
    lvlNV.Value = tonumber(level) or (def.maxLevel or 1)
    lvlNV.Parent = myFolder

    local last = 0
    local connection = RunService.Heartbeat:Connect(function()
        if not player.Parent or not player.Character then
            def.OnUnequip(player)
            return
        end
        local now = os.clock()
        if now - last >= stats.cooldown then
            -- only fire if there's a nearby enemy
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")
            if hrp and findNearestEnemyHRP(hrp.Position) then
                last = now
                task.spawn(function() performWorldSlash(player) end)
            end
        end
    end)

    ActiveByUser[userId] = { connection = connection }
    print(string.format("[WorldCuttingSlash] Equipped for %s - Cleave and Dismantle disabled", player.Name))
end

function def.OnUnequip(player)
    local userId = player.UserId
    local data = ActiveByUser[userId]
    if data then
        if data.connection then pcall(function() data.connection:Disconnect() end) end
        ActiveByUser[userId] = nil
    end
    -- cleanup disabled flags
    local runTrack = player and player:FindFirstChild("RunTrack")
    if not runTrack then return end
    local disabled = runTrack:FindFirstChild("DisabledCards")
    if not disabled then return end
    for _, id in ipairs({"Sukuna_Cleave", "Sukuna_Dismantle", (def.id or script.Name)}) do
        local v = disabled:FindFirstChild(id)
        if v and v:IsA("BoolValue") then v:Destroy() end
    end
end

function def.OnCardAdded(player, defTable, level)
    def.OnEquip(player, level or 1)
end

function def.OnLevelUp(player, newLevel)
    if ActiveByUser[player.UserId] then def.OnEquip(player, newLevel) end
end

return def
