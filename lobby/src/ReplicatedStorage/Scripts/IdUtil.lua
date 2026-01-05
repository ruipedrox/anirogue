-- IdUtil.lua
-- Geração de IDs únicos para instâncias de personagens (UID por personagem).

local HttpService = game:GetService("HttpService")

local IdUtil = {}

function IdUtil:GenerateInstanceId(templateName)
    -- GUID compacto sem chaves
    local guid = HttpService:GenerateGUID(false)
    -- Pode encurtar (ex: pegar primeiros 8 chars) se quiseres, mas manter completo reduz colisões
    local short = string.sub(guid, 1, 8)
    return string.format("%s_%s", templateName, short)
end

return IdUtil