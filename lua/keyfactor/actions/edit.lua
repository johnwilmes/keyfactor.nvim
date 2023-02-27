local module = {}

local binding = require("keyfactor.binding")

--[[
    orientation
    linewise
    register
        name
        entry
        overflow
        offset
        align_focus


    overflow = {selection = strategy_name, register = strategy_name}
    or
    overflow = strategy_name

    example settings:
        default: overflow = "truncate"
        on multiple: overflow = {selection = "cycle", register= "fill"}
        
--]]
module.paste = binding.action(function(params)
    local mode = kf.get_mode()
    local selection = mode:get_selection()
    local register = kf.register.read(params.register.name, params.register.entry)

    selection, register = selection:align_with(register, params.register)

    if params.linewise then
        local before = params.orientation.side=="before"
        selection = kf.edit.paste_lines(selection, params.orientation, register, before)
    else
        selection = selection:reduce(orientation)
        selection = kf.edit.replace(selection, aligned)
    end

    selection = mode:set_selection(selection, true) -- true: ensure focus visible

end, {fill={"orientation", "register"}})

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
]]
module.copy = binding.action(function(params)
    local frame = kf.get_frame()
    local selection = frame:get_selection()
    do_yank(selection, params.register.name, params.linewise)
end, {fill={"register"}})

--[[
    orientation
    linewise
    autochange -- TODO
    register
        name
        (entry)
]]
module.cut = binding.action(function(params)
    local frame = kf.get_frame()
    local selection = frame:get_selection()
    do_yank(selection, params.register.name, params.linewise)

    if params.linewise then
        local before = params.orientation.side=="before"
        kf.edit.delete_lines(selection, params.orientation, before)
    else
        kf.edit.delete(selection, params.orientation.boundary)
    end

    selection = frame:set_selection(selection, true)
end, {fill={"orientation", "register"}})

--[[
    orientation
    reverse
    join
--]]
module.trim = binding.action(function(params)
    local frame = kf.get_frame()
    local selection = frame:get_selection()

    -- TODO make this unicode safe
    -- TODO test join for extrange safety?
    for idx, range in selection:iter() do
        local pos=range[params.orientation]
        if params.reverse then
            if pos[2]==0 then
                if params.join then
                    vim.cmd(("%ujoin! 2"):format(pos[1]))
                end
            else
                vim.api.nvim_buf_set_text(selection.buffer, 0, pos[1], pos[2]-1, pos[1], pos[2], {})
            end
        else
            -- TODO better way to get line length?
            -- TODO fails if buffer not loaded...
            local text = vim.api.nvim_buf_get_lines(0, pos[1], pos[2], true)[1]
            local length = #text
            if pos[2]==length then
                if params.join then
                    vim.cmd(("%ujoin! 2"):format(pos[1]+1))
                end
            else
                vim.api.nvim_buf_set_text(selection.buffer, 0, pos[1], pos[2], pos[1], pos[2]+1, {})
            end
        end
    end

    selection = frame:set_selection(selection, true)
end, {fill={"orientation"}})

--[[
    reverse - true means *redo*, false means undo (default)
    keep_selection - false means also revert to corresponding selection, true means maintain current selection
]]
module.undo = binding.action(function(params)
    local frame = kf.get_frame()
    local selection = frame:get_selection()

    local offset = (params.reverse and 1) or -1
    local node, actual = kf.undo.get_node(selection.buffer, offset)
    if actual==offset then
        local selection = kf.undo.revert(selection.buffer, node)
        if not params.keep_selection then
            frame:set_selection(selection, true)
        end
    end
end)

return module
