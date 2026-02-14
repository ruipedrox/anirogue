-- RasenShuriken.lua
-- Periodically fires a spinning projectile that explodes on first hit for AoE damage

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")
local Projectile = require(ScriptsFolder:WaitForChild("Projectile"))
local Damage = require(ScriptsFolder:WaitForChild("Combat"):WaitForChild("Damage"))
local Crit = require(ScriptsFolder:WaitForChild("Combat"):WaitForChild("Crit"))

local M = {}

local running: { [Player]: RBXScriptConnection } = {}

-- Multiplier for the final explosion visual scale (1 = original size). Requested: 10x
local EXPLOSION_SCALE_MULT = 10
-- Default contact hitbox radius for the flying shuriken (studs)
local CONTACT_RADIUS_DEFAULT = 8
-- Percent increase of contact radius per level (e.g., 0.10 = +10% por nível)
local CONTACT_RADIUS_PCT_PER_LEVEL = 0.10

local function findNearestEnemy(origin: Vector3)
    local best, bestDist
    for _, enemy in ipairs(CollectionService:GetTagged("Enemy")) do
        if enemy and enemy.Parent then
            local hum = enemy:FindFirstChildOfClass("Humanoid")
            local pp = enemy.PrimaryPart or enemy:FindFirstChild("HumanoidRootPart")
            if hum and hum.Health > 0 and pp then
                local d = (pp.Position - origin).Magnitude
                if not bestDist or d < bestDist then
                    bestDist = d
                    best = enemy
                end
            end
        end
    end
    return best
end

-- Uniformly scale a projectile instance (Model or BasePart), including SpecialMeshes
local function scaleInstance(inst: Instance, factor: number)
    if not factor or math.abs(factor - 1) < 1e-3 then return end
    if inst:IsA("Model") then
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("SpecialMesh") then
                d.Scale = d.Scale * factor
            elseif d:IsA("BasePart") then
                local s = d.Size
                d.Size = Vector3.new(
                    math.max(0.05, s.X * factor),
                    math.max(0.05, s.Y * factor),
                    math.max(0.05, s.Z * factor)
                )
            end
        end
    elseif inst:IsA("BasePart") then
        local s = inst.Size
        inst.Size = Vector3.new(
            math.max(0.05, s.X * factor),
            math.max(0.05, s.Y * factor),
            math.max(0.05, s.Z * factor)
        )
    end
end

