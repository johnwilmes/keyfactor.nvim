local utils = require("keyfactor.utils")
local kf = require("keyfactor.api")

local TelescopeMode = utils.class()

local Picker = utils.class()

function Picker:__init(opts)
    self._constructor = opts.constructor
end

function Picker:get_handle()
    if self._picker and not self._picker:is_done() then
        return self._picker.prompt_buffer
    end
end

function Picker:get_active_picker()
    if (not self._picker) or self._picker:is_done() then
        self._picker = self._constructor()
        -- TODO? listen for picker close: cache option settings so we can restart smoothly
    end
    return self._picker
end

function Picker:__gc()
    if self._picker and not self._picker:is_done() then
        require("telescope.actions").close(self._picker.prompt_bufnr)
    end
end

local TelescopePrompt = utils.class(kf.controller.Prompt)

function TelescopePrompt:__init(opts)
    -- TODO
end

function TelescopePrompt:get_value()
    -- TODO
end


local TelescopeView = utils.class()

function TelescopeView:__init(opts)
    self._page = opts.page
    self._picker = opts.picker
    self._target = opts.target
end

function TelescopeView:draw()
    -- draw underlying page
    self._page:draw()

    -- if picker not drawn, then restart it
    local picker = self._picker:get_active_picker()

    -- update picker
    local text = vim.api.nvim_buf_get_lines(target.buffer, 0, 1, false)
    text = text[1] or ""
    picker:set_prompt(text)

    -- TODO
    -- translate target.selection to picker prompt buffer
        -- picker.prompt_bufnr, and picker.prompt_prefix as column offset
        -- as list of ranges
        -- draw target highlights
end

function TelescopeMode:__init(opts)
    local picker = opts.picker
    if type(picker) == "string" then
        picker = require("telescope.builtin")[picker]
    elseif not utils.is_callable(picker) then
        error("picker required")
    end

    local themes = require("telescope.themes")
    local picker_opts = themes.get_ivy{
        initial_mode="normal",
        mappings = {},
        default_mappings = {},
    }
    local constructor = function()
        picker(picker_opts)
    end
    self._picker = Picker{constructor=constructor}

    self._prompt_buffer = vim.api.nvim_create_buf(false, true)
    self.target = kf.controller.Target{buffer=self._prompt_buffer}
    -- TODO attach to prompt buffer changes
    -- set picker text if started

    local layer_init = opts.layers
    if not layer_init then
        layer_init = {
            -- TODO
            groups={"normal", "input", "prompt"},
        }
    end

    self.layers = kf.controller.Layers(layer_init)

    self.options = TelescopeOptions{picker=self._picker}

    local page = kf.view.get_page(opts.page)
    if not page then page = kf.view.get_page() end

    self.view = TelescopeView{page=page, picker=self._picker, target=self.target}

    self.prompt = TelescopePrompt{...} -- TODO
    
    -- TODO? event subscription:
    -- if mode loses focus, then cache picker option settings and kill the picker?
end

function TelescopeMode:__gc()
    if self._picker and not self._picker:is_done() then
        require("telescope.actions").close(self._picker.prompt_bufnr)
    end
end

local module = {
    TelescopeMode = TelescopeMode,
}

return module
