-- ShadowClone.lua (Rewritten)
-- Spawns a short-lived clone at the enemy's death location.
-- The clone attacks nearby enemies for a few seconds using half of the player's damage, then disappears.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")
local Projectile = require(ScriptsFolder:WaitForChild("Projectile"))
local OnHit = require(ScriptsFolder:WaitForChild("Combat"):WaitForChild("OnHit"))
local Damage = require(ScriptsFolder:WaitForChild("Combat"):WaitForChild("Damage"))
local Crit = require(ScriptsFolder:WaitForChild("Combat"):WaitForChild("Crit"))
local DoT = require(ScriptsFolder:WaitForChild("Combat"):WaitForChild("DoT"))

local M = {}
local ActiveByUserId: {[number]: number} = {}

-- Helpers
-- Previously used to immobilize the clone; no longer anchoring to allow natural physics.
local function setNetworkOwnerServer(container: Instance)
    for _, d in ipairs(container:GetDescendants()) do
        if d:IsA("BasePart") then
            pcall(function() d:SetNetworkOwner(nil) end)
        end
    end
end

local function safeDestroy(inst: Instance?)
    if not inst then return end
    pcall(function()
        if inst.Parent then inst:Destroy() end
    end)
end

local function getEquippedWeaponModel(player: Player): Instance?
    local equippedFolder = player:FindFirstChild("EquippedItems")
    local equippedFolder = player:FindFirstChild("EquippedItems")
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    local chars = shared and shared:FindFirstChild("Chars")
    local narutoFolder = chars and chars:FindFirstChild("Naruto_5")
    if not equippedFolder then return nil end
    local weaponOV = equippedFolder:FindFirstChild("Weapon")
    local weaponModule = weaponOV and weaponOV:IsA("ObjectValue") and weaponOV.Value
    if not (weaponModule and weaponModule:IsA("ModuleScript")) then return nil end
    local container = weaponModule.Parent
    if not container then return nil end
    local preferred = {"Projectile", "Model", "ProjectileModel"}
    for _, name in ipairs(preferred) do
        local child = container:FindFirstChild(name)
        if child and (child:IsA("Model") or child:IsA("BasePart")) then
            return child
        end
    end
    for _, ch in ipairs(container:GetChildren()) do
        if ch:IsA("Model") or ch:IsA("BasePart") then
            return ch
        end
    end
    return nil
end

-- Try to find a reasonable attack Animation to play on the clone's Humanoid
local function findAttackAnimation(player: Player, weaponModel: Instance?): Animation?
    local candidates: {Animation} = {}
    local function collectAnims(container: Instance?)
        if not container then return end
        for _, d in ipairs(container:GetDescendants()) do
            if d:IsA("Animation") then
                table.insert(candidates, d)
            end
        end
    end
    -- Prefer animations from the weapon's container, then player's character
    if weaponModel and weaponModel.Parent then collectAnims(weaponModel.Parent) end
    collectAnims(player.Character)
    -- Heuristic: prefer names that look like attack
    local best
    for _, a in ipairs(candidates) do
        local n = string.lower(a.Name or "")
        if n:find("attack") or n:find("swing") or n:find("punch") then
            best = a
            break
        end
    end
    return best or candidates[1]
end

local function getNearestEnemy(position: Vector3, maxRange: number)
    local best, bestDist
    for _, enemy in ipairs(CollectionService:GetTagged("Enemy")) do
        if enemy and enemy.Parent then
            local ok, cf = pcall(function() return (enemy :: Model):GetPivot() end)
            local pos
            if ok and typeof(cf) == "CFrame" then
                pos = cf.Position
            else
                local pp = (enemy :: Model).PrimaryPart or (enemy :: Model):FindFirstChild("HumanoidRootPart")
                pos = pp and pp.Position or nil
            end
            if pos then
                local d = (pos - position).Magnitude
                if d <= maxRange and (not bestDist or d < bestDist) then
                    bestDist = d
                    best = enemy
                end
            end
        end
    end
    return best
end

