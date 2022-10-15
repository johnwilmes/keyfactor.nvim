--[[
function start(...)
    for every key in key do
        ask encoder fr encodings of key (for all hardware mods; encoder is allowed to choose
        subset of them)
            -encoder also indicates printable result, where applicable?
        map (normal mode) to resolve_keypress (with nowait)
    end
end

function dispatch_keypress(names, mods)
    create context - incorporating mods
        - context: how things were when the key was pressed, not necessarily how the are *now*
        (e.g. action might change window, but context will reflect original window)

    reset state: mods, layer, orientation, register, etc

    create new coroutine fr current mode, and cache it somewhere along with current context

    within coroutine:
        for each active layer from high to low do
            resolve layer binding 
            if resolution is non-nil then break end
        end

        if resolution is nil then
            resolve default mode bindings
        end

    cleanup
        - undo node and selection checkpoints?
end
]]
