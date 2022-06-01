local kf = require("keyfactor.base")


local module = {}

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
        inner = boolean - whether we consider the inner or outer boundary of the textobject in
                determining its position. (I'll just always have this set to true, but in principle
                it could be set to false)
        stretch = boolean - passed to range:update
        exterior = boolean - reverse xor exterior is true iff we consider the left side of the
                textobject in determining its position. 
                Additionally, if exterior is true, the new selection is given by combining the
                focus side of the current selection with the appropriate (nearer) side of the
                chosen text object
        augment = boolean - whether we replace current selection vs extend/reduce it
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
                range = delta:new{focus={reverse=params.reverse,
                                         inner=range.focus.inner}}
            else
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
