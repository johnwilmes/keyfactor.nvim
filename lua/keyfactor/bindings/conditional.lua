local base = require("keyfactor.bindings.base")

local module = {}

--[=[


on CONDITION [:bind BINDING [:else_bind BINDING]]
    -- CONDITIONAL: on{(condition)} or on.mod or on_not{(condition)} or on_not.mod

    -- CONDITIONAL:bind(thing1)
    -- CONDITIONAL:bind(thing1):else_bind(thing2)

    following are equivalent to wrapping thing1/thing2 in `map` binding
    -- CONDITIONAL:map(thing1)
    -- CONDITIONAL:map(thing1):else_map(thing2)


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

    local function do_bind(obj, alternative)
        if obj._n_alternatives~=0 then
            error("first conditional alternative is already bound")
        end
        local new = {_n_alternatives=1, _true=alternative}
        return setmetatable(vim.tbl_extend("force", obj, new), conditional_mt)
    end

    local function do_else(obj, alternative)
        if obj._n_alternatives==0 then
            error("cannot bind second conditional alternative until first alternative is bound")
        elseif obj._n_alternatives==2 then
            error("second conditional alternative is already bound")
        end
        local new = {_n_alternatives=2, _false=alternative}
        return setmetatable(vim.tbl_extend("force", obj, new), conditional_mt)
    end

    function conditional_mt:bind(alternative)
        return do_bind(self, alternative)
    end

    function conditional_mt:map(alternative)
        local obj = do_bind(self, base.map(alternative))
        obj._needs_map = true
        return obj
    end

    function conditional_mt:else_bind(alternative)
        if self._needs_map then
            error("expected mapping alternative")
        end
        return do_else(self, alternative)
    end

    function conditional_mt:else_map(alternative)
        if not self._needs_map then
            error("expected non-map binding alternative")
        end
        return do_else(self, base.map(alternative))
    end

    function conditional_mt:__bind(key, params)
        local alternative -- which binding to use: the "then" part or the "else" part
        if utils.xor(base.bind(self._condition, key, params), self._negate) then
            if self._n_alternatives>0 then
                alternative = self._true
            else
                -- default result
                alternative = true
            end
        else
            alternative = self._false
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
        return reduce(alternative)
    end

    local on_mt = {}

    function on_mt:__index(key)
        return self{[key]=true}
    end

    function on_mt:__call(condition)
        -- TODO validate condition:
        --      all keys must either be list-part indices, with bindable values
        --      or keys must be strings, and value is interpreted as boolean

        local obj = {_negate=self._negate}
        obj._condition = function(key, params)
            local result = true
            for k,v in pairs(tbl) do
                if type(k)=="string" then
                    -- k is a name of a mode, v is whether it must be enabled or disabled
                    result = result and utils.xor(key.mods[k], not v)
                else -- it is a list-part index
                    result = result and base.bind(v, key, params)
                end
            end
            return result
        end
        return setmetatable(obj, conditional_mt)
    end

    module.on = setmetatable({}, on_mt)
    module.on_not = setmetatable({_negate=true}, on_mt)
end

return module
