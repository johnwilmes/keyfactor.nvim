local module = {}

--[[ TODO module.resolve, resolve_map, and flatten_params all fail to properly handle
--circular table references ]]

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

--[[
    binding is a binding (callable, or with __bind in the metatable)

    returns the result of calling binding in the appropriate form, with key and params
--]]
function module.bind(binding, params)
    local result
    if type(obj)=="function" then
        result = obj(params)
    elseif type(obj)=="table" then
        local mt = getmetatable(obj) or {}
        local callable = rawget(mt, "__bind") or rawget(mt, "__call")
        if type(callable)=="function" then
            result = callable(obj, params)
        end
    end
    return result
end

--[[ if target is bindable, return bound value
--   elseif target is NOT table then
--      return target
--  else
--      recurse into target and return new table with same keys of target, and values replaced by
--      resolved values
--  end
--]]  
function module.resolve(target, params)
    if base.is_bindable(target) then
        return base.bind(target, params)
    elseif type(target)=="table" then
        return utils.table.map_values(target, module.resolve)
    else
        return binding
    end
end

local function resolve_map(bindings, params, result, limit)
    if limit and #result >= limit then return result end
    if module.is_bindable(binding) then
        local actions = module.bind(binding, params)
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
                    if limit and #result>=limit then return result end
                end
            end
        end
    elseif type(binding)=="table" then
        for idx,value in ipairs(binding) do
            local success, msg = pcall(resolve_map_recursively, value, params, result)
            if not success then
                error(msg..", binding index "..idx, 0)
            end
            if limit and #result >= limit then return result end
        end
        if type(params.key)=="table" and type(params.key.names)=="table" then
            for _,name in ipairs(params.key.names) do
                if binding[name]~=nil then
                    local success, msg = pcall(resolve_map_recursively, value, params, result)
                    if not success then
                        error(msg.."; binding key "..idx, 0)
                    end
                    if limit and #result >= limit then return result end
                end
            end
        end
    else
        error("table or bindable value expected", 0)
    end
    return result
end

--[[
    Recurse into list-like part of {params}, until we hit a string key
    insert into result as (ordered) list of encounters {key=string_key, value=value}

    silently ignore any thing that is not string-key under any number of list-indices
]]
local function flatten_params(params, result)
    if type(params)~="table" then return end

    for _,p in ipairs(params) do
        if type(p)=="table" then
            flatten_params(p, result)
        end
    end
    for k,v in pairs(params) do
        if type(k)=="string" then
            result[#result+1]={key=k, value=v}
        end
    end
end

--[[
    merge deltas into single table, while copying as little/shallowly as possible,
        subject to the constraint that no values of deltas are modified
]]
local function merge_params(deltas)
    local params = {}
    local safe = {} -- portion of table that indexes to already-copied tables
    for _,delta in ipairs(deltas) do
        local params_prefix = params
        local safe_prefix = safe
        local key_parts = utils.string.split(delta.key, "__")
        for i=1,(#key_parts-1) do
            k=key_parts[i]
            if not safe_prefix[k] then
                if type(params_prefix[k])=="table" then
                    params_prefix[k]=utils.shallow_copy(params_prefix[k])
                else
                    params_prefix[k]={}
                end
                safe_prefix[k]={}
            end
            params_prefix=params_prefix[k]
            safe_prefix=safe_prefix[k]
        end
        local k = key_parts[#key_parts]
        params_prefix[k]=delta.value
        -- this prefix now references delta.value so is no longer safe
        safe_prefix[k]=nil
    end
    return params
end

local function resolve_params(param_list, outer)
    if #param_list==0 then return outer end

    local deltas = {}
    for _,params in ipairs(param_list) do
        if params.bind then
            params = module.resolve(params.value)
        end
        flatten_params(params.value, deltas)
    end

    return merge_params(deltas)
end

do
    local action_mt = {}

    function action_mt:__index(key)
        local value
        if self._index then
            value = self._index[key]
        end
        return value or rawget(action_mt, key)
    end

    function action_mt:_resolved_bindings(outer)
        outer = outer or {}
        local callables = resolve_map(self._bindings, outer, {}, self._limit)
        local params = resolve_params(self._params, outer)
        return callables, params
    end

    function action_mt:__call(outer)
        local callables, params = self:_resolved_bindings(outer)
        local results = {}
        for _,c in ipairs(callables) do
            results[#results+1]=c(params)
        end
        return unpack(results)
    end

    function action_mt:__bind(outer)
        local callables, params = self:_resolved_bindings(outer)
        if #callables==0 then
            return nil
        else
            local result = module.map(function() return callables end)
            return result:pass(params)
        end
    end

    function action_mt:_with_params(params, bind)
        local new_params = {unpack(self._params)}
        new_params[#new_params+1]={value=params, bind=bind}
        local obj = vim.tbl_extend("force", self, {_params=new_params})
        return setmetatable(obj, action_mt)
    end

    function action_mt:bind(params)
        return self:_with_params(params, true)
    end

    function action_mt:pass(params)
        return self:_with_params(params, false)
    end


    function module.map(bindings, index)
        obj = obj or {}
        obj = {
            _bindings=bindings or {},
            _params={}
            _index=index,
        }
        return setmetatable(obj, action_mt) 
    end

    function module.map_first(bindings, index)
        obj = module.map(bindings or {}, index)
        obj._limit=1
        return obj
    end

    function module.action(callable, index)
        if not utils.is_callable(callable) then error("action must be callable") end
        return module.map(function() return callable end, index)
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
