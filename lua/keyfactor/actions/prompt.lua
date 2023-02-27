local module = {}

local binding = require("keyfactor.binding")

module.accept = binding.action(function(params)
    local frame = kf.get_frame()
    local mode = frame:get_mode()
    local prompt = mode.model
    if prompts.is_prompt(prompt) then
        prompt:accept()
    end
end, {})

module.cancel = binding.action(function(params)
    local frame = kf.get_frame()
    local mode = frame:get_mode()
    local prompt = mode.model
    if prompts.is_prompt(prompt) then
        prompt:stop()
    end
end, {})

--[[
--  params.key (optional) (TODO)
--]]
module.push_key = binding.bindable(function(context, params)
    local frame = kf.get_frame()
    local mode = frame:get_mode()
    local prompt = mode.model
    if prompts.is_prompt(prompt) and prompts.push_key then
        prompt:push_key(context.key)
    end
end, {})

module.pop_key = binding.action(function(params)
    local frame = kf.get_frame()
    local mode = frame:get_mode()
    local prompt = mode.model
    if prompts.is_prompt(prompt) and prompts.pop_key then
        prompt:pop_key()
    end
end, {})


return module
