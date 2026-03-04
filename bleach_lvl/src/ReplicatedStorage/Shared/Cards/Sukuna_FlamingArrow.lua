-- Sukuna Flaming Arrow
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Projectile = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Projectile"))
local Damage = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("Damage"))
local DoT = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("DoT"))
local SFXHelper = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("SFXHelper"))

local FLAMING_ARROW_SFX_ID = 114596541216552

local def = {
    Name = "Flaming Arrow",
    Rarity = "Legendary",
    Type = "Active",
    MaxLevel = 5,
    Description = "Charge to grow and aim at nearest enemy, then launch a flaming arrow that explodes and applies burn.",
}

local statsPerLevel = {
    [1] = { damagePercent = 1.0, cooldown = 6, chargeTime = 1.3, size = 1.0, speed = 120, pierce = 2, explosionRadius = 4, burnPlayerPercent = 0.5 },
    [2] = { damagePercent = 1.25, cooldown = 5.5, chargeTime = 1.3, size = 1.2, speed = 140, pierce = 2, explosionRadius = 5, burnPlayerPercent = 0.6 },
    [3] = { damagePercent = 1.5, cooldown = 5.0, chargeTime = 1.3, size = 1.5, speed = 160, pierce = 3, explosionRadius = 6, burnPlayerPercent = 0.7 },
    [4] = { damagePercent = 1.75, cooldown = 4.5, chargeTime = 1.3, size = 1.8, speed = 180, pierce = 3, explosionRadius = 7, burnPlayerPercent = 0.8 },
    [5] = { damagePercent = 2.0, cooldown = 4.0, chargeTime = 1.3, size = 2.2, speed = 220, pierce = 4, explosionRadius = 8, burnPlayerPercent = 1.0 },
}

local ActiveByUser = {}

-- Try to locate authored assets under ReplicatedStorage.Shared.Chars/<CharName>
local function findCharAsset(partName)
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    if not shared then return nil end
    local chars = shared:FindFirstChild("Chars")
    if not chars then return nil end
    local group = chars:FindFirstChild("Sukuna_5")
    if not group then
        -- fallback: search all char folders for matching asset
        for _, g in ipairs(chars:GetChildren()) do
            if g and (g:IsA("Folder") or g:IsA("Model")) then
                local candidate = g:FindFirstChild(partName)
                if candidate then return candidate end
            end
        end
        return nil
    end
    local cand = group:FindFirstChild(partName) or group:FindFirstChild(partName:lower()) or group:FindFirstChild(partName:upper())
    return cand
end

local function findNearestEnemyPosition(origin)
    local best, bestDist = nil, math.huge
    for _, model in pairs(CollectionService:GetTagged("Enemy")) do
        if model and model.PrimaryPart then
            local d = (model.PrimaryPart.Position - origin).Magnitude
            if d < bestDist then
                bestDist = d
                best = model.PrimaryPart.Position
            end
        end
    end
    return best
end

local function createChargeVisual(size)
    -- Prefer authored asset if present
    local asset = findCharAsset("Flame_arrow") or findCharAsset("FlameArrow")
    if asset then
        local ok, clone = pcall(function() return asset:Clone() end)
        if ok and clone then
            -- If single part, wrap in model
            if clone:IsA("BasePart") then
                local wrapper = Instance.new("Model")
                wrapper.Name = (clone.Name ~= "" and clone.Name) or "FlameCharge"
                -- store base size and set scaled size
                local baseSize = clone.Size
                clone:SetAttribute("sukuna_base_size", baseSize)
                clone.Size = baseSize * math.clamp(size or 1, 0.2, 2)
                clone.CanCollide = false
                clone.CanTouch = false
                clone.CanQuery = false
                clone.Anchored = true
                -- if there's a mesh, store its base scale too
                local mesh = clone:FindFirstChildOfClass("SpecialMesh")
                if mesh then
                    mesh:SetAttribute("sukuna_base_scale", mesh.Scale)
                    mesh.Scale = mesh.Scale * math.clamp(size or 1, 0.2, 2)
                end
                clone.Parent = wrapper
                wrapper.PrimaryPart = clone
                wrapper.Parent = workspace
                return wrapper
            else
                -- Model: sanitize parts and store original sizes/scales as attributes
                for _, d in ipairs(clone:GetDescendants()) do
                    if d:IsA("SpecialMesh") then
                        -- store base scale
                        local base = d.Scale
                        d:SetAttribute("sukuna_base_scale", base)
                        d.Scale = base * math.clamp(size or 1, 0.2, 2)
                    elseif d:IsA("BasePart") then
                        local base = d.Size
                        d:SetAttribute("sukuna_base_size", base)
                        d.CanCollide = false
                        d.CanTouch = false
                        d.CanQuery = false
                        d.Anchored = true
                        d.Size = base * math.clamp(size or 1, 0.2, 2)
                    end
                end
                if not clone.PrimaryPart then
                    clone.PrimaryPart = clone:FindFirstChildWhichIsA("BasePart")
                end
                clone.Parent = workspace
                return clone
            end
        end
    end
    -- Fallback simple part
    local part = Instance.new("Part")
    part.Name = "FlamingArrowCharge"
    part.Size = Vector3.new(0.5, 0.5, 1) * (size or 1)
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Material = Enum.Material.Neon
    part.Color = Color3.fromRGB(255, 140, 0)
    part.Shape = Enum.PartType.Cylinder
    part.Parent = workspace
    return part
