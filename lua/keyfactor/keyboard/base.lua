local module = {}

local keyboard = {}

local mod_state
local layer_state

function module.initialize(params)
    keyboard.layers = {base=0}
    keyboard.max_layer = 0
    mod_state = {}
    layer_state = {base=true}

    if params.layers then
        keyboard.max_layer = #params.layers
        for i,layer in ipairs(params.layers) do
            if layer~='base' then
                keyboard.layers[i] = layer
                layer_state[layer] = false
            end
        end
    end

    if params.mods then
        for i,mod in ipairs(params.mods) do
            keyboard.mods[mod]=i
        end
    else
        all_mods = {shift=1, control=2, alt=3, super=4}
    end

    if params.keys then
        -- TODO validate keys
        keyboard.keys = params.keys
    else
        keyboard.keys = {}
    end

    -- TODO mod decoder
    
    -- TODO map all keys to process_keys
end

function module.set_mods(mods)
    for mod, value in pairs(mods) do
        if keyboard.mods[mod] then
            if value then
                mod_state[mod]=value
            else
                mod_state[mod]=nil
            end
        end
    end
end

function module.get_mods()
    return vim.deepcopy(mod_state)
end

function module.clear_mods()
    mod_state = {}
end

function module.set_layers(layers)
    for layer, enable in pairs(layers) do
        if keyboard.layers[layer] and layers[layer]>0 then
            layer_state[mod]=enable
        end
    end
end

function module.get_layers()
    return vim.deepcopy(layer_state)
end

function module.clear_layers()
    layer_state = {base=true}
end

function module.get_active_map(mode, key)
    for i=keyboard.n_layers,0,-1 do
        layer = all_layers[i]
        if layer_state[layer] then
            -- check if key is present in layer
            -- if it is, return its mappings
        end
    end
    return {}
end

function module.process_keypress(mode, key, mods)
    module.set_mods(mods)
    
    -- look up key/layer/mode combination

    local action = function() end
    local params = {}
    local keep_mods = false
    for _, mapping in ipairs(key layer mode combination) do
        if mods match then
            action = mapping.action or action
            if mapping.defaults then
                params = vim.tbl_extend("force", params, mapping.defaults)
            end
            if mapping.params then
                for key, map in mapping.params do
                    if key=='__ACTION__' then
                        action = map(action, params)
                    else
                        params[key] = map(action, params)
                    end
                end
            end
            if mapping.keep_mods ~= nil then
                keep_mods = mapping.keep_mods
            end
        end
    end

    action(params)

    if keep_mods then
        if type(keep_mods)=='table' then
            local mods = {}
            for _, mod in ipairs(keep_mods) do
                if mod_state[mod] then mods[mod]=true end
            end
            mod_state = mod
        end
        -- else, keep all mods (no op)
    else
        module.clear_mods()
    end
end

    
    





    --[[

    when do mods get cleared? should happen automatically after most actions. maybe add extra
    `keep_mods` field to map calls (in addition to action, defaults, params) indicating which mods
    pass through. Useful primarily for oneshot/lock mod actions, but could also be used for layer
    keys, etc. keep_mods could be a table of mods to pass through, or boolean true



    - set the mods

    - find highest layer with a map for this (base) key in this mode (ignore mods in selecting
    layer!)
    - iterate over all results for this key/layer/mode, and whichever are selected by the current
    mods, apply in order
        - first set action, defaults
        - then call params, and insert result into defaults or replace action
    --]]
end

return module
