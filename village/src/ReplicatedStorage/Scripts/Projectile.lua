-- Projectile.lua
-- Simple server-side projectile utility with pierce handling.
-- Spawns a projectile (model or default part), moves it along a direction at a speed,
-- raycasts for collisions each frame, and decrements pierce on enemy hit.
-- Destroys itself when lifetime expires or pierce <= 0.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Projectile = {}
local Damage = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Combat"):WaitForChild("Damage"))

-- Global tracking: map owner -> list of active projectile handles
local OwnerProjectiles: {[Instance]: {ProjectileHandle}} = {}

-- Helper: find the top-level model with a Humanoid for a hit part
local function getHumanoidModelFromPart(part: BasePart?)
    if not part then return nil end
    local node: Instance? = part
    while node do
        if node:IsA("Model") then
            local hasHum = (node :: Model):FindFirstChildWhichIsA("Humanoid", true)
            if hasHum then
                return node :: Model
            end
        end
        node = node.Parent
    end
    return nil
end

local function findAnyBasePart(model: Instance): BasePart?
    if model:IsA("BasePart") then
        return model
    end
    if model:IsA("Model") then
        if model.PrimaryPart then
            return model.PrimaryPart
        end
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then
                return d
            end
        end
    end
    return nil
end

local function createDefaultProjectile(origin: Vector3, direction: Vector3)
    local part = Instance.new("Part")
    part.Size = Vector3.new(0.2, 0.2, 1)
    part.Color = Color3.fromRGB(255, 230, 109)
    part.Material = Enum.Material.Neon
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Name = "Projectile"
    part.CFrame = CFrame.new(origin, origin + direction)
    part.Parent = workspace
    return part
end

export type FireParams = {
    origin: Vector3,
    direction: Vector3, -- will be unitized
    speed: number, -- studs per second
    lifetime: number?, -- seconds (default 2)
    pierce: number?, -- integer (default 1)
    damage: number?, -- optional damage to apply to Humanoid:TakeDamage
    model: Instance?, -- BasePart or Model to clone; if nil, uses default neon part
    owner: Player | Model | nil, -- used to ignore owner character in raycasts
    ignore: {Instance}?, -- additional instances to ignore in raycasts
    onHit: ((hitPart: BasePart, enemyModel: Model) -> ())?, -- optional callback per enemy hit
    orientationOffset: CFrame?, -- optional local rotation to apply after facing direction
    hitCooldownPerTarget: number?, -- seconds to wait before the same enemy can be hit again (default 0.2)
    spinPerSecond: number?, -- optional constant spin (radians/sec) around chosen axis during flight
    spinAxis: string?, -- "X" | "Y" | "Z" (default "Y")
    contactRadius: number?, -- optional proximity hit radius (studs). If >0, enemies within this radius around the projectile will be considered a hit
    proximityDelay: number?, -- optional delay (s) before proximity is active to allow render
    proximityMinDistance: number?, -- optional minimum travel distance before proximity can trigger
}

export type ProjectileHandle = {
    Instance: Instance?,
    Destroy: (self: any) -> (),
}

local function buildIgnoreList(instances: {Instance}?): {Instance}
    local ignoreList = {}
    if instances then
        for _, inst in ipairs(instances) do
            table.insert(ignoreList, inst)
        end
    end
    return ignoreList
end

