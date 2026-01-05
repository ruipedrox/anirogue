-- DebugPretty.lua
-- Pequeno util para printar tabelas (uso em RunService)
local function pretty(value, indent, visited)
    indent = indent or 0
    visited = visited or {}
    local t = type(value)
    if t ~= "table" then
        if t == "string" then
            return string.format('%q', value)
        else
            return tostring(value)
        end
    end
    if visited[value] then return '<rec>' end
    visited[value] = true
    local pad = string.rep('  ', indent)
    local lines = {'{'}
    for k,v in pairs(value) do
        local keyStr
        if type(k) == 'string' and k:match('^%a[%w_]*$') then
            keyStr = k .. ' = '
        else
            keyStr = '['..pretty(k,0,visited)..'] = '
        end
        table.insert(lines, pad .. '  ' .. keyStr .. pretty(v, indent+1, visited) .. ',')
    end
    table.insert(lines, pad .. '}')
    return table.concat(lines, '\n')
end
return function(tbl) return pretty(tbl) end