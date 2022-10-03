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


module.line = base.inline_textobject(function(buffer, line)
    local text = vim.api.nvim_buf_get_lines(buffer, line, line+1, true)
    local bounds = text:match("^()%s*().-()%s*()$")
    -- TODO translate bounds from byte index to utf index!
    return {kf.range(bounds)}
end)

-- TODO would be nice to have smarter word class that can include apostrophes, where appropriate
-- (e.g., within plaintext blocks, comments, quoted strings...)
--
-- Note: we exclude "sequence of other (not %w_) characters separated with white space", which is
-- included by base vim word motions
module.word = base.inline_textobject(function(buffer, line)
    local text = vim.api.nvim_buf_get_lines(buffer, line, line+1, true)
    local results = {}
    for l,r in text:gmatch("()[%w_]+()") do
        -- TODO translate bounds from byte index to utf index!
        results[#results+1]=kf.range{l,r}
    end
    return results
end)

module.WORD = base.inline_textobject(function(buffer, line)
    local text = vim.api.nvim_buf_get_lines(buffer, line, line+1, true)
    local results = {}
    for l,r in text:gmatch("()[^%s]+()") do
        -- TODO translate bounds from byte index to utf index!
        results[#results+1]=kf.range{l,r}
    end
    return results
end)

do
    local pattern_mt = {__call = function(buffer, line)
        local text = vim.api.nvim_buf_get_lines(buffer, line, line+1, true)
        local results = {}
        for a,b,c,d in text:gmatch(self.pattern) do
            -- TODO translate bounds from byte index to utf index!
            results[#results+1]=kf.range{a,b,c,d}
        end
        return results
    end}

    module.char = function(x)
        if x
        
    end
end




















--[[
-- Should be constructed with _pattern attribute containing lua pattern with four empty (position)
-- captures
--]]
local inline_pattern_textobject = textobject.inline_textobject:new()
function inline_pattern_textobject:_get_line(buffer, line)
    local text = unpack(vim.api.nvim_buf_get_lines(buffer, line-1, line, false))
    local results = {}

    local start = 1
    while true do
        -- no way to specify offsets using match_str, so use match_line even though we have already
        -- retrieved text
        offsets = {text:match(self._pattern, start)}
        if not offsets[1] then
            break
        end
        if start==1 then
            offsets[1]=offsets[2] -- no separator at start of line
        end
        if offsets[4]==#text+1 then
            offsets[4]=offsets[3] -- no separator at end of line
        end
        start=offsets[3]

        local object = range.range:new({bounds=lua_to_vim_positions(text, line, offsets),
                                        textobject={self, self}})
        table.insert(results, object)
    end
    re:match_line(buffer, line, offset)
end

module.WORD = inline_pattern_textobject({_pattern="()%s*()[^%s]+()%s*()"})
--[[ This word object is intentionally different from vim builtin. It excludes space-separated
--   sequences of non-alphanumeric/underscore characters
--]]
module.word = inline_pattern_textobject({_pattern="()%s*()[_%w]+()%s*()"})

module.line = textobject.inline_textobject:new()
function module.line:_get_line(buffer, line)
    local text = vim.api.nvim_buf_get_lines(buffer, line-1, line, false)
    local offsets = text:match("^()%s*().-()%s*()$")
    local object = range.range:new({bounds=lua_to_vim_positions(text, line, offsets),
                                    textobject={self, self}})
    return {object}
end

function module.char()
    -- TODO memoize
    local obj = textobject.inline_textobject:new()
    obj.char = -- TODO get user input
    return obj
end

function module.char:_get_line(buffer, line)
    local text = vim.api.nvim_buf_get_lines(buffer, line-1, line, false)
    local results = {}
    local char = (char:match("%w") and char) or ("%"..char) -- escape character for pattern
    for a,b in text:gmatch(("()"..char.."()")) do
        local bounds = lua_to_vim_positions(text, line, {a,b})
        local object = range.range:new({bounds=bounds, textobject={self, self}})
        table.insert(results, object)
    end
    return results
end
