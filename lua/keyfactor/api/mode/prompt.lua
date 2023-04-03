local utils = require("keyfactor.utils")
local kf = require("keyfactor.api")

local function on_search_complete(mode, prompt, event, details)
    kf.mode.stop(mode)
    if details.accept then
        -- TODO
    end
end

local Search = utils.class()

function Search:__init(opts)
    local search_buffer, is_valid = kf.get_buffer(opts.buffer)
    if not is_valid then search_buffer = nil end

    self._prompt_buffer = vim.api.nvim_create_buf(false, true)
    self.target =  kf.controller.Target{buffer=self._prompt_buffer}

    local layer_init = opts.layers
    if not layer_init then
        layer_init = {
            groups={"normal"}, -- TODO this is the initial group setting
                -- TODO all groups should be valid by default
        }
    end
    self.layers = kf.controller.Layers(layer_init)
    self.prompt = kf.controller.TextPrompt({buffer=self._prompt_buffer})
    self._event_handle = kf.events.attach(on_search_complete, {event={kf.events.prompt.accept, kf.events.prompt.cancel}, source=self.prompt, object=self})

    self.view = kf.view.SearchView({target=self.target, search=search_buffer})
    -- TODO completion controller?
    -- TODO self.status
end

function Search:__gc()
    kf.events.detach(self._event_handle)
    vim.api.nvim_buf_delete(self._prompt_buffer, {force=true})
end


local function on_get_key(mode, prompt, event, details)
    kf.mode.stop(mode)
    if details.accept then
        -- TODO
    end
end

local GetKey = utils.class()

function GetKey:__init(opts)
    self.layers = kf.controller.Layers{groups={prompt=true}, layers={getkey=true}}
    self.prompt = kf.controller.GetKey()
    self._event_handle = kf.events.attach(on_get_key,
    {event={kf.events.prompt.accept, kf.events.prompt.cancel}, source=self.prompt, object=self})
    -- TODO self.status
end

function GetKey:__gc()
    kf.events.detach(self._event_handle)
end

local module = {
    Search=Search,
    GetKey=GetKey
}

return module
