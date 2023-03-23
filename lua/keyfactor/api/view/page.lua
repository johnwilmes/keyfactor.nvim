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

local function do_layout(layout, windows, win)
    vim.api.nvim_set_current_win(win)
    if not (layout.mode or (layout.orientation and layout[1] and layout[2])) then
        return
    end
    if layout.mode then
        local record = {window=win, mode=layout.mode}
        windows[layout.mode] = record
        windows[win] = record
        return
    end
    local split = {win}
    for i=2,#split do
        vim.cmd(layout.orientation.." split")
        split[i]=vim.api.nvim_get_current_win()
    end
    for i,w in ipairs(split) do
        do_layout(layout[i], windows, w)
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
    self._base_win = reset_tab(tab)
    self._is_tabpage_stale = true
    self._layout.resize()--TODO
    self._modes = {}

    -- TODO start listening for window events
end

function Page:_stop(tab)
    assert(self._tab, "already stopped")
    assert(tab==self._tab, "inconsistent tabpage")
    assert(not kf.get_page(self), "inconsistent page state")
    reset_tab(tab)
    self._tab = nil
    self._base_win = nil
    self._windows = nil
end

function Page:_add_mode(params)
    assert(self._tab, "page is not started")
    local mode = params.mode
    self._layout.add_mode(mode, params)
    self._is_layout_stale = true
    self._is_mode_stale = {}
end

function Page:_remove_mode(params)
    local mode = params.mode
    if self._windows[mode] then
        mode.view:clear()
        self._windows[mode] = nil
        self._layout.remove_mode(mode)
        self._is_layout_stale = true
        self._is_mode_stale[mode]=nil
    end
end

function Page:clear()
    for _,mode in ipairs(kf.page.get_attached_modes(self)) do
        mode.view:clear()
        self._is_mode_stale[mode]=true
    end
end

function Page:draw()
    utils.vim.noautocmd(function()
        if self._is_tabpage_stale then
            vim.api.nvim_set_current_tabpage(self._tab)
        end
        local modes = kf.get_attached_modes(self)
        -- TODO handle mismatch between get_attached_modes and added modes?
        if self._is_layout_stale then
            self._base_win = reset_tab(self._tab)
            if #modes>0 then
                self._windows = {}
                local layout = self._layout:get_splits()
                do_layout(layout, self._windows, self._base_win)
                self._base_win = nil
            end
            self._is_layout_stale = nil
            self._is_size_stale = true
        end
        if self._is_size_stale then
            local sizes = self._layout:get_sizes()
            for win,_ in self._windows do
                if type(win)=="number" then
                    vim.api.nvim_win_option(win, "winfixwidth", false)
                    vim.api.nvim_win_option(win, "winfixheight", false)
                end
            end
            for win,record in self._windows do
                if type(win)=="number" then
                    local mode = record.mode
                    self._is_mode_stale[mode]=true
                    local s = sizes[mode]
                    if s then
                        vim.api.nvim_set_current_win(win)
                        vim.call("vertical resize "..s.width) -- yes, vertical resize changes width
                        vim.call("horizontal resize "..s.height)
                        vim.api.nvim_win_option(win, "winfixwidth", true)
                        vim.api.nvim_win_option(win, "winfixheight", true)
                    end
                end
            end
            self._is_size_stale = nil
            self._is_focus_stale = true
        end
        for mode,_ in pairs(self._is_mode_stale) do
            local win = self._windows[mode].window
            local view = mode.view
            -- TODO validate
            vim.api.nvim_win_set_buf(win, view.buffer)
            -- TODO set view.viewport
            -- TODO set view.options?
            -- TODO set view.config style options?
            view:draw(win)
            self._is_mode_stale[mode]=nil
        end
        if self._is_focus_stale then
            local mode = kf.mode.get_mode(self)
            if mode then
                vim.api.nvim_set_current_win(self._windows[mode].window)
            end
            self._is_focus_stale = nil
        end
    end)
end

function TallPage:__gc()
end
