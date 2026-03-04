-- Aizen_Reiatsu.lua
-- Legendary card: creates a persistent aura around the player that deals periodic area damage
-- and applies a light knockback on each damage tick.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Aizen_Reiatsu = {}

local Damage = nil
pcall(function()
    Damage = require(ReplicatedStorage.Scripts.Combat.Damage)
end)

local SFXHelper = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("SFXHelper"))
local REIATSU_SFX_ID = 115610095182136

-- Active state per player
local _active = {} -- [player] = { inst = table }

-- Config (can be tuned via card def)
local statsPerLevel = {
    [1] = { damagePercent = 0.05, cooldown = 0, aoe = 20, tickInterval = 0.5, knockback_strength = 10},
    [2] = { damagePercent = 0.1,  cooldown = 0, aoe = 20, tickInterval = 0.5, knockback_strength = 10},
    [3] = { damagePercent = 0.15, cooldown = 0, aoe = 20, tickInterval = 0.5, knockback_strength = 10},
    [4] = { damagePercent = 0.2,  cooldown = 0, aoe = 20, tickInterval = 0.5, knockback_strength = 10},
    [5] = { damagePercent = 0.25, cooldown = 0, aoe = 20, tickInterval = 0.5, knockback_strength = 10},
}

local function isValidEnemyModel(model, player)
    if not model or not model:IsA("Model") then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    -- Exclude players' characters
    local plr = Players:GetPlayerFromCharacter(model)
    if plr then return false end
    -- Exclude dead or non-physical models
    if hum.Health <= 0 then return false end
    local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if not hrp then return false end
    return true
end

local function applyKnockbackToModel(model, sourcePos, strength)
    local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if not hrp or hrp:IsDescendantOf(nil) then return end
    local dir = (hrp.Position - sourcePos)
    if dir.Magnitude <= 0 then return end
    local vel = dir.Unit * strength
    pcall(function()
        if hrp:IsA("BasePart") then
            hrp.Velocity = hrp.Velocity + vel
        end
    end)
end

-- Damage application helper
local function damageModel(model, amount, sourcePlayer)
    if not model then return end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    pcall(function()
        if typeof(hum.TakeDamage) == "function" then
            hum:TakeDamage(amount)
        else
            hum.Health = hum.Health - amount
        end
    end)
    if sourcePlayer and sourcePlayer.UserId then
        pcall(function()
            local tag = Instance.new("ObjectValue")
            tag.Name = "creator"
            tag.Value = sourcePlayer
            tag.Parent = hum
            task.defer(function() pcall(function() tag:Destroy() end) end)
        end)
    end
end

local function spawnVisualForPlayer(player)
    local ok, shared = pcall(function() return ReplicatedStorage:WaitForChild("Shared", 1) end)
    if not ok or not shared then return nil end
    local chars = shared:FindFirstChild("Chars")
    if not chars then return nil end
    local aizen = chars:FindFirstChild("Aizen_5")
    if not aizen then return nil end
    local reiPart = aizen:FindFirstChild("Reiatsu") or aizen:FindFirstChild("reiatsu")
    if not reiPart then return nil end
    local clone = reiPart:Clone()
    clone.Name = "Reiatsu_Visual"
    pcall(function()
        for _, d in ipairs(clone:GetDescendants()) do
            if d:IsA("BasePart") then
                d.CanCollide = false
                d.CanTouch = false
                d.CanQuery = true
                d.Anchored = true
            end
        end
    end)
    clone.Parent = workspace
    return clone
end


