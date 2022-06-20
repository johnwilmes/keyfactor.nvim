--[[
    per buffer:
        - just take the whole multirange, but also put in extranges
--]]

local kf_range = require("keyfactor.range")

local selection = {inner = {namespace=vim.api.nvim_create_namespace('KeyfactorSelectionInner'),
                        style = {hl_group='KeyfactorSelectionInner', priority=1010},
                        active_style = {hl_group='KeyfactorActiveInner', priority=1060},
                   }, outer = {namespace=vim.api.nvim_create_namespace('KeyfactorSelectionOuter'),
                        style = {hl_group='KeyfactorSelectionOuter', priority=1000},
                        active_style = {hl_group='KeyfactorActiveOuter', priority=1050},
                   }, focus = {namespace=vim.api.nvim_create_namespace('KeyfactorSelectionFocus'),
                            style={priority=1020},
                            active_style={priority=1070},
                   },
}

function selection:get(buffer)
    local buf_sel = self.index[buffer]
    if not buf_sel then
        return {}
    end
    local updated = {}
    for id, range in ipairs(buf_sel) do
        local inner_row, inner_col, inner_details = vim.api.nvim_buf_get_extmark_by_id(buffer,
            self.inner.namespace, id, {details=true})
        local outer_row, outer_col, outer_details = vim.api.nvim_buf_get_extmark_by_id(buffer,
            self.outer.namespace, id, {details=true})
        updated[id] =  range:new({bounds = {{outer_row, outer_col},
                                            {inner_row, inner_col},
                                            {inner_details.end_row, inner_details.end_col},
                                            {outer_details.end_row, outer_details.end_col}}})
    end
    return buf_sel:new(updated)
end

function selection:set(buffer, multirange)
    self.index[buffer] = multirange
    vim.api.nvim_buf_clear_namespace(buffer, self.inner.namespace, 0, -1)
    vim.api.nvim_buf_clear_namespace(buffer, self.outer.namespace, 0, -1)
    vim.api.nvim_buf_clear_namespace(buffer, self.focus.namespace, 0, -1)

    if #multirange == 0 then
        return
    end

    for id, range in ipairs(multirange) do
        for name, inner in pairs({inner=true, outer=false}) do
            bounds = range:get_bounds(inner)
            vim.api.nvim_buf_set_extmark(self.buffer, self[name].namespace, bounds[1][1], bounds[1][2],
                {id=id, hl_group=self[name].style.hl_group, priority=self[name].style.priority,
                 end_row=bounds[1][1], end_col=bounds[2][2]})
        end
        local focus = range:get_focus()
        vim.api.nvim_buf_set_extmark(buffer, self.focus.namespace, focus[1], focus[2],
            {id=id, priority=self.focus.style.priority})
    end

    local active = multirange[multirange.active]
    for name, inner in pairs({inner=true, outer=false}) do
        bounds = active:get_bounds(inner)
        vim.api.nvim_buf_set_extmark(self.buffer, self[name].namespace, bounds[1][1], bounds[1][2],
            {id=id, hl_group=self[name].active_style.hl_group, priority=self[name].active_style.priority,
             end_row=bounds[1][1], end_col=bounds[2][2]})
    end
    local focus = active:get_focus()
    vim.api.nvim_buf_set_extmark(buffer, self.focus.namespace, focus[1], focus[2],
        {id=id, priority=self.focus.active_style.priority})
end

return module
