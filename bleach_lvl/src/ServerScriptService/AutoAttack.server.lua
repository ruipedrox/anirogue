-- AutoAttack.server.lua
-- Continually attacks nearest enemy for each player based on final Player Stats (aggregated).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")
local Projectile = require(ScriptsFolder:WaitForChild("Projectile"))
local OnHit = require(ScriptsFolder:WaitForChild("Combat"):WaitForChild("OnHit"))
local Damage = require(ScriptsFolder:WaitForChild("Combat"):WaitForChild("Damage"))
local Crit = require(ScriptsFolder:WaitForChild("Combat"):WaitForChild("Crit"))
local DoT = require(ScriptsFolder:WaitForChild("Combat"):WaitForChild("DoT"))

-- Config defaults
local DEFAULT_RANGE = 80 -- studs
local MIN_INTERVAL = 0.1 -- seconds (cap for extreme AttackSpeed)

local function getCharacterRoot(character: Model): BasePart?
    return character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart) or nil
end

-- Track last known enemy reference and clear it when that enemy dies so we don't fire at stale positions
local lastEnemyData = setmetatable({}, { __mode = "k" }) -- [enemyModel] = true (weak keys)

local function isEnemyAlive(enemy: Model): boolean
    if not enemy or not enemy.Parent then return false end
    local hum = enemy:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function getEnemyPosition(enemy: Model): Vector3?
    if not enemy or not enemy.Parent then return nil end
    local ok, cf = pcall(function() return enemy:GetPivot() end)
    if ok and typeof(cf) == "CFrame" then return cf.Position end
    local pp = enemy.PrimaryPart or enemy:FindFirstChild("HumanoidRootPart")
    return pp and pp.Position or nil
end

local function getNearestEnemy(position: Vector3, maxRange: number)
    local best, bestDist
    for _, enemy in ipairs(CollectionService:GetTagged("Enemy")) do
        if enemy and enemy.Parent and isEnemyAlive(enemy :: Model) then
            local pos = getEnemyPosition(enemy :: Model)
            if pos then
                local dist = (pos - position).Magnitude
                if dist <= maxRange and (not bestDist or dist < bestDist) then
                    bestDist = dist
                    best = enemy :: Model
                end
            end
        end
    end
    if best then
        if not lastEnemyData[best] then
            lastEnemyData[best] = true
            -- Hook death to auto-clear
            local hum = best:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.Died:Connect(function()
                    lastEnemyData[best] = nil
                end)
            end
            best.AncestryChanged:Connect(function(_, parent)
                if not parent then
                    lastEnemyData[best] = nil
                end
            end)
        end
    end
    return best
end

local playerLoops = {} -- [player] = RBXScriptConnection
local nextAttackTimes = {} -- [player] = number (os.clock())
local playerAttackCycle = {} -- [player] = { fireAt: number, postDelay: number }
local playerAnimState = {} -- [player] = { animator, idleTrack, attackTrack, weaponName }

-- Try to get the equipped weapon's model to use as a projectile visual
local function getEquippedWeaponModel(player: Player): Instance?
    local equippedFolder = player:FindFirstChild("EquippedItems")
    if not equippedFolder then return nil end
    local weaponOV = equippedFolder:FindFirstChild("Weapon")
    local weaponModule = weaponOV and weaponOV:IsA("ObjectValue") and weaponOV.Value
    if not (weaponModule and weaponModule:IsA("ModuleScript")) then return nil end
    local container = weaponModule.Parent
    if not container then return nil end
    -- Priority by common names
    local preferredNames = {"Projectile", "Model", "ProjectileModel"}
    for _, name in ipairs(preferredNames) do
        local child = container:FindFirstChild(name)
        if child and (child:IsA("Model") or child:IsA("BasePart")) then
            return child
        end
    end
    -- Fallback: any Model or BasePart under the weapon folder
    for _, ch in ipairs(container:GetChildren()) do
        if ch:IsA("Model") or ch:IsA("BasePart") then
            return ch
        end
    end
    return nil
