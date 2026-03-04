-- Vegeta_PrideBarrage.lua
-- Legendary/Active: selects a target enemy and deals area damage around them for a short duration

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local Damage = nil
pcall(function()
    Damage = require(ReplicatedStorage.Scripts.Combat.Damage)
end)

local SFXHelper = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("SFXHelper"))
local KI_BLAST_SFX_ID = 81487890423399

local def = {
    Name = "Pride Barrage",
    Rarity = "Legendary",
    Type = "Active",
    MaxLevel = 5,
    Description = "Target an enemy and bombard them with ki for 2s; visual ki blasts spawn beside you and arc toward the target.",
}

def.id = def.id or script.Name

local Active = {}

local statsPerLevel = {
    -- damagePercent is percentage of player's BaseDamage per tick
    -- radius = AoE around target
    -- duration = how long the barrage lasts
    -- tickInterval = damage tick cadence and visual spawn cadence
    -- cooldown = seconds after ability ends
    [1] = { damagePercent = 0.12, radius = 4, duration = 2.0, tickInterval = 0.1, cooldown = 10 },
    [2] = { damagePercent = 0.18, radius = 4.5, duration = 2.0, tickInterval = 0.1, cooldown = 9 },
    [3] = { damagePercent = 0.25, radius = 5, duration = 2.0, tickInterval = 0.1, cooldown = 8 },
    [4] = { damagePercent = 0.32, radius = 5.5, duration = 2.0, tickInterval = 0.1, cooldown = 7 },
    [5] = { damagePercent = 0.40, radius = 6, duration = 2.0, tickInterval = 0.1, cooldown = 6 },
}

local function findNearestEnemy(player, range)
    local char = player.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
    if not hrp then return nil end
    local best, bestDist = nil, math.huge
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj ~= char then
            local hum = obj:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local targetHRP = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
                if targetHRP and targetHRP:IsA("BasePart") then
                    local d = (targetHRP.Position - hrp.Position).Magnitude
                    if d <= range and d < bestDist then
                        best = obj
                        bestDist = d
                    end
                end
            end
        end
    end
    return best
end

local function spawnKiBlast(player, startCFrameOrPos, targetPos, lifetime)
    -- try to find KiBlast template in player character folder (Vegeta_5.KiBlast) or fallback
    local template = nil
    pcall(function()
        local shared = ReplicatedStorage:FindFirstChild("Shared")
        if shared then
            local chars = shared:FindFirstChild("Chars")
            if chars and chars:FindFirstChild("Vegeta_5") then
                template = chars.Vegeta_5:FindFirstChild("KiBlast") or chars.Vegeta_5:FindFirstChild("ki_blast")
            end
        end
    end)
    local part
    if template and template:IsA("BasePart") then
        part = template:Clone()
    else
        part = Instance.new("Part")
        part.Size = Vector3.new(0.6,0.6,0.6)
        part.Shape = Enum.PartType.Ball
        part.BrickColor = BrickColor.new("Deep blue")
    end
    part.Anchored = true
    part.CanCollide = false
    part.Parent = workspace

    -- determine start position from either a CFrame or a Vector3
    local startPos
    if typeof(startCFrameOrPos) == "CFrame" then
        startPos = startCFrameOrPos.Position
    elseif typeof(startCFrameOrPos) == "Vector3" then
        startPos = startCFrameOrPos
    else
        startPos = (player.Character and (player.Character:FindFirstChild("HumanoidRootPart") or player.Character.PrimaryPart) and player.Character:FindFirstChild("HumanoidRootPart").Position) or Vector3.new()
    end

    part.CFrame = CFrame.new(startPos)
    SFXHelper.playAt(part, KI_BLAST_SFX_ID, 0.75, { minDist = 10, maxDist = 60, lifetime = (lifetime or 0.5) + 0.5 })
    local total = lifetime or 0.5

    -- Create a quadratic Bezier curve: start -> control -> target
    local mid = (startPos + targetPos) * 0.5
    local raise = Vector3.new(0, math.max(3, (targetPos - startPos).Magnitude * 0.2), 0)
    -- lateral offset to ensure a visible curve (perpendicular to direction)
    local dir = (targetPos - startPos)
    local perp = Vector3.new(-dir.Z, 0, dir.X)
    if perp.Magnitude > 0 then perp = perp.Unit end
    local curveSide = (math.random() < 0.5) and -1 or 1
    local curveAmount = math.clamp(dir.Magnitude * 0.08, 1, 4) * curveSide
    local control = mid + raise + perp * curveAmount

    -- animate along the Bezier curve using Heartbeat for a smooth curved path
    task.spawn(function()
        local t = 0
        while t < 1 do
            local dt = RunService.Heartbeat:Wait()
            t = math.min(1, t + dt / math.max(0.0001, total))
            local omt = (1 - t)
            local pos = omt * omt * startPos + 2 * omt * t * control + t * t * targetPos
            local deriv = 2 * omt * (control - startPos) + 2 * t * (targetPos - control)
            local lookCFrame
            if deriv.Magnitude > 0.01 then
                lookCFrame = CFrame.lookAt(pos, pos + deriv, Vector3.new(0, 1, 0))
            else
                lookCFrame = CFrame.new(pos)
            end
            part.CFrame = lookCFrame
        end
    end)

    Debris:AddItem(part, total + 0.1)
end

