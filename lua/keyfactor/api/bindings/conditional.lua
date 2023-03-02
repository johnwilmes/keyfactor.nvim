local base = require("keyfactor.bindings.base")

local module = {}

--[=[


on CONDITION [:bind BINDING [:else_on CONDITION :bind BINDING]* [:else_bind BINDING]]
    -- CONDITIONAL: on{(condition)} or on.mod or on_not{(condition)} or on_not.mod

    -- CONDITIONAL:bind(thing1)
    -- CONDITIONAL:bind(thing1):else_bind(thing2)

    -- CONDITIONAL:pass(thing1)
    -- CONDITIONAL:pass(thing1):else_pass(thing2)



on_not (similarly)

    -resolves condition (passed as either index or call, different formats)
    -if condition is truthy then resolves thing1 and returns whatever it resolves to; defaults to
    returning `true` if no thing1
    -if condition is falsy, then resolves thing2 and returns whatever it resolves to; defaults to
    returning `nil` if no _else; (if _else given then thing2 must be given, or resolving is an
    error)

CONDITION:
    - index into `on` object with string index referring to a `mod`
    - call with table or bindable
        - list-like part: bindables
        - key-value part: string keys are mod names and values are boolean
    - return "and" of the results

BINDING:
    for every value:
    - if bindable, resolve and return result
    - if table, recurse into it, returning a table with same set of keys
    - otherwise, return value itself
--]=]

do
    local conditional_mt = {_n_alternatives=0}
    conditional_mt.__index = conditional_mt

    function conditional_mt:_ensure_else()
        if #self._conditions>self._n_alternatives then
            error("missing conditional binding before default binding")
        elseif #self._conditions<self._n_alternatives then
            error("default conditional binding already specified")
        end
    end

    function conditional_mt:_with_alternative(alternative, bind)
        local new_alternatives = {unpack(self._alternatives)}
        new_alternatives[#new_alternatives+1]={value=alternative, bind=bind}
        local obj = vim.tbl_extend("force", self, {_alternatives=new_alternatives})
        return setmetatable(obj, conditional_mt)
    end

    function condition_to_binding(condition)
        -- TODO validate condition:
        --      all keys must either be list-part indices, with bindable values
        --      or keys must be strings, and value is interpreted as boolean

        return function(params)
            local result = true
            for k,v in pairs(condition) do
                if type(k)=="string" then
                    -- k is a name of a mode, v is whether it must be enabled or disabled
                    result = result and utils.xor(key.mods[k], not v)
                else -- it is a list-part index
                    result = result and base.bind(v, params)
                end
            end
            return result
        end
    end

    -- TODO transform conditions to bindables
    function conditional_mt:_with_condition(condition, negate)
        local binding
        if base.is_bindable(condition) then
            binding = condition
        else
            binding = condition_to_binding(condition)
        end

        local new_conditions = {unpack(self._conditions)}
        new_conditions[#new_conditions+1]={binding=binding, negate=not not negate}
        local obj = vim.tbl_extend("force", self, {_conditions=new_conditions})
        return setmetatable(obj, conditional_mt)
    end

    function conditional_mt:bind(alternative)
        if #self._conditions<=#self._alternatives then
            error("conditional binding already specified")
        end
        return self:_with_alternative(alternative, true)
    end

    function conditional_mt:pass(alternative)
        if #self._conditions<=#self._alternatives then
            error("conditional binding already specified")
        end
        return self:_with_alternative(alternative, false)
    end

    function conditional_mt:else_bind(alternative)
        self:_ensure_else()
        return self:_with_alternative(alternative, true)
    end

    function conditional_mt:else_pass(alternative)
        self:_ensure_else()
        return self:_with_alternative(alternative, false)
    end

    function conditional_mt:else_on(condition)
        self:_ensure_else()
        return self:_with_condition(condition, false)
    end

    function conditional_mt:else_on_not(condition)
        self:_ensure_else()
        return self:_with_condition(condition, true)
    end

    local default_alternatives = {{value=true, bind=false}, {value=nil, bind=false}}

    function conditional_mt:__bind(params)
        local alternatives
        if self._n_alternatives==0 then 
            alternatives = default_alternatives
        else
            alternatives = {unpack(self._alternatives)}
            if #alternatives==#self._conditions then
                alternatives[#alternatives+1]={} -- implicit default nil
            end
        end

        local case -- which alternative is chosen
        for i,a in ipairs(alternatives) do
            case=a
            local condition = self._conditions[i]
            if condition and (not base.bind(condition.binding, params)==condition.negate) then
                break
            end
        end

        -- TODO the following can't handle circular table references
        local function reduce(binding)
            if base.is_bindable(binding) then
                return base.bind(binding, key, params)
            elseif type(binding)=="table" then
                return utils.table.map_values(binding, reduce)
            else
                return binding
            end
        end
        if case.bind then
            return reduce(case.value)
        else
            return case.value
        end
    end

    local on_mt = {}

    function on_mt:__index(key)
        return self{[key]=true}
    end

    function on_mt:__call(condition)
        local obj = setmetatable({_conditions={}, _alternatives={}}, conditional_mt)
        return obj:_with_condition(condition, self._negate)
    end

    module.on = setmetatable({}, on_mt)
    module.on_not = setmetatable({_negate=true}, on_mt)
end

return module
