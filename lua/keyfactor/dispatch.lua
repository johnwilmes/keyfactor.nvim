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
    local actions
    
    -- TODO fail more gracefully if no layers controller, or doesn't give layers
    for name, binding in kf.binding.iter(mode.layers) do
        local success, result = pcall(kf.binding.resolve_map, binding, key)
        if success then
            if #result > 0 then
                actions = result
                break
            end
        else
            error(result.."; from layer "..name)
        end
    end

    for _,action in ipairs(actions) do
        kf.exec(action)
    end
end

function module.exec(action)
    local mode = kf.mode.get_focus()

    -- if not currently execing an action
        -- create new coroutine
        -- store the coroutine somewhere...?
        -- exec action (param mode) within coroutine
    -- else
        -- fail?
end

return module
