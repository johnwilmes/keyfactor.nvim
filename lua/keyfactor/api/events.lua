local utils = require("keyfactor.utils")
local default = require("keyfactor.default")

local module = {}

module.Channel = utils.class()

function module.Channel:__init(opts)
    self._observers = {} -- sorted by decreasing priority
    self._source = opts.source or self
end

--[[

Broadcast frequent: should not require sorting
Attach infrequent: okay to do O(n) insertion
Detach very infrequent: typically will not detach individual observers, just clear them all (O(1)), so
O(n) okay

--]]

--[[ broadcast to high priority observers first ]]
function module.Channel:broadcast(event, ...)
    for _,attached in ipairs(self._observers) do
        self:_send(attached, event, ...)
    end
end

function module.Channel:_send(attached, event, ...)
    local observer = attached.observer
    local obj = attached.object or observer
    local source = attached.source or self._default_source
    observer(obj, source, event, ...)
end

function module.Channel:attach(observer, opts)
    -- TODO validate utils.is_callable(observer)
    opts = opts or {}
    local handle = {}
    local priority = opts.priority
    if type(priority)~="number" then priority=default.priority.channel end
    local i = 1
    while i<=#self._observers and priority<=self._observers[i].priority do
        i = i+1
    end
    local attached = {
        handle=handle,
        priority=priority,
        observer=observer,
        object=opts.object,
        source=opts.source
    }
    table.insert(self._observers, i, attached)
    self:_send(attached, "attach")
    return handle
end

function module.Channel:detach(handle)
    for i,attached in ipairs(self._observers) do
        if attached.handle == handle then
            table.remove(self._observers, i)
            self:_send(attached, "detach")
            break
        end
    end
end

function module.Channel:clear()
    self:broadcast("detach")
    self._observers = {}
end

module.Observer = utils.class()

function module.Observer:__init(opts)
    self._channels = {}
    self._is_stopped = false

    local default_object = opts.object or self
    local default_source = opts.source or nil
    local default_priority = opts.priority or nil

    for id,attachment in ipairs(opts) do
        local opts = {
            object=self,
            source=id,
            priority=attachment.priority or default_priority,
        }
        self._channels[id] = {
            channel = attachment.channel,
            object = attachment.object or default_object,
            source = attachment.source or default_source,
            handle = attachment.channel:attach(self.receive, opts)
            events = attachment.events,
        }
    end
end

function module.Observer:receive(channel, event, ...)
    if self._is_stopped then
        -- e.g., don't pass through detach events that result from calling self:stop()
        return
    end
    local channel = self._channels[channel]
    if not channel then
        -- TODO log warning
        return
    end
    local event = channel.events[event]
    if utils.is_callable(event) then
        event(channel.object, channel.source, ...)
    end
end

function module.Observer:stop()
    if not self._is_stopped then
        self._is_stopped = true
        for _,channel in ipairs(self._channels) do
            channel.channel:detach(handle)
        end
    end
end


local synchronizer = Channel()

function synchronizer:catch()
    self._is_scheduled = true
end

function synchronizer:schedule()
    if not self._is_scheduled then
        self._is_scheduled = true
        vim.schedule(function() self:release() end)
    end
end

function synchronizer:release()
    self._is_scheduled = false
    self:broadcast("release")
end

function module.get_synchronizer()
    return synchronizer
end

local buffer_channel = {}
local window_channel = {}

local buffer_text_queue = {}
local buffer_tick_queue = {}

local function schedule_buffer_update(event, buffer)
    buffer_tick_queue[buffer]=true
    if event~="changedtick" then
        buffer_text_queue[buffer]=true
    end
    synchronizer:schedule()
end

local function release_buffer_updates(buffer)
    local channel = buffer_channel[buffer]
    if channel then
        if buffer_text_queue[buffer] then
            buffer_text_queue[buffer]=false
            channel:broadcast("text")
        end
        if buffer_tick_queue[buffer] then
            buffer_tick_queue[buffer]=false
            channel:broadcast("tick")
        end
    end
