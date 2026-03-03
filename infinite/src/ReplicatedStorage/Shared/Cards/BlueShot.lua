-- BlueShot.lua
-- Spawns a "Blue" mass orbiting the player that pulls nearby enemies inward.
print("[BlueShot] MODULE REQUIRED <<<")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Damage = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("Damage"))

local SFXHelper        = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("SFXHelper"))
local BLUESHOT_SFX_ID  = 95527239456288

local def = {
    Name = "BlueShot",
    Rarity = "Legendary",
    Type = "Active",
    MaxLevel = 5,
    Description = "Spawns a blue mass that pulls enemies toward it for a short time.",
}

-- Backwards-compat helper used by CardPool
def.maxLevel = def.maxLevel or def.MaxLevel
def.id = def.id or script.Name

-- Tunables
local PULL_SCALE = 80
local DAMAGE_SCALE = 1.0
local ORBIT_SPEED_MULTIPLIER = 2.0

local statsPerLevel = {
    -- reduced orbitRadius so the blue mass orbits closer to the player (better chance to affect enemies)
    [1] = { spawnInterval = 8, activeDuration = 3, range = 24, pullStrength = 60, tickRate = 0.2, damagePercent = 0.05, orbitRadius = 18 },
    [2] = { spawnInterval = 7, activeDuration = 3.5, range = 26, pullStrength = 72, tickRate = 0.18, damagePercent = 0.10, orbitRadius = 20 },
    [3] = { spawnInterval = 6, activeDuration = 4, range = 28, pullStrength = 86, tickRate = 0.16, damagePercent = 0.15, orbitRadius = 22 },
    [4] = { spawnInterval = 5, activeDuration = 4.5, range = 30, pullStrength = 100, tickRate = 0.14, damagePercent = 0.20, orbitRadius = 24 },
    [5] = { spawnInterval = 4, activeDuration = 5, range = 32, pullStrength = 116, tickRate = 0.12, damagePercent = 0.25, orbitRadius = 26 },
}

local ActiveBlueShotByUserId = {}

local function findBlueAsset()
    local chars = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("Chars")
    if not chars then return nil end
    for _, c in ipairs(chars:GetChildren()) do
        local b = c:FindFirstChild("Blue") or c:FindFirstChild("BlueShot") or c:FindFirstChild("Blue", true)
        if b then return b end
    end
    return nil
end

local BlueAsset = findBlueAsset()

local function createBlueModel(character, size)
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    if BlueAsset then
        local clone = BlueAsset:Clone()
        clone.Name = "BlueShotEffect"
        -- Sanitizar a própria part E os descendentes (GetDescendants não inclui o clone em si)
        if clone:IsA("BasePart") then
            clone.CanCollide = false
            clone.Massless   = true
            clone.Anchored   = true
        end
        for _, d in ipairs(clone:GetDescendants()) do
            if d:IsA("BasePart") then
                d.CanCollide = false
                d.Massless = true
                d.Anchored = true
            end
        end
        -- Ensure PrimaryPart exists
        if clone:IsA("Model") then
            local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
            if primary then
                clone.PrimaryPart = primary
            end
            clone.Parent = workspace
            -- PivotTo moves the WHOLE model so relative offsets are correct before SetPrimaryPartCFrame ever runs
            pcall(function() clone:PivotTo(CFrame.new(hrp.Position + Vector3.new(0, 1, 0))) end)
        elseif clone:IsA("BasePart") then
            clone.Size = Vector3.new(size, size, size)
            clone.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 0.5, 0))
            if not clone:FindFirstChild("BluePullTarget") then
                local a = Instance.new("Attachment")
                a.Name = "BluePullTarget"
                a.Position = Vector3.new(0, 0, 0)
                a.Parent = clone
            end
        end
        clone.Parent = workspace
        return clone
    end
    local p = Instance.new("Part")
    p.Name = "BlueShotEffect"
    p.Size = Vector3.new(size, size, size)
    p.Shape = Enum.PartType.Ball
    p.Material = Enum.Material.Neon
    p.Color = Color3.fromRGB(100, 150, 255)
    p.Transparency = 0.6
    p.CanCollide = false
    p.Massless = true
    p.Anchored = true
    p.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 0.5, 0))
    p.Parent = workspace
    return p
