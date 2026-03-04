-- Luffy - Gear
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local def = {
    Name = "Gum-Gum Gear",
    Rarity = "Rare",
    Type = "Active",
    MaxLevel = 5,
    Description = "Every X seconds grant AttackSpeed% and MoveSpeed% for 10s. Improves per level.",
}

def.id = def.id or script.Name

local Active = {}

local statsPerLevel = {
    -- cooldown = seconds between activations, buffAttack = percent, buffMove = percent
    [1] = { cooldown = 18, buffAttackPercent = 20, buffMovePercent = 8, duration = 10 },
    [2] = { cooldown = 16, buffAttackPercent = 26, buffMovePercent = 10, duration = 10 },
    [3] = { cooldown = 14, buffAttackPercent = 34, buffMovePercent = 12, duration = 10 },
    [4] = { cooldown = 12, buffAttackPercent = 42, buffMovePercent = 14, duration = 10 },
    [5] = { cooldown = 10, buffAttackPercent = 50, buffMovePercent = 16, duration = 10 },
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

-- apply a temporary upgrade value under player.Upgrades and mirror to Stats for immediate effect
local function applyTempUpgrade(player, name, value)
    if not player then return end
    local upgrades = player:FindFirstChild("Upgrades")
    if not upgrades then
        upgrades = Instance.new("Folder")
        upgrades.Name = "Upgrades"
        upgrades.Parent = player
    end
    local u = upgrades:FindFirstChild(name)
    if not u then
        u = Instance.new("NumberValue")
        u.Name = name
        u.Value = 0
        u.Parent = upgrades
    end
    u.Value = u.Value + value

    -- mirror into Stats
    local stats = player:FindFirstChild("Stats")
    if stats then
        local s = stats:FindFirstChild(name)
        if not s then
            s = Instance.new("NumberValue")
            s.Name = name
            s.Value = 0
            s.Parent = stats
        end
        s.Value = s.Value + value
    end
    return u
end

local function removeTempUpgrade(player, name, value)
    if not player then return end
    local upgrades = player:FindFirstChild("Upgrades")
    if upgrades then
        local u = upgrades:FindFirstChild(name)
        if u and u:IsA("NumberValue") then
            u.Value = math.max(0, u.Value - value)
        end
    end
    local stats = player:FindFirstChild("Stats")
    if stats then
        local s = stats:FindFirstChild(name)
        if s and s:IsA("NumberValue") then
            s.Value = math.max(0, s.Value - value)
        end
    end
end

-- activate buff for player; returns function to cancel early
local function grantBuff(player, stats)
    local atkName = "AttackSpeedPercent"
    local mvName = "MoveSpeedPercent"
    local atkVal = stats.buffAttackPercent or 0
    local mvVal = stats.buffMovePercent or 0

    -- apply
    applyTempUpgrade(player, atkName, atkVal)
    applyTempUpgrade(player, mvName, mvVal)

    -- spawn a simple vapor particle effect on the player's HRP while buff is active
    local vapeAttachment, vapeEmitter
    do
        local char = player and player.Character
        local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
        if hrp then
            vapeAttachment = Instance.new("Attachment")
            vapeAttachment.Name = "LuffyGearVape"
            vapeAttachment.Position = Vector3.new(0, 1.4, 0)
            vapeAttachment.Parent = hrp

            vapeEmitter = Instance.new("ParticleEmitter")
            vapeEmitter.Name = "LuffyGearVapeEmitter"
            vapeEmitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
            vapeEmitter.Color = ColorSequence.new(Color3.new(1,1,1), Color3.new(0.9,0.9,1))
            vapeEmitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.4)})
            vapeEmitter.Lifetime = NumberRange.new(0.6, 1.2)
            vapeEmitter.Rate = 20
            vapeEmitter.Speed = NumberRange.new(0.6, 1.6)
            vapeEmitter.VelocitySpread = 20
            vapeEmitter.Rotation = NumberRange.new(0, 360)
            vapeEmitter.RotSpeed = NumberRange.new(-30, 30)
            vapeEmitter.LightEmission = 0.2
            vapeEmitter.Enabled = true
            vapeEmitter.Parent = vapeAttachment
        end
    end

    local cancelled = false
    -- schedule removal after duration
    task.spawn(function()
        local t = 0
        local dur = stats.duration or 10
        while t < dur do
            if cancelled then break end
            local dt = RunService.Heartbeat:Wait()
            t = t + (dt or 0)
        end
        if not cancelled then
            removeTempUpgrade(player, atkName, atkVal)
            removeTempUpgrade(player, mvName, mvVal)
            -- cleanup particle effect
            if vapeEmitter then pcall(function() vapeEmitter.Enabled = false end) end
            if vapeAttachment and vapeAttachment.Parent then pcall(function() vapeAttachment:Destroy() end) end
        end
    end)

    return function()
        if cancelled then return end
        cancelled = true
        removeTempUpgrade(player, atkName, atkVal)
        removeTempUpgrade(player, mvName, mvVal)
        if vapeEmitter then pcall(function() vapeEmitter.Enabled = false end) end
        if vapeAttachment and vapeAttachment.Parent then pcall(function() vapeAttachment:Destroy() end) end
    end
end

function def.OnEquip(player, level)
    level = math.clamp(level or 1, 1, def.MaxLevel)

    -- reuse existing active entry if present
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
    local state = { waitingForCooldown = false, cooldownAcc = 0, active = false, cancelBuff = nil }
    local conn
    conn = RunService.Heartbeat:Connect(function(dt)
        if not player.Parent or not player.Character then
            if conn then conn:Disconnect() end
            def.OnUnequip(player)
            return
        end

        if state.waitingForCooldown then
            state.cooldownAcc = state.cooldownAcc + (dt or 0)
            if state.cooldownAcc >= (stats.cooldown or 18) then
                state.waitingForCooldown = false
                state.cooldownAcc = 0
            end
        else
            if not state.active then
                state.active = true
                task.spawn(function()
                    local ok, err = pcall(function()
                        -- grant buff and get cancel function
                        local cancel = grantBuff(player, stats)
                        state.cancelBuff = cancel
                        -- after granting, mark cooldown (buff removal handles itself)
                        state.active = false
                        state.waitingForCooldown = true
                        state.cooldownAcc = 0
                    end)
                    if not ok then
                        warn("[Luffy_Gear] grantBuff error:", err)
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
        if data.connection then pcall(function() data.connection:Disconnect() end) end
        if data.state and type(data.state.cancelBuff) == "function" then
            pcall(data.state.cancelBuff)
        end
    end
    Active[player] = nil
end

function def.OnLevelUp(player, newLevel)
    local data = Active[player]
    if not data then return end
    data.level = newLevel
    local myFolder = data.folder
    if myFolder then
        local lvlNV = myFolder:FindFirstChild("Level")
        if not lvlNV then
            lvlNV = Instance.new("IntValue")
            lvlNV.Name = "Level"
            lvlNV.Parent = myFolder
        end
        lvlNV.Value = tonumber(newLevel) or lvlNV.Value
    end
end

function def.OnCardAdded(player, defTable, level)
    def.OnEquip(player, level or 1)
end

return def