end

synchonizer:attach(function(_, _, event)
    if event=="release" or event=="detach" then
        -- copy keys for safe iteration
        for _,buffer in ipairs(utils.table.keys(buffer_tick_queue)) do
            release_buffer_updates(buffer)
        end
    end
end)





synchronizer:attach({
    release = function()
        for window, events in pairs(pending_window_events) do
            local channel = window_channel[window]
            if channel then
                for event, details in pairs(events) do
                    channel:broadcast(event, unpack(details))
                end
            end
        end
        pending_window_events = {}

        for buffer, events in pairs(pending_buffer_events) do
            local channel = buffer_channel[buffer]
            if channel then
                for event, details in pairs(events) do
                    channel:broadcast(event, unpack(details))
                end
            end
        end
        pending_buffer_events = {}
    end
})

function module.get_buffer_channel(buffer)
    --[[ events
    --      text (if the contents of the buffer change)
    --      tick (if the changedtick incremented, regardless of whether text changed)
    --]]
    local buffer, valid, loaded = kf.get_buffer(buffer)
    if not valid then
        error("invalid buffer")
    end
    if not loaded then
        -- TODO subscribe to autocmd waiting for buffer to be loaded?
        -- unclear if relevant autocmd exists, maybe BufRead or BufEnter
        error("can't observe unloaded buffer")
    end
    if not buffer_channel[buffer] then
        buffer_channel[buffer] = module.Channel({source=buffer})
        vim.api.nvim_buf_attach(buffer, false, {
            on_lines=schedule_buffer_update,
            on_reload=schedule_buffer_update,
            on_changed_tick=schedule_buffer_update,
            on_detach=function()
                -- happens immediately
                local channel = buffer_channel[buffer]
                if channel then
                    release_buffer_updates(buffer)
                    channel:clear()
                    buffer_channel[buffer]=nil
                end
            end,
        })
    end
    return buffer_observerable[buffer]
end

local event_type = {
    WinEnter = "focus",
    WinLeave = "unfocus",
    WinScrolled = "viewport",
    BufWinEnter = "buffer",
}
vim.api.nvim_create_autocmd({"WinEnter", "WinLeave", "WinScrolled", "BufWinEnter", "WinClosed"}, {
-- TODO check that BufWinEnter triggers reliably
    callback = function(desc)
        local window = vim.api.nvim_get_current_win()
        local event = event_type[desc.event]
        if not event then
            return
        end
        local channel = window_channel[window]
        if channel then
            channel:broadcast(event)
        end
    end
})

vim.api.nvim_create_autocmd({"TabEnter", "TabLeave"} {
    callback = function(desc)
        local windows = vim.api.nvim_tabpage_list_wins(0)
        local event = (desc.event=="TabEnter" and "unhide") or "hide"
        for _,window in ipairs(windows) do
            local channel = window_channel[window]
            if channel then
                channel:broadcast(event)
            end
        end
    end
})

vim.api.nvim_create_autocmd("WinClosed", {
    callback = function()
        local window = vim.api.nvim_get_current_win()
        local obs = window_channel[window]
        if obs then
            obs:clear()
            window_channel[window]=nil
        end
    end
})

function module.get_window_channel(window)
    --[[ events:
    --      focus (if we enter the window, WinEnter)
    --      unfocus (if we leave the window, WinLeave)
    --      buffer (if which buffer the window displays is changed, BufWinEnter)
    --      unhide (if the window becomes visible as a result of tab page change, TabEnter)
    --      hide (if window becomes invisible as a result of tab page change, TabLeave)
    --      viewport (if scrolled or resized, WinScrolled)
    --      detach (when the window closes, WinClosed)
    --]]
    local window, valid = kf.get_window(window)
    if not valid then
        error("invalid window")
    end
    if not window_channel[window] then
        window_channel[window] = module.Channel({source=window})
    end
    return window_channel[window]
end

return module
