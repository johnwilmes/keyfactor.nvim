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
    local window = vim.api.nvim_get_current_win()
    local selection = kf.get_selection(window)
    local register = kf.register.read(params.register.name, params.register.entry)

    selection, register = kf.align_selection(selection, register, params.register)

    if params.linewise then
        local before = params.orientation.side=="before"
        selection = kf.edit.paste_lines(selection, params.orientation, register, before)
    else
        selection = selection:reduce(orientation)
        selection = kf.edit.replace(selection, aligned)
    end

    selection = kf.set_selection(window, selection)
    kf.scroll_to_focus(window)
    kf.wring.set(module.paste, params, kf.register.wring_history)
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
module.yank = binding.action(function(params)
    local window = vim.api.nvim_get_current_win()
    local selection = kf.get_selection(window)
    do_yank(selection, params.register.name, params.linewise)
end, {fill={"register"}})

--[[
    orientation
    linewise
    register
        name
        (entry)
]]
module.cut = binding.action(function(params)
    local window = vim.api.nvim_get_current_win()
    local selection = kf.get_selection(window)

    do_yank(selection, params.register.name, params.linewise)

    if params.linewise then
        local before = params.orientation.side=="before"
        kf.edit.delete_lines(selection, params.orientation, before)
    else
        kf.edit.delete(selection, params.orientation.boundary)
    end

    selection = kf.set_selection(window, selection)
    kf.scroll_to_focus(window)
end, {fill={"orientation", "register"}})

return module
