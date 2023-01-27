local NormalMode = utils.class(base.Mode)

--[[
EditController tracks a window and buffer (and selection), but does NOT enforce that its window
displays its buffer at any given time. Most edits to a buffer don't depend on the window/viewport,
but for those that do (like, selecting the visible range), the user should use whatever the
viewport would be if the current window were switched to display that buffer
TODO create some utility functions to make this task easier
--]]
local EditController = utils.dataclass{
    channel = {}, -- get is implicitly read raw.focusable, set is implicitly error readonly
    is_active = {},
    is_targetable = {}, -- can target a different buffer
    is_visible = {}, -- the buffer is guaranteed* to be visible in the window
    window = {},
    buffer = {set = function(self, value) self:target{buffer=value} end},
    selection = {set = function(self, value) self:target{selection=value} end},
}

local function retarget_buffer(controller)
    if controller.is_visible then
        if controller.is_targetable then
            controller:target{buffer=vim.api.nvim_win_get_buf(controller.window)}
        else
            controller:stop()
        end
    end
    -- else: we don't care what buffer the window actually displays
end

function EditController:__init(opts)
    local window, valid = kf.get_window(opts.window)
    if not valid then
        error("invalid window")
    end
    self._raw.channel = require("kf.api.events").Observable{source=self}
    self._raw.is_targetable = opts.is_targetable~=false
    self._raw.is_visible = opts.is_visible~=false
    self._raw.window = window

    if opts.buffer and not self._raw.is_visible then
        self._raw.buffer, valid, loaded = kf.get_buffer(opts.buffer)
        if not (loaded and valid) then
            error("invalid buffer")
        end
    else
        self._raw.buffer = vim.api.nvim_win_get_buf(self._raw.window)
    end
    
    if opts.selection then
        self._raw.selection = opts.selection
    else
        -- TODO get default selection for window and buffer?
    end

    self._observer = kf.events.Observer{
        object=self,
        {
            channel=kf.events.get_window_channel(self._raw.window),
            events={
                buffer = retarget_buffer,
                detach = self.stop,
            }
        }
    }
end

function EditController:stop()
    self._observer:stop()
    self._raw.channel:clear()
end

function EditController:target(values)
    local old = {buffer=self.buffer, selection=self.selection}
    local new = utils.shallow_copy(old)

    if values.buffer then
        if not self.is_targetable then
            error("controller does not allow buffer targetting", 2)
        end
        local buffer, valid, loaded = kf.get_buffer(values.buffer)
        if not (loaded and valid) then
            error("buffer is not valid")
        end
        new.buffer = buffer
        new.selection = --TODO get default selection for this buffer/window
    end

    if values.selection then
        if values.selection.buffer ~= new.buffer then
            error("selection belongs to wrong buffer", 2)
        end
        new.selection = values.selection
    end

    for k,v in pairs(new) do
        if old[k]==v then
            old[k]=nil
        else
            self._raw[k] = v
        end
    end
    self.channel:broadcast("target", old)
end



local SelectionView = utils.class()

function SelectionView:__init(opts)
    self.controller = 

    --TODO:
    self._active_focus_highlight =
        {inner = {}, outer = {}, empty = {}}
    self._active_base_highlight
    self._inactive_focus_highlight
    self._inactive_base_highlight

    self._observer = kf.events.Observer{
        object=self,
        {
            channel=self.controller.channel,
            events={
                target=self.redraw,
                self=self.stop,
            },
        }, {
            channel=kf.events.get_window_channel(self.controller.window),
            events={
                focus=self.redraw,
                unfocus=self.redraw,
                unhide=self.redraw,
                hide=self.redraw,
                viewport=self.redraw,
                buffer=self.redraw,
                detach=self.stop,
            },
        },
    }

    self:redraw()
end

local function set_highlight(buffer, namespace, id, range, opts)
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
            id=id,
            end_row=part[2][1],
            end_col=part[2][2],
            strict=false,
        })
        vim.api.nvim_buf_set_extmark(buffer, namespace[boundary], part[1][1], part[1][2], filled)
    end
end

