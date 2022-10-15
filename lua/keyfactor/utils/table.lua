local module = {}

function module.reverse(t)
    local r = {}
    for k,v in pairs(t) do
        r[v] = k
    end
    return r
end

return module
