local module = {}

local binding = require("keyfactor.binding")

module.accept = binding.action(function(params)
    -- get current prompt...
    if prompt then
        if params.action and prompt:get_property("mutable_action") then
            prompt:set_action{accept=params.action}
        end
        prompt:accept()
    end
end, {})

module.cancel = binding.action(function(params)
    -- get current prompt...
    if prompt then
        if params.action and prompt:get_property("mutable_action") then
            prompt:set_action{cancel=params.action}
        end
        prompt:cancel()
    end
end, {})

module.rotate_focus = binding.action(function(params)
    -- get current prompt...
    if prompt then
        if params.action and prompt:get_property("options") then

        end
        prompt:cancel()
    end
end, {})

module.cancel = binding.action(function(params)
    -- get current prompt...
    if prompt then
        if params.action and prompt:get_property("mutable") then
            prompt:set_action{cancel=params.action}
        end
        prompt:cancel()
    end
end, {})

module.focus_mnemonic = binding.action(function(params)
    --[[
    tell views to display mnemonics for available options

    send key presses to mnemonic filter...
    --]]

end, {})



return module