end

local function createProjectileModel(size)
    -- Prefer authored asset
    local asset = findCharAsset("Flame_arrow") or findCharAsset("FlameArrow")
    if asset then
        local ok, clone = pcall(function() return asset:Clone() end)
        if ok and clone then
            if clone:IsA("BasePart") then
                local wrapper = Instance.new("Model")
                wrapper.Name = (clone.Name ~= "" and clone.Name) or "FlameProjectile"
                local baseSize = clone.Size
                clone:SetAttribute("sukuna_base_size", baseSize)
                clone.Size = baseSize * math.clamp(size or 1, 0.2, 4)
                clone.CanCollide = false
                clone.CanTouch = false
                clone.CanQuery = false
                clone.Anchored = true
                local mesh = clone:FindFirstChildOfClass("SpecialMesh")
                if mesh then
                    mesh:SetAttribute("sukuna_base_scale", mesh.Scale)
                    mesh.Scale = mesh.Scale * math.clamp(size or 1, 0.2, 4)
                end
                clone.Parent = wrapper
                wrapper.PrimaryPart = clone
                return wrapper
            else
                for _, d in ipairs(clone:GetDescendants()) do
                    if d:IsA("SpecialMesh") then
                        local base = d.Scale
                        d:SetAttribute("sukuna_base_scale", base)
                        d.Scale = base * math.clamp(size or 1, 0.2, 4)
                    elseif d:IsA("BasePart") then
                        local base = d.Size
                        d:SetAttribute("sukuna_base_size", base)
                        d.CanCollide = false
                        d.CanTouch = false
                        d.CanQuery = false
                        d.Anchored = true
                        d.Size = base * math.clamp(size or 1, 0.2, 4)
                    end
                end
                if not clone.PrimaryPart then clone.PrimaryPart = clone:FindFirstChildWhichIsA("BasePart") end
                return clone
            end
        end
    end
    -- Fallback primitive
    local part = Instance.new("Part")
    part.Name = "FlamingArrowProjectile"
    part.Size = Vector3.new(0.4, 0.4, 1) * (size or 1)
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Material = Enum.Material.Neon
    part.Color = Color3.fromRGB(255, 100, 0)
    return part
end

