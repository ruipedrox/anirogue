-- Nezuko Searing Frenzy
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Damage = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("Damage"))

local def = {
    Name = "Searing Frenzy",
    Rarity = "Epic",
    Type = "Active",
    MaxLevel = 5,
    Description = "Periodically deals damage to enemies affected by bleed within range and spawns a small blood burst on each hit.",
}

def.maxLevel = def.MaxLevel
def.id = def.id or script.Name

local statsPerLevel = {
    [1] = { damagePercent = 0.20, cooldown = 7 },
    [2] = { damagePercent = 0.35, cooldown = 6 },
    [3] = { damagePercent = 0.55, cooldown = 5 },
    [4] = { damagePercent = 0.80, cooldown = 4 },
    [5] = { damagePercent = 1.10, cooldown = 3 },
}

local ActiveByUser = {}

local function findPlayerBaseDamage(player)
    if not player then return 0 end
    local pst = player:FindFirstChild("Stats")
    local baseDamage = 30
    if pst then
        local bd = pst:FindFirstChild("BaseDamage")
        if bd and bd:IsA("NumberValue") then baseDamage = bd.Value end
    end
    return baseDamage
end

local function hasBleedEffectOnModel(model)
    if not model then return false end
    local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if not hrp then return false end
    local attach = hrp:FindFirstChild("DoTEffectAttachment")
    if not attach then return false end
    for _, child in ipairs(attach:GetChildren()) do
        if child and child.Name and string.lower(child.Name):find("bleed") then
            return true
        end
    end
    return false
end

local function spawnBloodBurstAt(position)
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Size = Vector3.new(0.5,0.5,0.5)
    part.CFrame = CFrame.new(position + Vector3.new(0,1,0))
    part.Transparency = 1
    part.Parent = workspace

    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "Nezuko_BloodBurst"
    emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    emitter.Color = ColorSequence.new(Color3.fromRGB(180,0,0), Color3.fromRGB(100,0,0))
    emitter.Speed = NumberRange.new(6, 10)
    emitter.Lifetime = NumberRange.new(0.2, 0.4)
    emitter.Rate = 200
    emitter.Rotation = NumberRange.new(0,360)
    emitter.RotSpeed = NumberRange.new(-180,180)
    emitter.SpreadAngle = Vector2.new(180,180)
    emitter.Size = NumberSequence.new(0.1, 0.3)
    emitter.Parent = part

    -- emit briefly
    task.spawn(function()
        -- give one frame for emitter to register
        task.wait(0.02)
        emitter:Emit(30)
        local fadeTime = 0.45
        task.delay(fadeTime, function()
            if emitter then emitter.Enabled = false end
        end)
        Debris:AddItem(part, 1)
    end)

    return part
end

local function applyDamageToBleedingEnemies(player, stats)
    local baseDamage = findPlayerBaseDamage(player)
    local totalDamage = baseDamage * (stats.damagePercent or 0.2)

    for _, model in pairs(CollectionService:GetTagged("Enemy")) do
        if model and model.PrimaryPart then
            if hasBleedEffectOnModel(model) then
                local hum = model:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    pcall(function() Damage.Apply(hum, totalDamage) end)
                    -- determine a safe position (prefer HumanoidRootPart if present)
                    local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
                    if hrp and hrp.Position then
                        pcall(function() spawnBloodBurstAt(hrp.Position) end)
                    else
                        -- fallback: try to use model:GetModelCFrame() if available
                        local ok, cf = pcall(function() return model:GetModelCFrame() end)
                        if ok and cf and cf.p then
                            pcall(function() spawnBloodBurstAt(cf.p) end)
                        end
                    end
                end
            end
        end
    end
end

function def.OnEquip(player, level)
    level = math.clamp(level or 1, 1, def.MaxLevel)
    local userId = player.UserId
    if ActiveByUser[userId] then def.OnUnequip(player) end

    local stats = statsPerLevel[level]
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
    
    print(string.format("[Nezuko_SearingFrenzy] OnEquip called for %s at level %d", tostring(player and player.Name), level))

    local conn = RunService.Heartbeat:Connect(function()
        if not player.Parent or not player.Character then
            def.OnUnequip(player)
            return
        end
        local now = os.clock()
        if now - last >= stats.cooldown then
            last = now
            print(string.format("[Nezuko_SearingFrenzy] triggering effect for %s", tostring(player and player.Name)))
            task.spawn(function()
                applyDamageToBleedingEnemies(player, stats)
            end)
        end
    end)

    ActiveByUser[userId] = { connection = conn, level = level }
end

function def.OnLevelUp(player, newLevel)
    if ActiveByUser[player.UserId] then
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
    print(string.format("[Nezuko_SearingFrenzy] OnCardAdded for %s level %s", tostring(player and player.Name), tostring(level)))
    def.OnEquip(player, level or 1)
end

def.Stats = statsPerLevel

return def
