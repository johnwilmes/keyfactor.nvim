module = {}

--[[

    register
        name
        offset
        align=top or focus (or bottom?)
        rotate= number of steps to rotate from alignment (positive or negative)
        length=larger or smaller or selection or register


--]]
module.paste = Operator{"register"}
function module.paste:exec(selection, params)
    local paste_after = (params.orientation.side=="right")
    local iter_params = {
        orientation=params.orientation,
        register=params.register,
        -- go from bottom to top when side=="right", so we don't touch ranges before we visit them
        -- useful e.g. for linewise paste when multiple ranges are on the same line
        reverse=paste_after,
    }

    for handle in selection:iter(iter_params) do
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
end

--[[
    TODO:
        - repeat with same register should be no-op?
        - allow to specify alignment?
            (could use shift key to specify focus alignment?)
--]]
module.yank = Operator{"register"}
function module.yank:exec(selection, params)
    local iter_params = {
        orientation=params.orientation,
        register=vim.tbl_extend("force", params.register, {length="selection"}),
    }

    for handle in selection:iter(iter_params) do
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

module.delete = Operator{"register"}
function module.delete:exec(selection, params)
    module.yank:exec(selection, params)

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

        for handle in selection:iter{orientation=iter_orientation} do
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
        selection:update({ranges=output})
    else
        for handle in selection:iter{orientation=iter_orientation} do
            local range = handle.range:read()[params.orientation.boundary]
            local left, right = range[1], range[2]
            if left != right then
                vim.api.nvim_buf_set_text(selection.buffer, left[1], left[2], right[1], right[2], {})
            end
        end
        -- TODO is selection update implicit?
    end
end

module.replace = Operator{"register"}
function module.replace:exec(selection, params)
    local iter_params = {
        orientation={boundary=params.orientation.boundary, side="left"},
        register=params.register,
    }
    if params.linewise then
        --TODO
    else
        for handle in selection:iter(iter_params) do
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
end

module.wring = Operator()
function module.wring:exec(selection, params)
    --[[
    check if selection corresponds to captured action+prev_params (w/ stored register info)
    if so:
        use register name specified in params, falling back to register stored at capture
        if register name specified in params is overriding a different stored reg name:
            start with offset = 0
        else
            start with stored offset

        let delta = max(1,params.register.offset) * (-1 if params.reverse else +1)

        new_reg = {name=as above, offset=starting offset + delta, align/multiple from params
        falling back to stored}

        set prev_params.register = new_reg

        if any bindings were specified with capture, apply them to action+prev_params
        then exec action+params

        arrange things so that resulting selection continues to correspond to same captured
        action+prev params
    else:
        if _else (or fallback? default_to?) binding(s) were given, apply them to the action
            nil+(current)params

    --]]
end
