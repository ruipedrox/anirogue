-- RunService.lua (ModuleScript)
-- Constrói TeleportData para iniciar a run (mock) e imprime payload formatado.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptsFolder = ReplicatedStorage:WaitForChild("Scripts")

local ProfileService = require(ScriptsFolder:WaitForChild("ProfileService"))

local RunService = {}

function RunService:BuildTeleportPayload(player)
    local profile = ProfileService:Get(player)
    if not profile then return nil end
    local charInstances = {}
    for id, data in pairs(profile.Characters.Instances) do
        charInstances[id] = {
            TemplateName = data.TemplateName,
            Level = data.Level,
            XP = data.XP,
            Tier = data.Tier,
        }
    end
    -- Resolve equipped item templates from instance ids for Weapon/Armor/Ring
    local equippedInstanceIds = (profile.Items and profile.Items.Equipped) or {}
    local function resolveTemplateFor(categoryPlural, instId)
        if not instId or instId == "" then return nil end
        local owned = profile.Items and profile.Items.Owned
        local cat = owned and owned[categoryPlural]
        local instances = cat and cat.Instances
        local entry = instances and instances[instId]
        if entry and entry.Template then return entry.Template end
        -- Fallback: sometimes Equipped holds the template name (pre-migration)
        return instId
    end
    local function resolveLevelFor(categoryPlural, instId)
        if not instId or instId == "" then return 1 end
        local owned = profile.Items and profile.Items.Owned
        local cat = owned and owned[categoryPlural]
        local instances = cat and cat.Instances
        local entry = instances and instances[instId]
        return (entry and tonumber(entry.Level)) or 1
    end
    local function resolveQualityFor(categoryPlural, instId)
        if not instId or instId == "" then return nil end
        local owned = profile.Items and profile.Items.Owned
        local cat = owned and owned[categoryPlural]
        local instances = cat and cat.Instances
        local entry = instances and instances[instId]
        return entry and entry.Quality or nil
    end
    local equippedTemplates = {
        Weapon = resolveTemplateFor("Weapons", equippedInstanceIds and equippedInstanceIds.Weapon),
        Armor = resolveTemplateFor("Armors", equippedInstanceIds and equippedInstanceIds.Armor),
        Ring = resolveTemplateFor("Rings", equippedInstanceIds and equippedInstanceIds.Ring),
    }
    local equippedLevels = {
        Weapon = resolveLevelFor("Weapons", equippedInstanceIds and equippedInstanceIds.Weapon),
        Armor = resolveLevelFor("Armors", equippedInstanceIds and equippedInstanceIds.Armor),
        Ring = resolveLevelFor("Rings", equippedInstanceIds and equippedInstanceIds.Ring),
    }
    local equippedQualities = {
        Weapon = resolveQualityFor("Weapons", equippedInstanceIds and equippedInstanceIds.Weapon),
        Armor = resolveQualityFor("Armors", equippedInstanceIds and equippedInstanceIds.Armor),
        Ring = resolveQualityFor("Rings", equippedInstanceIds and equippedInstanceIds.Ring),
    }
    local payload = {
        Version = 1,
        Account = { Level = profile.Account.Level },
        Characters = {
            Equipped = profile.Characters.EquippedOrder,
            Instances = charInstances,
        },
        Items = {
            Equipped = profile.Items.Equipped,
            EquippedTemplates = equippedTemplates,
            EquippedItemLevels = equippedLevels,
            EquippedItemQualities = equippedQualities,
        },
        Seed = os.time(),
    }
    -- Compatibility: also expose character data at top-level for run place consumer
    -- vila/ReplicatedStorage/Scripts/CharacterInventory.lua expects these keys
    payload.CharacterInstances = charInstances
    payload.Equipped = profile.Characters.EquippedOrder
    return payload
end

function RunService:StartRun(player)
    local payload = self:BuildTeleportPayload(player)
    if not payload then return false, "NoProfile" end
    print("[RunService] StartRun payload ->", player.Name)
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    if shared and shared:FindFirstChild("DebugPretty") then
        local ok, pretty = pcall(require, shared.DebugPretty)
        if ok and type(pretty) == "function" then
            print(pretty(payload))
        end
    end
    return true
end

print("[RunService Module] Loaded")
return RunService
