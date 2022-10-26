local module

local target_position = {before=2, inner=3, after=4}

-- insert individual operations (insert text/indent/line break/delete) work on selections, but
--      user-facing actions take windows
-- insert mode operates on windows

-- TODO listen for buffer changes within active windows, and stop insert mode if that happens

--[[
variants:
    - truncate existing selection to new insertion
    - convert old selection to outer, new insertion is inner 
    - append, preserving existing selection
        - new insertion is outer, at positions 2 and 4, or new insertion is inner at position 3

keep_selection=falsey/truthy/"append"
    - falsey = truncate to insert
    - truthy
        convert existing to outer, insert becomes inner
    - append - only valid if orientation gives positions 2/3/4 - insert appends to
        left outer/inner/right outer - and only valid if linewise=false

for linewise, truncate makes the most sense, but could do convert to outer
    - reverse param might be reasonable for linewise
--]]

function module.open(selection, orientation, before, preserve)
    local out_ranges = {}
    local open_line
    if before then
        -- "\8" is backspace; type a and delete to preserve indent
        open_line = "normal! Oa\8"
    else
        open_line = "normal! oa\8"
    end
    vim.api.nvim_buf_call(selection.buffer, function()
        local view = vim.fn.winsaveview()
        for idx, range in selection:iter() do
            local bounds = {}
            local pos = range[orientation]
            vim.api.nvim_win_set_cursor(0, {pos[1]+1, 0})
            vim.cmd(open_line)
            local line = vim.fn.line(".")-1
            pos = kf.position{line, vim.fn.col(".")-1}
            bounds = {kf.position{line, 0}, pos, pos, pos}
            if preserve then
                bounds[1] = utils.min(range[1], bounds[1])
                bounds[4] = utils.max(range[4], bounds[4])
            end
            out_ranges[idx]={kf.range(bounds)}
        end
        vim.fn.winrestview(view)
    end)

    return selection:get_child(out_ranges)
end

--[[ target: "inner", "before", or "after" ]]
function module.literal(selection, target, value)
    local lines = vim.split(value, "\n")
    for idx, range in selection:iter() do
        local gravity = kf.selection.active_gravity[target]
        selection:set_gravity(sel_idx, gravity)
        local pos = range[target_position[target]]
        vim.api.nvim_buf_set_text(selection.buffer, pos[1], pos[2], pos[1], pos[2], lines)
    end
    return selection
end

-- TODO support some variant of 'backspace' not containing "start";
--      e.g., can delete base start of current range, or can't delete past any earlier ranges
function module.vim(selection, target, value)
    -- TODO make sure "start" is in backspace

    vim.api.nvim_buf_call(selection.buffer, function()
        local view = vim.fn.winsaveview()
        for idx, range in selection:iter() do
            local gravity = kf.selection.active_gravity[target]
            selection:set_gravity(sel_idx, gravity)
            local pos = range[target_position[target]]
            if pos[2]==0 then
                vim.api.nvim_win_set_cursor(0, {pos[1]+1, pos[2]})
                vim.cmd("normal! i"..value)
            else
                vim.api.nvim_win_set_cursor(0, {pos[1]+1, pos[2]-1})
                vim.cmd("normal! a"..value)
            end
        end
        vim.fn.winrestview(view)
    end)
    return selection
end

return module
