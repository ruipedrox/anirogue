-- Evolve.lua for Ichigo_3 -> Ichigo_4 (Bleach)
-- Requirements: besides the main, 3 copies of the same char, 2 Evolve Shards, 3 SoulSword items

return {
    evolve_to = "Ichigo_4",
    required_level = 1,
    cost = { Gold = 5000 },
    copies_req = { { template = "Ichigo_3", count = 3 } },
    copies_mode = "including",
    materials_req = {
        { template = "EvolveShard", count = 2 },
        { template = "SoulSword", count = 3 },
    },
    carry_over_xp = true,
    potential_increase = 3,
    forbid_equipped_sacrifice = true,
}
