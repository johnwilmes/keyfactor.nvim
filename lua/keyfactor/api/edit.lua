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
    selection:iter opts:
        orientation - if present, used to order selection; otherwise, selection indices used
        start = "first", "focus", "last"; default "first"
        offset = signed integer, number of steps to rotate alignment; default 0
        reverse = boolean; default false (reverse order of selection, keeping order of register)
]]


--[[
Alignment strategies:

    - truncate to shorter of register/selection
        - this is the only strategy used by paste_lines and replace

    - repeat shorter register cyclically
        - use a "virtual register" wrapper around a register to repeat it cyclically
    - add empty ranges at end to match longer register
        - modify the selection before calling paste_lines/replace

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

        align - table of opts for align_register (can have separate or no orientation)
]]
function module.paste_lines(selection, orientation, register, opts)
    local out_ranges = {}
    local reg_idx = 0
    local n_reg = register.length or #register
    for sel_idx, range in selection:iter(opts.align) do
        reg_idx = reg_idx+1
        if reg_idx > n_reg then break end
        local pos = range[orientation]
        if opts.before then
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
function module.delete_lines(selection, opts)
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

    local orientation = opts.orientation or {}
    if not orientation.boundary then
        orientation.boundary = "outer"
    end
    if not orientation.side then
        orientation.side = (opts.before and "before") or "after"
    end
    -- TODO validate orientation

    -- use before side for iteration order, so we guarantee that previously seen ranges started
    -- before current range in iteration
    for idx, range in selection:iter{orientation={boundary="outer", side="before"}} do
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
        if opts.before then
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
function module.delete(selection, opts)
    -- TODO we assume that selection is created by setting extmarks using strict=false, or that
    -- the range will otherwise be truncated...

    for idx, range in selection:iter() do
        range = range[opts.boundary]
        local left, right = range[1], range[2]
        if left != right then
            vim.api.nvim_buf_set_text(selection.buffer, left[1], left[2], right[1], right[2], {})
        end
    end
    return selection -- TODO does it need to be refreshed with some call? using extmark positions
end

--[[
    opts:
        align - passed to align_register

        
        mode: "inner"/"outer"/"all" (default "all")
            all: replace entire selection with entire register
            inner: replace selection inner with register inner
            outer: replace selection outer with register outer
--]]
function module.replace(selection, register, opts)
    local out_ranges = {}
    local reg_idx = 0
    local n_reg = register.length or #register
    for sel_idx, range in selection:iter(opts.align) do
        reg_idx = reg_idx+1
        if reg_idx > n_reg then break end
        local text = register[reg_idx]
        if mode=="inner" then
            text={inner=text.inner}
        elseif mode=="outer" then
            text={before=text.before, after=text.after}
        end
        local result = module.set_text(range, text)
        out_ranges[sel_idx]={result}
    end
    return selection:get_child(out_ranges)
end
--

--[[
    opts:
        same as for module.align_register
        which I guess is the same as for selection:iter...

    this doesn't actually write to register, just returns what would be used for that call
--]]
function module.yank(selection, opts)
    local result = {}
    local origin = {}
    for idx, range in selection:iter{opts} do
        local text = module.get_text(range)
        result[#result+1]=text
        origin[#result]=idx
    end
    return result, origin
end

