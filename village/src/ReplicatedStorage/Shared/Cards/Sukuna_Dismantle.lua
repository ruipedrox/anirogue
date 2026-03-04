-- Sukuna Dismantle (periodic AoE around a random enemy)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Damage = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("Damage"))
local SFXHelper = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("SFXHelper"))

local DISMANTLE_SFX_ID = 122951695254282

local def = {
    Name = "Dismantle",
    Rarity = "Rare",
    Type = "Active",
    MaxLevel = 5,
    Description = "Periodically picks a random enemy and applies area damage around it for 2s. Shows a visual on the target.",
}

local statsPerLevel = {
    [1] = { damagePercent = 0.2, cooldown = 8, aoe = 6, duration = 2, stagger = 0.18 },
    [2] = { damagePercent = 0.4, cooldown = 7.5, aoe = 6.5, duration = 2, stagger = 0.2 },
    [3] = { damagePercent = 0.6, cooldown = 7, aoe = 7, duration = 2, stagger = 0.22 },
    [4] = { damagePercent = 0.8, cooldown = 6.5, aoe = 7.5, duration = 2, stagger = 0.24 },
    [5] = { damagePercent = 1.0, cooldown = 6, aoe = 8, duration = 2, stagger = 0.26 },
}

local ActiveByUser = {}

local function findCharAsset(partName)
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    if not shared then return nil end
    local chars = shared:FindFirstChild("Chars")
    if not chars then return nil end
    local group = chars:FindFirstChild("Sukuna_5")
    if group then
        return group:FindFirstChild(partName) or group:FindFirstChild(partName:lower()) or group:FindFirstChild(partName:upper())
    end
    for _, g in ipairs(chars:GetChildren()) do
        if g and (g:IsA("Folder") or g:IsA("Model")) then
            local candidate = g:FindFirstChild(partName)
            if candidate then return candidate end
        end
    end
    return nil
end

