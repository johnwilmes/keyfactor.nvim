module = {}

local action = require("keyfactor.actions.base").action

--[[

    register
        name
        depth
        align=top or focus (or bottom?)
        offset= number of steps to rotate from alignment (positive or negative)
        length=larger or smaller or selection or register


--]]
module.paste = action(function(params)
    local paste_after = (params.orientation.side=="right")
    local iter_params = {
        orientation=params.orientation,
        register=params.register,
        -- go from bottom to top when side=="right", so we don't touch ranges before we visit them
        -- useful e.g. for linewise paste when multiple ranges are on the same line
        reverse=paste_after,
    }

    for handle in params.selection:iter(iter_params) do
        local pos = handle.range:read()[params.orientation]
        local inner, outer = handle.register:read()
        if params.linewise then
            local line = pos[1]
            if paste_after then line = line+1 end
            local range = kf.insert_lines(selection.buffer, line, inner, outer)
            handle.range:write(range)
        else
            local range = kf.insert_text(selection.buffer, pos, inner, outer)
            handle.range:write(range)
        end
    end

end, {"selection", "orientation", "register"})


--[[
    TODO:
        - repeat with same register should be no-op?
        - allow to specify alignment?
            (could use shift key to specify focus alignment?)
--]]
local function do_yank(params)
    local iter_params = {
        orientation=params.orientation,
        register=vim.tbl_extend("force", params.register, {length="selection"}),
    }

    for handle in params.selection:iter(iter_params) do
        local inner, outer
        if params.linewise then
            inner, outer = kf.get_lines(selection.buffer, handle.range:read())
        else
            inner, outer = kf.get_text(selection.buffer, handle.range:read())
        end
        if params.orientation.boundary=="inner" then
            handle.register:write({inner=inner})
        else
            handle.register:write({inner=inner, outer=outer})
        end
    end
end

module.yank = action(do_yank, {"selection", "orientation", "register"})