end

-- Get the equipped weapon container (folder/module parent) and name
local function getEquippedWeaponContainer(player: Player): Instance? 
    local equippedFolder = player:FindFirstChild("EquippedItems")
    if not equippedFolder then return nil end
    local weaponOV = equippedFolder:FindFirstChild("Weapon")
    local weaponModule = weaponOV and weaponOV:IsA("ObjectValue") and weaponOV.Value
    if not (weaponModule and weaponModule:IsA("ModuleScript")) then return nil end
    return weaponModule.Parent
end

local function getEquippedWeaponName(player: Player): string?
    local container = getEquippedWeaponContainer(player)
    return container and container.Name or nil
end

local function startLoopForPlayer(player: Player)
    if playerLoops[player] then return end

    playerLoops[player] = RunService.Heartbeat:Connect(function(dt)
        local character = player.Character
        if not character or not character.Parent then return end
        -- Global pause or per-player pause while choosing a card
        if ReplicatedStorage:GetAttribute("GamePaused") then return end
        if character:GetAttribute("PausedForCard") then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then return end
        local root = getCharacterRoot(character)
        if not root then return end

        -- Read final Player Stats (from player.Stats folder)
        local statsFolder = player:FindFirstChild("Stats")
        if not statsFolder then return end
        local function getNumber(name, default)
            local nv = statsFolder:FindFirstChild(name)
            if nv and nv:IsA("NumberValue") then return nv.Value end
            return default
        end

        local atkPerSec = getNumber("AttackSpeed", 1)
        local interval = math.max(1 / math.max(atkPerSec, 0.001), MIN_INTERVAL)
        local preDelay = interval * 0.2 -- 1/5 before firing
        local postDelayDefault = interval - preDelay -- remaining time after firing
        local now = os.clock()
        local state = playerAttackCycle[player]
        local nextTime = nextAttackTimes[player]

        -- If not in an attack cycle yet, consider starting one (wind-up phase)
        if not state then
            if nextTime and now < nextTime then return end

            -- Find nearest enemy in range
            local range = getNumber("Range", DEFAULT_RANGE)
            local enemy = getNearestEnemy(root.Position, range)
            if not enemy then return end

            -- Compute facing towards enemy now, but defer firing to after preDelay
            local enemyPos
            do
                local ok, cf = pcall(function() return (enemy :: Model):GetPivot() end)
                if ok and typeof(cf) == "CFrame" then
                    enemyPos = cf.Position
                else
                    local pp = (enemy :: Model).PrimaryPart or (enemy :: Model):FindFirstChild("HumanoidRootPart")
                    enemyPos = pp and pp.Position or nil
                end
            end
            if not enemyPos then return end

            local origin = root.Position + Vector3.new(0, 1.2, 0)
            local dir = enemyPos - origin
            if dir.Magnitude < 1e-3 then return end
            dir = dir.Unit

            -- Schedule the fire moment and remember the post delay
            playerAttackCycle[player] = { fireAt = now + preDelay, postDelay = postDelayDefault }
            return
        end

        -- We are in wind-up; fire when time arrives
        if now < state.fireAt then return end

        -- Re-evaluate target at fire time to avoid shooting at dead/moved targets
        local range = getNumber("Range", DEFAULT_RANGE)
    local enemy = getNearestEnemy(root.Position, range)
        local enemyPos
        if enemy then
            local ok, cf = pcall(function() return (enemy :: Model):GetPivot() end)
            if ok and typeof(cf) == "CFrame" then
                enemyPos = cf.Position
            else
                local pp = (enemy :: Model).PrimaryPart or (enemy :: Model):FindFirstChild("HumanoidRootPart")
                enemyPos = pp and pp.Position or nil
            end
        end
        if not enemyPos then
            -- No valid target anymore; finish cycle and wait post-delay
            nextAttackTimes[player] = now + (state.postDelay or postDelayDefault)
            playerAttackCycle[player] = nil
            return
        end

        -- Calculate direction first
        local centerPos = root.Position + Vector3.new(0, 1.2, 0)
        local dir = (enemyPos - centerPos)
        if dir.Magnitude < 1e-3 then
            nextAttackTimes[player] = now + (state.postDelay or postDelayDefault)
            playerAttackCycle[player] = nil
            return
        end
        -- TOP-DOWN: Ignore Y axis (height) when aiming projectiles
        dir = dir * Vector3.new(1, 0, 1)
        if dir.Magnitude < 1e-3 then dir = Vector3.new(0, 0, -1) end
        dir = dir.Unit
        
        -- Offset projectile spawn in a circle around player (~1 stud radius)
        local angle = math.random() * math.pi * 2
        local offsetRadius = 1
        local offset = Vector3.new(math.cos(angle) * offsetRadius, 0, math.sin(angle) * offsetRadius)
        local origin = centerPos + offset

        -- Build weapon-like stats from final Stats
        local weaponStats = {
            ProjectileSpeed = getNumber("ProjectileSpeed", 80),
            Pierce = math.floor(getNumber("Pierce", 1)),
            Lifetime = getNumber("Lifetime", 2),
        }
    -- Damage applied in onHit using final stats (crit/DoT); pass 0 here
    local damage = 0
        local modelInstance = getEquippedWeaponModel(player)

        -- Prepare animator and per-weapon animations (Idle/Attack)
        do
            local state = playerAnimState[player]
            local weaponName = getEquippedWeaponName(player)
            if not state or state.weaponName ~= weaponName then
                -- cleanup old
                if state then
                    pcall(function() if state.idleTrack then state.idleTrack:Stop(0.1) end end)
                    pcall(function() if state.attackTrack then state.attackTrack:Stop(0.1) end end)
                end
                state = {}
                playerAnimState[player] = state
                state.weaponName = weaponName
                -- ensure animator
                local animator: Animator? = humanoid:FindFirstChildOfClass("Animator")
                if not animator then
                    animator = Instance.new("Animator")
                    animator.Parent = humanoid
                end
                state.animator = animator
                -- resolve animations: weapon folder first, then generic fallback
                local weaponFolder = getEquippedWeaponContainer(player)
                local idleAnim = weaponFolder and weaponFolder:FindFirstChild("Idle")
                local attackAnim = weaponFolder and weaponFolder:FindFirstChild("Attack")
                if not idleAnim then
                    local anims = ReplicatedStorage:FindFirstChild("Animations")
                    local cloneFolder = anims and anims:FindFirstChild("Clone")
                    if cloneFolder then idleAnim = cloneFolder:FindFirstChild("Idle") end
                end
                if not attackAnim then
                    local anims = ReplicatedStorage:FindFirstChild("Animations")
                    local cloneFolder = anims and anims:FindFirstChild("Clone")
                    if cloneFolder then attackAnim = cloneFolder:FindFirstChild("Attack") end
                end
                if idleAnim and idleAnim:IsA("Animation") then
                    local ok, track = pcall(function() return animator:LoadAnimation(idleAnim) end)
                    if ok and track then
                        state.idleTrack = track
                        state.idleTrack.Looped = true
                        state.idleTrack:Play(0.15)
                        -- Scale idle speed lightly with AttackSpeed
                        local atkPerSecNow = getNumber("AttackSpeed", 1)
                        local idleScale = math.clamp(atkPerSecNow, 0.5, 3)
                        pcall(function() state.idleTrack:AdjustSpeed(idleScale) end)
                    end
                end
                -- Attack animations removed - player doesn't rotate to face enemies
            end
        end

        -- Fire projectile now
        Projectile.FireFromWeapon({
            weaponStats = weaponStats,
            origin = origin,
            direction = dir,
            owner = character,
            damage = damage,
            model = modelInstance,
            orientationOffset = CFrame.Angles(0, math.rad(-90), 0),
            hitCooldownPerTarget = 0.15,
            onHit = function(hitPart, enemyModel)
                local hum = enemyModel and enemyModel:FindFirstChildOfClass("Humanoid")
                if not hum then return end

                -- Tag creator for XP attribution
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

                -- Read needed stats
                local function getNumber(name, default)
                    local nv = statsFolder:FindFirstChild(name)
                    if nv and nv:IsA("NumberValue") then return nv.Value end
                    return default
                end

                local baseDamage = getNumber("BaseDamage", 0)
                local dmgPercent = getNumber("DamagePercent", 0)
                local dmgMult = 1 + math.max(-0.99, (dmgPercent or 0) / 100)
                local critChance = getNumber("CritChance", 0)
                local critMult = getNumber("CritDamage", 1)

                -- Resolve crit and apply damage
                local mult, critCount = Crit.Resolve(critChance, critMult)
                local dealt = baseDamage * dmgMult * mult
                
                -- Apply damage with crit info for damage numbers
                local finalDmg = Damage.Apply(hum, dealt)
                
                -- Show damage number with crit
                if finalDmg > 0 then
                    local DamageNumbers = require(ScriptsFolder:WaitForChild("Combat"):WaitForChild("DamageNumbers"))
                    local pos = getEnemyPosition(enemy)
                    if pos then
                        DamageNumbers.Show({
                            position = pos,
                            amount = finalDmg,
                            damageType = critCount > 0 and "crit" or "normal",
                            critCount = critCount
                        })
                    end
                end
                
                -- Apply Electric chain lightning if player has electric stacks
                local Electric = require(ScriptsFolder:WaitForChild("Combat"):WaitForChild("Electric"))
                local electricStats = Electric.GetStats(player)
                if electricStats and electricStats.chainCount > 0 and electricStats.damagePercent > 0 then
                    Electric.Apply({
                        player = player,
                        originModel = enemy,
                        damage = baseDamage, -- Use only base damage without multipliers
                        chainCount = electricStats.chainCount,
                        damagePercent = electricStats.damagePercent
                    })
                end

                -- Apply DoT after base damage if enabled
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
                    local totalDotBase = baseDamage * eff
                    local totalDot = dotCritFlag and (totalDotBase * mult) or totalDotBase
                    DoT.Apply(hum, { totalTime = totalTime, totalDamage = totalDot, tick = 0.25 })
                end

                -- Call auxiliary on-hit pipeline with context including dealt damage
                OnHit.Process({ player = player, statsFolder = statsFolder, isCrit = isCrit, dealt = dealt }, hum)
            end
        })

        -- Finish cycle: set next time to post-delay after the fire
        nextAttackTimes[player] = now + (state.postDelay or postDelayDefault)
        playerAttackCycle[player] = nil
    end)
end

local function stopLoopForPlayer(player)
    local conn = playerLoops[player]
    if conn then
        conn:Disconnect()
        playerLoops[player] = nil
    end
    nextAttackTimes[player] = nil
    playerAttackCycle[player] = nil
    -- Cleanup animations
    local state = playerAnimState[player]
    if state then
        pcall(function() if state.idleTrack then state.idleTrack:Stop(0.1) end end)
        pcall(function() if state.attackTrack then state.attackTrack:Stop(0.1) end end)
    end
    playerAnimState[player] = nil
end

Players.PlayerAdded:Connect(function(player)
    -- Small delay to ensure EquippedItems initialized
    task.delay(1, function()
        startLoopForPlayer(player)
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    stopLoopForPlayer(player)
end)

-- Start for existing players (studio quick play)
for _, plr in ipairs(Players:GetPlayers()) do
    task.delay(1, function()
        startLoopForPlayer(plr)
    end)
end
