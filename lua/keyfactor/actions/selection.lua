local kf = require("keyfactor.base")

local module = {}


--[[

    params:
        orientation
            boundary = "inner" or "outer"
            side = "left" or "right"
        reverse (boolean)
        partial (boolean)
        augment (boolean)
        multiple = "split" or "select" or falsey
            (default to "select" if truthy and not "split"?)
        choose = "auto" or "telescope" or "hop" or falsey
            (default to "auto" if truthy and not "telescope" or "hop"?)
        ranges = {...}


--]]
module.select_textobject = Operator()
local function get_partial_side(pos, next_range, params)
    local sides = {next_range["left"], next_range["right"]}
    local index



    local cmp = (params.reverse and "<"
    sides = utils.list.filter(sides, function(v) return v[...] < pos end)

    sides = utils.list.sort(sides, function(v) return v[...] end)

    --[[
        filter sides: remove anything that isn't on the desired side of pos
            (as determined by params.reverse, comparing based on params.orientation.boundary)

        sort sides (reversed in params.reverse)

        return first element of sides
    --]]

end

function module.select_textobject:exec(selection, params)
    if params.multiple then
        if params.augment then
            -- TODO iterate over existing selection, and either subselect or internally split
            -- (if selection is empty, do nothing)
            for entry in selection:iter() do
                local range = entry.range:read()[params.orientation.boundary]
                local matches = params.textobject:get_all{range=range, buffer=params.buffer}
            end
        else
            -- TODO replace selection by selecting from/splitting entire buffer
        end
        if params.choose then
            -- TODO if current (replaced) selection is not empty, use chooser to select a subset of
            -- the ranges
            -- chooser({select multiple, on_confirm=...})
        end
    else
        if params.choose then
            -- TODO if params.choose then select single range from entire buffer (telescope) or
            --      from viewport (hop). Do so regardless of #selection
            -- TODO first restrict to focus
            -- if (params.augment or params.partial) and selection is empty, treat selection as
            --      first line/col of buffer, or if params.reverse then last line/col
            --
            -- chooser({select one, on_confirm=...})
        else
            local tobj_params = {
                orientation = {
                    boundary=params.orientation.boundary,
                    side=(not params.partial) and params.orientation.side,
                },
                reverse = params.reverse,
                buffer = params.buffer,
            }
            local inverse = kf.invert_orientation(params.orientation)
            for entry in selection:iter() do
                local range = entry.range:read()
                local pos = range[params.orientation]
                tobj_params.position = pos
                local next_range = params.textobject:get_next(tobj_params)
                if params.augment then
                    if next_range~=nil then
                        local old = range[inverse.side]
                        local new
                        if params.partial then
                            new = get_partial_side(pos, next_range, params)
                        else
                            new = next_range[params.orientation.side]
                        end
                        -- TODO truncate new to old
                        local bounds = {old[1], old[2], new[1], new[2]}
                        -- TODO sort bounds
                        entry.range:write(kf.range(bounds))
                    end -- else, next_range==nil; range stays the same
                else
                    if next_range~=nil and params.partial then
                        local old = range[params.orientation.side]
                        local new = get_partial_side(pos, next_range, params)
                        -- TODO truncate new to old
                        local bounds = {old[1], old[2], new[1], new[2]}
                        -- TODO sort bounds
                        entry.range:write(kf.range(bounds))
                    else
                        entry.range:write(next_range)
                    end
                end

                local bounds = {}

                
            end
        end
    end
end









module.selector = kf.action:new()

module.select_next = module.selector:new()

module.select_all = module.selector:new()

module.select_telescope = module.selector:new()

module.select_hop = module.selector:new()

-- anchor and cursor both point to places between characters

-- selection affects end with the cursor

-- TODO enable count? or implement generically via action wrapper

--[[
    Params:
        selection (current selection)
        textobject

        reverse = boolean - which direction we search, in the document
        outer = boolean - whether we consider the inner or outer boundary of the textobject in
                determining its position. 
        side = 1 or 2 (default 2) - whether we consider side 1 or side 2 of the textobject in
                determining its position
        exterior = boolean - reverse xor exterior is true iff we consider the left side of the
                textobject in determining its position. 
                Additionally, if exterior is true, the new selection is given by combining the
                focus side of the current selection with the appropriate (nearer) side of the
                chosen text object
        partial = boolean - if current position is within a textobject, only select from position
            to one side of textobject. (or, if exterior, if current position is between
            textobjects). Should this be implied by augment?
        augment = boolean - whether we replace current selection vs extend/reduce it
        stretch = boolean - passed to range:update
]]

function module.select_next:_exec(params)
    local result = {}
    local side = utils.xor(params.reverse, params.exterior)
    local tobj_params = {reverse = params.reverse,
                         inner = params.inner,
                         side = side}
    local update_params = {reverse = side,
                           augment = params.augment,
                           inner = params.inner,
                           stretch = params.stretch}

    for _, range in ipairs(params.selection) do
        local delta = params.textobject:get_next(range:get_focus(), tobj_params)
        if delta then
            if not (params.augment or params.exterior) then
                -- replace 
                range = delta:new{focus={reverse=params.reverse,
                                         inner=range.focus.inner}}
            else
                -- 
                range = range:update(delta, update_params)
            end
            table.insert(result, range)
        end
    end
    return params.selection:new(result)
end

--[[
    Params:
        selection
        textobject

        boundary = "inner", "outer", "both"
        target = "interior", "exterior"
        overlap = "any", "outer", "none"

        Note: boundary refers to the submatches. The outer boundary of the original selection is
        ignored, and only the inner portion is searched. If the outer boundary of the original
        selection is desired, the selection should be reduced to its outer boundary before applying
        this operation
--]]

function module.select_all:_exec(params)
    local result = {}

    for _, range in ipairs(params.selection) do
        local matches = params.textobject:get_all({inner=params.inner, range:get_bounds(params.inner)})
        local subranges = {}
        if params.exterior then
            local current = {bounds={range:get_side(true)}, textobject={range.textobject[1]}}
            for _, match in ipairs(matches:merge(params.inner)) do
                current.bounds[3], current.bounds[4] = match:get_side(false)
                current.textobject[2] = match.textobject[2]
                table.insert(subranges, range:new(current))
                current = {bounds={match:get_side(true)}, textobject={match.textobject[1]}}
            end
            current.bounds[3], current.bounds[4] = range:get_side(false)
            current.textobject[2] = range.textobject[2]
            table.insert(subranges, range:new(current))
        else
            for _, match in ipairs(matches) do
                table.insert(subranges, range:new(current))
            end
        end
        vim.list_extend(result, subranges)
    end

    return params.selection:new(result)
end

function module.select_hop:_exec(params)
    -- use hop to get the thing
end

function module.select_telescope:_exec(params)
    -- use telescope to get one or more things
    -- cancel if nothing selected
end
