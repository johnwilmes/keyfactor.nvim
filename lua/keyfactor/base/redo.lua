module = {}

local binding = require("keyfactor.binding")

local redo_target = {}

local function set_redo(capture, params, go)
    local namespace
    if not require("keyfactor.bind").is_executable(capture[1]) then
        capture = capture[1]
        namespace=capture.namespace
    end
    local result
    if go then
        result = kf.execute(self.actions, params)
    else
        result = module{namespace=namespace}
    end
   redo_target[namespace] = {actions=capture, params=params}
   return result
   
end

local function redo(params)
    -- TODO maybe allow also extra actions params to be passed via redo?
    local namespace=params.namespace
    local target = redo_target[namespace]
    if target then
        for _,action in ipairs(target.actions) do
            kf.execute(action, target.params)
        end
    end
end

module.set = binding.capture(function(capture, params) return set_redo(capture, params, true) end)
module.set_only = binding.capture(set_redo)

return binding.action(redo, {index=module})
