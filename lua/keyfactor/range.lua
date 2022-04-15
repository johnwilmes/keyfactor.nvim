--[[ Everything here is (0,0)-indexed ]]

local kf = require("keyfactor.base")

local module = {}

module.boundary = {inner = {}, outer = {}, focus = {}, all = {}}

module.range = {focus_index = 3}
local range_mt = {__index = module.range}

function module.range:new(obj)
    if #obj ~=1 and #obj ~=2 and #obj ~=4 then
        error("Invalid range construction")
    end
    if #obj == 1 then
        obj[1], obj[2] = obj[1], obj[1]
    end
    if #obj == 2 then
        obj[1], obj[2], obj[3], obj[4] = obj[1], obj[1], obj[2], obj[2]
    end
    setmetatable(obj, range_mt)
    return obj
end

function module.range:get_focus()
    return self[self.focus_index]
end

function module.range:default_boundary()
    if (self.focus_index == 1) or (self.focus_index == 4) then
        return module.boundary.outer
    else
        return module.boundary.inner
    end
end

function module.range:reduce(boundary, linewise)
    return self:new{focus_index=self.focus_index, self:get_bounds(boundary, linewise)}
end

function module.range:get_bounds(boundary, linewise)
    local result
    if boundary == module.boundary.focus then
        local f = self:get_focus()
        result = {f, f}
    elseif boundary == module.boundary.outer then
        result = {self[1], self[4]}
    elseif boundary == module.boundary.inner then
        result = {self[2], self[3]}
    else
        return self:get_targets(self:default_boundary(), linewise)
    end
    if linewise then
        result[1] = {result[1][1], 0}
        result[2] = {result[2][1], 0}
    end
    return result
end

--[[
    Params: boundary (in module.boundary)
            exterior, reverse (both boolean)
--]]
function module.range:augment(delta, params)
    params = params or {}
    local result = {focus_index=self.focus_index}

    delta = delta:reduce(params.boundary)

    if params.exterior then
        delta = {delta[4], delta[3], delta[2], delta[1]}
    end

    if params.reverse then
        result = {delta[1], delta[2]}
    else
        result = {delta[4], delta[3]}
    end

    if self.focus_index < 3 then
        result[3], result[4] = self[3], self[4]
        if utils.position_less(result[3], result[2]) then
            -- contracted beyond focus; focus is now on opposite side
            result.focus_index = 5 - result.focus_index
        end
    else
        result[3], result[4] = self[2], self[1]
        if utils.position_less(result[2], result[3]) then
            -- contracted beyond focus; focus is now on opposite side
            result.focus_index = 5 - result.focus_index
        end
    end

    table.sort(result, utils.position_less)
    return self:new(result)
end

module.multirange = {}
local multirange_mt = {__index = module.multirange}

function module.multirange:new(obj)
    obj = obj or {}
    setmetatable(obj, multirange_mt)
    return obj
end

function module.multirange:merge(boundary, linewise)
    if #self == 0 then
        return self
    end

    local head = self[1]
    local sorted = vim.deepcopy(self) -- directly edit elements below
    utils.sort_ranges(sorted, {boundary=boundary, linewise=linewsie})

    local result = {}
    local current = sorted[1]
    local _, right = current:get_bounds(boundary, linewise)
    if (boundary == module.boundary.focus) or linewise then
        right = {right[1], right[2]+1}
    end
    for _, range in ipairs(rounded) do
        local left, _ = range:get_bounds(boundary, linewise)
        if utils.position_less(new_left, right) then
            -- deep copied above so safe to edit current directly
            if utils.position_less(current[3], range[3]) then
                current[3] = range[3]
            end
            if utils.position_less(current[4], range[4]) then
                current[4] = range[4]
            end
        else
            table.insert(result, current)
            current = range
            _, right = current:get_bounds(boundary, linewise)
            if (boundary == module.boundary.focus) or linewise then
                right = {right[1], right[2]+1}
            end
        end
    end

    return self:new(result)
end


--[[
    TODO this should actually be per WINDOW+buffer
--]]
module.extrange = {}
local extrange_mt = {__index = module.extrange}

function module.extrange:new(buffer, namespace, range, style)
    style = style or {}
    local obj = {buffer = buffer, namespace = namespace, style=style}
    setmetatable(obj, extrange_mt)
    obj:update(range)
    return obj
