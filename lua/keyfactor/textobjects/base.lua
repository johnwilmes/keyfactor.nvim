--[[TODO
-- Handle folds properly?
--]]

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
            reverse
            outer
            containing
            cursor

        Returns next object. If containing is false, this is the first object whose inner (or
        outer, if outer is true) portion is completely beyond cursor (in the forward direction,
        unless reverse is true).  If containing is true, this is the first object containing the
        cursor, ordered by inner/outer endpoint proximity to cursor in the appropriate direction

        Returns nil if no such object. When there are multiple possible next objects, returns all
        of them sorted by increasing size

    --]]
    error("Not implemented")
end

function module.textobject:iter(params)
    --[[
        Params:
            reverse
            outer
            left
            right

        iterates over all objects contained in the region [left, right]
        sorted first by increasing left side, then by increasing right side (unless reverse, in
        which case sorted by decreasing right side, then by decreasing left side)

        we give implementation based on get_next, but it is reasonable to override this with a more
        efficient implementation where possible
    --]]
    error("Not implemented")
end



--[[
-- Motion parameters:
--      reverse
--      outer 
--      near - if textobject and mode=ox, does not skip objects containing cursor. (not near skips
--             such objects). if not textobject, moves to boundary of current object (if not
--             already there) rather than boundary of next object. (so near is like e/b and not
--             near is like w/ge) textobject - for mode=ox, behave as text object rather than motion wrap
--]]

function module.motion:_exec(params)
    --
    -- TODO when mode=xo, handle exclusive/inclusive motions properly?
    --
    -- but probably not the way vim does it

    if utils.mode_in('ox') then
        if (not self.params.textobject) or utils.mode_in('x') then
            self.params.wrap = false
        end
        local left, right = self:range(params)
        if not left then
            return
        end
        if utils.mode_in('o') then
            require('keyfactor.operator')._register_motion(self, params)
            vim.api.nvim_buf_set_mark(0, '[', left[1], left[2], {})
            vim.api.nvim_buf_set_mark(0, ']', right[1], right[2], {})
            local visual_mode
            local mode = vim.api.nvim_get_mode()["mode"]
            if #mode == 3 then
                visual_mode = mode:sub(3,3)
            else
                visual_mode = self.motion_type.visual_mode
            end
            vim.cmd('normal! '..visual_mode..'`[o`]') -- TODO works for ctrl-v?
        else -- mode is 'x'
            -- TODO does this work properly if visual mode is linewise?
            -- TODO this definitely doesn't work properly if visual mode is blockwise
            local visual_start = vim.api.nvim_buf_get_mark(0, '<')
            local visual_end = vim.api.nvim_buf_get_mark(0, '>')
            local start_contract = (not params.reverse) and vim.deep_equal(visual_start, params.cursor)
            local end_contract = params.reverse and vim.deep_equal(visual_end, params.cursor)
            local expand = (not (start_contract or end_contract)) or vim.deep_equal(visual_start, visual_end)

            if params.textobject and (params.count == 0) then
                -- iteratively increase count until motion has an effect
                params.count = 1
                while ((expand and utils.range_contains({visual_start, visual_end}, {left, right})) or
                       (start_contract and (vim.deep_equal(visual_start, right))) or
                       (end_contract and (vim.deep_equal(visual_end, left)))) do
                    params.count = params.count + 1
                    left, right = self:range(params)
                    if not left then
                        return
                    end
                end
            end

            if expand then
                if utils.position_less(left, visual_start) then
                    if not vim.deep_equal(visual_start, params.cursor) then
                        vim.cmd("normal! o")
                    end
                    vim.api.nvim_win_set_cursor(0, left)
                    if not params.reverse then
                        vim.cmd("normal! o")
                    end
                end
                if utils.position_less(visual_end, right) then
                    if not vim.deep_equal(visual_end, params.cursor) then
                        vim.cmd("normal! o")
                    end
                    vim.api.nvim_win_set_cursor(0, right)
                    if params.reverse then
                        vim.cmd("normal! o")
                    end
                end
            elseif start_contract then
                vim.api.nvim_win_set_cursor(0, right)
            else -- end_contract
                vim.api.nvim_win_set_cursor(0, left)
            end
        end
    else -- just a motion, not a selection
        params.textobject = false
        local reverse_pos, pos = self:range(params)
        if not reverse_pos then
            return
        end
        if params.reverse then
            pos = reverse_pos
        end
        if params.jump then
            kf.state:add_jump(pos)
        end
        vim.api.nvim_win_set_cursor(0, pos)
    end

    if params.seek then
        kf.state:set_seek(self, params)
    end
end

function module.motion:range(params)
    --[[
        returns pair left, right where left is the left endpoint (closer to buffer start) of the
        range given by the motion and right is the right endpoint (closer to buffer end)

        If params.textobject is true, the endpoints are the endpoints of the relevant textobject.
        Otherwise, one of the endpoints is equal to params.cursor (the left one iff params.reverse
        is false)
    ]]
    return self:_range(self:_get_params(params))
end

