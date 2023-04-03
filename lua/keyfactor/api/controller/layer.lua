local module = {}


module.LayerController = utils.class()

--[[

    if valid is list, then it is taken as list of layers that may be set to true (or false)

    otherwise, valid is interpreted as table with layer name keys and boolean values. in this case,
    true means the layer MUST be true, and false means the layer MUST be false
--]]
local function get_validator(valid)
    if vim.tbl_islist(valid) then
        local permitted = utils.list.to_flags(valid)
        return function(l,s) return (not s) or permitted[l] end
    end

    return function(l,s)
        local v = valid[l]
        return (v==nil) or (not s == not v)
    end
end

--[[

groups: list of initial groups
layers: list of initial layers

valid_layers: layer validator (function or list of valid or table of required/forbidden)
valid_groups: group validator (same)

--]]
function module.LayerController:__init(opts)
    -- TODO validate layers: keys must be valid layer names
    -- TODO validate groups: keys must be valid group names
    
    if utils.is_callable(opts.valid_layers) then
        self._is_valid_layer = opts.valid_layers
    elseif type(opts.valid_layers)=="table" then
        self._is_valid_layer = get_validator(opts.valid_layers)
    else
        self._is_valid_layer = function() return true end
    end

    if utils.is_callable(opts.valid_groups) then
        self._is_valid_group = opts.valid_groups
    elseif type(opts.valid_groups)=="table" then
        self._is_valid_group = get_validator(opts.valid_groups)
    else
        self._is_valid_group = function() return true end
    end

    self._layers = utils.table.filter(self._is_valid_layer, kf.layers.get())
    self._raw = utils.table.filter(self._is_valid_layer, kf.layers.get(true))
    self._groups = utils.table.filter(self._is_valid_group, kf.layers.get_groups())

    if opts.groups then
        if not self:set(opts.groups) then
            error("initial groups are invalid")
        end
    end

    if opts.layers then
        if not self:set(opts.layers) then
            error("initial layers are invalid")
        end
    end
end

--[[
    ignore_groups (boolean) - if true, then give all active layers, even those in inactive groups

    otherwise (default, false), then layer is true if active in raw, and also at least one of its
    groups is active
--]]
function module.LayerController:get(ignore_groups)
    if ignore_groups then
        return vim.deepcopy(self._raw)
    else
        return vim.deepcopy(self._layers)
    end
end

function module.LayerContoller:set(layers)
    if not utils.table.all(layers, self._is_valid_layer) then
        return false
    end

    for layer, state in pairs(layers) do
        if state then
            if not self._raw[layer] then
                self._raw[layer]=true
                local groups = kf.layers.get_groups(layer)
                if #groups==0 or utils.table.any(groups, function(_,g) return self._groups[g] end) then
                    self._layers[layer]=true
                end
            end
        else
            self._raw[layer]=nil
            self._layers=nil
        end
    end
    return true
end

function module.LayerController:get_groups()
    return vim.deepcopy(self._groups)
end

function module.LayerController:set_groups(groups)
    if not utils.table.all(groups, self._is_valid_group) then
        return false
    end

    for group, state in pairs(groups) do
        self._groups[group] = (not not state) or nil
    end

    self._layers={}
    for layer,_ in pairs(self._raw) do
        if utils.table.any(kf.layers.get_groups(layer), function(_,g) return self._groups[g] end) then
            self._layers[layer]=true
        end
    end
    return true
end
