local module = {}

--[[

on CONDITION  BINDING [._else] BINDING

CONDITION: index into `on` object
    - string index: unambiguously of form `mod` or `mode` or `submode`,
        or the same prefixed with either "no_" or "not_"
    - un-callable table index: (key, value) entries can be:
        (number, string): string is interpreted same as string index
        (string, bool): string is interpreted as string index (but prefix no/not disallowed)
        ("mode", "insert" or "normal" or {insert=true} or {normal=true})
        ("mods", table of entries of form {modname=bool})
        ("submode", submode name or table of entries of form {submode=bool})
    - callable table or function index: gets called with same "context" as resolve, and must return
        true/false

BINDING:
    - index with string: treat as name of "known" binding (i.e. element of this module, other than
    "on"?); subsequent calling or indexing (other than "_else/Else") gets passed to this binding
    - call: parameters should be bindings or tables of bindings

    -- TODO have an interface for registering "known" bindings
--]]
do
    local conditional_mt = {}
    function conditional_mt:__call(context)
        if self.mode then
            if self.mode~=context.mode then
                return false
            end
        end

        if self.submode_forbidden and self.submode_forbidden[context.submode] then
            return false
        end

        if self.submode_allowed and not self.submode_allowed[context.submode] then
            return false
        end

        for m,v in pairs(self.mods) do
            if utils.xor(v, context.mods[m]) then
                return false
            end
        end

        return true
    end
    
    local function parse_negation(s)
        local negate = s:match("^not?_(.+)")
        s = negate or s
        if s=="insert" or s=="normal" then
            if negate then
                if s=="insert" then
                    s="normal"
                else
                    s="insert"
                end
                negate = false
            end
        return (not negate), s
    end

    local function string_to_table(s, enable)
        if enable==nil then
            enable, s = parse_negation(s)
        end
        if s=="insert" or s=="normal" then
            return {mode=s}
        end
        if is_mod(s) then
            if is_submode(s) then
                -- TODO error ambiguous
            end
            return {mods={[s]=enable}}
        elseif is_submode(s) then
            if enable then
                return {submode_allowed={[s]=true}}
            else
                return {submode_forbidden={[s]=true}}
            end
        else
            -- TODO unrecognized
        end
    end

    local function get_conditional(desc)
        local conditional
        if type(desc)=="string" then
            conditional = string_to_table(desc)
        elseif type(desc)=="table" then
            conditional = {}
            for key,value in pairs(desc) do
                if type(key)=="number" and type(value)=="string" then
                    conditional = vim.tbl_deep_extend("force", conditional, string_to_table(value))
                elseif type(key)=="string" and type(value)=="bool" then
                    conditional = vim.tbl_deep_extend("force", conditional, string_to_table(key, value))
                elseif key=="mods" then
                    conditional.mods = conditional.mods or {}
                    for k,v in pairs(mods) do
                        if type(k)=="string" then
                            conditional.mods[k] = not (not v)
                        elseif type(v)=="string" then
                            local enable, mod = parse_negation(v)
                            conditional.mods[mod]=enable
                        end
                    end
                elseif key=="submode" then
                    if type(value)=="string" then
                        local enable, submode = parse_negation(value)
                        local d = "submode"..((enable and "_allowed") or "_forbidden")
                        d = utils.table.set_default(conditional, d)
                        d[value] = true
                    elseif type(value)=="table" then
                        for submode, allowed in pairs(value) do
                            local d = "submode"..((allowed and "_allowed") or "_forbidden")
                            d = utils.table.set_default(conditional, d)
                            d[submode] = true
                        end
                    end
                elseif key=="mode" then
                    if value=="insert" or value=="normal" then
                        conditional.mode=value
                    else
                        --TODO error
                    end
                end
            end
        end
        return setmetatable(conditional, conditional_mt)
    end

    local mt = {}

    local function new(old)
        old = old or {}
        local obj = old[old] or {}
        obj = {--shallow copy of used fields
            condition=obj.condition,
            on_true=obj.on_true,
            on_false=obj.on_false,
            unresolved=obj.unresolved
        }

        local new = {}
        new[new] = obj -- stored here to avoid index conflicts

        return setmetatable(new, mt)
    end

    function mt:__bind(context)
        local obj = self[self]
        if obj.condition==nil then
            -- TODO error
        elseif obj.on_true==nil and not obj.unresolved then
            -- TODO error
        elseif obj.on_false==false and not obj.unresolved then
            -- TODO error
        end

        if obj.condition(context) then
            if obj.on_true==nil then
                return module.resolve(obj.unresolved, context)
            end
            return module.resolve(obj.on_true, context)
        elseif obj.on_false~=nil then
            if obj.on_false==false then
                return module.resolve(obj.unresolved, context)
            end
            return module.resolve(obj.on_false, context)
        else
            return context.action, context.params
        end
    end

    function mt:__index(key)
        local result = new(self) -- avoid side effects, don't modify self
        local obj = result[result] -- stored here to avoid index conflicts

        if obj.condition==nil then
            -- key represents CONDITION
            if utils.is_callable(key) then
                obj.condition = key
            else
                obj.condition = get_conditional(key)
            end
        elseif obj.unresolved then
            if key=="_else" or key=="Else" then
                if obj.on_true~=nil then
                    -- TODO error
                end
                obj.on_true = obj.unresolved
                obj.on_false = false
                obj.unresolved = nil
            else
                obj.unresolved=obj.unresolved[key]
                if not obj.unresolved then
                    -- TODO error?
                end
            end
        elseif obj.on_true==nil then
            -- key represents name of known binding; set unresolved
            if key=="on" or not module[key] then
                --TODO error
            end
            obj.unresolved = module[key]
        elseif obj.on_false==nil then
            -- awaiting "else"
            if key~="_else" and key~="Else" then
                --TODO error
            end
            obj.on_false = false
        elseif obj.on_false==false then
            -- key represents name of known binding; set unresolved
            if key=="on" or not module[key] then
                --TODO error
            end
            obj.unresolved = module[key]
        else
            -- TODO error
        end

        return result
    end

    function mt:__call(...)
        local result = new(self) -- avoid side effects, don't modify self
        local obj = result[result] -- stored here to avoid index conflicts

        if obj.condition==nil then
            --TODO error, CONDITION must be provided as index
        elseif obj.unresolved then
            obj.unresolved = obj.unresolved(...)
        elseif obj.on_true==nil then
            obj.on_true = {...}
        elseif obj.on_false==false then
            obj.on_false = {...}
        else
            -- TODO error
        end

        return result
    end

    module.on = new()
