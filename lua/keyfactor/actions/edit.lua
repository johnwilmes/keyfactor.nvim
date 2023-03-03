local module = {}

local kf = require("keyfactor.api")

--[[
    orientation
    linewise
    register
        name
        entry
        overflow
        offset
        align_focus
    scroll


    overflow = {selection = strategy_name, register = strategy_name}
    or
    overflow = strategy_name

    example settings:
        default: overflow = "truncate"
        on multiple: overflow = {selection = "cycle", register= "fill"}
        
--]]
module.paste = kf.binding.action(function(params)
    local mode, orientation, register = kf.fill(params, "mode", "orientation", "register")
    if not mode.edit then
        return nil
    end

    local target = mode.edit:get()
    local selection = target.selection
    local text = kf.register.read(register.name, register.entry)

    selection, text = selection:align_with(text, register)

    if params.linewise then
        local before = orientation.side=="before"
        selection = kf.edit.paste_lines(selection, orientation, text, before)
    else
        selection = selection:reduce(orientation)
        selection = kf.edit.replace(selection, text)
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
    TODO:
        - repeat with same register should be no-op?
--]]
local function do_yank(selection, register, linewise)
    local text
    if linewise then
        text = kf.edit.get_lines(selection)
    else
        text = kf.edit.get_text(selection)
    end
    kf.register.write(register, text, selection)
end


--[[
    orientation (only for scrolling)
    register (name)
    linewise
    scroll
]]
module.copy = kf.binding.action(function(params)
    local mode, register = kf.fill(params, "mode", "register")
    if not mode.edit then
        return nil
    end

    local target = mode.edit:get()
    local selection = target.selection
    if selection.length==0 then return end

    do_yank(selection, register.name, params.linewise)

    if target.viewport and params.scroll~=false then
        local position = selection:get_focus()[orientation]
        local viewport = kf.viewport.scroll_to_position(target.viewport, position)
        mode.edit:set_details{
            window=target.window,
            buffer=target.buffer,
            viewport=viewport
        }
    end
end)

--[[
    orientation
    linewise
    autochange -- TODO
    register
        name
        (entry)
    scroll
]]
module.cut = kf.binding.action(function(params)
    local mode, orientation, register = kf.fill(params, "mode", "orientation", "register")
    if not mode.edit then
        return nil
    end

    local target = mode.edit:get()
    local selection = target.selection
    if selection.length==0 then return end

    do_yank(selection, register.name, params.linewise)

    if params.linewise then
        local before = orientation.side=="before"
        selection = kf.edit.delete_lines(selection, orientation, before)
    else
        selection = kf.edit.delete(selection, orientation.boundary)
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
    single character delete

    orientation
    reverse
    join -- whether to join lines when deleting beginning/end of line
    scroll
--]]
module.trim = kf.binding.action(function(params)
    local mode, orientation = kf.fill(params, "mode", "orientation")
    if not mode.edit then
        return nil
    end

    local target = mode.edit:get()
    local selection = target.selection
    if selection.length==0 then return end

    -- TODO test join for extrange safety?
    vim.api.nvim_buf_call(target.buffer, function()
        -- use nvim_buf_call in case we need to use :join
        for idx, range in selection:iter() do
            local pos=range[params.orientation]
            if params.reverse then
                if pos[2]==0 then
                    if params.join then
                        -- cmd is 1-indexed, pos is 0-indexed, so pos[1] refers to previous line
                        vim.cmd(("%ujoin! 2"):format(pos[1]))
                    end
                else
                    local text = vim.api.nvim_buf_get_lines(0, pos[1], pos[1]+1, false)[1]
                    local before = utils.utf8.round(text, pos[2]-1, true)
                    vim.api.nvim_buf_set_text(selection.buffer, 0, pos[1], before, pos[1], pos[2], {})
                end
            else
                local text = vim.api.nvim_buf_get_lines(0, pos[1], pos[1]+1, false)[1]
                local length = #text
                if pos[2]==length then
                    if params.join then
                        -- cmd is 1-indexed, pos is 0-indexed, so pos[1]+1 refers to this line
                        vim.cmd(("%ujoin! 2"):format(pos[1]+1))
                    end
                else
                    local after = utils.utf8.round(text, pos[2]+1, false)
                    vim.api.nvim_buf_set_text(selection.buffer, 0, pos[1], pos[2], pos[1], after, {})
                end
            end
        end
    end)

    if target.viewport and params.scroll~=false then
        local position = selection:get_focus()[orientation]
        local viewport = kf.viewport.scroll_to_position(target.viewport, position)
        mode.edit:set_details{
            window=target.window,
            buffer=target.buffer,
            viewport=viewport
        }
    end
end)

--[[
    reverse - true means *redo*, false means undo (default)
    keep_selection - false means also revert to corresponding selection, true means maintain current selection
]]
module.undo = binding.action(function(params)
    local mode = kf.fill(params, "mode")
    if not mode.edit then
        return nil
    end

    local target = mode.edit:get()
    local selection

    local offset = (params.reverse and 1) or -1
    local node, actual = kf.undo.get_node(target.buffer, offset)
    if actual==offset then
        selection = kf.undo.revert(target.buffer, node)
        if params.keep_selection then
            selection=nil
        end
    end

    if selection then
        mode.edit:set_details{
            window=target.window,
            buffer=target.buffer,
            selection=selection,
        }
    end
end)

return module
