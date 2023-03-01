local module = {}

local binding = require("keyfactor.binding")

module.accept = binding.action(function(mode, _)
    local prompt = mode.prompt
    if prompt then
        prompt:accept()
        if kf.mode.is_started(mode) then kf.mode.stop(mode) end
    end
end, {})

--[[
    params: key
]]
module.push_key = binding.action(function(mode, params)
    local prompt = mode.prompt
    if prompt and prompt.push_key and params.key then
        prompt:push_key(params.key)
        module.accept(mode)
    end
end, {})

return module
