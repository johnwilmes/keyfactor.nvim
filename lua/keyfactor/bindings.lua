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

function module.resolve(action, context)
    return (get_bind(action))(context)
end

--[[
    start with params=params or {}
    first resolve list-like part of bindings
        - if value is bindable, on resolve it should return a table containing (string) key=value
        pairs which will be extended into params
        - otherwise value must be table, and this table is treated recursively as param binding
        table
    next resolve (string) key=value part of bindings
        - if value is bindable, resolve it and assign value to key in params
        - otherwise directly assign value to key in params
    keys of form "part1__part2" are treated as values for params.part1.part2, etc.

    return params, errors where errors is nil if all indices/values conformed to above description,
    or a list of error messages otherwise
]]
function module.resolve_params(bindings, context, params, prefix)
    params = params or {}
    prefix = prefix or ""
    for idx,value in ipairs(bindings) do
        if module.is_bindable(value) then
            value = module.resolve(value, context)
        end

        local new_prefix = "%s[%s]":format(prefix, tostring(idx))
        if type(value)~="table" then
            local msg="table value expected at index "..new_prefix
            -- TODO log msg
        else
            module.resolve_params(value, context, params, new_prefix)
        end
    end
    for key,value in pairs(bindings) do
        if type(key)=="string" then
            if module.is_bindable(value) then
                value = module.resolve(value, context)
            end
            utils.table.set(params, key, value, "__")
        elseif not utils.list.is_index(key, bindings) then
            local new_prefix = "%s[%s]":format(prefix, tostring(key))
            local msg="invalid index "..new_prefix
            -- TODO log msg
        end
    end
    return params
end

--[[
    first, resolve list-like part. then, resolve any key=value pairs where key appears on
    config.key
        -if value is bindable, resolve it and append result to results
        -otherwise value should be table, recurse into it
--]]
function module.resolve_keypress(bindings, context, result, prefix)
    result = result or {}
    prefix = prefix or ""
    errors = errors or {}

    if module.is_bindable(bindings) then
        result[#result+1] = module.resolve(bindings, context)
    elseif type(value=="table") then
        for idx,value in ipairs(bindings) do
            local new_prefix="%s[%s]":format(prefix, tostring(idx))
            module.resolve_keypress(value, context, result, new_prefix)
        end
        for name in context.key do
            if bindings[name]~=nil then
                local new_prefix="%s.%s":format(prefix, name)
                module.resolve_keypress(value, context, result, new_prefix)
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

function bindable_mt:__bind(context)
    local params
    if self._with then
        params = module.resolve_params(self._with, context)
    else
        params = context.params
    end

    if self.fill then
        -- fill fields of params listed in fill
    end

    return self:_wrapped(context)
end

function module.bindable(callable, obj)
    obj = obj or {}
    obj = {_erapped=callable,
        _fill = obj._fill or obj.fill,
        _with = obj._with or obj.with,
        _index = obj._index or obj.index
    }
    return setmetatable(obj, bindable_mt)
end

function module.action(callable, obj)
    local wrapped = function(binding, context)
        callable(context.params)
        return binding
    end
    return module.bindable(wrapped, obj)
end

function module.param(callable, obj)
    local wrapped = function(binding, context)
        return callable(context.params)
    end
    return module.bindable(wrapped, obj)
end

function module.capture(callable, obj)
    return function(...)
        local capture = {...}
        local wrapped = function(binding, context)
            return callable(capture, params)
        end
        return module.bindable(wrapped, obj)
    end
end

function module.bind(...)
    local actions = {...}
    local wrapped = function(_, context)
        local results = module.resolve_keypress(actions, context)
        if #results > 0 then
            return results
        end
    end
    return module.bindable(wrapped, obj)
end

do
    local outer_mt = {}

    function outer_mt:__index(k)
        local index = utils.list.concatenate(self._index, {k})
        return setmetatable({_index=index}, outer_mt)
    end

    function outer_mt:__bind(context)
        local result = context.params
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

    function on_mt:__bind(context)
        if self._condition==nil then
            error
        end

        local bindings
        local n
        if module.resolve(self._condition, context) then
            bindings = self._true or {true}
            n = self._n_true or 1
        else
            bindings = self._false or {}
            n = self._n_false or 0
        end

        local result = {}
        local eval = function(b) return module.resolve(b, context) end
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
    function toggle_mt:__bind(context)
        local value
        if self.value then
            value = module.resolve(self.value, context)
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