-- Compute final damage numbers from player stats (BaseDamage, DamagePercent, Crit, DoT) and apply a multiplier
local function computeAndApplyDamage(player: Player, hum: Humanoid, baseMult: number)
    local statsFolder = player:FindFirstChild("Stats")
    if not statsFolder then return 0, false end
    local function getNumber(name, default)
        local nv = statsFolder:FindFirstChild(name)
        if nv and nv:IsA("NumberValue") then return nv.Value end
        return default
    end
    local baseDamage = getNumber("BaseDamage", 0)
    local dmgPercent = getNumber("DamagePercent", 0)
    local critChance = getNumber("CritChance", 0)
    local critMult = getNumber("CritDamage", 1)
    local dmgMult = 1 + math.max(-0.99, (dmgPercent or 0) / 100)
    local mult, isCrit = Crit.Resolve(critChance, critMult)
    local dealt = baseDamage * dmgMult * mult * baseMult
    Damage.Apply(hum, dealt)

    -- DoT optional
    local dotEnabled = false
    do
        local bv = statsFolder:FindFirstChild("DoTEnabled")
        dotEnabled = bv and bv:IsA("BoolValue") and bv.Value or false
    end
    if dotEnabled then
        local totalTime = math.max(0.1, getNumber("DoTTime", 1))
        local eff = getNumber("DoTEffectiveness", 1)
        local dotCritFlag = false
        do
            local bv = statsFolder:FindFirstChild("DoTCrit")
            dotCritFlag = bv and bv:IsA("BoolValue") and bv.Value or false
        end
        local totalDotBase = baseDamage * eff * baseMult
        local totalDot = dotCritFlag and (totalDotBase * mult) or totalDotBase
        DoT.Apply(hum, { totalTime = totalTime, totalDamage = totalDot, tick = 0.25 })
    end
    return dealt, isCrit
end

-- Remove references that point back to the player's original character and risky constraints/accessories
local function sanitizeCloneModel(model: Model, sourceChar: Model?)
    -- Names / substrings (case-insensitive) de partes temporárias de habilidades que não queremos copiar
    local EXCLUDED_SUBSTRINGS = {
        "kame",      -- kame / kamehameha
        "beam",      -- generic beam parts
        "kameha",    -- extra safety
        "projectiletemp", -- se usares nomes assim
    }
    local function shouldExclude(inst: Instance)
        -- Attribute flags (se quiseres marcar manualmente no runtime)
        if inst:GetAttribute("AbilityEffect") or inst:GetAttribute("TempAbility") then
            return true
        end
        local name = string.lower(inst.Name)
        for _, sub in ipairs(EXCLUDED_SUBSTRINGS) do
            if name:find(sub) then
                return true
            end
        end
        return false
    end
    for _, d in ipairs(model:GetDescendants()) do
        -- Remove partes temporárias de habilidades (mantém HumanoidRootPart / corpo / acessórios)
        if d:IsA("BasePart") or d:IsA("Model") then
            if shouldExclude(d) then
                pcall(function() d:Destroy() end)
                continue
            end
        elseif d:IsA("Attachment") or d:IsA("ParticleEmitter") or d:IsA("Beam") then
            if shouldExclude(d) then
                pcall(function() d:Destroy() end)
                continue
            end
        end
        if d:IsA("ObjectValue") then
            local v = d.Value
            if v and typeof(v) == "Instance" and sourceChar and v:IsDescendantOf(sourceChar) then
                pcall(function() d.Value = nil end)
            end
        elseif d:IsA("JointInstance") then
            local part0 = d.Part0
            local part1 = d.Part1
            local invalid0 = part0 and (not part0:IsDescendantOf(model))
            local invalid1 = part1 and (not part1:IsDescendantOf(model))
            if invalid0 then pcall(function() d.Part0 = nil end) end
            if invalid1 then pcall(function() d.Part1 = nil end) end
            if (invalid0 and invalid1) then
                pcall(function() d:Destroy() end)
            end
        -- keep Constraints and Accessories so the clone visual (hats etc.) stays intact
        elseif d:IsA("Tool") or d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
            pcall(function() d:Destroy() end)
        end
    end
end

