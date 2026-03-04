-- Evolve.lua for Shikamaru_3 -> Shikamaru_4
-- Mirrors Naruto_3 requirements

return {
    evolve_to = "Shikamaru_4",
    required_level = 1,
    cost = { Gold = 1000 },
    copies_req = {
        { template = "Shikamaru_3", count = 3 }, -- 3 extra copies (excluding the main)
    },
    copies_mode = "including",
    materials_req = {
        { template = "EvolveShard", count = 2 },
        { template = "Headband", count = 3 },
    },
    carry_over_xp = true,
    potential_increase = 3,
    forbid_equipped_sacrifice = true,
}
