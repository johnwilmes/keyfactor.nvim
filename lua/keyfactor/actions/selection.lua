local kf = require("keyfactor.base")


local module = {}

module.target = {exterior = {}, interior = {}, inner = {}, outer = {}, both = {}, focus = {}}

module.range = {default_focus = 3}

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
    obj.focus = obj.focus or self.default_focus
    setmetatable(obj, module.range)
    return obj
end

function module.range:get_focus()
    return self[self.focus]
end

function module.range:reduce(boundary)
    if target == "both" then
        return self
    elseif target == "focus" then
        return self:new{self:get_focus(), focus=self.focus}
    elseif (target == "outer") or (self.focus == 1) or (self.focus == 4) then
        return self:new{self[1], self[4], focus=self.focus}
    else
        return self:new{self[2], self[3], focus=self.focus}
    end
end

function module.range:augment(delta, params)
    params = params or {}
    local result = {focus=self.focus}

    delta = delta:reduce(params.boundary)

    if params.target == module.target.exterior then
        delta = {delta[4], delta[3], delta[2], delta[1]}
    end

    if params.direction == "backward" then
        result = {delta[1], delta[2]}
    else -- "forward"
        result = {delta[4], delta[3]}
    end

    if self.focus < 3 then
        result[3], result[4] = self[3], self[4]
        if utils.position_less(result[3], result[2]) then
            -- contracted past focus; focus is now on opposite side
            result.focus = 5 - result.focus
        end
    else
        result[3], result[4] = self[2], self[1]
        if utils.position_less(result[2], result[3]) then
            -- contracted past focus; focus is now on opposite side
            result.focus = 5 - result.focus
        end
    end

    table.sort(result, utils.position_less)
    return self:new(result)
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