-- Spawn a clone at position; attacks enemies for `duration` seconds.
function M.Spawn(player: Player, position: Vector3, duration: number)
    if not player or not player.Parent then return end
    duration = tonumber(duration) or 5
    if typeof(position) ~= "Vector3" then
        warn("[ShadowClone] Spawn called with invalid position; aborting")
        return
    end

    -- Enforce max active clones per player (from upgrades, default 3 if not set)
    local maxActive = 3
    do
        local upgrades = player:FindFirstChild("Upgrades")
        local onKill = upgrades and upgrades:FindFirstChild("OnKill")
        local sc = onKill and onKill:FindFirstChild("ShadowClone")
        local cap = sc and sc:FindFirstChild("MaxActive")
        if cap and cap:IsA("IntValue") then
            maxActive = math.max(0, cap.Value)
        end
    end
    -- Use robust per-player counter to avoid race conditions on rapid kills
    local uid = player.UserId
    local current = ActiveByUserId[uid] or 0
    if current >= maxActive then
        return -- at cap, do not spawn a new clone
    end
    ActiveByUserId[uid] = current + 1

    -- Build a safe, anchored visual clone using a deep clone of the player's Character
    local sourceChar = player.Character
    local model: Model
    local rootPart: BasePart? = nil
    local humanoid: Humanoid? = nil
    if sourceChar and sourceChar:IsA("Model") then
        -- Characters often have Archivable=false; temporarily allow cloning
        local prevArchivable = sourceChar.Archivable
        sourceChar.Archivable = true
        local ok, cloned = pcall(function() return sourceChar:Clone() end)
        sourceChar.Archivable = prevArchivable
        if ok and cloned and cloned:IsA("Model") then
            model = cloned
            model.Name = ("ShadowClone_%d_%d"):format(player.UserId, math.floor(os.clock() * 1000) % 100000)
            humanoid = model:FindFirstChildOfClass("Humanoid")
            rootPart = (model:FindFirstChild("HumanoidRootPart") :: BasePart) or model.PrimaryPart
        else
            model = Instance.new("Model")
            model.Name = ("ShadowClone_%d_%d"):format(player.UserId, math.floor(os.clock() * 1000) % 100000)
            warn("[ShadowClone] Failed to deep-clone character; spawning minimal clone model instead")
        end
    else
        model = Instance.new("Model")
        model.Name = ("ShadowClone_%d_%d"):format(player.UserId, math.floor(os.clock() * 1000) % 100000)
    end

    if not humanoid then
        humanoid = Instance.new("Humanoid")
        humanoid.Name = "Humanoid"
        humanoid.Parent = model
    end
    if not rootPart then
        local part = Instance.new("Part")
        part.Name = "HumanoidRootPart"
        part.Anchored = false
        part.CanCollide = false
        part.Transparency = 1
        part.Size = Vector3.new(2, 2, 1)
        part.Parent = model
        rootPart = part
    end
    if rootPart and not model.PrimaryPart then model.PrimaryPart = rootPart end

    model.Parent = workspace
    model:SetAttribute("SpawnedAt", position)
    local spawnCF = CFrame.new(position + Vector3.new(0, 2, 0))
    -- sanitize after parenting so Instance relationships are valid
    sanitizeCloneModel(model, sourceChar)
    -- keep physics enabled; only ensure server network ownership
    setNetworkOwnerServer(model)
    model:PivotTo(spawnCF)

    -- Tag it as a clone
    CollectionService:AddTag(model, "ShadowClone")
    model:SetAttribute("OwnerUserId", player.UserId)

    -- UI de-emphasis
    pcall(function()
        humanoid.DisplayName = "Clone"
        humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
        humanoid.NameDisplayDistance = 0
        humanoid.AutoRotate = false
    end)

    -- Attack loop: use player's stats, halve the damage, run for `duration` seconds
    local statsFolder = player:FindFirstChild("Stats")
    if not statsFolder then
        -- No stats; just cleanup later
        task.delay(duration, function() safeDestroy(model) end)
        return
    end

    local function getNumber(name, default)
        local nv = statsFolder:FindFirstChild(name)
        if nv and nv:IsA("NumberValue") then return nv.Value end
        return default
    end

    local atkPerSec = getNumber("AttackSpeed", 1)
    local range = getNumber("Range", 80)
    local projSpeed = getNumber("ProjectileSpeed", 80)
    local pierce = math.floor(getNumber("Pierce", 1))
    local lifetime = getNumber("Lifetime", 2)

    local interval = math.max(1 / math.max(atkPerSec, 0.001), 0.1)
    local nextAttackTime = 0
    local turnSpeedDeg = getNumber("TurnSpeed", 1) -- degrees per second (slower default)

    local weaponModel = getEquippedWeaponModel(player)
    -- Animation setup (optional)
    local animator: Animator? = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end
    local attackTrack: AnimationTrack? = nil
    local attackAnimSpeed = math.clamp(atkPerSec, 0.5, 2)
    do
        local anim = findAttackAnimation(player, weaponModel)
        if anim and animator then
            local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
            if ok and track then
                attackTrack = track
                attackTrack.Priority = Enum.AnimationPriority.Action
                attackTrack.Looped = false -- play only when attacking
            end
        end
    end
    -- Track last known root position; start at spawn and update each tick
    local lastRootPos = spawnCF.Position
    local conn
    conn = RunService.Heartbeat:Connect(function(dt)
        if not model or not model.Parent then if conn then conn:Disconnect() end return end
        local now = os.clock()
        -- Get current root position from model pivot or rootPart
        local rootPos
        do
            local ok, cf = pcall(function() return model:GetPivot() end)
            rootPos = (ok and typeof(cf) == "CFrame") and cf.Position or (rootPart and rootPart.Position) or lastRootPos
            lastRootPos = rootPos
        end

        local enemy = getNearestEnemy(rootPos, range)
        if not enemy then return end
        local targetPos
        do
            local ok, cf = pcall(function() return enemy:GetPivot() end)
            if ok and typeof(cf) == "CFrame" then
                targetPos = cf.Position
            else
                local pp = enemy.PrimaryPart or enemy:FindFirstChild("HumanoidRootPart")
                targetPos = pp and pp.Position or nil
            end
        end
        if not targetPos then return end

        -- Attack only at interval
        if now < nextAttackTime then return end
        nextAttackTime = now + interval

        -- On attack: tween the rotation once towards the target (yaw only)
        if rootPart then
            local cf = rootPart.CFrame
            local curLook = cf.LookVector
            local desiredDir = (Vector3.new(targetPos.X, cf.Position.Y, targetPos.Z) - cf.Position)
            if desiredDir.Magnitude > 1e-3 then
                desiredDir = desiredDir.Unit
                -- Angle between current look and desired direction (0..pi)
                local dot = math.clamp(curLook.X * desiredDir.X + curLook.Z * desiredDir.Z, -1, 1)
                local angDeg = math.deg(math.acos(dot))
                local speed = math.max(1, turnSpeedDeg) -- deg/s
                local duration = math.clamp(angDeg / speed, 0.05, 0.3)
                -- Use lookAt to ensure correct facing (avoids opposite rotation)
                local desiredCF = CFrame.lookAt(cf.Position, Vector3.new(targetPos.X, cf.Position.Y, targetPos.Z))
                if rootPart:FindFirstChild("_TurnTween") then
                    local tag = rootPart:FindFirstChild("_TurnTween");
                    if tag and tag.Value then pcall(function() tag.Value:Cancel() end) end
                    pcall(function() tag:Destroy() end)
                end
                local tween = TweenService:Create(rootPart, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { CFrame = desiredCF })
                local holder = Instance.new("ObjectValue")
                holder.Name = "_TurnTween"
                holder.Value = tween
                holder.Parent = rootPart
                tween:Play()
                tween.Completed:Connect(function()
                    if holder and holder.Parent then holder:Destroy() end
                end)
            end
        end

        -- Play attack animation only when we actually fire
        if attackTrack then
            pcall(function()
                attackTrack:Stop(0)
                attackTrack.TimePosition = 0
                attackTrack:AdjustSpeed(attackAnimSpeed)
                attackTrack:Play(0.05)
            end)
        end

        local origin = rootPos + Vector3.new(0, 1.2, 0)
        local dir = targetPos - origin
        if dir.Magnitude < 1e-3 then return end
        dir = dir.Unit

        Projectile.FireFromWeapon({
            weaponStats = { ProjectileSpeed = projSpeed, Pierce = pierce, Lifetime = lifetime },
            origin = origin,
            direction = dir,
            owner = player, -- attribute to player for ignore/attribution, never to the clone
            ignore = { model }, -- avoid self-hit
            damage = 0, -- we apply damage via onHit with final stats
            model = weaponModel,
            orientationOffset = CFrame.Angles(0, math.rad(-90), 0),
            hitCooldownPerTarget = 0.15,
            onHit = function(hitPart, enemyModel)
                local hum: Humanoid? = nil
                if enemyModel and enemyModel:IsA("Model") then
                    hum = enemyModel:FindFirstChildOfClass("Humanoid")
                end
                if not hum and hitPart and hitPart.Parent then
                    local ancestor = hitPart.Parent
                    -- Walk up to find a Model with a Humanoid (prefer ones tagged Enemy)
                    while ancestor and ancestor ~= workspace do
                        if ancestor:IsA("Model") then
                            local h = ancestor:FindFirstChildOfClass("Humanoid")
                            if h then
                                if CollectionService:HasTag(ancestor, "Enemy") then
                                    hum = h
                                    break
                                else
                                    -- fallback if no Enemy tag found higher up
                                    hum = hum or h
                                end
                            end
                        end
                        ancestor = ancestor.Parent
                    end
                end
                if not hum then return end

                -- Tag creator for attribution
                do
                    local creator = hum:FindFirstChild("creator")
                    if not creator then
                        creator = Instance.new("ObjectValue")
                        creator.Name = "creator"
                        creator.Value = player
                        creator.Parent = hum
                        task.delay(2, function() if creator and creator.Parent then creator:Destroy() end end)
                    end
                end

                local dealt, isCrit = computeAndApplyDamage(player, hum, 0.5)
                OnHit.Process({ player = player, statsFolder = statsFolder, isCrit = isCrit, dealt = dealt }, hum)
            end
        })
    end)

    -- Ensure we release the active counter exactly once
    local released = false
    local function release()
        if released then return end
        released = true
        ActiveByUserId[uid] = math.max(0, (ActiveByUserId[uid] or 0) - 1)
    end
    model.AncestryChanged:Connect(function(_, parent)
        if not parent then release() end
    end)
    task.delay(duration, function()
        if conn then conn:Disconnect() end
        if attackTrack then pcall(function() attackTrack:Stop(0) end) end
        release()
        safeDestroy(model)
    end)
