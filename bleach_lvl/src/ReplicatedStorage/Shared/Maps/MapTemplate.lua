-- MapTemplate.lua
-- Template and validator for gameplay maps.
-- Copy this structure into each map folder as a `Map.lua` that returns a table with all required fields.

local Template = {}

-- Create a new empty map config with sensible defaults
function Template.New()
    return {
        -- Map type: 'gameplay' (default) or 'hub'.
        -- 'hub' maps only require PlaceId (teleport destination after runs).
        Type = "gameplay",
        -- Unique identifier used internally (usually the folder name)
        Id = "",
        -- Human-readable name for UI
        DisplayName = "",
        -- Optional: explicit order for UI lists (lower first). If nil, UI may sort alphabetically.
        SortOrder = nil,
        -- Roblox PlaceId for the gameplay place of this map
        PlaceId = 0,
        -- UI images
        PreviewImage = "rbxassetid://0",     -- shown in map selection
        BackgroundImage = "rbxassetid://0",  -- background for the selection panel

        -- Three levels (1..3). Each level must have a BossImage and a WaveKey.
        -- WaveKey is a simple string you will pass to the gameplay/waves script to pick the correct wave set.
        Levels = {
            { Level = 1, BossImage = "rbxassetid://0", WaveKey = "" },
            { Level = 2, BossImage = "rbxassetid://0", WaveKey = "" },
            { Level = 3, BossImage = "rbxassetid://0", WaveKey = "" },
        },

        -- Optional extras you may want later (uncomment as needed):
        -- MusicId = 0,
        -- RecommendedPower = { [1] = 0, [2] = 0, [3] = 0 },
        -- RewardsPreview = { Coins = 0, Gems = 0 },
        -- Drops = {
        --     -- First clear rewards; if PerLevel=true, applies once per each Level (1..3)
        --     FirstClear = { Gems = 0, Gold = 0, PerLevel = true },
        --     -- Repeat rewards for any subsequent clear
        --     Repeat = { Gems = 0, Gold = 0 },
        --     -- Items granted every run regardless of first/repeat
        --     GuaranteedItemsPerRun = {
        --         -- { Id = "headband", Quantity = 2 },
        --     },
        -- },
    }
end

-- Validate a map table and return (ok:boolean, err?:string)
function Template.Validate(map)
    if type(map) ~= "table" then return false, "map is not a table" end
    local mapType = tostring(map.Type or "gameplay"):lower()
    -- Hub map: only needs PlaceId (and Id). DisplayName optional.
    if mapType == "hub" then
        if type(map.Id) ~= "string" or map.Id == "" then return false, "Id (string) required for hub maps" end
        if type(map.PlaceId) ~= "number" or map.PlaceId <= 0 then return false, "PlaceId (number) required for hub maps" end
        -- No further requirements for hub
        return true
    end
    -- Gameplay map: requires full UI assets and exactly 3 levels
    if type(map.Id) ~= "string" or map.Id == "" then return false, "Id (string) required" end
    if type(map.DisplayName) ~= "string" or map.DisplayName == "" then return false, "DisplayName (string) required" end
    if type(map.PlaceId) ~= "number" or map.PlaceId <= 0 then return false, "PlaceId (number) required" end
    if type(map.PreviewImage) ~= "string" then return false, "PreviewImage (string) required" end
    if type(map.BackgroundImage) ~= "string" then return false, "BackgroundImage (string) required" end
    if type(map.Levels) ~= "table" or #map.Levels ~= 3 then return false, "Levels must be an array of 3 entries" end
    for i = 1, 3 do
        local L = map.Levels[i]
        if type(L) ~= "table" then return false, ("Levels[%d] must be a table"):format(i) end
        if tonumber(L.Level) ~= i then return false, ("Levels[%d].Level must be %d"):format(i,i) end
        if type(L.BossImage) ~= "string" or L.BossImage == "" then return false, ("Levels[%d].BossImage (string) required"):format(i) end
        if type(L.WaveKey) ~= "string" or L.WaveKey == "" then return false, ("Levels[%d].WaveKey (string) required"):format(i) end
    end
    return true
end

return Template
