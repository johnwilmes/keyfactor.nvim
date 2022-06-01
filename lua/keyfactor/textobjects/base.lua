local utils = require("keyfactor.utils")
local kf = require("keyfactor.base")

local module = {}

module.textobject = {}

function module.textobject:new(obj)
    obj = obj or {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function module.textobject:get_next(params)
    --[[
        Params:
            buffer
            reverse
            side - 1 or 2
            inner - boolean
            position

        Returns next object. This is the first object whose (side, inner) position is strictly
        beyond position (in forward direction, unless reverse is true)

        Returns nil if no such object. When there are multiple possible next objects, returns all
        of them sorted by increasing size (where size is measured first by inner, if inner is true,
        and then by outer; or vice versa if inner is false)

    --]]
    error("Not implemented")
end

function module.textobject:get_containing(params)
    --[[
        Params:
            buffer
            reverse (boolean)
            inner (boolean)
            [1] left bound
            [2] right bound (default left bound)

        Returns all objects containing region [1,2] (in their inner region if inner is true, else in
        their outer region). 

        Returns nil if no such object. When there are multiple possible containing objects, returns all
        of them sorted first by increasing proximity in the forward position (unless reverse) (for inner/outer
        boundary depending on inner param), then by increasing proximity in reverse position (...),
        then by the same for the other boundary

    --]]
    error("Not implemented")
end


function module.textobject:get_all(params)
    --[[
        Params:
            buffer
            reverse (boolean)
            inner (boolean)
            linewise (boolean)
            [1] left bound
            [2] right bound

        iterates over all objects whose (inner if inner, else outer) portion is entirely contained
        in the region [1, 2] sorted first by increasing left side, then by increasing right side
        (unless reverse, in which case sorted by decreasing right side, then by decreasing left
        side)
    --]]
    error("Not implemented")
end


module.simple_textobject = module.textobject:new()

function module.simple_textobject._get_all(buffer)
    --[[ Return a list of all text objects in this buffer ]]
end

function module.simple_textobject:get_next(params)
    local buffer = params.buffer or 0

    local filter = function(range)
        local a, b = params.position, range:get_position(params.inner, params.side)
        if params.reverse then
            a, b = b, a
        end
        return utils.position_less(a, b)
    end

    local candidates = self:_get_all(buffer)
    candidates = vim.tbl_filter(filter, candidates)
    if not vim.tbl_empty(candidates) then
        require("keyfactor.range").sort(candidates, params)
        return unpack(candidates)
    end
end

function module.simple_textobject:get_containing(params)
    local buffer = params.buffer or 0
    local left_in, right_in = unpack(params)
    right_in = right_in or left_in

    local filter = function(range)
        local left_out, right_out = range:get_bounds(params.inner)
        return utils.position_less_equal(left_out, left_in) and utils.position_less_equal(right_in, right_out)
    end

    local candidates = self:_get_all(buffer)
    candidates = vim.tbl_filter(filter, candidates)
    require("keyfactor.range").sort(candidates, params)
    return unpack(candidates)
end

function module.simple_textobject:get_all(params)
    local buffer = params.buffer or 0
    local result = {}
    local left_out, right_out = unpack(params)
    if params.linewise then
        left_out, right_out = utils.round_to_line(left_out, right_out)
    end

    local filter = function(range)
        local left_in, right_in = range:get_bounds(params.inner, params.linewise)
        return utils.position_less_equal(left_out, left_in) and utils.position_less_equal(right_in, right_out)
    end

    local candidates = self:_get_all(buffer)
    candidates = vim.tbl_filter(filter, candidates)
    vim.list_extend(result, candidates)
    require("keyfactor.range").sort(result, params)
    return unpack(result)
end

module.inline_textobject = module.textobject:new()

function module.inline_textobject._get_line(buffer, line)
    --[[ Return a list of all text objects in this buffer in the specified line ]]
end


function module.inline_textobject:get_next(params)
    local buffer = params.buffer or 0
    local first = params.position[1]
    local last = (reverse and 1) or vim.api.nvim_buf_line_count(buffer)
    local inc = (reverse and -1) or 1

    local filter = function(range)
        local a, b = params.position, range:get_position(params.inner, params.side)
        if params.reverse then
            a, b = b, a
        end
        return utils.position_less(a, b)
    end

    for line=first,last,inc do
        local candidates = self:_get_line(buffer, line)
        candidates = vim.tbl_filter(filter, candidates)
        if not vim.tbl_empty(candidates) then
            require("keyfactor.range").sort(candidates, params)
            return unpack(candidates)
        end
    end
end

function module.inline_textobject:get_containing(params)
    local buffer = params.buffer or 0
    local left_in, right_in = unpack(params)
    right_in = right_in or left_in

    if left_in[1] ~= right_in[1] then
        -- inline textobjects cannot contain a range that spans more than one line
        return nil
    end

    local filter = function(range)
        local left_out, right_out = range:get_bounds(params.inner)
        return utils.position_less_equal(left_out, left_in) and utils.position_less_equal(right_in, right_out)
    end

    local candidates = self:_get_line(buffer, left_in[1])
    candidates = vim.tbl_filter(filter, candidates)
    require("keyfactor.range").sort(candidates, params)
    return unpack(candidates)
end

function module.inline_textobject:get_all(params)
    local buffer = params.buffer or 0
    local result = {}
    local left_out, right_out = unpack(params)
    if params.linewise then
        left_out, right_out = utils.round_to_line(left_out, right_out)
    end

    local filter = function(range)
        local left_in, right_in = range:get_bounds(params.inner, params.linewise)
        return utils.position_less_equal(left_out, left_in) and utils.position_less_equal(right_in, right_out)
    end

    for line = first[1],last[1] do
        local candidates = self:_get_line(buffer, left_in[1])
        candidates = vim.tbl_filter(filter, candidates)
        vim.list_extend(result, candidates)
    end
    require("keyfactor.range").sort(result, params)
    return unpack(result)
end

return module
