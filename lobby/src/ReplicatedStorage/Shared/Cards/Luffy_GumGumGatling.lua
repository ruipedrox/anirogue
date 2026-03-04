-- Luffy - Gum-Gum Gatling
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Damage = require(ReplicatedStorage.Scripts.Combat.Damage)

local def = {
    Name = "Gum-Gum Gatling",
    Rarity = "Epic",
    Type = "Active",
    MaxLevel = 5,
    Description = "Spawns a flurry of Gum-Gum projectiles in a cone, dealing damage over 2s.",
}

def.id = def.id or script.Name

local Active = {}

-- Stats per level (tweak these to change gatling behavior)
local statsPerLevel = {
    [1] = { range = 18, coneDeg = 60, duration = 2, tickInterval = 0.1, visualsPerTick = 2, damagePerTickMultiplier = 0.05, cooldown = 6.0, spinSpeed = math.pi/4, visualTravel = 0.35 },
    [2] = { range = 20, coneDeg = 60, duration = 2, tickInterval = 0.1, visualsPerTick = 2, damagePerTickMultiplier = 0.1, cooldown = 5.5, spinSpeed = math.pi/4, visualTravel = 0.35 },
    [3] = { range = 22, coneDeg = 60, duration = 2, tickInterval = 0.1, visualsPerTick = 2, damagePerTickMultiplier = 0.15, cooldown = 5.0, spinSpeed = math.pi/4, visualTravel = 0.35 },
    [4] = { range = 24, coneDeg = 60, duration = 2, tickInterval = 0.1, visualsPerTick = 2, damagePerTickMultiplier = 0.20, cooldown = 4.5, spinSpeed = math.pi/4, visualTravel = 0.35 },
    [5] = { range = 26, coneDeg = 60, duration = 2, tickInterval = 0.1, visualsPerTick = 2, damagePerTickMultiplier = 0.25, cooldown = 4.0, spinSpeed = math.pi/4, visualTravel = 0.35 },
}

local function safeFindRunTrack(player)
    local rt = player:FindFirstChild("RunTrack")
    if not rt then
        rt = Instance.new("Folder")
        rt.Name = "RunTrack"
        rt.Parent = player
    end
    return rt
end

-- Utility: get player's root position and look vector
local function getOriginAndLook(player)
    local char = player.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
    if not hrp then return nil end
    return hrp.Position, hrp.CFrame.LookVector, hrp.CFrame
end
function def.Fire(player, level, onFinished)
    level = tonumber(level) or 1
    local stats = statsPerLevel[level] or statsPerLevel[1]
    local range = stats.range or 20
    local coneDeg = stats.coneDeg or 60
    local duration = stats.duration or 2
    local spawnInterval = stats.tickInterval or 0.1 -- tick cadence (per-level aware)
    local spawnTicks = math.max(1, math.floor(duration / spawnInterval))
    local gumTemplate = nil
    pcall(function()
        gumTemplate = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("Chars")
        if gumTemplate and gumTemplate:FindFirstChild("Luffy_5") then
            gumTemplate = gumTemplate.Luffy_5:FindFirstChild("gum_gum")
        else
            gumTemplate = nil
        end
    end)

    for t = 1, spawnTicks do
        -- fetch origin and look each tick so visuals follow the player
        local originPos, lookVec = getOriginAndLook(player)
        if not originPos then break end

        -- Use current spinAngle from Active state so cone rotates during effect
        local activeEntry = Active[player]
        local currentSpin = 0
        if activeEntry and activeEntry.state and type(activeEntry.state.spinAngle) == "number" then
            currentSpin = activeEntry.state.spinAngle
        end
        local jitter = (math.random() * 2 - 1) * 0.05
        local rotationAngle = currentSpin + jitter
        local rotatedLook = CFrame.fromAxisAngle(Vector3.new(0,1,0), rotationAngle).LookVector

        -- spawn visuals this tick (use per-level setting, default to 1)
        local thisCount = tonumber(stats.visualsPerTick) or 1
        for i = 1, thisCount do
            spawn(function()
                local half = math.rad(coneDeg / 2)
                local yaw = (math.random() * 2 - 1) * half
                local dir = (CFrame.fromAxisAngle(Vector3.new(0,1,0), yaw) * rotatedLook).Unit

                local height = 0.6 + math.random() * 1.8
                local startPos = originPos + Vector3.new(0, height, 0) + dir * (0.8 + math.random() * 0.6)
                local endPos = startPos + dir * (range * (0.5 + math.random() * 0.5))

                local part
                if gumTemplate and gumTemplate:IsA("BasePart") then
                    part = gumTemplate:Clone()
                else
                    part = Instance.new("Part")
                    part.Size = Vector3.new(0.5,0.5,0.5)
                    part.BrickColor = BrickColor.new("Bright orange")
                    part.Shape = Enum.PartType.Ball
                end
                part.Anchored = true
                part.CanCollide = false
                -- orient part to face along dir, then rotate 90 degrees for punch look
                part.CFrame = CFrame.new(startPos, startPos + dir) * CFrame.Angles(0, math.rad(90), 0)
                part.Parent = workspace
                local vTime = stats.visualTravel or math.clamp(spawnInterval * 0.9, 0.06, 0.5)
                local tweenInfo = TweenInfo.new(vTime, Enum.EasingStyle.Linear)
                local ok, tw = pcall(function()
                    return TweenService:Create(part, tweenInfo, {CFrame = CFrame.new(endPos, endPos + dir) * CFrame.Angles(0, math.rad(90), 0)})
                end)
                if ok and tw then tw:Play() end
                Debris:AddItem(part, vTime + 0.05)
            end)
        end

        -- apply damage using the rotated look direction for this tick (use originPos from this tick)
        local halfAngle = math.rad(coneDeg / 2)
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Model") then
                local hum = obj:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    local hrp = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
                    if hrp and hrp:IsA("BasePart") then
                        local toTarget = (hrp.Position - originPos)
                        local dist = toTarget.Magnitude
                        if dist <= range and dist > 0.001 then
                            local dirToTarget = toTarget.Unit
                            local ang = math.acos(math.clamp(dirToTarget:Dot(rotatedLook), -1, 1))
                            if ang <= halfAngle then
                                local ok, err = pcall(function()
                                    local creatorTag = Instance.new("ObjectValue")
                                    creatorTag.Name = "creator"
                                    creatorTag.Value = player
                                    creatorTag.Parent = hum
                                    local baseDamage = (player:FindFirstChild("Stats") and player.Stats:FindFirstChild("BaseDamage") and player.Stats.BaseDamage.Value) or 10
                                    local mult = stats.damagePerTickMultiplier or (0.12 * math.clamp(level,1,def.MaxLevel))
                                    local dmgPerTick = math.max(1, baseDamage * mult)
                                    Damage.Apply(hum, dmgPerTick, { damageType = "gatling" })
                                    creatorTag:Destroy()
                                end)
                                if not ok then warn("Gatling damage apply failed:", err) end
                            end
                        end
                    end
                end
            end
        end

        task.wait(spawnInterval)
    end

    if type(onFinished) == "function" then pcall(onFinished) end
