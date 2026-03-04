-- Evolve.lua for Goku_3 -> Goku_4 (Dragon Ball)
-- Requirements: besides the main, 3 copies of the same char, 2 Evolve Shards, 3 WishBall items
return {
    evolve_to = "Goku_4",
    required_level = 1,
    cost = { Gold = 1000 },
    copies_req = { { template = "Goku_3", count = 3 } },
    copies_mode = "including",
    materials_req = {
        { template = "EvolveShard", count = 2 },
        { template = "WishBall", count = 3 },
    },
    carry_over_xp = true,
    potential_increase = 3,
    forbid_equipped_sacrifice = true,
}
