local kf = require("keyfactor.api")

local module = {}

-- TARGETING: these actions all operate on the first target in mode:get_targets() that presents
-- both a name and a selection (can be empty)

-- TODO whenever selection is changed, also shift viewport to make selection visible

local function get_selection_target(mode)
    for _,t in ipairs(mode:get_targets()) do
        if t.name and t.selection then
            return t
        end
    end
end

--[[
    params:
        mode
        orientation
        direction (left right up down)
        augment
        wrap_horizontal - default FALSE
            (wrap line for left/right)
        wrap - default FALSE
            (wrap to top/bottom of buffer (for up/down, and also left/wrap if wrap_horizontal is true))
        raw_column - default TRUE
            (for up/down, whether to use raw column or actual column)
        viewport - boolean default TRUE
            - if selection is length 0 then default to one end of viewport
        scroll - boolean default TRUE
            - if selection is changed, and is nonempty, scroll so that focus is visible
]]
local horizontal = {left=true, right=true}
local vertical = {up=true, down=true}
local direction_to_side={up="after", left="after", down="before", right="before"}
module.direction = kf.binding.action(function(params)
    local side = direction_to_side[params.direction]
    if not side then
        --TODO log invalid direction
        return
    end

    local mode, orientation = kf.fill(params, "mode", "orientation")

    local target = get_selection_target(mode)
    if not target then
        return
    end
    local selection = target.selection

    if selection.length==0 and target.viewport and params.viewport~=false then
        local range = kf.range.viewport(target.viewport)
        range = kf.range({range[side]["inner"]})
        selection = kf.selection(target.buffer, {range})
    end

    if vertical[params.direction] then
        local opts = {
            reverse = (params.direction=="up"),
            wrap = params.wrap
            raw_column = (params.raw_column~=false)
        }
        if params.augment then
            selection = selection:augment_row(orientation, opts)
        else
            selection = selection:next_row(orientation, opts)
        end
    else -- horizontal[params.direction]
        local opts = {
            reverse= (params.direction=="left"),
            wrap = params.wrap
        }
        local preserve_row = (not params.wrap_horizontal) and "row"
        local textobject = kf.textobjects.column{preserve=preserve_row}
        if params.augment then
            selection = selection:augment_textobject(textobject, orientation, opts)
        else
            selection = selection:next_textobject(textobject, orientation, opts)
        end
    end

    local viewport
    if target.viewport and params.scroll~=false then
        local position = selection:get_focus()[orientation]
        viewport = kf.viewport.scroll_to_position(target.viewport, position)
    end

    mode[target.name]:set_details{
        window=target.window,
        buffer=target.buffer,
        selection=selection,
        viewport=viewport
    }
end)

--[[

    params:
        mode
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
        viewport (boolean default true)


--]]
module.textobject = kf.binding.action(function(params)
    -- TODO validate params.textobject
    local mode, orientation = kf.fill(params, "mode", "orientation")

    local target = get_selection_target(mode)
    if not target then
        return
    end
    local selection = target.selection

    if selection.length==0 and target.viewport and params.viewport~=false then
        local range = kf.range.viewport(target.viewport)
        range = kf.range({range[(params.reverse and "after") or "before"]["inner"]})
        selection = kf.selection(target.buffer, {range})
    end

    if params.multiple then
        if not params.augment then
            selection = kf.selection(selection.buffer, {kf.range.buffer(selection.buffer)})
        end
        if params.multiple=="split" then
            selection = selection:split_textobject(params.textobject)
        else
            selection = selection:subselect_textobject(params.textobject)
        end
        if params.choose then
            -- TODO
            return
            --[[
            local all = selection:get_all()
            local confirm, ranges = ...-- TODO kf.prompt.range{options=all, multiple=true, picker="telescope"}
            local child = {}
            for _,idx in ipairs(ranges) do
                child[idx]={all[idx]}
            end
            return selection:get_child(child)
            ]]
        end
    else
        if params.choose then
            return
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

    mode[target.name]:set_details{window=target.window, buffer=target.buffer, selection=selection}
end)

--[[ restrict selection to its focus

        mode
        scroll - boolean default TRUE
            - scroll so that focus is visible
--]]
module.focus = kf.binding.action(function(params)
    local mode = kf.fill(params, "mode")

    local target = get_selection_target(mode)
    if not target then
        return
    end
    local selection = target.selection
    if selection.length > 0 then
        local focus = selection:get_focus()
        selection = selection:get_child({[focus]={selection:get_range(focus)}})
        mode[target.name]:set_details{window=target.window, buffer=target.buffer, selection=selection}
    end
end)

--[[
    truncate each range in the selection to one part: inner/outer, before/after

    mode
    boundary = "inner", "outer", or nil
    side = "before", "after", or nil
    scroll = boolean default TRUE
--]]
module.truncate = kf.binding.action(function(params)
    local mode = kf.fill(params, "mode")
    local target = get_selection_target(mode)
    if not target then
        return
    end
    local selection = target.selection

    selection = selection:reduce(params.orientation)

    mode[target.name]:set_details{window=target.window, buffer=target.buffer, selection=selection}
end)


--[[
    TODO move focus within selection

    mode
    reverse = boolean
    jump = boolean
    contents = "register", "raw" or truthy, false? TODO
    scroll = boolean default TRUE
local alt_focus = {}
module.rotate = kf.binding.action(function(params)
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
--]]

return module

