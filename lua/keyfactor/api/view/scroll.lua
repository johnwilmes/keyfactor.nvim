local function scroll(view, index, action)
    local callable
    local arg
    if type(action)=="string" then
        -- action assumed to be normal mode command
        callable = vim.cmd
        arg = "normal! "..vim.api.nvim_replace_termcodes(action, true, true, true)
    elseif utils.is_callable(action) then
        callable = action
        arg = nil
    else
        error("invalid scroll action")
    end

    local wm = kf.get_window_manager()
    local window = wm:get_window(view, index)
    if not window then
        -- TODO log message, can't scroll without window
        return
    end

    local saveview
    vim.api.nvim_win_call(window, function()
        -- we are just assuming that the view is rendered properly in the window
        callable(arg)
        saveview = vim.fn.winsaveview()
    end)

    view:set{[index]={view=saveview}}
end

return {scroll=scroll}