end

-- Configure OnKill settings for this card. Keep it simple and deterministic by default.
function M.Apply(player: Player, def)
    if not player or not player.Parent then return end
    def = def or {}

    local upgrades = player:FindFirstChild("Upgrades")
    if not upgrades then
        upgrades = Instance.new("Folder")
        upgrades.Name = "Upgrades"
        upgrades.Parent = player
    end
    local onKill = upgrades:FindFirstChild("OnKill") or Instance.new("Folder")
    onKill.Name = "OnKill"
    onKill.Parent = upgrades
    local sc = onKill:FindFirstChild("ShadowClone") or Instance.new("Folder")
    sc.Name = "ShadowClone"
    sc.Parent = onKill

    -- Chance handling: support absolute def.chance, or additive def.baseChance up to def.maxChance
    local chanceNV = sc:FindFirstChild("Chance") or Instance.new("NumberValue")
    chanceNV.Name = "Chance"
    chanceNV.Parent = sc
    local hasAbs = typeof(def.chance) == "number"
    local baseChance = typeof(def.baseChance) == "number" and def.baseChance or 0
    local maxChance = typeof(def.maxChance) == "number" and def.maxChance or 1
    if hasAbs then
        chanceNV.Value = math.clamp(def.chance, 0, maxChance)
    else
        local current = chanceNV.Value or 0
        chanceNV.Value = math.min(maxChance, current + baseChance)
    end

    -- Lifetime in seconds (default 5)
    local durationNV = sc:FindFirstChild("Duration") or Instance.new("NumberValue")
    durationNV.Name = "Duration"
    durationNV.Parent = sc
    durationNV.Value = typeof(def.duration) == "number" and def.duration or 5

    -- Optional: store damage multiplier for reference (default 0.5)
    local multNV = sc:FindFirstChild("DamageMultiplier") or Instance.new("NumberValue")
    multNV.Name = "DamageMultiplier"
    multNV.Parent = sc
    multNV.Value = typeof(def.damageMultiplier) == "number" and def.damageMultiplier or 0.5

    -- Configure MaxActive cap (default 3); map both def.maxActive and def.maxClones
    local capNV = sc:FindFirstChild("MaxActive") or Instance.new("IntValue")
    capNV.Name = "MaxActive"
    capNV.Parent = sc
    local defCap = 3
    if typeof(def.maxActive) == "number" then
        defCap = math.floor(def.maxActive)
    elseif typeof(def.maxClones) == "number" then
        defCap = math.floor(def.maxClones)
    end
    capNV.Value = math.max(0, defCap)
end

return M