end

-- Card lifecycle
function def.OnEquip(player, level)
    level = math.clamp((level ~= nil) and level or 1, 1, def.MaxLevel)
    -- If already active for this player, update level and reuse existing connection/state
    local existing = Active[player]
    if existing then
        existing.level = level
        local myFolder = existing.folder
        if myFolder then
            local lvlNV = myFolder:FindFirstChild("Level")
            if not lvlNV then
                lvlNV = Instance.new("IntValue")
                lvlNV.Name = "Level"
                lvlNV.Parent = myFolder
            end
            lvlNV.Value = tonumber(level) or lvlNV.Value
        end
        return
    end

    local rt = safeFindRunTrack(player)
    local myFolder = rt:FindFirstChild(def.id) or Instance.new("Folder")
    myFolder.Name = def.id
    myFolder.Parent = rt
    local lvlNV = myFolder:FindFirstChild("Level") or Instance.new("IntValue")
    lvlNV.Name = "Level"
    lvlNV.Value = tonumber(level) or 1
    lvlNV.Parent = myFolder

    local stats = statsPerLevel[level] or statsPerLevel[1]

    local state = { waitingForCooldown = false, cooldownAcc = 0, active = false, spinAngle = 0 }
    local conn
    conn = RunService.Heartbeat:Connect(function(dt)
        if not player.Parent or not player.Character then
            if conn then conn:Disconnect() end
            def.OnUnequip(player)
            return
        end
        if ReplicatedStorage:GetAttribute("GamePaused") then return end
        -- update continuous spin angle every heartbeat (rotates even while on cooldown)
        local entry = Active[player]
        local entryLevel = (entry and entry.level) or level
        local currentStats = statsPerLevel[entryLevel] or statsPerLevel[1]
        state.spinAngle = (state.spinAngle + ((currentStats.spinSpeed or math.pi / 4) * (dt or 0))) % (2 * math.pi)

        if state.waitingForCooldown then
            state.cooldownAcc = state.cooldownAcc + (dt or 0)
            if state.cooldownAcc >= (stats.cooldown or 6) then
                state.waitingForCooldown = false
                state.cooldownAcc = 0
            end
        else
            if not state.active then
                state.active = true
                task.spawn(function()
                    local ok, err = pcall(function()
                        def.Fire(player, level, function()
                            state.active = false
                            state.waitingForCooldown = true
                            state.cooldownAcc = 0
                        end)
                    end)
                    if not ok then
                        warn("[GumGumGatling] Fire error:", err)
                        state.active = false
                        state.waitingForCooldown = true
                        state.cooldownAcc = 0
                    end
                end)
            end
        end
    end)

    Active[player] = { folder = myFolder, connection = conn, level = level, state = state }
end

function def.OnUnequip(player)
    local data = Active[player]
    if data then
        if data.connection then
            data.connection:Disconnect()
        end
    end
    Active[player] = nil
end

function def.OnCardAdded(player, defTable, level)
    def.OnEquip(player, level or 1)
end

function def.OnLevelUp(player, newLevel)
    local data = Active[player]
    if not data then return end
    local myFolder = data.folder
    if not myFolder then return end
    local lvlNV = myFolder:FindFirstChild("Level")
    if lvlNV then lvlNV.Value = tonumber(newLevel) or lvlNV.Value end
    data.level = tonumber(newLevel) or data.level
end

return def
