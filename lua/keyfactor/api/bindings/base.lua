local module = {}

do
    --[[ example usage:
            action(function(mode, params) do something end):with{register=blah}
    ]]
    local bound_action_mt = {}
    function bound_action_mt:__call(mode, params)
        params = vim.tbl_extend("force", self._default_params, params or {})
        return self._wrapped(mode, params)
    end

    local unbound_action_mt = {}

    local function resolve_params(key, outer, inner)
        -- TODO
    end

    function unbound_action_mt:__bind(key, params)
        if self._with then
            params = resolve_params(key, params, self._with)
        end

        local bound_action = {_default_params=params, _wrapped=self._wrapped}
        return setmetatable(bound_action, bound_action_mt)
    end

    function unbound_action_mt:__call(unbound_params)
        return self:with(unbound_params)
    end

    function unbound_action_mt:with(unbound_params)
        local with = self._with or {}
        with = vim.tbl_extend("force", with, {[#with+1]=unbound_params})
        local obj = vim.tbl_extend(self, {_with=with})
        return setmetatable(obj, unbound_action_mt)
    end

    function unbound_action_mt:__index(key)
        local value
        if self._index then
            value = self._index[key]
        end
        return value or rawget(unbound_action_mt, key)
    end

    -- [[ produces an UNBOUND action ]]
    function module.action(callable, obj)
        obj = obj or {}
        obj = {
            _wrapped=callable,
            _with=obj.with,
            _index=obj.index
        }
        return setmetatable(obj, unbound_action_mt) 
    end
end

function module.is_bindable(obj)
    if type(obj)=="function" then
        return true
    elseif type(obj)=="table" then
        local mt = getmetatable(obj)
        if mt then
            local bind =  rawget(mt, "__bind") or rawget(mt, "__call")
            return type(bind)=="function"
        end
    end
    return false
end

local function resolve_map_recursively(bindings, key, params, result)
    if module.is_bindable(binding) then
        local actions = module.bind(binding, key, params)
        --[[
            actions is supposed to be a callable, or list of callables
            we silently ignore anything not callable
        ]]
        if utils.is_callable(a) then
            result[#result+1]=a
        elseif type(actions)=="table" then
            for _,a in ipairs(actions) do
                if utils.is_callable(a) then
                    result[#result+1]=a
                end
            end
        end
    elseif type(binding)=="table" then
        for idx,value in ipairs(binding) do
            local success, msg = pcall(resolve_map_recursively, value, key, params, result)
            if not success then
                error(msg..", binding index "..idx, 0)
            end
        end
        for _,name in ipairs(key.names) do
            if binding[name]~=nil then
                local success, msg = pcall(resolve_map_recursively, value, key, params, result)
                if not success then
                    error(msg.."; binding key "..idx, 0)
                end
            end
        end
    else
        error("table or bindable value expected", 0)
    end
    return result
end

--[[
--   bindings is table of bindings
--      bindings can have list-like part, which is recursed into
--      key-value part is triggered if key appears on list of names of triggering press
--   key is record of the triggering key press
--   params (optional) is table of param values
--
--   returns list of param-bound actions
--]]
function module.resolve_map(bindings, key, params)
    --[[first, resolve list-like part. then, resolve any key=value pairs where key appears on
    config.key
        -if value is bindable, resolve it and append result to results
        -otherwise value should be table, recurse into it
    ]]
    local result = {}
    params = params or {}
    resolve_map_recursively(bindings, key, params, result)
    return result
end

--[[
    binding is a binding (callable, or with __bind in the metatable)

    returns the result of calling binding in the appropriate form, with key and params
--]]
function module.bind(binding, key, params)
    local result
    if type(obj)=="function" then
        result = obj(key, params)
    elseif type(obj)=="table" then
        local mt = getmetatable(obj) or {}
        local callable = rawget(mt, "__bind") or rawget(mt, "__call")
        if callable then
            result = callable(obj, key, params)
        end
    end
    return result
end

--[[ map returns a binding which resolves to a list of actions via resolve_map ]]
do
    local map_mt = {}
    function map_mt:__bind(key, params)
        return module.resolve_map(self._bindings, key, params)
    end

    function module.map(bindings)
        return setmetatable({_bindings=bindings}, map_mt)
    end
end

do
    local outer_mt = {}

    function outer_mt:__index(k)
        local index = utils.list.concatenate(self._index, {k})
        return setmetatable({_index=index}, outer_mt)
    end

    function outer_mt:__bind(_, params)
        local result = params
        for _,k in ipairs(self._index) do
            result = (result or {})[k]
        end
        return result
    end

    module.outer = setmetatable({_index={}}, outer_mt)
end

return module
