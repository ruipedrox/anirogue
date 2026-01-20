local Template = require(script.Parent.Parent.Template)

local items = {}

do
    local it = Template.New()
    it.Id = "xp_1"
    it.Category = "xp"
    it.DisplayName = "XP I"
    it.Icon = "rbxassetid://0"
    it.Rarity = "comum"
    it.Stackable = true
    it.CanEvolve = true
    it.SellPrice = 25
    it.Meta = { xpValue = 100 }
    items[it.Id] = it
end

do
    local it = Template.New()
    it.Id = "xp_2"
    it.Category = "xp"
    it.DisplayName = "XP II"
    it.Icon = "rbxassetid://0"
    it.Rarity = "raro"
    it.Stackable = true
    it.CanEvolve = true
    it.SellPrice = 100
    it.Meta = { xpValue = 400}
    items[it.Id] = it
end

do
    local it = Template.New()
    it.Id = "xp_3"
    it.Category = "xp"
    it.DisplayName = "XP III"
    it.Icon = "rbxassetid://0"
    it.Rarity = "epico"
    it.Stackable = true
    it.CanEvolve = true
    it.SellPrice = 350
    it.Meta = { xpValue = 1500 }
    items[it.Id] = it
end

do
    local it = Template.New()
    it.Id = "xp_4"
    it.Category = "xp"
    it.DisplayName = "XP IV"
    it.Icon = "rbxassetid://0"
    it.Rarity = "lendario"
    it.Stackable = true
    it.CanEvolve = true
    it.SellPrice = 1200
    it.Meta = { xpValue = 5000 }
    items[it.Id] = it
end

do
    local it = Template.New()
    it.Id = "xp_5"
    it.Category = "xp"
    it.DisplayName = "XP V"
    it.Icon = "rbxassetid://0"
    it.Rarity = "mitico"
    it.Stackable = true
    it.CanEvolve = false
    it.SellPrice = 4000
    it.Meta = { xpValue = 20000 }
    items[it.Id] = it
end

return items