module.delete = action(function(params)
    do_yank(params)

    -- use left side for iteration order, so we guarantee that previously seen ranges started
    -- to left of current range in iteration
    local iter_orientation = {boundary=params.orientation.boundary, side="left"}

    if params.linewise then
        --[[
            First, iterate top to bottom. Compute:
                - (merged) line ranges to delete
                - final locations of shifted ranges
            Then, iterate over merged line ranges (from bottom to top?) and delete
            Then, directly update selection (without iteration)
        --]]
        local output = {} -- location of output ranges
        local merged = {} -- line blocks to delete (translated according to earlier blocks)
        local total = 0 -- total lines deleted in previous blocks
        local prev_right = -1 -- previous endpoint
        local prev_left = -1

        for handle in params.selection:iter{orientation=iter_orientation} do
            local range = handle.range:read()[params.orientation.boundary]
            local left = max(range[1][1]-total, prev_right)
            local right = max(range[2][1]+1-total, prev_right)
            if left==prev then
                merged[#merged][2]=right
            else
                total = total + (prev_right-prev_left)
                prev_left, prev_right = left, right
                merged[#merged+1]={left, right}
            end

            local line = prev_left
            if params.orientation.side=="left" then
                line = max(line-1,0)
            end
            output[handle.range.id] = {kf.range{{line, range[params.orientation.side][2]}}}
        end

        for _,block in ipairs(merged) do
            vim.api.nvim_buf_set_lines(selection.buffer, block[1], block[2], false, {})
        end

        -- TODO we assume that selection is created by setting extmarks using strict=false, or that
        -- the range will otherwise be truncated...
        params.selection:update({ranges=output})
    else
        for handle in params.selection:iter{orientation=iter_orientation} do
            local range = handle.range:read()[params.orientation.boundary]
            local left, right = range[1], range[2]
            if left != right then
                vim.api.nvim_buf_set_text(selection.buffer, left[1], left[2], right[1], right[2], {})
            end
        end
        -- TODO is selection update implicit?
    end
end, {"selection", "orientation", "register"})

module.replace = action(function(params)
    local iter_params = {
        orientation={boundary=params.orientation.boundary, side="left"},
        register=params.register,
    }
    if params.linewise then
        --TODO
    else
        for handle in params.selection:iter(iter_params) do
            local range = handle.range:read()
            if params.orientation.boundary=="inner" then
                range = kf.range(range["inner"])
            end
            local inner, outer = handle.register:read()
            local out_range
            if params.linewise then
                --TODO make sure that the selection extmarks for overlapping ranges end up
                --continuing to overlap; otherwise we will probably need to proceed more carefully
                --as in module.delete
                out_range = kf.replace_lines(selection.buffer, range, inner, outer)
            else
                out_range = kf.replace_text(selection.buffer, range, inner, outer)
            end
            handle.range:write(out_range)
        end
    end
end, {"selection", "orientation", "register"})


do
    local is_valid_align = {top=true, focus=true, bottom=true}
    local is_valid_shape = {larger=true, smaller=true, selection=true, register=true}
    local wring_target = {}

    -- NOTE: wrapped actions are expected to respect scope, selection, and register params
    -- (wring doesn't really make sense for actions that don't respect these...)
    local fill = {"scope", "selection", "register"}

    local wring_capture_mt = {}
    function wring_capture_mt:__call(params)
        local selection = params.selection
        local target = {
            actions=self.actions,
            params=params,
            register=params.register,
            before=selection.id,
        }
        if self.go then
            kf.execute(self.actions, params)
        end
        target.after=selection.id
        -- TODO someday, when we have selection-scoped undo,
        -- this could instead be per-window+buffer
        wring_target[params.buffer] = target
    end

    function do_wring(params)
        local selection = params.selection
        local fallback = params.fallback
        local increment = params.increment
        params = utils.table.delete(params, {"fallback", "increment"})

        local target = wring_target[params.buffer]
        if target and target.after==selection.id then
            --[[

            if any parameters of register have been set to something different, then don't increment
                (name, align, shape, depth, offset)
                -- TODO could have a force_increment parameter to override?
            otherwise, increment only depth OR offset, dependening on params.increment (or stored
            increment value)
            --]]

            local register = vim.deepcopy(params.register or {}) -- new register data to use
            -- validate register and fill by default from target.register
            if not kf.register[register.name] then
                -- TODO we are checking if register.name already exists...
                register.name = target.register.name
            end
            if not is_valid_shape[register.shape] then
                register.shape = target.register.shape
            end
            if not is_valid_align[register.align] then
                register.align = target.register.align
            end
            if not (type(register.depth)=="number" and register.depth >= 0) then
                if register.name==target.register.name then
                    register.depth = target.register.depth
                else
                    register.depth=0
                end
            end
            if type(register.offset)~="number" then
                if (register.name==target.register.name and
                    register.depth==target.register.depth and
                    register.align==target.register.align) then
                    -- only default to old offset if name/depth/alignment have not changed
                    register.offset = target.register.offset
                else
                    register.offset=0
                end
            end

            if vim.deep_equal(register, target.register) then
                if increment=="align" or increment=="offset" then
                    if params.reverse then
                        register.offset=register.offset-1
                    else
                        register.offset=register.offset+1
                    end
                    -- TODO take register.offset modulo register size
                else
                    if params.reverse then
                        register.depth=register.depth-1
                    else
                        register.depth=register.depth+1
                    end
                    -- TODO get max_depth of register (register.name, maybe also current
                    -- scope/buffer/selection can affect register max depth?)
                    --
                    -- truncate register.depth to range [0, max_depth]
                end
            end

            if vim.deep_equal(register, target.register) then
                -- TODO flash error message
            else
                -- TODO undo
                kf.undo{selection=target.before}

                -- TODO is this the right extend?
                params = vim.tbl_deep_extend("force", target.params, params, {register=register})
                kf.execute(target.actions, params)
                
                -- record resulting selection id so that wringing remains valid
                target.after = selection.id
                target.register = register
            end
        elseif fallback then
            kf.execute(fallback, params)
        else
            -- TODO flash error
        end
    end

    module.wring = action(do_wring, fill)
    function module.wring:watch(actions)
        local capture = setmetatable({actions=actions, go=true}, wring_capture_mt)
        return action(capture, fill, self._with)
    end
    function module.wring:set(actions)
        local capture = setmetatable({actions=actions, go=false}, wring_capture_mt)
        return action(capture, fill, self._with)
    end
end

do
    local redo_target = {}
    local redo_target_key = {}

    local redo_capture_mt = {}
    function wring_capture_mt:__call(params)
        local target = params[redo_target_key] or false
        if self.go then
            kf.execute(self.actions, params)
        end
        redo_target[target]={
            actions=self.actions,
            params=params,
        }
    end

    local function do_actions(params)
        local target = redo_target[params[redo_target_key] or false]
        if target then
            params = vim.tbl_deep_extend("force", target.params, params)
            kf.execute(target.actions, params)
        end
    end

    module.redo = action(redo)

    -- TODO allow for scoped redo
    function module.redo:with_namespace(name)
        if name==nil then
            name = {}
        end
        return self:with(let{[redo_target_key]=name})
    end
    function module.redo:watch(actions)
        local capture = setmetatable({actions=actions, go=true}, redo_capture_mt)
        return action(capture,nil,self._with)
    end
    function module.redo:set(actions)
        local capture = setmetatable({actions=actions, go=false}, redo_capture_mt)
        return action(capture,nil,self._with)
    end
end

return module