function M.Start(player: Player)
    if running[player] then return end
    local conn
    conn = RunService.Heartbeat:Connect(function(dt)
        if not player or not player.Parent then conn:Disconnect() running[player] = nil return end
        local upgrades = player:FindFirstChild("Upgrades")
        local onInterval = upgrades and upgrades:FindFirstChild("OnInterval")
        local rs = onInterval and onInterval:FindFirstChild("RasenShuriken")
        if not rs then conn:Disconnect() running[player] = nil return end

        if ReplicatedStorage:GetAttribute("GamePaused") then
            return -- don't advance time while paused
        end

        local cooldownNV = rs:FindFirstChild("Cooldown")
        local periodNV = rs:FindFirstChild("Period")
        local multNV = rs:FindFirstChild("DamageMultiplier")
    local radiusNV = rs:FindFirstChild("Radius")
        local sizeScaleNV = rs:FindFirstChild("SizeScale")
        local period = (cooldownNV and cooldownNV.Value) or (periodNV and periodNV.Value) or 6
        local dmgMult = (multNV and multNV.Value) or 2.0
        local radius = (radiusNV and radiusNV.Value) or 12
        local sizeScale = (sizeScaleNV and sizeScaleNV.Value) or 1
    -- Optional projectile contact radius (enlarge the shuriken's own hitbox while flying)
    local contactNV = rs:FindFirstChild("ContactRadius")
    local contactRadius = (contactNV and contactNV.Value) or CONTACT_RADIUS_DEFAULT

        -- Persist remaining cooldown so it doesn't reset when choosing cards
        local remainingNV = rs:FindFirstChild("Remaining")
        if not remainingNV then
            remainingNV = Instance.new("NumberValue")
            remainingNV.Name = "Remaining"
            remainingNV.Value = period
            remainingNV.Parent = rs
        end
    -- Decrement remaining time only when not paused
    remainingNV.Value = math.max(0, (remainingNV.Value or period) - dt)
    if remainingNV.Value > 0 then return end
    -- Do NOT reset yet; only reset after a successful cast.

        local character = player.Character
        -- Validate character and compute origin
        local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
        if not (character and root) then return end
        local origin = root.Position + Vector3.new(0, 2, 0)

        -- Determine burst count and angles
        local countNV = rs:FindFirstChild("Count")
        local count = (countNV and countNV.Value) or 1
        if count < 1 then count = 1 end
        local theta0 = math.random() * math.pi * 2
        local angleStep = (2 * math.pi) / count

        -- Find projectile model
        local shared = ReplicatedStorage:FindFirstChild("Shared")
        local chars = shared and shared:FindFirstChild("Chars")
        local narutoFolder = chars and chars:FindFirstChild("Naruto_5")
        local modelRS = narutoFolder and narutoFolder:FindFirstChild("Rasenshuriken")
        if not modelRS then return end

        -- Read player damage stats
        local stats = player:FindFirstChild("Stats")
        local function getNumber(name, default)
            local nv = stats and stats:FindFirstChild(name)
            if nv and nv:IsA("NumberValue") then return nv.Value end
            return default
        end
        local baseDamage = getNumber("BaseDamage", 0)
        local dmgPercent = getNumber("DamagePercent", 0)
        local critChance = getNumber("CritChance", 0)
        local critMult = getNumber("CritDamage", 1)
        local percentMult = 1 + math.max(-0.99, (dmgPercent or 0) / 100)

        for i = 0, count - 1 do
            local theta = theta0 + i * angleStep
            local dir = Vector3.new(math.cos(theta), 0, math.sin(theta))
            local proj = modelRS:Clone()
            proj.Parent = workspace
            pcall(function() scaleInstance(proj, math.max(0.1, sizeScale)) end)

            -- determine a base part for position/rotation
            local main = proj:FindFirstChild("main", true)
            local basePart = nil
            if main and main:IsA("BasePart") then
                basePart = main
            else
                basePart = proj:IsA("Model") and (proj.PrimaryPart or proj:FindFirstChildWhichIsA("BasePart", true)) or nil
            end
            if proj:IsA("Model") and basePart and not proj.PrimaryPart then
                pcall(function() proj.PrimaryPart = basePart end)
            end

            local travelSpeed = 90
            local lifeTime = 3
            local distance = travelSpeed * lifeTime
            local endPos = origin + dir * distance
            local endCF = CFrame.new(endPos, endPos + dir)

            -- starting CFrame for the projectile (defensive: ensure it's set)
            local startCF = CFrame.new(origin, origin + dir)
            pcall(function() if proj:IsA("Model") then proj:PivotTo(startCF) else (proj :: any).CFrame = startCF end end)

            -- ensure parts won't react to physics (anchor them) and enable particle/trail effects
            for _, d in ipairs(proj:GetDescendants()) do
                if d:IsA("BasePart") then
                    d.Anchored = true
                    d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.Massless = true; d.CastShadow = false
                elseif d:IsA("ParticleEmitter") then
                    d.Enabled = true
                elseif d:IsA("Trail") then
                    d.Enabled = true
                end
            end

            -- prepare parts: anchor basePart and weld visual parts to it so moving basePart moves whole model
            for _, d in ipairs(proj:GetDescendants()) do
                if d:IsA("BasePart") then
                    d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.Massless = true; d.CastShadow = false
                    if d == basePart then
                        d.Anchored = true
                    else
                        d.Anchored = false
                        -- attach via WeldConstraint to basePart
                        if basePart then
                            if not d:FindFirstChild("RasenWeldToBase") then
                                local ok, w = pcall(function()
                                    local weld = Instance.new("WeldConstraint")
                                    weld.Name = "RasenWeldToBase"
                                    weld.Part0 = basePart
                                    weld.Part1 = d
                                    weld.Parent = d
                                    return weld
                                end)
                            end
                        end
                    end
                elseif d:IsA("ParticleEmitter") then
                    d.Enabled = true
                elseif d:IsA("Trail") then
                    d.Enabled = true
                end
            end
            local travelSpeed = 90
            local lifeTime = 3
            local distance = travelSpeed * lifeTime
            local endPos = origin + dir * distance
            local endCF = CFrame.new(endPos, endPos + dir)

            -- driver part and tween
            local driverPart = Instance.new("Part")
            driverPart.Name = "RasenDriver"
            driverPart.Size = Vector3.new(0.2, 0.2, 0.2)
            driverPart.Transparency = 1
            driverPart.Anchored = true
            driverPart.CanCollide = false
            driverPart.CanQuery = false
            driverPart.CanTouch = false
            driverPart.Parent = workspace
            driverPart.CFrame = startCF
            local tween = TweenService:Create(driverPart, TweenInfo.new(lifeTime, Enum.EasingStyle.Linear), { CFrame = endCF })
            tween:Play()

            local thisProj = proj
            local destroyed = false
            -- per-projectile spin settings (radians per second)
            local spinSpeed = (rs and rs:FindFirstChild("SpinSpeed") and rs.SpinSpeed.Value) or (2 * math.pi) -- 1 rev/sec
            local spinOffset = math.random() * math.pi * 2
            local hbConn
            local function cleanup(source)
                if destroyed then return end
                destroyed = true
                if hbConn then hbConn:Disconnect() hbConn = nil end
                pcall(function() tween:Cancel() end)
                if driverPart and driverPart.Parent then pcall(function() driverPart:Destroy() end) end
                if thisProj and thisProj.Parent then pcall(function() thisProj:Destroy() end) end
            end

            -- fallback cleanup
            task.delay(lifeTime + 1, function() pcall(function() cleanup("fallback") end) end)

            -- heartbeat: pivot model to driver and check collisions
            local spawnedAt = os.clock()
            local armedDelay = 0.08
            local ovParams = OverlapParams.new()
            ovParams.FilterType = Enum.RaycastFilterType.Exclude
            local excludes = { proj }
            if character and character:IsA("Model") then table.insert(excludes, character) end
            ovParams.FilterDescendantsInstances = excludes

            hbConn = RunService.Heartbeat:Connect(function()
                if not proj or not proj.Parent then if hbConn then hbConn:Disconnect() end return end
                if os.clock() - spawnedAt < armedDelay then return end
                if driverPart and driverPart.Parent then
                    -- compute spin angle and pivot model to driver CFrame plus rotation
                    local angle = (os.clock() - spawnedAt) * spinSpeed + spinOffset
                    local spunCFrame = driverPart.CFrame * CFrame.Angles(0, -angle, 0)
                    pcall(function() if proj:IsA("Model") then proj:PivotTo(spunCFrame) else (proj :: any).CFrame = spunCFrame end end)
                end
                local centerPos = (driverPart and driverPart.Position) or (basePart and basePart.Position)
                if not centerPos then return end
                local traveled = (centerPos - origin).Magnitude
                if traveled >= (distance - 0.5) then cleanup("max_range") return end
                local cr = contactRadius > 0 and contactRadius or (basePart and basePart.Size.Magnitude * 0.4)
                local nearby = workspace:GetPartBoundsInRadius(centerPos, cr, ovParams)
                if nearby and #nearby > 0 then
                    local enemyModel = nil
                    for _, p in ipairs(nearby) do
                        local node = p
                        while node do
                            if node:IsA("Model") and node:FindFirstChildOfClass("Humanoid") then enemyModel = node break end
                            node = node.Parent
                        end
                        if enemyModel then break end
                    end
                    if enemyModel then
                        local mult = select(1, Crit.Resolve(critChance, critMult))
                        local dealt = baseDamage * percentMult * dmgMult * mult
                        for _, other in ipairs(CollectionService:GetTagged("Enemy")) do
                            local oh = other:FindFirstChildOfClass("Humanoid")
                            if oh and oh.Health > 0 then
                                local pos
                                local ok, cf = pcall(function() return (other :: Model):GetPivot() end)
                                if ok and typeof(cf) == "CFrame" then pos = cf.Position else local opp = other.PrimaryPart or other:FindFirstChild("HumanoidRootPart") pos = opp and opp.Position or nil end
                                if pos and (pos - centerPos).Magnitude <= radius then
                                    local creator = oh:FindFirstChild("creator")
                                    if not creator then
                                        creator = Instance.new("ObjectValue")
                                        creator.Name = "creator"
                                        creator.Value = player
                                        creator.Parent = oh
                                        task.delay(2, function() if creator and creator.Parent then creator:Destroy() end end)
                                    end
                                    Damage.Apply(oh, dealt)
                                end
                            end
                        end
                        -- spawn explosion VFX (reuse existing explosion template)
                        local shared2 = ReplicatedStorage:FindFirstChild("Shared")
                        local chars2 = shared2 and shared2:FindFirstChild("Chars")
                        local naruto2 = chars2 and chars2:FindFirstChild("Naruto_5")
                        local explosionTemplate = naruto2 and naruto2:FindFirstChild("RasenExplosion")
                        if explosionTemplate then
                            local clone = explosionTemplate:Clone()
                            -- animateModel: place, enable effects, scale up and fade out
                            local function setPartsProps(container)
                                for _, d in ipairs(container:GetDescendants()) do
                                    if d:IsA("BasePart") then
                                        d.Anchored = true; d.CanCollide=false; d.CanQuery=false; d.CanTouch=false; d.Massless=true; d.CastShadow=false; d.Transparency=0
                                    elseif d:IsA("ParticleEmitter") then d.Enabled = true
                                    elseif d:IsA("Trail") then d.Enabled = true end
                                end
                            end
                            local function applyFade(container, alpha)
                                for _, d in ipairs(container:GetDescendants()) do
                                    if d:IsA("BasePart") then d.Transparency = alpha
                                    elseif d:IsA("Decal") then d.Transparency = alpha
                                    elseif d:IsA("ParticleEmitter") then pcall(function() d.Transparency = NumberSequence.new(alpha) end) end
                                end
                            end
                            local function scaleNumberSequence(seq: NumberSequence, factor: number)
                                local ok, res = pcall(function()
                                    local kps = {}
                                    for i3, kp in ipairs(seq.Keypoints) do kps[i3] = NumberSequenceKeypoint.new(kp.Time, kp.Value * factor, kp.Envelope) end
                                    return NumberSequence.new(kps)
                                end)
                                return ok and res or seq
                            end
                            local function scaleEffects(container: Instance, factor: number)
                                for _, d in ipairs(container:GetDescendants()) do
                                    if d:IsA("ParticleEmitter") then
                                        local ok, scaled = pcall(scaleNumberSequence, d.Size, factor)
                                        if ok and scaled then d.Size = scaled end
                                    elseif d:IsA("Trail") then
                                        d.WidthScale = NumberSequence.new(1 * factor)
                                    elseif d:IsA("Beam") then
                                        if d:IsA("Beam") then pcall(function() d.Width0 = d.Width0 * factor; d.Width1 = d.Width1 * factor end) end
                                    elseif d:IsA("BillboardGui") then
                                        pcall(function() d.Size = UDim2.new(d.Size.X.Scale * factor, d.Size.X.Offset * factor, d.Size.Y.Scale * factor, d.Size.Y.Offset * factor) end)
                                    end
                                end
                            end
                            local function animateModel(model)
                                pcall(function() model:PivotTo(CFrame.new(centerPos)) end)
                                model.Parent = workspace
                                setPartsProps(model)
                                -- start driver value to control scale/fade
                                local driver2 = Instance.new("NumberValue")
                                driver2.Value = 0.5; driver2.Parent = model
                                local particleEmitters = {}
                                local emitterOrigSizes = {}
                                for _, d in ipairs(model:GetDescendants()) do
                                    if d:IsA("ParticleEmitter") then table.insert(particleEmitters, d); emitterOrigSizes[d] = d.Size end
                                end
                                local conn2; conn2 = driver2.Changed:Connect(function(val)
                                    if not model or not model.Parent then if conn2 then conn2:Disconnect() end return end
                                    -- scale visuals and fade
                                    local fadeStart, fadeEnd = 0.4, 1 * EXPLOSION_SCALE_MULT
                                    local alpha = (val >= fadeStart) and math.clamp((val - fadeStart)/(fadeEnd - fadeStart),0,1) or 0
                                    applyFade(model, alpha); scaleEffects(model, val)
                                    pcall(function() if model.ScaleTo then model:ScaleTo(val) end end)
                                end)
                                local growTime = 0.4
                                TweenService:Create(driver2, TweenInfo.new(growTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 1 * EXPLOSION_SCALE_MULT }):Play()
                                task.delay(growTime, function() if conn2 then conn2:Disconnect() end if model then model:Destroy() end end)
                            end
                            animateModel(clone)
                        end
                        cleanup("enemy_hit")
                        return
                    end
                end
            end)

            tween.Completed:Connect(function() cleanup("tween_completed") end)
        end
        -- Reset timer only after we successfully fired
        remainingNV.Value = period
    end)
    running[player] = conn
end

function M.Stop(player: Player)
    local conn = running[player]
    if conn then conn:Disconnect() end
    running[player] = nil
end

-- Apply or level-up the RasenShuriken card for the player.
-- Ensures folders/values exist, increments level up to max, writes Count and DamageMultiplier,
-- and starts the periodic loop.
function M.Apply(player: Player, def)
    def = def or {}
    if not player or not player.Parent then return end
    -- Ensure Upgrades/OnInterval/RasenShuriken exists
    local upgrades = player:FindFirstChild("Upgrades")
    if not upgrades then
        upgrades = Instance.new("Folder")
        upgrades.Name = "Upgrades"
        upgrades.Parent = player
    end
    local onInterval = upgrades:FindFirstChild("OnInterval") or Instance.new("Folder")
    onInterval.Name = "OnInterval"
    onInterval.Parent = upgrades
    local rs = onInterval:FindFirstChild("RasenShuriken") or Instance.new("Folder")
    rs.Name = "RasenShuriken"
    rs.Parent = onInterval

    -- Helpers
    local function ensureNumber(parent, name, value)
        local nv = parent:FindFirstChild(name)
        if not nv then
            nv = Instance.new("NumberValue")
            nv.Name = name
            nv.Parent = parent
        end
        nv.Value = value
        return nv
    end
    local function ensureInt(parent, name, value)
        local iv = parent:FindFirstChild(name)
        if not iv then
            iv = Instance.new("IntValue")
            iv.Name = name
            iv.Parent = parent
        end
        iv.Value = value
        return iv
    end

    -- Base params from card def
    local cooldown = typeof(def.cooldown) == "number" and def.cooldown or 6
    local radius = (typeof(def.radius) == "number" and def.radius) or 12
    local contactRadius = (typeof(def.contactRadius) == "number" and def.contactRadius) or CONTACT_RADIUS_DEFAULT
    ensureNumber(rs, "Cooldown", cooldown)
    ensureNumber(rs, "Radius", radius)
    -- Persist base and pct for contact radius scaling
    local baseCR = (typeof(def.contactRadiusBase) == "number" and def.contactRadiusBase)
        or (rs:FindFirstChild("ContactRadiusBase") and rs.ContactRadiusBase.Value)
        or contactRadius
    local pctPerLevel = (typeof(def.contactRadiusPctPerLevel) == "number" and def.contactRadiusPctPerLevel)
        or (rs:FindFirstChild("ContactRadiusPctPerLevel") and rs.ContactRadiusPctPerLevel.Value)
        or CONTACT_RADIUS_PCT_PER_LEVEL
    ensureNumber(rs, "ContactRadiusBase", baseCR)
    ensureNumber(rs, "ContactRadiusPctPerLevel", pctPerLevel)

    -- Level tracking under RunTrack
    local runTrack = player:FindFirstChild("RunTrack") or Instance.new("Folder")
    runTrack.Name = "RunTrack"
    runTrack.Parent = player
    local folder = runTrack:FindFirstChild("RasenShuriken") or Instance.new("Folder")
    folder.Name = "RasenShuriken"
    folder.Parent = runTrack
    local lvl = folder:FindFirstChild("Level") or Instance.new("IntValue")
    lvl.Name = "Level"
    lvl.Parent = folder
    local maxLevel = (typeof(def.maxLevel) == "number" and def.maxLevel) or 5
    lvl.Value = math.min(maxLevel, (lvl.Value or 0) + 1)
    local L = math.max(1, lvl.Value)

    -- Size scaling: 25% per level, with a final-level bonus
    local sizePerLevel = (typeof(def.sizePerLevel) == "number" and def.sizePerLevel) or 0.25
    local finalLevelExtra = (typeof(def.finalLevelExtra) == "number" and def.finalLevelExtra) or 0.25
    local sizeScale = 1 + math.max(0, sizePerLevel * (L - 1)) + ((L >= maxLevel) and math.max(0, finalLevelExtra) or 0)

    -- Per-level rules: base Count = L; at final level, add +2 instead of +1 (i.e., count = L + 1)
    local count = (L >= maxLevel) and (L + 1) or L
    local damageMultiplier = 0.40 * L
    ensureInt(rs, "Count", count)
    ensureNumber(rs, "DamageMultiplier", damageMultiplier)
    ensureNumber(rs, "SizeScale", sizeScale)

    -- Apply percent-per-level scaling to contact radius: base * (1 + pct * (L - 1))
    local scaledCR = math.max(0, (rs:FindFirstChild("ContactRadiusBase") and rs.ContactRadiusBase.Value or CONTACT_RADIUS_DEFAULT)
        * (1 + (rs:FindFirstChild("ContactRadiusPctPerLevel") and rs.ContactRadiusPctPerLevel.Value or CONTACT_RADIUS_PCT_PER_LEVEL) * (L - 1)))
    ensureNumber(rs, "ContactRadius", scaledCR)

    -- Start loop (idempotent)
    M.Start(player)
end

return M
