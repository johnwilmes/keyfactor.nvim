module = {}
-- TODO maybe replace with more general "bindable" so that we can avoid "kf.execute(action,
-- params)" needing to recover context...

local binding = require("keyfactor.binding")

local wring_target = {}
local is_valid_align = {top=true, focus=true, bottom=true}
local is_valid_shape = {larger=true, smaller=true, selection=true, register=true}

-- [[ params: namespace, selection (filled) ]]
local function is_active(params)
    local selection = params.selection
    local target = wring_target[params.namespace]
    return target and (target.after==selection.id)
end

--[[ params: namespace, register, increment ]]
local function get_register(params)
    local target = wring_target[params.namespace]
    if not target then
        return params.register or {}
    end

    local register = vim.deepcopy(params.register or {}) -- new register data to use
    -- validate register and fill by default from target.register
    if not kf.register[register.name] then
        -- TODO we are checking if register.name already exists...
        register.name = target.register.name
    end
    if not is_valid_shape[register.shape] then
        register.shape = target.register.shape
    end
    if not is_valid_align[register.align] then
        register.align = target.register.align
    end
    if not (type(register.depth)=="number" and register.depth >= 0) then
        if register.name==target.register.name then
            register.depth = target.register.depth
        else
            register.depth=0
        end
    end
    if type(register.offset)~="number" then
        if (register.name==target.register.name and
            register.depth==target.register.depth and
            register.align==target.register.align) then
            -- only default to old offset if name/depth/alignment have not changed
            register.offset = target.register.offset
        else
            register.offset=0
        end
    end

    --[[
    if any parameters of register have been set to something different, then don't increment
        (name, align, shape, depth, offset)
        -- TODO could have a force_increment parameter to override?
    otherwise, if params.increment is truthy, increment only depth OR offset,
        dependening on params.increment
    --]]
    if params.increment and vim.deep_equal(register, target.register) then
        local increment = params.increment
        if increment=="align" or increment=="offset" then
            if params.reverse then
                register.offset=register.offset-1
            else
                register.offset=register.offset+1
            end
            -- TODO take register.offset modulo register size
        else
            if params.reverse then
                register.depth=register.depth-1
            else
                register.depth=register.depth+1
            end
            -- TODO get max_depth of register (register.name, maybe also current
            -- scope/buffer/selection can affect register max depth?)
            --
            -- truncate register.depth to range [0, max_depth]
        end
    end
    return register
end

--[[
    actions can be bindable, or table
    if table, can also have named parameter namespace
]]
local function set_wring(capture, params)
    local namespace
    if not require("keyfactor.bind").is_bindable(capture[1]) then
        capture = capture[1]
        namespace=capture.namespace
    end

    local selection = params.selection
    local target = {
        actions=capture,
        params=params,
        register=params.register,
        before=selection.id,
    }
    local result = kf.execute(self.actions, params)
    target.after=selection.id
    wring_target[namespace] = target
    return result
end

--[[
    params:
        increment
        reverse
        register
        namespace
]]
local function do_wring(params)
    local selection = params.selection
    local increment = params.increment

    local target = wring_target[params.namespace]
    if is_active(params) then
        -- default to depth increment, if not set
        local params = vim.tbl_extend("keep", params, {increment="depth"})
        local register = get_register(params)

        if vim.deep_equal(register, target.register) then
            -- TODO flash error message
        else
            -- TODO undo
            kf.undo{selection=target.before}

            for _,action in ipairs(target.actions) do
                kf.execute(action, target.params)
            end
            
            -- record resulting selection id so that wringing remains valid
            target.after = selection.id
            target.register = register
        end
    else
        -- TODO flash message
    end
end

module.is_active = binding.param(is_active, {fill={"selection"}})
module.register = binding.param(get_register)
module.set = binding.capture(set_wring, {fill={"selection", "register"}})

return binding.action(do_wring, {fill={"selection"}, index=module})
