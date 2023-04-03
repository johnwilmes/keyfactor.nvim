local kf = require("keyfactor.api")

local PromptController = utils.class()

function PromptController:get_value()
    return nil
end

function PromptController:accept()
    kf.events.broadcast(self, kf.events.prompt.accept, {accept=true, value=self:get_value()})
end

function module.PromptController:cancel()
    kf.events.broadcast(self, kf.events.prompt.cancel, {accept=false, value=self:get_value()})
end

local GetKeyController = utils.class(PromptController)

function module.GetKeyController:__init(opts)
    self._key = nil
end

function module.GetKeyController:get_value()
    return vim.deepcopy(self._key)
end

function module.GetKeyController:push_key(key)
    self._key = key
    self:accept()
end

local TextPromptController = utils.class(PromptController)

function TextPromptController:__init(opts)
    local buffer, is_valid = kf.get_buffer(opts.buffer)
    if not is_valid then
        error("invalid initial buffer")
    end
    self.buffer = buffer
end

function TextPromptController:get_value()
    local lines = vim.api.nvim_buf_get_lines(self.buffer, 0, 1, false)
    return lines[1]
end


local module = {
    events = events,
    PromptController = PromptController,
    GetKeyController = GetKeyController,
}

return module
