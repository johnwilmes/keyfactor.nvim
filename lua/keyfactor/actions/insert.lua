local module = {}
local binding = require("keyfactor.binding")

local orientation_to_target = kf.orientable{"before", "before", "inner", "after"}[params.orientation]
local active = {}

local reinsert_mt = {}
function reinsert_mt:__call()
    local window = vim.api.nvim_get_current_win()
    local selection = kf.get_selection(window)
    local target

    selection, target = open_insert(selection, self.open)
    for _,action in self.actions do
        selection = do_insert_action(selection, target, action.action, action,params)
    end
    kf.set_selection(window, selection)
    kf.scroll_to_focus(window)
end

local function commit(id)
    if kf.options{window=window}.insert.reinsertable then
        local prev_insert = active[id]
        if prev_insert.actions then
            local reinsert = {
                open=prev_insert.open,
                actions=prev_insert.actions,
            }
            -- TODO redo action should also set wring, with wringer changinger redo history index
            -- for insert namespace
            kf.redo.set(setmetatable(reinsert, reinsert_mt), "insert")
            prev_insert.actions = nil
            return true
        end
    end
    return false
end

local function open_insert(selection, params)
    local target = "inner"
    if params.linewise then
        local before = params.linewise=="before"
        selection = kf.insert.open(selection, params.orientation, before, params.preserve)
    elseif params.preserve then
        if params.preserve~="outer" and
            not (params.orientation.boundary=="outer" and params.orientation.side=="before") then

            target = orientation_to_target[params.orientation]
        else
            selection = selection:reduce_inner(orientation)
        end
    else
        selection = selection:reduce(orientation)
    end
    return selection, target
end

local function do_insert_action(selection, target, action, params)
    if type(action)=="string" then
        return kf.insert[action](selection, target, params)
    else
        return action(selection, params)
    end
end

local function do_insert(action, params)
    local window = vim.api.nvim_get_current_win()
    local selection = kf.get_selection(window)
    local undo = kf.get_undo_node(selection.buffer)
    local settings = active[window]
    local target
    if settings then
        target = settings.target
        if selection.id ~= settings.selection then
            commit(window)
        end
    else
        target = orientation_to_target[params.orientation]
    end

    selection = do_insert_action(selection, target, action, params)
    selection = kf.set_selection(window, selection)

    if settings then
        settings.selection=selection.id
        if settings.undo==undo then
            kf.undo_join(undo)
        else
            settings.undo=kf.get_undo_node(selection.buffer)
        end
        local actions = utils.table.set_default(settings, "actions")
        if type(action)=="string" and #actions > 0 and actions[#actions].action==action then
                actions[#actions].params = actions[#actions].params .. params
        else
            actions[#actions+1] = {action=action, params=params}
        end
    end

    kf.scroll_to_focus(window)
end

-------------------

--[[
        params:
            orientation
            linewise - before/ after or true / false or none
            preserve - outer/ all or true / false or none

        if linewise, then truthy preserve equivalent to outer
]]
module.start = binding.action(function(params)
    local window = vim.api.nvim_get_current_win()
    local selection = kf.get_selection(window)
    local layer = kf.options{window=window}.insert.layer -- TODO local options...

    local prev = active[window]
    if prev then
        commit(window)
    end

    local target -- where we will do the inserting: before, inner, after
    selection, target = open_insert(selection, params)

    selection = kf.set_selection(window, selection)
    active[window] = {
        open = params,
        target = target,
        selection = selection.id,
        layer = layer,
        undo = kf.get_undo_node(selection.buffer) -- TODO...
    }

    kf.options{window=window}.insert.layer = true
    -- TODO start listening for changes to buffer of current window, to stop insert?

    kf.scroll_to_focus(window)
end)

module.stop = binding.action(function()
    local window = vim.api.nvim_get_current_win()

    local settings = active[window]
    if not settings then
        return
    end
    commit(window)
    kf.options{window=window}.clear{insert={settings.layer}} -- TODO...
    local active[window]=nil
end)

module.indent = binding.action(function() do_insert("vim", "\t") end)
module.linebreak = binding.action(function() do_insert("vim", "\n") end)

local bs = vim.api.nvim_replace_termcodes("<bs>", true, true, true)
local del = vim.api.nvim_replace_termcodes("<del>", true, true, true)
local function delete_textobject(params)
end
module.delete = binding.action(function(params)
    if not params.textobject then
        local char = (params.reverse and bs) or del
        do_insert("vim", char)
    else
        do_insert(delete_textobject, params)
    end
end)

module.is_active = binding.action(function()
    local window = vim.api.nvim_get_current_win()
    return not not active[window]
end)

local function text(params)
    if type(params.text)~="string" then
        --TODO error
    end
    do_insert("literal", params.text)
end

return binding.action(text, {index=module})
