-- Evolve.lua for Sanji_3 -> Sanji_4
-- Requirements copied from Zoro

return {
    evolve_to = "Sanji_4",
    required_level = 1,
    cost = { Gold = 5000 },
    copies_req = { { template = "Sanji_3", count = 3 } },
    copies_mode = "including",
    materials_req = {
        { template = "EvolveShard", count = 5 },
    },
    carry_over_xp = true,
    potential_increase = 3,
    forbid_equipped_sacrifice = true,
}