-- Core fire function
function Projectile.Fire(params: FireParams): ProjectileHandle
    assert(params and typeof(params.origin) == "Vector3", "Projectile.Fire: missing origin")
    assert(params and typeof(params.direction) == "Vector3", "Projectile.Fire: missing direction")
    assert(typeof(params.speed) == "number" and params.speed > 0, "Projectile.Fire: speed must be > 0")

    local direction = params.direction.Magnitude > 0 and params.direction.Unit or Vector3.new(0, 0, -1)
    local lifetime = typeof(params.lifetime) == "number" and params.lifetime or 2
    local pierce = typeof(params.pierce) == "number" and math.floor(params.pierce) or 1
    local damage = typeof(params.damage) == "number" and params.damage or 0

    -- Build or clone the projectile instance
    local inst: Instance
    if params.model then
        inst = params.model:Clone()
    else
        inst = createDefaultProjectile(params.origin, direction)
    end

    local basePart = findAnyBasePart(inst)
    if not basePart then
        -- Try to wrap non-part models/folders in a container with a carrier part
        if inst:IsA("Model") or inst:IsA("Folder") then
            local container = Instance.new("Model")
            container.Name = "ProjectileContainer"
            local carrier = Instance.new("Part")
            carrier.Name = "Carrier"
            carrier.Size = Vector3.new(0.2, 0.2, 0.2)
            carrier.Transparency = 1
            carrier.Anchored = true
            carrier.CanCollide = false
            carrier.CanQuery = false
            carrier.CanTouch = false
            carrier.Parent = container
            local attach = Instance.new("Attachment")
            attach.Name = "CarrierAttachment"
            attach.Parent = carrier
            -- Parent the original instance into the container
            inst.Parent = container
            -- Use the carrier as the primary/movable part
            container.PrimaryPart = carrier
            inst = container
            basePart = carrier
            -- Fix up common effect primitives so they render when there is no BasePart in the original
            for _, d in ipairs(container:GetDescendants()) do
                if d:IsA("ParticleEmitter") then
                    -- ParticleEmitter must be under a BasePart or Attachment
                    d.Parent = attach
                elseif d:IsA("BillboardGui") then
                    -- Make the billboard follow the carrier if it has no Adornee
                    if d.Adornee == nil then d.Adornee = carrier end
                end
            end
        else
            warn("Projectile.Fire: provided instance is not a Model/BasePart; using default.")
            if inst then inst:Destroy() end
            inst = createDefaultProjectile(params.origin, direction)
            basePart = findAnyBasePart(inst) :: BasePart
        end
    end

    -- Ensure baseline physics flags
    if basePart:IsA("BasePart") then
        basePart.Anchored = true
        basePart.CanCollide = false
        basePart.CanQuery = false
        basePart.CanTouch = false -- raycast handles hits
    end

    -- Position and parent
    local initialCF = CFrame.new(params.origin, params.origin + direction)
    if params.orientationOffset then
        initialCF = initialCF * params.orientationOffset
    end
    if inst:IsA("Model") then
        if not inst.PrimaryPart then
            inst.PrimaryPart = basePart
        end
        inst:PivotTo(initialCF)
        inst.Parent = workspace
    else
        (inst :: BasePart).CFrame = initialCF
        inst.Parent = workspace
    end

    -- Ensure effects will render: attach orphan emitters to a known attachment and enable them
    local function hasPartOrAttachmentAncestor(obj: Instance): boolean
        local p = obj.Parent
        while p do
            if p:IsA("BasePart") or p:IsA("Attachment") then return true end
            p = p.Parent
        end
        return false
    end
    -- Create or find a carrier attachment on the basePart
    local carrierAttach: Attachment? = nil
    if basePart and basePart:IsA("BasePart") then
        carrierAttach = basePart:FindFirstChild("CarrierAttachment")
        if not carrierAttach then
            carrierAttach = Instance.new("Attachment")
            carrierAttach.Name = "CarrierAttachment"
            carrierAttach.Parent = basePart
        end
    end
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("ParticleEmitter") then
            if not hasPartOrAttachmentAncestor(d) and carrierAttach then
                d.Parent = carrierAttach
            end
            d.Enabled = true
        elseif d:IsA("Trail") then
            d.Enabled = true
        elseif d:IsA("BillboardGui") then
            if d.Adornee == nil and basePart and basePart:IsA("BasePart") then
                d.Adornee = basePart
            end
        end
    end

    -- Build raycast ignore list
    local ignoreList = buildIgnoreList(params.ignore)
    -- Ignore projectile itself
    table.insert(ignoreList, inst)
    -- Ignore owner character
    if params.owner then
        local character: Model? = nil
        if typeof(params.owner) == "Instance" then
            if params.owner:IsA("Player") then
                character = params.owner.Character
            elseif params.owner:IsA("Model") then
                character = params.owner
            end
        end
        if not character and typeof(params.owner) == "Instance" and params.owner:IsA("Player") then
            character = (params.owner :: Player).Character
        end
        if character then table.insert(ignoreList, character) end
    end

    local rcParams = RaycastParams.new()
    rcParams.FilterType = Enum.RaycastFilterType.Exclude
    rcParams.FilterDescendantsInstances = ignoreList

    local alive = true
    local elapsed = 0
    local startPos = params.origin
    local currentPos = params.origin
    local connection
    local lastHitTimes: { [Model]: number } = {}
    -- Proximity hit support
    local contactRadius = (typeof(params.contactRadius) == "number" and params.contactRadius or 0)
    if contactRadius < 0 then contactRadius = 0 end
    local ovParams = OverlapParams.new()
    ovParams.FilterType = Enum.RaycastFilterType.Exclude
    ovParams.FilterDescendantsInstances = ignoreList

    local handle: ProjectileHandle
    local spinAngle = 0
    local spinSpeed = (typeof(params.spinPerSecond) == "number") and params.spinPerSecond or 0
    local spinAxis = (type(params.spinAxis) == "string") and string.upper(params.spinAxis) or "Y"
    local function applySpin(cf: CFrame)
        if spinAngle == 0 then return cf end
        if spinAxis == "X" then
            return cf * CFrame.Angles(spinAngle, 0, 0)
        elseif spinAxis == "Z" then
            return cf * CFrame.Angles(0, 0, spinAngle)
        else
            return cf * CFrame.Angles(0, spinAngle, 0)
        end
    end
    handle = {
        Instance = inst,
        Destroy = function(self)
            if not alive then return end
            alive = false
            if connection then connection:Disconnect() end
            if inst and inst.Parent then inst:Destroy() end
            self.Instance = nil
            
            -- Remove from owner tracking
            if params.owner and OwnerProjectiles[params.owner] then
                local list = OwnerProjectiles[params.owner]
                for i = #list, 1, -1 do
                    if list[i] == self then
                        table.remove(list, i)
                    end
                end
                -- Clean up empty list
                if #list == 0 then
                    OwnerProjectiles[params.owner] = nil
                end
            end
        end
    }

    -- Track projectile by owner for auto-cleanup
    if params.owner then
        if not OwnerProjectiles[params.owner] then
            OwnerProjectiles[params.owner] = {}
        end
        table.insert(OwnerProjectiles[params.owner], handle)
        
        -- Setup death listener for this specific projectile
        local ownerModel: Model? = nil
        if typeof(params.owner) == "Instance" then
            if params.owner:IsA("Player") then
                ownerModel = params.owner.Character
            elseif params.owner:IsA("Model") then
                ownerModel = params.owner
            end
        end
        
        if ownerModel then
            local hum = ownerModel:FindFirstChildOfClass("Humanoid")
            if hum then
                -- Each projectile gets its own death listener
                local deathConnection = hum.Died:Connect(function()
                    -- Destroy this specific projectile
                    if alive and handle then
                        handle:Destroy()
                    end
                end)
                
                -- Clean up listener when projectile is destroyed
                local originalDestroy = handle.Destroy
                handle.Destroy = function(self)
                    if deathConnection then
                        deathConnection:Disconnect()
                        deathConnection = nil
                    end
                    originalDestroy(self)
                end
            end
            
            -- Also watch for owner being removed from workspace
            local ancestryConnection = ownerModel.AncestryChanged:Connect(function(_, parent)
                if not parent then
                    -- Owner removed from game, destroy this projectile
                    if alive and handle then
                        handle:Destroy()
                    end
                end
            end)
            
            -- Clean up ancestry listener when projectile is destroyed
            local originalDestroy2 = handle.Destroy
            handle.Destroy = function(self)
                if ancestryConnection then
                    ancestryConnection:Disconnect()
                    ancestryConnection = nil
                end
                originalDestroy2(self)
            end
        end
    end

    connection = RunService.Heartbeat:Connect(function(dt)
        if not alive then return end
        -- Always advance lifetime even while paused so projectiles clean up
        elapsed += dt
        if elapsed >= lifetime then
            handle:Destroy()
            return
        end
        if ReplicatedStorage:GetAttribute("GamePaused") then
            -- While paused, don't move or collide, but still count down the lifetime (above)
            return
        end

        local stepDist = params.speed * dt
        local remaining = stepDist
        local pos = currentPos

        while remaining > 0 and alive do
            if spinSpeed ~= 0 then
                spinAngle += spinSpeed * dt
            end
            -- Optional proximity hit (larger hitbox) with sampling along the segment
            if contactRadius and contactRadius > 0 and elapsed >= ((typeof(params.proximityDelay) == "number" and params.proximityDelay) or 0) then
                local minDist = (typeof(params.proximityMinDistance) == "number" and params.proximityMinDistance) or 0
                if (pos - startPos).Magnitude < minDist then
                    -- Skip proximity this iteration until we have traveled far enough
                else
                local stepLen = remaining
                local samples = math.clamp(math.ceil(stepLen / math.max(1, contactRadius * 0.75)), 1, 5)
                local hit = false
                for s = 0, samples do
                    local t = (samples == 0) and 0 or (s / samples)
                    local samplePos = pos + direction * (stepLen * t)
                    local nearby = workspace:GetPartBoundsInRadius(samplePos, contactRadius, ovParams)
                    if nearby and #nearby > 0 then
                        -- Find the first enemy humanoid model among the parts
                        local enemyModel: Model? = nil
                        for _, p in ipairs(nearby) do
                            local m = getHumanoidModelFromPart(p)
                            if m then enemyModel = m break end
                        end
                        if enemyModel then
                            local now = os.clock()
                            local cd = typeof(params.hitCooldownPerTarget) == "number" and params.hitCooldownPerTarget or 0.2
                            local last = lastHitTimes[enemyModel]
                            if (not last) or (now - last) >= cd then
                                lastHitTimes[enemyModel] = now
                                if damage > 0 then
                                    local hum = enemyModel:FindFirstChildOfClass("Humanoid")
                                    if hum then Damage.Apply(hum, damage) end
                                end
                                if params.onHit then
                                    -- Use a dummy BasePart reference when using proximity
                                    task.spawn(params.onHit, findAnyBasePart(enemyModel) :: BasePart, enemyModel)
                                end
                                pierce -= 1
                                if pierce <= 0 then
                                    handle:Destroy()
                                    return
                                end
                                hit = true
                                break
                            end
                        end
                    end
                end
                if hit then
                    -- Continue loop; do not raycast this frame if we already consumed a pierce
                end
                end
            end
            local target = pos + direction * remaining
            local result = workspace:Raycast(pos, target - pos, rcParams)
            if result then
                -- Move to hit position
                local hitPos = result.Position
                -- Orient towards direction
                local cf = CFrame.new(hitPos, hitPos + direction)
                if params.orientationOffset then cf = cf * params.orientationOffset end
                cf = applySpin(cf)
                if inst:IsA("Model") then
                    inst:PivotTo(cf)
                else
                    (inst :: BasePart).CFrame = cf
                end

                -- Process hit
                local enemyModel = getHumanoidModelFromPart(result.Instance)
                if enemyModel then
                    local now = os.clock()
                    local cd = typeof(params.hitCooldownPerTarget) == "number" and params.hitCooldownPerTarget or 0.2
                    local last = lastHitTimes[enemyModel]
                    if (not last) or (now - last) >= cd then
                        lastHitTimes[enemyModel] = now
                        -- Apply damage if requested (legacy)
                        if damage > 0 then
                            local hum = enemyModel:FindFirstChildOfClass("Humanoid")
                            if hum then
                                Damage.Apply(hum, damage)
                            end
                        end
                        if params.onHit then
                            task.spawn(params.onHit, result.Instance, enemyModel)
                        end
                        -- During arming window, do not decrement pierce on raycast to avoid instant consumption at spawn
                        if elapsed > (((typeof(params.proximityDelay) == "number") and params.proximityDelay) or 0) then
                            pierce -= 1
                        end
                        if pierce <= 0 then
                            handle:Destroy()
                            return
                        end
                    end
                end

                -- Continue from just past hit
                local EPS = 0.05
                local travel = (hitPos - pos).Magnitude
                remaining -= travel + EPS
                pos = hitPos + direction * EPS
                currentPos = pos
            else
                -- No hit, move to target
                currentPos = target
                local cf = CFrame.new(currentPos, currentPos + direction)
                if params.orientationOffset then cf = cf * params.orientationOffset end
                cf = applySpin(cf)
                if inst:IsA("Model") then
                    inst:PivotTo(cf)
                else
                    (inst :: BasePart).CFrame = cf
                end
                remaining = 0
            end
        end
    end)

    return handle
