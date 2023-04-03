local utils = require("keyfactor.utils")
local default = require("keyfactor.default")

local module = {}

local is_scheduled = false
local queue = {}
local head = 0
local tail = 0

--[[ keys are sources, values are tables
--          special `nil` event key corresponds to any event/any source
--          (nil/nil disallowed)
--
--      value tables:
--          [event] = {listener table}
--
--      listener table:
--          [handle] = {callable=callable, object=object}
--          
--]]
local attached = {}

--[[ keys are attachment handles, values are tables
--      source = source
--      event = {[evt]=true}
--      once = boolean
--]]
local index = {}

function broadcast(listeners, source, event, details)
    local n_reinserted = 0 -- number of processed listener reinserted
    for h,l in ipairs(listeners) do
        local ok, msg = pcall(l.callable, l.object, source, event, details)
        if not ok then
            -- TODO log msg
        end
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

    local listeners = attached[nil] -- all sources, this event
    if listeners then
        broadcast(listeners[record.event] or {}, record.source, record.event, record.details)
    end

    local listeners = attached[record.source]
    if not listeners then return end

    -- this source, all events
    broadcast(listeners[nil] or {}, record.source, record.event, record.details)
    -- this source, this event
    broadcast(listeners[record.event] or {}, record.source, record.event, record.details)
end

function module.enqueue(source, event, details)
    if type(source)~="table" or type(event)~="table" then
        error("invalid event")
    end
    tail = tail + 1
    queue[tail] = {source=source, event=event, details=details}
    vim.schedule(release_next)
end

--[[
    opts
        listener (callable)
        source
        event
        object (default listener)
        once (boolean; default false)

    either source or event is required
    if event is falsey then attaches to all events from this source.
    otherwise, event is table or list of tables and only receives matching events

    listener will receive
        listener(object, source, event, details)
--]]
function module.attach(opts)
    if not utils.is_callable(opts.listener) then
        error("invalid listener")
    end
    local object = opts.object or opts.listener
    local event
    if vim.tbl_islist(opts.event) and #event>0 then
        event = utils.list.to_flags(opts.event)
    elseif type(opts.event="table") then
        event = {[opts.event]=true}
    else
        event = {[nil]=true}
    end

    local source
    if type(opts.source)=="table" then
        source=opts.source
    elseif not opts.source then
        if type(opts.event)~="table" then
            error("valid source or event required")
        end
        source = nil
    else
        error("invalid source")
    end


    local handle = #index+1
    index[handle] = {source=source, event=event, once=not not opts.once}
    local source_listeners = utils.table.set_default(attached, source)
    local listener = {callable=opts.listener, object=object}
    for e,_ in pairs(event) do
        local event_listeners = utils.table.set_default(source_listeners, e)
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
            for e,_ in pairs(listener.event) do
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
        event - single event, list of events, boolean, or nil
        listener - callable or nil
        object

    clears all listeners for source that match all specified opts
        (if event is falsey, matches only listeners attached to "all" event; if event is true,
        then matches listeners attached to specific events as well as all event)
--]]
function module.clear(source, opts)
    if not source then source = nil end

    local listeners = attached[source]
    if not listeners then
        return
    end

    local event

    if type(opts.event)=="table" then
        if #event==0 then
            -- opts.event is a specific event
            event = {[opts.event]=true}
        else
            event = utils.list.to_flags(opts.event)
        end
    elseif not event then
        event = {[nil]=true}
    else
        event = utils.list.to_flags(utils.table.keys(listeners))
    end

    for e,_ in pairs(event) do
        local event_listeners = listeners[e]
        for h,l in pairs(event_listeners) do
            if (opts.object==nil or opts.object==l.object) and
                (opts.listener==nil or opts.listener==l.callable) then
                event_listeners[h]=nil
                l_index = index[h]
                if l_index then
                    l_index.event[e]=nil
                    if vim.tbl_isempty(l_index.event) then
                        index[h]=nil
                    end
                end
            end
        end
    end
end


return module
