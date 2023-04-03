local utils = require("keyfactor.utils")
local kf = require("keyfactor.api")

local Edit = utils.class()

--[[

    opts
        target: options for target initialization
            requires target.buffer
        layers: options for layer initialization (optional)
        view: options for view initialization (optional)
]]
function Edit:__init(opts)
    -- TODO validate opts?
    opts = opts or {}
    
    if not opts.target then
        error("no target specified")
    end
    local buffer, is_valid = kf.get_buffer(opts.target.buffer)
    if not is_valid then
        error("invalid initial buffer")
    end

    self.target = kf.controller.Target(opts.target)

    local layer_init = opts.layers
    if not layer_init then
        layer_init = {
            groups={"normal"}, -- TODO this is the initial group setting
                -- TODO all groups should be valid by default
        }
    end

    self.layers = kf.controller.Layers(layer_init)

    self.view = kf.view.Target(vim.tbl_extend("force", opts.view or {}, {target=self.target}))

    -- self.status = ... stuff that a status view, managed by Page, could read and incorporate...
end

local module = {Edit = Edit}
return module
