local module = {}

module.InsertController = utils.class()

function module.InsertController:__init(opts)
    self._target = opts.target
    -- TODO validate opts.target
    if not opts.target then
        error("target required")
    end
    local target = self._target:get()
    self._buffer = target.buffer
    self._selection = target.selection
    self._undo_node = kf.undo.create_node(self._selection)

    self._history = {}
    self._redo = opts.namespace or "insert"
    self._position = opts.position or "inner"
    self._multiline = true -- TODO single line?
end

function module.InsertController:_do_insert(value, kind)
    -- kind should be literal, vim, or action

    local target = self._target:get()
    if target.buffer~=self._buffer or target.selection~=self._selection then
        self:commit()
        self._buffer = target.buffer
        self._selection = target.selection
        self._undo_node = kf.undo.create_node(self._selection)
    end
    
    if kind=="literal" or kind=="vim" then
        local selection = kf.insert[kind](selection, self._position, value)
        self._target:set({selection=selection})
    else -- kind=="action"
        value({target=self._target, insert=self})
    end

    local prev = self._history[#self._history]
    if prev and kind==prev.kind then
        prev[#prev+1]=value
    else
        table.insert(self._history, {value, kind=kind})
    end

    target = self._target:get()
    if append and target.buffer==self._buffer then
        kf.undo.join(target.selection, self._undo_node)
    else
        self._buffer = target.buffer
        self._selection = target.selection
        self._undo_node = kf.undo.create_node(target.selection)
    end
end

function module.InsertController:get_position()
    return self._position
end

function module.InsertController:get_namespace()
    return self._namespace
end

function module.InsertController:set_namespace(namespace)
    if type(namespace)=="string" and namespace~=self._namespace then
        self:commit()
        self._namespace = namespace
    end
end

function module.InsertController:commit()
    if #self._history > 0 then
        local reduced = {}
        for _,a in ipairs(self._history) do
            if a.kind=="literal" or a.kind=="vim" then
                reduced[reduced+1]=get_insert_action(a.kind, table.concat(a))
            else -- a.kind=="action"
                vim.list_extend(reduced, a)
            end
        end
        -- TODO:
        kf.redo.set(self._namespace, reduced)
        self._history = {}
    end
end

function module.InsertController:text(value)
    self:_do_insert(value, "literal")
    return true
end

function module.InsertController:linebreak()
    if self._multiline then
        self:_do_insert("\n", "vim")
        return true
    end
    return false
end

function module.InsertController:indent()
    self:_do_insert("\t", "vim")
    return true
end

local bs = vim.api.nvim_replace_termcodes("<bs>", true, true, true)
local del = vim.api.nvim_replace_termcodes("<del>", true, true, true)
function module.InsertController:delete(opts)
    if not opts.textobject then
        local char = (opts.reverse and bs) or del
        self:_do_insert(char, "vim")
        return true
    end
    --TODO implement textobject deleting
    return false
end

function module.InsertController:capture(action)
    self:_do_insert(action, "action")
end

return module
