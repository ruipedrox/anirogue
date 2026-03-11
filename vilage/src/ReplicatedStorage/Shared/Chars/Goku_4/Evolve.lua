-- Evolve.lua for Goku_4 -> Goku_5 (Dragon Ball)
-- Requirements: besides the main, 3 copies of the same char, 2 Evolve Shards, 1 Evolve Core, 5 WishBall items

return {
    evolve_to = "Goku_5",
    required_level = 1,
    cost = { Gold = 25000 },
    copies_req = { { template = "Goku_4", count = 3 } },
    copies_mode = "including",
    materials_req = {
        { template = "EvolveShard", count = 2 },
        { template = "EvolveCore", count = 1 },
        { template = "WishBall", count = 5 },
    },
    carry_over_xp = true,
    potential_increase = 3,
    forbid_equipped_sacrifice = true,
}
