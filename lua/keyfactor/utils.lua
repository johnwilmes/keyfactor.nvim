local utils = {}

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

function utils.buffer_less(tuple1, tuple2)
    -- true iff tuple1 comes strictly before tuple2 in the buffer
    if tuple1[1] < tuple2[1] then
        return true
    elseif tuple1[1] == tuple2[1] and tuple1[2] < tuple2[2] then
        return true
    else
        return false
    end
end

return utils
