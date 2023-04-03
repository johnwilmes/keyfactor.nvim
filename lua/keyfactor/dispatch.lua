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


--[[
local main_loop = function()
    while true do
        get next coroutine
            next in fast queue, or next in slow queue if fast is empty
            if no coroutine then break
            resume coroutine
    end
end
]]


local draw_loop = a.sync(function()
    local mode = kf.mode.get_focus()
    while mode do
        mode.view:draw()
        -- local prev_time = vim.loop.hrtime()
        -- await any of these events:
        --      -- but if any of these events are already waiting to be broadcast, then wait until
        --      the *last* one in the queue
        -- {source=mode, event=mode.unfocus} or {source=mode.view, event=view.update}
        -- local wait_time = nil
        -- if prev_time then
        --      local diff_time = (vim.loop.hrtime() - prev_time)/1e6
        --      if diff_time < debounce then
        --          wait_time = debounce - diff_time
        --      end
        -- end 
        -- then await schedule (with wait time wait_time)
        mode = kf.mode.get_focus()
    end
    -- TODO cleanup: destroy all displays
end)

local main = a.sync(function()
    -- TODO start initial mode
    a.wait(with_nursery(function(nursery)
        nursery.start_soon(draw_loop)

        --[[
    for every key in key do
        ask encoder fr encodings of key (for all hardware mods; encoder is allowed to choose
        subset of them)
            -encoder also indicates printable result, where applicable?
        map (normal mode) to dispatch_keypress (with nowait)
    end
        --]]
        --
        -- TODO wait for Cancellation/terminate event? should be built into nursery somehow, right?
    end))
end)

local function dispatch_keypress(key, nursery)
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
            -- TODO error(result.."; from layer "..name)
        end
    end

    local success, result = pcall(nursery.start, action)
    if not success then
        -- TODO log error
    end
end

return module
