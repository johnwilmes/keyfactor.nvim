local utils = {}

local CTRL_V = "\22"
local CTRL_S = "\19"

function utils.lazy_require(module)
    local loaded
    local mt = {}
    function mt:__index(_, k)
        loaded = loaded or require(module)
        mt.__index = function(_,k) return loaded[k] end
        return loaded[k]
    end
    function mt:__newindex(_, k, v)
        loaded = loaded or require(module)
        mt.__newindex = function(_,k,v) loaded[k]=v end
        return loaded[k]
    end
    function mt:__call(_, ...)
        loaded = loaded or require(module)
        mt.__call = function(_,...) return loaded(...) end
        return loaded(...)
    end

    return setmetatable({}, mt)
end

utils.list = utils.lazy_require("keyfactor.utils.list")
utils.string = utils.lazy_require("keyfactor.utils.string")
utils.table = utils.lazy_require("keyfactor.utils.table")

function utils.enum(list)
    local enum = {}
    for i, name in ipairs(list) do
        enum[name] = i
    end
    return enum
end

function utils.is_callable(object)
    if type(object)=="function" then
        return true
    end
    local call = rawget(getmetatable(object) or {}, "__call")
    return type(call)=="function"
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

function utils.round_to_line(...)
    local result = {...}
    for i=1,#result do
        result[i] = {result[i][1], 0}
    end
    return unpack(result)
end

function utils.range_contains(range1, range2)
    -- true iff range1 contains range2
    return utils.position_less_equal(range1[1], range2[1]) and utils.position_less_equal(range2[2], range1[2])
end

--TODO ffi library is a more appropriate way of doing this (ffi.new() makes a cdata that is garbage
--collected, can set the finalizer)
function utils.set_finalizer(obj, finalizer, name)
    name = name or "__gc_proxy" -- TODO magic constant
    local proxy = newproxy(true)
    debug.getmetatable(proxy).__gc = finalizer
    rawset(obj, name, proxy)
end

-- Object model
local oo = require("loop.simple")

local function yieldsupers(topdown, class)
    if class~=nil then
        if topdown then
            yieldsupers(topdown, oo.getsuper(class))
            coroutine.yield(class)
        else
            coroutine.yield(class)
            yieldsupers(topdown, oo.getsuper(class))
        end
    end
end

local function topdown(class)
    return coroutine.wrap(yieldsupers), true, class
end

local function bottomup(class)
    return coroutine.wrap(yieldsupers), false, class
end


local BaseClass = oo.class()
function BaseClass.__new(class, ...)
    local obj = oo.rawnew(class)
    for class in topdown(class) do
        local init = oo.getmember(class, "__init")
        if init ~= nil then init(obj, ...) end
    end
    utils.set_finalizer(obj, BaseClass.__gc)
    return obj
end

function BaseClass:__gc()
    for class in bottomup(oo.getclass(self)) do
        local del = oo.getmember(class, "__del")
        if del ~= nil then del(self) end
    end
end

function utils.class(super)
    super = super or BaseClass
    return oo.class({}, super)
end
function utils.super(obj) return oo.getsuper(oo.getclass(obj)) end

return utils
