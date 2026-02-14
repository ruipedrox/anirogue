-- Evolve.lua for Naruto_3 -> Naruto_4
-- Requirements: besides the main, 3 copies of the same char, 2 Evolve Shards, 3 Headband items

return {
    evolve_to = "Naruto_4",
    required_level = 1,
    cost = {
        Gold = 0,
    },
    copies_req = {
        { template = "Naruto_3", count = 3 }, -- 3 extra copies (excluding the main)
    },
    copies_mode = "excluding",
    materials_req = {
        { template = "EvolveShard", count = 2 },
        { template = "Headband", count = 3 },
    },
    carry_over_xp = true,
    potential_increase = 3,
    forbid_equipped_sacrifice = true,
}
