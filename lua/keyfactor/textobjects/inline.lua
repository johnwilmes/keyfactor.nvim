local utils = require("keyfactor.utils")
local base = require("keyfactor.textobjects.base")
local kf = require("keyfactor.core")

local function lua_to_vim_positions(line, text, offsets)
    -- 1-based byte index -> (line, 0-based utf index) tuple
    local positions = {}
    for i,x in ipairs(offsets) do
        positions[i] = {line, vim.str_utfindex(text, x-1)}
    end

end

local module = {}

module.line = base.inline_textobject(function(params, {bytewise=true})
    if params.offset > 0 then return nil end
    local a,b,c,d = params.text:match("^()%s*().-()%s*()$")
    return {a-1,b-1,c-1,d-1}
end)


-- TODO would be nice to have smarter word class that can include apostrophes, where appropriate
-- (e.g., within plaintext blocks, comments, quoted strings...)
--
-- Note: we exclude "sequence of other (not %w_) characters separated with white space", which is
-- included by base vim word motions
module.word = base.pattern_textobject("()()[%w_]+()()")

module.WORD = base.pattern_textobject("()()[^%s]+()()")


do
    function get_char_textobject(char)
        --TODO presumably also set history?
        --highlighting?
        local pattern
        if char:match("^%p") then
            pattern = "()()%"..char.."()()"
        else
            pattern="()()"..char.."()()"
        end
        return base.pattern_textobject(pattern)
    end

    module.char = bindable(function(params)
        if type(params.char)=="string" then
            return get_char_textobject(params.char)
        end

        local char_prompt = prompts.CharMode({}, {limit=1}):await()
        if char_prompt and char_prompt:is_accepted() then
            local char = char_prompt:get_value()
            if type(char)=="string" and #char > 0 then
                return get_search_textobject(char)
            else
                --TODO default to history?
            end
        end

        return nil
    end)
end

do
    function get_search_textobject(pattern)
        --TODO presumably also set history?
        --highlighting?
        pattern = "()()"..pattern.."()()"
        local regex=require("rex_pcre2").new(pattern)
        return base.pattern_textobject(pattern)
    end

    module.search = bindable(function(params)
        if type(params.pattern)=="string" then
            return get_search_textobject(params.pattern)
        end

        local search_prompt = prompts.SearchMode():await()
        if search_prompt and search_prompt:is_accepted() then
            local pattern = search_prompt:get_value()
            if type(pattern)=="string" and #pattern > 0 then
                return get_search_textobject(pattern)
            else
                -- TODO default to history?
            end
        end

        return nil
    end)
end
