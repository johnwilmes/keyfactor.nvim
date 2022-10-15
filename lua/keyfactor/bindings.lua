local module = {}

--TODO shift to utils
function is_list_index(i,l) return (type(i)=="number" and i>0 and i<=#l and i%1==0) end

local function get_bind(obj)
    if type(obj)=="function" then
        return obj 
    elseif type(obj)=="table" then
        local mt = getmetatable(obj) or {}
        return rawget(mt, "__bind") or rawget(mt, "__call")
    end
end

function module.is_bindable(obj)
    return type(get_bind(obj))=="function"
end

function module.resolve(binding, context, params)
    return (get_bind(binding))(context, params)
end

--[[
    start with params=params or {}

    recurse through binding and produce two lists:
        {leaf binding of list-like part}, { {string key, unresolved value} }

    resolve each leaf binding and apply same recursion to output, then deep-set resulting (not
    additionally resolved values) at corresponding key

    finally resolve original string key values and deep set them in
]]

local function flatten_params(tbl, bindings, params)
    for _,v in ipairs(tbl) do
        if module.is_bindable(v) then
            bindings[#bindings+1]=v
        elseif type(v)=="table" then
            flatten_params(v, bindings, params)
        end
    end

    for k,v in pairs(tbl) do
        if type(k)=="string" then
            params[#params+1]={k,v}
        elseif not utils.list.is_index(k, tbl) then
            -- TODO log warning
        end
    end
end

function module.resolve_params(binding, context, params)
    local result = {}
    local leaves = {}
    local unresolved = {}
    flatten_params(binding, leaves, unresolved)
    for _,b in ipairs(leaves) do
        local resolved = {}
        flatten_params(module.resolve(b, context, params), {}, resolved)
        for _,kv in ipairs(resolved) do
            local k, v = unpack(kv)
            utils.table.set(result, k, v, "__")
        end
    end
    for _,kv in ipairs(unresolved) do
        local k, v = unpack(kv)
        if module.is_bindable(v) then
            v = module.resolve(v, context, params)
        end
        utils.table.set(result, k, v, "__")
    end
    return result
end

--[[
    first, resolve list-like part. then, resolve any key=value pairs where key appears on
    config.key
        -if value is bindable, resolve it and append result to results
        -otherwise value should be table, recurse into it
--]]
function module.resolve_keypress(binding, context, params, result, prefix)
    result = result or {}
    prefix = prefix or ""
    errors = errors or {}

    if module.is_bindable(binding) then
        result[#result+1] = module.resolve(binding, context, params)
    elseif type(binding)=="table" then
        for idx,value in ipairs(binding) do
            local new_prefix="%s[%s]":format(prefix, tostring(idx))
            module.resolve_keypress(value, context, params, result, new_prefix)
        end
        for name in context.key do
            if binding[name]~=nil then
                local new_prefix="%s.%s":format(prefix, name)
                module.resolve_keypress(value, context, params, result, new_prefix)
            end
        end
    else
        local msg="table or bindable value expected at index "..prefix
        -- TODO log msg
    end
    return result
end

local bindable_mt = {}
function bindable_mt:with(bindings)
    local with = self._with or {}
    with = vim.tbl_extend("force", with, {[#with+1]=bindings})
    local obj = vim.tbl_extend(self, {_with=with})
    return module.bindable(self._wrapped, obj)
end

function bindable_mt:__index(key)
    if self._index then
        if utils.is_callable(self._index) then
            return self:_index(key)
        else
            return self._index[key]
        end
    end
end

function bindable_mt:__call(bindings)
    return self:with(bindings)
end

function bindable_mt:__bind(context, params)
    if self._with then
        params = module.resolve_params(self._with, context, params)
    end

    if self.fill then
        -- fill fields of params listed in fill
    end

    return module.resolve(self._wrapped, context, params)
end

function module.bindable(callable, obj)
    obj = obj or {}
    obj = {_wrapped=callable,
        _fill = obj._fill or obj.fill,
        _with = obj._with or obj.with,
        _index = obj._index or obj.index
    }
    return setmetatable(obj, bindable_mt)
end

function module.action(callable, obj)
    local wrapped = function(binding, _, params)
        callable(params)
        return binding
    end
    return module.bindable(wrapped, obj)
end

function module.param(callable, obj)
    local wrapped = function(_, _, params)
        return callable(params)
    end
    return module.bindable(wrapped, obj)
end

function module.capture(callable, obj)
    return function(...)
        local capture = {...}
        local wrapped = function(binding, _, params)
            return callable(capture, params)
        end
        return module.bindable(wrapped, obj)
    end
end

function module.bind(...)
    local actions = {...}
    local wrapped = function(_, context, params)
        local results = module.resolve_keypress(actions, context, params)
        if #results > 0 then
            return results
        end
    end
    return module.bindable(wrapped)
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

--[=[

on CONDITION [[._then] BINDING [._else BINDING]]
    -- on[{(condition)}]
    -- on[{(condition)}](thing1) or on[{(condition)}]._then(thing1)
    -- on[{(condition)}]._else(thing2)
    -- on[{(condition)}](thing1)._else(thing2) or on[{(condition)}]._then(thing1)._else(thing2)

    -resolves condition (passed as either index or call, different formats)
    -if condition is truthy then resolves thing1 and returns whatever it resolves to; defaults to
    returning `true` if no thing1
    -if condition is falsy, then resolves thing2 and returns whatever it resolves to; defaults to
    returning `nil` if no _else; (if _else given then thing2 must be given, or resolving is an
    error)

CONDITION:
    - index into `on` object with string index unambiguously of form `mod` or `mode` or `submode`
    - call with table or bindable
        - list-like part: bindables
        - key-value part: string keys are unambiguously of form `mod`/`mode`/`subdmode`, and values
        are boolean
    - return "and" of the results

BINDING:
    for every value:
    - if bindable, resolve and return result
    - if table, recurse into it, returning a table with same set of keys
    - otherwise, return value itself
--]=]
do
    local function get_condition(tbl)
        return function(context)
            local result = true
            for k,v in pairs(table) do
                if utils.list.is_index(k,table) then
                    if is_bindable(v) then
                        result = result and module.resolve(v, context)
                    else
                        error
                    end
                elseif type(k)=="string" then
                    if k=="mode" then
                        if v=="insert" or v=="normal" then
                            ...
                        else
                            error
                        end
                    elseif k=="submode" then
                        if type(v)=="table" then
                            -- TODO check context.submode belongs to v
                        elseif type(v)=="string" then
                            -- TODO check submode==v
                        else
                            error
                        end
                    elseif k=="mods" then
                        -- TODO
                    elseif k =="layer" then
                        -- TODO
                    else
                        -- TODO check if unambiguously mode, submode, mod, or layer
                    end
                else
                    error
                end
            end
            return result
        end
    end

    local function reduce(binding, eval)
        if module.is_bindable(binding) then
            return eval(binding)
        elseif type(binding)=="table" then
            return utils.table.map_values(binding, eval)
        else
            return binding
        end
    end

    local on_mt = {}

    function on_mt:__bind(context, params)
        if self._condition==nil then
            error
        end

        local bindings
        local n
        if module.resolve(self._condition, context, params) then
            bindings = self._true or {true}
            n = self._n_true or 1
        else
            bindings = self._false or {}
            n = self._n_false or 0
        end

        local result = {}
        local eval = function(b) return module.resolve(b, context, params) end
        for i=1,n do
            local r = reduce(bindings[i], eval)
            if r ~= nil then
                results[#results+1]=r
            end
        end
        return unpack(result)
    end

    function on_mt:__index(key)
        return self{[key]=true}
    end

    function on_mt:__call(...)
        if self._true or self._false then
            error
        elseif self._condition then
            return self:_then(...)
        else
            local condition
            if module.is_bindable(...) then
                condition = {...}
            elseif type(...)=="table" then
                condition = get_condition(...)
            else
                error
            end
            return setmetatable({_condition=condition}, on_mt)
        end
    end

    function on_mt:_then(...)
        if self._condition==nil or self._true or self._false then
            error
        end
        local obj = {_condition=self.condition,
                     _true={...},
                     _n_true=select("#",...)}
        
        return setmetatable(obj, on_mt)
    end

    function on_mt:_else(...)
        if self._condition==nil or self._false then
            error
        end
        local obj = {_condition=self.condition,
                     _true=self._true,
                     _n_true=self._n_true,
                     _false={...},
                     _n_false=select("#",...)}
        return setmetatable(obj, on_mt)
    end

    module.on = setmetatable({}, on_mt)
end

-- toggle{opt1, opt2, ..., optn, [value=bindable]}
--
-- if value given, computes it
-- otherwise, takes value to be last returned value, or optn
--
-- if value==opti, returns opt(i+1)%n
-- otherwise returns opt1
do
    local toggle_mt = {}
    function toggle_mt:__bind(context, params)
        local value
        if self.value then
            value = module.resolve(self.value, context, params)
        else
            value = self.state or self[#self]
        end
        local index=1
        for i,x in ipairs(self) do
            if vim.deep_equal(x, value) then
                index=(i%#self)+1
                break
            end
        end

        value=self[index]
        if not self.value then
            self.state=value
        end
        return value
    end

    module.toggle = function(toggle)
        return setmetatable(toggle, toggle_mt)
    end
end

-- PROMPT
--[[

    textobject prompt: search/surround/char
        - at declaration, could maybe specify some ways of modifying the prompt
        - at binding, wrap the action
        - at execution
            - enter appropriate prompt mode
            - on cancel: if specific cancel specified then do it, otherwise just exit mode
            - on confirm: if different confirm provided at declaration, do it
                otherwise, set textobject=(self with argument given by prompt),
                then execute wrapped action with params from execution

    register prompt:
        like textobject prompt, but default on confirm is to set register={...}
        - sometimes we will want to use prompt, but the action will then be to set the default
        register, which might be done via a different on_confirm?

    mark prompt:
        like register prompt...

    textobject "choose" prompt:
        - can be either single or multiple selection, and either hop-style or telescope-style
        - at least some of the time, we need to partially perform the select_textobject action
        first (e.g., for "multiple" selection, we first select everything then use choose to
        subselect...; possible also for "directional" hop), so this isn't bound like the others

    insert prompt
        - always modifies the buffer
        - but we can have it also call some other stuff on confirm?
            - in particular, want to be able to set "redo"
            - default on_confirm:
                set action=nil,
                modify params with params.insert={text, selection...},
                then apply any bindings passed to insert at declaration,
                then execute any resulting action
--]]

return module
