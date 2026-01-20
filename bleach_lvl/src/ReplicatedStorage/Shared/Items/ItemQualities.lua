-- ItemQualities.lua
-- Define multiplicadores percentuais para qualidades de itens.
-- Ordem progressiva: rusty < worn < new < polished < perfect < artifact
-- Cada passo +3% cumulativo (rusty = 0%).

local Qualities = {
    rusty = 0.00,
    worn = 0.03,
    new = 0.06,
    polished = 0.09,
    perfect = 0.12,
    artifact = 0.15,
}

-- Optional color mapping (UI usage)
Qualities.Colors = {
    rusty = Color3.fromRGB(130, 80, 60),
    worn = Color3.fromRGB(145, 110, 85),
    new = Color3.fromRGB(170, 170, 170),
    polished = Color3.fromRGB(80, 170, 220),
    perfect = Color3.fromRGB(90, 210, 120),
    artifact = Color3.fromRGB(230, 180, 60),
}

return Qualities