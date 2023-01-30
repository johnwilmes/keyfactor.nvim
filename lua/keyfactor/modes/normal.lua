local kf = require("keyfactor.api")

-- TODO move buffer targeting to the mode
-- TODO fix orientation targeting

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
    is_orientable = {}, -- can change orientation
    is_visible = {}, -- the buffer is guaranteed* to be visible in the window

    window = {},
    buffer = {set = function(self, value) self:target{buffer=value} end},
    selection = {set = function(self, value) self:target{selection=value} end},
    orientation = {set = function(self, value) self:target
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
    self.controller = opt.controller
    self.namespace = {
        outer = kf.namespace.create(),
        inner = kf.namespace.create(),
        empty = kf.namespace.create(),
    }

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

function SelectionView:stop()
    if self._buffer then
        for _,ns in pairs(self.namespace) do
            vim.api.nvim_buf_clear_namespace(self._buffer, ns, 0, -1)
        end
        kf.namespace.release(ns)
    end
    self._buffer = nil
    self._observer:stop()
end

local function set_highlight(buffer, namespace, id, range, opts)
    for _,boundary in ipairs{"outer", "inner"} do
        local part = range[boundary]
        local filled = opts[boundary]
        local ns = namespace[boundary]
        local start_col = part[1][2]
        local end_col = part[2][2]
        if boundary=="inner" and part[1]==part[2] then
            filled = opts.empty
            ns = namespace.empty
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
            end_col=end_col,
            strict=false,
        })
        vim.api.nvim_buf_set_extmark(buffer, ns, part[1][1], start_col, filled)
    end
end

function SelectionView:redraw()
    if self._buffer then
        for _,ns in pairs(self.namespace) do
            vim.api.nvim_buf_clear_namespace(self._buffer, ns, 0, -1)
        end
    end
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
        local highlight = ((i==focus_idx) and focus) or base
        set_highlight(selection.buffer, self.namespace, i, range, highlight)
    end
end

local NormalMode = utils.class(kf.mode.Mode)
function NormalMode:__init(opts)
    -- TODO specify default normal layers...

    self._preferred_window = opts.window
    self._targetable = (opts.targetable~=false)
    self._visible = (opts.visible~=false)
    self._observer = kf.events.Observer{
        object=self,
        {
            channel=self.channel,
            events={
                start=self._start,
                stop=self._stop,
                --yield=
                --resume=
            }
        }
    }
end

function NormalMode:_start(opts)
    local window = self._preferred_window or self._primary_window
    self.edit = EditController{
        window=self._primary_window,
        targetable=self._targetable,
        visible=self._visible,
    }
    self._view = SelectionView{controller=self.edit}

    self._controller_observer = kf.events.stop_on_detach(self, self.edit.channel)
end

function NormalMode:_stop(opts)
    self._view:stop()
    self.edit:stop()
    self._controller_observer:stop()
    self._view = nil
    self.edit = nil
    self._controller_observer = nil
    self:stop()
end




local function do_linebreak(controller, count)
    controller:_insert("\n", "vim")
end

local function do_insert_capture(controller, action)
    controller:_insert(action, "action")
end

local InsertController = utils.dataclass{
    multiline = {},
    reinsert = {},
    channel = {},
    orientation = {get=function(self) return vim.deepcopy(self._raw.orientation) end},
}

function InsertController:__init(opts)
    self._edit = opts.edit -- TODO validate

    self._raw.channel = require("kf.api.events").Observable{source=self}

    if opts.multiline~=false then
        self._raw.multiline=true
        rawset(self, "linebreak", do_linebreak)
    else
        self._raw.multiline=false
        -- TODO check that we don't already have more than one line...
        -- TODO nvim_buf_attach and do... something... if get more than one line
    end

    if opts.reinsert then
        self._raw.reinsert = true
        rawset(self, "capture", do_insert_capture)
    else
        self._raw.reinsert = false
    end
        
    local orientation = opts.orientation or -- TODO default
    self._raw.orientation = {boundary=orientation.boundary, side=orientation.side}

    local open_action, target = get_insert_opener(orientation, opts.linewise, opts.preserve)
    do_insert_capture(self, open_action)
end

function InsertController:_insert(value, kind)
    if self._changedtick ~= self._target.changedtick then
        self:commit()
    end

    kind = kind or "literal"
    if kind=="literal" or kind=="vim" then
        self._target.selection = kf.insert[kind](self._target, value)
    else -- kind=="action"
        self._target.selection = value(self._target)
    end
    kf.undo.join(self._target.selection, self._undo_node)

    if self.reinsert then
        local prev = self._history[#self._history]
        if prev and kind==prev.kind and (kind=="literal" or kind=="vim") then
            prev.value = prev.value .. value
        else
            table.insert(self._history, {kind=kind, value=value})
        end
    end
end

function InsertController:commit()
    if self.reinsert then
        self._history = {}
        -- TODO commit reinsert action if nonempty; shoult it be under kf.redo?
    end
    self._undo_node = kf.undo.split(self._target.selection)
    -- TODO stop any observers
    self._raw.channel:clear()
end

function InsertController:insert(value)
    -- TODO validate value (string)
    do_insert(value, "literal")
end

local bs = vim.api.nvim_replace_termcodes("<bs>", true, true, true)
local del = vim.api.nvim_replace_termcodes("<del>", true, true, true)
function InsertController:remove(forward, count)
    count = count or 1
    local char = (forward and del) or bs
    do_insert(count .. char, "vim")
end


local InsertMode = utils.class(NormalMode)
function InsertMode:__init(opts)
    self._targetable=false
    self._visible=true

    --TODO fix default layers
end

function InsertMode:_start()
    self.insert = --TODO
    utils.super(self):_start()
end

function InsertMode:_stop()
    util.super(self):_stop()
end

local TextPromptMode = utils.class(kf.mode.Mode)

function TextPromptMode:__init(opts)

end

function TextPromptMode:_start()
    if not self._preferred_window then
        -- TODO create window
    end
    self.edit = EditController
    self.insert = InsertController{
        -- select_empty
        -- single_line
    }
end

function TextPromptMode:_stop()
end