local function getRandomEnemy()
    local enemies = CollectionService:GetTagged("Enemy")
    if not enemies or #enemies == 0 then return nil end
    local choices = {}
    for _, m in ipairs(enemies) do
        if m and m.PrimaryPart then table.insert(choices, m) end
    end
    if #choices == 0 then return nil end
    return choices[math.random(1, #choices)]
end

local function spawnDismantleVisual(targetModel)
    if not targetModel or not targetModel.PrimaryPart then return end
    local asset = findCharAsset("Dismantle") or findCharAsset("dismantle")
    if not asset then return end
    local ok, clone = pcall(function() return asset:Clone() end)
    if not ok or not clone then return end
    local visualParts = {}
    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("BasePart") then
            d.CanCollide = false
            d.CanTouch = false
            d.Anchored = true
            d.Transparency = d.Transparency or 0
            table.insert(visualParts, d)
        elseif d:IsA("Decal") or d:IsA("Texture") then
            d.Transparency = d.Transparency or 0
            table.insert(visualParts, d)
        end
    end
    if not clone.PrimaryPart then clone.PrimaryPart = clone:FindFirstChildWhichIsA("BasePart") end
    if clone.PrimaryPart then
        clone:SetPrimaryPartCFrame(targetModel.PrimaryPart.CFrame)
    end
    clone.Parent = workspace

    local waitBefore = 0
    local fadeTime = 1.0
    task.delay(waitBefore, function()
        local tweenInfo = TweenInfo.new(fadeTime, Enum.EasingStyle.Linear)
        for _, p in ipairs(visualParts) do
            pcall(function()
                local tween = TweenService:Create(p, tweenInfo, {Transparency = 1})
                tween:Play()
            end)
        end
    end)
    Debris:AddItem(clone, fadeTime + waitBefore + 0.1)
    return clone
end

local function applyAoeDamageAround(position, ownerPlayer, damagePerTick, aoeRadius, staggerDuration)
    local parts = workspace:GetPartBoundsInRadius(position, aoeRadius or 6)
    if parts and #parts > 0 then
        local seen = {}
        for _, p in ipairs(parts) do
            local mdl = p and p:FindFirstAncestorOfClass("Model")
            if mdl and not seen[mdl] then
                seen[mdl] = true
                if ownerPlayer and ownerPlayer.Character and mdl == ownerPlayer.Character then continue end
                local hum = mdl:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    pcall(function() Damage.Apply(hum, damagePerTick) end)
                    -- apply stagger: zero movement for a short duration, then restore
                    if staggerDuration and staggerDuration > 0 then
                        -- store original values if not already stored
                        if hum:GetAttribute("sukuna_orig_walkspeed") == nil then
                            pcall(function() hum:SetAttribute("sukuna_orig_walkspeed", hum.WalkSpeed) end)
                        end
                        if hum:GetAttribute("sukuna_orig_jumppower") == nil then
                            pcall(function() hum:SetAttribute("sukuna_orig_jumppower", hum.JumpPower) end)
                        end
                        -- apply
                        pcall(function() hum.WalkSpeed = 0 end)
                        pcall(function() hum.JumpPower = 0 end)
                        task.delay(staggerDuration, function()
                            if hum and hum.Parent then
                                local ok, ows = pcall(function() return hum:GetAttribute("sukuna_orig_walkspeed") end)
                                if ok and ows then pcall(function() hum.WalkSpeed = ows end) hum:SetAttribute("sukuna_orig_walkspeed", nil) end
                                local ok2, ojp = pcall(function() return hum:GetAttribute("sukuna_orig_jumppower") end)
                                if ok2 and ojp then pcall(function() hum.JumpPower = ojp end) hum:SetAttribute("sukuna_orig_jumppower", nil) end
                            end
                        end)
                    end
                end
            end
        end
    end
end

local function performDismantle(player, stats)
    if not player then return end
    local target = getRandomEnemy()
    if not target or not target.PrimaryPart then return end

    print(string.format("[Dismantle] Performing for %s on target %s", tostring(player.Name), tostring(target.Name)))

    local pst = player:FindFirstChild("Stats")
    local baseDamage = 50
    if pst then
        local bd = pst:FindFirstChild("BaseDamage")
        if bd and bd:IsA("NumberValue") then baseDamage = bd.Value end
    end

    local totalDamage = baseDamage * (stats.damagePercent or 0.5)
    local duration = stats.duration or 2
    local ticks = math.max(2, math.floor(duration / 0.25))
    local perTick = totalDamage / ticks

    -- visual
    local vis = spawnDismantleVisual(target)
    if not vis then print("[Dismantle] No visual spawned (asset missing)") end

    SFXHelper.playAt(target.PrimaryPart, DISMANTLE_SFX_ID, 0.9, {
        minDist = 10, maxDist = 70, lifetime = duration + 0.5,
    })

    for i = 1, ticks do
        if not target.Parent then break end
        applyAoeDamageAround(target.PrimaryPart.Position, player, perTick, stats.aoe, stats.stagger)
        task.wait(duration / ticks)
    end
end

function def.OnEquip(player, level, maxLevel)
    level = math.clamp(level or 1, 1, maxLevel or def.MaxLevel)
    local userId = player.UserId
    if ActiveByUser[userId] then def.OnUnequip(player) end

    local stats = statsPerLevel[level]
    local last = 0

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

    print(string.format("[Dismantle] Equipped for %s at level %d", tostring(player.Name), level))

    local conn = RunService.Heartbeat:Connect(function()
        if not player.Parent or not player.Character then
            def.OnUnequip(player)
            return
        end
        local now = os.clock()
        if now - last >= stats.cooldown then
            local potential = getRandomEnemy()
            if potential then
                print(string.format("[Dismantle] Found potential target %s for %s", tostring(potential.Name), tostring(player.Name)))
                last = now
                task.spawn(function() performDismantle(player, stats) end)
            end
        end
    end)

    ActiveByUser[userId] = { connection = conn, level = level }
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

def.Stats = statsPerLevel

return def
