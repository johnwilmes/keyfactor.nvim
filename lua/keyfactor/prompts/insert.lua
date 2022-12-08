local oo = require("loop.simple")
local function super(obj) return oo.getsuper(oo.getclass(obj)) end

local base = require("keyfactor.modes.base")

local module = {}

function module.InsertMode:__init(opts)
    self._reinsert = opts.reinsert
end

function module.InsertMode:attach()
    if self._reinsert then
        local reinsertion = --TODO
        self.model:attach(reinsertion) -- TODO attach reinsertion controller
    end

    kf.push_mode(self.frame, {
        -- focus, scroll should be preserved
        name="Insert",
        model=self.model,
        layers="insert", -- TODO
    })
end

