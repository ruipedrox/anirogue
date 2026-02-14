-- Evolve.lua for XP4
-- 2x XP4 → 1x XP5

return {
	evolve_to = "XP5",
	required_level = 1,              -- Não precisa level
	cost = {
		Gold = 0,                    -- Sem custo em gold
	},
	copies_req = {
		{ template = "XP4", count = 3 }, -- 3 XP4 (incluindo a que evolui)
	},
	copies_mode = "including",
	materials_req = {},
	carry_over_xp = false,           -- Não carrega XP (reseta para level 1)
	forbid_equipped_sacrifice = true
}
