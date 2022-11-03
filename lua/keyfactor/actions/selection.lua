local kf = require("keyfactor.base")

local module = {}


--[[

    params:
        orientation
            boundary = "inner" or "outer"
            side = "left" or "right"
        reverse (boolean)
        partial (boolean)
        augment (boolean)
        wrap (boolean)
        multiple = "split" or "select" or falsey
            (default to "select" if truthy and not "split"?)
        choose = "auto" or "telescope" or "hop" or falsey
            (default to "auto" if truthy and not "telescope" or "hop"?)
        ranges = {...}


--]]
module.select_textobject = action(function(params)
    local window = vim.api.nvim_get_current_win()
    local selection = kf.get_selection(window)
    local focus = kf.get_focus(window)

    if params.multiple then
        if not params.augment then
            selection = kf.selection(selection.buffer, kf.range.buffer(selection.buffer))
        end
        if params.multiple=="split" then
            selection = selection:split_textobject(params.textobject)
        else
            selection = selection:subselect_textobject(params.textobject)
        end
        if params.choose then
            local all = selection:get_all()
            local confirm, ranges = kf.prompt.range{options=all, multiple=true, picker="telescope"}
            local child = {}
            for _,idx in ipairs(ranges) do
                child[idx]={all[idx]}
            end
            return selection:get_child(child)
        end
    else
        if params.choose then
            -- TODO if params.choose then select single range from entire buffer (telescope) or
            --      from viewport (hop). Do so regardless of #selection
            -- TODO first restrict to focus
            -- if (params.augment or params.partial) and selection is empty, treat selection as
            --      first line/col of buffer, or if params.reverse then last line/col
            --
            -- chooser({select one, on_confirm=...})
        else
            local opts = {reverse = params.reverse, partial = params.partial, wrap=params.wrap}
            if params.augment then
                selection = selection:augment_textobject(params.textobject, params.orientation, opts)
            else
                selection = selection:next_textobject(params.textobject, params.orientation, opts)
            end
        end
    end

    kf.set_selection(window, selection)
    kf.scroll_to_focus(window)
end, {"orientation"})

module.select_focus = action(function()
    local window = vim.api.nvim_get_current_win()
    local selection = kf.get_selection(window)
    local focus = kf.get_focus(window)

    selection = selection:get_child({[focus]={selection:get_range(focus)}})

    kf.set_selection(window, selection)
    kf.scroll_to_focus(window)
end, {"orientation"})

--[[
    boundary = "inner", "outer", or nil
    side = "before", "after", or nil
--]]
module.truncate_selection = action(function(params)
    local window = vim.api.nvim_get_current_win()
    local selection = kf.get_selection(window)

    selection = selection:reduce(params.orientation)

    kf.set_selection(window, selection)
    kf.scroll_to_focus(window)
end)

local alt_focus = {}

--[[
    reverse = boolean
    jump = boolean
    contents = "register", "raw" or truthy, false? TODO
--]]
module.rotate = action(function(params)
    local window = vim.api.nvim_get_current_win()
    local selection = kf.get_selection(window)

    local alt = alt_focus[window]
    if alt.selection ~= selection.id then
        alt.selection = selection.id
        alt.focus = kf.get_focus(window)
    end

    if params.contents then
        -- TODO
    else
        local focus = kf.get_focus(window)
        if params.jump then
            if params.reverse then
                if focus==1 then focus=selection.length
                elseif focus > alt.focus then focus = alt.focus
                else focus=1
                end
            else
                if focus==selection.length then focus=1
                elseif focus < alt.focus then focus = alt.focus
                else focus = selection.length
                end
            end
        else
            if params.reverse then focus = ((focus-2)%selection.length)+1
            else focus = (focus%selection.length)+1
            end
        end
        kf.set_focus(window)
    end


end)

return module

