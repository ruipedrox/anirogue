-- Sanji_BurnAura.lua
-- Sanji 4★ exclusive: Flame Spin — performs a spinning AoE that deals damage then goes on cooldown

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Scripts = ReplicatedStorage:WaitForChild("Scripts")
local Damage = require(Scripts:WaitForChild("Combat"):WaitForChild("Damage"))
local DoT = require(Scripts:WaitForChild("Combat"):WaitForChild("DoT"))

local def = {
    Name = "Flame Spin",
    Rarity = "Epic",
    Type = "Active",
    MaxLevel = 5,
    Description = "Active: Spin around the player, dealing instant AoE damage and applying a burn DoT to enemies; then goes on cooldown.",
}

def.id = def.id or script.Name
def.maxLevel = def.MaxLevel

local Active = {}

-- Tunable stats per level for balancing
local statsPerLevel = {
    -- range, cooldown, damageMultiplier (fraction of baseDamage applied instantly),
    -- burnPlayerMultiplier (fraction of baseDamage passed to DoT.Apply as playerDamage), burnTick (DoT tick rate)
    [1] = { range = 6, cooldown = 6.0, damageMultiplier = 0.5, burnPlayerMultiplier = 0.4, burnTick = 1.0 },
    [2] = { range = 7, cooldown = 5.5, damageMultiplier = 0.65, burnPlayerMultiplier = 0.55, burnTick = 1.0 },
    [3] = { range = 8, cooldown = 5.0, damageMultiplier = 0.8, burnPlayerMultiplier = 0.7, burnTick = 0.75 },
    [4] = { range = 9, cooldown = 4.5, damageMultiplier = 0.9, burnPlayerMultiplier = 0.85, burnTick = 0.6 },
    [5] = { range = 10, cooldown = 4.0, damageMultiplier = 1.0, burnPlayerMultiplier = 1.0, burnTick = 0.5 },
}

local function ensureFolder(parent, name)
    local f = parent:FindFirstChild(name)
    if not f then f = Instance.new("Folder") f.Name = name f.Parent = parent end
    return f
end

local function ensureNumber(parent, name, value)
    local nv = parent:FindFirstChild(name)
    if not nv then nv = Instance.new("NumberValue") nv.Name = name nv.Value = value nv.Parent = parent end
    return nv
end

local function getStats(player)
    local stats = player:FindFirstChild("Stats")
    if not stats then return 0, 1 end
    local function num(name, default)
        local nv = stats:FindFirstChild(name)
        if nv and nv:IsA("NumberValue") then return nv.Value end
        return default
    end
    local baseDamage = num("BaseDamage", 0)
    local dmgPercent = num("DamagePercent", 0)
    local percentMult = 1 + math.max(-0.99, (dmgPercent or 0) / 100)
    return baseDamage, percentMult
end

local function findEnemiesInRadius(origin, radius)
    local results = {}
    local tagged = CollectionService:GetTagged("Enemy")
    for _, m in ipairs(tagged) do
        if m and m:IsA("Model") then
            local hrp = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
            local hum = m:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                if (hrp.Position - origin).Magnitude <= radius then
                    table.insert(results, m)
                end
            end
        end
    end
    return results
end

local function applyBurnToHumanoid(hum, player, burnDPS, duration)
    if not hum or not hum.Parent then return end
    -- Use a NumberValue to track remaining burn time and avoid multiple concurrent loops
    local burnNV = hum:FindFirstChild("SanjiBurn")
    if not burnNV then
        burnNV = Instance.new("NumberValue")
        burnNV.Name = "SanjiBurn"
        burnNV.Value = duration
        burnNV.Parent = hum
        task.spawn(function()
            while burnNV and burnNV.Parent and burnNV.Value > 0 and hum and hum.Health > 0 do
                -- apply per-second burn damage
                pcall(function() Damage.Apply(hum, burnDPS) end)
                burnNV.Value = math.max(0, burnNV.Value - 1)
                task.wait(1)
            end
            if burnNV and burnNV.Parent then pcall(function() burnNV:Destroy() end) end
        end)
    else
        -- refresh duration
        burnNV.Value = math.max(burnNV.Value, duration)
    end
end

