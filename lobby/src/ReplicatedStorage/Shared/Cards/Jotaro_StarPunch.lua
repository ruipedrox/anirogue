-- Jotaro_StarPunch.lua
-- Simple cone attack: damages enemies in a forward cone, spawns a 'shock' visual in front of the player, then goes on cooldown.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Scripts = ReplicatedStorage:WaitForChild("Scripts")
local Damage = require(Scripts:WaitForChild("Combat"):WaitForChild("Damage"))

local def = {
    Name = "Star Punch",
    Rarity = "Epic",
    Type = "Active",
    MaxLevel = 5,
    Description = "Quick cone strike in front of the player that deals damage to enemies, then enters cooldown.",
}

def.id = def.id or script.Name

local Active = {}

local statsPerLevel = {
    [1] = { range = 8, coneDeg = 60, damageMul = 0.8, cooldown = 6.0 },
    [2] = { range = 10, coneDeg = 65, damageMul = 1.0, cooldown = 5.5 },
    [3] = { range = 12, coneDeg = 70, damageMul = 1.2, cooldown = 5.0 },
    [4] = { range = 14, coneDeg = 75, damageMul = 1.4, cooldown = 4.5 },
    [5] = { range = 16, coneDeg = 80, damageMul = 1.6, cooldown = 4.0 },
}

local function getOriginAndLook(player)
    local char = player.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
    if not hrp then return nil end
    return hrp.Position, hrp.CFrame.LookVector, hrp.CFrame
end

local function findEnemiesInCone(origin, lookVec, range, halfAngle)
    local results = {}
    local tagged = CollectionService:GetTagged("Enemy")
    for _, m in ipairs(tagged) do
        if m and m:IsA("Model") then
            local hrp = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
            local hum = m:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local toTarget = hrp.Position - origin
                local dist = toTarget.Magnitude
                if dist <= range and dist > 0.001 then
                    local dir = toTarget.Unit
                    local ang = math.acos(math.clamp(dir:Dot(lookVec), -1, 1))
                    if ang <= halfAngle then
                        table.insert(results, { model = m, humanoid = hum })
                    end
                end
            end
        end
    end
    return results
end

local function spawnShockVisual(player)
    local charsFolder = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("Chars")
    if not charsFolder then return end
    local sanjiFolder = charsFolder:FindFirstChild("Jotaro_4") or charsFolder:FindFirstChild("Jotaro_5") or charsFolder:FindFirstChild("Jotaro_3")
    if not sanjiFolder then return end
    local template = sanjiFolder:FindFirstChild("shock")
    if not template then return end

    local ok, clone = pcall(function() return template:Clone() end)
    if not ok or not clone then return end
    clone.Parent = workspace

    -- prevent physics from making the visual fall: disable collisions and anchor parts
    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("BasePart") then
            d.CanCollide = false
            d.Anchored = true
        end
    end

    local char = player and player.Character
    local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
    if not hrp then clone:Destroy() return end

    -- position slightly in front with configurable offset and rotate the model so it's laid down facing forward
    local forward = hrp.CFrame.LookVector
    local offsetForward = -1
    local verticalOffset = 0.5
    local pos = hrp.Position + forward * offsetForward + Vector3.new(0, verticalOffset, 0)
    -- orient the visual to face forward and lay flat (-90deg X)
    local visualCFrame = CFrame.new(pos, pos + forward) * CFrame.Angles(math.rad(-90), 0, 0)
    if clone:IsA("Model") then
        -- ensure model has a primary part; otherwise pivot to the CFrame
        local primary = clone.PrimaryPart
        if primary then
            clone:SetPrimaryPartCFrame(visualCFrame)
        else
            clone:PivotTo(visualCFrame)
        end
    elseif clone:IsA("BasePart") then
        clone.CFrame = visualCFrame
    end

    -- simple life: scale up quickly then fade
    local life = 0.6
    task.spawn(function()
        local start = os.clock()
        while os.clock() - start < life do
            if not clone or not clone.Parent then break end
            task.wait(0.05)
        end
        -- fade parts and remove (tween transparencies, disable particles)
        local fadeTime = 0.3
        for _, d in ipairs(clone:GetDescendants()) do
            if d:IsA("BasePart") then
                d.CanCollide = false
                d.Anchored = true
                pcall(function()
                    TweenService:Create(d, TweenInfo.new(fadeTime, Enum.EasingStyle.Linear), {Transparency = 1}):Play()
                end)
            elseif d:IsA("ParticleEmitter") then
                d.Enabled = false
            elseif d:IsA("Decal") or d:IsA("Texture") then
                pcall(function()
                    TweenService:Create(d, TweenInfo.new(fadeTime, Enum.EasingStyle.Linear), {Transparency = 1}):Play()
                end)
            end
        end
        Debris:AddItem(clone, fadeTime + 0.05)
    end)
