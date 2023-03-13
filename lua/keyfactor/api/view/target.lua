local TargetView = utils.class()

local default_style = {
    primary = {
        focus = {
            inner = {hl_group='KFPrimaryTargetFocusInner'},
            outer = {hl_group='KFPrimaryTargetFocusOuter'},
            empty = {hl_group='KFPrimaryTargetFocusEmpty'},
        },
        base = {
            inner = {hl_group='KFPrimaryTargetBaseInner'},
            outer = {hl_group='KFPrimaryTargetBaseOuter'},
            empty = {hl_group='KFPrimaryTargetBaseEmpty'},
        },
    },
    secondary = {
        focus = {
            inner = {hl_group='KFSecondaryTargetFocusInner'},
            outer = {hl_group='KFSecondaryTargetFocusOuter'},
            empty = {hl_group='KFSecondaryTargetFocusEmpty'},
        },
        base = {
            inner = {hl_group='KFSecondaryTargetBaseInner'},
            outer = {hl_group='KFSecondaryTargetBaseOuter'},
            empty = {hl_group='KFSecondaryTargetBaseEmpty'},
        },
    },
}

local function draw_range(window, buffer, ns, range, style)
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

function TargetView:__init(opts)
    -- TODO validate target
    local target = opts.target

    -- TODO validate style
    self.style = opts.style or default_style

    local viewport = {}

    viewport.buffer = target.buffer
    -- from winsaveview:
    -- TODO: right now, view is not window-agnostic; depends on size of window
    --      window-agnostic view would be something like: set cursor position (in buffer), and then
    --      specify where cursor appears as percent of screen height and width (?)
    viewport.view = -- TODO; if not set, get default (for this buffer)?

    -- e.g. wrap:
    viewport.options = -- TODO; if not set, get default?

    -- like nvim_open_win, but with more style options; only as hints to window manager
    viewport.config = -- TODO; if not set, get default?

    viewport.target = target
    -- TODO? viewport.type = "normal"

    self._state = {
        vertical = "primary",
        horizontal = "primary",
        focus = "primary",
    }

    self._viewport = viewport
    self._ns = kf.namespace()

    -- [<window-id>] = {viewport: <name>, current: <boolean>, focus: <boolean>}
    self._windows = {}
    self._buffer = nil -- where we have currently drawn the highlights

    -- TODO attach to target events
    -- TODO attach to buffer events
end

function TargetView:__gc(opts)
    self:clear(utils.table.keys(self._windows))
    -- detach from target events
    -- self._ns namespace object cleans itself up
end

function self:_clear_extmarks()
    if self._buffer then
        vim.api.nvim_buf_clear_namespace(self._buffer, self._ns.id, 0, -1)
    end
end


--[[ viewport: key from self:get()
     window: window id to draw to
     opts: focus: whether to treat this as the focus

    view can assume that generic data from get() is already drawn/set for the window
        (buffer, view, options, config)

    view is responsible for clearing anything previously drawn that is now invalid for that window
    (e.g. graphics protocol stuff) and drawing anything non-generic (e.g., target highlighting)

    view should also update its own `view` value (from get()) to reflect actual window?

--]]
function TargetView:draw(viewport, window, opts)
    if viewport~="primary" then
        return
    end

    vim.api.nvim_win_call(window, function()
        self._viewport.view = vim.fn.winsaveview()
    end)

    self:_clear_extmarks()

    local selection = self._viewport.target:get()
    local style = self.style[(opts.focus and "primary") or "secondary"]
    local focus_idx = selection:get_focus()

    for i,range in ipairs(selection:get_all()) do
        local range_style = style[((i==focus_idx) and "focus") or "base"]
        draw_range(window, selection.buffer, self._ns.id, range, range_style)
    end
    
    self._windows[window] = {viewport: "primary", current=true, focus=not not opts.focus}
    self._buffer = selection.buffer
end

-- windows is list of windows to clear
function TargetView:clear(windows)
    for _,win in ipairs(windows) do
        if self._windows[win] then
            -- self:_clear_graphics(win)
            self._windows[win]=nil
        end
    end
    -- for now, extmark highlighting is buffer-wise instead of window-wise...
    if vim.tbl_isempty(self._windows) then
        self:_clear_extmarks()
    end
end

--[[ which viewport to target for scrolling, which viewport is focus, which windows are clean/dirty
--]]
function TargetView:get_state()
    return vim.tbl_extend("keep", self._state, self._windows)
end

function TargetView:get_viewports()
    return {primary=vim.deepcopy(self._viewport)}
end

function TargetView:set_viewports(values)
    if type(values)~="table" then
        -- TODO error
        error("invalid values")
    end

    if type(values[1])~="table" then
        -- TODO warning
        return
    end

    values = values[1]
    for _,k in ipairs{"view", "options", "config"} do
        if type(values[k])=="table" then
            self._viewport[k] = vim.tbl_extend("force", self._viewport[k], values[k])
        end
    end

    kf.events.enqueue(self, kf.events.view.update)
end

local module = {TargetView=TargetView}
return module
