-- DevSummonTest.server.lua
-- Quick developer script to sample SummonModule probabilities and print empirical rates.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SummonModule = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("SummonModule"))

local Scripts = ReplicatedStorage:FindFirstChild("Scripts")
local CharacterCatalog = nil
pcall(function() if Scripts and Scripts:FindFirstChild("CharacterCatalog") then CharacterCatalog = require(Scripts:FindFirstChild("CharacterCatalog")) end end)

local catalog = {}
if CharacterCatalog and CharacterCatalog.GetAllMap then
    local all = CharacterCatalog:GetAllMap()
    for tpl, v in pairs(all) do
        table.insert(catalog, { id = tpl, stars = tonumber(v.stars) or 3 })
    end
else
    -- synthetic catalog: 10 entries per rarity
    for i=1,10 do table.insert(catalog, { id = "s5_"..i, stars = 5 }) end
    for i=1,10 do table.insert(catalog, { id = "s4_"..i, stars = 4 }) end
    for i=1,80 do table.insert(catalog, { id = "s3_"..i, stars = 3 }) end
end

local trials = 10000
local counts = { [5]=0, [4]=0, [3]=0 }
for i=1,trials do
    local _, rarity = SummonModule.SummonOnce(catalog)
    counts[rarity] = (counts[rarity] or 0) + 1
end

print(string.format("[DevSummonTest] Trials=%d -> 5*: %.4f%%, 4*: %.4f%%, 3*: %.4f%%",
    trials,
    (counts[5] / trials) * 100,
    (counts[4] / trials) * 100,
    (counts[3] / trials) * 100))

-- End of dev test
