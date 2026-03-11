-- Evolve.lua for Vegeta_3 -> Vegeta_4 (copied from Goku_3 evolve)
-- Requirements: besides the main, 3 copies of the same char and materials
return {
    evolve_to = "Vegeta_4",
    required_level = 1,
    cost = { Gold = 5000 },
    copies_req = { { template = "Vegeta_3", count = 3 } },
    copies_mode = "including",
    materials_req = {
        { template = "EvolveShard", count = 2 },
        { template = "WishBall", count = 3 },
    },
    carry_over_xp = true,
    potential_increase = 3,
    forbid_equipped_sacrifice = true,
}
