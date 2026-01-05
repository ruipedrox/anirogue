-- Shared/Drops/Template.lua
-- Contract and validator for drop items

local Template = {}

function Template.New()
    return {
        Id = "",               -- unique id (e.g., "xp_1")
        Category = "misc",     -- e.g., "xp", "evolve", "special"
        DisplayName = "",      -- UI name
        Icon = "rbxassetid://0",
        Rarity = "comum",      -- optional: reuse rarity keys
        Stackable = true,       -- stackable quantity vs unique instance
        CanEvolve = false,      -- whether this item can be evolved/combined to a higher tier
        SellPrice = 0,          -- how much gold the item sells for
        Meta = {},             -- free-form metadata per item type
    }
end

function Template.Validate(item)
    if type(item) ~= "table" then return false, "item is not a table" end
    if type(item.Id) ~= "string" or item.Id == "" then return false, "Id required" end
    if type(item.Category) ~= "string" or item.Category == "" then return false, "Category required" end
    if type(item.DisplayName) ~= "string" or item.DisplayName == "" then return false, "DisplayName required" end
    if type(item.Icon) ~= "string" then return false, "Icon (string) required" end
    if item.Stackable ~= nil and type(item.Stackable) ~= "boolean" then return false, "Stackable must be boolean" end
    if item.CanEvolve ~= nil and type(item.CanEvolve) ~= "boolean" then return false, "CanEvolve must be boolean" end
    if item.SellPrice ~= nil and type(item.SellPrice) ~= "number" then return false, "SellPrice must be number" end
    return true
end

return Template
