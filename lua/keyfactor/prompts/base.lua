local action = require("keyfactor.actions.base").action

local module = {}




do
    local search_mt = {}

    function search_mt:__bind(params)
        --[[ set up search prompt mode
        --      set prompt text
        --      set prompt contents to what gets confirmed by default
        --      name(s?) of mode for keybinding purposes?
        --   
        --   await prompt completion
        --
        --   if confirm, produce result:
        --   if self.as=="textobject" then
        --      return textobject...
        --   else
        --      return search string
        --   end
        --]]

        local prompt_config = {
            name="Search regex",
            base_type="text",
            --default_layer={add character to prompt, backspace deletes, arrows...}
                ---- implied by base_type="text"?
            --completion=TODO completion engine based on search history
            --[[various styling details?
            --      highlighting
            --      display of default completion
            --      display of other completions
            --      mechanism for incremental highlighting, e.g. "redraw" callback (or commit
            --      callback?)
            --          (commit callback better, can also use for implementing char prompt behavior
            --          of auto-accepting after first printable character entry)
            --]]
        }
        
        local search_prompt = prompt.new(prompt_config)
        local accept, pattern = search_prompt:await()

        if accept then
            return  pattern
        else
            return nil
        end
    end
end

return module
