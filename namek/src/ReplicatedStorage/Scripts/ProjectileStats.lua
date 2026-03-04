-- ProjectileStats.lua
-- Central registry for projectile-affecting modifiers (auras, debuffs, buffs)
-- Other abilities can register an aura that affects projectile speed.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ProjectileStats = {}

-- Active auras keyed by player.UserId -> { player = Player, range, minSlow, maxSlow }
local ActiveAuras = {}

-- Register or update an aura for a player
function ProjectileStats.RegisterAura(player, params)
    if not player then return end
    -- Accept either a Player instance or a Character Model (resolve to Player.UserId).
    local uid = nil
    if typeof(player) == "Instance" then
        if player:IsA("Player") then
            uid = player.UserId
        elseif player:IsA("Model") then
            local p = Players:GetPlayerFromCharacter(player)
            if p then uid = p.UserId end
        end
    end
    if not uid then
        -- Can't key this aura without a player UserId; ignore registration.
        return
    end
    ActiveAuras[uid] = {
        player = player,
        range = params.range or 0,
        minSlow = params.minSlow or 0,
        maxSlow = params.maxSlow or 0,
    }
end

-- Unregister an aura
function ProjectileStats.UnregisterAura(player)
    if not player then return end
    ActiveAuras[player.UserId] = nil
end

-- Get the strongest slow percent (0..1) at a given world position.
-- Optional second argument `ignorePlayer` can be a Player or Character Model to exclude from consideration.
function ProjectileStats.GetBestSlowAtPosition(position, ignorePlayer)
    local best = 0
    local ignoreUserId = nil
    if ignorePlayer then
        if typeof(ignorePlayer) == "Instance" then
            if ignorePlayer:IsA("Player") then
                ignoreUserId = ignorePlayer.UserId
            elseif ignorePlayer:IsA("Model") then
                local p = Players:GetPlayerFromCharacter(ignorePlayer)
                if p then ignoreUserId = p.UserId end
            end
        end
    end

    for _, aura in pairs(ActiveAuras) do
        local owner = aura.player
        -- Resolve owner to a character model for distance checks
        local ownerPlayer = nil
        local char = nil
        if owner then
            if typeof(owner) == "Instance" then
                if owner:IsA("Player") then
                    ownerPlayer = owner
                    char = owner.Character
                elseif owner:IsA("Model") then
                    -- owner may be a character model
                    char = owner
                    local p = Players:GetPlayerFromCharacter(owner)
                    if p then ownerPlayer = p end
                end
            end
        end

        -- Skip if this aura belongs to the ignored player
        if ownerPlayer and ignoreUserId and ownerPlayer.UserId == ignoreUserId then
            -- skip
        else
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp and aura.range and aura.range > 0 then
                local dist = (hrp.Position - position).Magnitude
                if dist <= aura.range then
                    local ratio = math.clamp(dist / aura.range, 0, 1)
                    local slowPercent = aura.maxSlow - (ratio * (aura.maxSlow - aura.minSlow))
                    if slowPercent > best then best = slowPercent end
                end
            end
        end
    end
    return best
end

return ProjectileStats