local function applyDamageAtPosition(centerPos, player, amount, radius)
    if not centerPos then return end
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") then
            local hum = obj:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local hrp = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
                if hrp and hrp:IsA("BasePart") then
                    local dist = (hrp.Position - centerPos).Magnitude
                    if dist <= radius then
                        if Damage and hum then
                            pcall(function()
                                local tag = Instance.new("ObjectValue")
                                tag.Name = "creator"
                                tag.Value = player
                                tag.Parent = hum
                                Damage.Apply(hum, amount, { damageType = "pride" })
                                tag:Destroy()
                            end)
                        else
                            pcall(function() hum:TakeDamage(amount) end)
                        end
                    end
                end
            end
        end
    end
end

function def.Fire(player, level)
    if not player or not player.Character then return end
    level = math.clamp(tonumber(level) or 1, 1, def.MaxLevel)
    local stats = statsPerLevel[level] or statsPerLevel[1]
    local hrp = player.Character:FindFirstChild("HumanoidRootPart") or player.Character.PrimaryPart
    if not hrp then return end
    -- choose nearest enemy within a reasonable range
    local target = findNearestEnemy(player, 60)
    if not target then
        -- Buffer: wait until an enemy appears (or until optional bufferMax expires)
        local bufferMax = (stats.bufferMax and tonumber(stats.bufferMax)) or 0 -- 0 = infinite
        local waited = 0
        warn("[PrideBarrage] No initial target, buffering until enemy appears for player", player and player.Name)
        while player and player.Character and not target do
            task.wait(0.2)
            waited = waited + 0.2
            target = findNearestEnemy(player, 60)
            if bufferMax > 0 and waited >= bufferMax then
                warn(string.format("[PrideBarrage] Buffer timed out after %.1fs for player %s", waited, player.Name))
                break
            end
        end
        if not target then
            -- still no target after buffering -> abort silently
            return
        end
    end

    -- snapshot the target position now (attack will go to this fixed position)
    local hrp = player.Character:FindFirstChild("HumanoidRootPart") or player.Character.PrimaryPart
    local targetHRP = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
    local targetSnapPos = nil
    if targetHRP and targetHRP:IsA("BasePart") then
        targetSnapPos = targetHRP.Position
    else
        targetSnapPos = hrp and (hrp.Position + hrp.CFrame.LookVector * 20) or nil
    end

    -- compute damage per tick based on player's BaseDamage
    local baseDamage = 10
    local pst = player:FindFirstChild("Stats")
    if pst then
        local bd = pst:FindFirstChild("BaseDamage")
        if bd and bd:IsA("NumberValue") then baseDamage = bd.Value end
    end
    -- visual spawn cadence (separate from damage tick cadence)
    local visualInterval = tonumber(stats.visualInterval) or 0.1 -- spawn a ki blast every 0.1s by default
    local tickInterval = tonumber(stats.tickInterval) or 0.1
    local duration = tonumber(stats.duration) or 2.0

    local damagePerTick = math.max(1, baseDamage * (stats.damagePercent or 0.2) * tickInterval)
    -- damage ticks will occur every tickInterval for duration
    local damageTicks = math.max(1, math.floor(duration / tickInterval))
    local char = player.Character

    -- run barrage: spawn visuals while applying damage at tick cadence
    local stopVisuals = false

    -- Visual spawn loop (separate task) targeting the snapshot position
    task.spawn(function()
        local elapsed = 0
        while elapsed < duration and player and player.Character and not stopVisuals do
            local hrp2 = player.Character and (player.Character:FindFirstChild("HumanoidRootPart") or player.Character.PrimaryPart)
            if hrp2 then
                -- origin at player's current position (slightly above center)
                local startPos = hrp2.Position + Vector3.new(0, 0, 0)
                local targetPos = targetSnapPos or (hrp2.Position + hrp2.CFrame.LookVector * 20)
                -- compute travel time based on distance so farther targets take longer (slower projectiles)
                local dist = (targetPos - startPos).Magnitude
                -- increase projectile speed: smaller travelTime means faster projectiles
                local travelTime = math.clamp(dist / 45, 0.25, 0.9) -- seconds (faster than before)
                spawnKiBlast(player, startPos, targetPos, travelTime)
            end
            task.wait(visualInterval)
            elapsed = elapsed + visualInterval
        end
    end)

    -- Damage tick loop: apply damage around the fixed snapshot position
    for i = 1, damageTicks do
        if not player or not player.Character then break end
        applyDamageAtPosition(targetSnapPos, player, damagePerTick, stats.radius or 4)
        task.wait(tickInterval)
    end

    stopVisuals = true
end

-- Equip lifecycle: make it usable and store level; simple implementation uses OnCardAdded to fire once when added
-- Active lifecycle: allow repeated automatic firing based on cooldown
local ActiveByUser = {}

function def.OnEquip(player, level, maxLevel)
    level = math.clamp(level or 1, 1, maxLevel or def.MaxLevel)
    local userId = player.UserId
    if ActiveByUser[userId] then def.OnUnequip(player) end

    local stats = statsPerLevel[level] or statsPerLevel[1]
    local last = 0

    -- Ensure RunTrack entry and record current level so CardPool can detect max level
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
        if now - last >= (stats.cooldown or 1) then
            local potential = findNearestEnemy(player, 60)
            if potential then
                last = now
                task.spawn(function()
                    local ok, err = pcall(function() def.Fire(player, level) end)
                    if not ok then warn("[PrideBarrage] Fire error:", err) end
                end)
            end
        end
    end)

    ActiveByUser[userId] = { connection = conn, level = level, folder = myFolder }
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
