local utils = require("keyfactor.utils")
local default = require("keyfactor.default")

local module = {}

local is_scheduled = false
local queue = {}
local head = 0
local tail = 0

--[[ keys are sources, values are tables mapping event key to list of listener keys
--          special `true` event key corresponds to any event
--]]
local attached = {}
local index = {}

function broadcast(listeners, source, event, details)
    local n_reinserted = 0 -- number of processed listener reinserted
    for h,l in ipairs(listeners) do
        l.callable(l.object, source, event, details)
        local once = (index[h] or {}).once
        if once then
            module.detach(h)
        end
    end
end

function release_next()
    if head >= tail then
        -- TODO log warning
        return
    end
    head = head + 1
    record = queue[head]
    queue[head] = nil

    local listeners = attached[record.source]
    if not listeners then return end

    broadcast(listeners[true] or {}, record.source, record.event, record.details)
    broadcast(listeners[record.event] or {}, record.source, record.event, record.details)
end

function module.enqueue(source, event, details)
    if not (type(source)=="table" and type(event)=="string") then
        error("invalid event")
    end
    tail = tail + 1
    queue[tail] = {source=source, event=event, details=details}
    vim.schedule(release_next)
end


--[[
    listener (callable)
    opts
        source
        event
        object (default listener)
        once (boolean; default false)

    source is required
    if event is falsey then attaches to all events from this source. otherwise, event is string or
    list of strings and only receives matching events

    listener will receive
        listener(object, source, event, details)
--]]
function module.attach(listener, source, opts)
    local object = opts.object or listener
    local events
    if type(opts.events)=="table" then
        if vim.tbl_islist(opts.events) then
            events = utils.list.to_flags(opts.events)
        else
            error("invalid events list")
        end
    elseif type(opts.events)=="string" then
        events = {[opts.events]=true}
    elseif not opts.events then
        events = {[true]=true}
    else
        error("invalid events list")
    end

    local handle = #index+1
    index[handle] = {source=source, events=events, once=not not opts.once}
    local source_listeners = utils.table.set_default(attached, source)
    local listener = {callable=listener, object=object}
    for e,_ in pairs(events) do
        local event_listeners = utils.table.set_default(attached, source)
        event_listeners[handle]=listener
    end
    return handle
end

function module.detach(handle)
    local listener = index[handle]
    if listener then
        index[handle]=nil
        local source_listeners = attached[listener.source]
        if source_listeners then
            for e,_ in pairs(listener.events) do
                event_listeners = source_listeners[e]
                if event_listeners then
                    event_listeners[handle]=nil
                    if vim.tbl_isempty(event_listeners) then
                        source_listeners[e]=nil
                    end
                end
            end
            if vim.tbl_isempty(source_listeners) then
                attached[listener.source]=nil
            end
        end
    end
end

--[[
    opts:
        events
        callable
        object

    clears all listeners for source that match all specified opts
        (if events is falsey, matches only listeners attached to "all" events; if events is true,
        then matches listeners attached to specific events as well as all events)
--]]
function module.clear(source, opts)
    local listeners = attached[source]
    if listeners then
        local events = opts.events
        if type(events)=="string" then
            events={events}
        elseif not events then
            events={true}
        elseif events==true then
            events=utils.table.keys(listeners)
        end

        if type(events)~="table" then
            error("invalid events filter")
        end
        for _,e in ipairs(events) do
            local event_listeners = listeners[e]
            for h,l in pairs(event_listeners) do
                if (opts.object==nil or opts.object==l.object) and
                    (opts.callable==nil or opts.callable==l.callable) then
                    event_listeners[h]=nil
                    l_index = index[h]
                    if l_index then
                        l_index.events[e]=nil
                        if vim.tbl_isempty(l_index.events) then
                            index[h]=nil
                        end
                    end
                end
            end
        end
    end
end






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