end

function def.Fire(player, level, onFinished)
    level = math.clamp(tonumber(level) or 1, 1, def.MaxLevel)
    local s = statsPerLevel[level] or statsPerLevel[1]
    local range = s.range or 8
    local coneDeg = s.coneDeg or 60
    local damageMul = s.damageMul or 1

    local originPos, lookVec = getOriginAndLook(player)
    if not originPos then if type(onFinished) == "function" then pcall(onFinished) end return end

    local halfAngle = math.rad(coneDeg / 2)
    local enemies = findEnemiesInCone(originPos, lookVec, range, halfAngle)

    local baseDamage = (player:FindFirstChild("Stats") and player.Stats:FindFirstChild("BaseDamage") and player.Stats.BaseDamage.Value) or 10
    local dmg = math.max(1, baseDamage * damageMul)

    for _, entry in ipairs(enemies) do
        local hum = entry.humanoid
        if hum and hum.Health > 0 then
            local creator = hum:FindFirstChild("creator")
            if not creator then
                creator = Instance.new("ObjectValue")
                creator.Name = "creator"
                creator.Value = player
                creator.Parent = hum
                task.delay(2, function() if creator and creator.Parent then creator:Destroy() end end)
            end
            pcall(function() Damage.Apply(hum, dmg, { damageType = "star_punch" }) end)
        end
    end

    spawnShockVisual(player)

    if type(onFinished) == "function" then pcall(onFinished) end
end

function def.OnEquip(player, level)
    level = math.clamp(tonumber(level) or 1, 1, def.MaxLevel)
    if Active[player] then def.OnUnequip(player) end

    local rt = player:FindFirstChild("RunTrack") or Instance.new("Folder")
    if not rt.Parent then rt.Name = "RunTrack" rt.Parent = player end
    local myFolder = rt:FindFirstChild(def.id) or Instance.new("Folder")
    myFolder.Name = def.id; myFolder.Parent = rt
    local lvlNV = myFolder:FindFirstChild("Level") or Instance.new("IntValue")
    lvlNV.Name = "Level"; lvlNV.Value = level; lvlNV.Parent = myFolder

    local s = statsPerLevel[level] or statsPerLevel[1]
    local cooldown = s.cooldown or 6.0

    local conn
    local acc = cooldown
    conn = RunService.Heartbeat:Connect(function(dt)
        if ReplicatedStorage:GetAttribute("GamePaused") then return end
        if not player or not player.Parent then if conn then conn:Disconnect() end return end
        acc = acc + (dt or 0)
        if acc < cooldown then return end
        acc = 0
        task.spawn(function()
            local ok, err = pcall(function() def.Fire(player, level) end)
            if not ok then warn("[StarPunch] Fire error:", err) end
        end)
    end)

    Active[player] = { conn = conn, folder = myFolder }
end

function def.OnUnequip(player)
    local data = Active[player]
    if not data then return end
    if data.conn then pcall(function() data.conn:Disconnect() end) end
    Active[player] = nil
end

function def.OnCardAdded(player, defTable, level)
    def.OnEquip(player, level or 1)
end

function def.OnLevelUp(player, newLevel)
    local data = Active[player]
    if not data then return end
    local lvlNV = data.folder and data.folder:FindFirstChild("Level")
    if lvlNV then lvlNV.Value = tonumber(newLevel) or lvlNV.Value end
end

return def
