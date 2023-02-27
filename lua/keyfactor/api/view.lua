local module = {}

local is_scheduled = false
local win_to_mode = {}
local mode_to_win = {}
local focus

local namespace = vim.api.nvim_create_namespace("")
-- TODO configurable style
local style = {
    primary = {
        focus = {
            inner = {hl_group='KFSelectionPrimaryFocusInner'},
            outer = {hl_group='KFSelectionPrimaryFocusOuter'},
            empty = {hl_group='KFSelectionPrimaryFocusEmpty'},
        },
        base = {
            inner = {hl_group='KFSelectionPrimaryBaseInner'},
            outer = {hl_group='KFSelectionPrimaryBaseOuter'},
            empty = {hl_group='KFSelectionPrimaryBaseEmpty'},
        },
    },
    secondary = {
        focus = {
            inner = {hl_group='KFSelectionSecondaryFocusInner'},
            outer = {hl_group='KFSelectionSecondaryFocusOuter'},
            empty = {hl_group='KFSelectionSecondaryFocusEmpty'},
        },
        base = {
            inner = {hl_group='KFSelectionSecondaryBaseInner'},
            outer = {hl_group='KFSelectionSecondaryBaseOuter'},
            empty = {hl_group='KFSelectionSecondaryBaseEmpty'},
        },
    },
}

local buffers = {}

local function release_schedule()
    is_scheduled = false
end

local function set_highlight(buffer, ns, range, opts)
    for _,boundary in ipairs{"outer", "inner"} do
        local part = range[boundary]
        local filled = opts[boundary]
        local start_col = part[1][2]
        local end_col = part[2][2]
        if boundary=="inner" and part[1]==part[2] then
            filled = opts.empty
            if start_col==0 then
                if utils.line_length(buffer, part[1][1])==0 then
                    -- nothing on the line, need to add virtual text in order to indicate
                    filled = vim.tbl_extend("force", filled, {
                        virtual_text={{" ", filled.hl_group}},
                        virtual_text_pos="eol",
                    })
                end
            else
                start_col=start_col-1
            end
            end_col = end_col+1
        end
        filled = vim.tbl_extend("force", filled, {
            end_row=part[2][1],
            end_col=end_col,
            strict=false,
        })
        vim.api.nvim_buf_set_extmark(buffer, ns, part[1][1], start_col, filled)
    end
end

local function draw_selection(window, target, is_primary)
    local selection = target.selection
    buffers[selection.buffer] = true
    local focus_idx = selection:get_focus()
    local highlight = style[(is_primary and "primary") or "secondary"]

    for i,range in ipairs(selection:get_all()) do
        local range_highlight = highlight[((i==focus_idx) and "focus") or "base"]
        set_highlight(selection.buffer, namespace, range, range_highlight)
    end
end

local function clear_selections(tabpage)
    for _,w in ipairs(vim.api.nvim_tabpage_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(w)
        if buffers[buf] then
            vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
            buffers[buf]=nil
        end
    end
end


local function redraw()
    local branches = kf.mode.list_branches()

    local seen = {}
    local updates = {}
    local new_focus

    for _,b in ipairs(branches) do
        for i=#b,1,-1 do
            local m =b[i]
            if m.get_targets then
                for _,t in ipairs(m:get_targets() or {}) do
                    -- TODO better validation of t?
                    local w = t.window
                    if w~=0 and vim.api.nvim_win_is_valid(w) then
                        if not new_focus then
                            new_focus = w
                        end
                        if not seen[w] then
                            seen[w]=true
                            updates[#updates]=t
                            local old_m = win_to_mode[w]
                            if old_m then
                                old_m_wins = mode_to_win[old_m]
                                if old_m_wins then old_m_wins[w]=nil end
                            end
                            win_to_mode[w]=m
                            utils.table.set_default(mode_to_win, m)[w]=true
                        end
                    end
                end
            end
        end
    end

    if new_focus and vim.api.nvim_get_current_win()~=new_focus then
        vim.api.nvim_set_current_win(new_focus)
    end

    local old_focus
    if new_focus then
        if new_focus~=focus then
            old_focus=focus
            focus=new_focus
            new_focus=true
        else
            new_focus=false
        end
    end

    -- TODO if using graphics protocol, clear all graphics here

    for _,target in ipairs(updates) do
        check If target represents a change to target.window viewport
        If so change the viewport
        check If target represents a change to selection
            or If target.window is old_focus or focus Then update it
        If so change the selection highlighting
        -- TODO additionally allow modes to provide custom hooks to be called here?
    end

    -- TODO maybe allow for attaching to a hook at this point, for plugins that want to do some
    --  extra direct drawing

    -- we schedule the release instead of just releasing, because any redrawing that is triggered
    -- by the redrawing itself is redundant
    vim.schedule(release_schedule)
end

function module.schedule_redraw()
    if not is_scheduled then
        is_scheduled = true
        kf.mode.lock_schedule(redraw)
    end
end

function module.get_displayed_mode(window)
    local window, is_valid = kf.window(window)
    if is_valid then
        local mode = win_to_mode[window]
        if mode then
            if kf.mode.is_started(mode) then
                return mode
            else
                -- invalid mode, clear out all associations
                for w,_ in pairs(mode_to_win[mode] or {}) do
                    if win_to_mode[w]==mode then win_to_mode[w]=nil end
                end
                mode_to_win[mode]=nil
            end
        end
    end
end

function module.release_windows(mode)
    for w,_ in pairs(mode_to_win[mode] or {}) do
        if win_to_mode[w]==mode then win_to_mode[w]=nil end
    end
    mode_to_win[mode]=nil
end

return module
