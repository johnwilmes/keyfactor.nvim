local module = {}

-- TODO ensure that modes appearing in win_to_mode are always active
local win_to_mode = {} -- immediate owner of window, not necessarily the current controller
local primary_window = {} -- mode keys, value is window of primary window
local secondary_windows = {} -- mode keys, value is table of window id keys, boolean (true) values

local mode_child = {}

local function yield_descendants(mode)
    if mode~=nil then
        yield_descendants(mode.child)
        coroutine.yield(mode)
    end
end

local function descendants(mode)
    return coroutine.wrap(yield_descendants), mode
end

local module.Mode = utils.class()

function Mode:__init(opts)
    self.channel = Observable{source=self}

    self.layers = {}
    self._initial_layers = opts.layers or {}
    self._preserve_layers = {}

    self.parent = nil
    self.child = nil
    self._primary_window = nil
    self._secondary_windows = {}
end

function Mode:_initialize_layers()
    if self.parent then
        self.layers = vim.api.tbl_extend("force", self.parent.layers, self._initial_layers)
    else
        self.layers = utils.shallow_copy(self._initial_layers)
    end
    self._preserve_layers = {}
end

--[[
    layers is dictionary with layer_name keys, boolean values

    preserve is boolean; if true, then these layers should be preserved (in this mode's window(s))
    even after stopping this mode and resuming the parent
--]]
function Mode:set_layers(layers, preserve)
    -- TODO validate layers
    self.layers = vim.api.tbl_extend("force", self.layers, layers)

    if preserve then
        self._preserve_layers = vim.api.tbl_extend("force", self._preserve_layers, layers)
    end
end

function Mode:stop()
    local parent = self.parent
    local primary = self._primary_window

    -- stop all descendants, including self
    for _,d in descendants(self) do
        d.child = nil
        if d.parent then
            d.parent.layers = vim.api.tbl_extend("force", d.parent.layers, d._preserve_layers)
            d.parent._preserve_layers = vim.api.tbl_extend("force", d.parent._preserve_layers, d._preserve_layers)
        end
        d.channel:broadcast("stop")
        d.parent = nil
        if vim.api.nvim_win_is_valid(d._primary_window) then
            kf.events.observe_window(d._primary_window):detach(self._primary_observer)
        end
        d._primary_window = nil
        d._primary_observer = nil
        for w,_ in pairs(d._secondary_windows) do
            if vim.api.nvim_win_is_valid(w) then
                vim.api.nvim_win_close(w, true)
            end
            win_to_mode[w] = nil
        end
        d._secondary_windows = {}
    end

    if parent then
        parent.child = nil
        parent.channel:broadcast("resume")
    else
        -- no parent, so this is the original mode for the primary window
        win_to_mode[primary] = nil
    end
end

function Mode:is_started()
    return not not self._primary_window
end

function Mode:is_yielding()
    return not not self.child
end

function Mode:enter(window)
    window = kf.get_window(window)
    if self:is_started() then
        -- TODO error
        return
    end

    if win_to_mode[window] then
        -- TODO error
        return
    end

    win_to_mode[window] = self
    self._primary_window = window
    self:_initialize_layers()

    local window_events = kf.events.observe_window(window)
    self._primary_observer = window_events:attach(kf.events.stop_on_detach, {source=self})
    
    self.channel:broadcast("start")
end

function Mode:yield(child)
    if self:is_yielding or not self:is_started() then
        -- TODO error
        return
    end

    if child:is_started() then
        -- TODO error
        return
    end

    self.child = child
    child.parent = self

    child._primary_window = self._primary_window
    child:_initialize_layers()
    self.channel:broadcast("yield")
    child.channel:broadcast("start")
end

--[[ directly substitute replacement mode for self, transferring parentage and windows ]]
function Mode:substitute(replacement)
    if self:is_yielding or not self:is_started() then
        -- TODO error
        return
    end

    if replacement:is_started() then
        -- TODO error
        return
    end

    replacement.layers = vim.api.tbl_extend("force",
        self._layers, replacement._initial_layers, self._preserve_layers)
    replacement._preserve_layers = self._preserve_layers
    self.channel:broadcast("stop")
    replacement.parent = self.parent
    replacement._primary_window = self._primary_window
    replacement._secondary_windows = self._secondary_windows

    local window_events = kf.events.observe_window(window)
    replacement._primary_observer = window_events:attach(kf.events.stop_on_detach, {source=replacement})
    window_events:detach(self._primary_observer)
    self._primary_observer = nil

    if self.parent then
        self.parent.child = replacement
        self.parent.channel:broadcast("yield")
    end

    self.parent = nil
    self._primary_window = nil
    self._secondary_windows = nil

    replacement:broadcast("start")
end

--[[
--  window should not currently be owned by any mode
--      - when the mode is stopped, we automatically close the windows (if they are still open)
--
--]]
function Mode:capture_window(window)
    window = kf.get_window(window)
    if not self:is_started() then
        -- TODO error
        return
    end

    if win_to_mode[window] then
        -- TODO error, window is already captured
    end

    win_to_mode[window] = mode
    self._secondary_windows[window] = true
end

function Mode:release_window(window)
    window = kf.get_window(window)
    if self._secondary_windows[window] then
        self._secondary_windows[window] = nil
        win_to_mode[window] = nil
    end
end

function Mode:get_windows()
    return self._primary_window, unpack(utils.table.keys(self._secondary_windows))
end

--[[ gets the mode ultimately responsible for window: the leaf descendant of whichever mode owns
--the window. If no mode owns the window, then first assigns window to normal mode.
--
--
-- If window falsey or 0, uses current (vim) focus window ]]
function module.get_mode(window, allow_nil)
    window = kf.get_window(window)
    local mode = win_to_mode[window]
    if not (mode or allow_nil) then
        mode = require("keyfactor.modes").NormalMode()
        mode:enter(window)
    else
        -- find leaf descendant
        for m in descendants(mode) do
            mode = m
            break
        end
    end
    return mode
end

return module
