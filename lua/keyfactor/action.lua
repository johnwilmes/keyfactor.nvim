local oo = require("loop.simple")
local utils = require("keyfactor.utils")
local state = require("keyfactor.state")

local Action = oo.class()

function Action:__call(options)
    state.update({action=self})
    self:exec(options)
end

    --[[
function Action:exec(options, context)
    if context == nil then
        context = self.context.get()
end
    ]]

return Action
