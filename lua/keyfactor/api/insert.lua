local module

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

function module.initialize(selection, orientation, opts)
    local orientation = params.orientation
    local keep = params.keep_selection
    local selection = params.selection

    local out_ranges = {}
    if params.linewise then
        local open_line
        if params.reverse then
            -- "\8" is backspace; type a and delete to preserve indent
            open_line = "normal! Oa\8"
        else
            open_line = "normal! oa\8"
        end
        vim.api.nvim_win_call(context.active.window, function()
            local view = vim.fn.winsaveview()
            for idx, range in selection:iter{orientation=orientation, reverse=params.reverse} do
                local bounds = {}
                local pos = range[orientation]
                vim.api.nvim_win_set_cursor(0, {pos[1]+1, 0})
                vim.cmd(open_line)
                local line = vim.fn.line(".")-1
                bounds[2] = kf.position{line, 0}
                bounds[3] = kf.position{line, vim.fn.col(".")-1}
                if keep then
                    bounds[1] = utils.min(range[1], bounds[2])
                    bounds[4] = utils.max(range[4], bounds[3])
                else
                    bounds[1]=bounds[2]
                    bounds[4]=bounds[3]
                end
                out_ranges[idx]={kf.range(bounds)}
            end
            vim.fn.winrestview(view)
        end)
    else
        if keep=="append" then
            if orientation.boundary=="outer" and orientation.side=="left" then
                -- can't append to position 1
                keep=true
            end
        end
        if keep~="append" then
            for idx, range in selection:iter() do
                if keep then
                    range = kf.range{range[1], range[orientation], range[orientation], range[4]}
                else
                    range = kf.range{range[orientation]}
                end
                out_ranges[idx]={range}
            end
            orientation = {boundary="inner", side="2"}
        end
    end

    return selection:get_child(out_ranges), orientation
end

function module.literal(selection, orientation, value)
    local lines = vim.split(value, "\n")
    for idx, range in selection:iter() do
        -- gravity is already set to right
        local pos = range[orientation]
        vim.api.nvim_buf_set_text(selection.buffer, pos[1], pos[2], pos[1], pos[2], lines)
    end
    return selection
end

-- TODO support some variant of 'backspace' not containing "start";
--      e.g., can delete base start of current range, or can't delete past any earlier ranges
function module.vim(selection, orientation, value)
    -- TODO make sure "start" is in backspace

    -- TODO need to either ensure virtualedit has onemore or all, or sometimes use a instead of i
    local cmd = "normal! i"..value
    vim.api.nvim_buf_call(selection.buffer, function()
        local view = vim.fn.winsaveview()
        for idx, range in selection:iter() do
            local pos = range[orientation]
            vim.api.nvim_win_set_cursor(0, {pos[1]+1, pos[2]})
            vim.cmd(cmd)
        end
        vim.fn.winrestview(view)
    end)
    return selection
end

return module
