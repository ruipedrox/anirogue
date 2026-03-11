-- Shikamaru Explosive Scrolls
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Damage = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("Damage"))
local SFXHelper              = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("SFXHelper"))
local EXPLOSION_SFX_ID       = 135670616983730

local def = {
    Name = "Explosive Scrolls",
    Rarity = "Epic",
    Type = "Active",
    MaxLevel = 5,
    Description = "Periodically places explosive scrolls on the ground; when an enemy gets close they explode dealing area damage.",
}

-- compatibility
def.maxLevel = def.maxLevel or def.MaxLevel
def.id = def.id or script.Name

local statsPerLevel = {
    [1] = { n = 1, damagePercent = 0.5, spawnCooldown = 8, spawnRadius = 4, triggerRadius = 3, explosionRadius = 6, life = 60 },
    [2] = { n = 2, damagePercent = 1.0, spawnCooldown = 7.5, spawnRadius = 4.5, triggerRadius = 3.25, explosionRadius = 6.5, life = 70 },
    [3] = { n = 3, damagePercent = 1.5, spawnCooldown = 7, spawnRadius = 5, triggerRadius = 3.5, explosionRadius = 7, life = 80 },
    [4] = { n = 4, damagePercent = 2.0, spawnCooldown = 6.5, spawnRadius = 5.5, triggerRadius = 4, explosionRadius = 8, life = 90 },
    [5] = { n = 5, damagePercent = 2.5, spawnCooldown = 6, spawnRadius = 6, triggerRadius = 4.5, explosionRadius = 9, life = 100 },
}

local ActiveByUser = {}

local function findCharAsset(partName)
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    if not shared then return nil end
    local chars = shared:FindFirstChild("Chars")
    if not chars then return nil end
    -- try Shikamaru_4 first
    local group = chars:FindFirstChild("Shikamaru_4")
    if group then
        local candidate = group:FindFirstChild(partName)
        if candidate then return candidate end
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

local function createScrollAt(pos)
    local asset = findCharAsset("Scroll")
    local model
    if asset then
        local ok, clone = pcall(function() return asset:Clone() end)
        if ok and clone then
            model = clone
        end
    end
    if not model then
        model = Instance.new("Model")
        local p = Instance.new("Part")
        p.Size = Vector3.new(1, 0.4, 1)
        p.Name = "ExplosiveScroll"
        p.Anchored = true
        p.CanCollide = false
        p.Material = Enum.Material.Wood
        p.Parent = model
        model.PrimaryPart = p
    end
    makeNonBlockingAnchored(model)
    -- ensure PrimaryPart
    if not model.PrimaryPart then
        for _, d in ipairs(model:GetDescendants()) do
            if d and d:IsA("BasePart") then model.PrimaryPart = d break end
        end
    end
    if model.PrimaryPart then
        -- lay the scroll model flat when spawning so it appears deitado
        pcall(function()
            model:SetPrimaryPartCFrame(CFrame.new(pos) * CFrame.Angles(math.rad(-90), 0, 0))
        end)
    end
    model.Parent = workspace
    return model
end

local function createExplosionEffect(position, radius)
    local explosion = Instance.new("Part")
    explosion.Name = "ScrollExplosion"
    explosion.Shape = Enum.PartType.Ball
    explosion.Size = Vector3.new(0.5,0.5,0.5)
    explosion.Material = Enum.Material.Neon
    explosion.Color = Color3.fromRGB(255,150,50)
    explosion.Anchored = true
    explosion.CanCollide = false
    explosion.CanQuery = false
    explosion.CanTouch = false
    explosion.Position = position
    explosion.Parent = workspace

    local emitter = Instance.new("ParticleEmitter")
    emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
    emitter.Color = ColorSequence.new(Color3.fromRGB(255,200,100), Color3.fromRGB(255,80,0))
    emitter.Lifetime = NumberRange.new(0.2, 0.5)
    emitter.Rate = 200
    emitter.Size = NumberSequence.new(0.5 * radius/3, radius/1.5)
    emitter.Parent = explosion

    local tween = TweenService:Create(explosion, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {Size = Vector3.new(radius*2, radius*2, radius*2), Transparency = 1})
    tween:Play()
    tween.Completed:Connect(function() if explosion and explosion.Parent then explosion:Destroy() end end)
end

