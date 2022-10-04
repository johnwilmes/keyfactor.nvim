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
