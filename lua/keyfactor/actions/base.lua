local module = {}


-----------------------------


function module.execute(actions, params)
    local context = -- TODO retrieve context
    local result = false

    if params then
        -- TODO make sure this kind of extend does what we want
        context = vim.tbl_deep_extend("force", context, {params=params})
    end

    for _, a in ipairs(actions) do
        local exec = rawget(getmetatable(a) or {}, "__exec")
        if exec then
            result = result or exec(a, context)
        elseif utils.is_callable(a) then
            result = result or a(params)
        elseif type(a)=="table" then
            result = result or module.execute(a, params)
        end
    end
end

return module
