local kf = require("keyfactor.api")

local module = {}

-- TODO horizontal scrolling

--[[

    mode
    view = index of mode viewport? if not specified, use first viewport that recommends targetting
        in appropriate scroll direction
    direction = up/down/left/right
    count
    pagewise: true/false or "partial"; default "partial"

    if viewport is not currently visible in a particular window, then
        only linewise=true, partial=false is permitted; if anything else is set, then no scrolling

--]]
local direction_to_axis = {up="vertical", down="vertical", left="horizontal", right="horizontal"}

-- direction:  pagewise
local cmd_index = {
    up = {
        [false] = "<C-y>",
        partial = "<C-u>",
        [true] = "<C-b>",
    }
    down = {
        [false] = "<C-e>",
        partial = "<C-d>",
        [true] = "<C-f>",
    },
    left = {
        [false] = "zh",
        partial = "zH",
        [true] = "zH", -- also multiply count by 2
    },
    right = {
        [false] = "zl",
        partial = "zL",
        [true] = "zL", -- also multiply count by 2
    },
}

module.scroll = kf.binding.action(function(params)
    local mode, count = kf.fill(params, "mode", "count")
    if not mode.view then
        -- TODO log warning?
        return
    end
    local direction = params.direction
    local axis = direct_to_axis[direction]
    if not axis then
        direction="down"
        axis="vertical"
    end

    local pagewise = params.pagewise
    if type(pagewise)~="boolean" then
        pagewise="partial"
    end

    local cmd = cmd_index[direction][pagewise]
    if axis=="horizontal" and pagewise==true then
        count = count*2
    end
    if count > 1 then
        cmd = count..cmd
    end

    local viewports = mode.view:get_viewports()
    local index = params.view
    local viewport = viewports[index]

    if not viewport then
    -- iterate over viewports and select the first one that supports scrolling in this direction
    -- ask the window manager if that viewport is actually present somewhere
        -- if so, apply native vim scrolling in that window, get vim.fn.winsaveview,
            -- and call view:set with the result
        -- otherwise, for pagewise scroll, just guess the number of lines

        for i,v in ipairs(mode.view:get_viewports()) do
            if v.scroll==axis or v.scroll=="both" then
                index = i
                viewport = v
                break
            end
        end
    end

    if not viewport then
        -- TODO log warning
        return
    end

    kf.scroll(view, index, cmd)
end)


return module

