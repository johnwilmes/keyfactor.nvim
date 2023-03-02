local module = {}

--[[
-- TODO following should go in setup

function start(...)
    for every key in key do
        ask encoder fr encodings of key (for all hardware mods; encoder is allowed to choose
        subset of them)
            -encoder also indicates printable result, where applicable?
        map (normal mode) to dispatch_keypress (with nowait)
    end
end
]]

function module.dispatch_keypress(key)
    local mode = kf.mode.get_focus()
    local action
    
    -- TODO fail more gracefully if no layers controller, or doesn't give layers
    local params = {key=key}
    for name, binding in kf.binding.iter(mode.layers) do
        local success, result = pcall(kf.binding.bind, binding, params)
        if success then
            if utils.callable(result) then
                action = result
                break
            end
        else
            error(result.."; from layer "..name)
        end
    end

    action()
end

return module