local function explodeAt(position, ownerPlayer, projectileDamage, explosionRadius, burnPlayerDamage)
    -- core gameplay blast (keeps damage radius logic)
    local actualRadius = (explosionRadius or 4) + 2
    local blast = Instance.new("Part")
    blast.Name = "FlameBlast"
    blast.Size = Vector3.new(1,1,1) * actualRadius
    blast.Anchored = true
    blast.CanCollide = false
    blast.Transparency = 0.5
    blast.Material = Enum.Material.Neon
    blast.Color = Color3.fromRGB(255, 120, 0)
    blast.CFrame = CFrame.new(position)
    blast.Parent = workspace
    Debris:AddItem(blast, 0.45)

    local parts = workspace:GetPartBoundsInRadius(position, actualRadius)
    if parts and #parts > 0 then
        local seen = {}
        for _, p in ipairs(parts) do
            local mdl = p and p:FindFirstAncestorOfClass("Model")
            if mdl and not seen[mdl] then
                seen[mdl] = true
                -- skip owner player's character
                if ownerPlayer and ownerPlayer.Character and mdl == ownerPlayer.Character then continue end
                local hum = mdl:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    if projectileDamage and projectileDamage > 0 then
                        Damage.Apply(hum, projectileDamage)
                    end
                    if burnPlayerDamage and burnPlayerDamage > 0 then
                        DoT.Apply(hum, { dotType = "burn", playerDamage = burnPlayerDamage, tick = 0.25, player = ownerPlayer })
                    end
                end
            end
        end
    end

    -- Visual: prefer authored explosion model `Arrow_explosion` if present
    local asset = findCharAsset("Arrow_explosion") or findCharAsset("ArrowExplosion") or findCharAsset("Arrow_Explosion")
    if asset then
        local ok, model = pcall(function() return asset:Clone() end)
        if ok and model then
            if model:IsA("BasePart") then
                local wrapper = Instance.new("Model")
                model.Parent = wrapper
                wrapper.PrimaryPart = model
                model = wrapper
            end
            -- sanitize and store base sizes/scales
            local firstBase
            for _, d in ipairs(model:GetDescendants()) do
                if d:IsA("BasePart") then
                    if not firstBase then firstBase = d end
                    d.CanCollide = false
                    d.CanQuery = false
                    d.CanTouch = false
                    d.Anchored = true
                    if not d:GetAttribute("sukuna_base_size") then d:SetAttribute("sukuna_base_size", d.Size) end
                    d.Transparency = d.Transparency or 0
                elseif d:IsA("SpecialMesh") then
                    if not d:GetAttribute("sukuna_base_scale") then d:SetAttribute("sukuna_base_scale", d.Scale) end
                elseif d:IsA("Decal") or d:IsA("Texture") then
                    d.Transparency = d.Transparency or 0
                end
            end
            if not model.PrimaryPart and firstBase then model.PrimaryPart = firstBase end
            if model.PrimaryPart then
                model:SetPrimaryPartCFrame(CFrame.new(position))
            else
                model.Parent = workspace
                model:SetPrimaryPartCFrame(CFrame.new(position))
            end
            model.Parent = workspace

            -- animate grow + fade over ~1 second (shorter)
            local duration = 1
            local ti = TweenInfo.new(duration, Enum.EasingStyle.Linear)
            for _, d in ipairs(model:GetDescendants()) do
                pcall(function()
                    if d:IsA("BasePart") then
                        local base = d:GetAttribute("sukuna_base_size") or d.Size
                        local goal = base * 8.0
                        TweenService:Create(d, ti, { Size = goal, Transparency = 1 }):Play()
                    elseif d:IsA("SpecialMesh") then
                        local base = d:GetAttribute("sukuna_base_scale") or d.Scale
                        local goal = base * 8.0
                        TweenService:Create(d, ti, { Scale = goal }):Play()
                        -- also fade parent part if exists
                        local parentPart = d.Parent
                        if parentPart and parentPart:IsA("BasePart") then
                            TweenService:Create(parentPart, ti, { Transparency = 1 }):Play()
                        end
                    elseif d:IsA("Decal") or d:IsA("Texture") then
                        TweenService:Create(d, ti, { Transparency = 1 }):Play()
                    end
                end)
            end
            Debris:AddItem(model, duration + 0.1)
            return
        end
    end

    -- fallback: original simple blast part if no authored asset
    -- (we already spawned a simple neon blast above; nothing else to do)
end

local function fireArrow(player, stats, aimDirection)
    if not player or not player.Character then return end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local baseDamage = 50
    local pst = player:FindFirstChild("Stats")
    if pst then
        local bd = pst:FindFirstChild("BaseDamage")
        if bd and bd:IsA("NumberValue") then baseDamage = bd.Value end
    end

    -- Use aimDirection passed from charge phase; fallback to re-calculating
    local direction = aimDirection
    if not direction or direction.Magnitude <= 0 then
        local aimPos = findNearestEnemyPosition(hrp.Position) or (hrp.Position + hrp.CFrame.LookVector * 50)
        direction = (aimPos - hrp.Position)
        if direction.Magnitude <= 0 then direction = hrp.CFrame.LookVector end
        direction = direction.Unit
    end

    local projectileDamage = baseDamage * stats.damagePercent

    local model = createProjectileModel(stats.size)
    local origin = hrp.Position + direction * (stats.size * 2 + 1) + Vector3.new(0, 1, 0)
    -- orient projectile model to face the firing direction
    if model and typeof(model) == "Instance" and model:IsA("Model") and model.PrimaryPart then
        model:SetPrimaryPartCFrame(CFrame.new(origin, origin + direction))
    end
    local lifetime = 2
    local handle = Projectile.Fire({
        origin = origin,
        direction = direction,
        speed = stats.speed or 120,
        lifetime = lifetime,
        pierce = stats.pierce or 1,
        damage = projectileDamage,
        model = model,
        owner = player,
        contactRadius = 1.2,
        hitCooldownPerTarget = 0.25,
        onHit = function(hitPart, enemyModel)
            local hum = enemyModel and enemyModel:FindFirstChildOfClass("Humanoid")
            -- don't damage the owner player
            if enemyModel and player and player.Character and enemyModel == player.Character then return end
            if hum and hum.Health > 0 then
                DoT.Apply(hum, { dotType = "burn", playerDamage = projectileDamage, tick = 0.25, player = player })
            end
        end,
    })

    task.delay(0.4, function()
        if handle and handle.Instance and handle.Instance.Parent then
            local pos
            local ok, cf = pcall(function() return handle.Instance:GetPivot() end)
            if ok and typeof(cf) == "CFrame" then pos = cf.Position end
            if not pos then
                local bp = handle.Instance:FindFirstChildWhichIsA("BasePart")
                if bp then pos = bp.Position end
            end
            if pos then
                -- remove projectile visual instance so the arrow disappears when exploding
                pcall(function()
                    if handle and handle.Instance then
                        -- if Instance is part of a model, Destroy will remove it entirely
                        handle.Instance:Destroy()
                    end
                end)

                explodeAt(pos, player, projectileDamage, stats.explosionRadius, projectileDamage * (stats.burnPlayerPercent or 0.5))
            end
        end
    end)
