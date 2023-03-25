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

local function fix_layout(current, target, modes, windows)
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
            vim.api.nvim_set_current_win(windows[1])
            vim.cmd(target.split.." split")
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
        if #target > 1 then
            current = {(target.split=="vertical" and "row") or "col", {"leaf", base_win}}
            for i=#target-1 do
                vim.cmd(target.split.." rightbelow split")
                current[i+2] = {"leaf", vim.api.nvim_get_current_win()}
            end
        else
            current = {"leaf", base_win}
        end
    end

    if layout.mode then
        local win = current[2]
        local record = {window=win, mode=layout.mode, stale={size=true, buffer=true, viewport=true}}
        modes[layout.mode] = record
        windows[win] = record
    else
        for i,w in ipairs(target) do
            fix_layout(current[i+1], target[i], modes, windows)
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
    self._layout.resize()--TODO notify layout of page dimensions
    self._modes = {}
    self._windows = {}

    -- TODO probably these autocmds should be set up once and used for all pages - easier to
    -- dispatch
    self._tab_autocmd = vim.api.nvim_create_autocmd("TabLeave", ...)
    self._layout_autocmd = vim.api.nvim_create_autocmd({"WinClosed", "WinNew"}, {
    })
    self._scroll_autocmd = vim.api.nvim_create_autocmd("WinScrolled", {
    })
    -- TODO start listening for window events
    self._is_tabpage_stale = true
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
        -- Tabpage displayed
        if self._is_tabpage_stale then
            vim.api.nvim_set_current_tabpage(self._tab)
        end

        -- Window layout
        if self._is_layout_stale then
            local current = vim.fn.winlayout(vim.api.nvim_tabpage_get_number(self._tab))
            local target = self._layout:get_splits()
            self._modes = {}
            self._windows = {}
            fix_layout(current, target, self._modes, self._windows)
            self._is_layout_stale = nil
            self._is_focus_stale = true
        end

        -- Window sizes
        local size_stale = {}
        local sizes = self._layout:get_sizes()
        for mode,record in pairs(self._modes) do
            local window = record.window
            local height = vim.api.nvim_win_get_height(window)
            local width = vim.api.nvim_win_get_width(window)
            if record.stale.size and (sizes[mode].height~=height or sizes[mode].width~=width) then
                size_stale[#size_stale]=record
                vim.api.nvim_win_option(window, "winfixwidth", false)
                vim.api.nvim_win_option(window, "winfixheight", false)
            else
                vim.api.nvim_win_option(window, "winfixwidth", true)
                vim.api.nvim_win_option(window, "winfixheight", true)
            end
            record.stale.size = nil
        end
        for _,record in ipairs(stale_size) do 
            vim.api.nvim_win_set_width(record.window, sizes[record.mode].width)
            vim.api.nvim_win_set_height(record.window, sizes[record.mode].height)
            vim.api.nvim_win_option(window, "winfixwidth", true)
            vim.api.nvim_win_option(window, "winfixheight", true)
            record.stale.viewport = true
        end

        -- Window buffer, scrolling, and drawing
        for mode,record in pairs(self._modes) do
            local view = mode.view
            local window = record.window
            if record.stale.buffer then
                vim.api.nvim_win_set_buf(window, view.buffer)
                record.stale.buffer = nil
                record.stale.viewport = true
            end
            if record.stale.viewport then
                vim.api.nvim_win_call(window, function()
                    vim.fn.winrestview(view.viewport)
                end)
                record.stale.viewport = nil
                record.stale.draw = true
            end
            if record.stale.draw then
                view:draw(window)
                record.stale.draw = nil
            end
        end

        -- Set focus window
        if self._is_focus_stale then
            local mode = kf.mode.get_mode(self)
            if mode then
                vim.api.nvim_set_current_win(self._modes[mode].window)
            end
            self._is_focus_stale = nil
        end
    end)
end

function TallPage:__gc()
end
