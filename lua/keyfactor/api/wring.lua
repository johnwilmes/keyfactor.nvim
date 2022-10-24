local module= {}

local wring_state = {} -- by buffer

local function get_wring_state(window, buffer)
    local state = wring_state[buffer]
    if state then return vim.deepcopy(state) end
end

local function set_wring(selection, origin, action, params, default_map)
    wring_state[selection.buffer] = {
        selection=selection.id,
        origin=origin,
        action=action,
        params=params,
        default_map=default_map
    }
end

local function wring(selection, map)
    local state = get_wring_state(selection.buffer)
    if not state or state.selection~=selection.id then
        return nil
    end
    local map = map or state.default_map
    local success, new_params = map(state.params)
    if success then
        selection = kf.undo{selection=state.origin}
        selection = state.action(selection, new_params)
        set_wring(selection, state.origin, state.action, new_params, state.default_map)
        return success
    end
    return false
end

return module
