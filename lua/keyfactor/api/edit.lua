local module = {}

-- ASSUMPTIONS: selections have inner gravity and have disjoint ranges (overlap has length zero)

function module.get_text(range)
end

function module.set_text(range, text)
    -- text.before, text.inner, text.after
    -- parts of text that are nil are left untouched in range
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
function module.paste_lines(selection, orientation, register, before)
    local n_reg = register.length or #register
    if n_reg~=selection.length then
        -- TODO error
    end

    local out_ranges = {}
    local reg_idx = 0
    for sel_idx, range in selection:iter() do
        reg_idx = reg_idx+1
        local pos = range[orientation]
        if before then
            vim.api.nvim_buf_set_lines(selection.buffer, pos[1], pos[1], true, {""})
            pos = kf.position{pos[1], 0}
        else
            vim.api.nvim_buf_set_lines(selection.buffer, pos[1]+1, pos[1]+1, true, {""})
            pos = kf.position{pos[1]+1, 0}
        end
        local text = register[reg_idx]
        local result = module.set_text(kf.range{pos}, text)
        out_ranges[sel_idx]={result}
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

local replace_gravity = {
    inner=kf.orientable{false, true},
    before=kf.orientable{false, true, true, true},
    after=kf.orientable{false, false, false, true},
}

--[[
        target: "inner"/"outer"/"all" (default "all")
            all: replace entire selection with entire register
            inner: replace selection inner with register inner
            outer: replace selection outer with register outer
--]]
function module.replace(selection, register, target)
    local n_reg = register.length or #register
    if n_reg~=selection.length then
        -- TODO error
    end

    if target=="inner" then
        target = {inner=true}
    elseif target=="outer" then
        target = {before=true, after=true}
    else
        target = {inner=true, before=true, after=true}
    end

    local reg_idx = 0
    for sel_idx, range in selection:iter() do
        reg_idx = reg_idx+1
        local text = register[reg_idx]
        --[[
        We always set inner first, to minimize cascading effects on any other existing selections
        with gravity toward this range and having outer touching outer of this range.

        We set gravity before modifying each part of the range, so that the extmarks of this range
        update properly
        --]]
        for _,part_name in ipairs{"inner", "before", "after"} do
            if target[part_name] then
                local part = range[part_name]
                selection:set_gravity(sel_idx, replace_gravity[part_name])
                vim.api.nvim_buf_set_text(selection.buffer,
                    part[1][1], part[1][2],
                    part[2][1], part[2][2],
                    {text[part_name]})
            end
        end
    end
    return selection
end
--

--[[
    this doesn't actually write to register, just returns what would be used for that call
--]]
function module.yank(selection)
    local result = {}
    local origin = {}
    for idx, range in selection:iter() do
        local text = module.get_text(range)
        result[#result+1]=text
        origin[#result]=idx
    end
    return result, origin
end

