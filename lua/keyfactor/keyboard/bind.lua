local module = {}

local function wrap(action, params)
    params = vim.deepcopy(params or {})
    params.count = params.count or vim.v.count
    params.window = params.window or 0
    params.buffer = vim.api.nvim_win_get_buf(params.window)
    params.cursor = params.cursor or vim.api.nvim_win_get_cursor(params.window)
    -- TODO params.prehook?
    if action(params) then
        -- TODO update state, remember action
        -- TODO params.posthook?
    end
end


--[[


map(trigger, result, mods) 

map(k.word, {defaults={textobject=textobjects.word}}, selection_map)



Things we might want to do that are currently inconvenient:
    - extend or modify a table parameter, rather than replacing it
        (e.g., list of layers to enable...?)

    - wrap an action, or perform an action before/after, rather than replacing it






mods table:
    [nil] is always selected
    oneshots can be pressed in any order

selection_mods = {
    ([1]=) {mods={},
            action=require("keyfactor.actions.selection").select_next,
            defaults={inner=true, stretch=true},
            --params={}
            },
    ([2]=) {mods={shift=true}, -- alias shift={shift=true} so you can do trigger=shift
            defaults={reverse=true}},
           {mods={control=true},
            defaults={augment=true}},
           {mods={alt=true},
            defaults={exterior=true}},
           {mods={[oneshot(k.choose)]
    shift={defaults={reverse=true}},
    control={defaults={augment=true}},
    alt={defaults={exterior=true}},
    [oneshot(k.choose)] = {action=require("keyfactor.actions.choose_selection").auto_choose},
}

bind(k.word, 









mod group {
    defaults = {....}
    shift -> reverse
    ctrl -> exterior
    alt -> outer
    (one-shot) leader(k.choose) -> {defaults = {choose}, shift -> reverse, ctrl-> exterior, ...}
    (one-shot) leader(ctrl(k.choose)) -> multiple
} motion mod group

bind ( k.visual, action= toggle `replace` in (motion mod group).defaults)

bind (alt(k.visual), action= action



bind(
{
    {trigger = {key='a'}, action=motions.word_part, params = {reverse = false, near = false, textobject = false, outer = false}}
    {trigger = {shift = true}, params = {reverse = true}},
    {trigger = {ctrl = true}, params = {near = true}},
    {trigger = {alt = true}, params = {outer = true}},
    {trigger = {mode='x'}, params = {near = true, textobject = true}},
    {trigger = {mode='x', ctrl = true}, params = {near = false, textobject = true}},
}

shift


{
    shift -> reverse=true
    ctrl -> exterior=true
    alt -> inner=true

    choose key -> set selector... as one-shot



    select key -> set replace=true
    shift(select key) -> set augment=true

    ctrl(select key) -> set all=true as one-shot

    alt(select key) -> rotate selection


    collapse selection...?
}




]]
