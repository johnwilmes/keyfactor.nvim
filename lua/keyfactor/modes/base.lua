local oo = require("loop.simple")
local function super(obj) return oo.getsuper(oo.getclass(obj)) end

local module = {}

-- should a model already have a frame?
module.Observable = oo.class({__new = require("loop.hierarchy").mutator})

function module.Observable:__init()
    self._active = true
    self._observers = {} -- sorted by decreasing priority
end

function module.Observable:is_active()
    return self._active
end

function module.Observable:stop()
    if self:is_active() then
        self._active = false

        self:_broadcast("detach")
        self._observers = {}
    end
end

--[[

Broadcast frequent: should not require sorting
Attach infrequent: okay to do O(n) insertion
Detach very infrequent: typically will not detach individual observers, just clear them all (O(1)), so
O(n) okay

--]]

function module.Observable:_broadcast(event, details)
    for _,x in ipairs(self._observers) do
        observer = x.observer
        if utils.is_callable(observer[event]) then
            observer[event](observer, details)
        end
    end
end

function module.Observable:attach(observer, priority)
    --TODO get rid of magic literal 100
    if type(priority)~="number" then priority=100 end
    if self:is_active() then
        local i = 1
        while i<=#self._observers and priority<=self._observers[i].priority do
            i = i+1
        end
        table.insert(self._observers, i, {priority=priority, observer=observer})
        if utils.is_callable(observer.attach) then observer:attach() end
    end
end

function module.Observable:detach(observer)
    for i,x in ipairs(self._observers) do
        if x.observer == observer then
            table.remove(self._observers, i)
            if utils.is_callable(observer.detach) then observer:detach() end
            break
        end
    end
end

module.Observer = oo.class({__new = require("loop.hierarchy").mutator})

module.Mode = oo.class({}, module.Observer)

function Mode:__init(opts)
    self.frame = kf.get_frame(opts.frame or 0) -- TODO
    self.model = Observable() -- most modes will override this
end

function Mode:async()
    self._mode_handle = kf.get_mode(self.frame)
    self.model:attach(self, 0) -- TODO get rid of magic literal 0
end

function Mode:await()
    self._awaiting = true
    self:async()
    kf.yield(self.frame)
    return self.model
end

function Mode:detach()
    kf.pop_mode(self.frame, self._mode_handle, true) -- pop everything above self._mode_handle; true = exclusive of mode_handle
    if self.model:is_active() then
        -- Failsafe in case mode is detached before the model stops. This should not happen
        -- Note: in this case observers with lower priority than self won't reliably trigger after
        self.model:stop()
    end

    if self._awaiting then
        kf.resume(self.frame, self._mode_handle)
        self._awaiting = false
    end
end

return module
