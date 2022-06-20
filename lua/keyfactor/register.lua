module = {}

module.register = {}

function module.register:new(database)
end

function module.register:read(params)
    -- params.name, params.index
end

function module.register:push(params)
    -- params.name... params.type?
end

--[[
    register has name (except special unnamed register) and stack history with random-access reading

    builtin registers
        default/unnamed register
        insert register
        regex/pattern captures 1-9
        entire regex/pattern match: 0

        search history? <- not uniform with other registers, it doesn't have multiple values for multiselections



--]]