function SelectionView:redraw()
    -- ensure buffer is current
    local buffer = self.controller.buffer
    if buffer~=self._buffer then
        if self._buffer_observer then self._buffer_observer:stop() end
        self._buffer = self.controller.buffer
        self._buffer_observer = kf.events.Observer{
            object=self,
            {
                channel=kf.events.get_buffer_channel(self._buffer),
                events={
                    text=self.redraw,
                },
            },
        }
    end

    local selection = self.controller.selection
    local ranges = selection:get_all()
    local focus_idx = selection:get_focus()

    vim.api.nvim_buf_clear_namespace(selection.buffer, self.namespace.inner, 0, -1)
    vim.api.nvim_buf_clear_namespace(selection.buffer, self.namespace.outer, 0, -1)
    kf.graphics.clear_namespace(self.namespace.graphics)

    local window = self.controller.window
    local tabpage = vim.api.nvim_win_get_tabpage(window)
    if vim.api.nvim_win_get_buf(window)~=buffer or vim.api.nvim_get_current_tabpage()~=tabpage then
        -- buffer or window not currently displayed
        return
    end

    local focus, base
    if self.controller.window == vim.api.nvim_get_current_window() then
        focus = self._active_focus_highlight
        base = self._active_base_highlight
    else
        focus = self._inactive_focus_highlight
        base = self._inactive_base_highlight
    end

    for i,range in ipairs(selection:get_all()) do
        if range[4] >= visible[1] and range[1] <= visible[4] then
            -- part of range is visible in window
            range = range:truncate(visible[1], visible[4])
            local highlight = ((i==focus_idx) and focus) or base
            set_highlight(selection.buffer, self.namespace, i, range, highlight)
            if range[2]==range[3] then
                -- If visible, 
                local col = range[2][2]
                if col==0 then col=1 end
                if 
                local screenpos = vim.fn.screenpos(window, range[2][1], range[2][2])
                -- empty inner
                -- TODO What about wrap?
                -- TODO What about FOLDS?!
                local pos = kf.get_screen_position(window, buffer, range[2])
                local covering = kf.get_windows_at_position(pos)
                local is_covered = false
                for _,w in ipairs(covering) do
                    if w~=window then
                        local z = vim.api.nvim_win_get_config(w).zindex
                        if z >= zindex then
                            is_covered = true
                            break
                        end
                    end
                end
                if not is_covered then
                    kf.graphics.set_cursor(self.namespace.graphics, pos, highlight.cursor)
                end
            end
        end
    end
end

function NormalModeController:yield(mode, details)
    if mode._selection_view then
        mode._selection_view
    -- if selection view is operating, stop it
end

function NormalModeController:resume(mode, details)
end

function NormalModeController:stop(mode, details)
end

local ModeThunk = utils.class()

function ModeThunk:__init(opts)
    self.mode = opts.mode
end

function ModeThunk:__index(key)
    local primary = self.mode:get_windows()
    if key=="window" then
        return primary
    elseif key=="buffer" then
        return vim.api.nvim_win_get_buf(primary)
    else
        return rawget(self, key)
    end
end

function NormalMode:__init(opts)
    -- TODO specify default normal layers...

    local edit = EditController{targetable=(opts.targetable~=false)}
    self.channel:attach(edit, {source=thunk})

    local view = SelectionHighlighter()
    self.channel:attach(view)
    edit.channel:attach(view)

    self.edit = edit
    self.preview = edit
end
    


    local buffer = vim.api.nvim_win_get_buf(self.frame.focus)

    local selection = {
        editable = (opts.editable~=false), -- can edit the buffer
        targetable = (opts.targetable~=false), -- can change which buffer is targeted

        -- optional: used to specify that buffer is visible in this window, so that e.g. the
        -- visible selection can be used
        visible = self.frame.focus,
        buffer = buffer,
        selection = opts.selection, -- if nil, use default/most recent for this frame/+buffer
    }

    self.focus = -- TODO current mode, get focus

    self.selection = SelectionController(selection)
    self.buffer = self.selection.buffer -- controller for the buffer

    if opts.preview then
        self.preview = opts.preview -- TODO validate and convert to positive window id
    end

    self._selection_view = views.SelectionView{selection=self.selection}
end

function NormalMode:start(parents, windows)
    self._selection_view:start()
    utils.super(self).start(self, parents, windows)
end


mode = kf.get_mode()
if mode.edit then
    local selection = mode.edit.selection
    stuff

    mode.edit.selection = selection:get_child(ranges)
end
