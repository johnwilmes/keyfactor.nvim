local module = {}

local NULL_VIEWPORT = {
    topline=1,
    lnum=1,
    col=0,
    coladd=0,
    curswant=0,
    leftcol=0,
    skipcol=0
}

local function update_details_dict(details, values)
    if values.selection then
        details.selection=values.selection
    end
    if values.viewport then
        local v = values.viewport
        local d = details.viewport
        for k,_ in pairs(NULL_VIEWPORT) do
            if v[k] then d[k]=v[k] end
        end
    end
end

local function get_window_and_buffer(opts)
    opts = opts or {}
    local window = opts.window
    local buffer = opts.buffer

    if type(window)=="number" and window>0 then
        window, is_valid = kf.get_window(window)
        if not is_valid then
            window = vim.api.nvim_get_current_win()
        end
    else
        window = vim.api.nvim_get_current_win()
    end

    if type(buffer)=="number" and buffer>0 then
        buffer, is_valid = kf.get_buffer(buffer)
        if not is_valid then
            buffer = vim.api.nvim_win_get_buf(window)
        end
    else
        buffer = vim.api.nvim_win_get_buf(window)
    end

    return window, buffer
end


local module.default_target = {
-- TODO save buffer-wise history via ShaDa or similar
    _buffer_history = {},
    _window_history = {},
}

function module.default_target:get(opts)
    local window, buffer = get_window_and_buffer(opts)

    -- use window+buffer history if set, fall back to buffer history
    local history = self._window_history[window]
    if history then
        history = self._window_history[buffer]
    end
    if not history then
        history = self._buffer_history[buffer]
    end

    local result = {window=window, buffer=buffer}

    -- if no history then use generic defaults
    if history then
        result.selection = history.selection
        result.viewport = vim.deepcopy(history.viewport)
    else
        result.selection = kf.selection(buffer, {})
        result.viewport = NULL_VIEWPORT
    end
    result.viewport.window = window
    return result
end

function module.default_target:set_details(values)
    local window, buffer = get_window_and_buffer(values)

    local history = utils.table.set_default(utils.table.set_default(self._window_history, window), buffer)
    update_details_dict(history, values)

    history = utils.table.set_default(self._buffer_history, buffer)
    update_details_dict(history, values)
    return true
end



local module.Target = utils.class()

function module.Target:__init(opts)
    if opts.default then
        self._default = opts.default
    else
        self._default = module.default_target
    end

    if opts.preserve_default then
        self._preserve_default = true
    end

    -- Set initial value so we can call self._get_default
    self._is_valid_window = function() return true end
    self._is_valid_buffer = self._is_valid_window
    local default = self:_get_default(opts.buffer, opts.window)

    self._window = default.window
    self._buffers = {[default.window]=default.buffer}
    self._details = {[default.window]={[default.buffer]={
        selection=default.selection,
        viewport=vim.deepcopy(default.viewport)
    }}}

    -- default if valid_windows not set: only current window is allowed
    local valid_windows = opts.valid_windows or {self._window}
    if vim.tbl_islist(valid_windows) then
        valid_windows = utils.list.to_flags(valid_windows)
        self._is_valid_window = function(w) return valid_windows[w] end
    elseif utils.is_callable(valid_windows) then
        self._is_valid_window = valid_windows
    elseif valid_windows==true then
        -- valid_windows==true means accept all, which is the current state
    else
        error("invalid window specification")
    end

    if not self._is_valid_window(default.window) then
        error("invalid initial window")
    end
        
    local valid_buffers = opts.valid_buffers or {default.buffer}
    if vim.tbl_islist(valid_buffers) then
        valid_buffers = utils.list.to_flags(valid_buffers)
        self._is_valid_buffer = function(b) return valid_buffers[b] end
    elseif utils.is_callable(valid_buffers) then
        self._is_valid_buffer = valid_buffers
    elseif valid_buffers==true then
        -- valid_buffers==true means accept all, which is the current state
    else
        error("invalid buffer specification")
    end

    if not self._is_valid_buffer(default.buffer) then
        error("invalid initial buffer")
    end
end

--[[

We use _get_default to check if a buffer/window combination is valid, or get its valid completion,
because a default value is required to exist in order for the combination to be valid

--]]
function module.Target:_get_default(buffer, window)
    local is_valid, default

    if type(window)=="number" and window>0 then
        window, is_valid = kf.get_window(window)
        is_valid = is_valid and self._is_valid_window(window)
    end

    if not is_valid then
        window = self._window
        if not window then
            default = self._default:get()
            window = default.window
        end
    end

    if type(buffer)=="number" and buffer>0 then
        buffer, is_valid = kf.get_buffer(buffer)
        is_valid = is_valid and self._is_valid_buffer(buffer, window)
    end

    if not is_valid then
        buffer = self._buffer[window]
    end

    if not (buffer and default and default.buffer==buffer) then
        default = self._default:get{window=window, buffer=buffer}
    end

    return default
end

function module.Target:get(opts)
    opts = opts or {}
    local default = self:_get_default(opts.buffer, opts.window)

    local details = (self._details[default.window] or {})[default.buffer]
    if not details then
        details = default
    end

    return {
        window=default.window,
        buffer=default.buffer,
        selection=details.selection,
        viewport=vim.deepcopy(details.viewport)
    }
end

function module.Target:set_window(window)
    local default = self:_get_default(nil, window)
    if default.window==window then
        self._window = window
        return true
    end
    return false
end

function module.Target:set_buffer(buffer, window)
    local default = self:_get_default(buffer, window)
    if (buffer==default.buffer) and ((not window) or window==default.window) then
        self._buffer[default.window] = buffer
        return true
    end
    return false
end

function module.Target:set_details(values)
    -- TODO better selection/viewport validation?
    if not (values.selection or values.viewport) then
        error("no details given")
    end

    local default = self:_get_default(values.buffer, values.window)
    if (values.buffer and values.buffer~=default.buffer) or
        (values.window and values.window~=default.window) then
        -- specified invalid non-default buffer/window combination
        return false
    end

    local details = utils.table.set_default(utils.table.set_default(self._details, default.window), default.buffer)
    if not details.selection then details.selection=default.selection end
    if not details.viewport then details.viewport=vim.deepcopy(default.viewport) end

    update_details_dict(details, values)

    if not self._preserve_default then
        self._default:set_details{
            window=default.window,
            buffer=default.buffer,
            selection=values.selection,
            viewport=values.viewport
        }
    end

    return true
end

return module
