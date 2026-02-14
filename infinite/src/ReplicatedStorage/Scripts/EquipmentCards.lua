-- Deprecated EquipmentCards module: logic migrated to per-item Cards.lua modules (e.g., Items/Weapons/Kunai/Cards.lua).
-- Keeping this stub so existing requires do not break; returns empty.
local EquipmentCards = {}
function EquipmentCards:GetCardsForPlayer()
    return {}
end
return EquipmentCards
