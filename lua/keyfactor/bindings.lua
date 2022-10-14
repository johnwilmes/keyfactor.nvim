local module = {}

--TODO shift to utils
function is_list_index(i,l) return (type(i)=="number" and i>0 and i<=#l and i%1==0) end

--[[
    start with params=params or {}
    first resolve list-like part of bindings
        - if value is __exec'able, on __exec it should return a table containing (string) key=value
        pairs which will be extended into params
        - otherwise value must be table, and this table is treated recursively as param binding
        table
    next resolve (string) key=value part of bindings
        - if value is __exec'able, exec it and assign value to key in params
        - otherwise directly assign value to key in params
    keys of form "part1__part2" are treated as values for params.part1.part2, etc.

    return params, errors where errors is nil if all indices/values conformed to above description,
    or a list of error messages otherwise
]]
function module.resolve_params(bindings, context, params, prefix)
    params = params or {}
    prefix = prefix or ""
    for idx,value in ipairs(bindings) do
        if module.is_executable(value) then
            value = module.execute(value, context)
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
            if module.is_executable(value) then
                value = module.execute(value, context)
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

do
--[[
    first, resolve list-like part. then, resolve any key=value pairs where key appears on
    config.key
        -if value is exec'able, exec it and append result to results
        -otherwise value should be table, recurse into it
--]]
--
    function resolve_action(bindings, context, result, index)
        if module.is_executable(value) then
            value = module.execute(value, context)
            result[#result+1]=value
        elseif type(value)=="table" then
            module.resolve_actions(value, context, result, index)
        else
            local msg="table or executable value expected at index "..index
            -- TODO log msg
        end
    end

    function module.resolve_actions(bindings, context, result, prefix)
        result = result or {}
        prefix = prefix or ""
        errors = errors or {}
        for idx,value in ipairs(bindings) do
            local new_prefix="%s[%s]":format(prefix, tostring(idx))
            resolve_action(value, context, result, new_prefix)
        end

        for name in context.key do
            if bindings[name]~=nil then
                local new_prefix="%s.%s":format(prefix, name)
                resolve_action(value, context, result, new_prefix)
            end
        end
        return result
    end
end


--[[ bind(action bindings):with{ param bindings }

every __call appends action bindings
every :with appends to param bindings

on __exec, 
    resolve param bindings (from first to last), or just use context.params if no params specified
    then resolve everything in action bindings using params resulting from param bindings
    return flattened list of results from action bindings, or nil if all action bindings returned
    nil
]]


do
    local bind_mt = {}
    bind_mt.__index = bind_mt

    function action_mt:__call(actions)
        if not self._actions then
            return setmetatable({_actions={actions}, _params=self._params}, bind_mt)
        else
            return self:with(actions)
        end
    end

    function action_mt:with(new_params)
        if self._actions==nil then
            error
        end
        local params = {unpack(self._params or {})} -- shallow copy self._params or {}
        params[#params+1]=new_params
        return setmetatable({_actions=self._actions, _params=self._params}, bind_mt)
    end

    function action_mt:__exec(context)
        local new_context = context
        if self._params then
            local params = module.resolve_params(self._params, context)
            new_context = vim.tbl_extend("force", context, {params=params})
        end
        local results = module.resolve(self._actions or {}, context)
        
        if #results > 0 then
            return results
        end
    end

    module.bind = setmetatable({}, bind_mt)
end

do
    local outer_mt = {}

    function outer_mt:__index(k)
        local index = utils.list.concatenate(self._index, {k})
        return setmetatable({_index=index}, outer_mt)
    end

    function outer_mt:__exec(context)
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
    - call with table or exec'able
        - list-like part: exec'ables
        - key-value part: string keys are unambiguously of form `mod`/`mode`/`subdmode`, and values
        are boolean
    - return "and" of the results

BINDING:
    for every value:
    - if exec'able, execute and return result
    - if table, recurse into it, returning a table with same set of keys
    - otherwise, return value itself
--]=]
do
    local function get_condition(tbl)
        return function(context)
            local result = true
            for k,v in pairs(table) do
                if utils.list.is_index(k,table) then
                    if is_executable(v) then
                        result = result and module.execute(v, context)
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

    local function eval(binding, exec)
        if module.is_executable(binding) then
            return exec(binding)
        elseif type(binding)=="table" then
            return utils.table.map_values(binding, exec)
        else
            return binding
        end
    end

    local on_mt = {}

    function on_mt:__exec(context)
        if self._condition==nil then
            error
        end

        local bindings
        local n
        if module.execute(self._condition, context) then
            bindings = self._true or {true}
            n = self._n_true or 1
        else
            bindings = self._false or {}
            n = self._n_false or 0
        end

        local result = {}
        local exec = function(b) return module.execute(b, context) end
        for i=1,n do
            local r = eval(bindings[i], exec)
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
            if module.is_executable(...) then
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

-- toggle{opt1, opt2, ..., optn, [value=execable]}
--
-- if value given, computes it
-- otherwise, takes value to be last returned value, or optn
--
-- if value==opti, returns opt(i+1)%n
-- otherwise returns opt1
do
    local toggle_mt = {}
    function toggle_mt:__exec(context)
        local value
        if self.value then
            value = module.execute(self.value, context)
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

-- CONTEXT CAPTURE
--[[
    at declaration, grab optional binding arguments
        - for redo, would be nice to be able to specify scope:
        global/window/buffer/window+buffer...
            - actually this could be specified with action.redo:new{scope=...}
    at binding, grab context and wrap action so we can grab params at execution
    at execution, grab params
        - for wring, also need to get undo node/selection at this point, so we know where to go
        when we undo
        - wring is always scoped to buffer+selection?
    
    Wring *action* declaration: optional .with_fallback indexing to specify alternate set of bindings
    Wring execution:
        if current selection/state is valid ("corresponds" to wring capture)
            compute new register
            if new reg is different from current selection's then
                undo to point of capture
                starting from the actual action/params that were performed for that selection,
                    apply an bindings specified with capture
                    execute the result
            else
                notify somehow that no change in register is available (some kind of error
                message?)
        else
            if "_else" bindings were provided with action declaration
                apply them, starting from nil/currently passed params
            else
                notify somehow that wringing is invalid (some kind of error message?)
--]]
do
    local mt = {}
    local module.capture = {}

    module.capture.wring
    module.capture.redo
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

-- BINDING RESOLUTION
do
    local function get_binding_handler(binding)
        local b = rawget(getmetatable(binding) or {}, "__bind")
        if (not b) and utils.is_callable(binding) then
            b = binding
        end
        if (not b) and type(b)=="table" then
            b = module.resolve
        end
        return b
    end

    function module.resolve(bindings, context)
        --[[
            context: action, params, key, mods, layers, mode, submode, (window+buffer???)
                - mods/layers are flags tables
                - mode/submode are strings
            context gets filled as needed

        Binding resolution:
            First, recursively apply bindings indexed from 1 to #bindings, in order of increasing index
            Then, if any table keys match any of the names of the keypress, recursively apply them (in
            an unspecified order)

        Applying a binding:
            if its metatable has "__bind" then call that
            else if it is itself callable, then call it
            else if it is a table then apply module.resolve to it
            else error
        --]]
        
        -- TODO fill context
        
        if type(bindings)~="table" then
            bindings = {bindings}
        end

        for _,binding in ipairs(bindings) do
            local b = get_binding_handler(binding)
            if (not b) then
                -- TODO error
            end
            context.action, context.params = b(binding, context)
        end

        for key,binding in pairs(bindings) do
            if type(key)=="string" then
                -- TODO if key refers to context.key then
                local b = get_binding_handler(binding)
                if (not b) then
                    -- TODO error
                end
                context.action, context.params = b(binding, context)
            end
        end
    end
end

return module