end


--[[

(only/first/last) ACTION {PARAMS} .with(BINDINGS)

ACTION
    - index with string name of "known" action
    - call with action object (or callable??)

PARAMS
    - optionally: call result with dictionary of params

.with(BINDINGS)
    -optionally: specify one or more bindings/binding tables



result of binding: returns (wrapper, existing params)
    - wrapper tracks (existing action), ACTION, PARAMS, and BINDINGS

execution of wrapper with (call params):
    - let (new params) = PARAMS or (call params)
    - let (a, p) = resolve(BINDINGS or {}, ACTION, (new params))
        -- TODO remaining context for bindings, like mods/mode?
            - presumably derived at execution time, since getting "mode" right seems important...
    - call (existing action) with (call params) and call (a, p), as appropriate, in the appropriate
    order, as determined by whether existing action is non-nil and whether this is only/first/last

]]

do
    local mt = {}

    local function new(old)
        local obj
        if type(old)=="string" then
            obj = {name=old}
        else
            old = old[old]
            obj = {--shallow copy of used fields
                name=old.name
                action=old.action,
                unresolved=old.unresolved,
                params=old.params,
                bindings=old.bindings
            }
        end

        local new = {}
        new[new] = obj -- stored here to avoid index conflicts

        return setmetatable(new, mt)
    end

    function mt:__index(key)
        local result = new(self) -- avoid side effects, don't modify self
        local obj = result[result] -- stored here to avoid index conflicts

        if key=="with" then
            if obj.bindings~=nil then
                -- TODO error
            end
            if obj.unresolved then
                obj.action = obj.unresolved
                obj.unresolved = nil
            elseif not obj.action then
                --TODO error
            end
            obj.bindings = false
        elseif obj.unresolved then
            obj.unresolved=obj.unresolved[key]
        elseif obj.action==nil then
            --TODO lookup action
        end

        return result
    end

    function mt:__call(...)
        local result = new(self) -- avoid side effects, don't modify self
        local obj = result[result] -- stored here to avoid index conflicts
        if obj.action==nil then
            if obj.unresolved~=nil then
                --TODO error
            end
            obj.action = ...
        elseif obj.bindings==nil then
            if obj.params~=nil then
                --TODO error
            end
            obj.params = ...
        elseif obj.bindings==false then
            obj.bindings = {...}
        else
            --TODO error
        end

        return result
    end

    function mt:__bind(context)
        local result = new(self)
        local obj = result[result]
        obj.replaced_action = context.action

        return result, context.params
    end

    function mt:__exec(params)
        local obj = self[self]
        local my_params = obj.params or params
        local action = obj.action
        if obj.bindings then
            local context = {action=action, params=my_params}
            action, my_params = module.resolve(obj.bindings, context)
        end
        if obj.name=="last" and obj.replaced_action then
            kf.exec(obj.replaced_action, params)
        end
        kf.exec(action, my_params)
        if obj.name=="first" and obj.replaced_action then
            kf.exec(obj.replaced_action, params)
        end
    end

    module.only = new("only")
    module.first = new("first")
    module.last = new("last")
end

-- PARAM MANIPULATION
do
    local mt = {}
    function mt:__bind(context)
        return context.action, vim.tbl_extend("force", context.params or {}, self.params)
    end

    module.let = function(params)
        return setmetatable({params=params}, mt)
    end
end
do
    local mt = {}
    function mt:__bind(context)
        return context.action, vim.tbl_deep_extend("force", context.params or {}, self.params)
    end

    module.extend = function(params)
        return setmetatable({params=params}, mt)
    end
end
do
    local mt = {}
    function mt:__bind(context)
        return context.action, self.params
    end

    module.let_only = function(params)
        return setmetatable({params=params}, mt)
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
    
    Wring *action* declaration: optional ._else indexing to specify alternate set of bindings
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
