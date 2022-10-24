local module = {}

local selection_mt = {}

--[[
local right_gravity = {
    inner = {inner={true, false}, outer={true, false}},
    outer = {inner={false, true}, outer={false, true}},
    left = {inner={false, false}, outer={false, false}},
    right = {inner={true, true}, outer={true, true}},
}
]]

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

function selection_mt:__gc()
    vim.api.nvim_buf_clear_namespace(self.buffer, self._ns.inner, 0, -1)
    vim.api.nvim_buf_clear_namespace(self.buffer, self._ns.outer, 0, -1)
end

function selection_mt:get_range(id)
    -- TODO validate id
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

function selection_mt:set_gravity(id, right_gravity)
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
        selection:set_gravity(id, kf.orientable{false})
        if id==selection.length then
            return nil
        else
            id=id+1
        end
    end
    return id, selection:get_range(id)
end

function selection_mt:iter(offset)
    --[[
        first, set all extmarks to right gravity
        at the time each range is processed, set current extmarks to left gravity

        This way, editing when editing the contents of a range during iteration, the other ranges
        are unaffected and properly update

    Note that having two simultaneous iterations over same selection, or setting gravity of ranges
    other than current iterand, might produce bad results
    --]]

    for id=1,self.length do
        self:set_gravity(id, kf.orientable{true})
    end
    return get_next_range, self
end

function selection_mt:get_child(new_ranges)
    local child = get_new_selection(self.buffer, new_ranges)
    --[[ TODO when a selection is set as the active selection for a window+buffer,
            follow _parent links to discover whether new selection is descendant of former active
            selection. If so, use the _lineage records to describe relationship between former
            ranges and new ranges.

            When this happens, we can delete _parent and replace it with e.g. an _active record, so
            that parent garbage collection can happen
    ]]
    child._parent = self
    child._lineage = new_ranges
    return child
end


local function get_new_selection(buffer, ranges)
    if buffer==0 then buffer=vim.api.nvim_get_current_buf() end

    ranges = -- TODO flatten ranges table, sort ranges, and truncate ranges so they don't overlap

    local selection = {
        buffer=buffer
        id = --TODO new id,
        length = #ranges,
        _cache = ranges,
        _changedtick = vim.api.nvim_buf_get_changedtick,
        _ns = {inner=vim.api.nvim_create_namespace(""), outer=vim.api.nvim_create_namespace("")},
    }

    local gravity = kf.orientable{true}
    for id,range in ipairs(ranges) do
        set_selection_extmark(buffer, selection._ns, id, range, gravity)
    end

    return setmetatable(selection, selection_mt)
end

local module_mt = {
    __call = get_new_selection
}

return setmetatable(module, module_mt)
