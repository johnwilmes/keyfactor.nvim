local module

module.PromptController = utils.class()

function module.PromptController:__init(opts)
    self._accepted = false
end

function module.PromptController:is_accepted()
    return self._accepted
end

function module.PromptController:accept()
    self._accepted=true
end

module.GetKeyController = utils.class(module.PromptController)

function module.GetKeyController:__init(opts)
    self._accepted = false
    self._keys = {}
end

function module.GetKeyController:is_accepted()
    return self._accepted
end

function module.GetKeyController:accept()
    self._accepted=true
end

function module.GetKeyController:get_keys()
    return vim.deepcopy(self._keys)
end

function module.GetKeyController:push_key(key)
    self._keys[#self._keys]=key
end

return module