end

-- Pull implementation: operate on XZ plane, damp vertical velocity and cap max speed
local function pullEnemiesTowards(position, stats, dt, ownerPlayer, trappedTable)
    local enemies = CollectionService:GetTagged("Enemy")
    for _, enemy in ipairs(enemies) do
        if enemy and enemy:IsA("Model") then
            local hum = enemy:FindFirstChildOfClass("Humanoid")
            local hrp = enemy:FindFirstChild("HumanoidRootPart")
            if hum and hrp and hum.Health > 0 then
                local dir = position - hrp.Position
                local dirXZ = Vector3.new(dir.X, 0, dir.Z)
                local dist = dirXZ.Magnitude
                if dist <= stats.range and dist > 0.1 then
                    local pullPercent = 1 - math.clamp(dist / stats.range, 0, 1)
                    local maxPullSpeed = 120
                    local desiredSpeed = math.min(stats.pullStrength * PULL_SCALE * pullPercent, maxPullSpeed)
                    local desiredVelXZ = (dirXZ.Magnitude > 0 and dirXZ.Unit or Vector3.new(0,0,0)) * desiredSpeed
                    local currentVel = hrp.AssemblyLinearVelocity
                    local dampedY = math.clamp(currentVel.Y * 0.2, -8, 8)
                    local desiredVel = Vector3.new(desiredVelXZ.X, dampedY, desiredVelXZ.Z)
                    local lerpAlpha = 0.85
                    local newVel = currentVel:Lerp(desiredVel, lerpAlpha)
                    if dist <= 1.5 then
                        newVel = Vector3.new(0, math.clamp(currentVel.Y * 0.1, -4, 4), 0)
                        if trappedTable and not trappedTable[hrp] then
                            trappedTable[hrp] = true
                            if hrp and hrp:IsA("BasePart") then
                                hrp.Anchored = true
                            end
                        end
                    end
                    hrp.AssemblyLinearVelocity = newVel

                    -- damage tick
                    local percent = stats.damagePercent or 0
                    if percent > 0 and ownerPlayer then
                        local baseDamage = 0
                        local pst = ownerPlayer:FindFirstChild("Stats")
                        if pst then
                            local bd = pst:FindFirstChild("BaseDamage")
                            if bd and bd:IsA("NumberValue") then baseDamage = bd.Value end
                        end
                        local tickDamage = baseDamage * percent * DAMAGE_SCALE * dt
                        if tickDamage > 0 then
                            Damage.Apply(hum, tickDamage)
                        end
                    end
                end
            end
        end
    end
end

