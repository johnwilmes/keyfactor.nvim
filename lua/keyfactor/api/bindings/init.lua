local utils = require("keyfactor.utils")

local module = utils.lazy_import{
    action = "keyfactor.bindings.base",
    is_bindable = "keyfactor.bindings.base",
    bind = "keyfactor.bindings.base",
    map = "keyfactor.bindings.base",
    resolve_map = "keyfactor.bindings.base",
    outer = "keyfactor.bindings.base",

    on = "keyfactor.bindings.conditional",
    on_not = "keyfactor.bindings.conditional",

}

return module
