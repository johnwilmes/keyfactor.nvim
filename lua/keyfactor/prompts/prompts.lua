local oo = require("loop.simple")
local function super(obj) return oo.getsuper(oo.getclass(obj)) end

local base = require("keyfactor.modes.base")
local models = require("keyfactor.modes.prompt_models")
local views = require("keyfactor.modes.prompt_views")

local module = {}

module.CharMode = oo.class({}, base.Mode)

function module.CharMode:__init(opts)
    self.model = models.CharPrompt()
    -- TODO opts might have overrides for the layer or status line view...
end

function module.CharMode:attach()
    -- TODO initialize status line view

    kf.push_mode(self.frame, {
        --[[ commands that edit, edit the buffer, if set (even if not visible!);
        --   viewport is a window, receives viewport commands (e.g. scroll)
        --   note that viewport need not display buffer ]]
        name="Char",
        buffer=false,
        -- viewport = current viewport (default)
        layers="prompt",
        model=self.model, -- so that push_key/pop_key can be directed appropriately...
    })
end

module.SearchMode = oo.class({}, base.Mode)

function SearchPromptMode:__init(opts)
    self.model = models.TextBufferPrompt()
    -- TODO validate/apply opts to the view
    self._pattern_view = views.BufferPromptView({}, {buffer=self.model.buffer})
    -- self._incremental_view = TODO
end

function SearchPromptMode:attach()
    self.model:attach(self._pattern_view)
    -- TODO attach incremental view

    kf.push_mode(self.frame, {
        name="Search",
        buffer=self.model.buffer,
        -- viewport = current viewport (default)
        layers="prompt",
        model=self.model, -- so that push_key/pop_key can be directed appropriately...
    })
end




--[[
-- If it supports "options":

prompt_mt.options

function prompt_mt:get_options(filter)
end

function prompt_mt:get_option_details(id)
end

function prompt_mt:get_focus()
end

function prompt_mt:set_focus()
end

function prompt_mt:select_options()
end
]]

do
    local search_mt = {}

    function search_mt:__bind(params)
        --[[

        prompt:
            single, free text entry
                - this style of prompt should start insert
            label: Search
            completion options: search history TODO
            preview handler TODO
                - e.g. as with :command-preview, 'inccomand'
        ]]

        local prompt_config = {
            --completion = history...,
            views = {incremental, prompt_window}
        }
        
        local search_prompt = create_text_buffer_prompt(prompt_config)
        local accept, results = search_prompt:await()

        -- TODO... return as textobject, probably
        if accept then
            local pattern = results[1]
            return pattern
        else
            return nil
        end
    end
end

