local oo = require("loop.simple")
local function super(obj) return oo.getsuper(oo.getclass(obj)) end

local base = require("keyfactor.modes.base")

local module = {}

module.BufferPromptView = oo.class({}, base.Observer)

function BufferPromptView:__init(opts)
    self.buffer = opts.buffer
    self._win_opts = {
        zindex = opts.zindex or 50, --TODO magic constant!
        focusable=false,
        style="minimal",
    }
end

function BufferPromptView:attach()
    local window = vim.api.nvim_open_win(self.buffer, false, {
        -- TODO make a window according to self settings
    })

    if window==0 then
        -- TODO log error
    else
        self.window = window
    end
end

function BufferPromptView:detach()
    if self.window then
        vim.api.nvim_win_close(self.window, true)
        self.window = nil
    end
end

return module
