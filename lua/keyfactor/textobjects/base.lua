local utils = require("keyfactor.utils")
local kf = require("keyfactor.base")

local module = {}

--[[ Text object interface:

function textobject:get_next(params)
        Params:
            buffer
            position
            orientation = {side, boundary}
            reverse

        Returns next object. This is the first object strictly
        beyond `position` (in forward direction, unless reverse is true). Position of an object is
        given by considering all positions of the range compatible with orientation. So if
        orientation is fully specified, this is one position, if partially specified two, if
        unspecified than four. 

        Returns nil if no such object. When there are multiple possible next objects, returns all
        of them sorted by increasing size (where size is measured first by inner, if inner is true,
        and then by outer; or vice versa if inner is false)

function textobject:get_all(params)
        Params:
            buffer
            range


        Returns list of all objects within range (which should be just two positions, not a full
        range). Includes objects that only partially intersect range, possibly including only the
        endpoints of the range
--]]


do
--[[
    Wrapper for producing textobject in case when objects are
        - proper (set of textobjects is determined by buffer, not requiring additional context like
        cursor position)
        - completely disjoint
        - do not contain line breaks

    Just call module.inline_textobject(raw_next, options), where:

       function raw_next(params)
            params:
                buffer
                line (number)
                offset (number)
                    -refers to positions *between* characters. 
                text
                    - gives the text of the line

            returns list with four offsets from start of line (left outer, left inner, right inner,
            right outer) for the first textobject on the line whose left outer is >= offset, or nil
            if no such textobject exists

        options (optional):
            bytewise (boolean) - true if offsets (in params and return) are in byte units.
            otherwise they are in vim col units

    -- TODO might be nice to offer some options:
    --      - sparse: indicates typical line doesn't contain any examples of pattern; do binary
    --      search for appropriate line rather than sequential search
    --
    --      - no_text: don't cache/provide line text to raw_next
    --
    -- TODO implement as binary search with caching
    --]]

    
    local inline_mt = {}
    inline_mt.__index = inline_mt

    local by_orientation = {
        [nil] = {
            [nil] = {1,2,3,4},
            left = {1,2},
            right = {3,4},
        },
        outer = {
            [nil] = {1,4},
            left = {1},
            right = {4},
        },
        inner = {
            [nil] = {2,3},
            left = {2},
            right = {3},
        },
    }

    local function all_bounds_to_range(line, list)
        local function inner(_, b) return kf.position(line, b) end
        local function outer(_, bounds)
            return kf.range(utils.list.map(bounds, inner))
        end
        return utils.list.map(list, outer)
    end

    function inline_mt:get_next(params)
        local line = params.position[1]
        local targets = by_orientation[params.orientation.boundary][params.orientation.side]
        local all = self._cache[params.buffer][line]
        local result
        if not params.reverse then
            all = utils.list.filter(all, function(_, bounds)
                return utils.list.any(targets, function(_, t)
                    return bounds[t] > params.position[2]
                end)
            end)
            local n_lines = vim.api.nvim_buf_line_count(params.buffer)
            while #all==0 do
                line = line+1
                if line > n_lines then
                    return nil
                end
                all = self._cache[params.buffer][line]
            end

            table.sort(all, function(a,b) return a[1]<b[1] end)
            result = all[1]
        else
            all = utils.list.filter(all, function(_, bounds)
                return utils.list.any(targets, function(_, t)
                    return bounds[t] < params.position[2]
                end)
            end)
            while #all==0 do
                line = line-1
                if line < 0 then
                    return nil
                end
                all = self._cache[params.buffer][line]
            end

            table.sort(all, function(a,b) return a[1]<b[1] end)
            result = all[#all]
        end

        return all_bounds_to_range(line, {result})[1]
    end
        
    function inline_mt:get_all(params)
        local line = params.range[1][1]
        local pos = params.range[1][2]
        local all = self._cache[params.buffer][line]
        all = utils.list.filter(all, function(_, bounds)
            return bounds[4] > pos or bounds[1] >= pos
        end)
        if params.range[2][1]==line then
            pos = params.range[2][2]
            all = utils.list.filter(all, function(_, bounds)
                return bounds[1] < pos or bounds[4] <= pos
            end)
            return all_bounds_to_range(line, all)
        else
            all = all_bounds_to_range(line, all)
        end

        for line=line+1,params.range[2][1]-1 do
            vim.list_extend(all, all_bounds_to_range(line, self._cache[params.buffer][line]))
        end

        pos = params.range[2][2]
        local remaining = self._cache[params.buffer][params.range[2][2]]
        remaining = utils.list.filter(remaining, function(_, bounds)
            return bounds[1] < pos or bounds[4] <= pos
        end)
        remaining = all_bounds_to_range(params.range[2][2], remaining)
        vim.list_extend(all, remaining)

        return all
    end

    function module.inline_texotbject(raw_next, options)
        local cache = utils.cache.buffer_state(function(buffer, line)
            local text = vim.api.nvim_buf_get_lines(buffer, line, line+1, true)[1]
            local params = {buffer=buffer, line=line, text=text, offset=0}
            local results = {}
            local bytewise = false
            if options.bytewise then
                bytewise = {buffer=buffer, line=line, text=text, round_left=false}
            end

            while true do
                local offsets = raw_next(params)
                if offsets==nil then
                    break
                else
                    if bytewise then
                        bytewise.index = offsets
                        offsets = utils.byte_to_col(bytewise)
                    end
                    results[#results+1]=offsets
                    if offsets[1]==offsets[4] then
                        params.offset=offsets[4]+1
                    else
                        params.offset=offsets[4]
                    end
                end
            end
            return results
        end)

        local obj = {_cache=cache}
        return setmetatable(obj, inline_mt)
    end
end

--[[

pattern should be a lua string matching pattern, with four empty captures () at the positions of
the left outer, left inner, right inner, and right outer points

TODO support options:
    multiline (boolean)
        - implement via binary search?
    overlap (boolean)
        - instead of using gmatch, need to start right after last starting point...
]]
function module.pattern_textobject(pattern)
    local function raw_next(params)
        local a,b,c,d = params.text:match(self.pattern, params.offset+1)
        if a then
            return {a-1,b-1,c-1,d-1}
        end
    end
    return module.inline_textobject(raw_next, {bytewise=true})
end

--[[ 
--   regex is a compiled regular expression supporting an interface compatible with lrexlib
--
--   e.g. regex=require("rex_pcre2").new(some regular expression)
--
--   The regular expression should have four captures, starting at the positions of each 
--   of left outer, left inner, right inner, and right outer points
--]]
function module.regex_textobject(regex)
    local function raw_next(params)
        local i,f,t = regex:exec(params.text, params.offset+1)
        if i then
            return {t[1]-1, t[3]-1, t[5]-1, t[7]-1}
        end
    end
    return module.inline_textobject(raw_next, {bytewise=true})
end

return module
