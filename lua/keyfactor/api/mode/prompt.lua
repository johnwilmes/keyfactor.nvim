local module = {}

module.TextPrompt = utils.class()
function module.Search:__init(opts)
    local default_layers = {
        groups={"normal", "insert", "prompt"},
    }
    self._layer_init = opts.layers or default_layers
end

function module.TextPrompt:get_targets()
    if self.edit then
        return {self.edit:get()}
    end
    return {}
end

function module.TextPrompt:_start()
    if self._started then
        error("already started")
    end
    self._prompt_buffer = vim.api.nvim_create_buf(false, true)
    -- TODO set buffer property: single line
    self._prompt_window = kf.layout.create_window{style="prompt", anchor=self._target.window}

    self.edit = kf.controller.Target{buffer=self._prompt_buffer, window=self._prompt_window}
    self.layers = kf.controller.Layers(self._layer_init)
    self.prompt = kf.controller.PromptController()

    self._started = true
end






module.Search = utils.class(module.TextPrompt)

function module.Search:__init(opts)
    -- TODO validate
    self._target = opts.target
end

function module.Search:_start()
    if self._started then
        error("already started")
    end
    self._search_buffer = vim.api.nvim_create_buf(false, true)
    self._search_window = kf.layout.create_window{style="prompt", anchor=self._target.window}
    self.result = {}

    self.edit = kf.controller.Target{buffer=self._search_buffer, window=self._search_window}
    -- TODO fix reinsert/history target for insert
    self.insert = kf.controller.Insert{target=self.edit}
    self.layers = kf.controller.Layers(self._layer_init)
    self.prompt = kf.controller.PromptController()

    -- TODO completion controller?

    self._started = true
end

function module.Search:_stop()
    if self._started then
        local lines = vim.api.nvim_buf_get_lines(self._search_buffer, 0, 1, false)
        self.result.text = lines[1] or ""
        self.result.accept = self.prompt:is_accepted()

        if self.insert then
            self.insert:commit()
        end

        -- TODO self.result.text gets pushed to search history

        self.edit = nil
        self.insert = nil
        self.layers = nil
        self.prompt = nil

        kf.layout.release_window(self._search_window)
        vim.api.nvim_buf_delete(self._search_buffer, {force=true})
        self._started = false
    end
end

module.GetKey = utils.class()

function module.GetKey:__init(opts)
end

function module.GetKey:_start()
    self.layers = kf.controller.Layers{groups={prompt=true}, layers={getkey=true}}
    self.prompt = kf.controller.GetKey()
end

function module.GetKey:_stop()
    if self.prompt then
        self.result = {
            keys = self.prompt:get_keys(),
            accept = self.prompt:is_accepted()
        }
        self.layers = nil
        self.prompt = nil
    end
end


