-- Evolve.lua for Naruto_4 -> Naruto_5
-- Requirements: besides the main, 3 copies of the same char, 2 Evolve Shards, 1 Evolve Core, 5 Headband items

return {
    evolve_to = "Naruto_5",
    required_level = 1,
    cost = { Gold = 5000 },
    copies_req = {
        { template = "Naruto_4", count = 3 }, -- 3 extra copies (excluding the main)
    },
    copies_mode = "including",
    materials_req = {
        { template = "EvolveShard", count = 2 },
        { template = "EvolveCore", count = 1 },
        { template = "Headband", count = 5 },
    },
    carry_over_xp = true,
    potential_increase = 3,
    forbid_equipped_sacrifice = true,
}
