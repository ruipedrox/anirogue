local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemsFolder = ReplicatedStorage.Shared:WaitForChild("Items")

-- Dynamic item registry: automatically registers items under Weapons/Armors/Rings
-- IDs are the folder names (e.g., Kunai, ClothArmor, IronRing)
local Registry = {
    Weapons = {},
    Armors = {},
    Rings = {},
}

local function populate(bucketName)
    local container = ItemsFolder:FindFirstChild(bucketName)
    if not container then return end
    local bucket = Registry[bucketName]
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Folder") and child:FindFirstChild("Stats") then
            bucket[child.Name] = child.Stats
        end
    end
end

populate("Weapons")
populate("Armors")
populate("Rings")

local singularToPlural = {
    Weapon = "Weapons",
    Armor = "Armors",
    Ring = "Rings",
}

function Registry:GetModule(itemType, itemId)
    local group = singularToPlural[itemType] or itemType
    local bucket = self[group]
    if not bucket then return nil end
    return bucket[itemId]
end

-- Optional helper: find the ID for a given ModuleScript
function Registry:GetIdForModule(moduleScript, itemType)
    if not moduleScript or typeof(moduleScript) ~= "Instance" or not moduleScript:IsA("ModuleScript") then
        return nil
    end
    local searchGroups = {}
    if itemType then
        table.insert(searchGroups, singularToPlural[itemType] or itemType)
    else
        for groupName, _ in pairs(self) do
            if type(self[groupName]) == "table" then
                table.insert(searchGroups, groupName)
            end
        end
    end
    for _, groupName in ipairs(searchGroups) do
        local bucket = self[groupName]
        if type(bucket) == "table" then
            for id, mod in pairs(bucket) do
                if mod == moduleScript then
                    return id
                end
            end
        end
    end
    -- Fallback: try to use the parent name (folder) as ID
    if moduleScript.Parent then
        return moduleScript.Parent.Name
    end
    return nil
end

return Registry