local function fireBlueShot(player, stats, onFinished)
    print("[BlueShot] fireBlueShot called for", player and player.Name)
    if not player or not player.Parent then print("[BlueShot] abort: player invalid") return end
    local character = player.Character
    if not character then print("[BlueShot] abort: no character") return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then print("[BlueShot] abort: no HRP") return end

    local model = createBlueModel(character, stats.orbitRadius * 2)
    if not model then print("[BlueShot] abort: no model") return end

    local alive = true
    local elapsed = 0
    local angle = 0
    local angularSpeed = math.pi * 2 / math.max(0.01, stats.activeDuration) * ORBIT_SPEED_MULTIPLIER
    local tickAcc = 0
    local connection
    local primaryPart = model:IsA("Model") and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")) or (model:IsA("BasePart") and model)

    -- SFX 3D: tocar na part do modelo em workspace, com loop durante toda a duração
    local sfxPart = primaryPart or (model:IsA("Model") and model.PrimaryPart) or (model:IsA("BasePart") and model)
    local sfxSound = nil
    if sfxPart then
        sfxSound = SFXHelper.playAt(sfxPart, BLUESHOT_SFX_ID, 0.85, { minDist = 15, maxDist = 80, lifetime = stats.activeDuration + 1, loop = true })
    end
    local trapped = {}

    local function untrapAll()
        for hrpPart, _ in pairs(trapped) do
            if hrpPart and hrpPart:IsA("BasePart") then
                pcall(function()
                    hrpPart.Anchored = false
                    hrpPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                end)
            end
        end
        trapped = {}
    end

    -- collect parts and emitters for fade control
    local parts = {}
    local partOriginalTransparency = {}
    local emitters = {}
    local emitterOriginalRate = {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            parts[#parts+1] = d
            partOriginalTransparency[d] = d.Transparency or 0
            d.Transparency = 1
        elseif d:IsA("ParticleEmitter") then
            emitters[#emitters+1] = d
            emitterOriginalRate[d] = d.Rate or 0
            d.Rate = 0
        end
    end

    -- fade-in visuals
    local fadeInTime = math.clamp(0.18, 0.05, stats.activeDuration * 0.5)
    for _, p in ipairs(parts) do
        if p and p.Parent then
            pcall(function()
                TweenService:Create(p, TweenInfo.new(fadeInTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = partOriginalTransparency[p] or 0 }):Play()
            end)
        end
    end
    do
        local elapsedFade = 0
        while elapsedFade < fadeInTime do
            local dt = RunService.Heartbeat:Wait()
            elapsedFade = elapsedFade + dt
            local a = math.clamp(elapsedFade / fadeInTime, 0, 1)
            for e, r in pairs(emitterOriginalRate) do
                if e and e.Parent then
                    e.Rate = r * a
                end
            end
        end
    end

    connection = RunService.Heartbeat:Connect(function(dt)
        if not alive then return end
        if not player.Parent or not character.Parent then
            alive = false
            connection:Disconnect()
            untrapAll()
            if sfxSound and sfxSound.Parent then pcall(function() sfxSound:Stop() end) end
            if model and model.Parent then model:Destroy() end
            return
        end
        elapsed = elapsed + dt
        angle = angle + angularSpeed * dt
        local r = stats.orbitRadius
        local offset = Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
        -- orbit slightly above ground so it interacts with enemies reliably
        local targetPos = hrp.Position + offset + Vector3.new(0, 0.5, 0)
        if model and model:IsA("Model") then
            local cf = CFrame.new(targetPos) * CFrame.Angles(0, angle, 0)
            pcall(function()
                -- Ensure parts remain anchored and sanitized before moving
                for _, d in ipairs(model:GetDescendants()) do
                    if d:IsA("BasePart") then
                        d.CanCollide = false
                        d.Massless = true
                        d.Anchored = true
                    end
                end
                if model.PrimaryPart then
                    model:SetPrimaryPartCFrame(cf)
                elseif model.PivotTo then
                    model:PivotTo(cf)
                else
                    for _, c in ipairs(model:GetChildren()) do
                        if c:IsA("BasePart") then
                            c.CFrame = cf
                            break
                        end
                    end
                end
            end)
        elseif primaryPart and primaryPart:IsA("BasePart") then
            pcall(function() primaryPart.CFrame = CFrame.new(targetPos) * CFrame.Angles(0, angle, 0) end)
        end

        -- Safety: if the model somehow fell below the map, snap it back up
        if model and model:IsA("Model") then
            local bp = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
            if bp and bp.Position.Y < -50 then
                pcall(function()
                    local safeCf = CFrame.new(targetPos) * CFrame.Angles(0, angle, 0)
                    if model.PrimaryPart then
                        model:SetPrimaryPartCFrame(safeCf)
                    elseif model.PivotTo then
                        model:PivotTo(safeCf)
                    end
                end)
            end
        end

        tickAcc = tickAcc + dt
        if tickAcc >= stats.tickRate then
            tickAcc = tickAcc - stats.tickRate
            local pos = primaryPart and primaryPart.Position or (model and model:IsA("Model") and (model.PrimaryPart and model.PrimaryPart.Position) or hrp.Position)
            if pos then pullEnemiesTowards(pos, stats, stats.tickRate, player, trapped) end
        end

        if elapsed >= stats.activeDuration then
            -- fade-out visuals then cleanup
            local fadeOutTime = 0.18
            for _, p in ipairs(parts) do
                if p and p.Parent then
                    pcall(function()
                        TweenService:Create(p, TweenInfo.new(fadeOutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
                    end)
                end
            end
            local elapsedFade = 0
            while elapsedFade < fadeOutTime do
                local dt2 = RunService.Heartbeat:Wait()
                elapsedFade = elapsedFade + dt2
                local a = 1 - math.clamp(elapsedFade / fadeOutTime, 0, 1)
                for e, r in pairs(emitterOriginalRate) do
                    if e and e.Parent then
                        e.Rate = r * a
                    end
                end
            end
            alive = false
            connection:Disconnect()
            untrapAll()
            if sfxSound and sfxSound.Parent then pcall(function() sfxSound:Stop() end) end
            if model and model.Parent then model:Destroy() end
            if type(onFinished) == "function" then
                pcall(onFinished)
            end
        end
    end)

    local controller = {}
    function controller.Stop()
        if not alive then return end
        alive = false
        if connection then pcall(function() connection:Disconnect() end) end
        if sfxSound and sfxSound.Parent then pcall(function() sfxSound:Stop() end) end
        -- fade-out visuals then cleanup
        local fadeOutTime = 0.18
        for _, p in ipairs(parts) do
            if p and p.Parent then
                pcall(function()
                    TweenService:Create(p, TweenInfo.new(fadeOutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
                end)
            end
        end
        local elapsedFade = 0
        while elapsedFade < fadeOutTime do
            local dt = RunService.Heartbeat:Wait()
            elapsedFade = elapsedFade + dt
            local a = 1 - math.clamp(elapsedFade / fadeOutTime, 0, 1)
            for e, r in pairs(emitterOriginalRate) do
                if e and e.Parent then
                    e.Rate = r * a
                end
            end
        end
        untrapAll()
        if model and model.Parent then pcall(function() model:Destroy() end) end
        if type(onFinished) == "function" then pcall(onFinished) end
    end

    return controller
end

function def.OnEquip(player, level)
    level = math.clamp(level or 1, 1, def.MaxLevel)
    local uid = player.UserId
    print("[BlueShot] OnEquip called for", player.Name, "level", level)
    if ActiveBlueShotByUserId[uid] then
        def.OnUnequip(player)
    end
    local stats = statsPerLevel[level] or statsPerLevel[1]

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

    local state = { acc = 0, waitingForCooldown = false, cooldownAcc = 0, active = false }
    local connection
    connection = RunService.Heartbeat:Connect(function(dt)
        if not player.Parent then
            def.OnUnequip(player)
            return
        end
        if state.waitingForCooldown then
            state.cooldownAcc = state.cooldownAcc + dt
            if state.cooldownAcc >= stats.spawnInterval then
                state.waitingForCooldown = false
                state.cooldownAcc = 0
            end
        else
            -- spawn a blue shot and enter cooldown
            if not state.active then
                state.active = true
                print("[BlueShot] spawning BlueShot for", player.Name)
                local controller = nil
                local ok, err = pcall(function()
                    controller = fireBlueShot(player, stats, function()
                        state.active = false
                        state.waitingForCooldown = true
                        state.cooldownAcc = 0
                    end)
                end)
                if not ok then
                    warn("[BlueShot] fireBlueShot error:", err)
                    state.active = false
                    state.waitingForCooldown = true
                    state.cooldownAcc = 0
                end
                ActiveBlueShotByUserId[uid] = { connection = connection, controller = controller }
            end
        end
    end)

end

function def.OnUnequip(player)
    if not player then return end
    local uid = player.UserId
    local entry = ActiveBlueShotByUserId[uid]
    if entry then
        if entry.connection then
            pcall(function() entry.connection:Disconnect() end)
        end
        if entry.controller and type(entry.controller.Stop) == "function" then
            pcall(function() entry.controller.Stop() end)
        end
        ActiveBlueShotByUserId[uid] = nil
    end
end

function def.OnLevelUp(player, newLevel)
    if ActiveBlueShotByUserId[player.UserId] then
        def.OnEquip(player, newLevel)
    end
end

-- Compatibility for CardDispatcher: called when a card instance is added (levelable/stackable support)
function def.OnCardAdded(player, defTable, level)
    def.OnEquip(player, level or 1)
end

return def
