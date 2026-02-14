local Template = require(script.Parent.Parent.Template)

local items = {}

do
    local it = Template.New()
    it.Id = "evolve_shard"
    it.Category = "evolve"
    it.DisplayName = "Evolve Shard"
	it.Icon = "rbxassetid://79229534708781"
    it.Rarity = "raro"
    it.Description = "Small fragment used to evolve characters. Collect many to craft evolutions."
    it.Stackable = true
    it.SellPrice = 250
    it.Meta = { shardType = "generic" }
    items[it.Id] = it
end

do
    local it = Template.New()
    it.Id = "evolve_core"
    it.Category = "evolve"
    it.DisplayName = "Evolve Core"
	it.Icon = "rbxassetid://92749049461009"
    it.Rarity = "lendario"
    it.Description = "A powerful core required for high-tier evolutions. Valuable and rare."
    it.Stackable = true
    it.SellPrice = 1500
    it.Meta = { shardType = "core" }
    items[it.Id] = it
end

-- Specific evolve item: Wish Ball (used to evolve certain characters like Goku)
do
    local it = Template.New()
    it.Id = "wish_ball"
    it.Category = "evolve"
    it.DisplayName = "Wish Ball"
	it.Icon = "rbxassetid://114655951919645"
    it.Rarity = "epico"
    it.Description = "A mystical sphere used to grant special evolutions for certain characters."
    it.Stackable = true
    it.SellPrice = 600
    -- Per-character Evolve.lua modules declare the required items; keep Meta minimal here
    it.Meta = { }
    items[it.Id] = it
end

-- Specific evolve item: Headband
do
    local it = Template.New()
    it.Id = "headband"
    it.Category = "evolve"
    it.DisplayName = "Headband"
	it.Icon = "rbxassetid://97254110390104"
    it.Rarity = "epico"
    it.Description = "A headband every ninja has. Can be used to evolve certain characters."
    it.Stackable = true
    it.SellPrice = 600
    it.Meta = { }
    items[it.Id] = it
end

-- Specific evolve item: Soul Sword (referenced by Soul_City map)
do
    local it = Template.New()
    it.Id = "soul_sword"
    it.Category = "evolve"
    it.DisplayName = "Soul Sword"
    it.Icon = "rbxassetid://0"
    it.Rarity = "epico"
    it.Description = "A blade incarnation of the soul. Used to evolve characters with strong souls."
    it.Stackable = true
    it.SellPrice = 800
    it.Meta = { }
    items[it.Id] = it
end

return items
