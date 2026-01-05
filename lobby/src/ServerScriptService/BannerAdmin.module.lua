-- BannerAdmin.module.lua
-- Small helper for admin-only banner updates.

local BannerManager = require(script.Parent:WaitForChild("BannerManager.module"))

local Admin = {}

-- Replace these with your studio/admin UserIds
local WHITELIST = {
    [12345678] = true, -- example
}

function Admin:IsAdmin(userId)
    return WHITELIST[userId] == true
end

function Admin:UpdateBannerFromAdmin(player, banner)
    if not player or not player.UserId then return false, "no player" end
    if not self:IsAdmin(player.UserId) then
        return false, "not authorized"
    end
    BannerManager:Save(banner)
    BannerManager:Broadcast(banner)
    return true
end

return Admin
