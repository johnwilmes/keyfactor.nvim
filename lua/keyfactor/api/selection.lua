local utils = require("keyfactor.utils")

local module = {}

-- For editing the corresponding part of range: 
module.active_gravity = {
    inner=kf.orientable{false, true},
    before=kf.orientable{false, true, true, true},
    after=kf.orientable{false, false, false, true},
}

-- For when this range is before/after the actively edited part of buffer
module.inactive_gravity = {
    before=kf.orientable{false},
    after=kf.orientable{true},
}

local function set_selection_extmark(buffer, namespace, id, range, gravity)
    for _,boundary in ipairs{"inner", "outer"} do
        local part = range[boundary]
        vim.api.nvim_buf_set_extmark(buffer, namespace[boundary], part[1][1], part[1][2], {
            id=id,
            right_gravity=gravity[boundary][1],
            end_row=part[2][1],
            end_col=part[2][2],
            end_right_gravity=gravity[boundary][2],
            strict=false,
        })
    end
end

local Selection = utils.class()
function Selection:__init(buffer, ranges)
    if buffer==0 then buffer=vim.api.nvim_get_current_buf() end

    ranges = -- TODO flatten ranges table, sort ranges, and truncate ranges so they don't overlap

    self.buffer=buffer
    self.id = {} -- TODO need to coordinate with persistance mechanism
    self.length = #ranges
    self._raw = ranges
    self._ns = {inner=vim.api.nvim_create_namespace(""), outer=vim.api.nvim_create_namespace("")}

    local gravity = module.inactive_gravity.before
    for id,range in ipairs(ranges) do
        set_selection_extmark(buffer, selection._ns, id, range, gravity)
    end
end

function Selection:__del()
    vim.api.nvim_buf_clear_namespace(self.buffer, self._ns.inner, 0, -1)
    vim.api.nvim_buf_clear_namespace(self.buffer, self._ns.outer, 0, -1)
end


function Selection:get_range(id)
    -- TODO validate id
    -- TODO cache?
    local inner = vim.api.nvim_buf_get_extmark_by_id(self.buffer, self._ns.inner, id, {details=true})
    local outer = vim.api.nvim_buf_get_extmark_by_id(self.buffer, self._ns.inner, id, {details=true})
    if #inner==0 or #outer==0 then
        -- TODO error
    end
    local bounds = {
        kf.position{outer[1], outer[2]},
        kf.position{inner[1], inner[2]},
        kf.position{inner[3].end_row, inner[3].end_col},
        kf.position{outer[3].end_row, outer[3].end_col},
    }
    return kf.range(bounds)
end

function Selection:set_gravity(id, right_gravity)
    --[[ right_gravity is list of 4 booleans
    --      - or, table with same indexing interface as range? why not...
    --]]
    local range = self:get_range(id)
    set_selection_extmark(self.buffer, self._ns, id, range, right_gravity)
end


local function get_next_range(selection, id)
    if id==nil then
        id=1
    else
        -- set left gravity to ids we have already processed
        selection:set_gravity(id, module.inactive_gravity.before)
        if id==selection.length then
            return nil
        else
            id=id+1
        end
    end
    return id, selection:get_range(id)
end

function Selection:iter()
    --[[
        first, set all extmarks to right gravity
        at the time each range is processed, set current extmarks to left gravity

        This way, editing when editing the contents of a range during iteration, the other ranges
        are unaffected and properly update

    Note that having two simultaneous iterations over same selection, or setting gravity of ranges
    other than current iterand, might produce bad results
    --]]

    for id=1,self.length do
        self:set_gravity(id, module.inactive_gravity.after)
    end
    return get_next_range, self
end

function Selection:get_child(new_ranges)
    local child = Selection(self.buffer, new_ranges)
    --[[ TODO when a selection is set as the active selection for a window+buffer,
            follow _parent links to discover whether new selection is descendant of former active
            selection. If so, use the _lineage records to describe relationship between former
            ranges and new ranges.

            When this happens, we can delete _parent and replace it with e.g. an _active record, so
            that parent garbage collection can happen
    ]]
    child._parent = self
    child._lineage = new_ranges -- TODO this isn't right
    return child
end

-- reduce to range at position or part given by orientation
function Selection:reduce(orientation)
    local out_ranges = {}
    for i=1,self.length do
        local range = self:get_range(i)
        if range:get_length(orientation) == 1 then
            out_ranges[i]={kf.range{range[orientation]}}
        else
            out_ranges[i]={kf.range(range[orientation])}
        end
    end
    return self:get_child(out_ranges)
