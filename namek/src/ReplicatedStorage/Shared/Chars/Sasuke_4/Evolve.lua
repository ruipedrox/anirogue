-- Evolve.lua for Sasuke_4 -> Sasuke_5
-- Requirements: besides the main, 3 copies of the same char, 2 Evolve Shards, 1 Evolve Core, 5 Headband items

return {
    evolve_to = "Sasuke_5",
    required_level = 1,
    cost = { Gold = 5000 },
    copies_req = { { template = "Sasuke_4", count = 3 } },
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
