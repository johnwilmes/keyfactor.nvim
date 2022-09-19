module = {}

--[[

    register
        name
        offset
        align=top or focus (or bottom?)
        rotate= number of steps to rotate from alignment (positive or negative)
        multiple=larger or smaller or selection or register


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
            local range = kf.insert_lines(buffer, line, inner, outer)
            handle.range:write(range)
        else
            local range = kf.insert_text(buffer, pos, inner, outer)
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
        register=params.register,
    }

    for handle in selection:iter(iter_params) do
        local inner, outer
        if params.linewise then
            inner, outer = kf.get_lines(handle.range:read())
        else
            inner, outer = kf.get_text(handle.range:read())
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
            vim.api.nvim_buf_set_lines(params.buffer, block[1], block[2], false, {})
        end

        -- TODO we assume that selection is created by setting extmarks using strict=false, or that
        -- the range will otherwise be truncated...
        selection:update({ranges=output})
    else
        for handle in selection:iter{orientation=iter_orientation} do
            local range = handle.range:read()[params.orientation.boundary]
            local left, right = range[1], range[2]
            if left != right then
                vim.api.nvim_buf_set_text(params.buffer, left[1], left[2], right[1], right[2], {})
            end
        end
        -- TODO is selection update implicit?
    end
end
