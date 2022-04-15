module = {}
module.operator = {}

function module.operator:exec(params)
    --[[
        - this doesn't work for delete, particularly with linewise, it can end up with too many
        lines being deleted (e.g. imagine two separate ranges on the same line)
        - need to yank first
    --]]
    for range in params.selection:iter() do
        self:operate(range, params)
    end
end

--[[
    Paste options:
    
    Dealing with mismatch between register and selection cardinality:
        - larger selection than register: only paste until register cardinality exhausted. result
        is lower-cardinality selection (could be called "truncate")
        - larger selection than register: re-start pasting from first register position (could be
        called "rotate")

        - larger register than selection: only past until selection cardinality exhauted. (could
        also be called "truncate")
        - join, and paste all at the active selection?

    Register "type"?
        - just ignore it, and paste either char-wise or line-wise

        - standard vim "linewise" type actually mostly determines *where* the pasting happens -
        inserted between existing lines, or inserted between characters of current line.
        - but register "type" also perhaps includes information about separators

    Idea: yanking with "boundary=both" (or with linewise=true) sets a non-nil register type.
    Can have separate register type for each end (e.g. if you start selecting a word on the left
    end but then augment to something charwise on the right end. 

    Alternate idea: textobject-based selection can query object for separator at either end,
    regardless of 


--]]
module.paste = module.operator:new()
function module.paste:exec(multirange, params)
    local register = {name=params.register}
    
    
end


--[[
    TODO:
        - flag that this operation doesn't change buffer... (for undo stuff...)
        - repeat with same register should be no-op...
--]]
module.yank = module.operator:new()
function module.yank:exec(multirange, params)
    local boundary = params.boundary
    if (boundary == boundary.focus) then
        return
    end
    if (boundary == boundary.all) then
        boundary = boundary.outer
    end
    local result = {}
    local buffer = params.buffer or 0
    for range in params.selection:iter() do
        local left, right = range:get_bounds(boundary)
        local text
        if params.linewise then
            -- TODO separator is automatically linewise
            text = vim.api.nvim_buf_get_lines(buffer, left[1], right[1]+1, false)
        else
            text = utils.buf_get_text(buffer, left, right)
        end

        if params.autoseparate then
            --[[
            check for presence of separator on left and right sides
            if no separator present, but separator/textobject type is available, insert generic
                instance of separator
            --]]
        end

        table.insert(result, text)
    end
    local register = {name=params.register}
    if params.linewise then register['type'] = 'line' end
    require('keyfactor.register').push(register, result)
end


module.delete = module.operator:new()
function module.delete:exec(multirange, params)
    --[[
        Merge, then yank, then delete.
    --]]
    local boundary = params.boundary
    if (boundary == boundary.focus) then
        return
    end
    if (boundary == boundary.all) then
        boundary = boundary.outer
    end
    local buffer = params.buffer or 0
    multirange = multirange:merge(boundary, params.linewise)
    module.yank:exec(multirange, params)
    for range in multirange do
        local left, right = range:get_bounds(boundary)
        local replacement = {}
        if params.autoseparate then
            --[[
                compute what separator will be left behind
                    - if both left and right separators are identical, keep one of them
                    (for word: always take separator to be exactly one space

                replacement = {separator}
            --]]
        end
        if params.linewise then
            -- TODO, never a separator?
            vim.api.nvim_buf_set_lines(buffer, left[1], right[1]+1, false, replacement)
        else
            vim.api.nvim_buf_set_text(buffer, left[1], left[2], right[1], right[2], replacement)
        end
    end
end
