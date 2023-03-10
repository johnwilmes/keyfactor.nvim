local module = {}

module.events = {
    start = {},
    stop = {},
    yield = {},
    resume = {},
    focus = {},
    unfocus = {}
}

local modes = {}
local first_branch = nil
local last_branch = nil

-- branch:
--      { modes = {list of modes; lower index yields to higher index};
--        prev = prev branch
--        next = next branch
--      }

local function validate_mode(mode)
    -- TODO possibly more...
    return type(mode)=="table"
end

local function notify_branch(branch, event)
    for _,m in ipairs(branch.modes) do
        kf.events.enqueue(m, event)
    end
end

-- start mode on new branch
-- focus: boolean
-- if true, start mode as first branch; if false start mode as last branch
function module.start(mode, focus)
    if not validate_mode(mode) or module.is_started(mode) then
        error("cannot start invalid mode")
    end

    local branch = {modes = {}}
    if focus then
        if first_branch then
            branch.next = first_branch
            first_branch.prev = branch
        else
            last_mode = branch
        end
        first_branch = branch
    else
        if last_mode then
            branch.prev = last_mode
            last_mode.next = branch
        else
            first_branch = branch
        end
        last_mode = branch
    end

    branch.modes[1] = mode
    kf.events.enqueue(mode, module.events.start)
    if branch==first_branch then
        kf.events.enqueue(mode, module.events.focus)
    end
end

function module.yield(child, parent)
    -- child must be mode object that is neither stopped nor started
    if not validate_mode(child) or module.is_started(child) then
        error("cannot yield to invalid child")
    end

    local branch
    if parent then
        branch = (modes[parent] or {}).branch
        if not branch then
            error("cannot yield from invalid parent")
        end
    else
        branch = first_branch
        if not branch then
            module.start(child)
            return
        end
    end

    local branch_len = #branch.modes
    if branch_len > 0 then
        parent = branch.modes[branch_len]
        kf.events.enqueue(parent, module.events.yield)
    end

    branch_len = branch_len+1
    modes[child] = {branch=branch, index=branch_len}
    branch.modes[branch_len]=child

    kf.events.enqueue(child, module.events.start)
    if branch==first_branch then
        kf.events.enqueue(child, module.events.focus)
        if branch.next then
            notify_branch(branch.next, module.events.unfocus)
        end

    end
end

-- mode defaults to focus
function module.stop(mode)
    local branch, index
    if mode then
        record = modes[mode]
        if not record then
            error("cannot stop invalid mode")
        end
        branch = record.branch
        index = record.index
    else
        branch = first_branch
        if not branch then
            error("no mode to stop")
        end
        index = #branch.modes
        mode = branch.modes[index]
    end

    for i=#branch.modes, index, -1 do
        -- from end of branch down to child of mode
        local m = branch.modes[i]
        modes[m]=nil
        branch.modes[i]=nil
        kf.events.enqueue(m, module.events.stop)
    end

    if index==0 then
        -- remove the branch
        if branch==first_branch then
            first_branch = branch.next
            if first_branch then
                notify_branch(first_branch, module.events.focus)
            end
        else
            branch.prev.next = branch.next
        end

        if branch==last_branch then
            last_branch = branch.prev
        else
            branch.next.prev = branch.prev
        end
    else
        -- resume the parent
        kf.events.enqueue(branch.modes[index-1], module.events.resume)
    end
end

function module.set_focus(mode)
    local branch = (modes[mode] or {}).branch
    if not branch then
        error("cannot set focus to invalid mode")
    end

    if branch==first_branch then
        return
    end

    branch.prev.next = branch.next
    if branch==last_branch then
        last_branch = branch.prev
    else
        branc.next.prev = branch.prev
    end

    branch.prev=nil
    branch.next=first_branch
    first_branch.prev = branch
    first_branch = branch
    notify_branch(first_branch, module.events.focus)
    notify_branch(first_branch.next, module.events.unfocus)
end




function module.is_focus_branch(mode)
    local record = modes[mode]
    return (not not record) and (record.branch==first_branch)
end

function module.get_focus()
    if not first_branch then
        return nil
    end
    return first_branch.modes[#first_branch.modes]
end

function module.is_started(mode)
    return not not modes[mode]
end

function module.get_parent(mode)
    local record = modes[mode]
    if record then
        return record.branch.modes[record.length-1]
    end
    return nil
end

function module.get_child(mode)
    local record = modes[mode]
    if record then
        return record.branch.modes[record.length+1]
    end
    return nil
end

function module.get_branch(mode)
    local record = modes[mode]
    if record then
        return {unpack(record.branch.modes)}, record.index, record.branch==first_branch
    end
end

function module.list_branches()
    local result = {}
    local branch = first_branch
    while branch~=nil do
        result[#result]={unpack(branch.modes)}
        branch = branch.next
    end
    return result
end




module.Edit = utils.class()

function module.Edit:__init(opts)
    -- TODO validate opts?
    opts = opts or {}

    -- TODO default opts
    local default_layers = {
        groups={"normal"},
    }

    self._target_init = opts.target
    self._layer_init = opts.layers or default_layers
end

function module.Edit:get_targets()
    if self.edit then
        return {self.edit:get()}
    end
    return {}
end

function module.Edit:_start()
    local target_init = self._target_init
    self.edit = kf.controller.Target(self._target_init)
    self.layers = kf.controller.Layers(self._layer_init)
end

function module.Edit:_stop()
    self.edit = nil
    self.layers = nil
end

return module