-- helper: robustly get a model's world position (PrimaryPart, HumanoidRootPart, torso, or first BasePart)
local function getModelPosition(mdl)
    if not mdl then return nil end
    if mdl.PrimaryPart and mdl.PrimaryPart:IsA("BasePart") then
        return mdl.PrimaryPart.Position
    end
    local hrp = mdl:FindFirstChild("HumanoidRootPart") or mdl:FindFirstChild("Torso") or mdl:FindFirstChild("UpperTorso") or mdl:FindFirstChild("LowerTorso")
    if hrp and hrp:IsA("BasePart") then
        return hrp.Position
    end
    for _, d in ipairs(mdl:GetDescendants()) do
        if d and d:IsA("BasePart") then
            return d.Position
        end
    end
    return nil
end

local function explodeScroll(scrollModel, ownerPlayer, stats)
    if not scrollModel or not scrollModel.Parent then return end
    local pos
    if scrollModel.PrimaryPart then
        pos = scrollModel.PrimaryPart.Position
    else
        local ok, cf = pcall(function() return scrollModel:GetModelCFrame() end)
        pos = (ok and cf and cf.p) or nil
    end
    if not pos then
        scrollModel:Destroy()
        return
    end

    -- SFX 3D na posição da explosão
    do
        local anchor = Instance.new("Part")
        anchor.Anchored = true; anchor.CanCollide = false; anchor.Transparency = 1
        anchor.Size = Vector3.new(0.5,0.5,0.5)
        anchor.Position = pos
        anchor.Parent = workspace
        SFXHelper.playAt(anchor, EXPLOSION_SFX_ID, 0.85, { minDist = 15, maxDist = 80, lifetime = 3 })
        game:GetService("Debris"):AddItem(anchor, 4)
    end

    -- damage enemies in explosion radius (horizontal distance only)
    for _, mdl in ipairs(CollectionService:GetTagged("Enemy")) do
        local enemyPos = getModelPosition(mdl)
        if enemyPos then
            local a = Vector3.new(enemyPos.X, 0, enemyPos.Z)
            local b = Vector3.new(pos.X, 0, pos.Z)
            local d = (a - b).Magnitude
            if d <= (stats.explosionRadius or 6) then
                local hum = mdl:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    local pst = ownerPlayer and ownerPlayer:FindFirstChild("Stats")
                    local baseDamage = 30
                    if pst then
                        local bd = pst:FindFirstChild("BaseDamage")
                        if bd and bd:IsA("NumberValue") then baseDamage = bd.Value end
                    end
                    local dmg = baseDamage * (stats.damagePercent or 1)
                    pcall(function() Damage.Apply(hum, dmg) end)
                end
            end
        end
    end

    createExplosionEffect(pos, stats.explosionRadius or 6)
    scrollModel:Destroy()
end

