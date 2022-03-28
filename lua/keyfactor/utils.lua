local utils = {}

local CTRL_V = "\22"
local CTRL_S = "\19"

function utils.is_callable(object)
    if type(object) == "function" then
        return true
    elseif getmetatable(object) and getmetatable(object).__call then
        return true
    end
    return false
end

utils.string = {}
function utils.string.lstrip(s)
    return s:match("^%s*(.*)")
end

function utils.string.lstrip(s)
    return s:match("(.-)%s*$")
end

function utils.string.split_keycodes(s)
    local i = 1
    local a = 0
    local b = 0
    local result = {}
    while i <= #s do
        if a and a < i then
            a,b = s:find('<%w[%w%-]->', i)
        end
        if a==i then
            table.insert(result, s:sub(a,b))
            i = b+1
        else
            table.insert(result, s:sub(i,i))
            i = i+1
        end
    end
    return result
end

utils.table = {}
function utils.table.reverse(t)
    local r = {}
    for k,v in pairs(t) do
        r[v] = k
    end
end

function utils.get_register()
    --[[ Returns the current register, unless the current register is the default register, in
    which case returns nil ]]
    local register = vim.v.register
    if vim.tbl_contains(vim.opt.clipboard:get(), 'unnamedplus') then
        if register == '+' then register = nil end
    elseif vim.tbl_contains(vim.opt.clipboard:get(), 'unnamed') then
        if register == '*' then register = nil end
    else
        if register == '"' then register = nil end
    end
    return register
end

function utils.rowcol_to_byte(tuple, marklike)
    row, col = unpack(tuple)
    if not marklike then
        row = row+1
    end
    return vim.fn.line2byte(row) + col
end

--[[ Move cursor to next position, possibly wrapping to next line ]]
function utils.advance_cursor(window, reverse)
    local whichwrap_reset = vim.opt.whichwrap
    vim.opt.whichwrap = "h,l"
    local to_next = "l" 
    if reverse then
        to_next = "h"
    end
    vim.cmd([[normal! ]]..to_next)
    vim.opt.whichwrap = whichwrap_reset
end

function utils.get_next_position(window, position, reverse)
    -- Gets the next existing (1,0)-indexed cursor position in a window, wrapping to the next line
    -- if necessary. If already at the end of the file, returns the current position
    local cursor_reset = vim.api.nvim_win_get_cursor(window)
    vim.api.nvim_win_set_cursor(window, position)
    utils.advance_cursor(window, reverse)
    result = vim.api.nvim_win_get_cursor(window)
    vim.api.nvim_win_set_cursor(window, cursor_reset)
    return result
end

function utils.position_less(tuple1, tuple2)
    -- true iff tuple1 comes strictly before tuple2 in the buffer
    if tuple1[1] < tuple2[1] then
        return true
    elseif tuple1[1] == tuple2[1] and tuple1[2] < tuple2[2] then
        return true
    else
        return false
    end
end

function utils.position_less_equal(tuple1, tuple2)
    -- true iff tuple1 equals tuple2 or comes before it in the buffer
    return utils.position_less(tuple1, tuple2) or vim.deep_equal(tuple1, tuple2)
end

function utils.range_contains(range1, range2)
    -- true iff range1 contains range2
    return utils.position_less_equal(range1[1], range2[1]) and utils.position_less_equal(range2[2], range1[2])
end

function utils.mapping_encode(key, modifiers)
    local config = require("keyfactor.config")

    modifiers = modifiers or {}
    if modifiers.S and #key == 1 then
        local index , _ = config.unshifted:find(key)
        if index then
            key = config.shifted:sub(index,index)
            modifiers.S = nil
        end
    end

    local sys_encoded = config.system_encode(key, modifiers)
    if sys_encoded then return sys_encoded end
    if vim.tbl_isempty(modifiers) then return key end

    if #key == 1 then
        key = ("<%s>"):format(key)
    end
    for mod, _ in pairs(modifiers) do
        key = ("<%s-%s"):format(mod, key:sub(2))
    end
    return key
end

function utils.mode_in(modes)
    -- valid chars for modes: citnosx
    current = vim.api.nvim_get_mode()["mode"]
    if current:sub(1,2) == 'no' then
        current = 'o'
    elseif (current:sub(1,1) == 'v' or
            current:sub(1,1) == 'V' or
            current:sub(1,1) == CTRL_V) then
        current = 'x'
    elseif (current:sub(1,1) == 's' or
            current:sub(1,1) == 'S' or
            current:sub(1,1) == CTRL_S) then
        current = 's'
    else
        current = current:sub(1,1)
    end
    if modes:find(current) then
        return true
    end
    return false
end

local motion_types = {
    char = {visual_mode='v', select_mode='s'},
    line = {visual_mode='V', select_mode='S'},
    block = {visual_mode=CTRL_V, select_mode=CTRL_S},
}
for name, obj in pairs(motion_types) do
    obj.name = name
end

local function motion_type_from_string(s)
    for name, obj in pairs(motion_types) do
        if s == name or s == name:sub(1,1) or s == obj.visual_mode or s == obj.select_mode then
            return obj
        end
    end
    error("Unrecognized motion type")
end

local function motion_type_from_mode()
    local mode = vim.api.nvim_get_mode()["mode"]
    if mode:sub(1,2) == 'no' then
        return module.motion_type.from_string(mode:sub(3,3))
    else
        return module.motion_type.from_string(mode:sub(1,1))
    end
end

function utils.get_motion_type(s)
    if s then
        return motion_type_from_string(s)
    else
        return motion_type_from_mode()
    end
end

function utils.exit_visual()
    if utils.mode_in('x') then
        vim.cmd('normal! '..utils.get_motion_type().visual_mode)
    end
end

function utils.operate(operator, left, right, motion_type, count, register, remap)
    local visual_start = vim.api.nvim_buf_get_mark(0, '<')
    local visual_end = vim.api.nvim_buf_get_mark(0, '>')

    vim.api.nvim_buf_set_mark(0, '[', left[1], left[2], {})
    vim.api.nvim_buf_set_mark(0, ']', right[1], right[2], {})
    if remap or (operator:lower():sub(1, #'<plug>') == '<plug>') then
        remap = ''
    else
        remap = '!'
    end
    if motion_type.name == 'block' then
        motion_type = '<C-v>'
    else
        motion_type = motion_type.visual_mode
    end
    if count then
        count = tostring(count)
    else
        count = ''
    end
    if register then
        register = '"'..register
    else
        register = ''
    end

    local cmd = [[normal%s %s<Cmd>normal! %s`[o`]%s%s<CR>]]
    cmd = cmd:format(remap, operator, motion_type, count, register)
    cmd = vim.api.nvim_replace_termcodes(cmd, true, true, true)
    vim.cmd(cmd)

    vim.api.nvim_buf_set_mark(0, '<', visual_start[1], visual_start[2], {})
    vim.api.nvim_buf_set_mark(0, '>', visual_end[1], visual_end[2], {})
end

return utils
