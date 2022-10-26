local module = {}

function module.get_range_text(buffer, range)
    -- TODO error if buffer is not loaded
    local result = {}
    for _,part_name in ipairs{"inner", "before", "after"} do
        local part = range[part_name]
        local lines = vim.api.nvim_buf_get_text(buffer,
            part[1][1], part[1][2],
            part[2][1], part[2][2], {})
        result[part_name] = lines
    end
end

function module.get_text(selection)
    local result = {}
    for idx, range in selection:iter() do
        result[#result+1] = module.get_range_text(range)
    end
    return result
end

function module.get_lines(selection)
    local result = {}
    for idx, range in selection:iter() do
        local lines = vim.api.nvim_buf_get_lines(selection.buffer,
            range["outer"][1][1], range["outer"][2][1]+1, true)
        result[#result+1] = {inner=lines, before={""}, after={""}}
    end
    return result
end


--- higher level

--[[
Alignment strategies:
    - repeat shorter register cyclically
        - use a "virtual register" wrapper around a register to repeat it cyclically
    - truncate to register that is shorter than selection (removing ranges)
        - modify selection before/after calling
    - truncate to selection that is shorter than register by ommitting register entries
        - wrap register
    - add empty ranges at end to match longer register
        - modify the selection before calling paste_lines/replace
    - fill register with empty entries ("") to match longer selection
        - wrap register

    - reverse order of register compared to selection
        - if we actually ever needed this, again use a wrapper around the register to implement it
    - offset between register and selection
        - again use a wrapper!

This level of the API does not offer ANY support for different alignment strategies; the functions
REQUIRE that selection and register have equal length

Redundant methods:
    - replace_lines:
        - if this were ever actually wanted, in what way would it be different from delete_lines
        followed by paste_lines?
    - paste
        - equivalent to truncating selection followed by replace
        - replace is slightly more powerful than delete followed by paste, because it allows for
        outer-only replace
    - delete_lines inner only
        - same as truncating inner and then doing delete_lines; and then if you want to use
        whatever outer scraps are left of original selection, you can still use that selection
--]]


--[[
    opts: before (boolean) default false
        - whether the resulting empty range is placed on the previous or following line
]]
function module.paste_lines(selection, orientation, text, before)
    if #text~=selection.length then
        -- TODO error
    end

    local out_ranges = {}
    for idx, range in selection:iter() do
        local pos = range[orientation]
        if before then
            pos = kf.position{pos[1], 0}
        else
            pos = kf.position{pos[1]+1, 0}
        end
        local bounds = {pos}
        local lines = {""}
        for _,part_name in ipairs{"before", "inner", "after"} do
            local part = text[idx][part_name]
            lines[#lines] = lines[#lines]..part[1]
            vim.list_extend(lines, part, 2)
            bounds[#bounds+1] = kf.position{pos[1]+#lines-1, #(lines[#lines])}
        end
        vim.api.nvim_buf_set_lines(selection.buffer, pos[1], pos[1], true, lines)
        out_ranges[idx]={kf.range(bounds)}
    end
    return selection:get_child(out_ranges)
end

--[[

    always deletes outer

    opts: before (boolean)
        - whether the resulting empty range is placed on the previous or following line

        orientation - column of empty range is copied from old range at this orientation
            -defaults to "outer", "before" iff reverse
--]]
function module.delete_lines(selection, orientation, before)
    --[[
        First, iterate top to bottom. Compute:
            - (merged) line ranges to delete
            - final locations of shifted ranges
        Then, iterate over merged line ranges and delete
    --]]
    local out_ranges = {}
    local merged = {} -- line blocks to delete (translated according to earlier blocks)
    local total = 0 -- total lines deleted in previous blocks
    local prev_right = -1 -- previous endpoint
    local prev_left = -1

    local orientation = orientation or {}
    if not orientation.boundary then
        orientation.boundary = "outer"
    end
    if not orientation.side then
        orientation.side = (before and "before") or "after"
    end
    -- TODO validate orientation

    for idx, range in selection:iter() do
        local left = max(range["outer"][1][1]-total, prev_right)
        local right = max(range["outer"][2][1]+1-total, prev_right)
        if left==prev_right then
            merged[#merged][2]=right
        else
            total = total + (prev_right-prev_left)
            prev_left, prev_right = left, right
            merged[#merged+1]={left, right}
        end

        local line = prev_left
        if before then
            line = max(line-1,0)
        end
        out_ranges[idx] = {kf.range{kf.position{line, range[orientation][2]}}}
    end

    for _,block in ipairs(merged) do
        vim.api.nvim_buf_set_lines(selection.buffer, block[1], block[2], false, {})
    end

    return selection:get_child(out_ranges)
end

--[[
    opts:
        boundary "inner"/"outer"; default "outer"
--]]
function module.delete(selection, boundary)
    boundary = boundary or "outer"
    for idx, range in selection:iter() do
        range = range[boundary]
        local before, after = range[1], range[2]
        if before~=after then
            vim.api.nvim_buf_set_text(selection.buffer, before[1], before[2], after[1], after[2], {})
        end
    end
    return selection -- TODO does it need to be refreshed with some call? using extmark positions
end

--[[
        target: "inner"/"outer"/"all" (default "all")
            all: replace entire selection with entire register
            inner: replace selection inner with register inner
            outer: replace selection outer with register outer
--]]
function module.replace(selection, text, target)
    if #text~=selection.length then
        -- TODO error
    end

    if target=="inner" then
        target = {inner=true}
    elseif target=="outer" then
        target = {before=true, after=true}
    else
        target = {inner=true, before=true, after=true}
    end

    for idx, range in selection:iter() do
        --[[
        We always set inner first, to minimize cascading effects on any other existing selections
        with gravity toward this range and having outer touching outer of this range.

        We set gravity before modifying each part of the range, so that the extmarks of this range
        update properly
        --]]
        for _,part_name in ipairs{"inner", "before", "after"} do
            if target[part_name] then
                local part = range[part_name]
                local gravity = kf.selection.active_gravity[part_name]
                selection:set_gravity(sel_idx, gravity)
                vim.api.nvim_buf_set_text(selection.buffer,
                    part[1][1], part[1][2],
                    part[2][1], part[2][2],
                    text[idx][part_name])
            end
        end
    end
    return selection
end

