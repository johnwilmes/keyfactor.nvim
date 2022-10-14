module = {}
local a = require("keyfactor.actions.base").action
-- NOTE: wrapped actions are expected to respect scope, selection, and register params
-- (wring doesn't really make sense for actions that don't respect these...)
local fill = {"scope", "selection", "register"}


local wring_target = {}

local function is_active(context, namespace)
end

local function get_register(context, namespace)
end

do
    local active_mt = {}

    function active_mt:__call(namespace)
        if type(namespace)=="string" then
            return setmetatable({namespace=namespace}, active_mt)
        elseif type(namespace)=="table" then
            return setmetatable({namespace=namespace.namespace}, active_mt)
        else
            -- TODO log warning
            return setmetatable({namespace=nil}, active_mt)
        end
    end

    function active_mt:__exec(context)
        return is_active(context, self.namespace)
    end

    module.is_active = setmetatable({}, active_mt)
end

do
    local register_mt = {}

    function register_mt:__call(namespace)
        if type(namespace)=="string" then
            return setmetatable({namespace=namespace}, register_mt)
        elseif type(namespace)=="table" then
            return setmetatable({namespace=namespace.namespace}, register_mt)
        else
            -- TODO log warning
            return setmetatable({namespace=nil}, register_mt)
        end
    end

    function register_mt:__exec(context)
        return is_active(context, self.namespace)
    end

    module.register = setmetatable({}, register_mt)
end

do
    local set_mt = {}
    function set_mt:__call(params)
        local selection = params.selection
        local target = {
            actions=self.actions,
            params=params,
            register=params.register,
            before=selection.id,
        }
        kf.execute(self.actions, params)
        target.after=selection.id
        wring_target[self.namespace] = target
    end

    --[[
        actions can be exec'ble, or table
        if table, can also have named parameter namespace
    ]]
    function module.set(actions)
        local obj = {}
        local b = require("keyfactor.bind")
        if b.is_executable(actions) then
            obj.actions={actions}
        elseif type(b)=="table" then
            obj.actions={actions}
            obj.namespace=actions.namespace
        else
            error
        end
        local capture = setmetatable(obj, set_mt)
        return a(capture, fill)
    end
end

--[[
    params:
        increment
        reverse
        register
        namespace
]]

local is_valid_align = {top=true, focus=true, bottom=true}
local is_valid_shape = {larger=true, smaller=true, selection=true, register=true}

local function do_wring(params)
    local selection = params.selection
    local increment = params.increment

    local target = wring_target[params.namespace]
    if target and target.after==selection.id then
        --[[

        if any parameters of register have been set to something different, then don't increment
            (name, align, shape, depth, offset)
            -- TODO could have a force_increment parameter to override?
        otherwise, increment only depth OR offset, dependening on params.increment (or stored
        increment value)
        --]]

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

        if vim.deep_equal(register, target.register) then
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


local wring_action = a(do_wring, fill)

local wring_mt = {}
function wring_mt:__call(params)
    return wring_action(params)
end
function wring_mt:__exec(context)
    return require("keyfactor.bind").execute(wring_action, context)
end
function module.with(_, ...)
    return wring_action:with(...)
end

return setmetatable(module, wring_mt)
