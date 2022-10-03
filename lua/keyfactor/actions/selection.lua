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
local function get_partial_side(pos, next_range, params)
    local sides = {next_range["left"], next_range["right"]}
    --[[
        filter sides: remove anything that isn't on the desired side of pos
            (as determined by params.reverse, comparing based on params.orientation.boundary)

        sort sides (reversed in params.reverse)

        return first element of sides
    --]]
    if params.reverse then
        sides = utils.list.filter(sides, function(v) return v[params.orientation.boundary] < pos end)
        sides = utils.list.sort(sides, function(v) return v[params.orientation.boundary] end)
        return sides[#sides]
    else
        sides = utils.list.filter(sides, function(v) return v[params.orientation.boundary] > pos end)
        sides = utils.list.sort(sides, function(v) return v[params.orientation.boundary] end)
        return sides[1]
    end

end

module.select_textobject = action(function(params)
    local selection = params.selection

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
                },
                reverse = params.reverse,
                buffer = params.buffer,
            }
            if not params.partial then
                tobj_params.orientation.side=params.orientation.side
            end

            local inverse = kf.invert_orientation(params.orientation)
            for entry in selection:iter() do
                local range = entry.range:read()
                local pos = range[params.orientation]
                tobj_params.position = pos
                local next_range = params.textobject:get_next(tobj_params)
                if next_range~=nil and (params.augment or params.partial) then
                    local new, old
                    if params.augment then
                        old = range[inverse.side]
                        if params.partial then
                            new = get_partial_side(pos, next_range, params)
                        else
                            new = next_range[params.orientation.side]
                        end
                        if inverse.side=="left" then
                            pos = old[2]
                        else
                            pos = old[1]
                        end
                    else -- params.augment = false, params.partial = true
                        old = range[params.orientation.side]
                        new = get_partial_side(pos, next_range, params)
                    end

                    -- truncate new to old
                    local better
                    if params.reverse then
                        better = function(i,v) return utils.min(v, pos) end
                    else
                        better = function(i,v) return utils.max(v, pos) end
                    end
                    new = utils.list.map(new, better)
                    local bounds = {old[1], old[2], new[1], new[2]}
                    table.sort(bounds)
                    entry.range:write(kf.range(bounds))
                elseif not params.augment then
                    entry.range:write(next_range)
                end -- else params.augment = true and next_range = nil; do nothing
            end
        end
    end
end, {"selection", "orientation"})

return module