--[[

Tranched Motions

Many motions respect the "buffer order" - moving "forward" should go monotonically toward the end of
the buffer, and vice versa. (Some exceptions: traversing the jump or change list.) For such
motions, it is often simple to produce a list of all possible text objects, giving both endpoints
of both the inner and outer forms. This list can then be used by a `tranched_motion` object to
extract the next cursor position or range, given the current cursor position and motion parameters.

tranched_motion objects should implement the :tranches(params) function, that returns an iterator.
The iterator yields list-like tables (tranches). Each tranche entry is itself a list-like table
with four values:
    { outer_start, inner_start, inner_end, outer_end}
Each value is the pair {row, column} where the corresponding part of the object occurs.

No particular ordering is assumed within tranches. However, separate tranches should respect the
buffer order: in particular, nothing in tranche i+1 should come strictly before (in the order
implied by params) any entry in tranche i.

For non-overlapping text objects, or when params.textobject is false, the ordering is obvious (and
depends only on the value of params.reverse; but it may not be a strict ordering for
overlapping-text objects with params.textobjects false).

For overlapping text objects when params.textobject is true, the following ordering is observed:
- First, any text objects containing the cursor (these can be skipped if params.near is false).
These are ordered first by the relevant textobject endpoint in the *opposite* of the search
direction, with endpoints *farther* from the cursor coming first, and subsequently ordered by the other
relevant textobject endpoint (in search direction), with endpoints *closer* to the cursor coming first.
- Then, any text objects following the cursor. These are ordered first by the relevant textobject
endpoint closer to the cursor, with endpoints close to the cursor coming first, and then by the
other relevant endpoint, with endpoints close to the cursor coming first.

--]]

module.tranched_motion = module.motion:new()

local function tm_bounds(params)
    local left, right = 2, 3
    if params.outer then
        left, right = 1, 4
    end
    return left, right
end


local function tm_targets(params)
    local first, second = tm_bounds(params)
    if params.reverse then
        first, second = second, first
    end
    if not params.textobject then
        if params.near then
            first = second
        else
            second = first
        end
    end
    return first, second
end

local function tm_extract(params, object)
    if params.textobject then
        local left, right = tm_bounds(params)
        return object[left], object[right]
    elseif params.reverse then
        local target, _ = tm_targets(params)
        return object[target], params.cursor
    else
        local target, _ = tm_targets(params)
        return params.cursor, object[target]
    end
end

local function tm_contains(params)
    local left, right = tm_bounds(params)
    return function(object)
        return (utils.position_less_equal(left, params.cursor) and
                utils.position_less_equal(params.cursor, right))
    end
end

local function tm_follows(params)
    first, second = tm_targets(params)

    return function(object)
        local a = params.cursor
        local b = object[first]
        if params.reverse then
            a,b = b,a
        end
        return utils.position_less(a, b)
    end
end

local function tm_order(params)
    first, second = tm_targets(params)

    return function(a, b)
        --[[ true iff a comes before b ]]
        if params.reverse then
            a,b = b,a
        end
        return (utils.position_less(a[first], b[first]) or
                (vim.deep_equal(a[first], b[first]) and utils.position_less(b[second], a[second])))
    end
end

local function tm_unique(params, objects)
    index, _ = tm_targets(params)

    -- objects is assumed to be sorted
    local unique = {}
    local prev
    for _, object in ipairs(objects) do
        if (prev == nil) or (not vim.deep_equal(prev, object[index])) then
            prev = object[index]
            table.insert(unique, object)
        end
    end
    return unique
end

function module.tranched_motion:_range(params)
    local count = 0 -- number of matches passed so far in the correct direction
    -- follows iff subsequent tranches contain only candidates following cursor
    local follows = false

    for candidates in self:tranches() do
        if not follows then
            if params.textobject then
                local contains = vim.tbl_filter(tm_contains(params), candidates)
                table.sort(contains, tm_order(params))
                for _, candidate in ipairs(contains) do
                    count = count+1
                    if count >= params.count then
                        return tm_extract(params, candidate)
                    end
                end
            end
            candidates = vim.tbl_filter(tm_follows(params), candidates)
            if not vim.tbl_isempty(candidates) then
                follows = true
            end
        end
        table.sort(candidates, tm_order(params))
        if not params.textobject then
            candidates = tm_unique(params, candidates)
        end
        for _, candidate in ipairs(candidates) do
            count = count+1
            if count >= params.count then
                return tm_extract(params, candidate)
            end
        end
    end
end

function module.tranched_motion:_tranches(params)
    error("Not implemented")
end

module.definite_motion = module.tranched_motion:new({defaults={seek=false, jump=true}})
function module.definite_motion:_tranches(params)
    local values = self:get_all(params)
    local done = false
    return function()
        if not done then
            done = true
            return values
        end
        return nil
    end
end

module.inline_motion = module.tranched_motion:new({defaults={seek=false, jump=false}})

function module.inline_motion:_tranches(params)
    local last_row = (params.reverse and 1) or vim.api.nvim_buf_line_count(0)
    local inc = (params.reverse and -1) or 1
    local index = params.cursor[1]-inc
    local finished = false
    local wrapped = false

    return function()
        if finished then
            return nil
        end
        index = index+inc
        if index == last_row + inc then
            if params.wrap then
                index = (params.reverse and vim.api.nvim_buf_line_count(0)) or 1
                last_row = params.cursor[1]-inc
                if index == last_row+inc then
                    finished = true
                    return nil
                end
            else
                finished = true
            end
        end

        return self:get_all_in_line(params, index)
    end
end

function module.inline_motion:_get_all_in_line(params, line)
    error("Not implemented")
end

return module
