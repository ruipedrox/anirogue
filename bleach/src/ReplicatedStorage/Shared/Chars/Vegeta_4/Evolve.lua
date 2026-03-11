-- Evolve.lua for Vegeta_4 -> Vegeta_5 (copied/adapted from Goku_3 evolve)
return {
    evolve_to = "Vegeta_5",
    required_level = 1,
    cost = { Gold = 25000 },
    copies_req = { { template = "Vegeta_4", count = 3 } },
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