-- Minimal Fire: instant AoE damage + apply DoT using DoT.Apply
function def.Fire(player, level, onFinished)
    level = math.clamp(tonumber(level) or 1, 1, def.MaxLevel)
    local s = statsPerLevel[level] or statsPerLevel[1]
    local range = s.range or 6
    local damageMul = s.damageMultiplier or 0.5
    local burnMul = s.burnPlayerMultiplier or 0.4
    local burnTick = s.burnTick or 1.0

    local originPos
    local char = player and player.Character
    local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
    if hrp then originPos = hrp.Position else return end

    local baseDamage, percentMult = getStats(player)
    local instantDamage = math.max(1, baseDamage * percentMult * damageMul)
    local dotPlayerDamage = math.max(1, baseDamage * percentMult * burnMul)

    local enemies = findEnemiesInRadius(originPos, range)
    for _, m in ipairs(enemies) do
        local hum = m:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            -- creator tag for attribution
            local creator = hum:FindFirstChild("creator")
            if not creator then
                creator = Instance.new("ObjectValue")
                creator.Name = "creator"
                creator.Value = player
                creator.Parent = hum
                task.delay(2, function() if creator and creator.Parent then creator:Destroy() end end)
            end
            pcall(function() Damage.Apply(hum, instantDamage, { damageType = "flame_spin" }) end)
            pcall(function()
                DoT.Apply(hum, { dotType = "burn", playerDamage = dotPlayerDamage, tick = burnTick })
            end)
        end
    end

    -- spawn visual model (one 360 spin + fade) if available
    task.spawn(function()
        local ok, err = pcall(function()
            local charsFolder = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("Chars")
            if not charsFolder then return end
            local sanjiFolder = charsFolder:FindFirstChild("Sanji_4") or charsFolder:FindFirstChild("Sanji_5") or charsFolder:FindFirstChild("Sanji_3")
            if not sanjiFolder then return end
            local template = sanjiFolder:FindFirstChild("flame_spin")
            if not template then return end

            local model = template:Clone()
            if not model then return end
            model.Parent = workspace

            local char = player and player.Character
            local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
            if not hrp then return end

            local baseCFrame = hrp.CFrame
            -- position model at player's HRP pivot; start laid down (rotate -90deg on X)
            local visualCFrame = baseCFrame * CFrame.Angles(0, 0, math.rad(-90))
            if model:IsA("Model") then
                model:PivotTo(visualCFrame)
            else
                -- if it's a single part
                if model:IsA("BasePart") then
                    model.CFrame = visualCFrame
                end
            end

            local spinDuration = 0.2
            local elapsed = 0
            local conn
            conn = RunService.Heartbeat:Connect(function(dt)
                if not model or not model.Parent then if conn then conn:Disconnect() end return end
                elapsed = elapsed + (dt or 0)
                local t = math.clamp(elapsed / spinDuration, 0, 1)
                local ang = t * math.pi * 2
                if model:IsA("Model") then
                    model:PivotTo(visualCFrame * CFrame.Angles(ang, 0, 0))
                else
                    if model:IsA("BasePart") then
                        model.CFrame = visualCFrame * CFrame.Angles(ang, 0, 0)
                    end
                end
                if elapsed >= spinDuration then
                    conn:Disconnect()
                    -- fade out parts and stop particle emitters
                    local fadeTime = 0.4
                    for _, desc in ipairs(model:GetDescendants()) do
                        if desc:IsA("BasePart") then
                            desc.CanCollide = false
                            desc.Anchored = true
                            local ti = TweenInfo.new(fadeTime, Enum.EasingStyle.Linear)
                            pcall(function()
                                TweenService:Create(desc, ti, {Transparency = 1}):Play()
                            end)
                        elseif desc:IsA("ParticleEmitter") then
                            desc.Enabled = false
                        end
                    end
                    Debris:AddItem(model, fadeTime + 0.05)
                end
            end)
        end)
        if not ok then warn("[FlameSpin] visual spawn error:", err) end
    end)

    if type(onFinished) == "function" then pcall(onFinished) end
end

function def.OnEquip(player, level)
    level = math.clamp(tonumber(level) or 1, 1, def.MaxLevel)
    if Active[player] then def.OnUnequip(player) end

    local rt = player:FindFirstChild("RunTrack") or ensureFolder(player, "RunTrack")
    local myFolder = rt:FindFirstChild(def.id) or Instance.new("Folder")
    myFolder.Name = def.id
    myFolder.Parent = rt

    local lvlNV = myFolder:FindFirstChild("Level") or Instance.new("IntValue")
    lvlNV.Name = "Level"; lvlNV.Value = level; lvlNV.Parent = myFolder

    -- cooldown-driven activation: call def.Fire every `cooldown` seconds
    local s = statsPerLevel[level] or statsPerLevel[1]
    local cooldown = s.cooldown or 6.0

    local conn
    local acc = cooldown -- start ready; set to 0 if you want to wait full cooldown on equip
    conn = RunService.Heartbeat:Connect(function(dt)
        if ReplicatedStorage:GetAttribute("GamePaused") then return end
        if not player or not player.Parent then if conn then conn:Disconnect() end return end
        acc = acc + (dt or 0)
        if acc < cooldown then return end
        acc = 0
        -- perform the simple AoE + DoT
        task.spawn(function()
            local ok, err = pcall(function() def.Fire(player, level) end)
            if not ok then warn("[FlameSpin] Fire error:", err) end
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
