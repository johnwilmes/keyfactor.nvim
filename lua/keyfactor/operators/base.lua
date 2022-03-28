local kf = require("keyfactor.base")
local motion = require("keyfactor.motion")

local module = {}

-- Would be nice if NVIM api exposed a nicer way to do this. (Or if &opfunc could be a function
-- instead of a string!)
-- TODO when script-local stuff works better, use s: instead of Keyfactor prefix
-- KeyfactorOperator is needed because vim operatorfunc must be a string function name
vim.cmd([[
function! KeyfactorOperator(motion_type)
    return v:lua.require'keyfactor.operators'._opfunc(a:motion_type)
endfunction
]])

-- Should this be per-window/buffer? I'm not sure if there is any way to switch windows/buffers
-- that doesn't exit op-pending mode
local active_operator
-- I don't think this needs to be per-window/buffer, because _register_motion is only called by motions
-- while in op-pending mode, and when that call terminates the opfunc is immediately called to
-- restore it
local prev_visual
local active_motion

function module._register_motion(motion, params)
    if active_operator and utils.mode_in('o') then
        active_motion = {motion, params}
        prev_visual = {vim.api.nvim_buf_get_mark(0, '<'), vim.api.nvim_buf_get_mark(0, '>')}
    end
end

function module._opfunc(motion_type)
    local operator, params = unpack(active_operator)
    params.left = vim.api.nvim_buf_get_mark(0, '[')
    params.right = vim.api.nvim_buf_get_mark(0, ']')
    params.motion_type = motion.motion_type.from_string(motion_type)
    if active_motion then
        params.motion = active_motion
        active_motion = nil
    end

    if prev_visual then
        local prev_start, prev_end = unpack(prev_visual)
        nvim_buf_set_mark(0, '<', prev_start[0], prev_start[1], {})
        nvim_buf_set_mark(0, '>', prev_end[0], prev_end[1], {})
        prev_visual = nil
    end

    operator:_apply(params)
    active_operator = nil
end


module.operator = kf.action:new()

-- TODO when the operator is actually applied, set state.repeat
function module.operator:_exec(params)
    if utils.mode_in('xn') then
        if utils.mode_in('x') then
            params.left = vim.api.nvim_buf_get_mark(params.buffer, '<')
            params.right = vim.api.nvim_buf_get_mark(params.buffer, '>')
            params.motion_type = motion.motion_type.from_mode()
            self:_apply(params)
            -- also exit visual mode?
            -- return true?
        else -- utils.mode_in('n')
            if params.left and params.left and params.motion_type then
                self:_apply(params)
            elseif params.motion then
                local motion, motion_params = unpack(motion)

                if params.count > 0 then
                    -- TODO decide if count should be applied to motion
                end
                params.left, params.right = motion:range(motion_params)
                params.motion_type = motion.motion_type
                self:_apply(params)
            else
                vim.opt.operatorfunc = "KeyfactorOperator"
                active_operator = {self, params}
                vim.api.nvim_feedkeys("g@", "ni", false)
            end
        end
        return true
    else -- operators only work when mode=x or mode=n
        return false
    end
end

function module.operator:_apply(params)
    self:apply(params)
    --TODO set repeat info, etc.
end

function module.operator:apply(params)
    --[[ just do whatever to params.left, params.right, params.motion_type ]]
    error("Not implemented")
end

module.vim_operator = module.operator:new()

function module.vim_operator:apply(params)
    local command

    for _, variant in ipairs(self:variants) do
        if type(variant.selector) == 'string' and params[variant.selector] then
            command = variant.command
        elseif type(variant.selector) == 'table' then
            local selected = true
            for _, selector in ipairs(variant.selector) do
                if not params[selector] then
                    selected = false
                    break
                end
            end
            if selected then
                command = variant.command
            end
        else
            error('Invalid variant specification')
        end
    end

    if not command then
        return false
    end

    utils.exit_visual()

    -- TODO count and register
    local count = false
    local register = false
    
    utils.operate(command, params.left, params.right, params.motion_type, count, register)
end

-- later listed versions have priority over earlier ones when multiple match. E.g. reverse and
-- alternate are both set below, then use alternate
local indent = {variants = {
    {selector={}, command='>'},
    {selector='reverse', command='<'},
    {selector='alternate', command='='},
    --{selector={'reverse', 'alternate'}, command='='} -- implicit
}}
module.indent = module.vim_operator:new(indent)
