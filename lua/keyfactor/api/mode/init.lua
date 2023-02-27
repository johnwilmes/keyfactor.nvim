local module = {}

local modes = {}
local first_branch = nil
local last_branch = nil

-- ensures we are only doing one start/yield/stop at a time to keep state consistent
local lock = false

local function with_lock(callable)
    return function(...)
        if lock then
            error("attempt to modify modes while modelock is active")
        end

        lock = true
        local success, result = pcall(callable, ...)
        lock = false

        if success then
            return result
        else
            error(result)
        end
    end
end

local function clean_branch(branch)
    -- last mode in branch is dead
    -- remove it and try to resume parents until a resume is successful or branch is empty
    local mode = table.remove(branch.modes)
    local idx = modes[mode].index-1
    modes[mode]=nil
    kf.view.release_windows(mode)
    while idx>0 do
        mode = branch.modes[idx]
        if (not mode._resume) or pcall(mode._resume, mode) then
            -- successfully resumed mode
            return true
        end
        -- failed to resume mode, remove it and try the next one
        kf.view.release_windows(mode)
        idx = idx-1
        modes[mode]=nil
    end

    -- ran out of branch modes without successfully resuming
    -- remove the branch
    if branch==first_branch then
        first_branch = branch.next
    else
        branch.prev.next = branch.next
    end

    if branch==last_branch then
        last_branch = branch.prev
    else
        branch.next.prev = branch.prev
    end
    return false
end

-- start mode on new branch
module.start = with_lock(function(mode, focus)
    local branch = {modes = {}}
    if focus then
        if first_mode then
            branch.next = first_mode
            first_mode.prev = branch
        else
            last_mode = branch
        end
        first_mode = branch
    else
        if last_mode then
            branch.prev = last_mode
            last_mode.next = branch
        else
            first_mode = branch
        end
        last_mode = branch
    end

    branch.modes[1] = mode
    if mode._start and not pcall(mode._start, mode) then
        -- TODO log.warn("error while starting mode")
        clean_branch(branch)
        return false
    end

    return true
end)

module.yield = with_lock(function(child, parent)
    -- child must be mode object that is neither stopped nor started
    if not child or module.is_started(child) then
        -- TODO better validation
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
            branch = init_branch(true)
        end
    end

    local branch_len = #branch.modes
    if branch_len > 0 then
        parent = branch.modes[branch_len]
        if parent._yield and not pcall(parent._yield, parent) then
            -- TODO log.warn("error while yielding parent")
            -- kill the parent
            modes[parent] = nil
            branch.modes[branch_len] = nil
            branch_len = branch_len - 1
        end
    end

    branch_len = branch_len+1
    modes[child] = {branch=branch, index=branch_len}
    branch.modes[branch_len]=child

    if child._start and not pcall(child._start, child) then
        -- TODO log.warn("error while starting child")
        clean_branch(branch)
        return false
    end

    return true
end)

-- mode defaults to focus
module.stop = with_lock(function(mode)
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

    for i=#branch.modes, index+1, -1 do
        -- from end of branch down to child of mode
        local m = branch.modes[i]
        if m._stop and not pcall(m._stop, m) then
            -- TODO log.warn
        end
        kf.view.release_windows(m)
        modes[m]=nil
        branch.modes[i]=nil
    end

    if mode._stop and not pcall(mode._stop, mode) then
        -- TODO log.warn
    end
    kf.view.release_windows(mode)
    clean_branch(branch)
    return true
end)

module.set_focus = with_lock(function(mode)
    local branch = (modes[mode] or {}).branch
    if not branch then
        error("cannot set focus to invalid mode")
    end

    if branch==first_branch then
        return true
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

    return true
end)

function module.is_locked()
    return lock
end

function module.is_focus(mode)
    local record = modes[mode]
    return (not not record) and (record.branch==first_branch)
end

module.get_current_focus = function()
    if not first_branch then
        return nil
    end
    return first_branch.modes[#first_branch.modes]
end

local function get_normal_window()
    local win = vim.api.nvim_get_current_win()
    if vim.fn.win_gettype(win)=="" then
        return win
    end
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.fn.win_gettype(win)=="" then
            return win
        end
    end
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.fn.win_gettype(win)=="" then
            return win
        end
    end
end

-- requires modelock
module.get_focus = with_lock(function ()
    local focus = module.get_current_focus()
    if focus then return focus end

    local win = get_normal_window()
    if not win then
        error("no active modes and no normal windows open")
    end
    local mode = module.Edit{target={window=win}}

    if first_branch then
        -- this should never happen; means first_branch is empty but has not been removed
        -- TODO log debug info
    else
        first_branch = {modes={}}
        last_branch = first_branch
    end
    first_branch.modes[1] = mode
    modes[mode]={branch=first_branch, index=1}
    if mode._start and not pcall(mode._start, mode) then
        clean_branch(branch)
        error("error starting new focus")
    end
    return mode
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

function module.lock_schedule(callback)
    vim.schedule(function()
        if lock then
            error("modelock is deadlocked")
        end
        lock = true
        callback()
        lock = false
    end)
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
    self.insert = kf.controller.Insert({target=self.edit})
    self.layers = kf.controller.Layers(self._layer_init)
end

function module.Edit:_stop()
    if self.insert then
        self.insert:commit()
    end

    self.edit = nil
    self.insert = nil
    self.layers = nil
end

module.Search = utils.class()

function module.Search:__init(opts)
    -- TODO validate
    self._target = opts.target

    local default_layers = {
        groups={"normal", "insert", "prompt"},
    }
    self._layer_init = opts.layers or default_layers

    self.result = {}
end

function module.Search:get_targets()
    if self.edit then
        return {self.edit:get()}
    end
    return {}
end

function module.Search:_start()
    if self._started then
        error("already started")
    end
    self._search_buffer = vim.api.nvim_create_buf(false, true)
    self._search_window = kf.layout.create_window{style="prompt", anchor=self._target.window}
    self.result = {}

    self.edit = kf.controller.Target{buffer=self._search_buffer, window=self._search_window}
    -- TODO fix reinsert/history target for insert
    self.insert = kf.controller.Insert{target=self.edit}
    self.layers = kf.controller.Layers(self._layer_init)
    self.prompt = kf.controller.PromptController()

    -- TODO completion controller?

    self._started = true
end

function module.Search:_stop()
    if self._started then
        local lines = vim.api.nvim_buf_get_lines(self._search_buffer, 0, 1, false)
        self.result.text = lines[1] or ""
        self.result.accept = self.prompt:is_accepted()

        if self.insert then
            self.insert:commit()
        end

        -- TODO self.result.text gets pushed to search history

        self.edit = nil
        self.insert = nil
        self.layers = nil
        self.prompt = nil

        kf.layout.release_window(self._search_window)
        vim.api.nvim_buf_delete(self._search_buffer, {force=true})
        self._started = false
    end
end

module.GetKey = utils.class()

function module.GetKey:__init(opts)
end

function module.GetKey:_start()
    self.layers = kf.controller.Layers{groups={prompt=true}, layers={getkey=true}}
    self.prompt = kf.controller.PromptController()
end

function module.GetKey:_stop()
    if self.prompt then
        self.result = {
            keys = self.prompt:get_keys(),
            accept = self.prompt:is_accepted()
        }
        self.layers = nil
        self.prompt = nil
    end
end


