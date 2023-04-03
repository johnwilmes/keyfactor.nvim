local module = {}
local kf = require("keyfactor.api")

--[[
        params:
            mode
            orientation
            linewise - boolean
            preserve - boolean
            follow - boolean
            layer_groups - layer group specification table, default {insert=true}

        if linewise, then open new line; it appears after the orientation position if
        orientation.side=="after", and otherwise it appears before
            - to instead open a line after the before side, or vice versa, first truncate the
            selection

        new selection has empty inner, at orientation position or start of new lines if linewise.
        if preserve then the former ranges of the selection are preserved as outer portion of new
        ranges; otherwise new outer portion is empty
]]
module.start = kf.binding.action(function(params)
    local mode, orientation = kf.fill(params, "mode", "orientation")
    -- require edit target and ability to set layers
    if not mode.edit or not mode.layers then return nil end

    local target = mode.edit:get()
    local selection = target.selection

    -- requires non-empty selection
    if selection.length == 0 then return nil end

    -- layer controller must allow insert group to continue
    local layer_groups = params.layer_groups or {insert=true}
    if not mode.layers:set_groups(layer_groups) then return nil end

    if linewise then
        local before = orientation.side=="before"
        selection = kf.insert.open(selection, orientation, before, preserve)
    elseif preserve then
        selection = selection:reduce_inner(orientation.side)
    else
        selection = selection:reduce(orientation)
    end

    local viewport
    if target.viewport and params.scroll~=false then
        local position = selection:get_focus()[orientation]
        viewport = kf.viewport.scroll_to_position(target.viewport, position)
    end

    mode.edit:set_details{
        window=target.window,
        buffer=target.buffer,
        selection=selection,
        viewport=viewport
    }
end)

--[[
    params:
        mode
        layer_groups (default: {insert=false})
--]]
module.stop = kf.binding.action(function()
    local mode = kf.fill(params, "mode")
    -- require edit target and ability to set layers
    if not mode.layers then return nil end

    -- layer controller must allow insert group to continue
    local layer_groups = params.layer_groups or {insert=false}
    if not mode.layers:set_groups(layer_groups) then return nil end
end)


local function do_insert(kind, value, params)
    local mode = kf.fill(params, "mode")
    -- require edit target
    if not mode.edit then return nil end

    local target = mode.edit:get()
    local selection = target.selection

    -- requires non-empty selection
    if selection.length == 0 then return nil end

    selection = kf.insert[kind](selection, value)

    local viewport
    if target.viewport and params.scroll~=false then
        local position = selection:get_focus()["inner"]["after"]
        viewport = kf.viewport.scroll_to_position(target.viewport, position)
    end

    mode.edit:set_details{
        window=target.window,
        buffer=target.buffer,
        selection=selection,
        viewport=viewport
    }

end

--[[
    params:
        key

        mode
        scroll
--]]
module.text = kf.binding.action(function(params)
    -- requires printable key
    if not key.printable then return nil end

    do_insert("literal", key.printable, params)
end)


module.indent = binding.action(function(params)
    do_insert("vim", "\t", params)
end)

module.linebreak = binding.action(function(params)
    -- require multiline permitted
    local mode = kf.fill(params, "mode")
    if not mode.edit then return nil end
    local target = mode.edit:get()
    if not target.multiline then return nil end

    do_insert("vim", "\n", params)
end)

local bs = vim.api.nvim_replace_termcodes("<bs>", true, true, true)
local del = vim.api.nvim_replace_termcodes("<del>", true, true, true)
local function delete_textobject(params)
    -- TODO
end

module.delete = binding.action(function(params)
    if not params.textobject then
        local char = (params.reverse and bs) or del
        do_insert("vim", char, params)
    else
        delete_textobject(params)
    end
end)

return module
