local kf = require("keyfactor.api")

local module = {}

-- TODO horizontal scrolling

--[[

    mode
    reverse (boolean)
    partial (boolean)
    linewise (boolean)

--]]
module.scroll = kf.binding.api(function(params)
    local mode = kf.fill(params, "mode")
    local target
    for _,t in ipairs(mode:get_targets()) do
        if t.name and t.viewport and t.multiline then
            target = t
        end
    end
    if not target then
        return
    end

    local viewport = target.viewport
    local reverse = not not params.reverse
    if params.linewise or params.partial then
        local count = 1
        if params.partial then
            count = vim.api.nvim_win_get_option(target.window, 'scroll')
        end
        viewport = kf.viewport.scroll_lines(target.viewport, reverse, count)
    else
        viewport = kf.viewport.scroll_pages(target.viewport, reverse, 1)
    end

    mode[target.name]:set_details{
        window=target.window,
        buffer=target.buffer,
        viewport=viewport
    }
end)


return module

