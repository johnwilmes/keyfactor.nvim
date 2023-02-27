local kf = require("keyfactor.base")

local module = {}

--[[
    params:
        orientation
        direction (left right up down)
        augment
        wrap_horizontal - default FALSE
            (wrap line for left/right)
        wrap - default FALSE
            (wrap to top/bottom of buffer (for up/down, and also left/wrap if wrap_horizontal is true))
        raw_column - default TRUE
            (for up/down, whether to use raw column or actual column)
]]
local horizontal = {left=true, right=true}
local vertical = {up=true, down=true}
module.select_direction = action(function(params)
    local frame = kf.get_frame()
    local selection = frame:get_selection()

    if vertical[params.direction] then
        local opts = {
            reverse= (params.direction=="up"),
            wrap = params.wrap
            raw_column= (params.raw_column~=false)
        }
        if params.augment then
            selection = selection:augment_row(params.orientation, opts)
        else
            selection = selection:next_row(params.orientation, opts)
        end
    elseif horizontal[params.direction] then
        local opts = {
            reverse= (params.direction=="left"),
            wrap = params.wrap
        }
        local preserve_row = (not params.wrap_horizontal) and "row"
        local textobject = kf.textobjects.column{preserve=preserve_row}
        if params.augment then
            selection = selection:augment_textobject(textobject, params.orientation, opts)
        else
            selection = selection:next_textobject(textobject, params.orientation, opts)
        end
    else
        --TODO log error
        return
    end

    frame:set_selection(selection, true)
end, {fill={"orientation"}})

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
    local frame = kf.get_frame()
    local selection = frame:get_selection()

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
            local confirm, ranges = ...-- TODO kf.prompt.range{options=all, multiple=true, picker="telescope"}
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

    frame:set_selection(selection, true)
end, {"orientation"})

module.select_focus = action(function()
    local frame = kf.get_frame()
    local selection = frame:get_selection()
    local focus = frame:get_selection_focus()

    selection = selection:get_child({[focus]={selection:get_range(focus)}})

    frame:set_selection(selection, true)
end)

--[[
    boundary = "inner", "outer", or nil
    side = "before", "after", or nil
--]]
module.truncate_selection = action(function(params)
    local frame = kf.get_frame()
    local selection = frame:get_selection()

    selection = selection:reduce(params.orientation)

    frame:set_selection(selection, true)
end)

local alt_focus = {}

--[[
    reverse = boolean
    jump = boolean
    contents = "register", "raw" or truthy, false? TODO
--]]
module.rotate = action(function(params)
    local frame = kf.get_frame()
    local selection = frame:get_selection()

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

