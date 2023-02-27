local module = {}
local kf = require("keyfactor.api")
local binding = require("keyfactor.binding")

local insert_modes = {}

local function clear_inactive_inserts(active)
    while #active > 0 and not active[#active]:is_active() do
        active[#active]=nil
    end
end

local function no_action(selection) return selection end
local orientation_to_target = kf.orientable{"before", "before", "inner", "after"}[params.orientation]
local function get_opener(orientation, linewise, preserve)
    local action
    local target = "inner"
    if linewise then
        local before = params.linewise=="before"
        action = function(selection) kf.insert.open(selection, orientation, before, preserve) end
    elseif preserve then
        if preserve~="outer" and not (orientation.boundary=="outer" and orientation.side=="before") then
            target = orientation_to_target[params.orientation]
            action = no_action
        else
            action = function(selection) return selection:reduce_inner(orientation) end
        end
    else
        action = function(selection) return selection:reduce(orientation) end
    end
    return action, target
end

--[[
        params:
            orientation
            linewise - before/ after or true / false or none
            preserve - outer/ all or true / false or none

        if linewise, then truthy preserve equivalent to outer
]]
module.start = binding.action(function(params)
    local frame = kf.get_frame()
    local open_action, target = get_opener(params.orientation, params.linewise, params.preserve)

    local active = utils.table.get_default(insert_modes, frame)
    clear_inactive_inserts(active)

    local mode = frame:get_mode()
    if #active > 0 and mode==active[#active] then
        mode:commit()
        target = mode.target
    else
        mode = InsertMode{reinsert=true, target=target}
        active[#active+1]=mode
        mode:async()
    end

    mode:insert("action", open_action)
end

module.stop = binding.action(function()
    local frame = kf.get_frame()

    local active = utils.table.get_default(insert_modes, frame)
    clear_inactive_inserts(active)
    if #active > 0 then
        local mode = table.remove(active)
        frame:pop_mode(mode)
    end
end)

local function do_insert(value, kind)
    kind = kind or "literal"
    local frame = kf.get_frame()

    clear_inactive_inserts(active)
    local mode = frame:get_mode()
    if #active > 0 and mode==active[#active] then
        mode:insert(value, kind)
    else
        selection = frame:get_selection()
        target = orientation_to_target[params.orientation]
        if kind=="literal" or kind=="vim" then
            selection = kf.insert[action](selection, self.target, value)
        else -- kind=="action"
            selection = value(selection, self.target)
        end
        frame:set_selection(selection)
    end
end

module.indent = binding.action(function() do_insert("\t", "vim") end)
module.linebreak = binding.action(function() do_insert("\n", "vim") end)

local bs = vim.api.nvim_replace_termcodes("<bs>", true, true, true)
local del = vim.api.nvim_replace_termcodes("<del>", true, true, true)
local function delete_textobject(params)
end
module.delete = binding.action(function(params)
    if not params.textobject then
        local char = (params.reverse and bs) or del
        do_insert(char, "vim")
    else
        do_insert(delete_textobject, "action")
    end
end)

local function text(params)
    if type(params.text)~="string" then
        --TODO error
    end
    do_insert(params.text, "literal")
end

return binding.action(text, {index=module})
