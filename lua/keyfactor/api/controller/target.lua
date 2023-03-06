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

local buffer_history = {} -- [buffer] = {viewport=..., selection=...}
local default_target = {} -- [window] = DefaultTarget

local function update_history(buffer, history, values)
    if values.selection then
        history.selection=values.selection
    elseif not history.selection then
        history.selection=kf.selection(buffer, {})
    end

    if not history.viewport then
        history.viewport = vim.deepcopy(NULL_VIEWPORT)
    end
    if values.viewport then
        local v = values.viewport
        local h = history.viewport
        for k,_ in pairs(NULL_VIEWPORT) do
            if v[k] then d[k]=v[k] end
        end
    end
end

local DefaultTarget = utils.class()

-- TODO handle window having been closed

function DefaultTarget:__init(opts)
    self._window = opts.window
    self._buffer = vim.api.nvim_win_get_buf(self._window)
    self._values = {}
end

function DefaultTarget:get(buffer)
    if type(buffer)=="number" and buffer>0 then
        buffer, is_valid = kf.get_buffer(buffer)
        if not valid then return false end
    end

    if not buffer then buffer = self._buffer end

    local values = self._values[buffer] or buffer_history[buffer]
    if not values then
        values = {
            viewport=vim.deepcopy(NULL_VIEWPORT),
            selection= kf.selection(buffer, {})
        }
    end

    return {
        buffer=buffer,
        selection=values.selection,
        viewport=values.viewport,
    }
end

function DefaultTarget:set_buffer(buffer)
    local is_valid
    if type(buffer)=="number" and buffer>0 then
        buffer, is_valid = kf.get_buffer(buffer)
        if is_valid then
            self._buffer = buffer
        end
    end
end

function DefaultTarget:set_selection(selection)
    local buffer = selection.buffer
    local id, is_valid = kf.get_buffer(buffer)
    if id~=buffer or not is_valid then return false end

    local history = utils.table.set_default(self._values, id)
    update_history(id, history, {selection=selection})

    local history = utils.table.set_default(buffer_history, id)
    update_history(id, history, {selection=selection})
    return true
end

function DefaultTarget:set_viewport(buffer, viewport)
    local id, is_valid = kf.get_buffer(buffer)
    if id~=buffer or not is_valid then return false end

    local history = utils.table.set_default(self._values, id)
    update_history(id, history, {viewport=viewport})

    local history = utils.table.set_default(buffer_history, id)
    update_history(id, history, {viewport=viewport})
    return true
end

function DefaultTarget:set(values)
    local id, is_valid
    if values.buffer then
        id, is_valid = kf.get_buffer(values.buffer)
        if id~=buffer or not is_valid then
            return false
        end
    else
        id = self._buffer
    end

    if values.selection and id~=values.selection.buffer then
        return false
    end

    if values.buffer then
        self._buffer = id
    end

    local history = utils.table.set_default(self._values, id)
    update_history(id, history, values)

    local history = utils.table.set_default(buffer_history, id)
    update_history(id, history, values)
    return true
end


function module.get_default_target(window)
    local window, is_valid = kf.get_window(window)
    if not is_valid then
        error("invalid window")
    end

    local target = default_target[window]
    if not target then
        target = DefaultTarget{window=window}
        default_target[window] = target
    end
    return target
end

--[[

Single fixed window target controller, for controlling
    - which buffer is in window
    - viewport
    - selection

--]]

local module.TargetController = utils.class()

function module.TargetController:__init(opts)
    local window, is_valid = kf.get_window(window)
    if not is_valid then
        error("invalid window")
    end
    self._window = window

    if opts.default then
        self._default = opts.default
    else
        self._default = module.get_default_target(self._window)
    end

    -- whether we write updates to the default target
    if opts.preserve_default then
        self._preserve_default = true
    end

    local default = self._default:get(opts.buffer)
    if not default then
        error("invalid buffer")
    end

    self._buffer = default.buffer
    self._values = {[default.buffer]=default}

    self._valid = {}
    local valid_buffer = opts.valid_buffer
    if valid_buffer==nil or valid_buffer==true then
        -- default is that all buffers are allowed
        valid_buffer = function() return true end
    elseif opts.valid_buffer==false then
        -- only initial buffer is allowed
        valid_buffer={self._values.buffer}
    end
        
    if vim.tbl_islist(valid_buffer) then
        valid_buffer = utils.list.to_flags(valid_buffer)
        self._valid.buffer = function(b) return valid_buffer[b] end
    elseif utils.is_callable(valid_buffer) then
        self._valid.buffer = valid_buffer
    else
        error("invalid buffer specification")
    end

    if utils.is_callable(opts.valid_viewport) then
        self._valid.viewport = opts.valid_viewport
    end

    if utils.is_callable(opts.valid_selection) then
        self._valid.selection = opts.valid_selection
    end

    for k,v in pairs(self._valid) do
        if not v(self._values[k]) then
            error("invalid initial "..k)
        end
    end
end

-- TODO validation of output of self._default:get ?

function module.TargetController:_get_valid(buffer)
    local is_valid

    if type(buffer)=="number" and buffer>0 then
        buffer, is_valid = kf.get_buffer(buffer)
        is_valid = is_valid and self._valid.buffer(buffer)
    end

    if not is_valid then
        buffer = self._buffer
    end

    return buffer, is_valid
end

function module.TargetController:get(buffer)
    local id, is_valid = self:_get_valid(buffer)

    if buffer and not is_valid then
        return false
    end

    local values = self._values[id]
    if not values then
        values = self._default:get(id)
    end

    return {
        buffer=id,
        selection=values.selection,
        viewport=vim.deepcopy(values.viewport)
    }
end

function module.TargetController:set_buffer(buffer)
    local id, is_valid = self:_get_valid(buffer)
    if not is_valid then
        return false
    end

    if not self._values[id] then
        self._values[id] = self:_default:get(id)
    end

    self._buffer = id
    return true
end

function module.TargetController:set_selection(selection)
    local id, is_valid = self:_get_valid(selection.buffer)
    if not is_valid then
        return false
    end

    if self._valid.selection and not self._valid.selection(selection) then
        return false
    end

    if not self._values[id] then
        self._values[id] = self._default:get(id)
    end

    self._values[id].selection = selection
    if not self._preserve_default then
        self._default:set_selection(selection)
    end
    return true
end

function module.TargetController:set_viewport(buffer, viewport)
    local id, is_valid = self:_get_valid(buffer)
    if not is_valid then
        return false
    end

    if self._valid.viewport and not self._valid.viewport(viewport) then
        return false
    end

    if not self._values[id] then
        self._values[id] = self._default:get(id)
    end

    self._values[id].viewport = viewport

    if not self._preserve_default then
        self._default:set_viewport(id, viewport)
    end
    return true
end

function module.TargetController:set(values)
    local id, is_valid = self:_get_valid(values.buffer)

    if values.selection then
        if id~=values.selection.buffer or (self._valid.selection and not
            self._valid.selection(selection)) then
            return false
        end
    end

    if values.viewport and self._valid.viewport and not self._valid.viewport(viewport) then
        return false
    end

    if values.buffer then
        if is_valid then
            return false
        else
            self._buffer = id
        end
    end

    if not self._values[id] then
        self._values[id] = self._default:get(id)
    end

    if values.viewport then
        self._values[id].viewport = values.viewport
    end

    if values.selection then
        self._values[id].selection = values.selection
    end

    if not self._preserve_default then
        self._default:set{buffer=id,
            selection=values.selection,
            viewport=values.viewport
        }
    end

    return true
end

return module
