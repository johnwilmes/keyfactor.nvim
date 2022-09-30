local module = {}

do
    local action_mt = {}
    action_mt.__index = action_mt

    function action_mt:with(bindings)
        local with = utils.table.set_default(self, "_with")
        with = vim.tbl_extend(with, {[#with+1]=bindings})
        return action(self._callable, self._fill, with)
    end

    function action_mt:__exec(context)
        local params = context.params
        if self._with then
            for key, value in pairs(self._with) do
                -- if key is number
                --      if value is callable or respects binding protocol then evaluate it with
                --          vim.tbl_extend("force", context, {params=params})
                --          params = result
                --      elseif value is table recurse into it
                --          params result
                -- elseif key is string
                --      split key on __ and proceed to case when key is table
                -- elseif key is table
                --      params[key[1]][key[2]]etc = value
                --      
            end
        end
        if self.fill then
            -- fill fields of params listed in fill
        end
        self.callable(params)
        return true
    end

    module.action = function(callable, fill, with)
        return setmetatable({_callable=callable, _fill=fill, _with=with}, action_mt)
    end
end

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
