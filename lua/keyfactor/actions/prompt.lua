local module = {}

local kf = require("keyfactor.api")

module.accept = kf.binding.action(function(params)
    local mode = kf.fill(params, "mode")
    local prompt = mode.prompt
    if prompt and prompt:is_active() then
        mode.prompt:accept()
    end
end)

module.cancel = kf.binding.action(function(params)
    local mode = kf.fill(params, "mode")
    local prompt = mode.prompt
    if prompt and prompt:is_active() then
        mode.prompt:cancel()
    end
end)

--[[
    params: key
]]
module.push_key = kf.binding.action(function(params)
    local mode = kf.fill(params, "mode")
    local prompt = mode.prompt
    if prompt and prompt:is_active() and prompt.push_key and params.key then
        prompt:push_key(params.key)
    end
end)

return module
