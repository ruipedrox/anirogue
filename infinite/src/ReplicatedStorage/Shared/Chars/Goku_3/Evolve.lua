-- Evolve.lua (exemplo para Goku_3)
-- Este arquivo descreve como uma instância de Goku_3 pode evoluir para Goku_4.
-- Formato pensado para ser simples, escalável e fácil de copiar para outros personagens.
-- Notas:
--  * "count" em copies_req inclui a própria instância que vai evoluir (modo "including").
--    Ou seja: count = 3 -> 1 (que evolui) + 2 extras sacrificadas.
--  * Se no futuro quiser dizer que são 3 ALÉM da principal, poderias introduzir copies_mode = "extra".
--  * materials_req é opcional. Usa IDs livres; poderás ter um MaterialCatalog para meta (ícone, raridade, etc.).
--  * carry_over_xp = true mantém nível e XP (ajusta Fraction conforme teu cálculo). False resetaria XP.
--  * Podes adicionar campos extras como: fx = { sound="rbxassetid://...", particle="TransformFX" }

return {
    evolve_to = "Goku_4",          -- Template destino (nome da pasta alvo)
    required_level = 30,             -- Nível mínimo da instância Goku_3
    cost = {                         -- Custos em moedas genéricas (ajusta conforme teu Profile.Account)
        Gold = 1000,
        -- Gems = 50,
    },
    copies_req = {                   -- Lista de requisitos de cópias (pode haver mais de um template no futuro)
        { template = "Goku_3", count = 3 },
    },
    copies_mode = "including",      -- "including" (o count inclui a própria) | "extra" (seriam 3 além da principal)
    materials_req = {                -- Materiais específicos adicionais (opcional)
        -- wish_balls = 3,
        -- monkey_staff = 2,
    },
    carry_over_xp = true,            -- Mantém XP/Level ao evoluir
    forbid_equipped_sacrifice = true -- Impede sacrificar cópias que estejam equipadas (se implementares no server)
}