end

function module.extrange:as_range()
    if self.deleted then
        return nil
    end
    local inner_row, inner_col, inner_details = vim.api.nvim_buf_get_extmark_by_id(self.buffer,
        self.namespace, self.inner, {details=true})
    local outer_row, outer_col, outer_details = vim.api.nvim_buf_get_extmark_by_id(self.buffer,
        self.namespace, self.outer, {details=true})
    return module.range:new({focus_index=self.focus_index, 
        {outer_row, outer_col}, {inner_row, inner_col},
        {inner_details.end_row, inner_details.end_col},
        {outer_details.end_row, outer_details.end_col}})
end

function module.extrange:update(range, style)
    style = style or self.style
    self.outer = vim.api.nvim_buf_set_extmark(self.buffer, self.namespace,
        range[1][1], range[1][2],
        {id=self.outer, hl_group=style.outer, end_row=range[4][1], end_col=range[4][2]})
    self.inner = vim.api.nvim_buf_set_extmark(self.buffer, self.namespace,
        range[2][1], range[2][2],
        {id=self.inner, hl_group=style.inner, end_row=range[3][1], end_col=range[3][2]})
    self.focus_index = range.focus_index
    local focus = range:get_focus()
    self.focus = vim.api.nvim_buf_set_extmark(buffer, namespace, focus[1], focus[2],
        {id=self.focus})
end

function module.extrange:delete()
    if not self.deleted then
        vim.api.nvim_buf_del_extmark(self.buffer, self.namespace, self.inner)
        vim.api.nvim_buf_del_extmark(self.buffer, self.namespace, self.outer)
        vim.api.nvim_buf_del_extmark(self.buffer, self.namespace, self.focus)
        self.deleted = true
    end
end

module.selection = {style = {
                        inner = {hl_group='KeyfactorSelectionInner', priority=1010},
                        outer = {hl_group='KeyfactorSelectionOuter', priority=1000},
                        focus = {priority=1020},
                    }, active_style = {
                        inner = {hl_group='KeyfactorActiveInner', priority=1060},
                        outer = {hl_group='KeyfactorActiveOuter', priority=1050},
                        focus = {priority=1070},
                    }}

local selection_mt = {__index = module.selection}

--[[
    Implemented as linked list, so that rotate can reliably visit all ranges even with heavy
    overlap
--]]


function module.selection:new(buffer, ranges, params)
    params = params or {}
    obj = {buffer = buffer, style = params.style, active_style = params.active_style}
    setmetatable(obj, selection_mt)

    obj.namespace = params.namespace or vim.api.nvim_create_namespace()
    obj.n = 0 -- __len metamethod doesn't work properly until Lua 5.2

    for _, r in ipairs(ranges) do
        obj:add_range(r)
        obj:rotate()
    end

    if obj.n > 0 then
        obj:rotate()
    end
    
    return obj
end

function module.selection:rotate(reverse)
    local new
    if self.head then
        if reverse then
            new = self.head.prev
        else
            new = self.head.next_
        end
        if new ~= self.head then
            new.extrange:update(new.extrange:as_range(), self.active_style)
            self.head.extrange:update(self.head.extrange:as_range(), self.style)
            self.head = new
        end
    end
end

function module.selection:update(range)
    -- update active selection
    if not self.head then
        error("Empty selection")
    else
        self.head.extrange:update(range, self.active_style)
    end
end

function module.selection:iter()
    --[[ primary interface for ops? first design ops ]]
end

function module.selection:as_multirange()
    local multirange = {}
    for extrange in self:iter() do
        table.insert(multirange, extrange:as_range())
    end
    return module.multirange:new(multirange)
end


function module.selection:add(range, before)
    if not self.head then
        self.head = {extrange=module.extrange:new(self.buffer, self.namespace, range, self.active_style)}
        self.head.next_ = self.head
        self.head.prev = self.head
    else
        local new = {extrange=module.extrange:new(self.buffer, self.namespace, range, self.style)}
        if before then
            new.prev = self.head.prev
            new.prev.next_ = new
            new.next_ = self.head
            new.next_.prev = new
        else
            new.next_ = self.head.next_
            new.next_.prev = new
            new.prev = self.head
            new.prev.next_ = new
        end
    end
    self.n = self.n +1
end