end

local function chargeAndFire(player, stats)
    if not player or not player.Character then return end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local charge = createChargeVisual(0.5)
    Debris:AddItem(charge, stats.chargeTime + 1)

    -- SFX 3D: toca no HRP do jogador no início do charge
    SFXHelper.playAt(hrp, FLAMING_ARROW_SFX_ID, 0.9, { minDist = 10, maxDist = 80 })

    local start = os.clock()
    local duration = stats.chargeTime or 1.2
    -- fix initial position for charge visual (do NOT follow player)
    local basePos = hrp.Position + hrp.CFrame.LookVector * 3 + Vector3.new(0,1.5,0)
    while os.clock() - start < duration do
        if not player.Parent or not player.Character then
            if charge and charge.Parent then charge:Destroy() end
            return
        end
        local t = (os.clock() - start) / duration
        -- Linear scale from 0.2 -> 1.2 over the charge duration
        local scale = math.clamp(0.2 + t * 1.0, 0.2, 1.2)
        -- Update size/scale safely depending on type; keep fixed base position
        if typeof(charge) == "Instance" and charge:IsA("Model") then
            for _, d in ipairs(charge:GetDescendants()) do
                if d:IsA("SpecialMesh") then
                    local base = d:GetAttribute("sukuna_base_scale") or d.Scale
                    d.Scale = base * scale
                elseif d:IsA("BasePart") then
                    local base = d:GetAttribute("sukuna_base_size") or d.Size
                    d.Size = base * scale
                end
            end
            local aimPos = findNearestEnemyPosition(basePos)
            local forward = aimPos and (aimPos - basePos).Unit or hrp.CFrame.LookVector
            local cframe = CFrame.new(basePos, basePos + forward)
            if charge.PrimaryPart then
                charge:SetPrimaryPartCFrame(cframe)
            else
                local bp = charge:FindFirstChildWhichIsA("BasePart")
                if bp then bp.CFrame = cframe end
            end
        else
            charge.Size = Vector3.new(0.4, 0.4, 1) * scale
            local aimPos = findNearestEnemyPosition(basePos)
            local forward = aimPos and (aimPos - basePos).Unit or hrp.CFrame.LookVector
            local cframe = CFrame.new(basePos, basePos + forward)
            charge.CFrame = cframe
        end
        task.wait(0.03)
    end

    -- Capturar a direção final apontada pelo charge para passar ao fireArrow
    local finalAimPos = findNearestEnemyPosition(hrp.Position)
    local finalDir
    if finalAimPos then
        local d = (finalAimPos - hrp.Position)
        finalDir = d.Magnitude > 0 and d.Unit or hrp.CFrame.LookVector
    else
        finalDir = hrp.CFrame.LookVector
    end

    if charge and charge.Parent then charge:Destroy() end
    fireArrow(player, stats, finalDir)
end

function def.OnEquip(player, level, maxLevel)
    level = math.clamp(level or 1, 1, maxLevel or def.MaxLevel)
    local userId = player.UserId
    if ActiveByUser[userId] then def.OnUnequip(player) end

    local stats = statsPerLevel[level]
    local last = 0
    local charging = false

    local conn = RunService.Heartbeat:Connect(function()
        if not player.Parent or not player.Character then
            def.OnUnequip(player)
            return
        end
        local now = os.clock()
        if not charging and (now - last >= stats.cooldown) then
            charging = true
            last = now
            task.spawn(function()
                local ok, err = pcall(function() chargeAndFire(player, stats) end)
                if not ok then warn("[FlamingArrow] charge error:", err) end
                charging = false
            end)
        end
    end)

    ActiveByUser[userId] = { connection = conn, level = level }
    print(string.format("[FlamingArrow] Equipped for %s at level %d", player.Name, level))
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
