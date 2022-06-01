--[[ Everything here is (0,0)-indexed ]]

local kf = require("keyfactor.base")

local module = {}

module.boundary = utils.enum({"inner", "outer", "focus", "all"})
local B = module.boundary


module.range = {focus = {inner = false, side = 2},
                textobject = {}}
local range_mt = {__index = module.range}

function module.range:new(params)
    params = params or {}
    local textobject = params.textobject or self.textobject
    local range = {focus = vim.deepcopy(params.focus or self.focus),
                   textobject = {textobject[1], textobject[2]}}
    setmetatable(range, range_mt)

    -- range._bounds[is_inner] = {left, right}
    --      - is_inner is true or false
    if params.bounds then
        range._bounds = {}
        if #params.bounds == 1 then
            range._bounds[true] = range._bounds[false] = {params.bounds[1], params.bounds[1]}
        elseif #params.bounds == 2 then
            range._bounds[true] = range._bounds[false] = {params.bounds[1], params.bounds[2]}
        elseif #params.bounds == 4 then
            range._bounds[false] = {params.bounds[2], params.bounds[3]} -- outer
            range._bounds[true] = {params.bounds[1], params.bounds[4]} -- inner
        else
            error("Wrong number of bounds")
        end
    elseif params._bounds then
        range._bounds = vim.deepcopy(params._bounds)
    else
        range._bounds = vim.deepcopy(self._bounds)
    end
    return range
end

function module.range:get_focus()
    return self:get_position(unpack(self.focus))
end


function module.range:get_bounds(inner, linewise)
    local result = self._bounds[not (not inner)]
    if linewise then
        return utils.round_to_line(unpack(result))
    end
    return unpack(result)
end

function module.range:get_side(side, linewise)
    -- return in order: inner, outer
    local result = {self._bounds[true][side], self._bounds[false][side]}
    if linewise then
        return utils.round_to_line(unpack(result))
    end
    return unpack(result)
end

function module.range:get_position(inner, side, linewise)
    local bounds = {self:get_bounds(inner, linewise)}
    return bounds[side]
end

function module.range:get_all(linewise)
    local result = {self._bounds[false][1], self._bounds[true][1],
                    self._bounds[true][2], self._bounds[false][2]}
    if linewise then
        return utils.round_to_line(unpack(result))
    end
    return unpack(result)
end

--[[
    Delta: a range object
    Params: side (1 or 2)
            augment, stretch, inner (boolean)

    Side: which side of DELTA to use
    If augment, use non-focus side of self. (Else use focus side)
    If stretch, and the inner and outer parts of the used side of delta coincide, then take from
    the other side of delta to try to get inner != outer
    If inner, use inner portions to decide which of delta or self is on the left.

    The resulting focus is on whichever position comes from DELTA. In case this coincides with the
    position from self, prefer whichever side has the focus in self.

    The result textobject is nil, unless outer part of self or delta is furthest left/right, in
    which case it is from self/delta
--]]
function module.range:update(delta, params)
    params = params or {}
    local result = {}

    -- Use focus side iff not params.augment
    local self_side = (params.augment and (3-self.focus.side)) or self.focus.side
    local result = {self:get_side(self_side)}
    local delta_side = params.side
    result[3], result[4] = delta:get_side(delta_side)

    local self_textobject = self.textobject[self_side]
    local delta_textobject = delta.textobject[delta_side]

    if params.stretch then
        local stretch = {delta:get_side(3-delta_side)}
        local textobject = {[2]=delta.textobject[3-delta_side]}
        for i=1,2 do
            if vim.deep_equal(result[3], result[4]) then
                result[4] = stretch[i]
                delta_textobject = textobject[i]
            end
        end
    end

    local focus_side
    local parity = (params.inner and 1) or 2
    if utils.position_less(result[parity], result[parity+2]) then
        focus_side = 2
    elseif utils.position_less(result[parity+2], result[parity]) then
        focus_side = 1
    else
        focus_side = self.focus.side
    end

    -- TODO if result[2] is extreme left or extreme right, then use self_textobject on that side
    -- similarly for result[4]/ delta_textobject
    -- otherwise, textobject is nil
    local textobject
    if focus_side==2 then
        textobject = {self_textobject, delta_textobject}
    else
        textobject = {delta_textobject, self_textobject}
    end

    return self:new({bounds=result,
                     focus={side=focus_side, inner=self.focus.inner},
                     textobject=textobject})
end

function module.compare(params)
    local order
    if params[1] then
        order = params
    else
        if params.inner then
            order = {3,2,4,1}
        else
            order = {4,1,3,2}
        end
        if params.side==1 then
            order[1], order[2] = order[2], order[1]
            order[3], order[4] = order[4], order[3]
        end
    end
    return function (a,b)
        if params.reverse then
            a,b = b,a
        end
        local a = {a:get_all(params.linewise)}
        local b = {b:get_all(params.linewise)}
        for _, idx in ipairs(order) do
            if utils.position_less(a[idx], b[idx]) then
                return true
            elseif utils.position_less(b[idx], a[idx]) then
                return false
            end
        end
        return false
    end
end

function module.sort(ranges, params)
    table.sort(ranges, module.compare(params))
end

module.multirange = {active=1}
local multirange_mt = {__index = module.multirange}

function module.multirange:new(obj)
    obj = obj or {}
    setmetatable(obj, multirange_mt)
    obj.active = (obj.active or self.active)

    return obj
end

function module.multirange:merge(inner, linewise)
    if #self <= 1 then
        return self
    end

    local sorted = self:sorted()
    local result = {}
    local old = sorted[1]
    local new = {bounds={old:get_all()}, textobject={old.textobject[1], old.textobject[2]}}

    -- we use linewise rounding when deciding what to merge, but the merged result is not rounded
    local left, right = old:get_bounds(inner, linewise)
    if linewise or vim.deep_equal(left, right) then
        right = {right[1], right[2]+1}
    end

    for _, range in ipairs(sorted) do
        local new_left, _ = range:get_bounds(inner, linewise)
        if utils.position_less(new_left, right) then
            local right_inner, right_outer = range:get_side()
            if utils.position_less(new.bounds[3], right_inner) then
                new.bounds[3] = right_inner
                new.textobject[2] = range.textobject[2]
            end
            if utils.position_less(new.bounds[4], right_outer) then
                new.bounds[4] = right_outer
            end
        else
            table.insert(result, old:new(new))
            old = range
            new = {bounds={old:get_all()}, textobject={old.textobject[1], old.textobject[2]}}

            left, right = current:get_bounds(inner, linewise)
            if linewise or vim.deep_equal(left, right) then
                right = {right[1], right[2]+1}
            end
        end
    end

    return self:new(result)
end

function module.multirange:sorted(inner, linewise, reverse)
    local sorted = {}
    for k,v in self do sorted[k]=v end
    module.sort(sorted, {inner=inner, linewise=linewise, reverse=reverse})
    return self:new(sorted)
end
