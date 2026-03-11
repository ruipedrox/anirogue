-- Evolve.lua for XP3
-- 3x XP3 → 1x XP4

return {
	evolve_to = "XP4",
	required_level = 1,              -- Não precisa level
	cost = {
		Gold = 5000,                 -- 3★ -> 4★ gold cost
	},
	copies_req = {
		{ template = "XP3", count = 3 }, -- 3 XP3 (incluindo a que evolui)
	},
	copies_mode = "including",
	materials_req = {},
	carry_over_xp = true,            -- Carrega XP para o novo personagem
	potential_increase = 3,          -- aumenta potencial/tier em +3 (capped)
	forbid_equipped_sacrifice = true
}
