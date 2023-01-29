local module = {}




function module.get_visible(window)
    -- outer is start of first line to end of last line in window
    -- inner is start of first column to end of last column
    local window, valid = kf.get_window(window)
    if not valid then
        error("invalid window")
    end
    local buffer = vim.api.nvim_win_get_buf(window)
    local info = vim.fn.getwininfo(window)
    local view = vim.api.nvim_win_call(window, vim.fn.winsaveview)
    local firstline = info.topline-1
    local lastline = info.botline-1
    local bounds = {kf.position{firstline, 0}}

    if wrap then
        --[[ If wrap, then info.botline only tells us the last complete line, and there may be
        --   an additional line partially displayed. 
        --
        --   When firstline==lastline, it also seems difficult to figure out the last actually
        --   displayed character of the line, since characters can variable display width. Could
        --   maybe do binary search with screenpos, but we'll just pretend the whole line is
        --   visible
        --]]
        bounds[2] = kf.position{firstline, view.skipcol}
        -- pcall because screenpos gives error if line number is out of bounds
        local success, screenpos = pcall(vim.fn.screenpos, window, lastline+2, 1) -- lines 1-indexed
        if success and screenpos.row~=0 then
            -- the start of the next line is visible
            lastline=lastline+1
        end
        local lastcol = utils.line_length(buffer, lastline)
        bounds[3] = kf.position{lastline, lastcol}
        bounds[4] = kf.position{lastline, lastcol}
    else
        bounds[2] = kf.position{firstline, math.min(utils.line_length(buffer,firstline), view.leftcol)}
        bounds[3] = kf.position{lastline, math.min(lastcol, view.leftcol+textwidth)}
        local lastcol = utils.line_length(buffer, lastline)
        bounds[4] = kf.position{lastline, lastcol}
    end

    return kf.range(bounds)
end


return module