end

-- Convenience: Fire using weapon stats module
-- weaponStats: Module with ProjectileSpeed, Pierce, Lifetime (optional defaults)
function Projectile.FireFromWeapon(args: {
    weaponStats: any,
    origin: Vector3,
    direction: Vector3,
    model: Instance?,
    owner: Player | Model | nil,
    damage: number?,
    ignore: {Instance}?,
    onHit: ((hitPart: BasePart, enemyModel: Model) -> ())?,
    orientationOffset: CFrame?,
    hitCooldownPerTarget: number?,
    spinPerSecond: number?,
    spinAxis: string?,
    contactRadius: number?,
    proximityDelay: number?,
})
    local ws = args.weaponStats or {}
    local speed = ws.ProjectileSpeed or 80
    local pierce = ws.Pierce or 1
    local lifetime = ws.Lifetime or 2
    return Projectile.Fire({
        origin = args.origin,
        direction = args.direction,
        speed = speed,
        lifetime = lifetime,
        pierce = pierce,
        damage = args.damage or 0,
        model = args.model,
        owner = args.owner,
        ignore = args.ignore,
        onHit = args.onHit,
        orientationOffset = args.orientationOffset,
        hitCooldownPerTarget = args.hitCooldownPerTarget,
        spinPerSecond = args.spinPerSecond,
        spinAxis = args.spinAxis,
        contactRadius = args.contactRadius,
        proximityDelay = args.proximityDelay,
    })
end

-- Example usage (server):
-- local Projectile = require(ReplicatedStorage.Scripts.Projectile)
-- local weaponStats = require(ReplicatedStorage.Items.Weapons.Kunai.Stats)
-- local origin = character.PrimaryPart.Position
-- local direction = (targetPosition - origin).Unit
-- Projectile.FireFromWeapon({
--     weaponStats = weaponStats,
--     origin = origin,
--     direction = direction,
--     owner = character,
--     -- model = ReplicatedStorage.Assets.Kunai, -- optional
--     damage = weaponStats.BaseDamage,
-- })

return Projectile
