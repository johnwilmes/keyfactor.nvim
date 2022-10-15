local module = {}

function module.lstrip(s)
    return s:match("^%s*(.-)$")
end

function module.rstrip(s)
    return s:match("^(.-)%s*$")
end

function module.strip(s)
    return s:match("^%s*(.-)%s*$")
end

function module.split_keycodes(s)
    local i = 1
    local a = 0
    local b = 0
    local result = {}
    while i <= #s do
        if a and a < i then
            a,b = s:find('<%w[%w%-]->', i)
        end
        if a==i then
            table.insert(result, s:sub(a,b))
            i = b+1
        else
            table.insert(result, s:sub(i,i))
            i = i+1
        end
    end
    return result
end

return module
