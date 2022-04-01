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