function def.OnEquip(player, level, maxLevel)
    level = math.clamp(level or 1, 1, maxLevel or def.MaxLevel)
    local uid = player.UserId
    if ActiveByUser[uid] then def.OnUnequip(player) end

    local stats = statsPerLevel[level] or statsPerLevel[1]
    local acc = 0
    local spawned = {}

    -- Ensure RunTrack entry and level
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

    local conn
    conn = RunService.Heartbeat:Connect(function(dt)
        if not player.Parent or not player.Character then
            def.OnUnequip(player)
            return
        end

        acc = acc + (dt or 0)
        -- spawn scrolls periodically
            if acc >= (stats.spawnCooldown or 6) then
            acc = 0
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                -- spawn N scrolls evenly spaced around the player (angle = 360 / N)
                local n = math.max(1, level or 1)
                local radius = stats.spawnRadius or 4
                for i = 1, n do
                    local angle = ((i - 1) * (2 * math.pi)) / n
                    local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
                    local spawnPos = hrp.Position + offset + Vector3.new(0, -1, 0)
                    local model = createScrollAt(spawnPos)
                    if model and model.PrimaryPart then
                        table.insert(spawned, model)
                        Debris:AddItem(model, stats.life or 12)
                        -- add a visual preview (flat disc) showing the trigger radius
                        pcall(function()
                            local radius = stats.triggerRadius or 3
                            local preview = Instance.new("Part")
                            preview.Name = "TriggerPreview"
                            preview.Anchored = true
                            preview.CanCollide = false
                            preview.CanQuery = false
                            preview.CanTouch = false
                            preview.Material = Enum.Material.ForceField
                            preview.Color = Color3.fromRGB(255, 120, 80)
                            preview.Transparency = 0.6
                            preview.Size = Vector3.new(radius * 2, 0.15, radius * 2)
                            -- place flat on the ground under the scroll
                            local yOff = -(model.PrimaryPart.Size.Y/2 + 0.075)
                            -- place flat on the ground under the scroll (world space)
                            preview.CFrame = CFrame.new(model.PrimaryPart.Position + Vector3.new(0, yOff, 0))
                            preview.Parent = workspace
                            Debris:AddItem(preview, stats.life or 12)
                        end)
                    end
                end
            end
        end

        -- check spawned scrolls for nearby enemies
        if #spawned > 0 then
            for i = #spawned, 1, -1 do
                local s = spawned[i]
                if not s or not s.Parent then
                    table.remove(spawned, i)
                else
                    local spos
                    if s.PrimaryPart then spos = s.PrimaryPart.Position end
                    if not spos then
                        local ok, cf = pcall(function() return s:GetModelCFrame() end)
                        spos = ok and cf and cf.p or nil
                    end
                    if spos then
                        local sposFlat = Vector3.new(spos.X, 0, spos.Z)
                        for _, mdl in ipairs(CollectionService:GetTagged("Enemy")) do
                            local enemyPos = getModelPosition(mdl)
                            if enemyPos then
                                local enemyFlat = Vector3.new(enemyPos.X, 0, enemyPos.Z)
                                local d = (enemyFlat - sposFlat).Magnitude
                                if d <= (stats.triggerRadius or 3) then
                                    -- explode
                                    explodeScroll(s, player, stats)
                                    table.remove(spawned, i)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    ActiveByUser[uid] = { connection = conn, spawned = spawned, level = level }
end

function def.OnUnequip(player)
    if not player then return end
    local uid = player.UserId
    local data = ActiveByUser[uid]
    if data then
        if data.connection then pcall(function() data.connection:Disconnect() end) end
        if data.spawned then
            for _, s in ipairs(data.spawned) do
                if s and s.Parent then pcall(function() s:Destroy() end) end
            end
        end
        ActiveByUser[uid] = nil
    end
end

function def.OnLevelUp(player, newLevel)
    if ActiveByUser[player.UserId] then
        -- update RunTrack Level
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

function def.OnCardAdded(player, defTable, level)
    local lvl = tonumber(level) or 1
    def.OnEquip(player, lvl, defTable and tonumber(defTable.maxLevel))

    -- trigger ability immediately: spawn N scrolls around the player
    local uid = player and player.UserId
    local data = uid and ActiveByUser[uid]
    local stats = statsPerLevel[lvl] or statsPerLevel[1]
    local spawnedList = data and data.spawned
    local char = player and player.Character
    local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("HumanoidRoot") )
    if hrp and stats then
        local n = math.max(1, lvl or 1)
        local radius = stats.spawnRadius or 4
        for i = 1, n do
            local angle = ((i - 1) * (2 * math.pi)) / n
            local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
            local spawnPos = hrp.Position + offset + Vector3.new(0, -1, 0)
            local model = createScrollAt(spawnPos)
            if model and model.PrimaryPart then
                if spawnedList then table.insert(spawnedList, model) end
                Debris:AddItem(model, stats.life or 12)
                pcall(function()
                    local r = stats.triggerRadius or 3
                    local preview = Instance.new("Part")
                    preview.Name = "TriggerPreview"
                    preview.Anchored = true
                    preview.CanCollide = false
                    preview.CanQuery = false
                    preview.CanTouch = false
                    preview.Material = Enum.Material.ForceField
                    preview.Color = Color3.fromRGB(255, 120, 80)
                    preview.Transparency = 0.6
                    preview.Size = Vector3.new(r * 2, 0.15, r * 2)
                    local yOff = -(model.PrimaryPart.Size.Y/2 + 0.075)
                    preview.CFrame = CFrame.new(model.PrimaryPart.Position + Vector3.new(0, yOff, 0))
                    preview.Parent = workspace
                    Debris:AddItem(preview, stats.life or 12)
                end)
            end
        end
    end
end

def.Stats = statsPerLevel

return def
