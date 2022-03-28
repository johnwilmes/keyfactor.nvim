--[[ TODO
-- Handle actions that take a parameter afterward? e.g. fFtT or surround
--]]

local utils = require("keyfactor.utils")

local module = {}

module.action = {defaults = {}}

function module.action:new(obj)
    obj = obj or {}
    obj.defaults = vim.tbl_extend("keep", obj.defaults or {}, self.defaults)
    setmetatable(obj, self)
    self.__index = self
    self.__call = self.__call -- HACK: make metatable work for "subclasses"
    return obj
end

function module.action:_get_params(params)
    params = vim.tbl_extend("keep", params, self.defaults)
    params.count = params.count or vim.v.count
    params.register = params.register or vim.v.register
    params.cursor = params.cursor or vim.api.nvim_win_get_cursor(0)
    if self._parse_argument then
        params.argument = params.argument or self:_parse_argument(params)
    end
    return params
end

function module.action:__call(params)
    params = self:_get_params(params)

    if self:_exec(params) then
        -- TODO update state?
    end
end

function module.action:_exec(params)
    error("Not implemented: action:exec")
end

module.state = {}

module.state.__index = function(t, i)
    return 
end

function state:set_motion(motion)
    -- TODO
end

function state:add_jump(context, pos)
--[[ Added by the jumps motion ]]
end

function state:set_seek(motion)
--[[ Added by the seek motion ]]
end

return state