end

-- convert entire range to outer, and put empty inner at position given by orientation
function Selection:reduce_inner(orientation)
    local out_ranges = {}
    for i=1,self.length do
        local range = self:get_range(i)
        local part = range[orientation]
        local n = range:get_length(orientation)
        if n==1 then
            out_ranges[i]={kf.range{range[1], part, part, range[4]}}
        elseif n==2 then
            out_ranges[i]={kf.range{range[1], part[1], part[2], range[4]}}
        else
            out_ranges[i]={range}
        end
    end
    return self:get_child(out_ranges)
end



-- TODO put this in some other module
-- TODO is this effectively doing the same as fix_range below?
local function truncate_positions(positions, bound, reverse)
    --[[ truncate positions to bound. if reverse, then ensure all positions are before bound;
    --otherwise, ensure all positions are after bound (by replacing position with bound as needed) ]]
    local truncate
    if reverse then
        truncate = function(i,v) return utils.min(v, bound) end
    else
        truncate = function(i,v) return utils.max(v, bound) end
    end
    return utils.list.map(positions, truncate)
end

--[[ opts: reverse, partial ]]
local function get_next_range(buffer, range, textobject, orientation, opts)
    local pos = range[orientation]
    local boundary = orientation.boundary

    local tobj_params = {
        orientation = {boundary=boundary},
        reverse = opts.reverse,
        buffer = buffer,
        pos = pos,
    }
    if not opts.partial then
        tobj_params.orientation.side=orientation.side
    end
    local next_range = textobject:get_next(tobj_params)

    --[[ alternate orientation: progress is guaranteed using this orientation ]]
    local alt = {
        boundary=boundary,
        side=(opts.reverse and "before") or "after",
    }

    if next_range and opts.partial then
        local old = range[orientation.side]
        local new
        local sides = {next_range["before"], next_range["after"]}
        --[[
            filter sides: remove anything that isn't on the desired side of pos
                (as determined by opts.reverse, comparing based on boundary)

            sort sides (reversed if reverse)

            return first element of sides
        --]]
        if opts.reverse then
            sides = utils.list.filter(sides, function(v) return v[boundary] < pos end)
            sides = utils.list.sort(sides, function(v) return v[boundary] end)
            new = sides[#sides]
        else
            sides = utils.list.filter(sides, function(v) return v[boundary] > pos end)
            sides = utils.list.sort(sides, function(v) return v[boundary] end)
            new = sides[1]
        end

        if new[boundary]==range[alt] then
            -- the new side agrees with the original range
            -- only possible if orientation ~= alt
            -- Note: it's okay to have new[boundary] closer to pos than old[alt]!
            return get_next_range(buffer, range, textobject, alt, opts)
        end

        new = truncate_positions(new, new[boundary], opts.reverse)
        local bounds = {old[1], old[2], new[1], new[2]}
        table.sort(bounds)
        next_range = kf.range(bounds)
    end
    return next_range
end

function Selection:augment_ranges(orientation, deltas)
    local child = {}
    local inverse = kf.orientation.inverse(orientation)
    for idx, range in ipairs(self:get_all()) do
        local new = deltas[idx]
        if new==nil then
            child[idx] = {range}
        else
            local old = range[inverse.side]
            if opts.reverse then new = new["before"]
            else new = new["after"]
            end
            new = truncate_positions(new, old[orientation.boundary], inverse.side=="after")
            local bounds = {old[1], old[2], new[1], new[2]}
            table.sort(bounds)
            child[idx] = {kf.range(bounds)}
        end
    end
end

--[[
    opts:
        reverse (boolean)
        partial (boolean)
]]
function Selection:augment_textobject(textobject, orientation, opts)
    local deltas = {}
    for idx, range in ipairs(self:get_all()) do -- not self:iter since don't need to edit
        deltas[idx] = get_next_range(self.buffer, range, textobject, orientation, opts)
    end
    return self:augment_ranges(orientation, deltas)
end


--[[ opts:
--      reverse
--      partial
--      wrap
--]]
function Selection:next_textobject(textobject, orientation, opts)
    local child = {}
    local wrap, wrap_bound = nil, nil
    for idx, range in selection:iter() do
        local next_range = get_next_range(self.buffer, range, textobject, orientation, opts)
        if next_range==nil and opts.wrap then
            if not wrap then
                if opts.reverse then
                    local line = vim.api.nvim_buf_line_count(self.buffer)-1
                    local col = utils.line_length(self.buffer, line)
                    wrap = kf.range{kf.position{line, col+1}}
                    wrap_bound =kf.position{line, col}
                else
                    wrap = kf.range{kf.position{0,-1}}
                    wrap_bound = kf.position{0,0}
                end
            end

            next_range = get_next_range(self.buffer, wrap, textobject, orientation, opts)
            next_range = kf.range(truncate_positions(next_range, wrap_bound, opts.reverse))
        end
        child[idx]={next_range or range}
    end
    return self:get_child(child)
end

function Selection:subselect_textobject(textobject)
end

function Selection:split_textobject(textobject)
end

local function fix_range(bounds, idx)
    for i=idx-1,1,-1 do
        if bounds[i] > bounds[i+1] then
            bounds[i] = bounds[i+1]
        end
    end
    for i=idx+1,4 do
        if bounds[i] < bounds[i-1] then
            bounds[i] = bounds[i-1]
        end
    end
end

-- TODO
--      row-wise manipulation, raw columns, etc. should all be based on VISUAL column, not byte
--      column

--[[
--  opts:
--      reverse
--      cols - falsey or a list of ranges: replace columns with these columns
--      wrap - if truthy,  decide whether to wrap around depending on whether position at
--          orientation can move
--]]
local function shift_rows(buffer, ranges, orientation, opts)
    local shifted = {}
    local reverse = not not opts.reverse
    local inc = (reverse and -1) or 1
    local buffer = kf.range.buffer(buffer)
    -- boundary[reverse] is the last position in the current direction
    local boundary = {[true] = buffer[1], [false] = buffer[4]}
    local wrap = opts.wrap and (boundary[true]~=boundary[false])
    local or_idx = kf.orientation.index[orientation]

    for idx, range in ipairs(ranges) do
        local bounds = {}
        local leader = range[or_idx]
        local is_wrap = wrap and leader[1]==boundary[reverse][1]
        for j=1,4 do
            local pos = kf.position(range[j])
            if opts.cols then
                -- This may make range invalid (not ordered properly) but we fix it later
                pos[2] = opts.cols[idx][2]
            end
            if is_wrap then
                if pos[1]==boundary[reverse][1] then
                    pos[1]=boudary[not reverse][1]
                else
                    -- we are wrapping, but this position was not yet on the boundary line
                    -- so set it to the very end of the line when we wrap
                    pos = kf.position(boundary[not reverse])
                end
            elseif pos[1]~=boundary[reverse][1] then
                pos[1] = pos[1]+inc
            end -- else, no wrap and already at boundary: do nothing
            fix_range(bounds, or_idx) -- correct things so that range bounds are in order
            shifted[idx] = kf.range(bounds)
        end
    end
    return shifted
end


--[[
--  opts:
--      reverse
--      raw_column
--          - if truthy, prefer raw column for orientation position
--              - also prefer raw column for other positions, subject to constraint that ordering
--              of positions is maintained
--      wrap
--          - if truthy, decide whether to wrap around depending on whether orientation position can move
--]]
function Selection:next_row(orientation, opts)
    local wrap_idx = kf.orientation.index[orientation]
    local shift_opts = {
        reverse=opts.reverse,
        wrap=opts.wrap,
        cols=opts.raw_column and self._raw
    }
    local child = shift_rows(self.buffer, self:get_all(), orientation, shift_opts)
    -- TODO fix me! preserve self._raw columns!
    return self:get_child(child)
end

--[[
--  opts:
--      reverse
--      raw_column
--]]
function Selection:augment_row(orientation, opts)
    local shifted={}
    local shift_opts = {
        reverse=opts.reverse,
        cols=opts.raw_column and self._raw
    }
    local shifted = shift_rows(self.buffer, self:get_all(), orientation, shift_opts)
    -- TODO fix me! preserve self._raw columns!
    return self:augment_ranges(orientation, shifted)
end

                    
function Selection:get_all()
    local all = {}
    for i=1,self.length do
        all[i] = self:get_range(i)
    end
    return all
end

local module_mt = {
    __call = function(_, ...) return Selection(...) end
}
return setmetatable(module, module_mt)
