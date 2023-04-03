local function reset_tab(tab)
    local windows = vim.api.nvim_tabpage_list_wins(tab)
    return vim.api.nvim_win_call(windows[1], function()
        utils.vim.noautocmd(function()
            vim.cmd("botright new")
            local base_win = vim.api.nvim_get_current_win()
            local new_buf = vim.api.nvim_get_current_buf()
            vim.api.nvim_win_set_buf(base_win, kf.get_null_buffer())
            vim.api.nvim_buf_delete(new_buf, {force=true})

            for _,w, in ipairs(windows) do
                vim.api.nvim_win_close(w, true)
            end
            return base_win
        end)
    end)
end

local function fix_layout(current, target, modes)
    if #current~=#target+1 then
        -- 1. produce a normal "base" window
        local windows = utils.list.filter(vim.tbl_flatten(current), function(x)
            return type(x)=="number"
        end)
        local base_win
        for i=1,#windows do
            local win = windows[i]
            if vim.fn.win_gettype(win)=="" then
                base_win=win
                break
            end
        end
        if not base_win then
            -- no extant normal window, so make one via split
            vim.api.nvim_set_current_win(windows[1])
            vim.cmd("split")
            base_win=vim.api.nvim_get_current_win()
        end
        -- 2. close everything under `current` except for the base window
        for _,win in ipairs(windows) do
            if win~=base_win then
                vim.api.nvim_win_hide(win)
            end
        end
        -- 3. split the base window to the cardinality of target
        --    update `current` to match resulting structure
        if target.split then
            current = {(target.split=="vertical" and "row") or "col", {"leaf", base_win}}
            for i=#target-1 do
                vim.cmd(target.split.." rightbelow split")
                current[i+2] = {"leaf", vim.api.nvim_get_current_win()}
            end
        else
            current = {"leaf", base_win}
        end
    end

    if not layout.split then
        local mode = layout[1]
        assert(current[1]=="leaf")
        local record = modes[mode]
        assert(record and record.window==nil)
        record.window = current[2]
        record.stale = true
    else
        for i,w in ipairs(target) do
            fix_layout(current[i+1], target[i], modes)
        end
    end
end

local Page = utils.class()

function Page:__init(opts)
    self._layout = opts.layout -- TODO or default layout
end

function Page:__gc()
    --TODO
end

function Page:_start(tab)
    assert(not self._tab, "page is already started")
    assert(self==kf.get_page(tab), "inconsistent page state")
    self._tab = tab
    reset_tab(tab)
    self._layout:resize(vim.go.columns, vim.go.lines)--TODO notify layout of page dimensions
    self._is_drawn = false
    self._autocmds = {vim.api.nvim_create_autocmd("VimResize", {callback=function()
        self._layout:resize(vim.go.columns, vim.go.lines)
        self._is_layout_stale = true
    end})}
end

function Page:_stop(tab)
    assert(self._tab, "already stopped")
    assert(tab==self._tab, "inconsistent tabpage")
    assert(not kf.get_page(self), "inconsistent page state")
    reset_tab(tab)
    self._tab = nil
    self._base_win = nil
    for mode,_ in pairs(self._modes) do
        self:_remove_mode(mode)
    end
    for _,handle in ipairs(self._autocmds) do
        pcall(vim.api.nvim_del_autocmd, handle)
    end
    self._autocmds = {}
end

function Page:_add_mode(params)
    assert(self._tab, "page is not started")
    local mode = params.mode
    self._layout:add_mode(mode, params)
    self._is_layout_stale = true
end

function Page:_remove_mode(params)
    local mode = params.mode
    if self._modes[mode] then
        mode.view:clear()
        self._layout:remove_mode(mode)
        self._modes[mode] = nil
        self._is_layout_stale = true
    end
end

function Page:get_window(mode)
    local record = self._modes[mode]
    if record then
        return record.window, not self._is_layout_stale
    end
    return nil, false
end

function Page:reposition(mode, placement)
    if not self._modes[mode] then
        error("invalid mode")
    end
    mode.view:clear()
    self._layout:remove_mode(mode)
    self._layout:add_mode(mode, placement)
    self._is_layout_stale = true
end

function Page:clear()
    if self._is_drawn then
        for mode,record in pairs(self._modes) do
            mode.view:clear()
            record.stale = true
        end
        self._is_drawn = false
    end
end

function Page:draw()
    utils.vim.noautocmd(function()
        -- Display tabpage
        vim.api.nvim_set_current_tabpage(self._tab)

        -- Window layout
        -- Use WinClosed/WinNew events, and mode add/remove calls to notice when layout is stale
        if self._is_layout_stale then
            if #self._modes > 0 then
                local current = vim.fn.winlayout(vim.api.nvim_tabpage_get_number(self._tab))
                local target = self._layout:get_splits()
                for _,record in pairs(self._modes) do
                    record.window = nil
                end
                fix_layout(current, target, self._modes)
            else
                reset_tab(self._tab)
            end
            self._is_layout_stale = nil
        end

        -- Window sizes
        -- Can't rely on WinScrolled events for window resizing, since they only trigger once the
        -- window has focus, so need to check every window
        local size_stale = {}
        local sizes = self._layout:get_sizes()
        for mode,record in pairs(self._modes) do
            local window = record.window
            local height = vim.api.nvim_win_get_height(window)
            local width = vim.api.nvim_win_get_width(window)
            if (sizes[mode].height~=height or sizes[mode].width~=width) then
                size_stale[#size_stale+1]=record
                vim.api.nvim_win_option(window, "winfixwidth", false)
                vim.api.nvim_win_option(window, "winfixheight", false)
            else
                vim.api.nvim_win_option(window, "winfixwidth", true)
                vim.api.nvim_win_option(window, "winfixheight", true)
            end
        end
        for _,record in ipairs(stale_size) do 
            vim.api.nvim_win_set_width(record.window, sizes[record.mode].width)
            vim.api.nvim_win_set_height(record.window, sizes[record.mode].height)
            vim.api.nvim_win_option(window, "winfixwidth", true)
            vim.api.nvim_win_option(window, "winfixheight", true)
        end

        -- Draw each mode
        for mode,record in pairs(self._modes) do
            local view = mode.view
            local window = record.window
            view:draw(window)
        end

        -- Set focus window
        local mode = kf.mode.get_mode(self)
        local record = self._modes[mode]
        if record then
            vim.api.nvim_set_current_win(record.window)
        end

        self._is_drawn = true
    end)
end

function TallPage:__gc()
end
