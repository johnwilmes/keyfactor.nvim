local oo = require("loop.simple")
local function super(obj) return oo.getsuper(oo.getclass(obj)) end

local base = require("keyfactor.modes.base")

local module = {}

module.BasePrompt = oo.class({}, base.Observable)

function module.BasePrompt:__init()
    self._accepted = false
end

function module.BasePrompt:is_accepted()
    return self._accepted
end

function module.BasePrompt:accept()
    if self:is_active() then
        self._accepted = true
        self:stop()
    end
end

module.TextBufferPrompt = oo.class({}, module.BasePrompt)

function module.TextBufferPrompt:__init(opts)
    if opts.buffer then
        -- TODO validate?
        self.buffer = opts.buffer
        self._del_buffer = (opts.keep_buffer==false)
        self:get_text() --initialize cache in case buffer becomes invalid
    end

    if not self.buffer then
        self.buffer = vim.api.nvim_create_buf(false, true)
        self._del_buffer = not opts.keep_buffer
        self._cached = ""
        self._cached_tick = vim.api.nvim_buf_get_option(self.buffer, "changedtick")
    end

    -- TODO autocmd to listen for buffer changes, and broadcast update?
end

function module.TextBufferPrompt:stop()
    self:get_text() -- ensure current value is cached
    super(self).stop()
    if self._del_buffer then
        vim.api.nvim_buf_delete(buffer, {force=true})
        self._del_buffer = false
    end
end

function module.TextBufferPrompt:get_value()
    return self:get_text()
end

function module.TextBufferPrompt:get_text()
    if buffer is valid then -- TODO
        local changedtick = vim.api.nvim_buf_get_option(self.buffer, "changedtick")
        if self._cached_tick ~= changedtick then
            local lines = vim.api.nvim_buf_get_lines(self.buffer, 0, 1, true)
            self._cached = lines[0]
            self._cached_tick = changedtick
        end
    end

    return self._cached
end

function module.TextBufferPrompt:set_text(text)
    -- TODO validate text: replace new-lines?
    if self:is_active() and buffer is valid then -- TODO
        vim.api.nvim_buf_set_lines(self.buffer, 0, 1, true, {text})
        self._cached = text
        self._cached_tick = vim.api.nvim_buf_get_option(self.buffer, "changedtick")
        -- TODO broadcast update?
    end
end



module.RawPrompt = oo.class({}, module.BasePrompt)

function module.RawPrompt:__init(opts)
    if type(opts.limit)~="number" then
        opts.limit=nil
    end
    self._keys = {}
end

function module.RawPrompt:get_value()
    return self._keys
end

function module.RawPrompt:push_key(key)
    table.insert(self._keys, key)
    if self.limit and #self._keys > self.limit then
        self:accept()
    end
    --TODO broadcast update?
end

function module.RawPrompt:pop_key()
    if #self._keys == 0 then
        self:stop()
    end
    return table.remove(self._keys)
    --TODO broadcast update?
end

module.CharPrompt = oo.class({}, module.RawPrompt)

function module.CharPrompt:get_value()
    return table.concat(utils.table.map_field(self._keys, "printable"))
end

function module.CharPrompt:push_key(key)
    if key.printable then
        super(self).push_key(self, key)
    else
        -- TODO log
    end
end

return module