function module.selection:remove(reverse)
    if not self.head then
        error("Empty selection")
    elseif self.n == 1 then
        self.head.extrange:delete()
        self.head = nil
        self.n = 0
    else
        local removed = self.head
        self:rotate(reverse)
        if reverse then
            self.head.next_ = removed.next_
            self.head.next_.prev = self.head
        else
            self.head.prev = removed.prev
            self.head.prev.next_ = self.head
        end
        removed.extrange:delete()
        self.n = self.n - 1
    end
end


module.selector = kf.action:new()

module.select_next = module.selector:new()

module.select_all = module.selector:new()

module.select_telescope = module.selector:new()

module.select_hop = module.selector:new()

-- anchor and cursor both point to places between characters

-- selection affects end with the cursor

--[[
    Params:
        selection (current selection)
        textobject

        direction = "forward", "backward", "focus", "reverse focus"
        boundary = "inner", "outer", "both"
        target = "interior", "exterior"

        replace (vs modify) = boolean
]]

function module.select_next:_exec(params)
    local result = {}
    local tobj_params = {reverse = (params.direction == "backward"),
                         outer = (params.boundary ~= "inner"),
                         contain = (params.target ~= "exterior")}
    local tobj_params_nocontain = vim.tbl_extend("force", tobj_params, {contain=false})
    for range in params.selection:iter() do
        local delta = params.textobject:get_next(range:focus(), tobj_params)
        if tobj_params.contain and not delta then
            delta = params.textobject:get_next(range:focus(), tobj_params_nocontain)
        end
        if delta then
            if params.replace then
                range = range:new{focus=focus, unpack(delta)}
            else
                range = range:augment(delta, params)
            end
            table.insert(result, range)
        end
    end
    if #result == 0 then
        -- reuse params.selection
    elseif #result == 1 then
        -- single selection
    else
        -- multiselection
    end
end

--[[
    Params:
        selection
        textobject

        boundary = "inner", "outer", "both"
        target = "interior", "exterior"
        overlap = "any", "outer", "none"

        Note: boundary refers to the submatches. The outer boundary of the original selection is
        ignored, and only the inner portion is searched. If the outer boundary of the original
        selection is desired, the selection should be reduced to its outer boundary before applying
        this operation
--]]

function module.select_all:_exec(params)
    local result = {}
    for range in params.selection:iter() do
        local prev = range
        for match in params.textobject:iter(, params.boundary) do
            if params.target == "exterior" then
            else
                match:reduce(params.boundary)
                table.insert(result, match)
            end
        end
    end
        local delta = params.textobject:get_next(range:focus(), tobj_params)
        if tobj_params.contain and not delta then
            delta = params.textobject:get_next(range:focus(), tobj_params_nocontain)
        end
        if delta then
            if params.replace then
                range = range:new{reversed=(params.direction=="backward"), unpack(delta)}
            else
                range = range:augment(delta, params)
            end
            table.insert(result, range)
        end
    end
    if #result == 0 then
        -- reuse params.selection
    elseif #result == 1 then
        -- single selection
    else
        -- multiselection
    end
end

function module.select_hop:_exec(params)
    -- use hop to get the thing
end

function module.select_telescope:_exec(params)
    -- use telescope to get one or more things
    -- cancel if nothing selected
end


function do_thing(selection)
    --[[
    selection contains the the actual ranges
    apply the actual selection updating logic
    --]]
end



function reduce_selection(range1, range2, params)
end

    local object = params.textobject:get_next
    if params.replace then
        -- replace the current selection with the new one
    else
        -- augment the current selection using the new one
        --
        -- decide if we are expanding or shrinking
        --

        if expanding then
            if not params.exterior then
                try to get object containing cursor (which necessarily expands!)
                if no such object then
                    isntead get first object that starts strictly beyond current range
                end
                new cursor location is after furthest point of object (depending on params.outer)
            else
                get first object that starts strictly beyond current range
                cursor is before nearest point of object
            end
            set cursor
        else -- shrinking
            if not params.exterior then
                try to get object containing cursor (which necessarily contracts!)
                if no such object then
                    instead get first object that starts strictly beyond cursor
                end
                new cursor location is after furthest point of object
            else
                get first object that starts strictly beyond cursor
                cursor is before nearest point of object
            end
            if new cursor position is before anchor then
                update cursor position
            else
                selection gets rotated
                anchor remains the same though?
            end
        end
    end
end




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
