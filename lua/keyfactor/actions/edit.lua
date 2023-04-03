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
    follow


    overflow = {selection = strategy_name, register = strategy_name}
    or
    overflow = strategy_name

    example settings:
        default: overflow = "truncate"
        on multiple: overflow = {selection = "cycle", register= "fill"}
        
--]]
module.paste = kf.binding.action(function(params)
    local mode, orientation, register, follow = kf.fill(params, "mode", "orientation", "register", "follow")
    if (not mode.target) or mode.target.read_only then
        -- TODO notify warning?
        return
    end

    local selection = mode.target:get()
    local text = kf.register.read(register.name, register.entry)

    selection, text = selection:align_with(text, register)

    -- TODO if target.single_line then compress text to one line?
    -- TODO don't allow linewise if target.single_line?
    if params.linewise then
        local before = orientation.side=="before"
        selection = kf.edit.paste_lines(selection, orientation, text, before)
    else
        selection = selection:reduce(orientation)
        selection = kf.edit.replace(selection, text)
    end

    mode.target:set(selection)

    if follow then kf.follow_target(mode, orientation) end
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
    register (name)
    linewise
    follow
    orientation (only for follow)
]]
module.copy = kf.binding.action(function(params)
    local mode, register, follow = kf.fill(params, "mode", "register", "follow")
    if (not mode.target) then
        -- TODO notify warning?
        return
    end

    local selection = mode.target:get()
    if selection.length==0 then return end

    do_yank(selection, register.name, params.linewise)

    if follow then kf.follow_target(mode, kf.fill(params, "orientation")) end
end)

--[[
    orientation
    linewise
    autochange -- TODO
    register
        name
        (entry)
    follow
]]
module.cut = kf.binding.action(function(params)
    local mode, orientation, register, follow = kf.fill(params, "mode", "orientation", "register", "follow")
    if (not mode.target) or mode.target.read_only then
        -- TODO notify warning?
        return
    end

    local selection = mode.target:get()
    if selection.length==0 then return end

    do_yank(selection, register.name, params.linewise)

    if params.linewise then
        local before = orientation.side=="before"
        selection = kf.edit.delete_lines(selection, orientation, before)
    else
        selection = kf.edit.delete(selection, orientation.boundary)
    end
    -- TODO if mode.target.single_line, and n_lines is 0, add an empty line?
    -- (is it even possible to have no lines in a vim buffer?)

    mode.target:set(selection)

    if follow then kf.follow_target(mode, orientation) end
end)

--[[
    single character delete

    orientation
    reverse
    join -- whether to join lines when deleting beginning/end of line
    follow
--]]
module.trim = kf.binding.action(function(params)
    local mode, orientation = kf.fill(params, "mode", "orientation")
    if (not mode.target) or mode.target.read_only then
        -- TODO notify warning?
        return
    end

    local selection = mode.target:get()
    if selection.length==0 then return end

    -- TODO test join for extrange safety?
    vim.api.nvim_buf_call(selection.buffer, function()
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

    if follow then kf.follow_target(mode, orientation) end
end)

--[[
    reverse - true means *redo*, false means undo (default)
    keep_selection - false means also revert to corresponding selection, true means maintain current selection
    follow (+ orientation)
]]
module.undo = kf.binding.action(function(params)
    local mode = kf.fill(params, "mode")
    if (not mode.target) or mode.target.read_only then
        -- TODO notify warning?
        return
    end

    local selection = mode.target:get()

    local offset = (params.reverse and 1) or -1
    local node, actual = kf.undo.get_node(selection.buffer, offset)
    if actual==offset then
        selection = kf.undo.revert(selection.buffer, node)
        if not params.keep_selection then
            mode.target:set(selection)
        end
    end

    if follow then kf.follow_target(mode, kf.fill(params, "orientation")) end
end)

-- TODO `wring`-able change buffer

--[[
    params:
        path
        prompt
]]
local change_buffer = kf.binding.action(function(params)
    local mode = kf.fill(params, "mode")

    if not mode.target then
        return
    end

    if not path and not prompt then
        prompt = --TODO default prompt
    end

    if prompt then
        -- start prompt mode
        -- set initial prompt text to path or ""
        -- on prompt accept:
            -- actually change the target
    end

    local buffer = vim.fn.bufadd(path)
    vim.api.nvim_buf_set_option(buffer, 'buflisted', true)
    target:set_buffer(buffer)
end)


return module