local function startAuraForPlayer(player, def, level)
    if not player or not player.Character then return end
    level = math.clamp(tonumber(level) or 1, 1, 5)

    -- SFX ao activar o reiatsu
    local _char = player.Character
    local _hrp = _char and (_char:FindFirstChild("HumanoidRootPart") or _char.PrimaryPart)
    if _hrp then
        SFXHelper.playAt(_hrp, REIATSU_SFX_ID, 0.85, { minDist = 15, maxDist = 80, lifetime = 3 })
    end

    local stats = statsPerLevel[level] or statsPerLevel[1]
    local cfg = {}
    -- populate cfg from the per-level stats (no separate DEFAULTS table)
    cfg.tickInterval = stats.tickInterval or (1/8)
    cfg.knockback_strength = stats.knockback_strength or 10
    cfg.radius = stats.aoe or 6
    if type(def) == "table" then
        if type(def.radius) == "number" then cfg.radius = def.radius end
        if type(def.tickInterval) == "number" then cfg.tickInterval = def.tickInterval end
        if type(def.tick_rate) == "number" then cfg.tickInterval = 1 / def.tick_rate end
        if type(def.knockback_strength) == "number" then cfg.knockback_strength = def.knockback_strength end
    end
    -- determine base damage from player stats (mirror Sukuna_Dismantle)
    local pst = player:FindFirstChild("Stats")
    local baseDamage = 50
    if pst then
        local bd = pst:FindFirstChild("BaseDamage")
        if bd and bd:IsA("NumberValue") then baseDamage = bd.Value end
    end
    -- per-tick damage is a percentage of the player's BaseDamage per tick
    local damagePerTick = math.max(1, baseDamage * (stats.damagePercent or 0.2))
    local tickInterval = cfg.tickInterval or (1/8)
    -- override radius with aoe from stats if present
    if stats.aoe then cfg.radius = stats.aoe end
    local running = true

    -- spawn visual if available
    local visual = spawnVisualForPlayer(player)
    -- ensure PrimaryPart for smooth SetPrimaryPartCFrame and create per-frame follow
    local hbConn = nil
    if visual then
        if visual:IsA("Model") and not visual.PrimaryPart then
            for _, d in ipairs(visual:GetDescendants()) do
                if d:IsA("BasePart") then
                    visual.PrimaryPart = d
                    break
                end
            end
        end
        if visual:IsA("Model") and visual.PrimaryPart then
            -- store original orientation vectors to avoid rotating with player
            local prim = visual.PrimaryPart
            local rightVec = prim.CFrame.RightVector
            local upVec = prim.CFrame.UpVector
            hbConn = RunService.Heartbeat:Connect(function()
                local char = player.Character
                local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
                if hrp and visual and visual.Parent then
                    pcall(function()
                        visual:SetPrimaryPartCFrame(CFrame.fromMatrix(hrp.Position, rightVec, upVec))
                    end)
                end
            end)
        elseif visual:IsA("BasePart") then
            local rightVec = visual.CFrame.RightVector
            local upVec = visual.CFrame.UpVector
            hbConn = RunService.Heartbeat:Connect(function()
                local char = player.Character
                local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
                if hrp and visual and visual.Parent then
                    pcall(function()
                        visual.CFrame = CFrame.fromMatrix(hrp.Position, rightVec, upVec)
                    end)
                end
            end)
        end
    end

    local co = task.spawn(function()
        while running do
            local startTime = tick()
            local char = player.Character
            local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
            if hrp then
                -- visual is updated per-frame by Heartbeat connection (hbConn)
                for _, candidate in ipairs(workspace:GetChildren()) do
                    if candidate ~= char and isValidEnemyModel(candidate, player) then
                        local targetHRP = candidate:FindFirstChild("HumanoidRootPart") or candidate.PrimaryPart
                        if targetHRP then
                            local dist = (targetHRP.Position - hrp.Position).Magnitude
                            if dist <= cfg.radius then
                                -- use shared Damage module if available, otherwise fall back to direct damage helper
                                local hum = candidate:FindFirstChildOfClass("Humanoid")
                                if Damage and hum then
                                    pcall(function()
                                        local creatorTag = Instance.new("ObjectValue")
                                        creatorTag.Name = "creator"
                                        creatorTag.Value = player
                                        creatorTag.Parent = hum
                                        Damage.Apply(hum, damagePerTick, { damageType = "reiatsu" })
                                        creatorTag:Destroy()
                                    end)
                                else
                                    damageModel(candidate, damagePerTick, player)
                                end
                                applyKnockbackToModel(candidate, hrp.Position, cfg.knockback_strength * 0.25)
                            end
                        end
                    end
                end
            end
            local elapsed = tick() - startTime
            local waitTime = math.max(0, tickInterval - elapsed)
            task.wait(waitTime)
        end
    end)

    return {
        stop = function() running = false end,
        thread = co,
        visual = visual,
        heartbeat = hbConn,
        level = level,
    }
end

function Aizen_Reiatsu.OnCardAdded(player, def, level)
    if not player then return end
    if _active[player] then return end
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
    local inst = startAuraForPlayer(player, def or {}, level)
    if inst then inst.folder = myFolder end
    _active[player] = inst
end

function Aizen_Reiatsu.OnLevelUp(player, newLevel)
    if not player then return end
    -- restart aura with new level
    if _active[player] then
        Aizen_Reiatsu.Stop(player)
        Aizen_Reiatsu.OnCardAdded(player, nil, newLevel)
    end
end

function Aizen_Reiatsu.Stop(player)
    local v = _active[player]
    if v then
        pcall(function() v.stop() end)
        if v.visual and v.visual.Parent then
            pcall(function() v.visual:Destroy() end)
        end
        if v.heartbeat then
            pcall(function() v.heartbeat:Disconnect() end)
        end
        _active[player] = nil
    end
end

Players.PlayerRemoving:Connect(function(plr)
    if _active[plr] then
        pcall(function() _active[plr].stop() end)
        _active[plr] = nil
    end
end)

return Aizen_Reiatsu
