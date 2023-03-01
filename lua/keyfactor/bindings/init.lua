local utils = require("keyfactor.utils")

local module = utils.lazy_import{
    action = "keyfactor.bindings.base",
    on = "keyfactor.bindings.conditional",
    on_not = "keyfactor.bindings.conditional",
    map = "keyfactor.bindings.base"
}


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
