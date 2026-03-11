-- Evolve.lua for Sasuke_4 -> Sasuke_5
-- Requirements: besides the main, 3 copies of the same char, 2 Evolve Shards, 1 Evolve Core, 5 Headband items

return {
    evolve_to = "Luffy_5",
    required_level = 1,
    cost = { Gold = 25000 },
    copies_req = { { template = "Luffy_4", count = 3 } },
    copies_mode = "including",
    materials_req = {
        { template = "EvolveShard", count = 5 },
        { template = "EvolveCore", count = 3 },
    },
    carry_over_xp = true,
    potential_increase = 3,
    forbid_equipped_sacrifice = true,
}
